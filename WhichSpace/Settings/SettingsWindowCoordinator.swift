import AppKit
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

    static var switching: Self {
        Self("switching")
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
        case .switching:
            .switching
        }
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
    private var search: SettingsSearchController?

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
        var isFirstShow = false
        if windowController == nil {
            isFirstShow = true
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
        windowController?.show(pane: pane?.identifier)
        if isFirstShow, let window = windowController?.window {
            positionAboveCenter(window)
        }
        windowController?.window?.orderFrontRegardless()
        NSApp.activate(ignoringOtherApps: true)
        // Drop the automatic focus on the first control so the window opens
        // without a highlighted toggle; Tab still reaches every control
        windowController?.window?.makeFirstResponder(nil)
        // Set last so the fade runs against a pane that is already on screen
        highlighter.point(at: focus)
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

    /// Opens the window above screen center so taller panes, which grow
    /// downward from a fixed top edge when switching tabs, stay on screen.
    /// First show only - later shows respect wherever the user moved it.
    private func positionAboveCenter(_ window: NSWindow) {
        guard let screen = window.screen ?? NSScreen.main else {
            return
        }
        let visible = screen.visibleFrame
        let frame = window.frame
        let slack = max(0, visible.height - frame.height)
        let topMargin = min(slack * 0.25, 64)
        let origin = NSPoint(
            x: visible.midX - frame.width / 2,
            y: visible.maxY - topMargin - frame.height
        )
        window.setFrameOrigin(origin)
    }
}
