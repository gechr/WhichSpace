import AppKit
import Defaults
import UniformTypeIdentifiers

/// Handles all menu-item @objc actions.
///
/// ActionHandler is the direct target for menu item selectors, eliminating the
/// need for forwarding stubs in AppDelegate.
@MainActor
final class ActionHandler: NSObject {
    // MARK: - Dependencies

    private let appState: AppState
    private var launchAtLogin: LaunchAtLoginProvider
    private let confirmAction: ConfirmAction

    private enum AccessibilityKeys {
        static let trustedCheckOptionPrompt = "AXTrustedCheckOptionPrompt"
    }

    /// Callback invoked whenever an action needs the status-bar icon refreshed.
    let onStatusBarIconNeedsUpdate: (() -> Void)?

    /// Callback invoked after the status-bar visibility may have changed.
    let onStatusBarVisibilityNeedsUpdate: (() -> Void)?

    /// Callback invoked to check for app updates (handled by AppDelegate's Sparkle integration).
    let onCheckForUpdates: (() -> Void)?

    /// Convenience accessor for the store via appState.
    private var store: DefaultsStore {
        appState.store
    }

    // MARK: - Initialization

    init(
        appState: AppState,
        confirmAction: @escaping ConfirmAction,
        launchAtLogin: LaunchAtLoginProvider,
        onStatusBarIconNeedsUpdate: (() -> Void)? = nil,
        onStatusBarVisibilityNeedsUpdate: (() -> Void)? = nil,
        onCheckForUpdates: (() -> Void)? = nil
    ) {
        self.appState = appState
        self.confirmAction = confirmAction
        self.launchAtLogin = launchAtLogin
        self.onStatusBarIconNeedsUpdate = onStatusBarIconNeedsUpdate
        self.onStatusBarVisibilityNeedsUpdate = onStatusBarVisibilityNeedsUpdate
        self.onCheckForUpdates = onCheckForUpdates
        super.init()
    }

    // MARK: - Toggle Actions

    @objc func toggleDimInactiveSpaces() {
        store.dimInactiveSpaces.toggle()
    }

    @objc func toggleHideEmptySpaces() {
        store.hideEmptySpaces.toggle()
    }

    @objc func toggleHideFullscreenApps() {
        store.hideFullscreenApps.toggle()
    }

    @objc func toggleHideSingleSpace() {
        store.hideSingleSpace.toggle()
        onStatusBarVisibilityNeedsUpdate?()
    }

    @objc func toggleLaunchAtLogin() {
        launchAtLogin.isEnabled.toggle()
    }

    @objc func toggleShowAllDisplays() {
        SettingsConstraints.setShowAllDisplays(!store.showAllDisplays, store: store)
    }

    @objc func toggleShowAllSpaces() {
        SettingsConstraints.setShowAllSpaces(!store.showAllSpaces, store: store)
    }

    @objc func toggleClickToSwitchSpaces() {
        let newValue = !store.clickToSwitchSpaces
        if !SettingsConstraints.setClickToSwitchSpaces(newValue, store: store) {
            NSLog("ActionHandler: accessibility permission denied for clickToSwitchSpaces")
            showAccessibilityPermissionAlert()
        }
    }

    @objc func toggleLocalSpaceNumbers() {
        store.localSpaceNumbers.toggle()
    }

    @objc func toggleUniqueIconsPerDisplay() {
        store.uniqueIconsPerDisplay.toggle()
    }

    // MARK: - Update Action

    @objc func checkForUpdates() {
        onCheckForUpdates?()
    }

    // MARK: - Sound Action

    @objc func selectSound(_ sender: NSMenuItem) {
        guard let soundName = sender.representedObject as? String else {
            NSLog("ActionHandler: selectSound sender has unexpected representedObject type")
            return
        }
        store.soundName = soundName
    }

    // MARK: - Confirmation Helper

    /// Shows a confirmation alert and, if confirmed, runs the given action then refreshes the status-bar icon.
    ///
    /// - Parameters:
    ///   - requiresSpace: When `true`, returns immediately if no space is selected.
    ///   - message: The alert's message text.
    ///   - detail: The alert's informative text.
    ///   - confirmTitle: Title for the confirm button.
    ///   - isDestructive: Whether the action is destructive (colours the button accordingly).
    ///   - action: The work to perform after the user confirms.
    private func withConfirmation(
        requiresSpace: Bool = true,
        message: String,
        detail: String,
        confirmTitle: String,
        isDestructive: Bool,
        action: () -> Void
    ) {
        if requiresSpace {
            guard appState.currentSpace > 0 else {
                return
            }
        }

        guard confirmAction(message, detail, confirmTitle, isDestructive) else {
            return
        }

        action()
        onStatusBarIconNeedsUpdate?()
    }

