import AppKit
import Combine
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
    let onCopyDiagnostics: () -> Bool
    let onResetAllSettings: () -> Void

    /// Only `canCheckForUpdates` is KVO-observable on the updater; bumped
    /// when the check toggle flips or a session ends so the other rows
    /// re-read the updater
    @State private var updaterTick = 0

    /// Mirrors the updater's in-flight state, driven by KVO below
    @State private var checkInProgress = false

    /// Confirms the diagnostics copy, which is otherwise invisible. Reverts
    /// after a moment so the button reads as repeatable.
    @State private var diagnosticsCopied = false

    /// Held so a second click cancels the first click's pending reset.
    @State private var diagnosticsResetTask: Task<Void, Never>?

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
                    if checkInProgress {
                        ProgressView().controlSize(.small)
                    }
                    Button(Localization.actionCheckForUpdates) {
                        onCheckForUpdates()
                    }
                    .disabled(checkInProgress)
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
            SettingsSection {
                SettingsRow(icon: "stethoscope", subtitle: Localization.tipDiagnostics, anchor: .diagnostics) {
                    Text(Localization.labelDiagnostics)
                } control: {
                    Button(diagnosticsCopied ? Localization.actionCopied : Localization.buttonCopy) {
                        guard onCopyDiagnostics() else {
                            return
                        }
                        diagnosticsCopied = true
                        // Cancel the previous reset, so a second click keeps
                        // the confirmation up for its own two seconds
                        diagnosticsResetTask?.cancel()
                        diagnosticsResetTask = Task {
                            try? await Task.sleep(for: .seconds(2))
                            guard !Task.isCancelled else {
                                return
                            }
                            diagnosticsCopied = false
                        }
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
                        // The update toggles bind to the updater, not the
                        // store, so a confirmed reset needs an explicit
                        // re-read
                        updaterTick += 1
                    }
                }
            }
            footer
        }
        .onReceive(canCheckPublisher) { canCheck in
            // Each body evaluation subscribes a fresh KVO publisher whose
            // initial emission lands here; bumping state on those replays
            // would re-render and resubscribe forever
            guard checkInProgress != !canCheck else {
                return
            }
            checkInProgress = !canCheck
            // Sparkle stamps the check date when the appcast fetch starts,
            // so the caption re-reads on every session transition
            updaterTick += 1
        }
    }

    /// KVO publisher for the updater's in-flight state: `canCheckForUpdates`
    /// is false while an update session runs. A nil updater (previews) reads
    /// as idle.
    private var canCheckPublisher: AnyPublisher<Bool, Never> {
        guard let updater else {
            return Just(true).eraseToAnyPublisher()
        }
        return updater.publisher(for: \.canCheckForUpdates).eraseToAnyPublisher()
    }

    /// Says "never" until Sparkle has checked at least once, so a bare row
    /// does not read as a broken caption.
    private var lastCheckedCaption: String? {
        let value = updater?.lastUpdateCheckDate
            .map { $0.formatted(date: .abbreviated, time: .shortened) }
            ?? Localization.labelNever
        return String(format: Localization.tipLastChecked, value)
    }

    private var footer: some View {
        HStack(spacing: 6) {
            footerLink(AppInfo.appName, destination: AppInfo.repositoryURL)
            // Verbatim keeps the separator out of the string catalog, which
            // the localized initializer would file it in
            Text(verbatim: "·")
                .foregroundStyle(.secondary)
            footerLink("v\(AppInfo.version)", destination: AppInfo.releaseURL)
        }
        .font(.callout)
        .frame(maxWidth: .infinity)
        .padding(.top, 4)
    }

    /// Falls back to plain text when the URL does not build, so the footer
    /// still reads as a version stamp.
    @ViewBuilder
    private func footerLink(_ title: String, destination: URL?) -> some View {
        if let destination {
            Link(title, destination: destination)
        } else {
            Text(title)
                .foregroundStyle(.secondary)
        }
    }
}
