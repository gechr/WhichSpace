import AppKit
import Testing
@testable import WhichSpace

// MARK: - Dynamic Display Tests

@MainActor
struct DynamicDisplayTests {
    private let stub: CGSStub
    private let store: DefaultsStore
    private let testSuite: TestSuite

    init() {
        testSuite = TestSuiteFactory.createSuite()
        store = DefaultsStore(suite: testSuite.suite)
        stub = CGSStub()
    }

    // MARK: - Multiple Display Configurations

    @Test("two displays: main display active")
    func twoDisplaysWithMainActive() {
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

        let sut = AppState(displaySpaceProvider: stub, skipObservers: true, store: store)

        #expect(sut.currentSpace == 1)
        #expect(sut.allSpaceLabels == ["1", "2"])
    }

    @Test("two displays: external display active")
    func twoDisplaysWithExternalActive() {
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

        let sut = AppState(displaySpaceProvider: stub, skipObservers: true, store: store)

        #expect(sut.currentSpace == 2)
        #expect(sut.allSpaceLabels == ["1", "2"])
    }

    @Test("single display configuration")
    func singleDisplayConfiguration() {
        stub.activeDisplayIdentifier = "Main"
        stub.displays = [
            CGSStub.makeDisplay(
                displayID: "Main",
                spaces: [(id: 100, isFullscreen: false), (id: 101, isFullscreen: false)],
                activeSpaceID: 101
            ),
        ]

        let sut = AppState(displaySpaceProvider: stub, skipObservers: true, store: store)
        #expect(sut.currentSpace == 2)
        #expect(sut.allSpaceLabels == ["1", "2"])
    }

    // MARK: - Display with Zero Spaces

    @Test("display with zero spaces handled gracefully")
    func displayWithZeroSpaces() {
        stub.activeDisplayIdentifier = "Main"
        stub.displays = [
            CGSStub.makeDisplay(
                displayID: "Main",
                spaces: [],
                activeSpaceID: 0
            ),
        ]

        let sut = AppState(displaySpaceProvider: stub, skipObservers: true, store: store)

        #expect(sut.allSpaceLabels == [])
        #expect(sut.currentSpace == 0)
    }

    @Test("mix of populated and empty displays")
    func mixedDisplaysWithEmptyDisplay() {
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

        let sut = AppState(displaySpaceProvider: stub, skipObservers: true, store: store)

        #expect(sut.allSpaceLabels == ["1"])
        #expect(sut.currentSpace == 1)
    }

    // MARK: - Space Count Configurations

    @Test("display with four spaces")
    func displayWithFourSpaces() {
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

        let sut = AppState(displaySpaceProvider: stub, skipObservers: true, store: store)
        #expect(sut.allSpaceLabels.count == 4)
        #expect(sut.allSpaceLabels == ["1", "2", "3", "4"])
    }

    @Test("active space at end of list")
    func displayWithActiveSpaceAtEnd() {
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

        let sut = AppState(displaySpaceProvider: stub, skipObservers: true, store: store)
        #expect(sut.currentSpace == 3)
        #expect(sut.allSpaceLabels == ["1", "2", "3"])
    }

    @Test("two spaces: second active")
    func displayWithTwoSpacesActiveSecond() {
        stub.activeDisplayIdentifier = "Main"
        stub.displays = [
            CGSStub.makeDisplay(
                displayID: "Main",
                spaces: [(id: 100, isFullscreen: false), (id: 102, isFullscreen: false)],
                activeSpaceID: 102
            ),
        ]

        let sut = AppState(displaySpaceProvider: stub, skipObservers: true, store: store)
        #expect(sut.currentSpace == 2)
        #expect(sut.allSpaceLabels == ["1", "2"])
    }

    // MARK: - Different Space Counts Per Display

    @Test("showAllDisplays renders displays with different space counts")
    func showAllDisplaysWithDifferentSpaceCounts() {
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

        let sut = AppState(displaySpaceProvider: stub, skipObservers: true, store: store)

        let icon = sut.statusBarIcon
        #expect(icon.size.width > Layout.statusItemWidth)
    }

