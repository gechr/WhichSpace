import Testing
@testable import WhichSpace

@MainActor
struct DiagnosticsTests {
    private let store: DefaultsStore
    private let testSuite: TestSuite

    init() {
        testSuite = TestSuiteFactory.createSuite()
        store = DefaultsStore(suite: testSuite.suite)
    }

    /// A display identifier that looks like the CGS ones the app really
    /// handles, so a leak would be recognisable in the assertions below.
    private static let displayID = "37D8832A-2D66-02CA-B9F7-8F30A301B230"

    private func makeEnvironment(
        spacesPerDisplay: [Int] = [3],
        thirdPartyApps: [String] = [],
        stageManagerEnabled: DiagnosticsFlag = .no,
        separateSpaces: DiagnosticsFlag = .yes,
        shrinkLevel: IconShrinkLevel = .full,
        activeDisplay: Int? = 1,
        activeSpaceIndex: Int? = 1,
        activeDesktopNumber: Int? = 1,
        activeSpaceIsFullscreen: Bool = false
    ) -> DiagnosticsEnvironment {
        DiagnosticsEnvironment(
            appVersion: "1.3.3",
            systemVersion: "26.6.2 (25G220)",
            architecture: "arm64",
            accessibilityTrusted: true,
            stageManagerEnabled: stageManagerEnabled,
            reduceMotionEnabled: false,
            separateSpaces: separateSpaces,
            spacesPerDisplay: spacesPerDisplay,
            fullscreenSpaceCount: 0,
            shrinkLevel: shrinkLevel,
            activeDisplay: activeDisplay,
            activeSpaceIndex: activeSpaceIndex,
            activeDesktopNumber: activeDesktopNumber,
            activeSpaceIsFullscreen: activeSpaceIsFullscreen,
            thirdPartyApps: thirdPartyApps
        )
    }

    // MARK: - Privacy

    @Test("report omits Space labels, badges and symbols")
    func report_omitsUserText() {
        SpacePreferences.setLabel("Acme Corp", forSpace: 1, store: store)
        SpacePreferences.setLabel("Payroll", forSpace: 2, store: store)

        let report = Diagnostics.markdown(
            environment: makeEnvironment(),
            store: store,
            hotkeys: [:]
        )

        #expect(!report.contains("Acme Corp"))
        #expect(!report.contains("Payroll"))
        // Presence is what replaces them
        #expect(report.contains("Custom labels"))
    }

    @Test("report omits display identifiers")
    func report_omitsDisplayIdentifiers() {
        store.displaySpaceLabels = [Self.displayID: [1: "Home"]]

        let report = Diagnostics.markdown(
            environment: makeEnvironment(spacesPerDisplay: [3, 2]),
            store: store,
            hotkeys: [:]
        )

        #expect(!report.contains(Self.displayID))
        #expect(!report.contains("Home"))
        // Topology survives without the identifier
        #expect(report.contains("Spaces per display"))
        #expect(report.contains("3, 2"))
    }

    @Test("report pairs each bound shortcut with its chord")
    func report_namesHotkeyChords() {
        let report = Diagnostics.markdown(
            environment: makeEnvironment(),
            store: store,
            hotkeys: ["switchLeft": "⌃←", "switchRight": "⌃→"]
        )

        #expect(report.contains("switchLeft ⌃←, switchRight ⌃→"))
        // The encoded form the backup uses stays out of it
        #expect(!report.contains("keyCode"))
    }

    @Test("settings exclude the free-text sound name")
    func settings_excludeSoundName() {
        store.soundName = "standup-reminder-acme.aiff"

        let report = Diagnostics.markdown(
            environment: makeEnvironment(),
            store: store,
            hotkeys: [:]
        )

        #expect(!report.contains("standup-reminder-acme.aiff"))
    }

    // MARK: - Customization

    @Test("customization reads no on a fresh store")
    func customization_noneByDefault() {
        #expect(Diagnostics.customization(store: store).allSatisfy { $0.1 == "no" })
    }

    @Test("a label on any display reads as customized")
    func customization_reportsPresence() {
        store.displaySpaceLabels = [Self.displayID: [1: "B"]]

        let labels = Diagnostics.customization(store: store).first { $0.0 == "Custom labels" }

        #expect(labels?.1 == "yes")
    }

    @Test("the default style template does not count as a customized Space")
    func customization_ignoresDefaultStyleTemplate() {
        SpacePreferences.setLabel("A", forSpace: SpacePreferences.defaultStyleSpace, store: store)

        let labels = Diagnostics.customization(store: store).first { $0.0 == "Custom labels" }

        #expect(labels?.1 == "no")
    }

