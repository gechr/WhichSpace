import AppKit
import Defaults
import UniformTypeIdentifiers

/// Target for status-menu @objc actions, plus the AppKit panel and alert
/// flows the settings window delegates back to the app.
@MainActor
final class ActionHandler: NSObject {
    // MARK: - Dependencies

    private let appState: AppState
    private var launchAtLogin: LaunchAtLoginProvider
    private let confirmAction: ConfirmAction

    /// Callback invoked whenever an action needs the status-bar icon refreshed.
    let onStatusBarIconNeedsUpdate: (() -> Void)?

    /// Callback invoked to check for app updates (handled by AppDelegate's Sparkle integration).
    let onCheckForUpdates: (() -> Void)?

    /// Callback invoked to open the settings window (handled by AppDelegate's coordinator).
    let onOpenSettings: (() -> Void)?

    /// Callback invoked by a full reset to clear recorded hotkeys. Injected
    /// so tests never touch the live bindings, which the hotkey library
    /// stores in the host app's standard defaults domain.
    let onResetHotkeys: (() -> Void)?

    /// Callback invoked by a full reset to restore Sparkle's update settings.
    /// Injected because the updater persists them in its own SU* defaults,
    /// outside the store's key list.
    let onResetUpdaterSettings: (() -> Void)?

    /// Convenience accessor for the store via appState.
    private var store: DefaultsStore {
        appState.store
    }

    // MARK: - Initialization

    init(
        appState: AppState,
        launchAtLogin: LaunchAtLoginProvider,
        confirmAction: @escaping ConfirmAction = {
            ConfirmationAlert(message: $0, detail: $1, confirmTitle: $2, isDestructive: $3).runModal()
        },
        onStatusBarIconNeedsUpdate: (() -> Void)? = nil,
        onCheckForUpdates: (() -> Void)? = nil,
        onOpenSettings: (() -> Void)? = nil,
        onResetHotkeys: (() -> Void)? = nil,
        onResetUpdaterSettings: (() -> Void)? = nil
    ) {
        self.appState = appState
        self.launchAtLogin = launchAtLogin
        self.confirmAction = confirmAction
        self.onStatusBarIconNeedsUpdate = onStatusBarIconNeedsUpdate
        self.onCheckForUpdates = onCheckForUpdates
        self.onOpenSettings = onOpenSettings
        self.onResetHotkeys = onResetHotkeys
        self.onResetUpdaterSettings = onResetUpdaterSettings
        super.init()
    }

    // MARK: - Update Action

    @objc func checkForUpdates() {
        onCheckForUpdates?()
    }

    // MARK: - Settings Window

    @objc func openSettingsWindow() {
        onOpenSettings?()
    }

    // MARK: - Sounds

    /// Explains how custom sounds work and, if confirmed, opens ~/Library/Sounds in Finder.
    @objc func openCustomSoundsFolder() {
        let confirmed = InfoAlert(
            message: Localization.alertCustomSoundsTitle,
            detail: Localization.alertCustomSoundsDetail,
            primaryButtonTitle: Localization.buttonOpen,
            dismissButtonTitle: Localization.buttonCancel
        ).runModal()
        guard confirmed else {
            return
        }
        SoundCatalog.openUserSoundsFolder()
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
            try BackupManager.load(from: url, store: store, launchAtLogin: launchAtLogin) {
                HotkeyCenter.importBindings($0)
            }
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
            try BackupManager.export(
                to: url,
                store: store,
                launchAtLogin: launchAtLogin,
                hotkeys: HotkeyCenter.exportBindings()
            )
        } catch {
            showExportFailedAlert(detail: error.localizedDescription)
        }
    }

    /// Puts a bug-report summary on the pasteboard, ready to paste into a
    /// GitHub issue. Separate from the settings export, which carries Space
    /// labels and display identifiers that do not belong in a public thread.
    /// Returns whether the pasteboard accepted it.
    @discardableResult
    @objc func copyDiagnostics() -> Bool {
        !ScriptingHelpers.copyDiagnostics(appState: appState, store: store).isEmpty
    }

    // MARK: - Settings Reset

    /// Returns every preference to the value it ships with, per-Space styling
    /// and Launch at Login included, so the app is left as it was on a fresh
    /// install. Launch at Login is not a defaults key, so it is turned off
    /// alongside the store rather than by it, and Sparkle's update settings
    /// are restored through the updater for the same reason.
    @objc func resetAllSettings() {
        guard confirmAction(
            Localization.confirmResetSettings,
            Localization.detailResetSettings,
            Localization.buttonResetAll,
            true
        ) else {
            return
        }
        store.resetAll()
        launchAtLogin.isEnabled = false
        onResetHotkeys?()
        onResetUpdaterSettings?()
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

    // MARK: - Accessibility

    /// Requests accessibility permission for click-to-switch, showing the permission alert.
    /// Called when the user left-clicks the status bar and click-to-switch is not yet enabled.
    func requestAccessibilityForClickToSwitch() {
        showAccessibilityPermissionAlert()
    }

    // MARK: - Space Picker

    /// Switches to the Space chosen from the left-click picker menu.
    @objc func switchToPickedSpace(_ sender: NSMenuItem) {
        guard let entry = sender.representedObject as? SpacePickerEntry else {
            return
        }
        guard AXIsProcessTrusted() else {
            showAccessibilityPermissionAlert()
            return
        }
        // Fullscreen spaces don't have a targetSpace - activate the app instead
        if entry.targetSpace == nil {
            _ = SpaceSwitcher.activateAppOnSpace(entry.spaceID)
        } else {
            SpaceSwitcher.switchToSpace(id: entry.spaceID)
        }
    }

    /// Shows the accessibility permission alert; `onGranted` applies the
    /// setting that triggered the request once permission comes through.
    private func showAccessibilityPermissionAlert(
        onGranted: @escaping (DefaultsStore) -> Void = { $0.clickToSwitchSpaces = true }
    ) {
        let alert = NSAlert()
        alert.messageText = Localization.alertAccessibilityRequired
        alert.informativeText = String(format: Localization.alertAccessibilityDetail, AppInfo.appName)
        alert.alertStyle = .informational
        alert.addButton(withTitle: Localization.buttonContinue)
        alert.addButton(withTitle: Localization.buttonCancel)

        NSApp.activate(ignoringOtherApps: true)
        let response = alert.runModal()

        if response == .alertFirstButtonReturn {
            Accessibility.requestPermission { [weak self] in
                guard let self else {
                    return
                }
                onGranted(store)
            }
        }
    }
}