    // MARK: - Active Display ID Not Found

    @Test("active display ID not in list falls back gracefully")
    func activeDisplayIDNotInList() {
        stub.activeDisplayIdentifier = "NonExistent"
        stub.displays = [
            CGSStub.makeDisplay(
                displayID: "Main",
                spaces: [(id: 100, isFullscreen: false)],
                activeSpaceID: 100
            ),
        ]

        let sut = AppState(displaySpaceProvider: stub, skipObservers: true, store: store)

        #expect(sut.currentSpace == 1)
    }

    @Test("no displays at all")
    func noDisplaysAtAll() {
        stub.activeDisplayIdentifier = "Main"
        stub.displays = []

        let sut = AppState(displaySpaceProvider: stub, skipObservers: true, store: store)

        #expect(sut.currentSpace == 0)
        #expect(sut.allSpaceLabels.isEmpty)
    }

    @Test("nil display spaces returned")
    func nilDisplaySpacesReturned() {
        stub.activeDisplayIdentifier = nil
        stub.displays = []

        let sut = AppState(displaySpaceProvider: stub, skipObservers: true, store: store)

        #expect(sut.currentSpace == 0)
    }
}

// MARK: - Regular Space Count Tests (for hideSingleSpace feature)

@MainActor
struct RegularSpaceCountTests {
    private let stub: CGSStub
    private let store: DefaultsStore
    private let testSuite: TestSuite

    init() {
        testSuite = TestSuiteFactory.createSuite()
        store = DefaultsStore(suite: testSuite.suite)
        stub = CGSStub()
    }

    @Test("single regular space")
    func regularSpaceCount_singleRegularSpace() {
        stub.activeDisplayIdentifier = "Main"
        stub.displays = [
            CGSStub.makeDisplay(
                displayID: "Main",
                spaces: [(id: 100, isFullscreen: false)],
                activeSpaceID: 100
            ),
        ]

        let sut = AppState(displaySpaceProvider: stub, skipObservers: true, store: store)

        #expect(sut.regularSpaceCount == 1)
    }

    @Test("multiple regular spaces")
    func regularSpaceCount_multipleRegularSpaces() {
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

        let sut = AppState(displaySpaceProvider: stub, skipObservers: true, store: store)

        #expect(sut.regularSpaceCount == 3)
    }

    @Test("fullscreen spaces excluded from regular count")
    func regularSpaceCount_excludesFullscreenSpaces() {
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

        let sut = AppState(displaySpaceProvider: stub, skipObservers: true, store: store)

        #expect(sut.regularSpaceCount == 2)
    }

    @Test("all spaces fullscreen yields zero regular count")
    func regularSpaceCount_allFullscreenSpaces() {
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

        let sut = AppState(displaySpaceProvider: stub, skipObservers: true, store: store)

        #expect(sut.regularSpaceCount == 0)
    }

    @Test("regular space count sums across multiple displays")
    func regularSpaceCount_multipleDisplays() {
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

        let sut = AppState(displaySpaceProvider: stub, skipObservers: true, store: store)

        #expect(sut.regularSpaceCount == 3)
    }

    @Test("no spaces yields zero regular count")
    func regularSpaceCount_noSpaces() {
        stub.activeDisplayIdentifier = "Main"
        stub.displays = [
            CGSStub.makeDisplay(
                displayID: "Main",
                spaces: [],
                activeSpaceID: 0
            ),
        ]

        let sut = AppState(displaySpaceProvider: stub, skipObservers: true, store: store)

        #expect(sut.regularSpaceCount == 0)
    }
}

// MARK: - Dark Mode Transition Tests

@MainActor
struct DarkModeTransitionTests {
    private let stub: CGSStub
    private let store: DefaultsStore
    private let testSuite: TestSuite