    // MARK: - Environment

    @Test("known apps are reported by name")
    func environment_reportsKnownApps() {
        let report = Diagnostics.markdown(
            environment: makeEnvironment(thirdPartyApps: ["BetterTouchTool", "Ice"]),
            store: store,
            hotkeys: [:]
        )

        #expect(report.contains("BetterTouchTool, Ice"))
    }

    @Test("an empty app list reads as none detected")
    func environment_reportsNoKnownApps() {
        let report = Diagnostics.markdown(
            environment: makeEnvironment(),
            store: store,
            hotkeys: [:]
        )

        #expect(report.contains("none detected"))
    }

    @Test("system version is composed, not the localized Foundation string")
    func systemVersion_isNotLocalized() {
        let version = DiagnosticsEnvironment.systemVersionString

        // `operatingSystemVersionString` reads "Version 26.6.2 (Build 25G220)"
        // and translates both words
        #expect(!version.contains("Version"))
        #expect(!version.contains("Build"))
        #expect(version.first?.isNumber == true)
    }

    @Test("known app list maps bundle identifiers to display names")
    func knownApps_mapBundleIdentifiers() {
        #expect(DiagnosticsEnvironment.knownApps["com.hegenberg.BetterTouchTool"] == "BetterTouchTool")
        #expect(DiagnosticsEnvironment.knownApps["com.jordanbaird.Ice"] == "Ice")
        #expect(DiagnosticsEnvironment.knownApps["com.apple.Safari"] == nil)
        // The core service runs whenever Karabiner is active; the settings
        // app only runs while its window is open
        #expect(DiagnosticsEnvironment.knownApps["org.pqrs.Karabiner-Core-Service"] == "Karabiner-Elements")
    }

    @Test("a missing probe key reads as unknown, not off")
    func probes_reportUnknownWhenAbsent() {
        let report = Diagnostics.markdown(
            environment: makeEnvironment(stageManagerEnabled: .unknown, separateSpaces: .unknown),
            store: store,
            hotkeys: [:]
        )

        #expect(report.contains("Stage Manager") && report.contains("unknown"))
        #expect(DiagnosticsEnvironment.flag(suite: "io.gechr.WhichSpace.absent", key: "nope") == .unknown)
    }

    @Test("report carries the live shrink level, not just the setting")
    func report_carriesShrinkLevel() {
        let report = Diagnostics.markdown(
            environment: makeEnvironment(shrinkLevel: .activePerDisplay),
            store: store,
            hotkeys: [:]
        )

        #expect(report.contains("Shrink level"))
        #expect(report.contains("active per display"))
    }

    @Test("report locates the active Space by ordinal, never by identifier")
    func report_carriesActiveContext() {
        let report = Diagnostics.markdown(
            environment: makeEnvironment(
                spacesPerDisplay: [3, 2],
                activeDisplay: 2,
                activeSpaceIndex: 1,
                activeDesktopNumber: 4,
                activeSpaceIsFullscreen: true
            ),
            store: store,
            hotkeys: [:]
        )

        #expect(report.contains("Active display"))
        #expect(report.contains("Active Desktop number"))
        #expect(report.contains("Active Space fullscreen"))
    }

    @Test("an unknown active Space reads as none")
    func report_activeContextMayBeAbsent() {
        let report = Diagnostics.markdown(
            environment: makeEnvironment(activeDisplay: nil, activeSpaceIndex: nil, activeDesktopNumber: nil),
            store: store,
            hotkeys: [:]
        )

        #expect(report.contains("none"))
    }

    // MARK: - Format

    @Test("report is wrapped in a collapsed details block")
    func report_isCollapsible() {
        let report = Diagnostics.markdown(
            environment: makeEnvironment(),
            store: store,
            hotkeys: [:]
        )

        #expect(report.hasPrefix("<details>"))
        #expect(report.hasSuffix("</details>"))
        #expect(report.contains("<summary>WhichSpace diagnostics</summary>"))
    }

    @Test("report carries the version and topology a report needs")
    func report_carriesEnvironment() {
        let report = Diagnostics.markdown(
            environment: makeEnvironment(spacesPerDisplay: [4, 4]),
            store: store,
            hotkeys: [:]
        )

        #expect(report.contains("1.3.3"))
        #expect(report.contains("26.6.2 (25G220)"))
        #expect(report.contains("arm64"))
        #expect(report.contains("Displays"))
        #expect(report.contains("Separate Spaces"))
    }
}
