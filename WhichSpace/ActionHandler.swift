import AppKit
import Defaults
import UniformTypeIdentifiers

/// Handles all menu-item @objc actions extracted from AppDelegate.
///
/// Each public method corresponds to a menu action. AppDelegate keeps thin
/// `@objc` forwarding stubs so that existing `#selector(AppDelegate.…)` references
/// (and the ~1 948 lines of tests that call through AppDelegate) continue to work.
@MainActor
final class ActionHandler {
    // MARK: - Dependencies

    private let appState: AppState
    private var launchAtLogin: LaunchAtLoginProvider
    private let alertFactory: ConfirmationAlertFactory

    private enum AccessibilityKeys {
        static let trustedCheckOptionPrompt = "AXTrustedCheckOptionPrompt"
    }

    /// Callback invoked whenever an action needs the status-bar icon refreshed.
    var onStatusBarIconNeedsUpdate: (() -> Void)?

    /// Callback invoked after the status-bar visibility may have changed.
    var onStatusBarVisibilityNeedsUpdate: (() -> Void)?

    /// Convenience accessor for the store via appState.
    private var store: DefaultsStore {
        appState.store
    }

    // MARK: - Initialization

    init(
        appState: AppState,
        alertFactory: ConfirmationAlertFactory,
        launchAtLogin: LaunchAtLoginProvider
    ) {
        self.appState = appState
        self.alertFactory = alertFactory
        self.launchAtLogin = launchAtLogin
    }

    // MARK: - Toggle Actions

    func toggleDimInactiveSpaces() {
        store.dimInactiveSpaces.toggle()
    }

    func toggleHideEmptySpaces() {
        store.hideEmptySpaces.toggle()
    }

    func toggleHideFullscreenApps() {
        store.hideFullscreenApps.toggle()
    }

    func toggleHideSingleSpace() {
        store.hideSingleSpace.toggle()
        onStatusBarVisibilityNeedsUpdate?()
    }

    func toggleLaunchAtLogin() {
        launchAtLogin.isEnabled.toggle()
    }

    func toggleShowAllDisplays() {
        store.showAllDisplays.toggle()
        if store.showAllDisplays {
            store.showAllSpaces = false
        }
    }

    func toggleShowAllSpaces() {
        store.showAllSpaces.toggle()
        if store.showAllSpaces {
            store.showAllDisplays = false
        }
    }

    func toggleClickToSwitchSpaces() {
        if !store.clickToSwitchSpaces, !AXIsProcessTrusted() {
            showAccessibilityPermissionAlert()
            return
        }
        store.clickToSwitchSpaces.toggle()
    }

    func toggleLocalSpaceNumbers() {
        store.localSpaceNumbers.toggle()
    }

    func toggleUniqueIconsPerDisplay() {
        store.uniqueIconsPerDisplay.toggle()
    }

    // MARK: - Sound Action

    func selectSound(_ sender: NSMenuItem) {
        guard let soundName = sender.representedObject as? String else {
            return
        }
        store.soundName = soundName
    }

    // MARK: - Color Actions

    func invertColors() {
        guard appState.currentSpace > 0 else {
            return
        }
        let defaults = IconColors.filledColors(darkMode: appState.darkModeEnabled)
        let foreground = appState.currentColors?.foregroundColor ?? defaults.foreground
        let background = appState.currentColors?.backgroundColor ?? defaults.background
        SpacePreferences.setColors(
            SpaceColors(foreground: background, background: foreground),
            forSpace: appState.currentSpace,
            display: appState.currentDisplayID,
            store: store
        )
        onStatusBarIconNeedsUpdate?()
    }

    func applyColorsToAllSpaces() {
        guard appState.currentSpace > 0 else {
            return
        }

        let confirmed = alertFactory.makeAlert(
            message: Localization.confirmApplyColorToAll,
            detail: Localization.detailApplyColorToAll,
            confirmTitle: Localization.buttonOK,
            isDestructive: false
        )
        .runModal()

        guard confirmed else {
            return
        }

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
        onStatusBarIconNeedsUpdate?()
    }

