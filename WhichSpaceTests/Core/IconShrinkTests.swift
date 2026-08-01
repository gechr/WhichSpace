import Foundation
import Testing
@testable import WhichSpace

struct IconShrinkTests {
    // MARK: - Helpers

    /// The reading produced when the menu bar ran out of room: this app's item
    /// is gone while its neighbours are still drawn.
    private static let evicted = StatusWindowSnapshot(
        ownWindowIsOnScreen: false,
        otherStatusWindowCount: 3,
        sessionIsActive: true
    )

    /// The reading produced when the bar on our own display is hidden,
    /// covering fullscreen Spaces, auto-hide, Mission Control, the lock screen
    /// and sleep. It is a per-display reading: a fullscreen Space hides one
    /// display's bar while another display keeps drawing its own.
    private static let barHidden = StatusWindowSnapshot(
        ownWindowIsOnScreen: false,
        otherStatusWindowCount: 0,
        sessionIsActive: true
    )

    private static let onScreen = StatusWindowSnapshot(
        ownWindowIsOnScreen: true,
        otherStatusWindowCount: 3,
        sessionIsActive: true
    )

    private static let now = Date(timeIntervalSinceReferenceDate: 1_000_000)

    // MARK: - Level Ladder

    @Test("levels order from full rendering down to the current Space alone")
    func level_ordering() {
        #expect(IconShrinkLevel.allCases == [.full, .compact, .activePerDisplay, .currentOnly])
        #expect(IconShrinkLevel.full.next == .compact)
        #expect(IconShrinkLevel.compact.next == .activePerDisplay)
        #expect(IconShrinkLevel.activePerDisplay.next == .currentOnly)
        #expect(IconShrinkLevel.currentOnly.next == nil)
    }

    @Test("each level gives up one more thing than the last")
    func level_renderingTraits() {
        // Custom styling and fullscreen slots go first
        #expect(IconShrinkLevel.full.usesCustomStyling)
        #expect(!IconShrinkLevel.compact.usesCustomStyling)
        #expect(IconShrinkLevel.full.showsFullscreenSpaces)
        #expect(!IconShrinkLevel.compact.showsFullscreenSpaces)
        #expect(IconShrinkLevel.full.paddingScaleOverride == nil)
        #expect(IconShrinkLevel.compact.paddingScaleOverride == 0)

        // Then the inactive Spaces, leaving one icon per display
        #expect(IconShrinkLevel.compact.showsInactiveSpaces)
        #expect(!IconShrinkLevel.activePerDisplay.showsInactiveSpaces)
        #expect(IconShrinkLevel.activePerDisplay.showsOtherDisplays)

        // The other displays go last
        #expect(!IconShrinkLevel.currentOnly.showsInactiveSpaces)
        #expect(!IconShrinkLevel.currentOnly.showsOtherDisplays)
    }

    // MARK: - Eviction Readings

    @Test("eviction shrinks one level at a time down to the floor")
    func apply_evictionDescendsOneLevelAtATime() {
        var detector = MenuBarEvictionDetector()
        detector.reset()

        #expect(detector.apply(Self.evicted, now: Self.now) == .compact)
        #expect(detector.apply(Self.evicted, now: Self.now) == .activePerDisplay)
        #expect(detector.apply(Self.evicted, now: Self.now) == .currentOnly)
        #expect(detector.level == .currentOnly)

        // The floor holds: further readings change nothing
        #expect(detector.apply(Self.evicted, now: Self.now) == nil)
        #expect(detector.level == .currentOnly)
    }

    @Test("a hidden menu bar never shrinks the icon")
    func apply_hiddenMenuBarIsIgnored() {
        var detector = MenuBarEvictionDetector()
        detector.reset()

        #expect(detector.apply(Self.barHidden, now: Self.now) == nil)
        #expect(detector.level == .full)
    }

    @Test("a locked screen never shrinks the icon")
    func apply_inactiveSessionIsIgnored() {
        var detector = MenuBarEvictionDetector()
        detector.reset()

        // Measured on a locked screen: the display keeps between 4 and 20
        // status windows drawn while this app's own occlusion drops, which is
        // indistinguishable from running out of room. The lock screen, the
        // screensaver and a sleeping display are excluded by name instead.
        let locked = StatusWindowSnapshot(
            ownWindowIsOnScreen: false,
            otherStatusWindowCount: 11,
            sessionIsActive: false
        )

        #expect(detector.apply(locked, now: Self.now) == nil)
        #expect(detector.level == .full)
    }

    @Test("an icon that is still drawn never shrinks")
    func apply_onScreenIsIgnored() {
        var detector = MenuBarEvictionDetector()
        detector.reset()

        #expect(detector.apply(Self.onScreen, now: Self.now) == nil)
        #expect(detector.level == .full)
    }

    @Test("readings taken before the icon has settled are discarded")
    func apply_readingInsideSettleWindowIsDiscarded() {
        var detector = MenuBarEvictionDetector()
        detector.reset()
        detector.beginSettling(now: Self.now)

        // Assigning the image relayouts the bar, so this reading is unreliable
        let midWindow = Self.now.addingTimeInterval(MenuBarEvictionDetector.settleInterval / 2)
        #expect(detector.apply(Self.evicted, now: midWindow) == nil)
        #expect(detector.level == .full)

        let afterWindow = Self.now.addingTimeInterval(MenuBarEvictionDetector.settleInterval)
        #expect(detector.apply(Self.evicted, now: afterWindow) == .compact)
    }

