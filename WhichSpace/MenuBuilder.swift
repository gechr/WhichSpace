import AppKit
import Defaults

// MARK: - MenuActionDelegate

/// Delegate protocol for menu interactions. AppDelegate conforms to this
/// so MenuBuilder has no direct dependency on it.
@MainActor
protocol MenuActionDelegate: AnyObject {
    func sizeChanged(to scale: Double)
    func skinToneSelected(_ tone: SkinTone)
    func foregroundColorSelected(_ color: NSColor)
    func backgroundColorSelected(_ color: NSColor)
    func separatorColorSelected(_ color: NSColor)
    func customForegroundColorRequested()
    func customBackgroundColorRequested()
    func customSeparatorColorRequested()
    func symbolSelected(_ symbol: String?)
    func iconStyleSelected(_ style: IconStyle, stylePicker: StylePicker?)

    // Preview hover callbacks
    func skinToneHoverStarted(_ tone: SkinTone)
    func colorHoverStarted(index: Int, isForeground: Bool)
    func backgroundColorHoverStarted(index: Int)
    func separatorColorHoverStarted(index: Int)
    func symbolHoverStarted(_ symbol: String, foreground: NSColor?, background: NSColor?, skinTone: SkinTone?)
    func styleHoverStarted(_ style: IconStyle)
    func hoverEnded()
}

// MARK: - MenuBuilder

/// Builds and configures the status menu for the app.
@MainActor
final class MenuBuilder {
    private let appState: AppState
    private let store: DefaultsStore

    init(appState: AppState, store: DefaultsStore) {
        self.appState = appState
        self.store = store
    }

    // MARK: - Menu State Update

