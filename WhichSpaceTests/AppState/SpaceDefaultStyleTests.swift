import Testing
@testable import WhichSpace

@MainActor
struct SpaceDefaultStyleTests {
    private let stub: CGSStub
    private let store: DefaultsStore
    private let testSuite: TestSuite

    init() {
        testSuite = TestSuiteFactory.createSuite()
        store = DefaultsStore(suite: testSuite.suite)
        stub = CGSStub()
    }

    // MARK: - Helpers

    private func makeAppState(spaces: [(id: Int, isFullscreen: Bool)], activeSpaceID: Int) -> AppState {
        stub.activeDisplayIdentifier = "Main"
        stub.displays = [
            CGSStub.makeDisplay(displayID: "Main", spaces: spaces, activeSpaceID: activeSpaceID),
        ]
        return AppState(displaySpaceProvider: stub, skipObservers: true, store: store)
    }

    private func updateStub(spaces: [(id: Int, isFullscreen: Bool)], activeSpaceID: Int) {
        stub.displays = [
            CGSStub.makeDisplay(displayID: "Main", spaces: spaces, activeSpaceID: activeSpaceID),
        ]
    }

    private func makeAppState(
        displays: [(displayID: String, spaces: [(id: Int, isFullscreen: Bool)], activeSpaceID: Int)],
        activeDisplayID: String
    ) -> AppState {
        stub.activeDisplayIdentifier = activeDisplayID
        stub.displays = displays.map { display in
            CGSStub.makeDisplay(
                displayID: display.displayID,
                spaces: display.spaces,
                activeSpaceID: display.activeSpaceID
            )
        }
        return AppState(displaySpaceProvider: stub, skipObservers: true, store: store)
    }

    private func updateStub(
        displays: [(displayID: String, spaces: [(id: Int, isFullscreen: Bool)], activeSpaceID: Int)]
    ) {
        stub.displays = displays.map { display in
            CGSStub.makeDisplay(
                displayID: display.displayID,
                spaces: display.spaces,
                activeSpaceID: display.activeSpaceID
            )
        }
    }

    // MARK: - Default Style Applied to New Spaces

    @Test("new space inherits default icon style")
    func newSpace_appliesDefaultStyle() {
        SpacePreferences.setIconStyle(.circle, forSpace: 1, store: store)
        SpacePreferences.saveDefaultStyle(fromSpace: 1, store: store)

        let sut = makeAppState(
            spaces: [(100, false), (101, false)],
            activeSpaceID: 101
        )

        updateStub(
            spaces: [(100, false), (101, false), (102, false)],
            activeSpaceID: 102
        )
        sut.forceSpaceUpdate()

        #expect(SpacePreferences.iconStyle(forSpace: 3, store: store) == .circle)
    }

    @Test("new space inherits default colors and symbol")
    func newSpace_appliesDefaultColorsAndSymbol() {
        let colors = SpaceColors(foreground: .red, background: .blue)
        SpacePreferences.setColors(colors, forSpace: 1, store: store)
        SpacePreferences.setSymbol("star.fill", forSpace: 1, store: store)
        SpacePreferences.saveDefaultStyle(fromSpace: 1, store: store)

        let sut = makeAppState(
            spaces: [(100, false)],
            activeSpaceID: 100
        )

        updateStub(
            spaces: [(100, false), (101, false)],
            activeSpaceID: 101
        )
        sut.forceSpaceUpdate()

        let inherited = SpacePreferences.colors(forSpace: 2, store: store)
        #expect(inherited != nil)
        #expect(inherited?.foreground == .red)
        #expect(inherited?.background == .blue)
        #expect(SpacePreferences.symbol(forSpace: 2, store: store) == "star.fill")
    }

    @Test("new space inherits multiple default preferences")
    func newSpace_appliesMultipleDefaultPreferences() {
        SpacePreferences.setIconStyle(.circle, forSpace: 1, store: store)
        SpacePreferences.setColors(SpaceColors(foreground: .red, background: .blue), forSpace: 1, store: store)
        SpacePreferences.setSymbol("star", forSpace: 1, store: store)
        SpacePreferences.setBadge(SpaceBadge(character: "A", position: .topRight), forSpace: 1, store: store)
        SpacePreferences.saveDefaultStyle(fromSpace: 1, store: store)

        let sut = makeAppState(
            spaces: [(100, false)],
            activeSpaceID: 100
        )

        updateStub(
            spaces: [(100, false), (101, false)],
            activeSpaceID: 101
        )
        sut.forceSpaceUpdate()

        #expect(SpacePreferences.iconStyle(forSpace: 2, store: store) == .circle)
        #expect(SpacePreferences.colors(forSpace: 2, store: store)?.foreground == .red)
        #expect(SpacePreferences.symbol(forSpace: 2, store: store) == "star")
        #expect(SpacePreferences.badge(forSpace: 2, store: store)?.character == "A")
    }

    @Test("new space on secondary display uses local shared space number")
    func newSpace_onSecondaryDisplay_appliesDefaultToLocalSharedSpaceNumber() {
        SpacePreferences.setIconStyle(.circle, forSpace: 1, store: store)
        SpacePreferences.saveDefaultStyle(fromSpace: 1, store: store)

        let sut = makeAppState(
            displays: [
                (displayID: "Main", spaces: [(100, false), (101, false)], activeSpaceID: 100),
                (displayID: "Secondary", spaces: [(200, false), (201, false)], activeSpaceID: 201),
            ],
            activeDisplayID: "Secondary"
        )

        updateStub(
            displays: [
                (displayID: "Main", spaces: [(100, false), (101, false)], activeSpaceID: 100),
                (displayID: "Secondary", spaces: [(200, false), (201, false), (202, false)], activeSpaceID: 202),
            ]
        )
        sut.forceSpaceUpdate()

        #expect(SpacePreferences.iconStyle(forSpace: 3, store: store) == .circle)
        #expect(SpacePreferences.iconStyle(forSpace: 5, store: store) == nil)
    }

