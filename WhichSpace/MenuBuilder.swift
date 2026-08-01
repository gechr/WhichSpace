import AppKit

// MARK: - MenuBuilder

/// Builds the status menu and the left-click Space picker menu. All
/// configuration lives in the settings window.
@MainActor
enum MenuBuilder {
    /// Builds the right-click status menu: version header, Settings, Check
    /// for Updates, and Quit.
    static func buildMenu(target: AnyObject) -> NSMenu {
        let menu = NSMenu()

        configureVersionHeader(in: menu)
        configureSettingsMenuItem(in: menu, target: target)
        menu.addItem(.separator())
        configureUpdateMenuItem(in: menu, target: target)
        configureQuitMenuItem(in: menu)

        return menu
    }

    // MARK: - Space Picker Menu

    /// Builds the transient menu shown on left-click in single-icon mode: one
    /// item per Space, rendered exactly like its status bar icon, titled with
    /// its Desktop name, with a checkmark on the active Space.
    static func buildSpacePickerMenu(entries: [SpacePickerEntry], target: AnyObject) -> NSMenu {
        let menu = NSMenu()
        for entry in entries {
            let item = NSMenuItem(
                title: entry.title,
                action: #selector(ActionHandler.switchToPickedSpace(_:)),
                keyEquivalent: entry.keyEquivalent
            )
            // Bare digits: the initializer defaults the mask to Command
            item.keyEquivalentModifierMask = []
            item.target = target
            item.image = entry.icon
            item.state = entry.isActive ? .on : .off
            item.representedObject = entry
            menu.addItem(item)
        }
        addBottomSpacer(to: menu)
        return menu
    }

    // MARK: - Version Header

    private static func configureVersionHeader(in menu: NSMenu) {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        let versionItem = NSMenuItem(title: "\(AppInfo.appName) v\(version)", action: nil, keyEquivalent: "")
        versionItem.isEnabled = false
        versionItem.toolTip = "https://github.com/gechr/WhichSpace"
        if let icon = NSApp.applicationIconImage {
            let resized = NSImage(size: NSSize(width: 16, height: 16), flipped: false) { rect in
                icon.draw(in: rect)
                return true
            }
            versionItem.image = resized
        }
        menu.addItem(versionItem)
        menu.addItem(.separator())
    }

    // MARK: - Update

    private static func configureUpdateMenuItem(in menu: NSMenu, target: AnyObject) {
        let updateItem = addMenuItem(
            to: menu,
            title: Localization.actionCheckForUpdates,
            action: #selector(ActionHandler.checkForUpdates),
            target: target,
            symbolName: "square.and.arrow.down",
            toolTip: String(format: Localization.tipCheckForUpdates, AppInfo.appName)
        )
        updateItem.keyEquivalent = "u"
        updateItem.keyEquivalentModifierMask = [.command]
    }

    // MARK: - Settings

    private static func configureSettingsMenuItem(in menu: NSMenu, target: AnyObject) {
        let settingsItem = addMenuItem(
            to: menu,
            title: Localization.menuSettingsWindow,
            action: #selector(ActionHandler.openSettingsWindow),
            target: target,
            symbolName: "gearshape",
            toolTip: String(format: Localization.tipSettingsWindow, AppInfo.appName)
        )
        settingsItem.keyEquivalent = ","
        settingsItem.keyEquivalentModifierMask = [.command]
    }

    // MARK: - Quit

    private static func configureQuitMenuItem(in menu: NSMenu) {
        menu.addItem(.separator())

        let quitItem = NSMenuItem(
            title: Localization.actionQuit,
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )
        quitItem.keyEquivalentModifierMask = [.command]
        quitItem.image = NSImage(systemSymbolName: "xmark.rectangle", accessibilityDescription: nil)
        quitItem.toolTip = String(format: Localization.tipQuit, AppInfo.appName)
        menu.addItem(quitItem)

        addBottomSpacer(to: menu)
    }

    // MARK: - Spacer

    /// The popped-up menu clips its bottom padding, cutting into the last
    /// item; an invisible spacer restores the inset.
    private static func addBottomSpacer(to menu: NSMenu) {
        let spacer = NSMenuItem()
        spacer.isEnabled = false
        spacer.view = NSView(frame: NSRect(x: 0, y: 0, width: 1, height: 5))
        menu.addItem(spacer)
    }

    // MARK: - Helpers

    @discardableResult
    private static func addMenuItem(
        to menu: NSMenu,
        title: String,
        action: Selector,
        target: AnyObject?,
        symbolName: String? = nil,
        toolTip: String? = nil
    ) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = target
        if let symbolName {
            item.image = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil)
        }
        item.toolTip = toolTip
        menu.addItem(item)
        return item
    }
}