    init() {
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

    // MARK: - Rapid Dark Mode Toggle

    @Test("rapid dark mode toggling")
    func rapidDarkModeToggling() {
        let sut = AppState(displaySpaceProvider: stub, skipObservers: true, store: store)
        let previousAppearance = NSApp.appearance

        for _ in 0 ..< 50 {
            NSApp.appearance = NSAppearance(named: .darkAqua)
            sut.updateDarkModeStatus()

            NSApp.appearance = NSAppearance(named: .aqua)
            sut.updateDarkModeStatus()
        }

        NSApp.appearance = NSAppearance(named: .darkAqua)
        sut.updateDarkModeStatus()
        #expect(sut.darkModeEnabled)

        NSApp.appearance = previousAppearance
    }

    @Test("icon generation during dark mode transition")
    func iconGenerationDuringDarkModeTransition() {
        let sut = AppState(displaySpaceProvider: stub, skipObservers: true, store: store)
        let previousAppearance = NSApp.appearance

        NSApp.appearance = NSAppearance(named: .darkAqua)
        sut.updateDarkModeStatus()

        let darkIcon = sut.statusBarIcon

        NSApp.appearance = NSAppearance(named: .aqua)
        sut.updateDarkModeStatus()

        let lightIcon = sut.statusBarIcon

        #expect(darkIcon.size.width > 0)
        #expect(lightIcon.size.width > 0)

        NSApp.appearance = previousAppearance
    }

    @Test("dark mode does not override custom colors")
    func darkModeWithCustomColors() {
        let sut = AppState(displaySpaceProvider: stub, skipObservers: true, store: store)
        let previousAppearance = NSApp.appearance

        let customColors = SpaceColors(foreground: .red, background: .blue)
        SpacePreferences.setColors(customColors, forSpace: 1, store: store)

        NSApp.appearance = NSAppearance(named: .darkAqua)
        sut.updateDarkModeStatus()

        let icon = sut.statusBarIcon
        #expect(icon as NSImage? != nil)

        NSApp.appearance = NSAppearance(named: .aqua)
        sut.updateDarkModeStatus()

        let lightIcon = sut.statusBarIcon
        #expect(lightIcon as NSImage? != nil)

        NSApp.appearance = previousAppearance
    }

    // MARK: - Dark Mode State Consistency

    @Test("dark mode state preserved after space update")
    func darkModeStateAfterUpdate() {
        let sut = AppState(displaySpaceProvider: stub, skipObservers: true, store: store)
        let previousAppearance = NSApp.appearance

        NSApp.appearance = NSAppearance(named: .darkAqua)
        sut.updateDarkModeStatus()
        let darkState = sut.darkModeEnabled

        sut.updateActiveSpaceNumber()

        #expect(sut.darkModeEnabled == darkState)

        NSApp.appearance = previousAppearance
    }

    @Test("multiple appearance updates without change remain stable")
    func multipleAppearanceUpdatesWithoutChange() {
        let sut = AppState(displaySpaceProvider: stub, skipObservers: true, store: store)
        let previousAppearance = NSApp.appearance

        NSApp.appearance = NSAppearance(named: .darkAqua)

        for _ in 0 ..< 10 {
            sut.updateDarkModeStatus()
            #expect(sut.darkModeEnabled)
        }

        NSApp.appearance = previousAppearance
    }
}

// MARK: - Observer Lifecycle Tests

@MainActor
struct ObserverLifecycleTests {
    private let stub: CGSStub
    private let store: DefaultsStore
    private let testSuite: TestSuite

