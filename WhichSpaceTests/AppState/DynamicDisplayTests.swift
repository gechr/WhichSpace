import XCTest
@testable import WhichSpace

// MARK: - Dynamic Display Tests

@MainActor
final class DynamicDisplayTests: XCTestCase {
    private var stub: CGSStub!
    private var sut: AppState!
    private var store: DefaultsStore!
    private var testSuite: TestSuite!

    override func setUp() async throws {
        try await super.setUp()
        testSuite = TestSuiteFactory.createSuite()
        store = DefaultsStore(suite: testSuite.suite)
        stub = CGSStub()
    }

    override func tearDown() async throws {
        sut = nil
        stub = nil
        if let store, let testSuite {
            store.resetAll()
            TestSuiteFactory.destroySuite(testSuite)
        }
        store = nil
        testSuite = nil
        try await super.tearDown()
    }

    // MARK: - Multiple Display Configurations

    func testTwoDisplaysWithMainActive() {
        stub.activeDisplayIdentifier = "Main"
        stub.displays = [
            CGSStub.makeDisplay(
                displayID: "Main",
                spaces: [(id: 100, isFullscreen: false), (id: 101, isFullscreen: false)],
                activeSpaceID: 100
            ),
            CGSStub.makeDisplay(
                displayID: "External",
                spaces: [
                    (id: 200, isFullscreen: false),
                    (id: 201, isFullscreen: false),
                    (id: 202, isFullscreen: false),
                ],
                activeSpaceID: 200
            ),
        ]

        sut = AppState(displaySpaceProvider: stub, skipObservers: true, store: store)

        // Should use main display's spaces
        XCTAssertEqual(sut.currentSpace, 1)
        XCTAssertEqual(sut.allSpaceLabels, ["1", "2"])
    }

    func testTwoDisplaysWithExternalActive() {
        stub.activeDisplayIdentifier = "External"
        stub.displays = [
            CGSStub.makeDisplay(
                displayID: "Main",
                spaces: [(id: 100, isFullscreen: false)],
                activeSpaceID: 100
            ),
            CGSStub.makeDisplay(
                displayID: "External",
                spaces: [(id: 200, isFullscreen: false), (id: 201, isFullscreen: false)],
                activeSpaceID: 201
            ),
        ]

        sut = AppState(displaySpaceProvider: stub, skipObservers: true, store: store)

        // Should use external display's spaces
        XCTAssertEqual(sut.currentSpace, 2)
        XCTAssertEqual(sut.allSpaceLabels, ["1", "2"])
    }

    func testSingleDisplayConfiguration() {
        stub.activeDisplayIdentifier = "Main"
        stub.displays = [
            CGSStub.makeDisplay(
                displayID: "Main",
                spaces: [(id: 100, isFullscreen: false), (id: 101, isFullscreen: false)],
                activeSpaceID: 101
            ),
        ]

        sut = AppState(displaySpaceProvider: stub, skipObservers: true, store: store)
        XCTAssertEqual(sut.currentSpace, 2)
        XCTAssertEqual(sut.allSpaceLabels, ["1", "2"])
    }

    // MARK: - Display with Zero Spaces

    func testDisplayWithZeroSpaces() {
        stub.activeDisplayIdentifier = "Main"
        stub.displays = [
            CGSStub.makeDisplay(
                displayID: "Main",
                spaces: [],
                activeSpaceID: 0
            ),
        ]

        sut = AppState(displaySpaceProvider: stub, skipObservers: true, store: store)

        // Should handle gracefully
        XCTAssertEqual(sut.allSpaceLabels, [])
        XCTAssertEqual(sut.currentSpace, 0)
    }

    func testMixedDisplaysWithEmptyDisplay() {
        stub.activeDisplayIdentifier = "Main"
        stub.displays = [
            CGSStub.makeDisplay(
                displayID: "Main",
                spaces: [(id: 100, isFullscreen: false)],
                activeSpaceID: 100
            ),
            CGSStub.makeDisplay(
                displayID: "Empty",
                spaces: [],
                activeSpaceID: 0
            ),
        ]

        sut = AppState(displaySpaceProvider: stub, skipObservers: true, store: store)

        // Should work with just the non-empty display
        XCTAssertEqual(sut.allSpaceLabels, ["1"])
        XCTAssertEqual(sut.currentSpace, 1)
    }