    // MARK: - Color Actions

    @objc func invertColors() {
        guard appState.currentSpace > 0 else {
            return
        }
        let defaults = IconColors.filledColors(darkMode: appState.darkModeEnabled)
        let foreground = appState.currentColors?.foreground ?? defaults.foreground
        let background = appState.currentColors?.background ?? defaults.background
        SpacePreferences.setColors(
            SpaceColors(foreground: background, background: foreground),
            forSpace: appState.currentSpace,
            display: appState.currentDisplayID,
            store: store
        )
        onStatusBarIconNeedsUpdate?()
    }

    @objc func applyColorsToAllSpaces() {
        withConfirmation(
            message: Localization.confirmApplyColorToAll,
            detail: Localization.detailApplyColorToAll,
            confirmTitle: Localization.buttonOK,
            isDestructive: false
        ) {
            let colors = appState.currentColors
            let skinTone = SpacePreferences.skinTone(
                forSpace: appState.currentSpace,
                display: appState.currentDisplayID,
                store: store
            )
            let display = appState.currentDisplayID
            for space in appState.getAllSpaceIndices() {
                if let colors {
                    SpacePreferences.setColors(colors, forSpace: space, display: display, store: store)
                } else {
                    SpacePreferences.clearColors(forSpace: space, display: display, store: store)
                }
                if let skinTone {
                    SpacePreferences.setSkinTone(skinTone, forSpace: space, display: display, store: store)
                } else {
                    SpacePreferences.clearSkinTone(forSpace: space, display: display, store: store)
                }
            }
        }
    }

    @objc func resetColorToDefault() {
        withConfirmation(
            requiresSpace: false,
            message: Localization.confirmResetColor,
            detail: Localization.detailResetColor,
            confirmTitle: Localization.buttonReset,
            isDestructive: true
        ) {
            SpacePreferences.clearColors(
                forSpace: appState.currentSpace,
                display: appState.currentDisplayID,
                store: store
            )
            SpacePreferences.clearSkinTone(
                forSpace: appState.currentSpace,
                display: appState.currentDisplayID,
                store: store
            )
            store.separatorColor = nil
        }
    }

    // MARK: - Style Actions

    @objc func applyStyleToAllSpaces() {
        withConfirmation(
            message: Localization.confirmApplyStyleToAll,
            detail: Localization.detailApplyStyleToAll,
            confirmTitle: Localization.buttonOK,
            isDestructive: false
        ) {
            let style = appState.currentIconStyle
            let symbol = appState.currentSymbol
            let display = appState.currentDisplayID
            for space in appState.getAllSpaceIndices() {
                SpacePreferences.setIconStyle(style, forSpace: space, display: display, store: store)
                if let symbol {
                    SpacePreferences.setSymbol(symbol, forSpace: space, display: display, store: store)
                } else {
                    SpacePreferences.clearSymbol(forSpace: space, display: display, store: store)
                }
            }
        }
    }

    @objc func resetStyleToDefault() {
        withConfirmation(
            message: Localization.confirmResetStyle,
            detail: Localization.detailResetStyle,
            confirmTitle: Localization.buttonReset,
            isDestructive: true
        ) {
            SpacePreferences.clearIconStyle(
                forSpace: appState.currentSpace,
                display: appState.currentDisplayID,
                store: store
            )
            SpacePreferences.clearSymbol(
                forSpace: appState.currentSpace,
                display: appState.currentDisplayID,
                store: store
            )
        }
    }

    // MARK: - Apply / Reset All Actions

    // swiftlint:disable:next function_body_length
    @objc func applyToAllSpaces() {
        withConfirmation(
            message: Localization.confirmApplyToAll,
            detail: Localization.detailApplyToAll,
            confirmTitle: Localization.buttonOK,
            isDestructive: false
        ) {
            let style = appState.currentIconStyle
            let colors = appState.currentColors
            let symbol = appState.currentSymbol
            let font = appState.currentFont
            let skinTone = SpacePreferences.skinTone(
                forSpace: appState.currentSpace,
                display: appState.currentDisplayID,
                store: store
            )
            let display = appState.currentDisplayID
            for space in appState.getAllSpaceIndices() {
                SpacePreferences.setIconStyle(style, forSpace: space, display: display, store: store)
                if let symbol {
                    SpacePreferences.setSymbol(symbol, forSpace: space, display: display, store: store)
                } else {
                    SpacePreferences.clearSymbol(forSpace: space, display: display, store: store)
                }
                if let colors {
                    SpacePreferences.setColors(colors, forSpace: space, display: display, store: store)
                } else {
                    SpacePreferences.clearColors(forSpace: space, display: display, store: store)
                }
                if let font {
                    SpacePreferences.setFont(SpaceFont(font: font), forSpace: space, display: display, store: store)
                } else {
                    SpacePreferences.clearFont(forSpace: space, display: display, store: store)
                }
                if let skinTone {
                    SpacePreferences.setSkinTone(skinTone, forSpace: space, display: display, store: store)
                } else {
                    SpacePreferences.clearSkinTone(forSpace: space, display: display, store: store)
                }
            }
        }
    }