    func resetColorToDefault() {
        let confirmed = alertFactory.makeAlert(
            message: Localization.confirmResetColor,
            detail: Localization.detailResetColor,
            confirmTitle: Localization.buttonReset,
            isDestructive: true
        )
        .runModal()

        guard confirmed else {
            return
        }

        SpacePreferences.clearColors(forSpace: appState.currentSpace, display: appState.currentDisplayID, store: store)
        SpacePreferences.clearSkinTone(
            forSpace: appState.currentSpace,
            display: appState.currentDisplayID,
            store: store
        )
        store.separatorColor = nil
        onStatusBarIconNeedsUpdate?()
    }

    // MARK: - Style Actions

    func applyStyleToAllSpaces() {
        guard appState.currentSpace > 0 else {
            return
        }

        let confirmed = alertFactory.makeAlert(
            message: Localization.confirmApplyStyleToAll,
            detail: Localization.detailApplyStyleToAll,
            confirmTitle: Localization.buttonOK,
            isDestructive: false
        )
        .runModal()

        guard confirmed else {
            return
        }

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
        onStatusBarIconNeedsUpdate?()
    }

    func resetStyleToDefault() {
        guard appState.currentSpace > 0 else {
            return
        }

        let confirmed = alertFactory.makeAlert(
            message: Localization.confirmResetStyle,
            detail: Localization.detailResetStyle,
            confirmTitle: Localization.buttonReset,
            isDestructive: true
        )
        .runModal()

        guard confirmed else {
            return
        }

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
        onStatusBarIconNeedsUpdate?()
    }

    // MARK: - Apply / Reset All Actions

    // swiftlint:disable:next function_body_length
    func applyToAllSpaces() {
        guard appState.currentSpace > 0 else {
            return
        }

        let confirmed = alertFactory.makeAlert(
            message: Localization.confirmApplyToAll,
            detail: Localization.detailApplyToAll,
            confirmTitle: Localization.buttonOK,
            isDestructive: false
        )
        .runModal()

        guard confirmed else {
            return
        }

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
        onStatusBarIconNeedsUpdate?()
    }

    func resetSpaceToDefault() {
        guard appState.currentSpace > 0 else {
            return
        }

        let confirmed = alertFactory.makeAlert(
            message: Localization.confirmResetSpace,
            detail: Localization.detailResetSpace,
            confirmTitle: Localization.buttonReset,
            isDestructive: true
        )
        .runModal()

        guard confirmed else {
            return
        }

        SpacePreferences.clearColors(forSpace: appState.currentSpace, display: appState.currentDisplayID, store: store)
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
        onStatusBarIconNeedsUpdate?()
    }

    func resetAllSpacesToDefault() {
        let confirmed = alertFactory.makeAlert(
            message: Localization.confirmResetAllSpaces,
            detail: Localization.detailResetAllSpaces,
            confirmTitle: Localization.buttonResetAll,
            isDestructive: true
        )
        .runModal()

        guard confirmed else {
            return
        }

        SpacePreferences.clearAll(store: store)
        store.sizeScale = Layout.defaultSizeScale
        store.soundName = ""
        store.separatorColor = nil
        onStatusBarIconNeedsUpdate?()
    }

    // MARK: - Font Actions