    /// Updates all menu item states (checkmarks, visibility, enabled states) based on current app state.
    /// Called from AppDelegate's `menuWillOpen(_:)` to refresh the menu before it is displayed.
    ///
    /// - Parameters:
    ///   - menu: The menu whose items should be updated.
    ///   - launchAtLoginEnabled: Whether Launch at Login is currently enabled.
    func updateMenuState(menu: NSMenu, launchAtLoginEnabled: Bool) {
        let currentStyle = appState.currentIconStyle
        let customColors = appState.currentColors
        let previewNumber = appState.currentSpaceLabel == "?" ? "1" : appState.currentSpaceLabel
        let currentSymbol = appState.currentSymbol
        let symbolIsActive = currentSymbol != nil

        func setCheckmark(_ tag: MenuTag, _ value: Bool) {
            menu.item(withTag: tag.rawValue)?.state = value ? .on : .off
        }

        setCheckmark(.launchAtLogin, launchAtLoginEnabled)
        setCheckmark(.localSpaceNumbers, store.localSpaceNumbers)
        setCheckmark(.uniqueIconsPerDisplay, store.uniqueIconsPerDisplay)
        setCheckmark(.showAllSpaces, store.showAllSpaces)
        setCheckmark(.showAllDisplays, store.showAllDisplays)

        // Dim/Hide options are visible when either showAllSpaces or showAllDisplays is enabled
        let showMultiSpaceOptions = store.showAllSpaces || store.showAllDisplays

        // Update Click to Switch Spaces checkmark and visibility (only shown when multi-space is enabled)
        // Deselect if permission has been revoked
        if store.clickToSwitchSpaces, !AXIsProcessTrusted() {
            SettingsConstraints.setClickToSwitchSpaces(false, store: store)
        }
        setCheckmark(.clickToSwitchSpaces, store.clickToSwitchSpaces)
        menu.item(withTag: MenuTag.clickToSwitchSpaces.rawValue)?.isHidden = !showMultiSpaceOptions

        setCheckmark(.dimInactiveSpaces, store.dimInactiveSpaces)
        menu.item(withTag: MenuTag.dimInactiveSpaces.rawValue)?.isHidden = !showMultiSpaceOptions

        // Update hide option menu items (checkmark, icon, visibility)
        let updateHideItem = { (tag: MenuTag, isEnabled: Bool) in
            guard let item = menu.item(withTag: tag.rawValue) else {
                return
            }
            item.state = isEnabled ? .on : .off
            item.image = NSImage(
                systemSymbolName: isEnabled ? "eye.slash" : "eye.fill",
                accessibilityDescription: nil
            )
            item.isHidden = !showMultiSpaceOptions
        }
        updateHideItem(.hideEmptySpaces, store.hideEmptySpaces)
        updateHideItem(.hideSingleSpace, store.hideSingleSpace)
        updateHideItem(.hideFullscreenApps, store.hideFullscreenApps)

        // Determine if current symbol is an emoji vs SF Symbol
        let currentSymbolIsEmoji = currentSymbol?.containsEmoji ?? false
        let currentSymbolIsSFSymbol = symbolIsActive && !currentSymbolIsEmoji

        for item in menu.items {
            // Update icon style views - only show checkmark when not in symbol mode
            if let view = item.view as? StylePicker {
                view.isChecked = !symbolIsActive && item.representedObject as? IconStyle == currentStyle
                view.customColors = customColors
                view.darkMode = appState.darkModeEnabled
                view.previewNumber = previewNumber
                view.needsDisplay = true
            }

            // Update symbol picker view
            if let view = item.view as? ItemPicker {
                view.selectedItem = currentSymbol
                view.darkMode = appState.darkModeEnabled
                view.needsDisplay = true
            }

            // Show skin tone items only when emoji is active
            if item.tag == MenuTag.skinToneLabel.rawValue || item.tag == MenuTag.skinToneSwatch.rawValue {
                item.isHidden = !currentSymbolIsEmoji
            }

            // Update skin tone swatch to reflect current space's skin tone (with global fallback)
            if item.tag == MenuTag.skinToneSwatch.rawValue, let swatch = item.view as? SkinToneSwatch {
                let spaceTone = SpacePreferences.skinTone(
                    forSpace: appState.currentSpace,
                    display: appState.currentDisplayID,
                    store: store
                )
                swatch.currentTone = spaceTone ?? .default
            }

            // Show symbol label and color swatch only when SF Symbol is active (not emoji)
            if item.tag == MenuTag.symbolLabel.rawValue || item.tag == MenuTag.symbolColorSwatch.rawValue {
                item.isHidden = !currentSymbolIsSFSymbol
            }

            // Show separator divider, label, and swatch only when Show all Displays is enabled
            // AND there are multiple displays (separator only appears between displays)
            if item.tag == MenuTag.separatorColorDivider.rawValue || item.tag == MenuTag.separatorLabel.rawValue
                || item.tag == MenuTag.separatorSwatch.rawValue
            {
                let hasMultipleDisplays = appState.allDisplaysSpaceInfo.count > 1
                item.isHidden = !store.showAllDisplays || !hasMultipleDisplays
            }

            // Hide foreground/background labels and swatches when any symbol is active (SF Symbol or emoji)
            // Also hide background items when style is transparent (no background to color)
            let foregroundTags = [MenuTag.foregroundLabel.rawValue, MenuTag.foregroundSwatch.rawValue]
            let backgroundTags = [
                MenuTag.colorSeparator.rawValue,
                MenuTag.backgroundLabel.rawValue,
                MenuTag.backgroundSwatch.rawValue,
            ]
            if foregroundTags.contains(item.tag) {
                item.isHidden = symbolIsActive
            }
            if backgroundTags.contains(item.tag) {
                item.isHidden = symbolIsActive || currentStyle == .transparent
            }

            // Hide "Invert color" when any symbol is active (no fg/bg to swap)
            if item.tag == MenuTag.invertColors.rawValue {
                item.isHidden = symbolIsActive
            }
            // Update foreground label text: "Number" for transparent, "Number (Foreground)" otherwise
            if item.tag == MenuTag.foregroundLabel.rawValue {
                item.title = currentStyle == .transparent
                    ? Localization.labelNumber
                    : Localization.labelNumberForeground
            }

            // Update size row view (tag 310)
            if item.tag == MenuTag.sizeRow.rawValue, let view = item.view as? SizeSlider {
                view.currentSize = store.sizeScale
            }

            // Update sound menu checkmarks
            if item.representedObject is String {
                let soundName = item.representedObject as? String ?? ""
                item.state = soundName == store.soundName ? .on : .off
            }
        }
    }

    // MARK: - Sound Discovery

    private static let systemSounds = discoverSounds(in: URL(fileURLWithPath: "/System/Library/Sounds"))
    private static let userSounds = discoverSounds(
        in: FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Sounds")
    )

