import AppKit
import Defaults

// MARK: - MenuBuilder Callbacks

/// Callbacks used by MenuBuilder to wire up interactive menu items.
/// The AppDelegate provides these so MenuBuilder has no dependency on it.
struct MenuBuilderCallbacks {
    var onSizeChanged: (Double) -> Void = { _ in }
    var onSkinToneSelected: (SkinTone) -> Void = { _ in }
    var onSkinToneHoverStart: (SkinTone) -> Void = { _ in }
    var onForegroundColorSelected: (NSColor) -> Void = { _ in }
    var onBackgroundColorSelected: (NSColor) -> Void = { _ in }
    var onSeparatorColorSelected: (NSColor) -> Void = { _ in }
    var onCustomForegroundColorRequested: () -> Void = {}
    var onCustomBackgroundColorRequested: () -> Void = {}
    var onCustomSeparatorColorRequested: () -> Void = {}
    var onSymbolSelected: (String?) -> Void = { _ in }
    var onIconStyleSelected: (IconStyle, StylePicker?) -> Void = { _, _ in }
    var onColorHoverStart: (Int, Bool) -> Void = { _, _ in } // (index, isForeground)
    var onBackgroundColorHoverStart: (Int) -> Void = { _ in }
    var onSeparatorColorHoverStart: (Int) -> Void = { _ in }
    var onSymbolHoverStart: (String, NSColor?, NSColor?, SkinTone?) -> Void = { _, _, _, _ in }
    var onStyleHoverStart: (IconStyle) -> Void = { _ in }
    var onHoverEnd: () -> Void = {}
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

        // Update Launch at Login checkmark
        if let launchAtLoginItem = menu.item(withTag: MenuTag.launchAtLogin.rawValue) {
            launchAtLoginItem.state = launchAtLoginEnabled ? .on : .off
        }

        if let localSpaceNumbersItem = menu.item(withTag: MenuTag.localSpaceNumbers.rawValue) {
            localSpaceNumbersItem.state = store.localSpaceNumbers ? .on : .off
        }

        // Update Unique Icons Per Display checkmark
        if let uniqueIconsItem = menu.item(withTag: MenuTag.uniqueIconsPerDisplay.rawValue) {
            uniqueIconsItem.state = store.uniqueIconsPerDisplay ? .on : .off
        }

        // Update Show All Spaces checkmark
        if let showAllSpacesItem = menu.item(withTag: MenuTag.showAllSpaces.rawValue) {
            showAllSpacesItem.state = store.showAllSpaces ? .on : .off
        }

        // Update Show All Displays checkmark
        if let showAllDisplaysItem = menu.item(withTag: MenuTag.showAllDisplays.rawValue) {
            showAllDisplaysItem.state = store.showAllDisplays ? .on : .off
        }

        // Dim/Hide options are visible when either showAllSpaces or showAllDisplays is enabled
        let showMultiSpaceOptions = store.showAllSpaces || store.showAllDisplays

        // Update Click to Switch Spaces checkmark and visibility (only shown when multi-space is enabled)
        // Deselect if permission has been revoked
        if store.clickToSwitchSpaces, !AXIsProcessTrusted() {
            SettingsInvariantEnforcer.setClickToSwitchSpaces(false, store: store)
        }
        if let clickToSwitchItem = menu.item(withTag: MenuTag.clickToSwitchSpaces.rawValue) {
            clickToSwitchItem.state = store.clickToSwitchSpaces ? .on : .off
            clickToSwitchItem.isHidden = !showMultiSpaceOptions
        }

