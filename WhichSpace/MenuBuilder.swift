import AppKit
import Defaults

// MARK: - MenuActionDelegate

/// Delegate protocol for menu interactions. AppDelegate conforms to this
/// so MenuBuilder has no direct dependency on it.
@MainActor
protocol MenuActionDelegate: AnyObject {
    func sizeChanged(to scale: Double)
    func paddingChanged(to scale: Double)
    func symbolGapChanged(to gap: Double)
    func scrollSensitivityChanged(to scale: Double)
    func scrollHapticIntensityChanged(to intensity: Int)
    func skinToneSelected(_ tone: SkinTone)
    func foregroundColorSelected(_ color: NSColor)
    func backgroundColorSelected(_ color: NSColor)
    func separatorColorSelected(_ color: NSColor)
    func symbolColorSelected(_ color: NSColor)
    func customForegroundColorRequested()
    func customBackgroundColorRequested()
    func customSeparatorColorRequested()
    func customSymbolColorRequested()
    func symbolSelected(_ symbol: String?)
    func iconStyleSelected(_ style: IconStyle, stylePicker: StylePicker?)
    func badgeCharacterChanged(_ character: String?)
    func badgePositionSelected(_ position: BadgePosition)
    func labelChanged(_ label: String?)
    func labelStyleSelected(_ style: IconStyle, stylePicker: StylePicker?)
    func labelStyleHoverStarted(_ style: IconStyle)

    // Preview hover callbacks
    func skinToneHoverStarted(_ tone: SkinTone)
    func colorHoverStarted(index: Int, isForeground: Bool)
    func backgroundColorHoverStarted(index: Int)
    func separatorColorHoverStarted(index: Int)
    func symbolColorHoverStarted(index: Int)
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
    private var userSounds: [String] = []
    private weak var labelInput: LabelInput?
    private weak var labelMenu: NSMenu?
    private weak var soundMenu: NSMenu?
    private weak var soundMenuTarget: AnyObject?

    private static let foregroundTags: Set<Int> = [
        MenuTag.foregroundLabel.rawValue,
        MenuTag.foregroundSwatch.rawValue,
    ]
    private static let backgroundTags: Set<Int> = [
        MenuTag.colorSeparator.rawValue,
        MenuTag.backgroundLabel.rawValue,
        MenuTag.backgroundSwatch.rawValue,
    ]

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

        // Deselect accessibility-dependent actions if permission has been revoked
        if !AXIsProcessTrusted() {
            if store.clickToSwitchSpaces {
                SettingsConstraints.setClickToSwitchSpaces(false, store: store)
            }
            if store.horizontalScrollEnabled {
                SettingsConstraints.setScrollSwitching(false, axis: \.horizontalScrollEnabled, store: store)
            }
            if store.verticalScrollEnabled {
                SettingsConstraints.setScrollSwitching(false, axis: \.verticalScrollEnabled, store: store)
            }
        }

        // Update Click to Switch Spaces checkmark and visibility (only shown when multi-space is enabled)
        setCheckmark(.clickToSwitchSpaces, store.clickToSwitchSpaces)
        menu.item(withTag: MenuTag.clickToSwitchSpaces.rawValue)?.isHidden = !showMultiSpaceOptions

        setCheckmark(.verticalScrollEnabled, store.verticalScrollEnabled)
        setCheckmark(.horizontalScrollEnabled, store.horizontalScrollEnabled)
        setCheckmark(.invertVerticalScroll, store.invertVerticalScroll)
        setCheckmark(.invertHorizontalScroll, store.invertHorizontalScroll)
        setCheckmark(.scrollWrapAround, store.scrollWrapAround)
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
        // Irrelevant while fullscreen spaces are hidden altogether
        setCheckmark(.fullscreenIconStyle, store.fullscreenIconStyle == .letter)
        menu.item(withTag: MenuTag.fullscreenIconStyle.rawValue)?.isHidden = store.hideFullscreenApps

        // Determine if current symbol is an emoji vs SF Symbol
        let currentSymbolIsEmoji = currentSymbol?.containsEmoji ?? false
        let currentSymbolIsSFSymbol = symbolIsActive && !currentSymbolIsEmoji

        // Update label input value and label style pickers
        let currentLabel = SpacePreferences.label(
            forSpace: appState.currentSpace,
            display: appState.currentDisplayID,
            store: store
        )
        labelInput?.currentLabel = currentLabel
        let hasLabel = currentLabel.map { !$0.isEmpty } ?? false

