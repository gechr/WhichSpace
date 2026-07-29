import AppKit

/// Presents the shared `NSColorPanel` for custom colors in the settings
/// window, forwarding continuous changes to the edited Space. The panes'
/// swatch rows only carry presets, so anything else routes through here.
@MainActor
final class ColorPanelCoordinator: NSObject {
    private var onColorChanged: ((NSColor) -> Void)?

    func show(currentColor: NSColor, onChange: @escaping (NSColor) -> Void) {
        onColorChanged = onChange

        let colorPanel = NSColorPanel.shared
        colorPanel.setTarget(self)
        colorPanel.setAction(#selector(colorChanged(_:)))
        colorPanel.isContinuous = true
        colorPanel.color = currentColor
        colorPanel.makeKeyAndOrderFront(nil)
    }

    @objc private func colorChanged(_ sender: NSColorPanel) {
        onColorChanged?(sender.color)
    }

    /// Closes the shared panel; called when the settings window closes so it
    /// cannot outlive the selection it was editing.
    static func closeSharedPanel() {
        if NSColorPanel.sharedColorPanelExists {
            NSColorPanel.shared.orderOut(nil)
        }
    }
}
