import XCTest
@testable import WhichSpace

@MainActor
final class SpaceInheritanceTests: XCTestCase {
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

    // MARK: - Inheritance on New Space

    func testNewSpace_inheritsStyleFromPreviousSpace() {
        // Given: 2 spaces, space 2 active with circle style
        sut = makeAppState(
            spaces: [(100, false), (101, false)],
            activeSpaceID: 101
        )
        SpacePreferences.setIconStyle(.circle, forSpace: 2, store: store)

        // When: A 3rd space is added
        updateStub(
            spaces: [(100, false), (101, false), (102, false)],
            activeSpaceID: 102
        )
        sut.forceSpaceUpdate()

        // Then: Space 3 inherits circle style from space 2
        XCTAssertEqual(
            SpacePreferences.iconStyle(forSpace: 3, store: store),
            .circle,
            "New space should inherit icon style from previous space"
        )
    }

    func testNewSpace_inheritsColorsFromPreviousSpace() {
        // Given: 2 spaces, space 1 active with custom colors
        let colors = SpaceColors(foreground: .red, background: .blue)
        sut = makeAppState(
            spaces: [(100, false), (101, false)],
            activeSpaceID: 100
        )
        SpacePreferences.setColors(colors, forSpace: 1, store: store)

        // When: A 3rd space is added
        updateStub(
            spaces: [(100, false), (101, false), (102, false)],
            activeSpaceID: 102
        )
        sut.forceSpaceUpdate()

        // Then: Space 3 inherits colors from space 1
        let inherited = SpacePreferences.colors(forSpace: 3, store: store)
        XCTAssertNotNil(inherited, "New space should inherit colors")
        XCTAssertEqual(inherited?.foreground, .red)
        XCTAssertEqual(inherited?.background, .blue)
    }

    func testNewSpace_inheritsSymbolFromPreviousSpace() {
        // Given: Space 1 active with a symbol
        sut = makeAppState(
            spaces: [(100, false)],
            activeSpaceID: 100
        )
        SpacePreferences.setSymbol("star.fill", forSpace: 1, store: store)

        // When: A 2nd space is added
        updateStub(
            spaces: [(100, false), (101, false)],
            activeSpaceID: 101
        )
        sut.forceSpaceUpdate()

        // Then: Space 2 inherits symbol
        XCTAssertEqual(
            SpacePreferences.symbol(forSpace: 2, store: store),
            "star.fill",
            "New space should inherit symbol from previous space"
        )
    }

