import AppKit
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
                    isOn: model.launchAtLoginBinding,
                    icon: "sunrise",
                    subtitle: String(format: Localization.tipLaunchAtLogin, AppInfo.appName)
                )
            }
            SettingsSection {
                SettingsRow(icon: "speaker.wave.2", subtitle: Localization.tipSound) {
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
                    ),
                    icon: "arrow.triangle.2.circlepath"
                )
                SettingsRowDivider()
                SettingsToggleRow(
                    title: Localization.toggleAutoInstallUpdates,
                    isOn: Binding(
                        get: { updater?.automaticallyDownloadsUpdates ?? false },
                        set: { updater?.automaticallyDownloadsUpdates = $0 }
                    ),
                    icon: "square.and.arrow.down"
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
                SettingsRow(icon: "externaldrive", subtitle: Localization.tipBackup) {
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
        .task {
            userSounds = await Task.detached(priority: .userInitiated) {
                SoundCatalog.discoverUserSounds()
            }.value
        }
    }

    /// Plays the newly selected sound.
    private var soundBinding: Binding<String> {
        let stored = model.binding(\.soundName)
        return Binding(
            get: { stored.wrappedValue },
            set: { name in
                stored.wrappedValue = name
                guard !name.isEmpty,
                      let sound = NSSound(named: NSSound.Name(name))?.copy() as? NSSound
                else {
                    return
                }
                sound.play()
            }
        )
    }

    private var soundPicker: some View {
        Picker(Localization.menuSound, selection: soundBinding) {
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
