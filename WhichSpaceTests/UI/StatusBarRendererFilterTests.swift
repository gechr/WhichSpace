import Testing
@testable import WhichSpace

@Suite("StatusBarRenderer Filtering")
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
}
