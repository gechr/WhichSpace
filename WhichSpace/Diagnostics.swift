import AppKit

// MARK: - DiagnosticsFlag

/// The result of a probe that can fail, so an absent key is never reported as
/// a deliberate off.
enum DiagnosticsFlag: String {
    case yes
    case no
    case unknown

    init(_ value: Bool) {
        self = value ? .yes : .no
    }

    /// Swaps yes and no, leaving a failed probe unknown.
    var inverted: Self {
        switch self {
        case .yes:
            .no
        case .no:
            .yes
        case .unknown:
            .unknown
        }
    }
}

// MARK: - DiagnosticsEnvironment

/// Host facts a bug report needs, carrying no user-authored text, file paths, or stable
/// hardware or Space identifiers. CGS derives a display's UUID from its vendor, model and
/// serial number, so display and Space identifiers are absent.
struct DiagnosticsEnvironment {
    var appVersion: String
    var systemVersion: String
    var architecture: String
    var accessibilityTrusted: Bool
    /// Undocumented keys, so a missing one reads as unknown rather than off.
    var stageManagerEnabled: DiagnosticsFlag
    var reduceMotionEnabled: Bool
    var separateSpaces: DiagnosticsFlag
    /// Space count per display, in the order the app orders displays. The
    /// length is the display count.
    var spacesPerDisplay: [Int]
    var fullscreenSpaceCount: Int
    /// How far the status item has degraded, which `shrinkIconToFit` alone
    /// does not show.
    var shrinkLevel: IconShrinkLevel
    /// Where the user was when they copied, as ordinals into
    /// `spacesPerDisplay` rather than identifiers.
    var activeDisplay: Int?
    var activeSpaceIndex: Int?
    var activeDesktopNumber: Int?
    var activeSpaceIsFullscreen: Bool
    /// Display names of running third-party apps known to affect Space
    /// switching, matched against `DiagnosticsEnvironment.knownApps`.
    var thirdPartyApps: [String]

    /// Third-party apps that affect Space switching, keyed by bundle identifier. Only matches are
    /// reported, so the list never enumerates what the user has installed. Daemons such as yabai
    /// and skhd do not register as running applications and go undetected.
    static let knownApps: [String: String] = [
        "bobko.aerospace": "AeroSpace",
        "com.amethyst.Amethyst": "Amethyst",
        "com.caldis.Mos": "Mos",
        "com.crowdcafe.windowmagnet": "Magnet",
        "com.hegenberg.BetterTouchTool": "BetterTouchTool",
        "com.jordanbaird.Ice": "Ice",
        "com.knollsoft.Rectangle": "Rectangle",
        "com.manytricks.Moom": "Moom",
        "com.pilotmoon.scroll-reverser": "Scroll Reverser",
        "com.stairways.keyboardmaestro.engine": "Keyboard Maestro",
        "com.surteesstudios.Bartender": "Bartender",
        "org.hammerspoon.Hammerspoon": "Hammerspoon",
        // The background core service, which runs whenever Karabiner is
        // active. The settings app only runs while its window is open.
        "org.pqrs.Karabiner-Core-Service": "Karabiner-Elements",
    ]

    /// Reads the live environment. Everything the caller passes comes from the
    /// snapshot it already holds.
    @MainActor
    static func current(
        spacesPerDisplay: [Int],
        fullscreenSpaceCount: Int,
        shrinkLevel: IconShrinkLevel,
        activeDisplay: Int?,
        activeSpaceIndex: Int?,
        activeDesktopNumber: Int?,
        activeSpaceIsFullscreen: Bool
    ) -> Self {
        Self(
            appVersion: AppInfo.version,
            systemVersion: systemVersionString,
            architecture: currentArchitecture,
            accessibilityTrusted: AXIsProcessTrusted(),
            stageManagerEnabled: flag(suite: "com.apple.WindowManager", key: "GloballyEnabled"),
            reduceMotionEnabled: NSWorkspace.shared.accessibilityDisplayShouldReduceMotion,
            // The spaces plist records the inverse, so spanning displays is
            // the same setting turned off.
            separateSpaces: flag(suite: "com.apple.spaces", key: "spans-displays").inverted,
            spacesPerDisplay: spacesPerDisplay,
            fullscreenSpaceCount: fullscreenSpaceCount,
            shrinkLevel: shrinkLevel,
            activeDisplay: activeDisplay,
            activeSpaceIndex: activeSpaceIndex,
            activeDesktopNumber: activeDesktopNumber,
            activeSpaceIsFullscreen: activeSpaceIsFullscreen,
            thirdPartyApps: runningKnownApps()
        )
    }

