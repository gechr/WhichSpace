import Testing
@testable import WhichSpace

@MainActor
struct StatusBarRendererFilterTests {
    private let store: DefaultsStore
    private let testSuite: TestSuite
    private let stub: CGSStub

    init() {
        testSuite = TestSuiteFactory.createSuite()
        store = DefaultsStore(suite: testSuite.suite)
        stub = CGSStub()
    }

    @Test("label template resolves displayed number past a fullscreen space")
    func labelTemplate_usesDisplayedNumber() {
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
        store.showAllSpaces = true
        store.localSpaceNumbers = true
        // Labels are keyed by fullscreen-inclusive position (3), but the
        // displayed number for that space is its regular index (2)
        SpacePreferences.setLabel("S{number}", forSpace: 3, store: store)

        let appState = AppState(displaySpaceProvider: stub, skipObservers: true, store: store)
        let layout = appState.statusBarLayout()

        #expect(layout.slots.map(\.label) == ["1", "F", "S2"])
    }

    // MARK: - hideEmptySpaces

    @Test("hideEmptySpaces hides non-active empty spaces")
    func hideEmptySpaces_hidesNonActiveEmptySpaces() {
        stub.activeDisplayIdentifier = "Main"
        stub.displays = [
            CGSStub.makeDisplay(
                displayID: "Main",
                spaces: [
                    (id: 100, isFullscreen: false),
                    (id: 101, isFullscreen: false),
                    (id: 102, isFullscreen: false),
                ],
                activeSpaceID: 101
            ),
        ]
        // Only space 101 and 102 have windows
        stub.spacesWithWindowsSet = [101, 102]
        store.showAllSpaces = true
        store.hideEmptySpaces = true

        let appState = AppState(displaySpaceProvider: stub, skipObservers: true, store: store)
        let layout = appState.statusBarLayout()

        // Space 100 (index 1) is empty and not active => hidden
        // Space 101 (index 2) is active => shown
        // Space 102 (index 3) has windows => shown
        #expect(layout.slots.count == 2)
        #expect(layout.slots.map(\.label) == ["2", "3"])
    }

    @Test("Space changes refresh populated window data off the main thread")
    func spaceChange_refreshesPopulatedWindowDataInBackground() {
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
        ]
        stub.spacesWithWindowsSet = [100, 101]
        store.showAllSpaces = true
        store.hideEmptySpaces = true

        let appState = AppState(displaySpaceProvider: stub, skipObservers: true, store: store)
        _ = appState.statusBarLayout()
        #expect(stub.mainThreadSpacesWithWindowsCallCount == 1)

        stub.displays = [
            CGSStub.makeDisplay(
                displayID: "Main",
                spaces: [
                    (id: 100, isFullscreen: false),
                    (id: 101, isFullscreen: false),
                ],
                activeSpaceID: 101
            ),
        ]
        appState.forceSpaceUpdate()
        _ = appState.statusBarLayout()

        #expect(stub.mainThreadSpacesWithWindowsCallCount == 1)
    }

    @Test("window refreshes run one scan at a time")
    func windowRefreshes_runSingleFlight() async {
        stub.activeDisplayIdentifier = "Main"
        stub.displays = makeDisplays(activeSpaceID: 100)
        stub.spacesWithWindowsSet = [100, 101]
        store.showAllSpaces = true
        store.hideEmptySpaces = true

        let appState = AppState(displaySpaceProvider: stub, skipObservers: true, store: store)
        _ = appState.statusBarLayout()
        #expect(stub.spacesWithWindowsCallCount == 1)

        let blocker = DispatchSemaphore(value: 0)
        stub.spacesWithWindowsBlocker = blocker
        defer {
            blocker.signal()
            blocker.signal()
        }

        stub.displays = makeDisplays(activeSpaceID: 101)
        appState.forceSpaceUpdate()
        _ = appState.statusBarLayout()
        await waitForWindowScanCount(2)

        stub.displays = makeDisplays(activeSpaceID: 100)
        appState.forceSpaceUpdate()
        _ = appState.statusBarLayout()
        try? await Task.sleep(for: .milliseconds(50))
        #expect(stub.spacesWithWindowsCallCount == 2)

        blocker.signal()
        await waitForWindowScanCount(3)
    }

    private func makeDisplays(activeSpaceID: Int) -> [NSDictionary] {
        [
            CGSStub.makeDisplay(
                displayID: "Main",
                spaces: [
                    (id: 100, isFullscreen: false),
                    (id: 101, isFullscreen: false),
                ],
                activeSpaceID: activeSpaceID
            ),
        ]
    }

    private func waitForWindowScanCount(_ expectedCount: Int) async {
        for _ in 0 ..< 100 where stub.spacesWithWindowsCallCount < expectedCount {
            try? await Task.sleep(for: .milliseconds(10))
        }
        #expect(stub.spacesWithWindowsCallCount == expectedCount)
    }

    // MARK: - hideFullscreenApps

    @Test("hideFullscreenApps removes fullscreen spaces")
    func hideFullscreenApps_removesFullscreenSpaces() {
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
        store.showAllSpaces = true
        store.hideFullscreenApps = true

        let appState = AppState(displaySpaceProvider: stub, skipObservers: true, store: store)
        let layout = appState.statusBarLayout()

        // Fullscreen space should be hidden
        #expect(layout.slots.count == 2)
        #expect(layout.slots.map(\.label) == ["1", "2"])
    }

    // MARK: - Active Space Always Shown

    @Test("active space is always shown regardless of hideEmptySpaces")
    func activeSpaceAlwaysShown_evenWhenEmpty() {
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
        ]
        // No spaces have windows (both are "empty")
        stub.spacesWithWindowsSet = []
        store.showAllSpaces = true
        store.hideEmptySpaces = true

        let appState = AppState(displaySpaceProvider: stub, skipObservers: true, store: store)
        let layout = appState.statusBarLayout()

        // Active space 100 (index 1) should still be shown even though empty
        #expect(layout.slots.count == 1)
        #expect(layout.slots[0].label == "1")
    }

    @Test("active fullscreen space is still shown when hideFullscreenApps enabled")
    func activeFullscreenSpace_shownWhenHidden() {
        stub.activeDisplayIdentifier = "Main"
        stub.displays = [
            CGSStub.makeDisplay(
                displayID: "Main",
                spaces: [
                    (id: 100, isFullscreen: false),
                    (id: 101, isFullscreen: true),
                    (id: 102, isFullscreen: false),
                ],
                activeSpaceID: 101
            ),
        ]
        store.showAllSpaces = true
        store.hideFullscreenApps = true

        let appState = AppState(displaySpaceProvider: stub, skipObservers: true, store: store)
        let layout = appState.statusBarLayout()

        // Active fullscreen space should still appear
        let labels = layout.slots.map(\.label)
        #expect(labels.contains("F"), "Active fullscreen space should be shown")
    }

    // MARK: - Label Templates

    @Test("label with {number} template resolves to space number")
    func labelTemplateResolvesInLayout() {
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
        store.showAllSpaces = true
        store.spaceLabels = [2: "{number} - Work"]

        let appState = AppState(displaySpaceProvider: stub, skipObservers: true, store: store)
        let layout = appState.statusBarLayout()

        let labels = layout.slots.map(\.label)
        #expect(labels == ["1", "2 - Work", "3"])
    }

    @Test("label with only {number} template shows space number")
    func labelTemplateOnlySpace() {
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
        ]
        store.showAllSpaces = true
        store.spaceLabels = [1: "{number}"]

        let appState = AppState(displaySpaceProvider: stub, skipObservers: true, store: store)
        let layout = appState.statusBarLayout()

        #expect(layout.slots.first?.label == "1")
    }
}

