import Defaults
import SwiftUI

// MARK: - Defaults Keys for SwiftUI Settings

extension Defaults.Keys {
    static let showAllSpaces = Key<Bool>(
        KeySpecs.showAllSpaces.name,
        default: KeySpecs.showAllSpaces.defaultValue
    )
    static let showAllDisplays = Key<Bool>(
        KeySpecs.showAllDisplays.name,
        default: KeySpecs.showAllDisplays.defaultValue
    )
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
    static let clickToSwitchSpaces = Key<Bool>(
        KeySpecs.clickToSwitchSpaces.name,
        default: KeySpecs.clickToSwitchSpaces.defaultValue
    )
    static let sizeScale = Key<Double>(
        KeySpecs.sizeScale.name,
        default: KeySpecs.sizeScale.defaultValue
    )
}

// MARK: - SettingsView

@MainActor
struct SettingsView: View {
    @Default(.showAllSpaces) private var showAllSpaces
    @Default(.showAllDisplays) private var showAllDisplays
    @Default(.dimInactiveSpaces) private var dimInactiveSpaces
    @Default(.hideEmptySpaces) private var hideEmptySpaces
    @Default(.hideSingleSpace) private var hideSingleSpace
    @Default(.clickToSwitchSpaces) private var clickToSwitchSpaces
    @Default(.sizeScale) private var sizeScale

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
    }

    // MARK: - General Tab

    private var generalTab: some View {
        Form {
            Section("Display") {
                Toggle(Localization.toggleShowAllSpaces, isOn: $showAllSpaces)
                Toggle(Localization.toggleShowAllDisplays, isOn: $showAllDisplays)
                Toggle(Localization.toggleDimInactiveSpaces, isOn: $dimInactiveSpaces)
            }

            Section("Visibility") {
                Toggle(Localization.toggleHideEmptySpaces, isOn: $hideEmptySpaces)
                Toggle(Localization.toggleHideSingleSpace, isOn: $hideSingleSpace)
            }

            Section("Behavior") {
                Toggle(Localization.toggleClickToSwitchSpaces, isOn: $clickToSwitchSpaces)
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
        Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String ?? "WhichSpace"
    }

    private var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "Unknown"
    }
}
