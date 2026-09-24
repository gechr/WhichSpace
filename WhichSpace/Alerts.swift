import Cocoa

private func runAlertOnMain<T: Sendable>(_ work: @MainActor () -> T) -> T {
    if Thread.isMainThread {
        return MainActor.assumeIsolated(work)
    }
    return DispatchQueue.main.sync {
        MainActor.assumeIsolated(work)
    }
}

extension NSAlert {
    /// Configures the alert with a scaled-down app icon (32x32)
    func useSmallAppIcon() {
        if let appIcon = NSApp.applicationIconImage {
            let smallIcon = NSImage(size: NSSize(width: 32, height: 32), flipped: false) { rect in
                appIcon.draw(in: rect)
                return true
            }
            icon = smallIcon
        }
    }

    /// Runs the alert modally with the app active. An accessory app with
    /// nothing on screen can be refused activation, leaving the alert
    /// inactive, so the request repeats once the alert is showing.
    ///
    /// The repeat is a timer in the modal panel mode, which fires inside the
    /// alert's session whichever run loop source or queue started it. The
    /// main queue does not drain there when the alert runs from a main-queue
    /// block, so a queued block would fire after the alert closed.
    @discardableResult
    func runActivatedModal() -> NSApplication.ModalResponse {
        NSApp.activate(ignoringOtherApps: true)
        let windowID = ObjectIdentifier(window)
        let retry = Timer(timeInterval: 0, repeats: false) { _ in
            MainActor.assumeIsolated {
                guard let modalWindow = NSApp.modalWindow, ObjectIdentifier(modalWindow) == windowID else {
                    return
                }
                NSApp.activate(ignoringOtherApps: true)
            }
        }
        RunLoop.main.add(retry, forMode: .modalPanel)
        defer { retry.invalidate() }
        return runModal()
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
        runAlertOnMain {
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

            return alert.runActivatedModal() == .alertFirstButtonReturn
        }
    }
}

enum SpaceSwipeGestureAlertResponse: Sendable {
    case enableInstantSwitching
    case useClassicSwitching
}

/// Explains the macOS 27 system setting required by instant Space switching.
struct SpaceSwipeGestureAlert {
    func runModal() -> SpaceSwipeGestureAlertResponse {
        runAlertOnMain {
            let alert = NSAlert()
            alert.messageText = Localization.alertSpaceSwipeGestureTitle
            alert.informativeText = String(
                format: Localization.alertSpaceSwipeGestureDetail,
                AppInfo.appName
            )
            alert.alertStyle = .informational
            alert.useSmallAppIcon()
            alert.addButton(withTitle: Localization.buttonEnableSwipeGestures)
            alert.addButton(withTitle: Localization.buttonUseClassicSwitching)

            return alert.runActivatedModal() == .alertFirstButtonReturn
                ? .enableInstantSwitching
                : .useClassicSwitching
        }
    }
}

/// Asks whether a left click should switch Spaces.
struct ClickToSwitchAlert {
    /// Shows the alert and returns true if the user turned click-to-switch on
    func runModal() -> Bool {
        runAlertOnMain {
            let alert = NSAlert()
            alert.messageText = Localization.alertClickToSwitchTitle
            alert.informativeText = Localization.alertClickToSwitchDetail
            alert.alertStyle = .informational
            alert.useSmallAppIcon()
            alert.addButton(withTitle: Localization.buttonTurnOn)
            let keepOffButton = alert.addButton(withTitle: Localization.buttonKeepOff)
            // AppKit gives Escape only to a button titled Cancel
            keepOffButton.keyEquivalent = "\u{1b}"

            return alert.runActivatedModal() == .alertFirstButtonReturn
        }
    }
}

/// A confirmation alert for destructive or important actions
struct ConfirmationAlert {
    let message: String
    let detail: String
    let confirmTitle: String
    let isDestructive: Bool

    init(message: String, detail: String, confirmTitle: String = Localization.buttonReset, isDestructive: Bool = true) {
        self.message = message
        self.detail = detail
        self.confirmTitle = confirmTitle
        self.isDestructive = isDestructive
    }

    /// Shows the alert and returns true if the user confirmed
    func runModal() -> Bool {
        runAlertOnMain {
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

            return alert.runActivatedModal() == .alertFirstButtonReturn
        }
    }
}
