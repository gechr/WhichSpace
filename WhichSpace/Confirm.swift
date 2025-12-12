import Cocoa

extension NSAlert {
    /// Configures the alert with a scaled-down app icon (32x32)
    func useSmallAppIcon() {
        if let appIcon = NSApp.applicationIconImage {
            let smallIcon = NSImage(size: NSSize(width: 32, height: 32))
            smallIcon.lockFocus()
            appIcon.draw(in: NSRect(x: 0, y: 0, width: 32, height: 32))
            smallIcon.unlockFocus()
            icon = smallIcon
        }
    }
}

/// An informational alert with a primary action and dismiss button
struct InfoAlert {
    let message: String
    let detail: String
    let primaryButtonTitle: String
    let dismissButtonTitle: String
    let icon: NSImage?

    init(
        message: String,
        detail: String,
        primaryButtonTitle: String,
        dismissButtonTitle: String = Localization.buttonOK,
        icon: NSImage? = nil
    ) {
        self.message = message
        self.detail = detail
        self.primaryButtonTitle = primaryButtonTitle
        self.dismissButtonTitle = dismissButtonTitle
        self.icon = icon
    }

    /// Shows the alert and returns true if the user clicked the primary button
    func runModal() -> Bool {
        NSApp.activate(ignoringOtherApps: true)

        let alert = NSAlert()
        alert.messageText = message
        alert.informativeText = detail
        alert.alertStyle = .informational
        if let icon {
            alert.icon = icon
        } else {
            alert.useSmallAppIcon()
        }
        alert.addButton(withTitle: primaryButtonTitle)
        alert.addButton(withTitle: dismissButtonTitle)

        return alert.runModal() == .alertFirstButtonReturn
    }
}

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
        alert.useSmallAppIcon()
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