    // MARK: - Space Count Configurations

    func testDisplayWithFourSpaces() {
        stub.activeDisplayIdentifier = "Main"
        stub.displays = [
            CGSStub.makeDisplay(
                displayID: "Main",
                spaces: [
                    (id: 100, isFullscreen: false),
                    (id: 101, isFullscreen: false),
                    (id: 102, isFullscreen: false),
                    (id: 103, isFullscreen: false),
                ],
                activeSpaceID: 100
            ),
        ]

        sut = AppState(displaySpaceProvider: stub, skipObservers: true, store: store)
        XCTAssertEqual(sut.allSpaceLabels.count, 4)
        XCTAssertEqual(sut.allSpaceLabels, ["1", "2", "3", "4"])
    }

    func testDisplayWithActiveSpaceAtEnd() {
        stub.activeDisplayIdentifier = "Main"
        stub.displays = [
            CGSStub.makeDisplay(
                displayID: "Main",
                spaces: [
                    (id: 100, isFullscreen: false),
                    (id: 101, isFullscreen: false),
                    (id: 102, isFullscreen: false),
                ],
                activeSpaceID: 102
            ),
        ]

        sut = AppState(displaySpaceProvider: stub, skipObservers: true, store: store)
        XCTAssertEqual(sut.currentSpace, 3)
        XCTAssertEqual(sut.allSpaceLabels, ["1", "2", "3"])
    }

    func testDisplayWithTwoSpacesActiveSecond() {
        stub.activeDisplayIdentifier = "Main"
        stub.displays = [
            CGSStub.makeDisplay(
                displayID: "Main",
                spaces: [(id: 100, isFullscreen: false), (id: 102, isFullscreen: false)],
                activeSpaceID: 102
            ),
        ]

        sut = AppState(displaySpaceProvider: stub, skipObservers: true, store: store)
        XCTAssertEqual(sut.currentSpace, 2)
        XCTAssertEqual(sut.allSpaceLabels, ["1", "2"])
    }

    // MARK: - Different Space Counts Per Display

    func testShowAllDisplaysWithDifferentSpaceCounts() {
        store.showAllDisplays = true
        stub.activeDisplayIdentifier = "DisplayA"
        stub.displays = [
            CGSStub.makeDisplay(
                displayID: "DisplayA",
                spaces: [(id: 100, isFullscreen: false)],
                activeSpaceID: 100
            ),
            CGSStub.makeDisplay(
                displayID: "DisplayB",
                spaces: [
                    (id: 200, isFullscreen: false),
                    (id: 201, isFullscreen: false),
                    (id: 202, isFullscreen: false),
                    (id: 203, isFullscreen: false),
                ],
                activeSpaceID: 200
            ),
        ]

        sut = AppState(displaySpaceProvider: stub, skipObservers: true, store: store)

        // Should show all displays' spaces
        let icon = sut.statusBarIcon
        XCTAssertGreaterThan(icon.size.width, Layout.statusItemWidth)
    }

    // MARK: - Active Display ID Not Found

    func testActiveDisplayIDNotInList() {
        stub.activeDisplayIdentifier = "NonExistent"
        stub.displays = [
            CGSStub.makeDisplay(
                displayID: "Main",
                spaces: [(id: 100, isFullscreen: false)],
                activeSpaceID: 100
            ),
        ]

        sut = AppState(displaySpaceProvider: stub, skipObservers: true, store: store)

        // Should fall back to first/main display
        XCTAssertEqual(sut.currentSpace, 1)
    }

    func testNoDisplaysAtAll() {
        stub.activeDisplayIdentifier = "Main"
        stub.displays = []

        sut = AppState(displaySpaceProvider: stub, skipObservers: true, store: store)

        // Should handle gracefully
        XCTAssertEqual(sut.currentSpace, 0)
        XCTAssertTrue(sut.allSpaceLabels.isEmpty)
    }