        // Hide badge menu when a symbol is shown alone; combined
        // symbol+label icons render text, so badges apply there
        menu.item(withTag: MenuTag.badgeMenuItem.rawValue)?.isHidden = symbolIsActive && !hasLabel
        let currentLabelStyle = SpacePreferences.labelStyle(
            forSpace: appState.currentSpace,
            display: appState.currentDisplayID,
            store: store
        ) ?? .square
        // Resolve the label submenu whether the opened menu contains it (style
        // menu) or IS it (menuWillOpen fires per-submenu with that submenu)
        let resolvedLabelMenu = menu === labelMenu
            ? menu
            : menu.item(withTag: MenuTag.labelMenuItem.rawValue)?.submenu
        if let resolvedLabelMenu {
            var pastInput = false
            for item in resolvedLabelMenu.items {
                if item.tag == MenuTag.labelInput.rawValue {
                    pastInput = true
                    continue
                }
                // Hide separators, headers, and style pickers when label is empty (not copy/reset)
                if pastInput, item.tag != MenuTag.fontMenuItem.rawValue,
                   item.isSeparatorItem || item.view is StylePicker || !item.isEnabled
                {
                    item.isHidden = !hasLabel
                }
                if let view = item.view as? StylePicker {
                    view.isChecked = item.representedObject as? IconStyle == currentLabelStyle
                    view.customColors = customColors
                    view.darkMode = appState.darkModeEnabled
                    view.previewNumber = previewNumber
                    view.sizeScale = store.sizeScale
                    view.needsDisplay = true
                }
            }

            // Symbol position/wrap section applies only when a symbol and a
            // label are combined
            updateSymbolSection(in: resolvedLabelMenu, visible: hasLabel && symbolIsActive)
        }

        let badgePositionTags: [MenuTag: BadgePosition] = [
            .badgePositionTopLeft: .topLeft,
            .badgePositionTopRight: .topRight,
            .badgePositionBottomLeft: .bottomLeft,
            .badgePositionBottomRight: .bottomRight,
        ]
        let currentBadge = SpacePreferences.badge(
            forSpace: appState.currentSpace,
            display: appState.currentDisplayID,
            store: store
        )

        for item in menu.items {
            // Update icon style views - only show checkmark when not in symbol
            // mode. Label pickers are handled above with the LABEL style; this
            // loop must not overwrite them with the icon style
            if let view = item.view as? StylePicker, menu !== labelMenu {
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

            // Hide foreground/background labels and swatches only when a
            // symbol is shown alone; combined symbol+label icons use them.
            // Also hide background items when style is transparent (no background to color)
            let symbolAlone = symbolIsActive && !hasLabel
            if Self.foregroundTags.contains(item.tag) {
                item.isHidden = symbolAlone
            }
            if Self.backgroundTags.contains(item.tag) {
                item.isHidden = symbolAlone || currentStyle == .transparent
            }

            // Hide "Invert color" when a symbol is shown alone (no fg/bg to swap)
            if item.tag == MenuTag.invertColors.rawValue {
                item.isHidden = symbolAlone
            }
            // Foreground/background headers name what they color: the label
            // when one is set, otherwise the number. Transparent styles have
            // no background, so the foreground header drops the suffix
            if item.tag == MenuTag.foregroundLabel.rawValue {
                let styleForTitle = hasLabel ? currentLabelStyle : currentStyle
                item.title = if styleForTitle == .transparent {
                    hasLabel ? Localization.menuLabel : Localization.labelNumber
                } else {
                    hasLabel ? Localization.labelLabelForeground : Localization.labelNumberForeground
                }
            }
            if item.tag == MenuTag.backgroundLabel.rawValue {
                item.title = hasLabel ? Localization.labelLabelBackground : Localization.labelNumberBackground
            }

            if item.tag == MenuTag.sizeRow.rawValue, let view = item.view as? SizeSlider {
                view.currentSize = store.sizeScale
            }

            if item.tag == MenuTag.paddingRow.rawValue, let view = item.view as? SizeSlider {
                view.currentSize = store.paddingScale
            }

            if item.tag == MenuTag.scrollSensitivityRow.rawValue, let view = item.view as? SizeSlider {
                view.currentSize = store.scrollSensitivity
            }
            if item.tag == MenuTag.scrollHapticIntensityRow.rawValue, let view = item.view as? SizeSlider {
                view.currentSize = store.scrollHapticFeedback ? Double(store.scrollHapticIntensity) : 0
            }

            // Update badge character input
            if item.tag == MenuTag.badgeCharacterField.rawValue, let badgeInput = item.view as? BadgeInput {
                badgeInput.currentCharacter = currentBadge?.character
            }

            // Update badge position checkmarks
            if let position = MenuTag(rawValue: item.tag).flatMap({ badgePositionTags[$0] }) {
                let activePosition = currentBadge?.position ?? .topLeft
                item.state = activePosition == position ? .on : .off
            }

            // Update sound menu checkmarks (skip badge position and symbol
            // position/wrap items which also use String representedObject)
            let isBadgePositionItem = MenuTag(rawValue: item.tag).flatMap { badgePositionTags[$0] } != nil
            let isSymbolSectionItem = Self.symbolSectionTags.contains(item.tag)
            if item.representedObject is String, !isBadgePositionItem, !isSymbolSectionItem {
                let soundName = item.representedObject as? String ?? ""
                item.state = soundName == store.soundName ? .on : .off
            }
        }
    }

    private static let symbolSectionTags: Set<Int> = [
        MenuTag.symbolSectionSeparator.rawValue,
        MenuTag.symbolPositionHeader.rawValue,
        MenuTag.symbolPositionLeft.rawValue,
        MenuTag.symbolPositionRight.rawValue,
        MenuTag.symbolWrapHeader.rawValue,
        MenuTag.symbolWrapInside.rawValue,
        MenuTag.symbolWrapOutside.rawValue,
        MenuTag.symbolGapSeparator.rawValue,
        MenuTag.symbolGapRow.rawValue,
    ]