// MARK: - Space Picker Menu

@MainActor
struct SpacePickerTests {
    private let store: DefaultsStore
    private let testSuite: TestSuite
    private let stub: CGSStub

    init() {
        testSuite = TestSuiteFactory.createSuite()
        store = DefaultsStore(suite: testSuite.suite)
        stub = CGSStub()
    }

    private func makeAppState(
        spaces: [(id: Int, isFullscreen: Bool)], activeSpaceID: Int
    ) -> AppState {
        stub.activeDisplayIdentifier = "Main"
        stub.displays = [
            CGSStub.makeDisplay(displayID: "Main", spaces: spaces, activeSpaceID: activeSpaceID),
        ]
        return AppState(displaySpaceProvider: stub, skipObservers: true, store: store)
    }

    @Test("picker lists every space with the active one marked")
    func entriesListAllSpaces() {
        let appState = makeAppState(
            spaces: [
                (id: 100, isFullscreen: false),
                (id: 101, isFullscreen: false),
                (id: 102, isFullscreen: false),
            ],
            activeSpaceID: 101
        )

        let entries = appState.spacePickerEntries()

        #expect(entries.map(\.isActive) == [false, true, false])
        #expect(entries.map(\.targetSpace) == [1, 2, 3])
        #expect(entries.map(\.spaceID) == [100, 101, 102])
    }

    @Test("picker ignores hide filters so hidden spaces stay reachable")
    func entriesIgnoreHideFilters() {
        store.hideEmptySpaces = true
        store.hideFullscreenApps = true
        stub.spacesWithWindowsSet = [100]
        let appState = makeAppState(
            spaces: [
                (id: 100, isFullscreen: false),
                (id: 101, isFullscreen: true),
                (id: 102, isFullscreen: false),
            ],
            activeSpaceID: 100
        )

        let entries = appState.spacePickerEntries()

        #expect(entries.count == 3)
        #expect(entries.map(\.spaceID) == [100, 101, 102])
    }

    @Test("fullscreen spaces have no target space")
    func fullscreenEntryHasNoTargetSpace() {
        let appState = makeAppState(
            spaces: [
                (id: 100, isFullscreen: false),
                (id: 101, isFullscreen: true),
            ],
            activeSpaceID: 100
        )

        let entries = appState.spacePickerEntries()

        #expect(entries.count == 2)
        #expect(entries[1].targetSpace == nil)
    }

    @Test("built menu carries icons, checkmark, and entries for the action")
    func builtMenuMatchesEntries() {
        let appState = makeAppState(
            spaces: [
                (id: 100, isFullscreen: false),
                (id: 101, isFullscreen: false),
            ],
            activeSpaceID: 101
        )
        let entries = appState.spacePickerEntries()
        let target = NSObject()

        let menu = MenuBuilder.buildSpacePickerMenu(entries: entries, target: target)

        #expect(menu.items.count == 2)
        #expect(menu.items.map(\.state) == [.off, .on])
        #expect(menu.items.allSatisfy { $0.image != nil })
        #expect(menu.items.allSatisfy { $0.target === target })
        #expect(menu.items.allSatisfy {
            $0.action == #selector(ActionHandler.switchToPickedSpace(_:))
        })
        #expect(menu.items.compactMap { ($0.representedObject as? SpacePickerEntry)?.spaceID } == [100, 101])
    }
}