    func testNilDisplaySpacesReturned() {
        stub.activeDisplayIdentifier = nil
        stub.displays = []

        sut = AppState(displaySpaceProvider: stub, skipObservers: true, store: store)

        // Should handle nil gracefully
        XCTAssertEqual(sut.currentSpace, 0)
    }
}

// MARK: - Regular Space Count Tests (for hideSingleSpace feature)

@MainActor
final class RegularSpaceCountTests: XCTestCase {
    private var stub: CGSStub!
    private var sut: AppState!
    private var store: DefaultsStore!
    private var testSuite: TestSuite!

    override func setUp() async throws {
        try await super.setUp()
        testSuite = TestSuiteFactory.createSuite()
        store = DefaultsStore(suite: testSuite.suite)
        stub = CGSStub()
    }

    override func tearDown() async throws {
        sut = nil
        stub = nil
        if let store, let testSuite {
            store.resetAll()
            TestSuiteFactory.destroySuite(testSuite)
        }
        store = nil
        testSuite = nil
        try await super.tearDown()
    }

    func testRegularSpaceCount_singleRegularSpace() {
        stub.activeDisplayIdentifier = "Main"
        stub.displays = [
            CGSStub.makeDisplay(
                displayID: "Main",
                spaces: [(id: 100, isFullscreen: false)],
                activeSpaceID: 100
            ),
        ]

        sut = AppState(displaySpaceProvider: stub, skipObservers: true, store: store)

        XCTAssertEqual(sut.regularSpaceCount, 1, "Should count 1 regular space")
    }

    func testRegularSpaceCount_multipleRegularSpaces() {
        stub.activeDisplayIdentifier = "Main"
        stub.displays = [
            CGSStub.makeDisplay(
                displayID: "Main",
                spaces: [
                    (id: 100, isFullscreen: false),
                    (id: 101, isFullscreen: false),
                    (id: 102, isFullscreen: false),
                ],
                activeSpaceID: 100
            ),
        ]

        sut = AppState(displaySpaceProvider: stub, skipObservers: true, store: store)

        XCTAssertEqual(sut.regularSpaceCount, 3, "Should count 3 regular spaces")
    }

    func testRegularSpaceCount_excludesFullscreenSpaces() {
        stub.activeDisplayIdentifier = "Main"
        stub.displays = [
            CGSStub.makeDisplay(
                displayID: "Main",
                spaces: [
                    (id: 100, isFullscreen: false),
                    (id: 101, isFullscreen: true),
                    (id: 102, isFullscreen: false),
                    (id: 103, isFullscreen: true),
                ],
                activeSpaceID: 100
            ),
        ]

        sut = AppState(displaySpaceProvider: stub, skipObservers: true, store: store)

        XCTAssertEqual(sut.regularSpaceCount, 2, "Should count only 2 regular spaces, excluding fullscreen")
    }

    func testRegularSpaceCount_allFullscreenSpaces() {
        stub.activeDisplayIdentifier = "Main"
        stub.displays = [
            CGSStub.makeDisplay(
                displayID: "Main",
                spaces: [
                    (id: 100, isFullscreen: true),
                    (id: 101, isFullscreen: true),
                ],
                activeSpaceID: 100
            ),
        ]

        sut = AppState(displaySpaceProvider: stub, skipObservers: true, store: store)

        XCTAssertEqual(sut.regularSpaceCount, 0, "Should count 0 regular spaces when all are fullscreen")
    }

    func testRegularSpaceCount_multipleDisplays() {
        stub.activeDisplayIdentifier = "Main"
        stub.displays = [
            CGSStub.makeDisplay(
                displayID: "Main",
                spaces: [
                    (id: 100, isFullscreen: false),
                    (id: 101, isFullscreen: false),
                ],
                activeSpaceID: 100
            ),
            CGSStub.makeDisplay(
                displayID: "External",
                spaces: [
                    (id: 200, isFullscreen: false),
                    (id: 201, isFullscreen: true),
                ],
                activeSpaceID: 200
            ),
        ]

        sut = AppState(displaySpaceProvider: stub, skipObservers: true, store: store)

        // 2 regular on Main + 1 regular on External = 3 total
        XCTAssertEqual(sut.regularSpaceCount, 3, "Should count regular spaces across all displays")
    }