    /// Shows or hides the combined symbol position/wrap rows in the Label
    /// menu and refreshes their checkmarks.
    func updateSymbolSection(in labelMenu: NSMenu, visible: Bool) {
        for tag in Self.symbolSectionTags {
            labelMenu.item(withTag: tag)?.isHidden = !visible
        }
        guard visible else {
            return
        }
        let position = SpacePreferences.symbolPosition(
            forSpace: appState.currentSpace,
            display: appState.currentDisplayID,
            store: store
        ) ?? .left
        let wrap = SpacePreferences.symbolWrap(
            forSpace: appState.currentSpace,
            display: appState.currentDisplayID,
            store: store
        ) ?? .inside
        labelMenu.item(withTag: MenuTag.symbolPositionLeft.rawValue)?.state = position == .left ? .on : .off
        labelMenu.item(withTag: MenuTag.symbolPositionRight.rawValue)?.state = position == .right ? .on : .off
        labelMenu.item(withTag: MenuTag.symbolWrapInside.rawValue)?.state = wrap == .inside ? .on : .off
        labelMenu.item(withTag: MenuTag.symbolWrapOutside.rawValue)?.state = wrap == .outside ? .on : .off
        if let slider = labelMenu.item(withTag: MenuTag.symbolGapRow.rawValue)?.view as? SizeSlider {
            slider.currentSize = SpacePreferences.symbolGap(
                forSpace: appState.currentSpace,
                display: appState.currentDisplayID,
                store: store
            ) ?? Layout.defaultSymbolGapScale
        }
    }

    // MARK: - Sound Discovery

    private static let systemSounds = discoverSounds(in: URL(fileURLWithPath: "/System/Library/Sounds"))
    static let userSoundsDirectory =
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Sounds")

