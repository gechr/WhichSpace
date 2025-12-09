import Cocoa

/// A confirmation alert for destructive or important actions
struct ConfirmationAlert {
    let message: String
    let detail: String
    let confirmTitle: String
    let isDestructive: Bool

    init(message: String, detail: String, confirmTitle: String = "Reset", isDestructive: Bool = true) {
        self.message = message
        self.detail = detail
        self.confirmTitle = confirmTitle
        self.isDestructive = isDestructive
    }

    /// Shows the alert and returns true if the user confirmed
    func runModal() -> Bool {
        NSApp.activate(ignoringOtherApps: true)

        let alert = NSAlert()
        alert.messageText = message
        alert.informativeText = detail
        alert.alertStyle = .warning

        if let appIcon = NSApp.applicationIconImage {
            let smallIcon = NSImage(size: NSSize(width: 32, height: 32))
            smallIcon.lockFocus()
            appIcon.draw(in: NSRect(x: 0, y: 0, width: 32, height: 32))
            smallIcon.unlockFocus()
            alert.icon = smallIcon
        }

        alert.addButton(withTitle: confirmTitle)
        alert.addButton(withTitle: Localization.buttonCancel)
        if isDestructive {
            alert.buttons[0].hasDestructiveAction = true
            alert.buttons[0].keyEquivalent = ""
            alert.buttons[1].keyEquivalent = "\r"
        }

        return alert.runModal() == .alertFirstButtonReturn
    }
}