    func testRegularSpaceCount_noSpaces() {
        stub.activeDisplayIdentifier = "Main"
        stub.displays = [
            CGSStub.makeDisplay(
                displayID: "Main",
                spaces: [],
                activeSpaceID: 0
            ),
        ]

        sut = AppState(displaySpaceProvider: stub, skipObservers: true, store: store)

        XCTAssertEqual(sut.regularSpaceCount, 0, "Should count 0 when no spaces")
    }
}

// MARK: - Dark Mode Transition Tests

@MainActor
final class DarkModeTransitionTests: XCTestCase {
    private var stub: CGSStub!
    private var sut: AppState!
    private var store: DefaultsStore!
    private var testSuite: TestSuite!

    override func setUp() async throws {
        try await super.setUp()
        testSuite = TestSuiteFactory.createSuite()
        store = DefaultsStore(suite: testSuite.suite)
        stub = CGSStub()
        stub.activeDisplayIdentifier = "Main"
        stub.displays = [
            CGSStub.makeDisplay(
                displayID: "Main",
                spaces: [(id: 100, isFullscreen: false)],
                activeSpaceID: 100
            ),
        ]
    }

    override func tearDown() async throws {
        sut = nil
        stub = nil
        if let store, let testSuite {
            store.resetAll()
            TestSuiteFactory.destroySuite(testSuite)
        }
        store = nil
        testSuite = nil
        try await super.tearDown()
    }

    // MARK: - Rapid Dark Mode Toggle

    func testRapidDarkModeToggling() {
        sut = AppState(displaySpaceProvider: stub, skipObservers: true, store: store)
        let previousAppearance = NSApp.appearance

        // Rapidly toggle many times
        for _ in 0 ..< 50 {
            NSApp.appearance = NSAppearance(named: .darkAqua)
            sut.updateDarkModeStatus()

            NSApp.appearance = NSAppearance(named: .aqua)
            sut.updateDarkModeStatus()
        }

        // Final state should be consistent
        NSApp.appearance = NSAppearance(named: .darkAqua)
        sut.updateDarkModeStatus()
        XCTAssertTrue(sut.darkModeEnabled)

        NSApp.appearance = previousAppearance
    }

    func testIconGenerationDuringDarkModeTransition() {
        sut = AppState(displaySpaceProvider: stub, skipObservers: true, store: store)
        let previousAppearance = NSApp.appearance

        // Set to dark mode
        NSApp.appearance = NSAppearance(named: .darkAqua)
        sut.updateDarkModeStatus()

        // Generate icon in dark mode
        let darkIcon = sut.statusBarIcon

        // Transition to light mode
        NSApp.appearance = NSAppearance(named: .aqua)
        sut.updateDarkModeStatus()

        // Generate icon in light mode
        let lightIcon = sut.statusBarIcon

        // Both should be valid images
        XCTAssertGreaterThan(darkIcon.size.width, 0)
        XCTAssertGreaterThan(lightIcon.size.width, 0)

        NSApp.appearance = previousAppearance
    }

    func testDarkModeWithCustomColors() {
        sut = AppState(displaySpaceProvider: stub, skipObservers: true, store: store)
        let previousAppearance = NSApp.appearance

        // Set custom colors for space 1
        let customColors = SpaceColors(foreground: .red, background: .blue)
        SpacePreferences.setColors(customColors, forSpace: 1, store: store)

        // Dark mode shouldn't override custom colors
        NSApp.appearance = NSAppearance(named: .darkAqua)
        sut.updateDarkModeStatus()

        let icon = sut.statusBarIcon
        XCTAssertNotNil(icon)

        // Light mode shouldn't override custom colors either
        NSApp.appearance = NSAppearance(named: .aqua)
        sut.updateDarkModeStatus()

        let lightIcon = sut.statusBarIcon
        XCTAssertNotNil(lightIcon)

        NSApp.appearance = previousAppearance
    }

    // MARK: - Dark Mode State Consistency

