import AppKit
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
        SpacePreferences.setLabel("S{#}", forSpace: 3, store: store)

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

    @Test("label with {#} template resolves to space number")
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
        store.spaceLabels = [2: "{#} - Work"]

        let appState = AppState(displaySpaceProvider: stub, skipObservers: true, store: store)
        let layout = appState.statusBarLayout()

        let labels = layout.slots.map(\.label)
        #expect(labels == ["1", "2 - Work", "3"])
    }

    @Test("label with only {#} template shows space number")
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
        store.spaceLabels = [1: "{#}"]

        let appState = AppState(displaySpaceProvider: stub, skipObservers: true, store: store)
        let layout = appState.statusBarLayout()

        #expect(layout.slots.first?.label == "1")
    }
}

// MARK: - Shrink Levels

@MainActor
struct StatusBarShrinkLevelTests {
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

    private static let plainSpaces: [(id: Int, isFullscreen: Bool)] = [
        (id: 100, isFullscreen: false),
        (id: 101, isFullscreen: false),
        (id: 102, isFullscreen: false),
    ]

    @Test("shrinking drops custom labels for the plain Space number")
    func compact_dropsCustomLabels() {
        store.showAllSpaces = true
        store.spaceLabels = [2: "Work"]
        let appState = makeAppState(spaces: Self.plainSpaces, activeSpaceID: 100)

        #expect(appState.statusBarLayout().slots.map(\.label) == ["1", "Work", "3"])

        appState.shrinkLevel = .compact
        #expect(appState.statusBarLayout().slots.map(\.label) == ["1", "2", "3"])
    }

    @Test("every level of the ladder narrows the icon again")
    func levels_narrowTheIconMonotonically() {
        store.showAllDisplays = true
        store.showAllSpaces = true
        store.spaceLabels = [2: "Work"]
        stub.activeDisplayIdentifier = "Main"
        stub.displays = [
            CGSStub.makeDisplay(displayID: "Main", spaces: Self.plainSpaces, activeSpaceID: 100),
            CGSStub.makeDisplay(
                displayID: "Second",
                spaces: [(id: 200, isFullscreen: false), (id: 201, isFullscreen: false)],
                activeSpaceID: 200
            ),
        ]
        let appState = AppState(displaySpaceProvider: stub, skipObservers: true, store: store)

        let widths = IconShrinkLevel.allCases.map { level -> Double in
            appState.shrinkLevel = level
            return appState.statusBarIcon.size.width
        }

        #expect(widths == widths.sorted(by: >), "each level should be strictly narrower: \(widths)")
        #expect(Set(widths).count == widths.count, "no level should be a no-op: \(widths)")
    }

    @Test("giving up the inactive Spaces leaves one icon per display")
    func activePerDisplay_keepsEveryDisplay() {
        store.showAllDisplays = true
        store.showAllSpaces = true
        stub.activeDisplayIdentifier = "Main"
        stub.displays = [
            CGSStub.makeDisplay(displayID: "Main", spaces: Self.plainSpaces, activeSpaceID: 101),
            CGSStub.makeDisplay(
                displayID: "Second",
                spaces: [(id: 200, isFullscreen: false), (id: 201, isFullscreen: false)],
                activeSpaceID: 201
            ),
        ]
        let appState = AppState(displaySpaceProvider: stub, skipObservers: true, store: store)

        appState.shrinkLevel = .activePerDisplay

        // One slot per display, each naming the Space that display is on
        let slots = appState.statusBarLayout().slots
        #expect(slots.count == 2)
        #expect(slots.map(\.spaceID) == [101, 201])
    }

    @Test("shrinking drops padding but keeps every Space")
    func compact_keepsEverySpace() {
        store.showAllSpaces = true
        let appState = makeAppState(spaces: Self.plainSpaces, activeSpaceID: 100)
        let full = appState.statusBarIcon.size.width

        appState.shrinkLevel = .compact

        #expect(appState.statusBarLayout().slots.count == 3)
        #expect(appState.statusBarIcon.size.width < full)
    }

    @Test("shrinking drops inactive fullscreen Spaces")
    func compact_dropsInactiveFullscreenSpaces() {
        store.showAllSpaces = true
        let appState = makeAppState(
            spaces: [
                (id: 100, isFullscreen: false),
                (id: 101, isFullscreen: true),
                (id: 102, isFullscreen: false),
            ],
            activeSpaceID: 100
        )

        #expect(appState.statusBarLayout().slots.map(\.label) == ["1", "F", "2"])

        appState.shrinkLevel = .compact
        #expect(appState.statusBarLayout().slots.map(\.label) == ["1", "2"])
    }