    @objc func resetSpaceToDefault() {
        withConfirmation(
            message: Localization.confirmResetSpace,
            detail: Localization.detailResetSpace,
            confirmTitle: Localization.buttonReset,
            isDestructive: true
        ) {
            SpacePreferences.clearColors(
                forSpace: appState.currentSpace,
                display: appState.currentDisplayID,
                store: store
            )
            SpacePreferences.clearIconStyle(
                forSpace: appState.currentSpace,
                display: appState.currentDisplayID,
                store: store
            )
            SpacePreferences.clearFont(
                forSpace: appState.currentSpace,
                display: appState.currentDisplayID,
                store: store
            )
            SpacePreferences.clearSymbol(
                forSpace: appState.currentSpace,
                display: appState.currentDisplayID,
                store: store
            )
            SpacePreferences.clearSkinTone(
                forSpace: appState.currentSpace,
                display: appState.currentDisplayID,
                store: store
            )
        }
    }

    @objc func resetAllSpacesToDefault() {
        withConfirmation(
            requiresSpace: false,
            message: Localization.confirmResetAllSpaces,
            detail: Localization.detailResetAllSpaces,
            confirmTitle: Localization.buttonResetAll,
            isDestructive: true
        ) {
            SpacePreferences.clearAll(store: store)
            store.sizeScale = Layout.defaultSizeScale
            store.soundName = ""
            store.separatorColor = nil
        }
    }

    // MARK: - Font Actions

    @objc func showFontPanel() {
        NSApp.activate(ignoringOtherApps: true)

        // Note: NSFontManager target/action are set by AppDelegate since
        // changeFont(_:) is dispatched through the responder chain.
        // This method only handles the panel presentation.

        let fontPanel = NSFontPanel.shared
        if let currentFont = appState.currentFont {
            fontPanel.setPanelFont(currentFont, isMultiple: false)
        } else {
            let defaultFont = NSFont.boldSystemFont(ofSize: Layout.baseFontSize)
            fontPanel.setPanelFont(defaultFont, isMultiple: false)
        }

        if let screen = NSScreen.main {
            let screenFrame = screen.visibleFrame
            let panelFrame = fontPanel.frame
            let centerX = screenFrame.midX - panelFrame.width / 2
            let centerY = screenFrame.midY - panelFrame.height / 2
            fontPanel.setFrameOrigin(NSPoint(x: centerX, y: centerY))
        }

        fontPanel.makeKeyAndOrderFront(nil)
    }

    @objc func changeFont(_ sender: Any?) {
        guard appState.currentSpace > 0 else {
            NSLog("ActionHandler: changeFont ignored; currentSpace is 0")
            return
        }

        guard let fontManager = sender as? NSFontManager else {
            NSLog("ActionHandler: changeFont sender is not NSFontManager")
            return
        }

        let currentFont = appState.currentFont ?? NSFont.boldSystemFont(ofSize: Layout.baseFontSize)
        let newFont = fontManager.convert(currentFont)

        SpacePreferences.setFont(
            SpaceFont(font: newFont),
            forSpace: appState.currentSpace,
            display: appState.currentDisplayID,
            store: store
        )
        onStatusBarIconNeedsUpdate?()
    }

    @objc func resetFontToDefault() {
        withConfirmation(
            message: Localization.confirmResetFont,
            detail: Localization.detailResetFont,
            confirmTitle: Localization.buttonReset,
            isDestructive: true
        ) {
            SpacePreferences.clearFont(
                forSpace: appState.currentSpace,
                display: appState.currentDisplayID,
                store: store
            )
        }
    }

    // MARK: - Settings Import/Export

    @objc func importSettings() {
        let openPanel = NSOpenPanel()
        openPanel.allowedContentTypes = [.json]
        openPanel.allowsMultipleSelection = false
        openPanel.canChooseDirectories = false

        NSApp.activate(ignoringOtherApps: true)
        let response = openPanel.runModal()

        guard response == .OK, let url = openPanel.url else {
            return
        }

        do {
            try BackupManager.load(from: url, store: store, launchAtLogin: launchAtLogin)
            onStatusBarIconNeedsUpdate?()
        } catch {
            showImportFailedAlert(detail: error.localizedDescription)
        }
    }

