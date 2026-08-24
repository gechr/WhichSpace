import AppKit
import KeyboardShortcuts
import Settings

extension Settings.PaneIdentifier {
    /// Computed because `PaneIdentifier` is not Sendable, so a stored static
    /// is rejected under strict concurrency
    static var general: Self {
        Self("general")
    }

    static var menuBar: Self {
        Self("menuBar")
    }

    static var spaces: Self {
        Self("spaces")
    }

    static var mouse: Self {
        Self("mouse")
    }

    static var keyboard: Self {
        Self("keyboard")
    }
}

extension SettingsPaneID {
    /// The Settings package identifier the deep-link pane name maps to.
    var identifier: Settings.PaneIdentifier {
        switch self {
        case .general:
            .general
        case .menuBar:
            .menuBar
        case .spaces:
            .spaces
        case .mouse:
            .mouse
        case .keyboard:
            .keyboard
        }
    }

    /// The pane a Settings package identifier names, for reading a pane back
    /// out of the toolbar order.
    init?(identifier: Settings.PaneIdentifier) {
        guard let pane = Self.allCases.first(where: { $0.identifier == identifier }) else {
            return nil
        }
        self = pane
    }
}

/// A settings model with an external-change observation stream scoped to the
/// window's lifetime.
@MainActor
protocol SettingsObservingModel: AnyObject {
    func startObserving()
    func stopObserving()
    /// Called when the window comes on screen after being closed, before
    /// the panes render, so a model can reorient around the current state.
    func prepareForShow()
}

extension SettingsObservingModel {
    func prepareForShow() {}
}

extension SettingsModel: SettingsObservingModel {}
extension SpaceEditorModel: SettingsObservingModel {}

/// Owns the single settings window. Holding one controller instance is
/// load-bearing: creating a controller per show() produces duplicate windows.
@MainActor
final class SettingsWindowCoordinator {
    private let models: [SettingsObservingModel]
    private let panes: [SettingsPane]
    private let highlighter: SettingsHighlighter
    private var windowController: SettingsWindowController?
    private var closeObserver: NSObjectProtocol?
    private var shortcutMonitor: Any?
    private var titleObservation: NSKeyValueObservation?
    private var search: SettingsSearchController?

    /// Margin past the package's 0.25 s tab crossfade before repairing.
    private static let transitionSettleDelay: Duration = .milliseconds(400)

    init(models: [SettingsObservingModel], panes: [SettingsPane], highlighter: SettingsHighlighter) {
        self.models = models
        self.panes = panes
        self.highlighter = highlighter
    }

    /// Shows and fronts the settings window, creating it on first use.
    /// `orderFrontRegardless` + `activate` is what reliably fronts a window
    /// from an accessory (LSUIElement) app.
    ///
    /// A nil pane leaves whichever pane was last shown selected. A focus
    /// brings one row into view, for links that point at a single setting,
    /// and briefly highlights it when the link asked for emphasis.
    func show(pane: SettingsPaneID? = nil, focus: SettingsFocus? = nil) {
        let wasVisible = windowController?.window?.isVisible ?? false
        // SettingsWindowController.show() restores its autosaved frame every
        // time, even when a deep link is only switching the pane of an
        // already-visible window. Preserve the live top-left corner so that
        // programmatic navigation does not undo the user's latest drag.
        let visibleTopLeft = windowController?.window.flatMap { window in
            wasVisible ? NSPoint(x: window.frame.minX, y: window.frame.maxY) : nil
        }
        if windowController == nil {
            let controller = SettingsWindowController(
                panes: panes,
                style: .toolbarItems,
                animated: true,
                hidesToolbarForSingleItem: true
            )
            windowController = controller
            if let window = controller.window {
                window.autorecalculatesKeyViewLoop = true
                attachSearch(to: window)
                observeWindowShortcuts(in: window)
                // The external-change observation streams only need to run
                // while the window can show their effects; the shared color
                // panel must not outlive the selection it edits
                closeObserver = NotificationCenter.default.addObserver(
                    forName: NSWindow.willCloseNotification,
                    object: window,
                    queue: .main
                ) { [weak self] _ in
                    Task { @MainActor in
                        for model in self?.models ?? [] {
                            model.stopObserving()
                        }
                        self?.search?.reset()
                        ColorPanelCoordinator.closeSharedPanel()
                    }
                }
                // The window is retitled on every tab activation, including
                // toolbar clicks this coordinator never sees; an interrupted
                // crossfade can strand the incoming pane half-faded, so each
                // switch schedules a repair for after the transition
                titleObservation = window.observe(\.title) { [weak self] window, _ in
                    // The title is set from the tab activation, on the main
                    // thread, and KVO delivers on the thread that set it, so
                    // the name is replaced before the bar is drawn
                    let retitled = MainActor.assumeIsolated {
                        Self.restoreAppTitle(in: window)
                    }
                    // The remaining change is the replacement above
                    guard retitled else {
                        return
                    }
                    Task { @MainActor in
                        try? await Task.sleep(for: Self.transitionSettleDelay)
                        self?.restorePaneVisibility()
                    }
                }
            }
        }
        for model in models {
            model.startObserving()
        }
        if !wasVisible {
            for model in models {
                model.prepareForShow()
            }
        }
        if ProcessInfo.processInfo.operatingSystemVersion.majorVersion >= 27 {
            windowController?.window?.collectionBehavior.insert(.moveToActiveSpace)
        }
        windowController?.show(pane: pane?.identifier)
        fitWindowToPane()
        restorePaneVisibility()
        if let visibleTopLeft, let window = windowController?.window {
            window.setFrameOrigin(NSPoint(
                x: visibleTopLeft.x,
                y: visibleTopLeft.y - window.frame.height
            ))
        }
        windowController?.window?.orderFrontRegardless()
        NSApp.activate(ignoringOtherApps: true)
        // Drop the automatic focus on the first control so the window opens
        // without a highlighted toggle; Tab still reaches every control
        windowController?.window?.makeFirstResponder(nil)
        // Set last so the fade runs against a pane that is already on screen
        highlighter.point(at: focus)
    }