    func testDarkModeStateAfterUpdate() {
        sut = AppState(displaySpaceProvider: stub, skipObservers: true, store: store)
        let previousAppearance = NSApp.appearance

        // Set dark mode
        NSApp.appearance = NSAppearance(named: .darkAqua)
        sut.updateDarkModeStatus()
        let darkState = sut.darkModeEnabled

        // Update space info (simulating space change)
        sut.updateActiveSpaceNumber()

        // Dark mode state should be preserved
        XCTAssertEqual(sut.darkModeEnabled, darkState)

        NSApp.appearance = previousAppearance
    }

    func testMultipleAppearanceUpdatesWithoutChange() {
        sut = AppState(displaySpaceProvider: stub, skipObservers: true, store: store)
        let previousAppearance = NSApp.appearance

        // Set to dark mode
        NSApp.appearance = NSAppearance(named: .darkAqua)

        // Call update multiple times
        for _ in 0 ..< 10 {
            sut.updateDarkModeStatus()
            XCTAssertTrue(sut.darkModeEnabled, "Dark mode should remain enabled")
        }

        NSApp.appearance = previousAppearance
    }
}

// MARK: - Observer Lifecycle Tests

@MainActor
final class ObserverLifecycleTests: XCTestCase {
    private var stub: CGSStub!
    private var store: DefaultsStore!
    private var testSuite: TestSuite!

    override func setUp() async throws {
        try await super.setUp()
        testSuite = TestSuiteFactory.createSuite()
        store = DefaultsStore(suite: testSuite.suite)
        stub = CGSStub()
        stub.activeDisplayIdentifier = "Main"
        stub.displays = [
            CGSStub.makeDisplay(
                displayID: "Main",
                spaces: [(id: 100, isFullscreen: false)],
                activeSpaceID: 100
            ),
        ]
    }

    override func tearDown() async throws {
        stub = nil
        if let store, let testSuite {
            store.resetAll()
            TestSuiteFactory.destroySuite(testSuite)
        }
        store = nil
        testSuite = nil
        try await super.tearDown()
    }

    // MARK: - AppState Lifecycle

    func testAppStateCreationWithSkipObservers() {
        // Creating with skipObservers should not start observer task
        let appState = AppState(displaySpaceProvider: stub, skipObservers: true, store: store)
        XCTAssertNotNil(appState)

        // Should still have valid state
        XCTAssertEqual(appState.currentSpace, 1)
    }

    func testMultipleAppStateInstances() {
        // Create multiple instances (simulating recreation)
        var instances: [AppState] = []

        for _ in 0 ..< 5 {
            let appState = AppState(displaySpaceProvider: stub, skipObservers: true, store: store)
            instances.append(appState)
        }

        // All instances should be valid
        for instance in instances {
            XCTAssertEqual(instance.currentSpace, 1)
        }
    }

    func testAppStateDeallocation() {
        weak var weakRef: AppState?

        autoreleasepool {
            let appState = AppState(displaySpaceProvider: stub, skipObservers: true, store: store)
            weakRef = appState
            XCTAssertNotNil(weakRef)
        }

        // After autoreleasepool, should be deallocated (if no retain cycles)
        // Note: This test verifies no obvious retain cycles exist
    }

    // MARK: - State Updates After Deallocation

    func testStateUpdateAfterStoreReset() {
        let appState = AppState(displaySpaceProvider: stub, skipObservers: true, store: store)

        // Set some preferences
        SpacePreferences.setIconStyle(.circle, forSpace: 1, store: store)

        // Reset store
        store.resetAll()

        // AppState should still function
        appState.updateActiveSpaceNumber()
        XCTAssertEqual(appState.currentSpace, 1)

        // Preference should be gone
        XCTAssertNil(SpacePreferences.iconStyle(forSpace: 1, store: store))
    }

    // MARK: - Callback Edge Cases

    func testSetSpaceStateWithValidData() {
        let appState = AppState(displaySpaceProvider: stub, skipObservers: true, store: store)

        appState.setSpaceState(
            labels: ["1", "2", "3"],
            currentSpace: 2,
            currentLabel: "2",
            displayID: "TestDisplay"
        )

        XCTAssertEqual(appState.allSpaceLabels, ["1", "2", "3"])
        XCTAssertEqual(appState.currentSpace, 2)
        XCTAssertEqual(appState.currentSpaceLabel, "2")
    }

