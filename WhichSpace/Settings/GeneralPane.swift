import AppKit
import Settings
import Sparkle
import SwiftUI

/// The General settings pane: startup, updates, and configuration backup.
/// Container-agnostic - it knows nothing about the window chrome hosting it.
struct GeneralPane: View {
    let model: SettingsModel
    /// Sparkle persists these settings itself (SU* defaults), so the toggles
    /// bind straight to the updater rather than `DefaultsStore`
    let updater: SPUUpdater?
    let onCheckForUpdates: () -> Void
    let onImportSettings: () -> Void
    let onExportSettings: () -> Void

    /// Sparkle state is not observable; bumped when the check toggle flips
    /// so dependent rows re-read the updater
    @State private var updaterTick = 0

    var body: some View {
        let _ = updaterTick
        SettingsForm {
            SettingsSection {
                SettingsToggleRow(
                    title: Localization.toggleLaunchAtLogin,
                    isOn: model.launchAtLoginBinding,
                    icon: "sunrise",
                    subtitle: String(format: Localization.tipLaunchAtLogin, AppInfo.appName),
                    anchor: .launchAtLogin
                )
            }
            SettingsSection {
                SettingsToggleRow(
                    title: Localization.toggleAutoCheckUpdates,
                    isOn: Binding(
                        get: { updater?.automaticallyChecksForUpdates ?? false },
                        set: {
                            updater?.automaticallyChecksForUpdates = $0
                            updaterTick += 1
                        }
                    ),
                    icon: "arrow.triangle.2.circlepath",
                    anchor: .autoCheckUpdates
                )
                SettingsRowDivider()
                SettingsToggleRow(
                    title: Localization.toggleAutoInstallUpdates,
                    isOn: Binding(
                        get: { updater?.automaticallyDownloadsUpdates ?? false },
                        set: { updater?.automaticallyDownloadsUpdates = $0 }
                    ),
                    icon: "square.and.arrow.down",
                    indented: true,
                    disabled: !(updater?.automaticallyChecksForUpdates ?? false),
                    anchor: .autoInstallUpdates
                )
                SettingsRowDivider()
                SettingsRow(anchor: .checkForUpdates) {
                    EmptyView()
                } control: {
                    Button(Localization.actionCheckForUpdates) {
                        onCheckForUpdates()
                    }
                    .help(String(format: Localization.tipCheckForUpdates, AppInfo.appName))
                }
            }
            SettingsSection {
                SettingsRow(icon: "externaldrive", subtitle: Localization.tipBackup, anchor: .backup) {
                    Text(Localization.labelBackup)
                } control: {
                    Button(Localization.actionImportSettings) {
                        onImportSettings()
                    }
                    Button(Localization.actionExportSettings) {
                        onExportSettings()
                    }
                }
            }
            footer
        }
    }

    private var footer: some View {
        HStack {
            let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
            let name = "\(AppInfo.appName) v\(version)"
            if let url = URL(string: "https://github.com/gechr/WhichSpace") {
                Link(name, destination: url)
            } else {
                Text(name)
                    .foregroundStyle(.secondary)
            }
        }
        .font(.callout)
        .frame(maxWidth: .infinity)
        .padding(.top, 4)
    }
}