    @Test("new space on secondary display uses local per-display space number")
    func newSpace_onSecondaryDisplay_appliesDefaultToLocalPerDisplaySpaceNumber() {
        store.uniqueIconsPerDisplay = true
        SpacePreferences.setIconStyle(.circle, forSpace: 1, display: "Main", store: store)
        SpacePreferences.saveDefaultStyle(fromSpace: 1, display: "Main", store: store)

        let sut = makeAppState(
            displays: [
                (displayID: "Main", spaces: [(100, false), (101, false)], activeSpaceID: 100),
                (displayID: "Secondary", spaces: [(200, false), (201, false)], activeSpaceID: 201),
            ],
            activeDisplayID: "Secondary"
        )

        updateStub(
            displays: [
                (displayID: "Main", spaces: [(100, false), (101, false)], activeSpaceID: 100),
                (displayID: "Secondary", spaces: [(200, false), (201, false), (202, false)], activeSpaceID: 202),
            ]
        )
        sut.forceSpaceUpdate()

        #expect(SpacePreferences.iconStyle(forSpace: 3, display: "Secondary", store: store) == .circle)
        #expect(SpacePreferences.iconStyle(forSpace: 5, display: "Secondary", store: store) == nil)
        #expect(SpacePreferences.iconStyle(forSpace: 3, display: "Main", store: store) == nil)
    }

    // MARK: - No Default Style

    @Test("new space without default style stays unconfigured")
    func newSpace_noDefaultStyle_getsNoCustomization() {
        let sut = makeAppState(
            spaces: [(100, false), (101, false)],
            activeSpaceID: 101
        )
        SpacePreferences.setIconStyle(.circle, forSpace: 2, store: store)

        updateStub(
            spaces: [(100, false), (101, false), (102, false)],
            activeSpaceID: 102
        )
        sut.forceSpaceUpdate()

        #expect(!SpacePreferences.hasAnyPreference(forSpace: 3, store: store))
    }

    // MARK: - Guards

    @Test("does not overwrite preferences already set on the new space")
    func newSpace_doesNotApplyDefaultWhenTargetHasPreferences() {
        SpacePreferences.setIconStyle(.circle, forSpace: 1, store: store)
        SpacePreferences.saveDefaultStyle(fromSpace: 1, store: store)
        SpacePreferences.setIconStyle(.hexagon, forSpace: 3, store: store)

        let sut = makeAppState(
            spaces: [(100, false), (101, false)],
            activeSpaceID: 100
        )

        updateStub(
            spaces: [(100, false), (101, false), (102, false)],
            activeSpaceID: 102
        )
        sut.forceSpaceUpdate()

        #expect(SpacePreferences.iconStyle(forSpace: 3, store: store) == .hexagon)
    }

    @Test("does not apply default when space count decreases")
    func newSpace_doesNotApplyDefaultWhenSpaceCountDecreases() {
        SpacePreferences.setIconStyle(.circle, forSpace: 1, store: store)
        SpacePreferences.saveDefaultStyle(fromSpace: 1, store: store)

        let sut = makeAppState(
            spaces: [(100, false), (101, false), (102, false)],
            activeSpaceID: 101
        )

        updateStub(
            spaces: [(100, false), (101, false)],
            activeSpaceID: 101
        )
        sut.forceSpaceUpdate()

        #expect(SpacePreferences.iconStyle(forSpace: 3, store: store) == nil)
    }

    @Test("does not apply default on initial launch")
    func newSpace_doesNotApplyDefaultOnInitialLaunch() {
        SpacePreferences.setIconStyle(.circle, forSpace: 1, store: store)
        SpacePreferences.saveDefaultStyle(fromSpace: 1, store: store)

        _ = makeAppState(
            spaces: [(100, false), (101, false), (102, false)],
            activeSpaceID: 100
        )

        #expect(SpacePreferences.iconStyle(forSpace: 2, store: store) == nil)
        #expect(SpacePreferences.iconStyle(forSpace: 3, store: store) == nil)
    }

    // MARK: - Per-Display

    @Test("per-display default applies to new space on its display")
    func newSpace_appliesDefault_perDisplay() {
        store.uniqueIconsPerDisplay = true

        SpacePreferences.setIconStyle(.circle, forSpace: 1, display: "Main", store: store)
        SpacePreferences.saveDefaultStyle(fromSpace: 1, display: "Main", store: store)

        let sut = makeAppState(
            spaces: [(100, false)],
            activeSpaceID: 100
        )

        updateStub(
            spaces: [(100, false), (101, false)],
            activeSpaceID: 101
        )
        sut.forceSpaceUpdate()

        #expect(SpacePreferences.iconStyle(forSpace: 2, display: "Main", store: store) == .circle)
    }

    // MARK: - Switching Without New Space

    @Test("switching active space does not apply default")
    func switchingSpaces_doesNotApplyDefault() {
        SpacePreferences.setIconStyle(.circle, forSpace: 1, store: store)
        SpacePreferences.saveDefaultStyle(fromSpace: 1, store: store)

        let sut = makeAppState(
            spaces: [(100, false), (101, false), (102, false)],
            activeSpaceID: 100
        )

        updateStub(
            spaces: [(100, false), (101, false), (102, false)],
            activeSpaceID: 101
        )
        sut.forceSpaceUpdate()

        #expect(SpacePreferences.iconStyle(forSpace: 2, store: store) == nil)
    }
}