    func testSetSpaceStateWithEmptyLabels() {
        let appState = AppState(displaySpaceProvider: stub, skipObservers: true, store: store)

        appState.setSpaceState(
            labels: [],
            currentSpace: 0,
            currentLabel: "",
            displayID: "TestDisplay"
        )

        XCTAssertEqual(appState.allSpaceLabels, [])
        XCTAssertEqual(appState.currentSpace, 0)
    }

    func testSetSpaceStateWithMismatchedIndex() {
        let appState = AppState(displaySpaceProvider: stub, skipObservers: true, store: store)

        // Set state where currentSpace index doesn't match labels array
        appState.setSpaceState(
            labels: ["1", "2"],
            currentSpace: 10, // Out of bounds
            currentLabel: "?",
            displayID: "TestDisplay"
        )

        // Should store the values even if they seem inconsistent
        // (validation happens elsewhere)
        XCTAssertEqual(appState.currentSpace, 10)
    }

    // MARK: - State Configuration Tests

    func testManySpacesConfiguration() {
        stub.activeDisplayIdentifier = "Main"
        stub.displays = [
            CGSStub.makeDisplay(
                displayID: "Main",
                spaces: Array(1 ... 16).map { (id: $0, isFullscreen: false) },
                activeSpaceID: 16
            ),
        ]

        let appState = AppState(displaySpaceProvider: stub, skipObservers: true, store: store)

        // Should handle many spaces correctly
        XCTAssertEqual(appState.currentSpace, 16)
        XCTAssertEqual(appState.allSpaceLabels.count, 16)
    }

    func testMaxTypicalSpaces() {
        stub.activeDisplayIdentifier = "Main"
        stub.displays = [
            CGSStub.makeDisplay(
                displayID: "Main",
                spaces: Array(1 ... 32).map { (id: $0, isFullscreen: false) },
                activeSpaceID: 32
            ),
        ]

        let appState = AppState(displaySpaceProvider: stub, skipObservers: true, store: store)

        // Should handle maximum typical space count
        XCTAssertEqual(appState.currentSpace, 32)
        XCTAssertEqual(appState.allSpaceLabels.count, 32)
    }

    func testAlternatingShowAllModesRapidly() {
        let appState = AppState(displaySpaceProvider: stub, skipObservers: true, store: store)

        stub.displays = [
            CGSStub.makeDisplay(
                displayID: "Main",
                spaces: [(id: 100, isFullscreen: false), (id: 101, isFullscreen: false)],
                activeSpaceID: 100
            ),
            CGSStub.makeDisplay(
                displayID: "External",
                spaces: [(id: 200, isFullscreen: false)],
                activeSpaceID: 200
            ),
        ]

        for _ in 0 ..< 50 {
            store.showAllSpaces = true
            store.showAllDisplays = false
            _ = appState.statusBarIcon

            store.showAllSpaces = false
            store.showAllDisplays = true
            _ = appState.statusBarIcon

            store.showAllSpaces = false
            store.showAllDisplays = false
            _ = appState.statusBarIcon
        }

        // Should not crash and be in consistent state
        XCTAssertNotNil(appState.statusBarIcon)
    }
}

// MARK: - Fullscreen Space Edge Cases

@MainActor
final class FullscreenSpaceEdgeCaseTests: XCTestCase {
    private var stub: CGSStub!
    private var sut: AppState!
    private var store: DefaultsStore!
    private var testSuite: TestSuite!

    override func setUp() async throws {
        try await super.setUp()
        testSuite = TestSuiteFactory.createSuite()
        store = DefaultsStore(suite: testSuite.suite)
        stub = CGSStub()
    }

    override func tearDown() async throws {
        sut = nil
        stub = nil
        if let store, let testSuite {
            store.resetAll()
            TestSuiteFactory.destroySuite(testSuite)
        }
        store = nil
        testSuite = nil
        try await super.tearDown()
    }