    private static func discoverSounds(in directory: URL) -> [String] {
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.contentTypeKey]
        ) else {
            return []
        }
        var sounds = Set<String>()
        for url in contents {
            guard let type = try? url.resourceValues(forKeys: [.contentTypeKey]).contentType,
                  type.conforms(to: .audio)
            else {
                continue
            }
            sounds.insert(url.deletingPathExtension().lastPathComponent)
        }
        return sounds.sorted()
    }

    // MARK: - Public Build Methods

    /// Builds the complete status menu, setting `target` for all @objc action items.
    func buildMenu(target: AnyObject, menuDelegate: NSMenuDelegate?, actionDelegate: MenuActionDelegate) -> NSMenu {
        let menu = NSMenu()

        configureVersionHeader(in: menu)
        configureColorMenuItem(in: menu, target: target, delegate: menuDelegate, actionDelegate: actionDelegate)
        configureStyleMenuItem(in: menu, target: target, delegate: menuDelegate, actionDelegate: actionDelegate)
        configureSoundMenuItem(in: menu, target: target, delegate: menuDelegate)
        configureSizeMenuItem(in: menu, delegate: menuDelegate, actionDelegate: actionDelegate)
        configureOptionsMenuItems(in: menu, target: target)
        configureLaunchAtLoginMenuItem(in: menu, target: target)
        configureUpdateMenuItem(in: menu, target: target)
        configureSettingsMenuItem(in: menu, target: target)
        configureQuitMenuItem(in: menu)

        return menu
    }

    // MARK: - Version Header

    private func configureVersionHeader(in menu: NSMenu) {
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

    // MARK: - Color Menu

    private func configureColorMenuItem(
        in menu: NSMenu, target: AnyObject, delegate: NSMenuDelegate?, actionDelegate: MenuActionDelegate
    ) {
        let colorsMenu = createColorMenu(target: target, actionDelegate: actionDelegate)
        colorsMenu.delegate = delegate
        let colorsMenuItem = NSMenuItem(title: Localization.menuColor, action: nil, keyEquivalent: "")
        colorsMenuItem.tag = MenuTag.colorMenuItem.rawValue
        colorsMenuItem.image = NSImage(systemSymbolName: "paintpalette", accessibilityDescription: nil)
        colorsMenuItem.submenu = colorsMenu
        menu.addItem(colorsMenuItem)
    }

    private func createColorMenu(target: AnyObject, actionDelegate: MenuActionDelegate) -> NSMenu {
        let colorsMenu = NSMenu(title: Localization.menuColor)

        addSkinToneSection(to: colorsMenu, actionDelegate: actionDelegate)
        addSymbolColorSection(to: colorsMenu, actionDelegate: actionDelegate)
        addForegroundBackgroundSection(to: colorsMenu, actionDelegate: actionDelegate)
        addSeparatorColorSection(to: colorsMenu, actionDelegate: actionDelegate)
        addColorActionItems(to: colorsMenu, target: target)

        return colorsMenu
    }

    private func addSkinToneSection(to menu: NSMenu, actionDelegate: MenuActionDelegate) {
        let skinToneLabelItem = NSMenuItem(title: Localization.labelSkinTone, action: nil, keyEquivalent: "")
        skinToneLabelItem.isEnabled = false
        skinToneLabelItem.tag = MenuTag.skinToneLabel.rawValue
        skinToneLabelItem.isHidden = true
        menu.addItem(skinToneLabelItem)

        let skinToneSwatchItem = NSMenuItem()
        skinToneSwatchItem.tag = MenuTag.skinToneSwatch.rawValue
        skinToneSwatchItem.isHidden = true
        let skinToneSwatch = SkinToneSwatch()
        skinToneSwatch.frame = NSRect(origin: .zero, size: skinToneSwatch.intrinsicContentSize)
        skinToneSwatch.onToneSelected = { [weak actionDelegate] tone in
            actionDelegate?.skinToneSelected(tone)
            skinToneSwatch.currentTone = tone
        }
        skinToneSwatch.onHoverStart = { [weak actionDelegate] index in
            if let tone = SkinTone(rawValue: index) {
                actionDelegate?.skinToneHoverStarted(tone)
            }
        }
        skinToneSwatch.onHoverEnd = { [weak actionDelegate] in
            actionDelegate?.hoverEnded()
        }
        skinToneSwatchItem.view = skinToneSwatch
        menu.addItem(skinToneSwatchItem)
    }

    private func addSymbolColorSection(to menu: NSMenu, actionDelegate: MenuActionDelegate) {
        let symbolLabelItem = NSMenuItem(title: Localization.labelSymbol, action: nil, keyEquivalent: "")
        symbolLabelItem.isEnabled = false
        symbolLabelItem.tag = MenuTag.symbolLabel.rawValue
        symbolLabelItem.isHidden = true
        menu.addItem(symbolLabelItem)

        let symbolSwatchItem = makeColorSwatchItem(
            tag: .symbolColorSwatch,
            onColorSelected: { [weak actionDelegate] in actionDelegate?.foregroundColorSelected($0) },
            onCustomColorRequested: { [weak actionDelegate] in actionDelegate?.customForegroundColorRequested() },
            onHoverStart: { [weak actionDelegate] in actionDelegate?.colorHoverStarted(index: $0, isForeground: true) },
            onHoverEnd: { [weak actionDelegate] in actionDelegate?.hoverEnded() }
        )
        symbolSwatchItem.isHidden = true
        menu.addItem(symbolSwatchItem)
    }

    private func addForegroundBackgroundSection(to menu: NSMenu, actionDelegate: MenuActionDelegate) {
        let foregroundLabel = NSMenuItem(title: Localization.labelNumberForeground, action: nil, keyEquivalent: "")
        foregroundLabel.isEnabled = false
        foregroundLabel.tag = MenuTag.foregroundLabel.rawValue
        menu.addItem(foregroundLabel)

        menu.addItem(makeColorSwatchItem(
            tag: .foregroundSwatch,
            onColorSelected: { [weak actionDelegate] in actionDelegate?.foregroundColorSelected($0) },
            onCustomColorRequested: { [weak actionDelegate] in actionDelegate?.customForegroundColorRequested() },
            onHoverStart: { [weak actionDelegate] in actionDelegate?.colorHoverStarted(index: $0, isForeground: true) },
            onHoverEnd: { [weak actionDelegate] in actionDelegate?.hoverEnded() }
        ))

        let separator = NSMenuItem.separator()
        separator.tag = MenuTag.colorSeparator.rawValue
        menu.addItem(separator)

        let backgroundLabel = NSMenuItem(title: Localization.labelNumberBackground, action: nil, keyEquivalent: "")
        backgroundLabel.isEnabled = false
        backgroundLabel.tag = MenuTag.backgroundLabel.rawValue
        menu.addItem(backgroundLabel)

        menu.addItem(makeColorSwatchItem(
            tag: .backgroundSwatch,
            onColorSelected: { [weak actionDelegate] in actionDelegate?.backgroundColorSelected($0) },
            onCustomColorRequested: { [weak actionDelegate] in actionDelegate?.customBackgroundColorRequested() },
            onHoverStart: { [weak actionDelegate] in actionDelegate?.backgroundColorHoverStarted(index: $0) },
            onHoverEnd: { [weak actionDelegate] in actionDelegate?.hoverEnded() }
        ))
    }

    private func addSeparatorColorSection(to menu: NSMenu, actionDelegate: MenuActionDelegate) {
        let separatorColorDivider = NSMenuItem.separator()
        separatorColorDivider.tag = MenuTag.separatorColorDivider.rawValue
        separatorColorDivider.isHidden = true
        menu.addItem(separatorColorDivider)

        let separatorLabelItem = NSMenuItem(title: Localization.labelSeparator, action: nil, keyEquivalent: "")
        separatorLabelItem.isEnabled = false
        separatorLabelItem.tag = MenuTag.separatorLabel.rawValue
        separatorLabelItem.isHidden = true
        menu.addItem(separatorLabelItem)

        let separatorSwatchItem = makeColorSwatchItem(
            tag: .separatorSwatch,
            onColorSelected: { [weak actionDelegate] in actionDelegate?.separatorColorSelected($0) },
            onCustomColorRequested: { [weak actionDelegate] in actionDelegate?.customSeparatorColorRequested() },
            onHoverStart: { [weak actionDelegate] in actionDelegate?.separatorColorHoverStarted(index: $0) },
            onHoverEnd: { [weak actionDelegate] in actionDelegate?.hoverEnded() }
        )
        separatorSwatchItem.isHidden = true
        menu.addItem(separatorSwatchItem)
    }

    private func addColorActionItems(to menu: NSMenu, target: AnyObject) {
        menu.addItem(.separator())

        addMenuItem(
            to: menu,
            title: Localization.actionInvertColors,
            action: #selector(ActionHandler.invertColors),
            target: target,
            tag: .invertColors,
            symbolName: "arrow.left.arrow.right",
            toolTip: Localization.tipInvertColors
        )
        menu.addItem(.separator())

        addMenuItem(
            to: menu,
            title: Localization.actionApplyColorToAll,
            action: #selector(ActionHandler.applyColorsToAllSpaces),
            target: target,
            symbolName: "square.on.square",
            toolTip: Localization.tipApplyColorToAll
        )
        addMenuItem(
            to: menu,
            title: Localization.actionResetColorToDefault,
            action: #selector(ActionHandler.resetColorToDefault),
            target: target,
            symbolName: "arrow.uturn.backward",
            toolTip: Localization.tipResetColorToDefault
        )
    }

    // MARK: - Style Menu

    // swiftlint:disable:next function_body_length
    private func configureStyleMenuItem(
        in menu: NSMenu, target: AnyObject, delegate: NSMenuDelegate?, actionDelegate: MenuActionDelegate
    ) {
        let styleMenu = NSMenu(title: Localization.menuStyle)
        styleMenu.delegate = delegate

        // Number submenu (icon shapes)
        let iconMenu = createIconMenu(target: target, actionDelegate: actionDelegate)
        let iconMenuItem = NSMenuItem(title: Localization.menuNumber, action: nil, keyEquivalent: "")
        iconMenuItem.image = NSImage(systemSymbolName: "textformat.123", accessibilityDescription: nil)
        iconMenuItem.submenu = iconMenu
        styleMenu.addItem(iconMenuItem)

        // Symbol submenu
        let symbolMenu = createItemMenu(type: .symbols, actionDelegate: actionDelegate)
        let symbolMenuItem = NSMenuItem(title: Localization.menuSymbol, action: nil, keyEquivalent: "")
        symbolMenuItem.image = NSImage(systemSymbolName: "burst.fill", accessibilityDescription: nil)
        symbolMenuItem.submenu = symbolMenu
        styleMenu.addItem(symbolMenuItem)

        // Emoji submenu
        let emojiMenu = createItemMenu(type: .emojis, actionDelegate: actionDelegate)
        let emojiMenuItem = NSMenuItem(title: Localization.menuEmoji, action: nil, keyEquivalent: "")
        emojiMenuItem.image = NSImage(systemSymbolName: "face.smiling", accessibilityDescription: nil)
        emojiMenuItem.submenu = emojiMenu
        styleMenu.addItem(emojiMenuItem)

        styleMenu.addItem(.separator())

        addMenuItem(
            to: styleMenu,
            title: Localization.actionApplyStyleToAll,
            action: #selector(ActionHandler.applyStyleToAllSpaces),
            target: target,
            symbolName: "square.on.square",
            toolTip: Localization.tipApplyStyleToAll
        )
        addMenuItem(
            to: styleMenu,
            title: Localization.actionResetStyleToDefault,
            action: #selector(ActionHandler.resetStyleToDefault),
            target: target,
            symbolName: "arrow.uturn.backward",
            toolTip: Localization.tipResetStyleToDefault
        )

        let styleMenuItem = NSMenuItem(title: Localization.menuStyle, action: nil, keyEquivalent: "")
        styleMenuItem.image = NSImage(systemSymbolName: "photo.artframe", accessibilityDescription: nil)
        styleMenuItem.submenu = styleMenu
        menu.addItem(styleMenuItem)
    }

    private func createIconMenu(target: AnyObject, actionDelegate: MenuActionDelegate) -> NSMenu {
        let iconMenu = NSMenu(title: Localization.menuNumber)

        for style in IconStyle.allCases {
            let item = NSMenuItem()
            let stylePicker = StylePicker(style: style)
            stylePicker.frame = NSRect(origin: .zero, size: stylePicker.intrinsicContentSize)
            stylePicker.isChecked = style == appState.currentIconStyle
            stylePicker.customColors = appState.currentColors
            stylePicker.darkMode = appState.darkModeEnabled
            stylePicker.previewNumber = appState.currentSpaceLabel == "?" ? "1" : appState.currentSpaceLabel
            stylePicker.sizeScale = appState.store.sizeScale
            stylePicker.onSelected = { [weak stylePicker, weak actionDelegate] in
                actionDelegate?.iconStyleSelected(style, stylePicker: stylePicker)
            }
            stylePicker.onHoverStart = { [weak actionDelegate] hoveredStyle in
                actionDelegate?.styleHoverStarted(hoveredStyle)
            }
            stylePicker.onHoverEnd = { [weak actionDelegate] in
                actionDelegate?.hoverEnded()
            }
            item.view = stylePicker
            item.representedObject = style
            iconMenu.addItem(item)
        }

        iconMenu.addItem(.separator())

        // showFontPanel uses responder chain (target: nil) because AppDelegate intercepts
        // it to configure the font manager before delegating to ActionHandler.
        addMenuItem(
            to: iconMenu,
            title: Localization.actionFont,
            action: #selector(ActionHandler.showFontPanel),
            target: nil,
            symbolName: "textformat",
            toolTip: Localization.tipFont
        )

        iconMenu.addItem(.separator())

        addMenuItem(
            to: iconMenu,
            title: Localization.actionResetFontToDefault,
            action: #selector(ActionHandler.resetFontToDefault),
            target: target,
            symbolName: "arrow.uturn.backward",
            toolTip: Localization.tipResetFontToDefault
        )

        return iconMenu
    }

    private func createItemMenu(type: ItemPicker.ItemType, actionDelegate: MenuActionDelegate) -> NSMenu {
        let title = type == .symbols ? Localization.menuSymbol : Localization.menuEmoji
        let menu = NSMenu(title: title)

        let pickerItem = NSMenuItem()
        let picker = ItemPicker(type: type)
        picker.frame = NSRect(origin: .zero, size: picker.intrinsicContentSize)
        picker.selectedItem = appState.currentSymbol
        picker.darkMode = appState.darkModeEnabled
        picker.onItemSelected = { [weak actionDelegate] item in
            actionDelegate?.symbolSelected(item)
        }
        picker.onItemHoverStart = { [weak self, weak actionDelegate] item in
            let skinTone = item.containsEmoji ? Defaults[.emojiPickerSkinTone] : nil
            let foreground = self?.appState.currentColors?.foreground
            let background = self?.appState.currentColors?.background
            actionDelegate?.symbolHoverStarted(item, foreground: foreground, background: background, skinTone: skinTone)
        }
        picker.onItemHoverEnd = { [weak actionDelegate] in
            actionDelegate?.hoverEnded()
        }
        pickerItem.view = picker
        menu.addItem(pickerItem)

        return menu
    }

    // MARK: - Sound Menu

    private func configureSoundMenuItem(in menu: NSMenu, target: AnyObject, delegate: NSMenuDelegate?) {
        let soundMenu = createSoundMenu(target: target)
        soundMenu.delegate = delegate
        let soundMenuItem = NSMenuItem(title: Localization.menuSound, action: nil, keyEquivalent: "")
        soundMenuItem.image = NSImage(systemSymbolName: "speaker.wave.2", accessibilityDescription: nil)
        soundMenuItem.submenu = soundMenu
        menu.addItem(soundMenuItem)
    }

    private func createSoundMenu(target: AnyObject) -> NSMenu {
        let soundMenu = NSMenu(title: Localization.menuSound)

        // "None" option at top (disables sound)
        let noneItem = NSMenuItem(
            title: Localization.soundNone,
            action: #selector(ActionHandler.selectSound(_:)),
            keyEquivalent: ""
        )
        noneItem.target = target
        noneItem.representedObject = ""
        noneItem.state = store.soundName.isEmpty ? NSControl.StateValue.on : NSControl.StateValue.off
        soundMenu.addItem(noneItem)

        soundMenu.addItem(.separator())

        let hasUserSounds = !Self.userSounds.isEmpty

        if hasUserSounds {
            let header = NSMenuItem(title: Localization.soundUser, action: nil, keyEquivalent: "")
            header.isEnabled = false
            soundMenu.addItem(header)

            for soundName in Self.userSounds {
                let item = NSMenuItem(
                    title: soundName,
                    action: #selector(ActionHandler.selectSound(_:)),
                    keyEquivalent: ""
                )
                item.target = target
                item.representedObject = soundName
                item.state = store.soundName == soundName ? NSControl.StateValue.on : NSControl.StateValue.off
                soundMenu.addItem(item)
            }

            soundMenu.addItem(.separator())
            let systemHeader = NSMenuItem(title: Localization.soundSystem, action: nil, keyEquivalent: "")
            systemHeader.isEnabled = false
            soundMenu.addItem(systemHeader)
        }

        for soundName in Self.systemSounds {
            let item = NSMenuItem(
                title: soundName,
                action: #selector(ActionHandler.selectSound(_:)),
                keyEquivalent: ""
            )
            item.target = target
            item.representedObject = soundName
            item.state = store.soundName == soundName ? .on : .off
            soundMenu.addItem(item)
        }

        return soundMenu
    }

    // MARK: - Size Menu

    private func configureSizeMenuItem(in menu: NSMenu, delegate: NSMenuDelegate?, actionDelegate: MenuActionDelegate) {
        let sizeMenu = NSMenu(title: Localization.menuSize)
        sizeMenu.delegate = delegate

        let sizeItem = NSMenuItem()
        sizeItem.tag = MenuTag.sizeRow.rawValue
        let sizeSlider = SizeSlider(
            initialSize: store.sizeScale,
            range: Layout.sizeScaleRange
        )
        sizeSlider.frame = NSRect(origin: .zero, size: sizeSlider.intrinsicContentSize)
        sizeSlider.onSizeChanged = { [weak actionDelegate] scale in
            actionDelegate?.sizeChanged(to: scale)
        }
        sizeItem.view = sizeSlider
        sizeMenu.addItem(sizeItem)

        let sizeMenuItem = NSMenuItem(title: Localization.menuSize, action: nil, keyEquivalent: "")
        sizeMenuItem.image = NSImage(
            systemSymbolName: "arrow.up.left.and.down.right.and.arrow.up.right.and.down.left",
            accessibilityDescription: nil
        )
        sizeMenuItem.submenu = sizeMenu
        menu.addItem(sizeMenuItem)
        menu.addItem(.separator())
    }

    // MARK: - Options Menu Items

    private struct OptionItem {
        let title: String
        let action: Selector
        var tag: MenuTag?
        let symbolName: String
        let toolTip: String
        var symbolConfig: NSImage.SymbolConfiguration?
    }

    private enum OptionEntry {
        case item(OptionItem)
        case separator
    }

    private static let optionEntries: [OptionEntry] = [
        .item(OptionItem(
            title: Localization.toggleLocalSpaceNumbers,
            action: #selector(ActionHandler.toggleLocalSpaceNumbers),
            tag: .localSpaceNumbers,
            symbolName: "1.square",
            toolTip: Localization.tipLocalSpaceNumbers,
            symbolConfig: NSImage.SymbolConfiguration(pointSize: 18, weight: .medium)
        )),
        .item(OptionItem(
            title: Localization.toggleUniqueIconsPerDisplay,
            action: #selector(ActionHandler.toggleUniqueIconsPerDisplay),
            tag: .uniqueIconsPerDisplay,
            symbolName: "theatermasks",
            toolTip: Localization.tipUniqueIconsPerDisplay
        )),
        .item(OptionItem(
            title: Localization.toggleDimInactiveSpaces,
            action: #selector(ActionHandler.toggleDimInactiveSpaces),
            tag: .dimInactiveSpaces,
            symbolName: "aqi.low",
            toolTip: Localization.tipDimInactiveSpaces
        )),
        .separator,
        .item(OptionItem(
            title: Localization.toggleShowAllDisplays,
            action: #selector(ActionHandler.toggleShowAllDisplays),
            tag: .showAllDisplays,
            symbolName: "display.2",
            toolTip: Localization.tipShowAllDisplays
        )),
        .item(OptionItem(
            title: Localization.toggleShowAllSpaces,
            action: #selector(ActionHandler.toggleShowAllSpaces),
            tag: .showAllSpaces,
            symbolName: "square.grid.3x1.below.line.grid.1x2",
            toolTip: Localization.tipShowAllSpaces
        )),
        .item(OptionItem(
            title: Localization.toggleClickToSwitchSpaces,
            action: #selector(ActionHandler.toggleClickToSwitchSpaces),
            tag: .clickToSwitchSpaces,
            symbolName: "hand.tap.fill",
            toolTip: Localization.tipClickToSwitchSpaces
        )),
        .separator,
        .item(OptionItem(
            title: Localization.toggleHideEmptySpaces,
            action: #selector(ActionHandler.toggleHideEmptySpaces),
            tag: .hideEmptySpaces,
            symbolName: "eye.slash.fill",
            toolTip: Localization.tipHideEmptySpaces
        )),
        .item(OptionItem(
            title: Localization.toggleHideSingleSpace,
            action: #selector(ActionHandler.toggleHideSingleSpace),
            tag: .hideSingleSpace,
            symbolName: "eye.slash.fill",
            toolTip: Localization.tipHideSingleSpace
        )),
        .item(OptionItem(
            title: Localization.toggleHideFullscreenApps,
            action: #selector(ActionHandler.toggleHideFullscreenApps),
            tag: .hideFullscreenApps,
            symbolName: "eye.slash.fill",
            toolTip: Localization.tipHideFullscreenApps
        )),
        .separator,
        .item(OptionItem(
            title: Localization.actionApplyToAll,
            action: #selector(ActionHandler.applyToAllSpaces),
            symbolName: "square.on.square",
            toolTip: Localization.tipApplyToAll
        )),
        .item(OptionItem(
            title: Localization.actionResetSpaceToDefault,
            action: #selector(ActionHandler.resetSpaceToDefault),
            symbolName: "arrow.uturn.backward",
            toolTip: Localization.tipResetSpaceToDefault
        )),
        .item(OptionItem(
            title: Localization.actionResetAllSpacesToDefault,
            action: #selector(ActionHandler.resetAllSpacesToDefault),
            symbolName: "arrow.triangle.2.circlepath",
            toolTip: Localization.tipResetAllSpacesToDefault
        )),
        .separator,
    ]

    private func configureOptionsMenuItems(in menu: NSMenu, target: AnyObject) {
        for entry in Self.optionEntries {
            switch entry {
            case .separator:
                menu.addItem(.separator())
            case let .item(opt):
                let item = addMenuItem(
                    to: menu,
                    title: opt.title,
                    action: opt.action,
                    target: target,
                    tag: opt.tag,
                    symbolName: opt.symbolName,
                    toolTip: opt.toolTip
                )
                if let symbolConfig = opt.symbolConfig {
                    item.image = item.image?.withSymbolConfiguration(symbolConfig)
                }
            }
        }
    }

    // MARK: - Launch at Login

    private func configureLaunchAtLoginMenuItem(in menu: NSMenu, target: AnyObject) {
        addMenuItem(
            to: menu,
            title: Localization.toggleLaunchAtLogin,
            action: #selector(ActionHandler.toggleLaunchAtLogin),
            target: target,
            tag: .launchAtLogin,
            symbolName: "sunrise",
            toolTip: String(format: Localization.tipLaunchAtLogin, AppInfo.appName)
        )
    }

    // MARK: - Update

    private func configureUpdateMenuItem(in menu: NSMenu, target: AnyObject) {
        guard !AppInfo.isHomebrewInstall else {
            return
        }
        addMenuItem(
            to: menu,
            title: Localization.actionCheckForUpdates,
            action: #selector(ActionHandler.checkForUpdates),
            target: target,
            symbolName: "square.and.arrow.down",
            toolTip: String(format: Localization.tipCheckForUpdates, AppInfo.appName)
        )
    }

    // MARK: - Settings

    private func configureSettingsMenuItem(in menu: NSMenu, target: AnyObject) {
        menu.addItem(.separator())

        let settingsMenu = NSMenu(title: Localization.menuSettings)

        addMenuItem(
            to: settingsMenu,
            title: Localization.actionImportSettings,
            action: #selector(ActionHandler.importSettings),
            target: target,
            symbolName: "square.and.arrow.down",
            toolTip: Localization.tipImportSettings
        )
        addMenuItem(
            to: settingsMenu,
            title: Localization.actionExportSettings,
            action: #selector(ActionHandler.exportSettings),
            target: target,
            symbolName: "square.and.arrow.up",
            toolTip: Localization.tipExportSettings
        )

        let settingsMenuItem = NSMenuItem(title: Localization.menuSettings, action: nil, keyEquivalent: "")
        settingsMenuItem.image = NSImage(systemSymbolName: "gearshape", accessibilityDescription: nil)
        settingsMenuItem.submenu = settingsMenu
        menu.addItem(settingsMenuItem)
    }

    // MARK: - Helpers

    @discardableResult
    private func addMenuItem(
        to menu: NSMenu,
        title: String,
        action: Selector,
        target: AnyObject?,
        tag: MenuTag? = nil,
        symbolName: String? = nil,
        toolTip: String? = nil
    ) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = target
        if let tag {
            item.tag = tag.rawValue
        }
        if let symbolName {
            item.image = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil)
        }
        item.toolTip = toolTip
        menu.addItem(item)
        return item
    }

    private func makeColorSwatchItem(
        tag: MenuTag,
        onColorSelected: @escaping (NSColor) -> Void,
        onCustomColorRequested: @escaping () -> Void,
        onHoverStart: @escaping (Int) -> Void,
        onHoverEnd: @escaping () -> Void
    ) -> NSMenuItem {
        let item = NSMenuItem()
        item.tag = tag.rawValue
        let swatch = ColorSwatch()
        swatch.frame = NSRect(origin: .zero, size: swatch.intrinsicContentSize)
        swatch.onColorSelected = onColorSelected
        swatch.onCustomColorRequested = onCustomColorRequested
        swatch.onHoverStart = { index in
            guard index < ColorSwatch.presetColors.count else {
                return
            }
            onHoverStart(index)
        }
        swatch.onHoverEnd = onHoverEnd
        item.view = swatch
        return item
    }

    // MARK: - Quit

    private func configureQuitMenuItem(in menu: NSMenu) {
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

        // NSMenu clips bottom padding when containing custom view-backed items, so add
        // an invisible spacer to compensate.
        let spacer = NSMenuItem()
        spacer.isEnabled = false
        spacer.view = NSView(frame: NSRect(x: 0, y: 0, width: 1, height: 5))
        menu.addItem(spacer)
    }
}
