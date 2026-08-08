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
    let onResetAllSettings: () -> Void

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
                // Applies to manual checks too, so not gated on the
                // auto-check toggle
                SettingsToggleRow(
                    title: Localization.toggleBetaUpdates,
                    isOn: model.binding(\.includeBetaUpdates),
                    icon: "testtube.2",
                    subtitle: Localization.tipBetaUpdates,
                    anchor: .betaUpdates
                )
                SettingsRowDivider()
                SettingsRow(subtitle: lastCheckedCaption, anchor: .checkForUpdates) {
                    EmptyView()
                } control: {
                    Button(Localization.actionCheckForUpdates) {
                        onCheckForUpdates()
                        refreshLastChecked()
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
            // Below the backup card, so the export that would preserve the
            // current setup is the nearer of the two
            SettingsSection {
                SettingsRow(
                    icon: "arrow.counterclockwise",
                    subtitle: Localization.tipResetSettings,
                    anchor: .resetSettings
                ) {
                    Text(Localization.labelResetSettings)
                } control: {
                    Button(Localization.actionReset) {
                        onResetAllSettings()
                    }
                }
            }
            footer
        }
    }

    /// Says "never" until Sparkle has checked at least once, so a bare row
    /// does not read as a broken caption.
    private var lastCheckedCaption: String? {
        let value = updater?.lastUpdateCheckDate
            .map { $0.formatted(date: .abbreviated, time: .shortened) }
            ?? Localization.labelNever
        return String(format: Localization.tipLastChecked, value)
    }

    /// Sparkle stamps the check date when the appcast fetch starts, not when
    /// the button is clicked, so the caption re-reads shortly after as well
    /// as immediately.
    private func refreshLastChecked() {
        updaterTick += 1
        Task {
            try? await Task.sleep(for: .seconds(2))
            updaterTick += 1
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
