import Defaults
import SwiftUI

// MARK: - Defaults Keys for SwiftUI Settings

extension Defaults.Keys {
    static let dimInactiveSpaces = Key<Bool>(
        KeySpecs.dimInactiveSpaces.name,
        default: KeySpecs.dimInactiveSpaces.defaultValue
    )
    static let hideEmptySpaces = Key<Bool>(
        KeySpecs.hideEmptySpaces.name,
        default: KeySpecs.hideEmptySpaces.defaultValue
    )
    static let hideSingleSpace = Key<Bool>(
        KeySpecs.hideSingleSpace.name,
        default: KeySpecs.hideSingleSpace.defaultValue
    )
    static let sizeScale = Key<Double>(
        KeySpecs.sizeScale.name,
        default: KeySpecs.sizeScale.defaultValue
    )
}

// MARK: - SettingsView

@MainActor
struct SettingsView: View {
    private let store = AppEnvironment.shared.store

    @Default(.dimInactiveSpaces) private var dimInactiveSpaces
    @Default(.hideEmptySpaces) private var hideEmptySpaces
    @Default(.hideSingleSpace) private var hideSingleSpace
    @Default(.sizeScale) private var sizeScale

    @State private var showingAccessibilityAlert = false

    private var showAllSpacesBinding: Binding<Bool> {
        Binding(
            get: { store.showAllSpaces },
            set: { SettingsInvariantEnforcer.setShowAllSpaces($0, store: store) }
        )
    }

    private var showAllDisplaysBinding: Binding<Bool> {
        Binding(
            get: { store.showAllDisplays },
            set: { SettingsInvariantEnforcer.setShowAllDisplays($0, store: store) }
        )
    }

    private var clickToSwitchSpacesBinding: Binding<Bool> {
        Binding(
            get: { store.clickToSwitchSpaces },
            set: { newValue in
                if !SettingsInvariantEnforcer.setClickToSwitchSpaces(newValue, store: store) {
                    showingAccessibilityAlert = true
                }
            }
        )
    }

    var body: some View {
        TabView {
            generalTab
                .tabItem {
                    Label("General", systemImage: "gearshape")
                }

            aboutTab
                .tabItem {
                    Label("About", systemImage: "info.circle")
                }
        }
        .frame(width: 380, height: 320)
        .alert(Localization.alertAccessibilityRequired, isPresented: $showingAccessibilityAlert) {
            Button(Localization.buttonContinue) {
                requestAccessibilityPermission()
            }
            Button(Localization.buttonCancel, role: .cancel) {}
        } message: {
            Text(Localization.alertAccessibilityDetail)
        }
    }

    // MARK: - Accessibility Permission

    private func requestAccessibilityPermission() {
        SpaceSwitcher.resetAccessibilityPermission()
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
        pollForAccessibilityPermission()
    }

    private func pollForAccessibilityPermission(remaining: Int = 60) {
        guard remaining > 0 else {
            NSLog("SettingsView: accessibility permission polling timed out")
            return
        }
        Timer.scheduledTimer(withTimeInterval: 0.5, repeats: false) { _ in
            if AXIsProcessTrusted() {
                Task { @MainActor in
                    store.clickToSwitchSpaces = true
                }
            } else {
                Task { @MainActor in
                    pollForAccessibilityPermission(remaining: remaining - 1)
                }
            }
        }
    }

    // MARK: - General Tab

    private var generalTab: some View {
        Form {
            Section("Display") {
                Toggle(Localization.toggleShowAllSpaces, isOn: showAllSpacesBinding)
                Toggle(Localization.toggleShowAllDisplays, isOn: showAllDisplaysBinding)
                Toggle(Localization.toggleDimInactiveSpaces, isOn: $dimInactiveSpaces)
            }

            Section("Visibility") {
                Toggle(Localization.toggleHideEmptySpaces, isOn: $hideEmptySpaces)
                Toggle(Localization.toggleHideSingleSpace, isOn: $hideSingleSpace)
            }

            Section("Behavior") {
                Toggle(Localization.toggleClickToSwitchSpaces, isOn: clickToSwitchSpacesBinding)
            }

            Section("Size") {
                HStack {
                    Slider(
                        value: $sizeScale,
                        in: Layout.sizeScaleRange,
                        step: 1
                    )
                    Text("\(Int(sizeScale))%")
                        .monospacedDigit()
                        .frame(width: 40)
                }
            }
        }
        .formStyle(.grouped)
        .padding()
    }

    // MARK: - About Tab

    private var aboutTab: some View {
        VStack(spacing: 12) {
            Spacer()

            if let icon = NSApp.applicationIconImage {
                Image(nsImage: icon)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 64, height: 64)
            }

            Text(appName)
                .font(.title2)
                .fontWeight(.semibold)

            Text("Version \(appVersion)")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Spacer()
        }
        .frame(maxWidth: .infinity)
        .padding()
    }

    // MARK: - Helpers

    private var appName: String {
        AppInfo.appName
    }

    private var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "Unknown"
    }
}