    /// Unknown when the key is absent or holds something other than a boolean,
    /// so a failed probe is never reported as a deliberate off.
    static func flag(suite: String, key: String) -> DiagnosticsFlag {
        guard let value = UserDefaults(suiteName: suite)?.object(forKey: key) as? Bool else {
            return .unknown
        }
        return DiagnosticsFlag(value)
    }

    /// Composed from the version components because `operatingSystemVersionString` is localized.
    static var systemVersionString: String {
        let version = ProcessInfo.processInfo.operatingSystemVersion
        let number = "\(version.majorVersion).\(version.minorVersion).\(version.patchVersion)"
        guard let build = sysctlString("kern.osversion") else {
            return number
        }
        return "\(number) (\(build))"
    }

    private static func sysctlString(_ name: String) -> String? {
        var size = 0
        guard sysctlbyname(name, nil, &size, nil, 0) == 0, size > 0 else {
            return nil
        }
        var buffer = [UInt8](repeating: 0, count: size)
        guard sysctlbyname(name, &buffer, &size, nil, 0) == 0 else {
            return nil
        }
        guard let value = String(bytes: buffer.prefix { $0 != 0 }, encoding: .utf8), !value.isEmpty else {
            return nil
        }
        return value
    }

    /// Architecture of the running binary, so a build running under Rosetta
    /// reports the translated architecture rather than the host's.
    static var currentArchitecture: String {
        #if arch(arm64)
            "arm64"
        #else
            "x86_64"
        #endif
    }

    static func runningKnownApps() -> [String] {
        NSWorkspace.shared.runningApplications
            .compactMap(\.bundleIdentifier)
            .compactMap { knownApps[$0] }
            .sorted()
    }
}

// MARK: - Diagnostics

/// Builds the report a reporter pastes into a GitHub issue.
///
/// Every value is listed explicitly rather than derived from `Backup`, which carries per-Space
/// labels, badges and symbols, and gains a field whenever a preference is added.
enum Diagnostics {
    /// Values that have changed a diagnosis, in the order they are reported. Free-text
    /// preferences are absent, since `soundName` names a file from `~/Library/Sounds`.
    @MainActor
    static func settings(store: DefaultsStore) -> [(String, String)] {
        [
            ("Show all Spaces", string(store.showAllSpaces)),
            ("Show all displays", string(store.showAllDisplays)),
            ("Local Space numbers", string(store.localSpaceNumbers)),
            ("Preserve system Space numbers", string(store.preserveSystemSpaceNumbers)),
            ("Display order", store.displayOrder.rawValue),
            ("Hide empty Spaces", string(store.hideEmptySpaces)),
            ("Hide fullscreen apps", string(store.hideFullscreenApps)),
            ("Hide single Space", string(store.hideSingleSpace)),
            ("Shrink to fit", string(store.shrinkIconToFit)),
            ("Size scale", string(store.sizeScale)),
            ("Classic switching", string(store.classicSpaceSwitching)),
            ("Click to switch", string(store.clickToSwitchSpaces)),
            ("Vertical scroll", string(store.verticalScrollEnabled)),
            ("Horizontal scroll", string(store.horizontalScrollEnabled)),
            ("Invert vertical scroll", string(store.invertVerticalScroll)),
            ("Invert horizontal scroll", string(store.invertHorizontalScroll)),
            ("Scroll sensitivity", string(store.scrollSensitivity)),
            ("Scroll wrap around", string(store.scrollWrapAround)),
            ("Scroll haptics", string(store.scrollHapticFeedback)),
            ("Skip empty Spaces (switch)", string(store.hotkeysSkipEmptySpaces)),
            ("Skip empty Spaces (move)", string(store.hotkeysMoveSkipEmptySpaces)),
            ("Skip empty Spaces (send)", string(store.hotkeysSendSkipEmptySpaces)),
            ("Space picker style", store.spacePickerStyle.rawValue),
            ("Nightly updates", string(store.includeNightlyUpdates)),
        ]
    }