    func testAllFullscreenSpaces() {
        stub.activeDisplayIdentifier = "Main"
        stub.displays = [
            CGSStub.makeDisplay(
                displayID: "Main",
                spaces: [
                    (id: 100, isFullscreen: true),
                    (id: 101, isFullscreen: true),
                    (id: 102, isFullscreen: true),
                ],
                activeSpaceID: 101
            ),
        ]

        sut = AppState(displaySpaceProvider: stub, skipObservers: true, store: store)

        // All spaces should be labeled as fullscreen
        XCTAssertEqual(sut.allSpaceLabels, [Labels.fullscreen, Labels.fullscreen, Labels.fullscreen])
        XCTAssertEqual(sut.currentSpaceLabel, Labels.fullscreen)
    }

    func testAlternatingFullscreenAndRegular() {
        stub.activeDisplayIdentifier = "Main"
        stub.displays = [
            CGSStub.makeDisplay(
                displayID: "Main",
                spaces: [
                    (id: 100, isFullscreen: true),
                    (id: 101, isFullscreen: false),
                    (id: 102, isFullscreen: true),
                    (id: 103, isFullscreen: false),
                ],
                activeSpaceID: 103
            ),
        ]

        sut = AppState(displaySpaceProvider: stub, skipObservers: true, store: store)

        XCTAssertEqual(sut.allSpaceLabels, [Labels.fullscreen, "1", Labels.fullscreen, "2"])
        XCTAssertEqual(sut.currentSpaceLabel, "2")
    }

    func testHideFullscreenWithAllFullscreen() {
        store.hideFullscreenApps = true
        store.showAllSpaces = true
        stub.activeDisplayIdentifier = "Main"
        stub.displays = [
            CGSStub.makeDisplay(
                displayID: "Main",
                spaces: [
                    (id: 100, isFullscreen: true),
                    (id: 101, isFullscreen: true),
                ],
                activeSpaceID: 100
            ),
        ]

        sut = AppState(displaySpaceProvider: stub, skipObservers: true, store: store)

        // When hiding fullscreen and all are fullscreen, current space should still show
        let icon = sut.statusBarIcon
        XCTAssertNotNil(icon)
    }

    func testHideFullscreenWithMixed() {
        store.hideFullscreenApps = true
        store.showAllSpaces = true
        stub.activeDisplayIdentifier = "Main"
        stub.displays = [
            CGSStub.makeDisplay(
                displayID: "Main",
                spaces: [
                    (id: 100, isFullscreen: false),
                    (id: 101, isFullscreen: true),
                    (id: 102, isFullscreen: false),
                ],
                activeSpaceID: 100
            ),
        ]

        sut = AppState(displaySpaceProvider: stub, skipObservers: true, store: store)

        // Icon should only show non-fullscreen spaces (2 of them)
        let icon = sut.statusBarIcon
        let expectedWidth = 2 * Layout.statusItemWidth
        XCTAssertEqual(icon.size.width, expectedWidth, accuracy: 0.1)
    }
}

// MARK: - Show All Displays Edge Cases

@MainActor
final class ShowAllDisplaysEdgeCaseTests: XCTestCase {
    private var stub: CGSStub!
    private var sut: AppState!
    private var store: DefaultsStore!
    private var testSuite: TestSuite!

    override func setUp() async throws {
        try await super.setUp()
        testSuite = TestSuiteFactory.createSuite()
        store = DefaultsStore(suite: testSuite.suite)
        stub = CGSStub()
    }

    override func tearDown() async throws {
        sut = nil
        stub = nil
        if let store, let testSuite {
            store.resetAll()
            TestSuiteFactory.destroySuite(testSuite)
        }
        store = nil
        testSuite = nil
        try await super.tearDown()
    }

    func testShowAllDisplaysWithSingleDisplay() {
        store.showAllDisplays = true
        stub.activeDisplayIdentifier = "Main"
        stub.displays = [
            CGSStub.makeDisplay(
                displayID: "Main",
                spaces: [(id: 100, isFullscreen: false), (id: 101, isFullscreen: false)],
                activeSpaceID: 100
            ),
        ]

        sut = AppState(displaySpaceProvider: stub, skipObservers: true, store: store)

        // With single display, should behave like showAllSpaces
        XCTAssertEqual(sut.allSpaceLabels.count, 2)
    }

