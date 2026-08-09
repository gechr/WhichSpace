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
    /// its Desktop name and the icons of the apps on it per the picker style,
    /// with a checkmark on the active Space.
    static func buildSpacePickerMenu(
        entries: [SpacePickerEntry],
        style: SpacePickerStyle,
        target: AnyObject
    ) -> NSMenu {
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
            if let attributed = attributedTitle(for: entry, style: style) {
                // AppKit draws the plain title in place of an empty
                // attributed one, so a blanked row clears the title itself
                // and keeps the Desktop name as a tooltip
                if attributed.length == 0 {
                    item.title = ""
                    item.toolTip = entry.title
                } else {
                    item.attributedTitle = attributed
                    // The "(empty)" placeholder does not name the Space
                    // either, so those rows keep the tooltip too
                    if entry.appIcons.isEmpty, entry.overflowCount == 0 {
                        item.toolTip = entry.title
                    }
                }
            }
            menu.addItem(item)
        }
        configureHiddenSettingsItem(in: menu, target: target)
        addBottomSpacer(to: menu)
        return menu
    }

    /// Hidden items still match key equivalents, so Cmd+, keeps opening the
    /// settings window while this menu is tracking instead of falling through
    /// to the app's hidden main menu.
    private static func configureHiddenSettingsItem(in menu: NSMenu, target: AnyObject) {
        let item = NSMenuItem(
            title: Localization.menuSettingsWindow,
            action: #selector(ActionHandler.openSettingsWindow),
            keyEquivalent: ","
        )
        item.keyEquivalentModifierMask = [.command]
        item.target = target
        item.isHidden = true
        menu.addItem(item)
    }

    /// The attributed row title carrying the app icons, or nil when the plain
    /// title already says everything: name mode, fullscreen rows, and an
    /// iconless row in the combined style. An empty string blanks the row
    /// entirely in the none style.
    static func attributedTitle(for entry: SpacePickerEntry, style: SpacePickerStyle) -> NSAttributedString? {
        if style == .none {
            return NSAttributedString(string: "")
        }
        guard style != .name, entry.targetSpace != nil else {
            return nil
        }
        let font = NSFont.menuFont(ofSize: 0)
        if entry.appIcons.isEmpty, entry.overflowCount == 0 {
            guard style == .icons else {
                return nil
            }
            // Empty Space in icons mode: a dim placeholder in place of icons
            return NSAttributedString(
                string: Localization.labelPickerEmpty,
                attributes: [.font: font, .foregroundColor: NSColor.secondaryLabelColor]
            )
        }
        let result = NSMutableAttributedString()
        if style == .both {
            // No foreground color on the name run: the menu substitutes the
            // highlight and dark-mode colors only for unstyled text
            result.append(NSAttributedString(string: entry.title + "  ", attributes: [.font: font]))
        }
        let side = Layout.spacePickerAppIconSize
        for (index, icon) in entry.appIcons.enumerated() {
            if index > 0 {
                result.append(NSAttributedString(string: "\u{2009}", attributes: [.font: font]))
            }
            let attachment = NSTextAttachment()
            attachment.image = icon
            // An icon taller than the font's ascent grows the line box and
            // drags the title off the row's centre with it, so the icon is
            // held inside the ascent and centred on the cap height
            attachment.bounds = CGRect(x: 0, y: (font.capHeight - side) / 2, width: side, height: side)
            result.append(NSAttributedString(attachment: attachment))
        }
        if entry.overflowCount > 0 {
            result.append(NSAttributedString(
                string: " +\(entry.overflowCount)",
                attributes: [.font: font, .foregroundColor: NSColor.secondaryLabelColor]
            ))
        }
        // An attachment run carries no font of its own, so the line would
        // otherwise take its metrics from the default font while the icons
        // are placed against the menu font, tilting them off centre
        result.addAttribute(.font, value: font, range: NSRange(location: 0, length: result.length))
        return result
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