        // Update Dim inactive Spaces checkmark and visibility
        if let dimInactiveItem = menu.item(withTag: MenuTag.dimInactiveSpaces.rawValue) {
            dimInactiveItem.state = store.dimInactiveSpaces ? .on : .off
            dimInactiveItem.isHidden = !showMultiSpaceOptions
        }

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
            if let view = item.view as? SymbolPicker {
                view.selectedSymbol = currentSymbol
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
    func buildMenu(target: AnyObject, menuDelegate: NSMenuDelegate?, callbacks: MenuBuilderCallbacks) -> NSMenu {
        let menu = NSMenu()

        configureVersionHeader(in: menu)
        configureColorMenuItem(in: menu, target: target, delegate: menuDelegate, callbacks: callbacks)
        configureStyleMenuItem(in: menu, target: target, delegate: menuDelegate, callbacks: callbacks)
        configureSoundMenuItem(in: menu, target: target, delegate: menuDelegate)
        configureSizeMenuItem(in: menu, delegate: menuDelegate, callbacks: callbacks)
        configureOptionsMenuItems(in: menu, target: target)
        configureLaunchAtLoginMenuItem(in: menu, target: target)
        configureUpdateMenuItem(in: menu, target: target)
        configureSettingsMenuItem(in: menu, target: target)
        configureQuitMenuItem(in: menu)

        return menu
    }

    // MARK: - Version Header

    private var appName: String {
        AppInfo.appName
    }

    private var isHomebrewInstall: Bool {
        AppInfo.isHomebrewInstall
    }

    private func configureVersionHeader(in menu: NSMenu) {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        let versionItem = NSMenuItem(title: "\(appName) v\(version)", action: nil, keyEquivalent: "")
        versionItem.isEnabled = false
        versionItem.toolTip = "https://github.com/gechr/WhichSpace"
        if let icon = NSApp.applicationIconImage {
            let resized = NSImage(size: NSSize(width: 16, height: 16))
            resized.lockFocus()
            icon.draw(in: NSRect(x: 0, y: 0, width: 16, height: 16))
            resized.unlockFocus()
            versionItem.image = resized
        }
        menu.addItem(versionItem)
        menu.addItem(.separator())
    }

    // MARK: - Color Menu

    private func configureColorMenuItem(
        in menu: NSMenu, target: AnyObject, delegate: NSMenuDelegate?, callbacks: MenuBuilderCallbacks
    ) {
        let colorsMenu = createColorMenu(target: target, callbacks: callbacks)
        colorsMenu.delegate = delegate
        let colorsMenuItem = NSMenuItem(title: Localization.menuColor, action: nil, keyEquivalent: "")
        colorsMenuItem.tag = MenuTag.colorMenuItem.rawValue
        colorsMenuItem.image = NSImage(systemSymbolName: "paintpalette", accessibilityDescription: nil)
        colorsMenuItem.submenu = colorsMenu
        menu.addItem(colorsMenuItem)
    }

    // swiftlint:disable:next function_body_length
    private func createColorMenu(target: AnyObject, callbacks: MenuBuilderCallbacks) -> NSMenu {
        let colorsMenu = NSMenu(title: Localization.menuColor)

        // Skin tone label (shown only when emoji active)
        let skinToneLabelItem = NSMenuItem(title: Localization.labelSkinTone, action: nil, keyEquivalent: "")
        skinToneLabelItem.isEnabled = false
        skinToneLabelItem.tag = MenuTag.skinToneLabel.rawValue
        skinToneLabelItem.isHidden = true
        colorsMenu.addItem(skinToneLabelItem)

        // Skin tone swatch (shown only when emoji active)
        let skinToneSwatchItem = NSMenuItem()
        skinToneSwatchItem.tag = MenuTag.skinToneSwatch.rawValue
        skinToneSwatchItem.isHidden = true
        let skinToneSwatch = SkinToneSwatch()
        skinToneSwatch.frame = NSRect(origin: .zero, size: skinToneSwatch.intrinsicContentSize)
        skinToneSwatch.onToneSelected = { tone in
            callbacks.onSkinToneSelected(tone)
            skinToneSwatch.currentTone = tone
        }
        skinToneSwatch.onToneHoverStart = { tone in
            callbacks.onSkinToneHoverStart(tone)
        }
        skinToneSwatch.onHoverEnd = {
            callbacks.onHoverEnd()
        }
        skinToneSwatchItem.view = skinToneSwatch
        colorsMenu.addItem(skinToneSwatchItem)

        // Symbol label (shown only when symbol active)
        let symbolLabelItem = NSMenuItem(title: Localization.labelSymbol, action: nil, keyEquivalent: "")
        symbolLabelItem.isEnabled = false
        symbolLabelItem.tag = MenuTag.symbolLabel.rawValue
        symbolLabelItem.isHidden = true
        colorsMenu.addItem(symbolLabelItem)

        // Symbol color swatch (shown only when symbol active)
        let symbolSwatchItem = makeColorSwatchItem(
            tag: .symbolColorSwatch,
            onColorSelected: callbacks.onForegroundColorSelected,
            onCustomColorRequested: callbacks.onCustomForegroundColorRequested,
            onHoverStart: { callbacks.onColorHoverStart($0, true) },
            onHoverEnd: callbacks.onHoverEnd
        )
        symbolSwatchItem.isHidden = true
        colorsMenu.addItem(symbolSwatchItem)

        // Foreground label (hidden when symbol active)
        let foregroundLabel = NSMenuItem(title: Localization.labelNumberForeground, action: nil, keyEquivalent: "")
        foregroundLabel.isEnabled = false
        foregroundLabel.tag = MenuTag.foregroundLabel.rawValue
        colorsMenu.addItem(foregroundLabel)

        // Foreground color swatches (hidden when symbol active)
        colorsMenu.addItem(makeColorSwatchItem(
            tag: .foregroundSwatch,
            onColorSelected: callbacks.onForegroundColorSelected,
            onCustomColorRequested: callbacks.onCustomForegroundColorRequested,
            onHoverStart: { callbacks.onColorHoverStart($0, true) },
            onHoverEnd: callbacks.onHoverEnd
        ))

        // Separator (hidden when symbol active)
        let separator = NSMenuItem.separator()
        separator.tag = MenuTag.colorSeparator.rawValue
        colorsMenu.addItem(separator)

        // Background label (hidden when symbol active)
        let backgroundLabel = NSMenuItem(title: Localization.labelNumberBackground, action: nil, keyEquivalent: "")
        backgroundLabel.isEnabled = false
        backgroundLabel.tag = MenuTag.backgroundLabel.rawValue
        colorsMenu.addItem(backgroundLabel)

        // Background color swatches (hidden when symbol active)
        colorsMenu.addItem(makeColorSwatchItem(
            tag: .backgroundSwatch,
            onColorSelected: callbacks.onBackgroundColorSelected,
            onCustomColorRequested: callbacks.onCustomBackgroundColorRequested,
            onHoverStart: callbacks.onBackgroundColorHoverStart,
            onHoverEnd: callbacks.onHoverEnd
        ))

        // Separator color section (shown only when Show all Displays is enabled)
        let separatorColorDivider = NSMenuItem.separator()
        separatorColorDivider.tag = MenuTag.separatorColorDivider.rawValue
        separatorColorDivider.isHidden = true
        colorsMenu.addItem(separatorColorDivider)

        let separatorLabelItem = NSMenuItem(title: Localization.labelSeparator, action: nil, keyEquivalent: "")
        separatorLabelItem.isEnabled = false
        separatorLabelItem.tag = MenuTag.separatorLabel.rawValue
        separatorLabelItem.isHidden = true
        colorsMenu.addItem(separatorLabelItem)

        let separatorSwatchItem = makeColorSwatchItem(
            tag: .separatorSwatch,
            onColorSelected: callbacks.onSeparatorColorSelected,
            onCustomColorRequested: callbacks.onCustomSeparatorColorRequested,
            onHoverStart: callbacks.onSeparatorColorHoverStart,
            onHoverEnd: callbacks.onHoverEnd
        )
        separatorSwatchItem.isHidden = true
        colorsMenu.addItem(separatorSwatchItem)

        // Separator before actions
        colorsMenu.addItem(.separator())

        let invertColorsItem = NSMenuItem(
            title: Localization.actionInvertColors,
            action: #selector(AppDelegate.invertColors),
            keyEquivalent: ""
        )
        invertColorsItem.tag = MenuTag.invertColors.rawValue
        invertColorsItem.target = target
        invertColorsItem.image = NSImage(systemSymbolName: "arrow.left.arrow.right", accessibilityDescription: nil)
        invertColorsItem.toolTip = Localization.tipInvertColors
        colorsMenu.addItem(invertColorsItem)
        colorsMenu.addItem(.separator())

        let applyToAllItem = NSMenuItem(
            title: Localization.actionApplyColorToAll,
            action: #selector(AppDelegate.applyColorsToAllSpaces),
            keyEquivalent: ""
        )
        applyToAllItem.target = target
        applyToAllItem.image = NSImage(systemSymbolName: "square.on.square", accessibilityDescription: nil)
        applyToAllItem.toolTip = Localization.tipApplyColorToAll
        colorsMenu.addItem(applyToAllItem)

        let resetColorItem = NSMenuItem(
            title: Localization.actionResetColorToDefault,
            action: #selector(AppDelegate.resetColorToDefault),
            keyEquivalent: ""
        )
        resetColorItem.target = target
        resetColorItem.image = NSImage(systemSymbolName: "arrow.uturn.backward", accessibilityDescription: nil)
        resetColorItem.toolTip = Localization.tipResetColorToDefault
        colorsMenu.addItem(resetColorItem)

        return colorsMenu
    }

    // MARK: - Style Menu

    // swiftlint:disable:next function_body_length
    private func configureStyleMenuItem(
        in menu: NSMenu, target: AnyObject, delegate: NSMenuDelegate?, callbacks: MenuBuilderCallbacks
    ) {
        let styleMenu = NSMenu(title: Localization.menuStyle)
        styleMenu.delegate = delegate

        // Number submenu (icon shapes)
        let iconMenu = createIconMenu(callbacks: callbacks)
        let iconMenuItem = NSMenuItem(title: Localization.menuNumber, action: nil, keyEquivalent: "")
        iconMenuItem.image = NSImage(systemSymbolName: "textformat.123", accessibilityDescription: nil)
        iconMenuItem.submenu = iconMenu
        styleMenu.addItem(iconMenuItem)

        // Symbol submenu
        let symbolMenu = createItemMenu(type: .symbols, callbacks: callbacks)
        let symbolMenuItem = NSMenuItem(title: Localization.menuSymbol, action: nil, keyEquivalent: "")
        symbolMenuItem.image = NSImage(systemSymbolName: "burst.fill", accessibilityDescription: nil)
        symbolMenuItem.submenu = symbolMenu
        styleMenu.addItem(symbolMenuItem)

        // Emoji submenu
        let emojiMenu = createItemMenu(type: .emojis, callbacks: callbacks)
        let emojiMenuItem = NSMenuItem(title: Localization.menuEmoji, action: nil, keyEquivalent: "")
        emojiMenuItem.image = NSImage(systemSymbolName: "face.smiling", accessibilityDescription: nil)
        emojiMenuItem.submenu = emojiMenu
        styleMenu.addItem(emojiMenuItem)

        styleMenu.addItem(.separator())

        let applyStyleItem = NSMenuItem(
            title: Localization.actionApplyStyleToAll,
            action: #selector(AppDelegate.applyStyleToAllSpaces),
            keyEquivalent: ""
        )
        applyStyleItem.target = target
        applyStyleItem.image = NSImage(systemSymbolName: "square.on.square", accessibilityDescription: nil)
        applyStyleItem.toolTip = Localization.tipApplyStyleToAll
        styleMenu.addItem(applyStyleItem)

        let resetStyleItem = NSMenuItem(
            title: Localization.actionResetStyleToDefault,
            action: #selector(AppDelegate.resetStyleToDefault),
            keyEquivalent: ""
        )
        resetStyleItem.target = target
        resetStyleItem.image = NSImage(systemSymbolName: "arrow.uturn.backward", accessibilityDescription: nil)
        resetStyleItem.toolTip = Localization.tipResetStyleToDefault
        styleMenu.addItem(resetStyleItem)

        let styleMenuItem = NSMenuItem(title: Localization.menuStyle, action: nil, keyEquivalent: "")
        styleMenuItem.image = NSImage(systemSymbolName: "photo.artframe", accessibilityDescription: nil)
        styleMenuItem.submenu = styleMenu
        menu.addItem(styleMenuItem)
    }

    private func createIconMenu(callbacks: MenuBuilderCallbacks) -> NSMenu {
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
            stylePicker.onSelected = { [weak stylePicker] in
                callbacks.onIconStyleSelected(style, stylePicker)
            }
            stylePicker.onHoverStart = { hoveredStyle in
                callbacks.onStyleHoverStart(hoveredStyle)
            }
            stylePicker.onHoverEnd = {
                callbacks.onHoverEnd()
            }
            item.view = stylePicker
            item.representedObject = style
            iconMenu.addItem(item)
        }

        iconMenu.addItem(.separator())

        let fontItem = NSMenuItem(
            title: Localization.actionFont,
            action: #selector(AppDelegate.showFontPanel),
            keyEquivalent: ""
        )
        fontItem.target = nil // Uses responder chain
        fontItem.image = NSImage(systemSymbolName: "textformat", accessibilityDescription: nil)
        fontItem.toolTip = Localization.tipFont
        iconMenu.addItem(fontItem)

        let resetFontItem = NSMenuItem(
            title: Localization.actionResetFontToDefault,
            action: #selector(AppDelegate.resetFontToDefault),
            keyEquivalent: ""
        )
        resetFontItem.target = nil // Uses responder chain
        resetFontItem.image = NSImage(systemSymbolName: "arrow.uturn.backward", accessibilityDescription: nil)
        resetFontItem.toolTip = Localization.tipResetFontToDefault
        iconMenu.addItem(resetFontItem)

        return iconMenu
    }