    /// Whether each kind of customization is in use anywhere. Presence rather than a count,
    /// because a bare Space number means different Spaces on different displays and cannot be
    /// counted from the keys alone.
    @MainActor
    static func customization(store: DefaultsStore) -> [(String, String)] {
        [
            ("Custom labels", string(any(store.spaceLabels, store.displaySpaceLabels))),
            ("Custom badges", string(any(store.spaceBadges, store.displaySpaceBadges))),
            ("Custom symbols", string(any(store.spaceSymbols, store.displaySpaceSymbols))),
            ("Custom colors", string(any(store.spaceColors, store.displaySpaceColors))),
        ]
    }

    /// The report, wrapped in a collapsed `<details>` block so it does not bury the prose of the
    /// issue it is pasted into. `hotkeys` maps each bound action to the chord that triggers it,
    /// which is what shows a shortcut already owned by something else.
    @MainActor
    static func markdown(
        environment: DiagnosticsEnvironment,
        store: DefaultsStore,
        hotkeys: [String: String]
    ) -> String {
        let chords = hotkeys.keys.sorted().map { "\($0) \(hotkeys[$0] ?? "")" }
        let groups: [[(String, String)]] = [
            [
                ("WhichSpace", environment.appVersion),
                ("macOS", environment.systemVersion),
                ("Architecture", environment.architecture),
            ],
            [
                ("Accessibility granted", string(environment.accessibilityTrusted)),
                ("Stage Manager", environment.stageManagerEnabled.rawValue),
                ("Reduce Motion", string(environment.reduceMotionEnabled)),
                (
                    "Other apps running",
                    environment.thirdPartyApps.isEmpty
                        ? "none detected"
                        : environment.thirdPartyApps.joined(separator: ", ")
                ),
            ],
            [
                ("Displays", string(environment.spacesPerDisplay.count)),
                ("Spaces per display", environment.spacesPerDisplay.map(String.init).joined(separator: ", ")),
                ("Fullscreen Spaces", string(environment.fullscreenSpaceCount)),
                ("Separate Spaces", environment.separateSpaces.rawValue),
            ],
            [
                ("Active display", string(environment.activeDisplay)),
                ("Active Space", string(environment.activeSpaceIndex)),
                ("Active Desktop number", string(environment.activeDesktopNumber)),
                ("Active Space fullscreen", string(environment.activeSpaceIsFullscreen)),
            ],
            [
                ("Shrink level", environment.shrinkLevel.reportName),
                ("Bound shortcuts", chords.isEmpty ? "none" : chords.joined(separator: ", ")),
            ] + customization(store: store),
            settings(store: store),
        ]

        // One column width across every group, so the values stay aligned
        // through the blank lines
        let width = groups.flatMap(\.self).map(\.0.count).max() ?? 0
        let body = groups
            .map { group in
                group
                    .map { "\($0.0.padding(toLength: width, withPad: " ", startingAt: 0))  \($0.1)" }
                    .joined(separator: "\n")
            }
            .joined(separator: "\n\n")

        return """
        <details>
        <summary>WhichSpace diagnostics</summary>

        ```
        \(body)
        ```

        </details>
        """
    }

    // MARK: - Helpers

    @MainActor
    private static func any<Value>(
        _ global: [Int: Value],
        _ perDisplay: [String: [Int: Value]]
    ) -> Bool {
        // Space 0 is the default style template rather than a Space, so it
        // does not count as a customized Space.
        let template = SpacePreferences.defaultStyleSpace
        return global.keys.contains { $0 != template }
            || perDisplay.values.contains { $0.keys.contains { $0 != template } }
    }

    private static func string(_ value: Bool) -> String {
        value ? "yes" : "no"
    }

    private static func string(_ value: Int) -> String {
        String(value)
    }

    private static func string(_ value: Int?) -> String {
        value.map(String.init) ?? "none"
    }

    private static func string(_ value: Double) -> String {
        String(format: "%.2f", value)
    }
}

// MARK: - IconShrinkLevel

extension IconShrinkLevel {
    /// Stable English name for the report, so it does not follow the enum's
    /// storage or any display string.
    var reportName: String {
        switch self {
        case .full:
            "full"
        case .compact:
            "compact"
        case .activePerDisplay:
            "active per display"
        case .currentOnly:
            "current only"
        }
    }
}