    func testNewSpace_doesNotInheritWhenTargetHasPreferences() {
        // Given: 2 spaces, space 1 active with circle; space 3 pre-configured with hexagon
        sut = makeAppState(
            spaces: [(100, false), (101, false)],
            activeSpaceID: 100
        )
        SpacePreferences.setIconStyle(.circle, forSpace: 1, store: store)
        SpacePreferences.setIconStyle(.hexagon, forSpace: 3, store: store)

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

    func testNewSpace_doesNotInheritWhenSpaceCountDecreases() {
        // Given: 3 spaces, space 2 active with custom style
        sut = makeAppState(
            spaces: [(100, false), (101, false), (102, false)],
            activeSpaceID: 101
        )
        SpacePreferences.setIconStyle(.circle, forSpace: 2, store: store)

        // When: Space is removed (count decreases to 2)
        updateStub(
            spaces: [(100, false), (101, false)],
            activeSpaceID: 101
        )
        sut.forceSpaceUpdate()

        // Then: No inheritance should happen (space 2 keeps its style, no new space)
        XCTAssertEqual(SpacePreferences.iconStyle(forSpace: 2, store: store), .circle)
        XCTAssertNil(SpacePreferences.iconStyle(forSpace: 3, store: store))
    }

    func testNewSpace_doesNotInheritOnInitialLaunch() {
        // Given: First launch with 3 spaces, space 1 has custom style
        SpacePreferences.setIconStyle(.circle, forSpace: 1, store: store)

        // When: AppState is created (initial launch)
        sut = makeAppState(
            spaces: [(100, false), (101, false), (102, false)],
            activeSpaceID: 100
        )

        // Then: Space 2 and 3 should NOT inherit (no previous space info)
        XCTAssertNil(
            SpacePreferences.iconStyle(forSpace: 2, store: store),
            "Spaces should not inherit on initial launch"
        )
        XCTAssertNil(
            SpacePreferences.iconStyle(forSpace: 3, store: store),
            "Spaces should not inherit on initial launch"
        )
    }

    func testNewSpace_doesNotInheritWhenPreviousSpaceHasNoPreferences() {
        // Given: 2 spaces, space 2 active with no custom preferences
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

        // Then: Space 3 has no preferences (nothing to inherit)
        XCTAssertFalse(
            SpacePreferences.hasAnyPreference(forSpace: 3, store: store),
            "New space should have no preferences when previous space had none"
        )
    }

    func testNewSpace_inheritsMultiplePreferencesAtOnce() {
        // Given: Space 1 active with multiple customizations
        sut = makeAppState(
            spaces: [(100, false)],
            activeSpaceID: 100
        )
        SpacePreferences.setIconStyle(.circle, forSpace: 1, store: store)
        SpacePreferences.setColors(SpaceColors(foreground: .red, background: .blue), forSpace: 1, store: store)
        SpacePreferences.setSymbol("star", forSpace: 1, store: store)
        SpacePreferences.setBadge(SpaceBadge(character: "A", position: .topRight), forSpace: 1, store: store)

        // When: A 2nd space is added
        updateStub(
            spaces: [(100, false), (101, false)],
            activeSpaceID: 101
        )
        sut.forceSpaceUpdate()

        // Then: All preferences are inherited
        XCTAssertEqual(SpacePreferences.iconStyle(forSpace: 2, store: store), .circle)
        XCTAssertEqual(SpacePreferences.colors(forSpace: 2, store: store)?.foreground, .red)
        XCTAssertEqual(SpacePreferences.symbol(forSpace: 2, store: store), "star")
        XCTAssertEqual(SpacePreferences.badge(forSpace: 2, store: store)?.character, "A")
    }

    // MARK: - Per-Display Inheritance

    func testNewSpace_inheritsPerDisplay_whenEnabled() {
        store.uniqueIconsPerDisplay = true

        // Given: Space 1 active on Main display with circle style
        sut = makeAppState(
            spaces: [(100, false)],
            activeSpaceID: 100
        )
        SpacePreferences.setIconStyle(.circle, forSpace: 1, display: "Main", store: store)

        // When: A 2nd space is added
        updateStub(
            spaces: [(100, false), (101, false)],
            activeSpaceID: 101
        )
        sut.forceSpaceUpdate()

        // Then: Space 2 inherits on Main display
        XCTAssertEqual(
            SpacePreferences.iconStyle(forSpace: 2, display: "Main", store: store),
            .circle,
            "New space should inherit per-display style"
        )
    }

    // MARK: - Switching Without New Space

    func testSwitchingSpaces_doesNotTriggerInheritance() {
        // Given: 3 spaces, space 1 active with circle style
        sut = makeAppState(
            spaces: [(100, false), (101, false), (102, false)],
            activeSpaceID: 100
        )
        SpacePreferences.setIconStyle(.circle, forSpace: 1, store: store)

        // When: Switch to space 2 (no new space created)
        updateStub(
            spaces: [(100, false), (101, false), (102, false)],
            activeSpaceID: 101
        )
        sut.forceSpaceUpdate()

        // Then: Space 2 should not inherit from space 1
        XCTAssertNil(
            SpacePreferences.iconStyle(forSpace: 2, store: store),
            "Switching spaces should not trigger inheritance"
        )
    }
}