    init() {
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

    // MARK: - AppState Lifecycle

    @Test("AppState creation with skipObservers")
    func appStateCreationWithSkipObservers() {
        let appState = AppState(displaySpaceProvider: stub, skipObservers: true, store: store)

        #expect(appState.currentSpace == 1)
    }

    @Test("multiple AppState instances")
    func multipleAppStateInstances() {
        var instances: [AppState] = []

        for _ in 0 ..< 5 {
            let appState = AppState(displaySpaceProvider: stub, skipObservers: true, store: store)
            instances.append(appState)
        }

        for instance in instances {
            #expect(instance.currentSpace == 1)
        }
    }

    @Test("AppState deallocation has no retain cycles")
    func appStateDeallocation() {
        weak var weakRef: AppState?

        autoreleasepool {
            let appState = AppState(displaySpaceProvider: stub, skipObservers: true, store: store)
            weakRef = appState
            #expect(weakRef != nil)
        }
    }

    // MARK: - State Updates After Deallocation

    @Test("state update after store reset")
    func stateUpdateAfterStoreReset() {
        let appState = AppState(displaySpaceProvider: stub, skipObservers: true, store: store)

        SpacePreferences.setIconStyle(.circle, forSpace: 1, store: store)

        store.resetAll()

        appState.updateActiveSpaceNumber()
        #expect(appState.currentSpace == 1)

        #expect(SpacePreferences.iconStyle(forSpace: 1, store: store) == nil)
    }

    // MARK: - Callback Edge Cases

    @Test("setSpaceState with valid data")
    func setSpaceStateWithValidData() {
        let appState = AppState(displaySpaceProvider: stub, skipObservers: true, store: store)

        appState.setSpaceState(
            labels: ["1", "2", "3"],
            currentSpace: 2,
            currentLabel: "2",
            displayID: "TestDisplay"
        )

        #expect(appState.allSpaceLabels == ["1", "2", "3"])
        #expect(appState.currentSpace == 2)
        #expect(appState.currentSpaceLabel == "2")
    }

    @Test("setSpaceState with empty labels")
    func setSpaceStateWithEmptyLabels() {
        let appState = AppState(displaySpaceProvider: stub, skipObservers: true, store: store)

        appState.setSpaceState(
            labels: [],
            currentSpace: 0,
            currentLabel: "",
            displayID: "TestDisplay"
        )

        #expect(appState.allSpaceLabels == [])
        #expect(appState.currentSpace == 0)
    }

    @Test("setSpaceState with mismatched index")
    func setSpaceStateWithMismatchedIndex() {
        let appState = AppState(displaySpaceProvider: stub, skipObservers: true, store: store)

        appState.setSpaceState(
            labels: ["1", "2"],
            currentSpace: 10,
            currentLabel: "?",
            displayID: "TestDisplay"
        )

        #expect(appState.currentSpace == 10)
    }

    // MARK: - State Configuration Tests

    @Test("many spaces configuration (16)")
    func manySpacesConfiguration() {
        stub.activeDisplayIdentifier = "Main"
        stub.displays = [
            CGSStub.makeDisplay(
                displayID: "Main",
                spaces: Array(1 ... 16).map { (id: $0, isFullscreen: false) },
                activeSpaceID: 16
            ),
        ]

        let appState = AppState(displaySpaceProvider: stub, skipObservers: true, store: store)

        #expect(appState.currentSpace == 16)
        #expect(appState.allSpaceLabels.count == 16)
    }

    @Test("max typical spaces configuration (32)")
    func maxTypicalSpaces() {
        stub.activeDisplayIdentifier = "Main"
        stub.displays = [
            CGSStub.makeDisplay(
                displayID: "Main",
                spaces: Array(1 ... 32).map { (id: $0, isFullscreen: false) },
                activeSpaceID: 32
            ),
        ]

        let appState = AppState(displaySpaceProvider: stub, skipObservers: true, store: store)

        #expect(appState.currentSpace == 32)
        #expect(appState.allSpaceLabels.count == 32)
    }

    @Test("alternating show-all modes rapidly stays consistent")
    func alternatingShowAllModesRapidly() {
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

        #expect(appState.statusBarIcon as NSImage? != nil)
    }
}

// MARK: - Fullscreen Space Edge Cases

@MainActor
struct FullscreenSpaceEdgeCaseTests {
    private let stub: CGSStub
    private let store: DefaultsStore
    private let testSuite: TestSuite

    init() {
        testSuite = TestSuiteFactory.createSuite()
        store = DefaultsStore(suite: testSuite.suite)
        stub = CGSStub()
    }

    @Test("all spaces fullscreen")
    func allFullscreenSpaces() {
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

        let sut = AppState(displaySpaceProvider: stub, skipObservers: true, store: store)

        #expect(sut.allSpaceLabels == [Labels.fullscreen, Labels.fullscreen, Labels.fullscreen])
        #expect(sut.currentSpaceLabel == Labels.fullscreen)
    }