    private nonisolated static func discoverSounds(in directory: URL) -> [String] {
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

    /// Asynchronously rescans ~/Library/Sounds and rebuilds the sound submenu.
    /// Called when the main menu opens so results are ready before the user reaches the Sound submenu.
    func refreshUserSounds() {
        guard soundMenu != nil else {
            return
        }
        let directory = Self.userSoundsDirectory
        nonisolated(unsafe) let target = soundMenuTarget
        let selectedSound = store.soundName

        DispatchQueue.global(qos: .userInitiated).async {
            let sounds = Self.discoverSounds(in: directory)

            DispatchQueue.main.async { [weak self] in
                guard let self, let soundMenu else {
                    return
                }
                userSounds = sounds
                rebuildSoundMenuItems(
                    in: soundMenu,
                    target: target,
                    userSounds: sounds,
                    selectedSound: selectedSound
                )
            }
        }
    }

    private func rebuildSoundMenuItems(
        in menu: NSMenu, target: AnyObject?, userSounds: [String], selectedSound: String
    ) {
        menu.removeAllItems()

        let noneItem = NSMenuItem(
            title: Localization.soundNone,
            action: #selector(ActionHandler.selectSound(_:)),
            keyEquivalent: ""
        )
        noneItem.target = target
        noneItem.representedObject = ""
        noneItem.state = selectedSound.isEmpty ? .on : .off
        menu.addItem(noneItem)

        menu.addItem(.separator())

        let hasUserSounds = !userSounds.isEmpty

        if hasUserSounds {
            let header = NSMenuItem(title: Localization.soundUser, action: nil, keyEquivalent: "")
            header.isEnabled = false
            menu.addItem(header)

            for soundName in userSounds {
                let item = NSMenuItem(
                    title: soundName,
                    action: #selector(ActionHandler.selectSound(_:)),
                    keyEquivalent: ""
                )
                item.target = target
                item.representedObject = soundName
                item.state = selectedSound == soundName ? .on : .off
                menu.addItem(item)
            }

            menu.addItem(.separator())
            let systemHeader = NSMenuItem(title: Localization.soundSystem, action: nil, keyEquivalent: "")
            systemHeader.isEnabled = false
            menu.addItem(systemHeader)
        }

        for soundName in Self.systemSounds {
            let item = NSMenuItem(
                title: soundName,
                action: #selector(ActionHandler.selectSound(_:)),
                keyEquivalent: ""
            )
            item.target = target
            item.representedObject = soundName
            item.state = selectedSound == soundName ? .on : .off
            menu.addItem(item)
        }

        menu.addItem(.separator())

        let customItem = NSMenuItem(
            title: Localization.soundCustom,
            action: #selector(ActionHandler.openCustomSoundsFolder),
            keyEquivalent: ""
        )
        customItem.target = target
        menu.addItem(customItem)
    }

    // MARK: - Public Build Methods

    /// Builds the complete status menu, setting `target` for all @objc action items.
    func buildMenu(target: AnyObject, menuDelegate: NSMenuDelegate?, actionDelegate: MenuActionDelegate) -> NSMenu {
        let menu = NSMenu()

        configureVersionHeader(in: menu)
        configureColorMenuItem(in: menu, target: target, delegate: menuDelegate, actionDelegate: actionDelegate)
        configureStyleMenuItem(in: menu, target: target, delegate: menuDelegate, actionDelegate: actionDelegate)
        configureBadgeMenuItem(in: menu, target: target, delegate: menuDelegate, actionDelegate: actionDelegate)
        configureScrollMenuItem(in: menu, target: target, delegate: menuDelegate, actionDelegate: actionDelegate)
        configureSoundMenuItem(in: menu, target: target, delegate: menuDelegate)
        configureSizeMenuItem(in: menu, delegate: menuDelegate, actionDelegate: actionDelegate)
        configureOptionsMenuItems(in: menu, target: target)
        configureLaunchAtLoginMenuItem(in: menu, target: target)
        configureUpdateMenuItem(in: menu, target: target)
        configureSettingsMenuItem(in: menu, target: target)
        configureQuitMenuItem(in: menu)

        return menu
    }

    // MARK: - Space Picker Menu

    /// Builds the transient menu shown on left-click in single-icon mode: one
    /// item per Space, rendered exactly like its status bar icon, with a
    /// checkmark on the active Space.
    static func buildSpacePickerMenu(entries: [SpacePickerEntry], target: AnyObject) -> NSMenu {
        let menu = NSMenu()
        for entry in entries {
            let item = NSMenuItem(
                title: "",
                action: #selector(ActionHandler.switchToPickedSpace(_:)),
                keyEquivalent: ""
            )
            item.target = target
            item.image = entry.icon
            item.state = entry.isActive ? .on : .off
            item.representedObject = entry
            menu.addItem(item)
        }
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
        symbolLabelItem.image = NSImage(systemSymbolName: "burst.fill", accessibilityDescription: nil)
        symbolLabelItem.isHidden = true
        menu.addItem(symbolLabelItem)

        let symbolSwatchItem = makeColorSwatchItem(
            tag: .symbolColorSwatch,
            onColorSelected: { [weak actionDelegate] in actionDelegate?.symbolColorSelected($0) },
            onCustomColorRequested: { [weak actionDelegate] in actionDelegate?.customSymbolColorRequested() },
            onHoverStart: { [weak actionDelegate] in actionDelegate?.symbolColorHoverStarted(index: $0) },
            onHoverEnd: { [weak actionDelegate] in actionDelegate?.hoverEnded() }
        )
        symbolSwatchItem.isHidden = true
        menu.addItem(symbolSwatchItem)
    }

    private func addForegroundBackgroundSection(to menu: NSMenu, actionDelegate: MenuActionDelegate) {
        let foregroundLabel = NSMenuItem(title: Localization.labelNumberForeground, action: nil, keyEquivalent: "")
        foregroundLabel.isEnabled = false
        foregroundLabel.tag = MenuTag.foregroundLabel.rawValue
        foregroundLabel.image = NSImage(
            systemSymbolName: "square.2.layers.3d.top.filled",
            accessibilityDescription: nil
        )
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
        backgroundLabel.image = NSImage(
            systemSymbolName: "square.2.layers.3d.bottom.filled",
            accessibilityDescription: nil
        )
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
            title: Localization.actionCopyColorToAll,
            action: #selector(ActionHandler.copyColorsToAllSpaces),
            target: target,
            symbolName: "square.on.square",
            toolTip: Localization.tipCopyColorToAll
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

    // MARK: - Badge Menu

    private func configureBadgeMenuItem(
        in menu: NSMenu, target: AnyObject, delegate: NSMenuDelegate?, actionDelegate: MenuActionDelegate
    ) {
        let badgeMenu = NSMenu(title: Localization.menuBadge)
        badgeMenu.delegate = delegate

        // Badge header
        let badgeLabel = NSMenuItem(title: Localization.menuBadge, action: nil, keyEquivalent: "")
        badgeLabel.isEnabled = false
        badgeLabel.image = NSImage(systemSymbolName: "tag", accessibilityDescription: nil)
        badgeMenu.addItem(badgeLabel)

        // Character input
        let characterItem = NSMenuItem()
        characterItem.tag = MenuTag.badgeCharacterField.rawValue
        let badgeInput = BadgeInput()
        badgeInput.frame = NSRect(origin: .zero, size: badgeInput.intrinsicContentSize)
        badgeInput.onCharacterChanged = { [weak self, weak actionDelegate, weak badgeMenu] character in
            actionDelegate?.badgeCharacterChanged(character)
            guard let self, let badgeMenu else {
                return
            }
            let currentBadge = SpacePreferences.badge(
                forSpace: appState.currentSpace,
                display: appState.currentDisplayID,
                store: store
            )
            let badgePositionTags: [MenuTag: BadgePosition] = [
                .badgePositionTopLeft: .topLeft,
                .badgePositionTopRight: .topRight,
                .badgePositionBottomLeft: .bottomLeft,
                .badgePositionBottomRight: .bottomRight,
            ]
            for item in badgeMenu.items {
                if let position = badgePositionTags.first(where: { $0.key.rawValue == item.tag })?.value {
                    let activePosition = currentBadge?.position ?? .topLeft
                    item.state = activePosition == position ? .on : .off
                }
            }
        }
        characterItem.view = badgeInput
        badgeMenu.addItem(characterItem)

        badgeMenu.addItem(.separator())

        // Position header
        let positionLabel = NSMenuItem(title: Localization.labelBadgePosition, action: nil, keyEquivalent: "")
        positionLabel.isEnabled = false
        positionLabel.image = NSImage(
            systemSymbolName: "arrow.up.and.down.and.arrow.left.and.right",
            accessibilityDescription: nil
        )
        badgeMenu.addItem(positionLabel)

        // Position items
        let positions: [(BadgePosition, MenuTag, String, String)] = [
            (.topLeft, .badgePositionTopLeft, Localization.badgePositionTopLeft, "rectangle.inset.topleft.filled"),
            (.topRight, .badgePositionTopRight, Localization.badgePositionTopRight, "rectangle.inset.topright.filled"),
            (
                .bottomLeft,
                .badgePositionBottomLeft,
                Localization.badgePositionBottomLeft,
                "rectangle.inset.bottomleft.filled"
            ),
            (
                .bottomRight,
                .badgePositionBottomRight,
                Localization.badgePositionBottomRight,
                "rectangle.inset.bottomright.filled"
            ),
        ]

        for (position, tag, title, symbolName) in positions {
            let item = NSMenuItem(
                title: title,
                action: #selector(ActionHandler.badgePositionSelected(_:)),
                keyEquivalent: ""
            )
            item.target = target
            item.tag = tag.rawValue
            item.representedObject = position.rawValue
            item.image = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil)
            badgeMenu.addItem(item)
        }

        badgeMenu.addItem(.separator())

        addMenuItem(
            to: badgeMenu,
            title: Localization.actionCopyBadgeToAll,
            action: #selector(ActionHandler.copyBadgeToAllSpaces),
            target: target,
            symbolName: "square.on.square",
            toolTip: Localization.tipCopyBadgeToAll
        )
        addMenuItem(
            to: badgeMenu,
            title: Localization.actionResetBadgeToDefault,
            action: #selector(ActionHandler.resetBadgeToDefault),
            target: target,
            symbolName: "arrow.uturn.backward",
            toolTip: Localization.tipResetBadgeToDefault
        )

        let badgeMenuItem = NSMenuItem(title: Localization.menuBadge, action: nil, keyEquivalent: "")
        badgeMenuItem.tag = MenuTag.badgeMenuItem.rawValue
        badgeMenuItem.image = NSImage(systemSymbolName: "tag", accessibilityDescription: nil)
        badgeMenuItem.submenu = badgeMenu
        menu.addItem(badgeMenuItem)
    }

    // MARK: - Scroll Menu

    private func configureScrollMenuItem(
        in menu: NSMenu, target: AnyObject, delegate: NSMenuDelegate?, actionDelegate: MenuActionDelegate
    ) {
        let scrollMenu = NSMenu(title: Localization.menuScroll)
        scrollMenu.delegate = delegate

        let verticalLabel = NSMenuItem(title: Localization.labelVertical, action: nil, keyEquivalent: "")
        verticalLabel.isEnabled = false
        verticalLabel.image = NSImage(systemSymbolName: "arrow.up.and.down", accessibilityDescription: nil)
        scrollMenu.addItem(verticalLabel)
        addMenuItem(
            to: scrollMenu,
            title: Localization.toggleScrollEnabled,
            action: #selector(ActionHandler.toggleVerticalScroll),
            target: target,
            tag: .verticalScrollEnabled,
            symbolName: "arrow.up.arrow.down",
            toolTip: Localization.tipScrollEnabled
        )
        addMenuItem(
            to: scrollMenu,
            title: Localization.toggleScrollInverted,
            action: #selector(ActionHandler.toggleInvertVerticalScroll),
            target: target,
            tag: .invertVerticalScroll,
            symbolName: "arrow.uturn.up",
            toolTip: Localization.tipScrollInverted
        )

        scrollMenu.addItem(.separator())

        let horizontalLabel = NSMenuItem(title: Localization.labelHorizontal, action: nil, keyEquivalent: "")
        horizontalLabel.isEnabled = false
        horizontalLabel.image = NSImage(systemSymbolName: "arrow.left.and.right", accessibilityDescription: nil)
        scrollMenu.addItem(horizontalLabel)
        addMenuItem(
            to: scrollMenu,
            title: Localization.toggleScrollEnabled,
            action: #selector(ActionHandler.toggleHorizontalScroll),
            target: target,
            tag: .horizontalScrollEnabled,
            symbolName: "arrow.left.arrow.right",
            toolTip: Localization.tipScrollEnabled
        )
        addMenuItem(
            to: scrollMenu,
            title: Localization.toggleScrollInverted,
            action: #selector(ActionHandler.toggleInvertHorizontalScroll),
            target: target,
            tag: .invertHorizontalScroll,
            symbolName: "arrow.uturn.backward",
            toolTip: Localization.tipScrollInverted
        )

        scrollMenu.addItem(.separator())

        let behaviorLabel = NSMenuItem(title: Localization.labelBehavior, action: nil, keyEquivalent: "")
        behaviorLabel.isEnabled = false
        behaviorLabel.image = NSImage(systemSymbolName: "switch.2", accessibilityDescription: nil)
        scrollMenu.addItem(behaviorLabel)
        addMenuItem(
            to: scrollMenu,
            title: Localization.toggleScrollWrapAround,
            action: #selector(ActionHandler.toggleScrollWrapAround),
            target: target,
            tag: .scrollWrapAround,
            symbolName: "repeat",
            toolTip: Localization.tipScrollWrapAround
        )
        scrollMenu.addItem(.separator())

        let hapticItem = NSMenuItem()
        hapticItem.tag = MenuTag.scrollHapticIntensityRow.rawValue
        let hapticSlider = SizeSlider(
            title: Localization.toggleScrollHapticFeedback,
            initialSize: store.scrollHapticFeedback ? Double(store.scrollHapticIntensity) : 0,
            range: 0 ... Double(Layout.scrollHapticIntensityRange.upperBound),
            numberOfTickMarks: Layout.scrollHapticIntensityRange.upperBound + 1
        ) { HapticIntensityLabel.label(for: Int($0)) }
        hapticSlider.frame = NSRect(origin: .zero, size: hapticSlider.intrinsicContentSize)
        hapticSlider.onSizeChanged = { [weak actionDelegate] intensity in
            actionDelegate?.scrollHapticIntensityChanged(to: Int(intensity))
        }
        hapticItem.view = hapticSlider
        hapticItem.toolTip = Localization.tipScrollHapticFeedback
        scrollMenu.addItem(hapticItem)

        scrollMenu.addItem(.separator())

        let sensitivityItem = NSMenuItem()
        sensitivityItem.tag = MenuTag.scrollSensitivityRow.rawValue
        let sensitivitySlider = SizeSlider(
            title: Localization.labelSensitivity,
            initialSize: store.scrollSensitivity,
            range: Layout.scrollSensitivityRange
        )
        sensitivitySlider.frame = NSRect(origin: .zero, size: sensitivitySlider.intrinsicContentSize)
        sensitivitySlider.onSizeChanged = { [weak actionDelegate] scale in
            actionDelegate?.scrollSensitivityChanged(to: scale)
        }
        sensitivityItem.view = sensitivitySlider
        scrollMenu.addItem(sensitivityItem)

        let scrollMenuItem = NSMenuItem(title: Localization.menuScroll, action: nil, keyEquivalent: "")
        scrollMenuItem.tag = MenuTag.scrollMenuItem.rawValue
        scrollMenuItem.image = NSImage(systemSymbolName: "computermouse", accessibilityDescription: nil)
        scrollMenuItem.submenu = scrollMenu
        menu.addItem(scrollMenuItem)
    }

    // MARK: - Style Menu

    // swiftlint:disable:next function_body_length
    private func configureStyleMenuItem(
        in menu: NSMenu, target: AnyObject, delegate: NSMenuDelegate?, actionDelegate: MenuActionDelegate
    ) {
        let styleMenu = NSMenu(title: Localization.menuStyle)
        styleMenu.delegate = delegate

        // Number submenu (icon shapes)
        let iconMenu = createIconMenu(target: target, delegate: delegate, actionDelegate: actionDelegate)
        let iconMenuItem = NSMenuItem(title: Localization.menuNumber, action: nil, keyEquivalent: "")
        iconMenuItem.image = NSImage(systemSymbolName: "textformat.123", accessibilityDescription: nil)
        iconMenuItem.submenu = iconMenu
        styleMenu.addItem(iconMenuItem)

        // Label submenu (custom text labels)
        let labelMenu = createLabelMenu(target: target, delegate: delegate, actionDelegate: actionDelegate)
        self.labelMenu = labelMenu
        let labelMenuItem = NSMenuItem(title: Localization.menuLabel, action: nil, keyEquivalent: "")
        labelMenuItem.image = NSImage(systemSymbolName: "character.textbox", accessibilityDescription: nil)
        labelMenuItem.submenu = labelMenu
        labelMenuItem.tag = MenuTag.labelMenuItem.rawValue
        styleMenu.addItem(labelMenuItem)

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
            title: Localization.actionCopyStyleToAll,
            action: #selector(ActionHandler.copyStyleToAllSpaces),
            target: target,
            symbolName: "square.on.square",
            toolTip: Localization.tipCopyStyleToAll
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

    private func createIconMenu(
        target: AnyObject, delegate: NSMenuDelegate?, actionDelegate: MenuActionDelegate
    ) -> NSMenu {
        let iconMenu = NSMenu(title: Localization.menuNumber)
        iconMenu.delegate = delegate

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

    private static let labelStyles: [IconStyle] = [
        .pill, .pillOutline, .square, .squareOutline, .stroke, .transparent,
    ]

    private static func labelStyleTitle(for style: IconStyle) -> String? {
        switch style {
        case .pill:
            Localization.labelStylePill
        case .pillOutline:
            Localization.labelStylePillOutline
        case .square:
            Localization.labelStyleBox
        case .squareOutline:
            Localization.labelStyleBoxOutline
        default:
            nil
        }
    }

    private func createLabelMenu(
        target: AnyObject, delegate: NSMenuDelegate?, actionDelegate: MenuActionDelegate
    ) -> NSMenu {
        let labelMenu = NSMenu(title: Localization.menuLabel)
        labelMenu.delegate = delegate

        // Label header
        let labelHeader = NSMenuItem(title: Localization.menuLabel, action: nil, keyEquivalent: "")
        labelHeader.isEnabled = false
        labelHeader.image = NSImage(systemSymbolName: "character.textbox", accessibilityDescription: nil)
        labelMenu.addItem(labelHeader)

        // Label text input
        let inputItem = NSMenuItem()
        let labelInput = LabelInput()
        labelInput.frame = NSRect(origin: .zero, size: labelInput.intrinsicContentSize)
        labelInput.currentLabel = SpacePreferences.label(
            forSpace: appState.currentSpace,
            display: appState.currentDisplayID,
            store: store
        )
        labelInput.onLabelChanged = { [weak actionDelegate] label in
            actionDelegate?.labelChanged(label)
        }
        inputItem.view = labelInput
        inputItem.tag = MenuTag.labelInput.rawValue
        labelMenu.addItem(inputItem)
        self.labelInput = labelInput

        labelMenu.addItem(.separator())

        // Layout header
        let styleHeader = NSMenuItem(title: Localization.menuStyle, action: nil, keyEquivalent: "")
        styleHeader.isEnabled = false
        styleHeader.image = NSImage(systemSymbolName: "photo.artframe", accessibilityDescription: nil)
        labelMenu.addItem(styleHeader)

        // Style pickers (subset)
        let currentLabelStyle = SpacePreferences.labelStyle(
            forSpace: appState.currentSpace,
            display: appState.currentDisplayID,
            store: store
        ) ?? .square

        for style in Self.labelStyles {
            let item = NSMenuItem()
            let stylePicker = StylePicker(style: style)
            stylePicker.frame = NSRect(origin: .zero, size: stylePicker.intrinsicContentSize)
            stylePicker.titleOverride = Self.labelStyleTitle(for: style)
            stylePicker.isChecked = style == currentLabelStyle
            stylePicker.customColors = appState.currentColors
            stylePicker.darkMode = appState.darkModeEnabled
            stylePicker.previewNumber = appState.currentSpaceLabel == "?" ? "1" : appState.currentSpaceLabel
            stylePicker.sizeScale = store.sizeScale
            stylePicker.onSelected = { [weak stylePicker, weak actionDelegate] in
                actionDelegate?.labelStyleSelected(style, stylePicker: stylePicker)
            }
            stylePicker.onHoverStart = { [weak actionDelegate] hoveredStyle in
                actionDelegate?.labelStyleHoverStarted(hoveredStyle)
            }
            stylePicker.onHoverEnd = { [weak actionDelegate] in
                actionDelegate?.hoverEnded()
            }
            item.view = stylePicker
            item.representedObject = style
            labelMenu.addItem(item)
        }

        // Combined symbol+label section (visible only when both are set)
        let symbolSectionSeparator = NSMenuItem.separator()
        symbolSectionSeparator.tag = MenuTag.symbolSectionSeparator.rawValue
        labelMenu.addItem(symbolSectionSeparator)

        let positionHeader = NSMenuItem(title: Localization.labelSymbolPosition, action: nil, keyEquivalent: "")
        positionHeader.isEnabled = false
        positionHeader.tag = MenuTag.symbolPositionHeader.rawValue
        positionHeader.image = NSImage(systemSymbolName: "arrow.left.and.right", accessibilityDescription: nil)
        labelMenu.addItem(positionHeader)

        let positions: [(SymbolPosition, MenuTag, String, String, String)] = [
            (
                .left,
                .symbolPositionLeft,
                Localization.symbolPositionLeft,
                "arrow.left.to.line",
                Localization.tipSymbolPositionLeft
            ),
            (
                .right,
                .symbolPositionRight,
                Localization.symbolPositionRight,
                "arrow.right.to.line",
                Localization.tipSymbolPositionRight
            ),
        ]
        for (position, tag, title, symbolName, toolTip) in positions {
            let item = NSMenuItem(
                title: title,
                action: #selector(ActionHandler.symbolPositionSelected(_:)),
                keyEquivalent: ""
            )
            item.target = target
            item.tag = tag.rawValue
            item.representedObject = position.rawValue
            item.image = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil)
            item.toolTip = toolTip
            labelMenu.addItem(item)
        }

        let wrapHeader = NSMenuItem(title: Localization.labelSymbolWrap, action: nil, keyEquivalent: "")
        wrapHeader.isEnabled = false
        wrapHeader.tag = MenuTag.symbolWrapHeader.rawValue
        wrapHeader.image = NSImage(systemSymbolName: "rectangle.dashed", accessibilityDescription: nil)
        labelMenu.addItem(wrapHeader)

        let wraps: [(SymbolWrap, MenuTag, String, String, String)] = [
            (
                .inside,
                .symbolWrapInside,
                Localization.symbolWrapInside,
                "rectangle.inset.filled",
                Localization.tipSymbolWrapInside
            ),
            (
                .outside,
                .symbolWrapOutside,
                Localization.symbolWrapOutside,
                "rectangle.split.2x1",
                Localization.tipSymbolWrapOutside
            ),
        ]
        for (wrap, tag, title, symbolName, toolTip) in wraps {
            let item = NSMenuItem(
                title: title,
                action: #selector(ActionHandler.symbolWrapSelected(_:)),
                keyEquivalent: ""
            )
            item.target = target
            item.tag = tag.rawValue
            item.representedObject = wrap.rawValue
            item.image = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil)
            item.toolTip = toolTip
            labelMenu.addItem(item)
        }

        // Gap between symbol and label text
        let gapSeparator = NSMenuItem.separator()
        gapSeparator.tag = MenuTag.symbolGapSeparator.rawValue
        labelMenu.addItem(gapSeparator)

        let gapItem = NSMenuItem()
        gapItem.tag = MenuTag.symbolGapRow.rawValue
        let gapSlider = SizeSlider(
            title: Localization.menuPadding,
            initialSize: SpacePreferences.symbolGap(
                forSpace: appState.currentSpace,
                display: appState.currentDisplayID,
                store: store
            ) ?? Layout.defaultSymbolGapScale,
            range: Layout.symbolGapScaleRange
        )
        gapSlider.frame = NSRect(origin: .zero, size: gapSlider.intrinsicContentSize)
        gapSlider.onSizeChanged = { [weak actionDelegate] gap in
            actionDelegate?.symbolGapChanged(to: gap)
        }
        gapItem.view = gapSlider
        labelMenu.addItem(gapItem)

        let fontSepBefore = NSMenuItem.separator()
        fontSepBefore.tag = MenuTag.fontMenuItem.rawValue
        labelMenu.addItem(fontSepBefore)

        // showFontPanel uses responder chain (target: nil) because AppDelegate intercepts
        // it to configure the font manager before delegating to ActionHandler.
        addMenuItem(
            to: labelMenu,
            title: Localization.actionFont,
            action: #selector(ActionHandler.showFontPanel),
            target: nil,
            tag: .fontMenuItem,
            symbolName: "textformat",
            toolTip: Localization.tipFont
        )

        let fontSepAfter = NSMenuItem.separator()
        fontSepAfter.tag = MenuTag.fontMenuItem.rawValue
        labelMenu.addItem(fontSepAfter)

        addMenuItem(
            to: labelMenu,
            title: Localization.actionCopyLabelToAll,
            action: #selector(ActionHandler.copyLabelToAllSpaces),
            target: target,
            symbolName: "square.on.square",
            toolTip: Localization.tipCopyLabelToAll
        )
        addMenuItem(
            to: labelMenu,
            title: Localization.actionResetLabelToDefault,
            action: #selector(ActionHandler.resetLabelToDefault),
            target: target,
            symbolName: "arrow.uturn.backward",
            toolTip: Localization.tipResetLabelToDefault
        )

        return labelMenu
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
            let skinTone = item.containsEmoji ? self?.store.emojiPickerSkinTone : nil
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
        soundMenuTarget = target
        let soundMenu = NSMenu(title: Localization.menuSound)
        self.soundMenu = soundMenu
        soundMenu.delegate = delegate
        rebuildSoundMenuItems(
            in: soundMenu, target: target, userSounds: userSounds, selectedSound: store.soundName
        )
        let soundMenuItem = NSMenuItem(title: Localization.menuSound, action: nil, keyEquivalent: "")
        soundMenuItem.image = NSImage(systemSymbolName: "speaker.wave.2", accessibilityDescription: nil)
        soundMenuItem.submenu = soundMenu
        menu.addItem(soundMenuItem)
    }

    // MARK: - Size Menu

    private func configureSizeMenuItem(in menu: NSMenu, delegate: NSMenuDelegate?, actionDelegate: MenuActionDelegate) {
        let sizeMenu = NSMenu(title: Localization.menuSize)
        sizeMenu.delegate = delegate

        let sizeItem = NSMenuItem()
        sizeItem.tag = MenuTag.sizeRow.rawValue
        let sizeSlider = SizeSlider(
            title: Localization.menuIcon,
            initialSize: store.sizeScale,
            range: Layout.sizeScaleRange
        )
        sizeSlider.frame = NSRect(origin: .zero, size: sizeSlider.intrinsicContentSize)
        sizeSlider.onSizeChanged = { [weak actionDelegate] scale in
            actionDelegate?.sizeChanged(to: scale)
        }
        sizeItem.view = sizeSlider
        sizeMenu.addItem(sizeItem)

        sizeMenu.addItem(.separator())

        let paddingItem = NSMenuItem()
        paddingItem.tag = MenuTag.paddingRow.rawValue
        let paddingSlider = SizeSlider(
            title: Localization.menuPadding,
            initialSize: store.paddingScale,
            range: Layout.paddingScaleRange
        )
        paddingSlider.frame = NSRect(origin: .zero, size: paddingSlider.intrinsicContentSize)
        paddingSlider.onSizeChanged = { [weak actionDelegate] scale in
            actionDelegate?.paddingChanged(to: scale)
        }
        paddingItem.view = paddingSlider
        sizeMenu.addItem(paddingItem)

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
        .item(OptionItem(
            title: Localization.toggleUseFForFullscreenApps,
            action: #selector(ActionHandler.toggleUseFForFullscreenApps),
            tag: .fullscreenIconStyle,
            symbolName: "f.square",
            toolTip: Localization.tipUseFForFullscreenApps
        )),
        .separator,
        .item(OptionItem(
            title: Localization.actionSetDefaultStyle,
            action: #selector(ActionHandler.setDefaultStyle),
            symbolName: "square.and.arrow.down.on.square",
            toolTip: Localization.tipSetDefaultStyle
        )),
        .item(OptionItem(
            title: Localization.actionCopyToAll,
            action: #selector(ActionHandler.copyToAllSpaces),
            symbolName: "square.on.square",
            toolTip: Localization.tipCopyToAll
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

    // MARK: - Helpers

    /// Recursively searches for a menu item with the given tag across submenus.
    static func findMenuItem(withTag tag: Int, in menu: NSMenu) -> NSMenuItem? {
        for item in menu.items {
            if item.tag == tag {
                return item
            }
            if let submenu = item.submenu, let found = findMenuItem(withTag: tag, in: submenu) {
                return found
            }
        }
        return nil
    }
}
