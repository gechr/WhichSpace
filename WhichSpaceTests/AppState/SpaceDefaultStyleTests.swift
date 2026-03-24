import XCTest
@testable import WhichSpace

@MainActor
final class SpaceDefaultStyleTests: XCTestCase {
    private var stub: CGSStub!
    private var sut: AppState!
    private var store: DefaultsStore!
    private var testSuite: TestSuite!

    override func setUp() {
        super.setUp()
        testSuite = TestSuiteFactory.createSuite()
        store = DefaultsStore(suite: testSuite.suite)
        stub = CGSStub()
    }

    override func tearDown() {
        sut = nil
        stub = nil
        if let store, let testSuite {
            store.resetAll()
            TestSuiteFactory.destroySuite(testSuite)
        }
        store = nil
        testSuite = nil
        super.tearDown()
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

    func testNewSpace_appliesDefaultStyle() {
        // Given: A default style is saved with circle icon style
        SpacePreferences.setIconStyle(.circle, forSpace: 1, store: store)
        SpacePreferences.saveDefaultStyle(fromSpace: 1, store: store)

        sut = makeAppState(
            spaces: [(100, false), (101, false)],
            activeSpaceID: 101
        )

        // When: A 3rd space is added
        updateStub(
            spaces: [(100, false), (101, false), (102, false)],
            activeSpaceID: 102
        )
        sut.forceSpaceUpdate()

        // Then: Space 3 gets the default style
        XCTAssertEqual(
            SpacePreferences.iconStyle(forSpace: 3, store: store),
            .circle,
            "New space should get the default style"
        )
    }

    func testNewSpace_appliesDefaultColorsAndSymbol() {
        // Given: Default style with colors and symbol
        let colors = SpaceColors(foreground: .red, background: .blue)
        SpacePreferences.setColors(colors, forSpace: 1, store: store)
        SpacePreferences.setSymbol("star.fill", forSpace: 1, store: store)
        SpacePreferences.saveDefaultStyle(fromSpace: 1, store: store)

        sut = makeAppState(
            spaces: [(100, false)],
            activeSpaceID: 100
        )

        // When: A 2nd space is added
        updateStub(
            spaces: [(100, false), (101, false)],
            activeSpaceID: 101
        )
        sut.forceSpaceUpdate()

        // Then: Space 2 gets the default colors and symbol
        let inherited = SpacePreferences.colors(forSpace: 2, store: store)
        XCTAssertNotNil(inherited, "New space should get default colors")
        XCTAssertEqual(inherited?.foreground, .red)
        XCTAssertEqual(inherited?.background, .blue)
        XCTAssertEqual(SpacePreferences.symbol(forSpace: 2, store: store), "star.fill")
    }

    func testNewSpace_appliesMultipleDefaultPreferences() {
        // Given: Default style with multiple customizations
        SpacePreferences.setIconStyle(.circle, forSpace: 1, store: store)
        SpacePreferences.setColors(SpaceColors(foreground: .red, background: .blue), forSpace: 1, store: store)
        SpacePreferences.setSymbol("star", forSpace: 1, store: store)
        SpacePreferences.setBadge(SpaceBadge(character: "A", position: .topRight), forSpace: 1, store: store)
        SpacePreferences.saveDefaultStyle(fromSpace: 1, store: store)

        sut = makeAppState(
            spaces: [(100, false)],
            activeSpaceID: 100
        )

        // When: A 2nd space is added
        updateStub(
            spaces: [(100, false), (101, false)],
            activeSpaceID: 101
        )
        sut.forceSpaceUpdate()

        // Then: All default preferences are applied
        XCTAssertEqual(SpacePreferences.iconStyle(forSpace: 2, store: store), .circle)
        XCTAssertEqual(SpacePreferences.colors(forSpace: 2, store: store)?.foreground, .red)
        XCTAssertEqual(SpacePreferences.symbol(forSpace: 2, store: store), "star")
        XCTAssertEqual(SpacePreferences.badge(forSpace: 2, store: store)?.character, "A")
    }

    func testNewSpace_onSecondaryDisplay_appliesDefaultToLocalSharedSpaceNumber() {
        // Given: Shared preferences across displays and a saved default style
        SpacePreferences.setIconStyle(.circle, forSpace: 1, store: store)
        SpacePreferences.saveDefaultStyle(fromSpace: 1, store: store)

        sut = makeAppState(
            displays: [
                (displayID: "Main", spaces: [(100, false), (101, false)], activeSpaceID: 100),
                (displayID: "Secondary", spaces: [(200, false), (201, false)], activeSpaceID: 201),
            ],
            activeDisplayID: "Secondary"
        )

        // When: Secondary display gets a new 3rd space
        updateStub(
            displays: [
                (displayID: "Main", spaces: [(100, false), (101, false)], activeSpaceID: 100),
                (displayID: "Secondary", spaces: [(200, false), (201, false), (202, false)], activeSpaceID: 202),
            ]
        )
        sut.forceSpaceUpdate()

        // Then: The local space number 3 inherits the default style, not the global total (5)
        XCTAssertEqual(SpacePreferences.iconStyle(forSpace: 3, store: store), .circle)
        XCTAssertNil(SpacePreferences.iconStyle(forSpace: 5, store: store))
    }

    func testNewSpace_onSecondaryDisplay_appliesDefaultToLocalPerDisplaySpaceNumber() {
        // Given: Per-display preferences and a saved default style
        store.uniqueIconsPerDisplay = true
        SpacePreferences.setIconStyle(.circle, forSpace: 1, display: "Main", store: store)
        SpacePreferences.saveDefaultStyle(fromSpace: 1, display: "Main", store: store)

        sut = makeAppState(
            displays: [
                (displayID: "Main", spaces: [(100, false), (101, false)], activeSpaceID: 100),
                (displayID: "Secondary", spaces: [(200, false), (201, false)], activeSpaceID: 201),
            ],
            activeDisplayID: "Secondary"
        )

        // When: Secondary display gets a new 3rd space
        updateStub(
            displays: [
                (displayID: "Main", spaces: [(100, false), (101, false)], activeSpaceID: 100),
                (displayID: "Secondary", spaces: [(200, false), (201, false), (202, false)], activeSpaceID: 202),
            ]
        )
        sut.forceSpaceUpdate()

        // Then: The per-display local space number 3 inherits the default style
        XCTAssertEqual(
            SpacePreferences.iconStyle(forSpace: 3, display: "Secondary", store: store),
            .circle
        )
        XCTAssertNil(SpacePreferences.iconStyle(forSpace: 5, display: "Secondary", store: store))
        XCTAssertNil(SpacePreferences.iconStyle(forSpace: 3, display: "Main", store: store))
    }

    // MARK: - No Default Style

    func testNewSpace_noDefaultStyle_getsNoCustomization() {
        // Given: No default style is saved
        sut = makeAppState(
            spaces: [(100, false), (101, false)],
            activeSpaceID: 101
        )
        // Even though space 2 has a style, no default is saved
        SpacePreferences.setIconStyle(.circle, forSpace: 2, store: store)

        // When: A 3rd space is added
        updateStub(
            spaces: [(100, false), (101, false), (102, false)],
            activeSpaceID: 102
        )
        sut.forceSpaceUpdate()

        // Then: Space 3 has no preferences (app defaults)
        XCTAssertFalse(
            SpacePreferences.hasAnyPreference(forSpace: 3, store: store),
            "New space should have no preferences when no default style is set"
        )
    }

    // MARK: - Guards

    func testNewSpace_doesNotApplyDefaultWhenTargetHasPreferences() {
        // Given: Default style saved, and space 3 pre-configured
        SpacePreferences.setIconStyle(.circle, forSpace: 1, store: store)
        SpacePreferences.saveDefaultStyle(fromSpace: 1, store: store)
        SpacePreferences.setIconStyle(.hexagon, forSpace: 3, store: store)

        sut = makeAppState(
            spaces: [(100, false), (101, false)],
            activeSpaceID: 100
        )

        // When: A 3rd space is added
        updateStub(
            spaces: [(100, false), (101, false), (102, false)],
            activeSpaceID: 102
        )
        sut.forceSpaceUpdate()

        // Then: Space 3 keeps its existing hexagon style
        XCTAssertEqual(
            SpacePreferences.iconStyle(forSpace: 3, store: store),
            .hexagon,
            "New space with existing preferences should not be overwritten"
        )
    }

    func testNewSpace_doesNotApplyDefaultWhenSpaceCountDecreases() {
        // Given: Default style saved, 3 spaces
        SpacePreferences.setIconStyle(.circle, forSpace: 1, store: store)
        SpacePreferences.saveDefaultStyle(fromSpace: 1, store: store)

        sut = makeAppState(
            spaces: [(100, false), (101, false), (102, false)],
            activeSpaceID: 101
        )

        // When: Space is removed (count decreases to 2)
        updateStub(
            spaces: [(100, false), (101, false)],
            activeSpaceID: 101
        )
        sut.forceSpaceUpdate()

        // Then: No default style applied
        XCTAssertNil(SpacePreferences.iconStyle(forSpace: 3, store: store))
    }

    func testNewSpace_doesNotApplyDefaultOnInitialLaunch() {
        // Given: Default style saved
        SpacePreferences.setIconStyle(.circle, forSpace: 1, store: store)
        SpacePreferences.saveDefaultStyle(fromSpace: 1, store: store)

        // When: AppState is created (initial launch)
        sut = makeAppState(
            spaces: [(100, false), (101, false), (102, false)],
            activeSpaceID: 100
        )

        // Then: Space 2 and 3 should NOT get default style on initial launch
        XCTAssertNil(
            SpacePreferences.iconStyle(forSpace: 2, store: store),
            "Spaces should not get default style on initial launch"
        )
        XCTAssertNil(
            SpacePreferences.iconStyle(forSpace: 3, store: store),
            "Spaces should not get default style on initial launch"
        )
    }

    // MARK: - Per-Display

    func testNewSpace_appliesDefault_perDisplay() {
        store.uniqueIconsPerDisplay = true

        // Given: Default style saved from space 1 on Main display
        SpacePreferences.setIconStyle(.circle, forSpace: 1, display: "Main", store: store)
        SpacePreferences.saveDefaultStyle(fromSpace: 1, display: "Main", store: store)

        sut = makeAppState(
            spaces: [(100, false)],
            activeSpaceID: 100
        )

        // When: A 2nd space is added
        updateStub(
            spaces: [(100, false), (101, false)],
            activeSpaceID: 101
        )
        sut.forceSpaceUpdate()

        // Then: Space 2 gets the default style on its display
        XCTAssertEqual(
            SpacePreferences.iconStyle(forSpace: 2, display: "Main", store: store),
            .circle,
            "New space should get default style per-display"
        )
    }

    // MARK: - Switching Without New Space

    func testSwitchingSpaces_doesNotApplyDefault() {
        // Given: Default style saved, 3 spaces
        SpacePreferences.setIconStyle(.circle, forSpace: 1, store: store)
        SpacePreferences.saveDefaultStyle(fromSpace: 1, store: store)

        sut = makeAppState(
            spaces: [(100, false), (101, false), (102, false)],
            activeSpaceID: 100
        )

        // When: Switch to space 2 (no new space created)
        updateStub(
            spaces: [(100, false), (101, false), (102, false)],
            activeSpaceID: 101
        )
        sut.forceSpaceUpdate()

        // Then: Space 2 should not get the default style
        XCTAssertNil(
            SpacePreferences.iconStyle(forSpace: 2, store: store),
            "Switching spaces should not apply default style"
        )
    }
}
