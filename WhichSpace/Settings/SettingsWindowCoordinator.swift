import AppKit
import Settings

extension Settings.PaneIdentifier {
    /// Computed because `PaneIdentifier` is not Sendable, so a stored static
    /// is rejected under strict concurrency
    static var general: Self {
        Self("general")
    }
}

/// Owns the single settings window. Holding one controller instance is
/// load-bearing: creating a controller per show() produces duplicate windows.
@MainActor
final class SettingsWindowCoordinator {
    private let model: SettingsModel
    private let panes: [SettingsPane]
    private var windowController: SettingsWindowController?
    private var closeObserver: NSObjectProtocol?

    init(model: SettingsModel, panes: [SettingsPane]) {
        self.model = model
        self.panes = panes
    }

    /// Shows and fronts the settings window, creating it on first use.
    /// `orderFrontRegardless` + `activate` is what reliably fronts a window
    /// from an accessory (LSUIElement) app.
    func show() {
        if windowController == nil {
            let controller = SettingsWindowController(
                panes: panes,
                style: .toolbarItems,
                animated: true,
                hidesToolbarForSingleItem: true
            )
            windowController = controller
            if let window = controller.window {
                // The external-change observation stream only needs to run
                // while the window can show its effects
                closeObserver = NotificationCenter.default.addObserver(
                    forName: NSWindow.willCloseNotification,
                    object: window,
                    queue: .main
                ) { [weak model] _ in
                    Task { @MainActor in
                        model?.stopObserving()
                    }
                }
            }
        }
        model.startObserving()
        windowController?.show()
        windowController?.window?.orderFrontRegardless()
        NSApp.activate(ignoringOtherApps: true)
        // Drop the automatic focus on the first control so the window opens
        // without a highlighted toggle; Tab still reaches every control
        windowController?.window?.makeFirstResponder(nil)
    }
}