    private func createItemMenu(type: ItemPicker.ItemType, callbacks: MenuBuilderCallbacks) -> NSMenu {
        let title = type == .symbols ? Localization.menuSymbol : Localization.menuEmoji
        let menu = NSMenu(title: title)

        let pickerItem = NSMenuItem()
        let picker = ItemPicker(type: type)
        picker.frame = NSRect(origin: .zero, size: picker.intrinsicContentSize)
        picker.selectedItem = appState.currentSymbol
        picker.darkMode = appState.darkModeEnabled
        picker.onItemSelected = { item in
            callbacks.onSymbolSelected(item)
        }
        picker.onItemHoverStart = { [weak self] item in
            let skinTone = item.containsEmoji ? Defaults[.emojiPickerSkinTone] : nil
            let foreground = self?.appState.currentColors?.foreground
            let background = self?.appState.currentColors?.background
            callbacks.onSymbolHoverStart(item, foreground, background, skinTone)
        }
        picker.onItemHoverEnd = {
            callbacks.onHoverEnd()
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
            action: #selector(AppDelegate.selectSound(_:)),
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
                    action: #selector(AppDelegate.selectSound(_:)),
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
                action: #selector(AppDelegate.selectSound(_:)),
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

    private func configureSizeMenuItem(in menu: NSMenu, delegate: NSMenuDelegate?, callbacks: MenuBuilderCallbacks) {
        let sizeMenu = NSMenu(title: Localization.menuSize)
        sizeMenu.delegate = delegate

        let sizeItem = NSMenuItem()
        sizeItem.tag = MenuTag.sizeRow.rawValue
        let sizeSlider = SizeSlider(
            initialSize: store.sizeScale,
            range: Layout.sizeScaleRange
        )
        sizeSlider.frame = NSRect(origin: .zero, size: sizeSlider.intrinsicContentSize)
        sizeSlider.onSizeChanged = { scale in
            callbacks.onSizeChanged(scale)
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

    // swiftlint:disable:next function_body_length
    private func configureOptionsMenuItems(in menu: NSMenu, target: AnyObject) {
        let localSpaceNumbersItem = NSMenuItem(
            title: Localization.toggleLocalSpaceNumbers,
            action: #selector(AppDelegate.toggleLocalSpaceNumbers),
            keyEquivalent: ""
        )
        localSpaceNumbersItem.target = target
        localSpaceNumbersItem.tag = MenuTag.localSpaceNumbers.rawValue
        let localSpaceNumbersConfig = NSImage.SymbolConfiguration(pointSize: 18, weight: .medium)
        localSpaceNumbersItem.image = NSImage(
            systemSymbolName: "1.square",
            accessibilityDescription: nil
        )?.withSymbolConfiguration(localSpaceNumbersConfig)
        localSpaceNumbersItem.toolTip = Localization.tipLocalSpaceNumbers
        menu.addItem(localSpaceNumbersItem)

        addMenuItem(
            to: menu,
            title: Localization.toggleUniqueIconsPerDisplay,
            action: #selector(AppDelegate.toggleUniqueIconsPerDisplay),
            target: target,
            tag: .uniqueIconsPerDisplay,
            symbolName: "theatermasks",
            toolTip: Localization.tipUniqueIconsPerDisplay
        )
        addMenuItem(
            to: menu,
            title: Localization.toggleDimInactiveSpaces,
            action: #selector(AppDelegate.toggleDimInactiveSpaces),
            target: target,
            tag: .dimInactiveSpaces,
            symbolName: "aqi.low",
            toolTip: Localization.tipDimInactiveSpaces
        )
        menu.addItem(NSMenuItem.separator())

        addMenuItem(
            to: menu,
            title: Localization.toggleShowAllDisplays,
            action: #selector(AppDelegate.toggleShowAllDisplays),
            target: target,
            tag: .showAllDisplays,
            symbolName: "display.2",
            toolTip: Localization.tipShowAllDisplays
        )
        addMenuItem(
            to: menu,
            title: Localization.toggleShowAllSpaces,
            action: #selector(AppDelegate.toggleShowAllSpaces),
            target: target,
            tag: .showAllSpaces,
            symbolName: "square.grid.3x1.below.line.grid.1x2",
            toolTip: Localization.tipShowAllSpaces
        )
        addMenuItem(
            to: menu,
            title: Localization.toggleClickToSwitchSpaces,
            action: #selector(AppDelegate.toggleClickToSwitchSpaces),
            target: target,
            tag: .clickToSwitchSpaces,
            symbolName: "hand.tap.fill",
            toolTip: Localization.tipClickToSwitchSpaces
        )
        menu.addItem(NSMenuItem.separator())

        addMenuItem(
            to: menu,
            title: Localization.toggleHideEmptySpaces,
            action: #selector(AppDelegate.toggleHideEmptySpaces),
            target: target,
            tag: .hideEmptySpaces,
            symbolName: "eye.slash.fill",
            toolTip: Localization.tipHideEmptySpaces
        )
        addMenuItem(
            to: menu,
            title: Localization.toggleHideSingleSpace,
            action: #selector(AppDelegate.toggleHideSingleSpace),
            target: target,
            tag: .hideSingleSpace,
            symbolName: "eye.slash.fill",
            toolTip: Localization.tipHideSingleSpace
        )
        addMenuItem(
            to: menu,
            title: Localization.toggleHideFullscreenApps,
            action: #selector(AppDelegate.toggleHideFullscreenApps),
            target: target,
            tag: .hideFullscreenApps,
            symbolName: "eye.slash.fill",
            toolTip: Localization.tipHideFullscreenApps
        )
        menu.addItem(.separator())

        addMenuItem(
            to: menu,
            title: Localization.actionApplyToAll,
            action: #selector(AppDelegate.applyToAllSpaces),
            target: target,
            symbolName: "square.on.square",
            toolTip: Localization.tipApplyToAll
        )
        addMenuItem(
            to: menu,
            title: Localization.actionResetSpaceToDefault,
            action: #selector(AppDelegate.resetSpaceToDefault),
            target: target,
            symbolName: "arrow.uturn.backward",
            toolTip: Localization.tipResetSpaceToDefault
        )
        addMenuItem(
            to: menu,
            title: Localization.actionResetAllSpacesToDefault,
            action: #selector(AppDelegate.resetAllSpacesToDefault),
            target: target,
            symbolName: "arrow.triangle.2.circlepath",
            toolTip: Localization.tipResetAllSpacesToDefault
        )
        menu.addItem(.separator())
    }

    // MARK: - Launch at Login

    private func configureLaunchAtLoginMenuItem(in menu: NSMenu, target: AnyObject) {
        let launchAtLoginItem = NSMenuItem(
            title: Localization.toggleLaunchAtLogin,
            action: #selector(AppDelegate.toggleLaunchAtLogin),
            keyEquivalent: ""
        )
        launchAtLoginItem.target = target
        launchAtLoginItem.tag = MenuTag.launchAtLogin.rawValue
        launchAtLoginItem.image = NSImage(systemSymbolName: "sunrise", accessibilityDescription: nil)
        launchAtLoginItem.toolTip = String(format: Localization.tipLaunchAtLogin, appName)
        menu.addItem(launchAtLoginItem)
    }

    // MARK: - Update

    private func configureUpdateMenuItem(in menu: NSMenu, target: AnyObject) {
        guard !isHomebrewInstall else {
            return
        }

        let updateItem = NSMenuItem(
            title: Localization.actionCheckForUpdates,
            action: #selector(AppDelegate.checkForUpdates),
            keyEquivalent: ""
        )
        updateItem.target = target
        updateItem.image = NSImage(systemSymbolName: "square.and.arrow.down", accessibilityDescription: nil)
        updateItem.toolTip = String(format: Localization.tipCheckForUpdates, appName)
        menu.addItem(updateItem)
    }

    // MARK: - Settings

    private func configureSettingsMenuItem(in menu: NSMenu, target: AnyObject) {
        menu.addItem(.separator())

        let settingsMenu = NSMenu(title: Localization.menuSettings)

        let importItem = NSMenuItem(
            title: Localization.actionImportSettings,
            action: #selector(AppDelegate.importSettings),
            keyEquivalent: ""
        )
        importItem.target = target
        importItem.image = NSImage(systemSymbolName: "square.and.arrow.down", accessibilityDescription: nil)
        importItem.toolTip = Localization.tipImportSettings
        settingsMenu.addItem(importItem)

        let exportItem = NSMenuItem(
            title: Localization.actionExportSettings,
            action: #selector(AppDelegate.exportSettings),
            keyEquivalent: ""
        )
        exportItem.target = target
        exportItem.image = NSImage(systemSymbolName: "square.and.arrow.up", accessibilityDescription: nil)
        exportItem.toolTip = Localization.tipExportSettings
        settingsMenu.addItem(exportItem)

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
        target: AnyObject,
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
        quitItem.toolTip = String(format: Localization.tipQuit, appName)
        menu.addItem(quitItem)

        // NSMenu clips bottom padding when containing custom view-backed items, so add
        // an invisible spacer to compensate.
        let spacer = NSMenuItem()
        spacer.isEnabled = false
        spacer.view = NSView(frame: NSRect(x: 0, y: 0, width: 1, height: 5))
        menu.addItem(spacer)
    }
}