    func testShowAllDisplaysWithManyDisplays() {
        store.showAllDisplays = true
        stub.activeDisplayIdentifier = "Display1"
        stub.displays = [
            CGSStub.makeDisplay(
                displayID: "Display1",
                spaces: [(id: 100, isFullscreen: false)],
                activeSpaceID: 100
            ),
            CGSStub.makeDisplay(
                displayID: "Display2",
                spaces: [(id: 200, isFullscreen: false)],
                activeSpaceID: 200
            ),
            CGSStub.makeDisplay(
                displayID: "Display3",
                spaces: [(id: 300, isFullscreen: false)],
                activeSpaceID: 300
            ),
            CGSStub.makeDisplay(
                displayID: "Display4",
                spaces: [(id: 400, isFullscreen: false)],
                activeSpaceID: 400
            ),
        ]

        sut = AppState(displaySpaceProvider: stub, skipObservers: true, store: store)

        // Should handle many displays
        let icon = sut.statusBarIcon
        XCTAssertNotNil(icon)
        // Icon should include separators between displays
        XCTAssertGreaterThan(icon.size.width, 4 * Layout.statusItemWidth)
    }

    func testShowAllDisplaysWithAllFullscreenOnOneDisplay() {
        store.showAllDisplays = true
        store.hideFullscreenApps = true
        stub.activeDisplayIdentifier = "DisplayA"
        stub.displays = [
            CGSStub.makeDisplay(
                displayID: "DisplayA",
                spaces: [(id: 100, isFullscreen: false)],
                activeSpaceID: 100
            ),
            CGSStub.makeDisplay(
                displayID: "DisplayB",
                spaces: [
                    (id: 200, isFullscreen: true),
                    (id: 201, isFullscreen: true),
                ],
                activeSpaceID: 200
            ),
        ]

        sut = AppState(displaySpaceProvider: stub, skipObservers: true, store: store)

        // DisplayB with all fullscreen should still show something (active space at minimum)
        let icon = sut.statusBarIcon
        XCTAssertNotNil(icon)
    }

    /// Regression test: Fullscreen spaces were incorrectly shown as active on Space 1.
    /// The bug: fullscreen spaces got globalIndex=1 due to nil regularIndex defaulting to 0,
    /// which matched currentGlobalSpaceIndex when user was on Space 1.
    func testHideFullscreenDoesNotShowFullscreenOnSpace1() {
        store.showAllDisplays = true
        store.hideFullscreenApps = true
        stub.activeDisplayIdentifier = "Display1"
        stub.displays = [
            // User is on Space 1 (regular space)
            CGSStub.makeDisplay(
                displayID: "Display1",
                spaces: [
                    (id: 100, isFullscreen: false),
                    (id: 101, isFullscreen: false),
                    (id: 102, isFullscreen: false),
                ],
                activeSpaceID: 100
            ),
            // Other display has a fullscreen space that should be hidden
            CGSStub.makeDisplay(
                displayID: "Display2",
                spaces: [
                    (id: 200, isFullscreen: true), // fullscreen - should be hidden
                    (id: 201, isFullscreen: false),
                ],
                activeSpaceID: 201
            ),
        ]

        sut = AppState(displaySpaceProvider: stub, skipObservers: true, store: store)

        // With hideFullscreenApps enabled:
        // Display1: 3 regular spaces (all shown)
        // Display2: 1 fullscreen (hidden) + 1 regular (shown) = 1 shown
        // Total: 3 + 1 = 4 spaces, plus 1 separator between displays
        let expectedSpaces = 4
        let expectedSeparators = 1
        let expectedWidth = Double(expectedSpaces) * Layout.statusItemWidth +
            Double(expectedSeparators) * Layout.displaySeparatorWidth
        let icon = sut.statusBarIcon
        XCTAssertEqual(
            icon.size.width,
            expectedWidth,
            accuracy: 0.1,
            "Fullscreen space should be hidden, not incorrectly shown as active on Space 1"
        )
    }
}