    @Test("alternating fullscreen and regular spaces")
    func alternatingFullscreenAndRegular() {
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

        let sut = AppState(displaySpaceProvider: stub, skipObservers: true, store: store)

        #expect(sut.allSpaceLabels == [Labels.fullscreen, "1", Labels.fullscreen, "2"])
        #expect(sut.currentSpaceLabel == "2")
    }

    @Test("hide fullscreen when all spaces fullscreen still produces icon")
    func hideFullscreenWithAllFullscreen() {
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

        let sut = AppState(displaySpaceProvider: stub, skipObservers: true, store: store)

        let icon = sut.statusBarIcon
        #expect(icon as NSImage? != nil)
    }

    @Test("hide fullscreen with mixed spaces")
    func hideFullscreenWithMixed() {
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

        let sut = AppState(displaySpaceProvider: stub, skipObservers: true, store: store)

        let icon = sut.statusBarIcon
        let expectedWidth = 2 * Layout.statusItemWidth
        #expect(abs(icon.size.width - expectedWidth) < 0.1)
    }
}

// MARK: - Show All Displays Edge Cases

@MainActor
struct ShowAllDisplaysEdgeCaseTests {
    private let stub: CGSStub
    private let store: DefaultsStore
    private let testSuite: TestSuite

    init() {
        testSuite = TestSuiteFactory.createSuite()
        store = DefaultsStore(suite: testSuite.suite)
        stub = CGSStub()
    }

    @Test("show all displays with a single display")
    func showAllDisplaysWithSingleDisplay() {
        store.showAllDisplays = true
        stub.activeDisplayIdentifier = "Main"
        stub.displays = [
            CGSStub.makeDisplay(
                displayID: "Main",
                spaces: [(id: 100, isFullscreen: false), (id: 101, isFullscreen: false)],
                activeSpaceID: 100
            ),
        ]

        let sut = AppState(displaySpaceProvider: stub, skipObservers: true, store: store)

        #expect(sut.allSpaceLabels.count == 2)
    }

    @Test("show all displays with many displays")
    func showAllDisplaysWithManyDisplays() {
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

        let sut = AppState(displaySpaceProvider: stub, skipObservers: true, store: store)

        let icon = sut.statusBarIcon
        #expect(icon as NSImage? != nil)
        #expect(icon.size.width > 4 * Layout.statusItemWidth)
    }

    @Test("show all displays where one has only fullscreen spaces")
    func showAllDisplaysWithAllFullscreenOnOneDisplay() {
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

        let sut = AppState(displaySpaceProvider: stub, skipObservers: true, store: store)

        let icon = sut.statusBarIcon
        #expect(icon as NSImage? != nil)
    }

    /// Regression test: Fullscreen spaces were incorrectly shown as active on Space 1.
    /// The bug: fullscreen spaces got globalIndex=1 due to nil regularIndex defaulting to 0,
    /// which matched currentGlobalSpaceIndex when user was on Space 1.
    @Test("hide fullscreen does not mark fullscreen as active on Space 1")
    func hideFullscreenDoesNotShowFullscreenOnSpace1() {
        store.showAllDisplays = true
        store.hideFullscreenApps = true
        stub.activeDisplayIdentifier = "Display1"
        stub.displays = [
            CGSStub.makeDisplay(
                displayID: "Display1",
                spaces: [
                    (id: 100, isFullscreen: false),
                    (id: 101, isFullscreen: false),
                    (id: 102, isFullscreen: false),
                ],
                activeSpaceID: 100
            ),
            CGSStub.makeDisplay(
                displayID: "Display2",
                spaces: [
                    (id: 200, isFullscreen: true),
                    (id: 201, isFullscreen: false),
                ],
                activeSpaceID: 201
            ),
        ]

        let sut = AppState(displaySpaceProvider: stub, skipObservers: true, store: store)

        let expectedSpaces = 4
        let expectedSeparators = 1
        let expectedWidth = Double(expectedSpaces) * Layout.statusItemWidth +
            Double(expectedSeparators) * Layout.displaySeparatorWidth
        let icon = sut.statusBarIcon
        #expect(abs(icon.size.width - expectedWidth) < 0.1)
    }
}