    // MARK: - Reset

    @Test("reset returns the icon to full size")
    func reset_returnsToFullSize() {
        var detector = MenuBarEvictionDetector()
        detector.reset()
        _ = detector.apply(Self.evicted, now: Self.now)
        #expect(detector.level == .compact)

        detector.reset()
        #expect(detector.level == .full)
    }

    @Test("reset clears any pending settle window")
    func reset_clearsSettleWindow() {
        var detector = MenuBarEvictionDetector()
        detector.reset()
        detector.beginSettling(now: Self.now)
        detector.reset()

        #expect(detector.apply(Self.evicted, now: Self.now) == .compact)
    }

    @Test("every reset walks the ladder again from the top")
    func reset_alwaysRestartsTheLadder() {
        var detector = MenuBarEvictionDetector()
        detector.reset()
        while detector.apply(Self.evicted, now: Self.now) != nil {}
        #expect(detector.level == .currentOnly)

        // No level is remembered across a reset. A remembered level would be
        // applied without testing the one above it, so a stale entry could
        // never discover that the shallower level now fits.
        detector.reset()
        #expect(detector.apply(Self.evicted, now: Self.now) == .compact)
    }

    // MARK: - Growing Back

    @Test("a Space switch alone does not earn another attempt at full size")
    func retry_needsEvidenceNotJustASpaceSwitch() {
        var detector = MenuBarEvictionDetector()
        detector.reset()
        _ = detector.apply(Self.evicted, now: Self.now)

        // The menu bar holds the same items either way, so widening the item
        // would reflow every icon to its left and end where it started
        #expect(!detector.shouldRetryFullSize(otherStatusWindowCount: 3))
        #expect(!detector.shouldRetryFullSize(otherStatusWindowCount: 4))
    }

    @Test("a neighbouring status item going away earns another attempt")
    func retry_onFewerNeighbours() {
        var detector = MenuBarEvictionDetector()
        detector.reset()
        _ = detector.apply(Self.evicted, now: Self.now)

        #expect(detector.shouldRetryFullSize(otherStatusWindowCount: 2))
    }

    @Test("an unshrunk icon has nothing to grow back to")
    func retry_isPointlessAtFullSize() {
        var detector = MenuBarEvictionDetector()
        detector.reset()

        #expect(!detector.shouldRetryFullSize(otherStatusWindowCount: 0))
    }

    // MARK: - Probe Fallback

    @Test("an unavailable window list reads as fitting")
    func probe_unavailableSnapshotNeverShrinks() {
        var detector = MenuBarEvictionDetector()
        detector.reset()

        #expect(detector.apply(.unavailable, now: Self.now) == nil)
        #expect(detector.level == .full)
    }
}

// MARK: - Reset Routing

/// A real Space or topology change is offered as a chance to grow back, but the
/// notification bursts that arrive on every app activation are not.
@MainActor
struct ShrinkResetRoutingTests {
    private let store: DefaultsStore
    private let testSuite: TestSuite
    private let stub: CGSStub

    init() {
        testSuite = TestSuiteFactory.createSuite()
        store = DefaultsStore(suite: testSuite.suite)
        stub = CGSStub()
    }

    private func setDisplays(activeSpaceID: Int) {
        stub.activeDisplayIdentifier = "Main"
        stub.displays = [
            CGSStub.makeDisplay(
                displayID: "Main",
                spaces: [(id: 100, isFullscreen: false), (id: 101, isFullscreen: false)],
                activeSpaceID: activeSpaceID
            ),
        ]
    }

    @Test("switching Space offers a chance to grow back")
    func snapshotChange_requestsReset() {
        setDisplays(activeSpaceID: 100)
        let appState = AppState(displaySpaceProvider: stub, skipObservers: true, store: store)
        var resetCount = 0
        appState.onSnapshotDidChange = { resetCount += 1 }

        setDisplays(activeSpaceID: 101)
        appState.forceSpaceUpdate()

        #expect(resetCount == 1)
    }

    @Test("a repeated snapshot leaves the icon alone")
    func unchangedSnapshot_requestsNoReset() {
        setDisplays(activeSpaceID: 100)
        let appState = AppState(displaySpaceProvider: stub, skipObservers: true, store: store)
        var resetCount = 0
        appState.onSnapshotDidChange = { resetCount += 1 }

        // App activation and the global-click fallback both land here with
        // nothing actually changed
        appState.forceSpaceUpdate()
        appState.forceSpaceUpdate()

        #expect(resetCount == 0)
    }

    @Test("the shrink level feeds the rendered icon")
    func shrinkLevel_drivesRendering() {
        store.showAllSpaces = true
        setDisplays(activeSpaceID: 100)
        let appState = AppState(displaySpaceProvider: stub, skipObservers: true, store: store)

        let full = appState.statusBarIcon.size.width
        appState.shrinkLevel = .currentOnly

        #expect(appState.statusBarIcon.size.width < full)
    }
}
