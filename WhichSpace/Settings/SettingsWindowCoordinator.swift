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

/// A settings model with an external-change observation stream scoped to the
/// window's lifetime.
@MainActor
protocol SettingsObservingModel: AnyObject {
    func startObserving()
    func stopObserving()
}

extension SettingsModel: SettingsObservingModel {}
extension SpaceEditorModel: SettingsObservingModel {}

/// Owns the single settings window. Holding one controller instance is
/// load-bearing: creating a controller per show() produces duplicate windows.
@MainActor
final class SettingsWindowCoordinator {
    private let models: [SettingsObservingModel]
    private let panes: [SettingsPane]
    private var windowController: SettingsWindowController?
    private var closeObserver: NSObjectProtocol?

    init(models: [SettingsObservingModel], panes: [SettingsPane]) {
        self.models = models
        self.panes = panes
    }

    /// Shows and fronts the settings window, creating it on first use.
    /// `orderFrontRegardless` + `activate` is what reliably fronts a window
    /// from an accessory (LSUIElement) app.
    func show() {
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
                        ColorPanelCoordinator.closeSharedPanel()
                    }
                }
            }
        }
        for model in models {
            model.startObserving()
        }
        windowController?.show()
        if isFirstShow, let window = windowController?.window {
            positionAboveCenter(window)
        }
        windowController?.window?.orderFrontRegardless()
        NSApp.activate(ignoringOtherApps: true)
        // Drop the automatic focus on the first control so the window opens
        // without a highlighted toggle; Tab still reaches every control
        windowController?.window?.makeFirstResponder(nil)
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
