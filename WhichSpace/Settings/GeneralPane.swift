import Settings
import Sparkle
import SwiftUI

/// The General settings pane: startup, Space-change sound, updates, and
/// configuration backup. Container-agnostic - it knows nothing about the
/// window chrome hosting it.
struct GeneralPane: View {
    let model: SettingsModel
    /// Sparkle persists these settings itself (SU* defaults), so the toggles
    /// bind straight to the updater rather than `DefaultsStore`
    let updater: SPUUpdater?
    let onCheckForUpdates: () -> Void
    let onImportSettings: () -> Void
    let onExportSettings: () -> Void
    let onOpenCustomSoundsFolder: () -> Void

    @State private var userSounds: [String] = []

    var body: some View {
        SettingsForm {
            SettingsSection {
                SettingsToggleRow(
                    title: Localization.toggleLaunchAtLogin,
                    isOn: model.launchAtLoginBinding
                )
                .help(String(format: Localization.tipLaunchAtLogin, AppInfo.appName))
            }
            SettingsSection {
                SettingsRow {
                    Text(Localization.menuSound)
                } control: {
                    soundPicker
                        .labelsHidden()
                }
                SettingsRowDivider()
                SettingsRow {
                    EmptyView()
                } control: {
                    Button(Localization.soundCustom) {
                        onOpenCustomSoundsFolder()
                    }
                }
            }
            SettingsSection {
                SettingsToggleRow(
                    title: Localization.toggleAutoCheckUpdates,
                    isOn: Binding(
                        get: { updater?.automaticallyChecksForUpdates ?? false },
                        set: { updater?.automaticallyChecksForUpdates = $0 }
                    )
                )
                SettingsRowDivider()
                SettingsToggleRow(
                    title: Localization.toggleAutoDownloadUpdates,
                    isOn: Binding(
                        get: { updater?.automaticallyDownloadsUpdates ?? false },
                        set: { updater?.automaticallyDownloadsUpdates = $0 }
                    )
                )
                SettingsRowDivider()
                SettingsRow {
                    EmptyView()
                } control: {
                    Button(Localization.actionCheckForUpdates) {
                        onCheckForUpdates()
                    }
                    .help(String(format: Localization.tipCheckForUpdates, AppInfo.appName))
                }
            }
            SettingsSection {
                SettingsRow {
                    Text(Localization.labelBackup)
                } control: {
                    Button(Localization.actionImportSettings) {
                        onImportSettings()
                    }
                    .help(Localization.tipImportSettings)
                    Button(Localization.actionExportSettings) {
                        onExportSettings()
                    }
                    .help(Localization.tipExportSettings)
                }
            }
            footer
        }
        .task {
            userSounds = await Task.detached(priority: .userInitiated) {
                SoundCatalog.discoverUserSounds()
            }.value
        }
    }

    private var soundPicker: some View {
        Picker(Localization.menuSound, selection: model.binding(\.soundName)) {
            Text(Localization.soundNone).tag("")
            if !userSounds.isEmpty {
                Divider()
                ForEach(userSounds, id: \.self) { sound in
                    Text(sound).tag(sound)
                }
            }
            Divider()
            ForEach(SoundCatalog.systemSounds, id: \.self) { sound in
                Text(sound).tag(sound)
            }
        }
    }

    private var footer: some View {
        HStack(spacing: 8) {
            let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
            Text("\(AppInfo.appName) v\(version)")
                .foregroundStyle(.secondary)
            if let url = URL(string: "https://github.com/gechr/WhichSpace") {
                Link(Localization.actionViewOnGitHub, destination: url)
            }
        }
        .font(.callout)
        .frame(maxWidth: .infinity)
        .padding(.top, 4)
    }
}