    func showFontPanel() {
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

    func changeFont(_ sender: Any?) {
        guard appState.currentSpace > 0 else {
            return
        }

        guard let fontManager = sender as? NSFontManager else {
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

    func resetFontToDefault() {
        guard appState.currentSpace > 0 else {
            return
        }

        let confirmed = alertFactory.makeAlert(
            message: Localization.confirmResetFont,
            detail: Localization.detailResetFont,
            confirmTitle: Localization.buttonReset,
            isDestructive: true
        )
        .runModal()

        guard confirmed else {
            return
        }

        SpacePreferences.clearFont(
            forSpace: appState.currentSpace,
            display: appState.currentDisplayID,
            store: store
        )
        onStatusBarIconNeedsUpdate?()
    }

    // MARK: - Settings Import/Export

    func importSettings() {
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
            try BackupManager.load(from: url, store: store)
            onStatusBarIconNeedsUpdate?()
        } catch {
            showImportFailedAlert(detail: error.localizedDescription)
        }
    }

    func exportSettings() {
        let savePanel = NSSavePanel()
        savePanel.allowedContentTypes = [.json]
        savePanel.nameFieldStringValue = BackupManager.defaultFilename

        NSApp.activate(ignoringOtherApps: true)
        let response = savePanel.runModal()

        guard response == .OK, let url = savePanel.url else {
            return
        }

        do {
            try BackupManager.export(to: url, store: store)
        } catch {
            showExportFailedAlert(detail: error.localizedDescription)
        }
    }

    // MARK: - Color Helpers (used by callbacks)

    func setForegroundColor(_ color: NSColor) {
        guard appState.currentSpace > 0 else {
            return
        }
        let defaults = IconColors.filledColors(darkMode: appState.darkModeEnabled)
        let background = appState.currentColors?.backgroundColor ?? defaults.background
        SpacePreferences.setColors(
            SpaceColors(foreground: color, background: background),
            forSpace: appState.currentSpace,
            display: appState.currentDisplayID,
            store: store
        )
        onStatusBarIconNeedsUpdate?()
    }

    func setBackgroundColor(_ color: NSColor) {
        guard appState.currentSpace > 0 else {
            return
        }
        let defaults = IconColors.filledColors(darkMode: appState.darkModeEnabled)
        let foreground = appState.currentColors?.foregroundColor ?? defaults.foreground
        SpacePreferences.setColors(
            SpaceColors(foreground: foreground, background: color),
            forSpace: appState.currentSpace,
            display: appState.currentDisplayID,
            store: store
        )
        onStatusBarIconNeedsUpdate?()
    }

    // MARK: - Private Alert Helpers

    private var appName: String {
        Bundle.main.infoDictionary?["CFBundleName"] as? String ?? "WhichSpace"
    }

    private func showImportFailedAlert(detail: String? = nil) {
        let alert = NSAlert()
        alert.messageText = Localization.alertImportFailed
        if let detail {
            alert.informativeText = detail
        }
        alert.alertStyle = .warning
        alert.addButton(withTitle: Localization.buttonOK)
        alert.runModal()
    }

    private func showExportFailedAlert(detail: String? = nil) {
        let alert = NSAlert()
        alert.messageText = "Export Failed"
        if let detail {
            alert.informativeText = detail
        }
        alert.alertStyle = .warning
        alert.addButton(withTitle: Localization.buttonOK)
        alert.runModal()
    }

    private func showAccessibilityPermissionAlert() {
        let alert = NSAlert()
        alert.messageText = "Permission Required"
        // swiftformat:disable all
        alert.informativeText = """
        This feature requires Accessibility permission to simulate keyboard shortcuts.

        After clicking Continue, macOS will prompt you for permission. Click "Open System Settings", then find \(appName) in the list and enable it.
        """
        // swiftformat:enable all
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Continue")
        alert.addButton(withTitle: "Cancel")

        NSApp.activate(ignoringOtherApps: true)
        let response = alert.runModal()

        if response == .alertFirstButtonReturn {
            Task {
                await SpaceSwitcher.resetAccessibilityPermission()
                let options = [AccessibilityKeys.trustedCheckOptionPrompt: true] as CFDictionary
                _ = AXIsProcessTrustedWithOptions(options)
                store.clickToSwitchSpaces = true
            }
        }
    }
}