    @Test("an active fullscreen Space survives shrinking")
    func compact_keepsActiveFullscreenSpace() {
        store.showAllSpaces = true
        let appState = makeAppState(
            spaces: [
                (id: 100, isFullscreen: false),
                (id: 101, isFullscreen: true),
            ],
            activeSpaceID: 101
        )

        appState.shrinkLevel = .compact

        #expect(appState.statusBarLayout().slots.map(\.label).contains("F"))
    }

    @Test("collapsing to the current Space reports no slots so the picker takes over")
    func currentOnly_reportsNoSlots() {
        store.showAllSpaces = true
        let appState = makeAppState(spaces: Self.plainSpaces, activeSpaceID: 101)

        #expect(!appState.statusBarLayout().slots.isEmpty)

        appState.shrinkLevel = .currentOnly

        // An empty layout is what routes a left click to showSpacePickerMenu,
        // which is the only way to reach the other Spaces while collapsed
        #expect(appState.statusBarLayout().slots.isEmpty)
        #expect(appState.spacePickerEntries().count == 3)
    }

    @Test("collapsing gives up the other displays last")
    func currentOnly_collapsesAcrossDisplays() {
        store.showAllDisplays = true
        store.showAllSpaces = true
        stub.activeDisplayIdentifier = "Main"
        stub.displays = [
            CGSStub.makeDisplay(
                displayID: "Main",
                spaces: [(id: 100, isFullscreen: false), (id: 101, isFullscreen: false)],
                activeSpaceID: 100
            ),
            CGSStub.makeDisplay(
                displayID: "Second",
                spaces: [(id: 200, isFullscreen: false), (id: 201, isFullscreen: false)],
                activeSpaceID: 200
            ),
        ]
        let appState = AppState(displaySpaceProvider: stub, skipObservers: true, store: store)
        let full = appState.statusBarIcon.size.width

        appState.shrinkLevel = .currentOnly

        #expect(appState.statusBarLayout().slots.isEmpty)
        #expect(appState.statusBarIcon.size.width < full)
    }