    /// Puts the app's name in the title bar, reporting whether a pane name was
    /// there to replace.
    ///
    /// The window is titled after the pane it shows, which the selected
    /// toolbar item below already names, so the bar carries the app the window
    /// belongs to instead.
    @MainActor
    private static func restoreAppTitle(in window: NSWindow) -> Bool {
        guard window.title != AppInfo.appName else {
            return false
        }
        window.title = AppInfo.appName
        return true
    }

    /// Sizes the window around the pane just put on screen, in the same pass
    /// that showed it so the corrected size is the first one drawn.
    ///
    /// A pane is measured for the window before it is on screen, where an
    /// AppKit-backed control has yet to take the control size the pane sets
    /// and answers with its default instead: the General pane's mini switches
    /// report a taller row each, leaving a band of empty window below the
    /// content. The window is then resized only for an animated tab switch,
    /// which a toolbar click gets and a deep link or a search hit does not, so
    /// a pane reached by either keeps whichever height the previous pane had.
    /// Both readings settle once the pane is in the window, so measure again
    /// from here.
    private func fitWindowToPane() {
        guard let window = windowController?.window,
              // A crossfade adds the incoming pane before dropping the
              // outgoing one, so the pane being shown is the last subview
              let pane = window.contentViewController?.view.subviews.last
        else {
            return
        }
        fitSettingsWindow(window, to: pane)
    }

    /// An animated toolbar switch crossfades the outgoing pane's view to
    /// alpha 0 and AppKit never restores it; the programmatic switch back is
    /// not animated, so the view would come back invisible while the window
    /// keeps its old frame. Restoring alpha after every programmatic switch
    /// makes the two paths composable in any order.
    private func restorePaneVisibility() {
        guard let container = windowController?.window?.contentViewController?.view else {
            return
        }
        for subview in container.subviews where subview.alphaValue < 1 {
            subview.alphaValue = 1
        }
    }

    /// Handles the window's own key equivalents: Command-W and Command-Q to
    /// close, and Command-digit to select a pane. The hidden main menu carries
    /// no items for any of them because the empty Settings scene removes its
    /// commands, so all three need explicit handling.
    private func observeWindowShortcuts(in window: NSWindow) {
        shortcutMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self, weak window] event in
            guard let window, event.window === window else {
                return event
            }
            if Self.isCloseShortcut(event) {
                window.performClose(nil)
                return nil
            }
            if let index = Self.paneShortcutIndex(event),
               !Self.isRecordingShortcut(in: window),
               self?.selectPane(at: index) == true
            {
                return nil
            }
            return event
        }
    }

    /// Command-W or Command-Q, with no other modifier along for the ride.
    private static func isCloseShortcut(_ event: NSEvent) -> Bool {
        guard event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command,
              let key = event.charactersIgnoringModifiers?.lowercased()
        else {
            return false
        }
        return key == "w" || key == "q"
    }

    /// The toolbar position a Command-digit selects, counting from the left.
    /// Command-1 through Command-9 read as positions the way they do in System
    /// Settings and a tabbed window.
    private static func paneShortcutIndex(_ event: NSEvent) -> Int? {
        guard event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command,
              let key = event.charactersIgnoringModifiers,
              let digit = Int(key), (1 ... 9).contains(digit)
        else {
            return nil
        }
        return digit - 1
    }

    /// Whether a shortcut recorder holds the focus. It takes every key it is
    /// sent as part of the shortcut being recorded, so Command-digit belongs to
    /// it rather than to the toolbar.
    private static func isRecordingShortcut(in window: NSWindow) -> Bool {
        // A field being edited answers as its field editor, which sits inside
        // the recorder rather than being it
        var view = window.firstResponder as? NSView
        while let candidate = view {
            if candidate is KeyboardShortcuts.RecorderCocoa {
                return true
            }
            view = candidate.superview
        }
        return false
    }

    /// Shows the pane in `index`'s toolbar position, reporting whether there
    /// was one. Routed through `show` so a keyboard switch preserves the
    /// window's corner, refits it, and repairs pane visibility exactly as a
    /// deep link does.
    private func selectPane(at index: Int) -> Bool {
        guard index < panes.count,
              let pane = SettingsPaneID(identifier: panes[index].paneIdentifier)
        else {
            return false
        }
        show(pane: pane)
        return true
    }

    /// Wires up the toolbar's search field. A hit goes back through `show`,
    /// the same path a `whichspace://settings` link takes, so a searched
    /// setting lands and lights up exactly like a linked one.
    private func attachSearch(to window: NSWindow) {
        let search = SettingsSearchController { [weak self] entry in
            self?.show(pane: entry.pane, focus: .highlight(entry.anchor))
        }
        search.attach(to: window)
        self.search = search
    }
}