    @objc func exportSettings() {
        let savePanel = NSSavePanel()
        savePanel.allowedContentTypes = [.json]
        savePanel.nameFieldStringValue = BackupManager.defaultFilename

        NSApp.activate(ignoringOtherApps: true)
        let response = savePanel.runModal()

        guard response == .OK, let url = savePanel.url else {
            return
        }

        do {
            try BackupManager.export(to: url, store: store, launchAtLogin: launchAtLogin)
        } catch {
            showExportFailedAlert(detail: error.localizedDescription)
        }
    }

    // MARK: - Color Helpers (used by callbacks)

    func setColor(_ color: NSColor, isForeground: Bool) {
        guard appState.currentSpace > 0 else {
            return
        }
        let defaults = IconColors.filledColors(darkMode: appState.darkModeEnabled)
        let foreground = isForeground ? color : (appState.currentColors?.foreground ?? defaults.foreground)
        let background = isForeground ? (appState.currentColors?.background ?? defaults.background) : color
        SpacePreferences.setColors(
            SpaceColors(foreground: foreground, background: background),
            forSpace: appState.currentSpace,
            display: appState.currentDisplayID,
            store: store
        )
        onStatusBarIconNeedsUpdate?()
    }

    func setSeparatorColor(_ color: NSColor) {
        store.separatorColor = color
        onStatusBarIconNeedsUpdate?()
    }

    // MARK: - Style Selection

    func selectIconStyle(_ style: IconStyle, stylePicker: StylePicker?) {
        guard appState.currentSpace > 0 else {
            return
        }

        // Clear SF Symbol to switch to number mode
        SpacePreferences.clearSymbol(
            forSpace: appState.currentSpace,
            display: appState.currentDisplayID,
            store: store
        )
        SpacePreferences.setIconStyle(
            style,
            forSpace: appState.currentSpace,
            display: appState.currentDisplayID,
            store: store
        )

        // Update checkmarks in all row views
        if let menu = stylePicker?.enclosingMenuItem?.menu {
            for item in menu.items {
                if let view = item.view as? StylePicker {
                    view.isChecked = item.representedObject as? IconStyle == style
                }
            }
        }

        onStatusBarIconNeedsUpdate?()
    }

    // MARK: - Symbol Selection

    func setSymbol(_ symbol: String?) {
        guard appState.currentSpace > 0 else {
            return
        }
        SpacePreferences.setSymbol(
            symbol,
            forSpace: appState.currentSpace,
            display: appState.currentDisplayID,
            store: store
        )
        // When setting an emoji, also set the per-space skin tone to match the current global picker tone
        if let symbol, symbol.containsEmoji {
            SpacePreferences.setSkinTone(
                Defaults[.emojiPickerSkinTone],
                forSpace: appState.currentSpace,
                display: appState.currentDisplayID,
                store: store
            )
        }
        onStatusBarIconNeedsUpdate?()
    }

    private func showImportFailedAlert(detail: String? = nil) {
        showErrorAlert(message: Localization.alertImportFailed, detail: detail)
    }

    private func showExportFailedAlert(detail: String? = nil) {
        showErrorAlert(message: Localization.alertExportFailed, detail: detail)
    }

    private func showErrorAlert(message: String, detail: String? = nil) {
        let alert = NSAlert()
        alert.messageText = message
        if let detail {
            alert.informativeText = detail
        }
        alert.alertStyle = .warning
        alert.addButton(withTitle: Localization.buttonOK)
        alert.runModal()
    }

    private func showAccessibilityPermissionAlert() {
        let alert = NSAlert()
        alert.messageText = Localization.alertAccessibilityRequired
        alert.informativeText = Localization.alertAccessibilityDetail
        alert.alertStyle = .informational
        alert.addButton(withTitle: Localization.buttonContinue)
        alert.addButton(withTitle: Localization.buttonCancel)

        NSApp.activate(ignoringOtherApps: true)
        let response = alert.runModal()

        if response == .alertFirstButtonReturn {
            SpaceSwitcher.resetAccessibilityPermission()
            let options = [AccessibilityKeys.trustedCheckOptionPrompt: true] as CFDictionary
            _ = AXIsProcessTrustedWithOptions(options)
            pollForAccessibilityPermission()
        }
    }

    private func pollForAccessibilityPermission(remaining: Int = 60) {
        guard remaining > 0 else {
            NSLog("ActionHandler: accessibility permission polling timed out")
            return
        }
        Timer.scheduledTimer(withTimeInterval: 0.5, repeats: false) { [weak self] _ in
            if AXIsProcessTrusted() {
                Task { @MainActor [weak self] in
                    self?.store.clickToSwitchSpaces = true
                }
            } else {
                Task { @MainActor [weak self] in
                    self?.pollForAccessibilityPermission(remaining: remaining - 1)
                }
            }
        }
    }
}