    @Test("the icon cache serves each level separately")
    func levels_cacheIndependently() {
        store.showAllSpaces = true
        let appState = makeAppState(spaces: Self.plainSpaces, activeSpaceID: 100)

        let full = appState.statusBarIcon
        appState.shrinkLevel = .compact
        _ = appState.statusBarIcon
        appState.shrinkLevel = .full

        #expect(appState.statusBarIcon.size.width == full.size.width)
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
        #expect(entries.map(\.title) == (1 ... 3).map {
            String(format: Localization.labelDesktopNumber, $0)
        })
        #expect(entries.map(\.keyEquivalent) == ["1", "2", "3"])
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

    @Test("fullscreen spaces have no target space and take the owning app's name")
    func fullscreenEntryHasNoTargetSpace() {
        let pid = ProcessInfo.processInfo.processIdentifier
        stub.fullscreenOwnerPIDsMap = [101: pid]
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
        #expect(entries[1].title == (NSRunningApplication.current.localizedName ?? ""))
        #expect(entries[1].keyEquivalent.isEmpty)
    }

    @Test("fullscreen spaces with no known owner stay untitled")
    func fullscreenEntryWithoutOwnerHasNoTitle() {
        let appState = makeAppState(
            spaces: [
                (id: 100, isFullscreen: false),
                (id: 101, isFullscreen: true),
            ],
            activeSpaceID: 100
        )

        let entries = appState.spacePickerEntries()

        #expect(entries[1].title.isEmpty)
    }

    @Test("built menu carries icons, titles, checkmark, and entries for the action")
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

        let menu = MenuBuilder.buildSpacePickerMenu(entries: entries, style: .both, target: target)

        #expect(menu.items.count == 4)
        let spaceItems = Array(menu.items.prefix(2))
        // No occupancy configured, so the combined style stays on the plain
        // titles the picker always had
        #expect(spaceItems.allSatisfy { $0.attributedTitle == nil })
        #expect(spaceItems.map(\.state) == [.off, .on])
        #expect(spaceItems.map(\.title) == (1 ... 2).map {
            String(format: Localization.labelDesktopNumber, $0)
        })
        #expect(spaceItems.map(\.keyEquivalent) == ["1", "2"])
        #expect(spaceItems.allSatisfy { $0.keyEquivalentModifierMask.rawValue == 0 })
        #expect(spaceItems.allSatisfy { $0.image != nil })
        #expect(spaceItems.allSatisfy { $0.target === target })
        #expect(spaceItems.allSatisfy {
            $0.action == #selector(ActionHandler.switchToPickedSpace(_:))
        })
        #expect(spaceItems.compactMap { ($0.representedObject as? SpacePickerEntry)?.spaceID } == [100, 101])
        // The hidden item claims Cmd+, during menu tracking so the shortcut
        // opens the real settings window rather than the blank Settings scene
        let settingsItem = menu.items[2]
        #expect(settingsItem.isHidden)
        #expect(settingsItem.keyEquivalent == ",")
        #expect(settingsItem.keyEquivalentModifierMask == [.command])
        #expect(settingsItem.action == #selector(ActionHandler.openSettingsWindow))
        // The trailing item is the invisible spacer restoring the bottom inset
        #expect(menu.items.last?.view != nil)
        #expect(menu.items.last?.representedObject == nil)
    }

    @Test("capped splits an ordered list at the app-icon limit")
    func cappedSplitsAtLimit() {
        let (under, underOverflow) = StatusBarRenderer.capped([1, 2], limit: 5)
        #expect(under == [1, 2])
        #expect(underOverflow == 0)

        let (exact, exactOverflow) = StatusBarRenderer.capped([1, 2, 3], limit: 3)
        #expect(exact == [1, 2, 3])
        #expect(exactOverflow == 0)

        let (over, overOverflow) = StatusBarRenderer.capped([1, 2, 3, 4, 5], limit: 2)
        #expect(over == [1, 2])
        #expect(overOverflow == 3)

        let (empty, emptyOverflow) = StatusBarRenderer.capped([Int](), limit: 2)
        #expect(empty.isEmpty)
        #expect(emptyOverflow == 0)
    }

    @Test("entries carry app icons frontmost first, fullscreen rows stay empty")
    func entriesCarryAppIcons() {
        stub.windowOwnerPIDsMap = [100: [11, 22]]
        let appState = makeAppState(
            spaces: [
                (id: 100, isFullscreen: false),
                (id: 101, isFullscreen: true),
            ],
            activeSpaceID: 100
        )
        var resolvedPIDs: [pid_t] = []
        appState.renderer.appIconResolver = { pid in
            resolvedPIDs.append(pid)
            return NSImage()
        }

        let entries = appState.spacePickerEntries()

        #expect(resolvedPIDs == [11, 22])
        #expect(entries[0].appIcons.count == 2)
        #expect(entries[0].overflowCount == 0)
        #expect(entries[1].appIcons.isEmpty)
        #expect(entries[1].overflowCount == 0)
    }

    @Test("apps beyond the cap fold into the overflow count")
    func overflowCountsBeyondCap() {
        store.spacePickerMaxAppIcons = 2
        stub.windowOwnerPIDsMap = [100: [1, 2, 3, 4, 5]]
        let appState = makeAppState(spaces: [(id: 100, isFullscreen: false)], activeSpaceID: 100)
        appState.renderer.appIconResolver = { _ in NSImage() }

        let entries = appState.spacePickerEntries()

        #expect(entries[0].appIcons.count == 2)
        #expect(entries[0].overflowCount == 3)
    }

    @Test("apps without a resolvable icon do not burn cap slots")
    func unresolvedIconsSkipCapSlots() {
        store.spacePickerMaxAppIcons = 2
        stub.windowOwnerPIDsMap = [100: [1, 2, 3]]
        let appState = makeAppState(spaces: [(id: 100, isFullscreen: false)], activeSpaceID: 100)
        appState.renderer.appIconResolver = { pid in pid == 1 ? nil : NSImage() }

        let entries = appState.spacePickerEntries()

        #expect(entries[0].appIcons.count == 2)
        #expect(entries[0].overflowCount == 0)
    }

    @Test("a cap of zero and name mode both skip the window scan")
    func capZeroAndNameModeSkipScan() {
        stub.windowOwnerPIDsMap = [100: [1]]
        let appState = makeAppState(spaces: [(id: 100, isFullscreen: false)], activeSpaceID: 100)

        store.spacePickerMaxAppIcons = 0
        _ = appState.spacePickerEntries()
        #expect(stub.windowOwnerPIDsCallCount == 0)

        store.spacePickerMaxAppIcons = 5
        store.spacePickerStyle = .name
        _ = appState.spacePickerEntries()
        #expect(stub.windowOwnerPIDsCallCount == 0)

        store.spacePickerStyle = .icons
        _ = appState.spacePickerEntries()
        #expect(stub.windowOwnerPIDsCallCount == 1)
    }

    @Test("a sticky window does not attribute its app to every Space")
    func stickyWindowFiltering() {
        // Window 50 sits on every Space, window 51 only on Space 2
        let owners = CGSDisplaySpaceProvider.resolveWindowOwners(
            appWindows: [(pid: 5, windowIDs: [50, 51])],
            spaceIDs: [1, 2, 3]
        ) { windows in
            windows == [51] ? [2] : [1, 2, 3]
        }

        #expect(owners == [2: [5]])
    }

    @Test("an app with one window per Space keeps them all")
    func everywhereAppSurvivesStickyFilter() {
        let spacesByWindow = [61: [1], 62: [2], 63: [3]]
        let owners = CGSDisplaySpaceProvider.resolveWindowOwners(
            appWindows: [(pid: 7, windowIDs: [61, 62, 63])],
            spaceIDs: [1, 2, 3]
        ) { windows in
            windows.count == 1 ? spacesByWindow[windows[0]] ?? [] : [1, 2, 3]
        }

        #expect(owners == [1: [7], 2: [7], 3: [7]])
    }

    @Test("a single requested Space skips the sticky filter")
    func singleSpaceSkipsStickyFilter() {
        var queries = 0
        let owners = CGSDisplaySpaceProvider.resolveWindowOwners(
            appWindows: [(pid: 5, windowIDs: [50])],
            spaceIDs: [1]
        ) { _ in
            queries += 1
            return [1, 2, 3]
        }

        #expect(owners == [1: [5]])
        #expect(queries == 1)
    }

    @Test("owners keep the front-to-back app order per Space")
    func ownersKeepAppOrder() {
        let owners = CGSDisplaySpaceProvider.resolveWindowOwners(
            appWindows: [(pid: 9, windowIDs: [90]), (pid: 8, windowIDs: [80])],
            spaceIDs: [1, 2]
        ) { _ in [1] }

        #expect(owners == [1: [9, 8]])
    }

    private func makeEntry(
        targetSpace: Int? = 1,
        appIcons: [NSImage] = [],
        overflowCount: Int = 0
    ) -> SpacePickerEntry {
        SpacePickerEntry(
            icon: NSImage(),
            title: "Desktop 1",
            keyEquivalent: "1",
            isActive: false,
            targetSpace: targetSpace,
            spaceID: 100,
            appIcons: appIcons,
            overflowCount: overflowCount
        )
    }

    private func attachmentCount(_ string: NSAttributedString?) -> Int {
        guard let string else {
            return 0
        }
        var count = 0
        string.enumerateAttribute(.attachment, in: NSRange(location: 0, length: string.length)) { value, _, _ in
            if value != nil {
                count += 1
            }
        }
        return count
    }

    @Test("attributed titles follow the picker style")
    func attributedTitlesFollowStyle() {
        let entry = makeEntry(appIcons: [NSImage(), NSImage()])

        #expect(MenuBuilder.attributedTitle(for: entry, style: .name) == nil)

        let fullscreen = makeEntry(targetSpace: nil, appIcons: [NSImage()])
        #expect(MenuBuilder.attributedTitle(for: fullscreen, style: .icons) == nil)
        #expect(MenuBuilder.attributedTitle(for: fullscreen, style: .both) == nil)

        let both = MenuBuilder.attributedTitle(for: entry, style: .both)
        #expect(both?.string.hasPrefix("Desktop 1") == true)
        #expect(attachmentCount(both) == 2)

        let iconsOnly = MenuBuilder.attributedTitle(for: entry, style: .icons)
        #expect(iconsOnly?.string.contains("Desktop") == false)
        #expect(attachmentCount(iconsOnly) == 2)
    }

    @Test("empty Spaces blank in icons mode and stay plain in the combined mode")
    func emptySpacesBlankInIconsMode() {
        let empty = makeEntry()

        let iconsOnly = MenuBuilder.attributedTitle(for: empty, style: .icons)
        #expect(iconsOnly != nil)
        #expect(iconsOnly?.string.isEmpty == true)

        #expect(MenuBuilder.attributedTitle(for: empty, style: .both) == nil)

        // AppKit falls back to the plain title when the attributed one is
        // empty, so the built row blanks the title and keeps the name as a
        // tooltip
        let menu = MenuBuilder.buildSpacePickerMenu(entries: [empty], style: .icons, target: NSObject())
        #expect(menu.items[0].title.isEmpty)
        #expect(menu.items[0].attributedTitle == nil)
        #expect(menu.items[0].toolTip == "Desktop 1")
    }

    @Test("overflow appends a +N suffix")
    func overflowAppendsSuffix() {
        let entry = makeEntry(appIcons: [NSImage()], overflowCount: 3)

        let title = MenuBuilder.attributedTitle(for: entry, style: .both)

        #expect(title?.string.hasSuffix(" +3") == true)
    }
}
