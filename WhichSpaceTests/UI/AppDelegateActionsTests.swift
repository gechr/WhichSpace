import AppKit
import Defaults
import XCTest
@testable import WhichSpace

// MARK: - Stub Confirm Action for Testing

/// A stub that records confirmation alerts and returns a predetermined result
final class StubConfirmAction: @unchecked Sendable {
    var shouldConfirm = true
    private(set) var alertsShown: [(message: String, detail: String, confirmTitle: String, isDestructive: Bool)] = []

    func callAsFunction(message: String, detail: String, confirmTitle: String, isDestructive: Bool) -> Bool {
        alertsShown.append((message, detail, confirmTitle, isDestructive))
        return shouldConfirm
    }

    func reset() {
        alertsShown = []
    }
}

// MARK: - Stub LaunchAtLogin for Testing

/// A stub launch-at-login provider for testing
final class StubLaunchAtLoginProvider: LaunchAtLoginProvider, @unchecked Sendable {
    var isEnabled = false
}

// MARK: - AppDelegate Actions Tests

/// Tests for AppDelegate menu action methods.
/// Uses stubbed dependencies to test actions without showing UI.
@MainActor
final class AppDelegateActionsTests: XCTestCase {
    private var store: DefaultsStore!
    private var testSuite: TestSuite!
    private var stub: CGSStub!
    private var appState: AppState!
    private var confirmStub: StubConfirmAction!
    private var launchAtLoginStub: StubLaunchAtLoginProvider!
    private var sut: AppDelegate!

    override func setUp() async throws {
        try await super.setUp()

        // Create per-test isolated store
        testSuite = TestSuiteFactory.createSuite()
        store = DefaultsStore(suite: testSuite.suite)
        store.horizontalScrollEnabled = true
        store.invertHorizontalScroll = false
        store.invertVerticalScroll = false
        store.verticalScrollEnabled = true

        stub = CGSStub()
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
                activeSpaceID: 101
            ),
        ]

        appState = AppState(displaySpaceProvider: stub, skipObservers: true, store: store)
        confirmStub = StubConfirmAction()
        launchAtLoginStub = StubLaunchAtLoginProvider()
        sut = AppDelegate(
            appState: appState,
            confirmAction: confirmStub.callAsFunction,
            launchAtLogin: launchAtLoginStub
        )
    }

    override func tearDown() async throws {
        sut.stopObservingAppState()
        sut = nil
        launchAtLoginStub = nil
        appState = nil
        confirmStub = nil
        stub = nil
        if let store, let testSuite {
            store.resetAll()
            TestSuiteFactory.destroySuite(testSuite)
        }
        store = nil
        testSuite = nil
        try await super.tearDown()
    }

    // MARK: - Helper Methods

    /// Waits for statusBarIconUpdateCount to change from the given value.
    /// Returns true if count changed, false if timeout was reached.
    private func waitForCountChange(
        from initialCount: Int,
        timeout: Duration = .milliseconds(100)
    ) async -> Bool {
        let deadline = ContinuousClock.now.advanced(by: timeout)
        while ContinuousClock.now < deadline {
            if sut.statusBarIconUpdateCount != initialCount {
                return true
            }
            try? await Task.sleep(for: .milliseconds(5))
        }
        return sut.statusBarIconUpdateCount != initialCount
    }

    private func makeOtherMouseUpEvent(location: CGPoint) throws -> NSEvent {
        let cgEvent = try XCTUnwrap(CGEvent(
            mouseEventSource: nil,
            mouseType: .otherMouseUp,
            mouseCursorPosition: CGPoint(x: location.x, y: location.y),
            mouseButton: .center
        ))
        return try XCTUnwrap(NSEvent(cgEvent: cgEvent))
    }

    // MARK: - Click Event Tests

    func testNSEventIsRightClick_trueForRightMouseUp() {
        let event = NSEvent.mouseEvent(
            with: .rightMouseUp,
            location: .zero,
            modifierFlags: [],
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            eventNumber: 0,
            clickCount: 1,
            pressure: 1
        )

        XCTAssertTrue(event?.isRightClick ?? false)
    }

    func testNSEventIsRightClick_trueForControlClick() {
        let event = NSEvent.mouseEvent(
            with: .leftMouseUp,
            location: .zero,
            modifierFlags: .control,
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            eventNumber: 0,
            clickCount: 1,
            pressure: 1
        )

        XCTAssertTrue(event?.isRightClick ?? false)
    }

    func testNSEventIsRightClick_falseForOptionClick() {
        let event = NSEvent.mouseEvent(
            with: .leftMouseUp,
            location: .zero,
            modifierFlags: .option,
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            eventNumber: 0,
            clickCount: 1,
            pressure: 1
        )

        XCTAssertFalse(event?.isRightClick ?? true)
    }

    func testNSEventIsRightClick_falseForPlainLeftClick() {
        let event = NSEvent.mouseEvent(
            with: .leftMouseUp,
            location: .zero,
            modifierFlags: [],
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            eventNumber: 0,
            clickCount: 1,
            pressure: 1
        )

        XCTAssertFalse(event?.isRightClick ?? true)
    }

    // MARK: - Click Permission Tests

    func testSpaceSwipeGuidance_onlyShowsForUnconfiguredInstantSwitchingOnMacOS27() {
        XCTAssertTrue(AppDelegate.shouldShowSpaceSwipeGestureGuidance(
            requiresSetting: true,
            usesClassicSwitching: false,
            gestureEnabled: false
        ))
        XCTAssertFalse(AppDelegate.shouldShowSpaceSwipeGestureGuidance(
            requiresSetting: false,
            usesClassicSwitching: false,
            gestureEnabled: false
        ))
        XCTAssertFalse(AppDelegate.shouldShowSpaceSwipeGestureGuidance(
            requiresSetting: true,
            usesClassicSwitching: true,
            gestureEnabled: false
        ))
        XCTAssertFalse(AppDelegate.shouldShowSpaceSwipeGestureGuidance(
            requiresSetting: true,
            usesClassicSwitching: false,
            gestureEnabled: true
        ))
    }

    private func makeDelegate(trusted: Bool, capability: Bool = true) -> AppDelegate {
        // Bound to locals first: a trailing closure here would bind to
        // `missionControlNotificationSender`, the initializer's first closure
        // parameter.
        let isProcessTrusted: () -> Bool = { trusted }
        let isCapabilityTrusted: () -> Bool = { capability }
        return AppDelegate(
            appState: appState,
            confirmAction: confirmStub.callAsFunction,
            launchAtLogin: launchAtLoginStub,
            isProcessTrusted: isProcessTrusted,
            isCapabilityTrusted: isCapabilityTrusted
        )
    }

    func testResolveClickPermission_untrustedWithSettingOn_keepsSettingOnAndAsks() {
        store.clickToSwitchSpaces = true
        let localSut = makeDelegate(trusted: false)

        XCTAssertEqual(localSut.resolveClickPermission(), .needsRequest)
        XCTAssertTrue(store.clickToSwitchSpaces, "The pref records intent even when the grant went away")
    }

    func testResolveClickPermission_untrustedWithSettingOff_leavesSettingOffAndAsks() {
        store.clickToSwitchSpaces = false
        let localSut = makeDelegate(trusted: false)

        XCTAssertEqual(localSut.resolveClickPermission(), .needsRequest)
        XCTAssertFalse(store.clickToSwitchSpaces)
    }

    func testResolveClickPermission_trustedWithSettingOff_enablesSetting() {
        store.clickToSwitchSpaces = false
        let localSut = makeDelegate(trusted: true)

        XCTAssertEqual(localSut.resolveClickPermission(), .granted)
        XCTAssertTrue(store.clickToSwitchSpaces, "The first click should enable click-to-switch")
    }

    func testResolveClickPermission_trustedWithSettingOn_grants() {
        store.clickToSwitchSpaces = true
        let localSut = makeDelegate(trusted: true)

        XCTAssertEqual(localSut.resolveClickPermission(), .granted)
        XCTAssertTrue(store.clickToSwitchSpaces)
    }

    func testResolveClickPermission_revokedWhileRunning_blocksWithoutTouchingSetting() {
        store.clickToSwitchSpaces = false
        let localSut = makeDelegate(trusted: true, capability: false)

        XCTAssertEqual(localSut.resolveClickPermission(), .revoked)
        XCTAssertFalse(store.clickToSwitchSpaces, "A revoked click must not auto-enable click-to-switch")
    }

    func testHandleMiddleClickEvent_consumesMiddleClickInsideButtonAndSendsNotification() throws {
        var notifications: [String] = []
        let sender: (CFString) -> Void = { notifications.append($0 as String) }
        let localSut = AppDelegate(
            appState: appState,
            confirmAction: confirmStub.callAsFunction,
            launchAtLogin: launchAtLoginStub,
            missionControlNotificationSender: sender
        )
        let event = try makeOtherMouseUpEvent(location: CGPoint(x: 12, y: 12))
        let button = NSView(frame: NSRect(
            x: event.locationInWindow.x - 5,
            y: event.locationInWindow.y - 5,
            width: 10,
            height: 10
        ))

        let result = localSut.handleMiddleClickEvent(event, in: button)

        XCTAssertEqual(event.buttonNumber, 2)
        XCTAssertNil(result)
        XCTAssertEqual(notifications, ["com.apple.expose.awake"])
    }

    func testHandleMiddleClickEvent_ignoresMiddleClickOutsideButton() throws {
        var notificationCount = 0
        let sender: (CFString) -> Void = { _ in notificationCount += 1 }
        let localSut = AppDelegate(
            appState: appState,
            confirmAction: confirmStub.callAsFunction,
            launchAtLogin: launchAtLoginStub,
            missionControlNotificationSender: sender
        )
        let event = try makeOtherMouseUpEvent(location: CGPoint(x: 100, y: 100))
        let button = NSView(frame: NSRect(
            x: event.locationInWindow.x + 100,
            y: event.locationInWindow.y + 100,
            width: 10,
            height: 10
        ))

        let result = localSut.handleMiddleClickEvent(event, in: button)

        XCTAssertNotNil(result)
        XCTAssertEqual(notificationCount, 0)
    }

    // MARK: - Scroll Event Tests

    private func makeScrollEvent(
        deltaY: Int32,
        deltaX: Int32 = 0,
        precise: Bool,
        momentum: Bool = false,
        phase: Int64? = nil,
        timestamp: TimeInterval = 0
    ) throws -> NSEvent {
        let cgEvent = try XCTUnwrap(CGEvent(
            scrollWheelEvent2Source: nil,
            units: precise ? .pixel : .line,
            wheelCount: 2,
            wheel1: deltaY,
            wheel2: deltaX,
            wheel3: 0
        ))
        cgEvent.location = CGPoint(x: 12, y: 12)
        cgEvent.timestamp = CGEventTimestamp(timestamp * 1_000_000_000)
        if momentum {
            cgEvent.setIntegerValueField(.scrollWheelEventMomentumPhase, value: 1)
        }
        if let phase {
            cgEvent.setIntegerValueField(.scrollWheelEventScrollPhase, value: phase)
        }
        return try XCTUnwrap(NSEvent(cgEvent: cgEvent))
    }

    private func buttonContaining(_ event: NSEvent) -> NSView {
        NSView(frame: NSRect(
            x: event.locationInWindow.x - 5,
            y: event.locationInWindow.y - 5,
            width: 10,
            height: 10
        ))
    }

    private func makeScrollSut(recording switches: @escaping (Bool) -> Void) -> AppDelegate {
        makeScrollSut { goRight, _ in
            switches(goRight)
            return true
        }
    }

    private func makeScrollSut(recording switches: @escaping (Bool, Bool) -> Bool) -> AppDelegate {
        AppDelegate(
            appState: appState,
            confirmAction: confirmStub.callAsFunction,
            launchAtLogin: launchAtLoginStub,
            relativeSpaceSwitchAction: switches
        )
    }

    func testHandleScrollEvent_ignoresScrollOutsideButton() throws {
        var switches: [Bool] = []
        let localSut = makeScrollSut { switches.append($0) }
        let event = try makeScrollEvent(deltaY: -1, precise: false)
        let button = NSView(frame: NSRect(
            x: event.locationInWindow.x + 100,
            y: event.locationInWindow.y + 100,
            width: 10,
            height: 10
        ))

        let result = localSut.handleScrollEvent(event, in: button)

        XCTAssertNotNil(result)
        XCTAssertEqual(switches, [])
    }

    func testHandleScrollEvent_ignoredWhenBothAxesDisabled() throws {
        store.verticalScrollEnabled = false
        store.horizontalScrollEnabled = false
        var switches: [Bool] = []
        let localSut = makeScrollSut { switches.append($0) }
        let event = try makeScrollEvent(deltaY: -1, precise: false)

        let result = localSut.handleScrollEvent(event, in: buttonContaining(event))

        XCTAssertNotNil(result)
        XCTAssertEqual(switches, [])
    }

    func testHandleScrollEvent_wheelNotchDownSwitchesToPreviousSpace() throws {
        var switches: [Bool] = []
        let localSut = makeScrollSut { switches.append($0) }
        let event = try makeScrollEvent(deltaY: -1, precise: false)

        let result = localSut.handleScrollEvent(event, in: buttonContaining(event))

        XCTAssertNil(result)
        XCTAssertEqual(switches, [false])
    }

    func testHandleScrollEvent_wheelNotchUpSwitchesToNextSpace() throws {
        var switches: [Bool] = []
        let localSut = makeScrollSut { switches.append($0) }
        let event = try makeScrollEvent(deltaY: 1, precise: false)

        let result = localSut.handleScrollEvent(event, in: buttonContaining(event))

        XCTAssertNil(result)
        XCTAssertEqual(switches, [true])
    }

    func testHandleScrollEvent_preciseDeltasAccumulateToThreshold() throws {
        var switches: [Bool] = []
        let localSut = makeScrollSut { switches.append($0) }

        // Two 20-point deltas stay below the 50-point threshold; the third crosses it
        for _ in 0 ..< 2 {
            let event = try makeScrollEvent(deltaY: -20, precise: true)
            XCTAssertNil(localSut.handleScrollEvent(event, in: buttonContaining(event)))
            XCTAssertEqual(switches, [])
        }
        let event = try makeScrollEvent(deltaY: -20, precise: true)
        XCTAssertNil(localSut.handleScrollEvent(event, in: buttonContaining(event)))

        XCTAssertEqual(switches, [false])
    }

    func testHandleScrollEvent_sensitivityScalesThreshold() throws {
        store.scrollSensitivity = 200.0
        var switches: [Bool] = []
        let localSut = makeScrollSut { switches.append($0) }
        // At 200% sensitivity the threshold halves to 25 points, so 30 crosses it
        let event = try makeScrollEvent(deltaY: 30, precise: true)

        let result = localSut.handleScrollEvent(event, in: buttonContaining(event))

        XCTAssertNil(result)
        XCTAssertEqual(switches, [true])
    }

    func testHandleScrollEvent_horizontalScrollLeftSwitchesToNextSpace() throws {
        var switches: [Bool] = []
        let localSut = makeScrollSut { switches.append($0) }
        // Fingers left = negative deltaX = Space on the right, matching the system swipe
        let event = try makeScrollEvent(deltaY: 0, deltaX: -60, precise: true)

        let result = localSut.handleScrollEvent(event, in: buttonContaining(event))

        XCTAssertNil(result)
        XCTAssertEqual(switches, [true])
    }

    func testHandleScrollEvent_horizontalDominatesWhenLargerThanVertical() throws {
        var switches: [Bool] = []
        let localSut = makeScrollSut { switches.append($0) }
        let event = try makeScrollEvent(deltaY: -10, deltaX: 60, precise: true)

        let result = localSut.handleScrollEvent(event, in: buttonContaining(event))

        XCTAssertNil(result)
        XCTAssertEqual(switches, [false])
    }

    func testHandleScrollEvent_horizontalIgnoredWhenDisabled() throws {
        store.horizontalScrollEnabled = false
        var switches: [Bool] = []
        let localSut = makeScrollSut { switches.append($0) }
        let event = try makeScrollEvent(deltaY: 0, deltaX: -60, precise: true)

        let result = localSut.handleScrollEvent(event, in: buttonContaining(event))

        XCTAssertNil(result)
        XCTAssertEqual(switches, [])
    }

    func testHandleScrollEvent_invertVerticalScrollFlipsMapping() throws {
        store.invertVerticalScroll = true
        var switches: [Bool] = []
        let localSut = makeScrollSut { switches.append($0) }
        let event = try makeScrollEvent(deltaY: 1, precise: false)

        let result = localSut.handleScrollEvent(event, in: buttonContaining(event))

        XCTAssertNil(result)
        XCTAssertEqual(switches, [false])
    }

    func testHandleScrollEvent_invertHorizontalScrollFlipsMapping() throws {
        store.invertHorizontalScroll = true
        var switches: [Bool] = []
        let localSut = makeScrollSut { switches.append($0) }
        let event = try makeScrollEvent(deltaY: 0, deltaX: -60, precise: true)

        let result = localSut.handleScrollEvent(event, in: buttonContaining(event))

        XCTAssertNil(result)
        XCTAssertEqual(switches, [false])
    }

    func testHandleScrollEvent_cooldownLimitsSwitchRate() throws {
        var switches: [Bool] = []
        let localSut = makeScrollSut { switches.append($0) }

        // Second notch arrives within the cooldown and is swallowed;
        // a third, well after it, switches again
        for (timestamp, expected) in [(0.0, [true]), (0.1, [true]), (10.0, [true, true])] {
            let event = try makeScrollEvent(deltaY: 1, precise: false, timestamp: timestamp)
            XCTAssertNil(localSut.handleScrollEvent(event, in: buttonContaining(event)))
            XCTAssertEqual(switches, expected)
        }
    }

    func testHandleScrollEvent_forwardsWrapAroundPreference() throws {
        store.scrollWrapAround = true
        var wraps: [Bool] = []
        let localSut = makeScrollSut { (_: Bool, wrap: Bool) in
            wraps.append(wrap)
            return true
        }
        let event = try makeScrollEvent(deltaY: 1, precise: false)

        let result = localSut.handleScrollEvent(event, in: buttonContaining(event))

        XCTAssertNil(result)
        XCTAssertEqual(wraps, [true])
    }

    func testHandleScrollEvent_wrapAroundDisabledByDefault() throws {
        var wraps: [Bool] = []
        let localSut = makeScrollSut { (_: Bool, wrap: Bool) in
            wraps.append(wrap)
            return true
        }
        let event = try makeScrollEvent(deltaY: 1, precise: false)

        let result = localSut.handleScrollEvent(event, in: buttonContaining(event))

        XCTAssertNil(result)
        XCTAssertEqual(wraps, [false])
    }

    func testHandleScrollEvent_momentumEventsConsumedWithoutSwitching() throws {
        var switches: [Bool] = []
        let localSut = makeScrollSut { switches.append($0) }
        let event = try makeScrollEvent(deltaY: -100, precise: true, momentum: true)

        let result = localSut.handleScrollEvent(event, in: buttonContaining(event))

        XCTAssertNil(result)
        XCTAssertEqual(switches, [])
    }

    func testHandleScrollEvent_directGesturePlaysHapticEvenWithoutPreciseDeltas() throws {
        store.scrollHapticFeedback = true
        store.scrollHapticIntensity = 6
        var hapticIntensities: [Int] = []
        let localSut = AppDelegate(
            appState: appState,
            confirmAction: confirmStub.callAsFunction,
            launchAtLogin: launchAtLoginStub,
            relativeSpaceSwitchAction: { _, _ in true },
            scrollHapticAction: { hapticIntensities.append($0) }
        )
        let event = try makeScrollEvent(deltaY: 1, precise: false, phase: 2)

        XCTAssertNil(localSut.handleScrollEvent(event, in: buttonContaining(event)))

        XCTAssertEqual(hapticIntensities, [6])
    }

    func testHandleScrollEvent_noHapticWhenSwitchDoesNotHappen() throws {
        store.scrollHapticFeedback = true
        store.scrollHapticIntensity = 6
        var hapticCount = 0
        let localSut = AppDelegate(
            appState: appState,
            confirmAction: confirmStub.callAsFunction,
            launchAtLogin: launchAtLoginStub,
            relativeSpaceSwitchAction: { _, _ in false },
            scrollHapticAction: { _ in hapticCount += 1 }
        )
        let event = try makeScrollEvent(deltaY: 1, precise: false, phase: 2)

        XCTAssertNil(localSut.handleScrollEvent(event, in: buttonContaining(event)))

        XCTAssertEqual(hapticCount, 0)
    }

    func testHandleScrollEvent_preciseScrollWithoutGesturePhaseDoesNotPlayHaptic() throws {
        store.scrollHapticFeedback = true
        var hapticCount = 0
        let localSut = AppDelegate(
            appState: appState,
            confirmAction: confirmStub.callAsFunction,
            launchAtLogin: launchAtLoginStub,
            relativeSpaceSwitchAction: { _, _ in true },
            scrollHapticAction: { _ in hapticCount += 1 }
        )
        let event = try makeScrollEvent(deltaY: 60, precise: true)

        XCTAssertNil(localSut.handleScrollEvent(event, in: buttonContaining(event)))

        XCTAssertEqual(hapticCount, 0)
    }

    // MARK: - Size Scale Tests

    func testSizeScale_defaultValue() {
        XCTAssertEqual(Layout.defaultSizeScale, 100.0, "Default size scale should be 100")
    }

    func testSizeScale_range() {
        XCTAssertEqual(Layout.sizeScaleRange.lowerBound, 60.0, "Size scale lower bound should be 60")
        XCTAssertEqual(Layout.sizeScaleRange.upperBound, 120.0, "Size scale upper bound should be 120")
    }

    func testSizeScale_canBeModified() {
        store.sizeScale = 85.0
        XCTAssertEqual(store.sizeScale, 85.0)

        store.sizeScale = 115.0
        XCTAssertEqual(store.sizeScale, 115.0)
    }

    // MARK: - Space Preferences Edge Cases

    func testSpacePreferences_handleSpaceZero() {
        // Space 0 typically means "unknown space"
        SpacePreferences.setColors(SpaceColors(foreground: .red, background: .blue), forSpace: 0, store: store)

        // Should still work (storage allows it)
        let colors = SpacePreferences.colors(forSpace: 0, store: store)
        XCTAssertNotNil(colors)
    }

    func testSpacePreferences_handleLargeSpaceNumbers() {
        let largeSpace = 100

        SpacePreferences.setIconStyle(.hexagonOutline, forSpace: largeSpace, store: store)

        XCTAssertEqual(SpacePreferences.iconStyle(forSpace: largeSpace, store: store), .hexagonOutline)
    }

    func testSpacePreferences_handleNegativeSpaceNumbers() {
        let negativeSpace = -1

        SpacePreferences.setIconStyle(.circle, forSpace: negativeSpace, store: store)

        XCTAssertEqual(SpacePreferences.iconStyle(forSpace: negativeSpace, store: store), .circle)
    }

    // MARK: - Observer/Task Lifecycle Tests

    func testStartObservingAppState_createsObservationTask() {
        XCTAssertNil(sut.observationTask, "Task should not exist before starting observation")

        sut.startObservingAppState()

        XCTAssertNotNil(sut.observationTask, "Task should exist after starting observation")
    }

    func testStopObservingAppState_cancelsTask() {
        sut.startObservingAppState()
        XCTAssertNotNil(sut.observationTask)

        sut.stopObservingAppState()

        XCTAssertNil(sut.observationTask, "Task should be nil after stopping observation")
    }

    func testObservationTask_isCancelledOnStop() {
        sut.startObservingAppState()
        let task = sut.observationTask
        XCTAssertNotNil(task)

        sut.stopObservingAppState()

        // Task.cancel() is synchronous, so the task is immediately marked cancelled
        XCTAssertTrue(task?.isCancelled ?? false, "Task should be cancelled after stopping observation")
    }

    func testObservation_updatesStatusBarIconOnAppStateChange() async {
        sut.startObservingAppState()
        let initialCount = sut.statusBarIconUpdateCount

        // Brief yield to let observation loop register its first tracking
        await Task.yield()

        // Trigger an app state change
        appState.setSpaceState(labels: ["1", "2", "3"], currentSpace: 3, currentLabel: "3")

        // Wait for the observation callback to fire
        let didChange = await waitForCountChange(from: initialCount)

        // The observation task should have triggered updateStatusBarIcon
        XCTAssertTrue(didChange, "status bar update count should change after appState mutation")
        XCTAssertGreaterThan(
            sut.statusBarIconUpdateCount,
            initialCount,
            "updateStatusBarIcon should be called when appState changes"
        )
    }

    func testStopObservingAppState_stopsObservationLoop() async {
        sut.startObservingAppState()
        XCTAssertNotNil(sut.observationTask, "Task should exist after starting")

        // Brief yield to let observation loop register its first tracking
        await Task.yield()

        // Stop observation
        sut.stopObservingAppState()
        XCTAssertNil(sut.observationTask, "Task should be nil after stopping")

        // Trigger a change - the previously-registered onChange callback may still fire
        let countBeforeFirstChange = sut.statusBarIconUpdateCount
        appState.setSpaceState(labels: ["1", "2"], currentSpace: 1, currentLabel: "1")

        // Wait for any pending callback (poll until count changes or timeout)
        _ = await waitForCountChange(from: countBeforeFirstChange)

        // Record count (may or may not have incremented from pending callback)
        let countAfterFirstChange = sut.statusBarIconUpdateCount

        // Trigger another change - this should NOT trigger any callback
        // because the loop is stopped and no new observation was registered
        appState.setSpaceState(labels: ["1", "2", "3"], currentSpace: 2, currentLabel: "2")

        // Poll to verify count does NOT change (should timeout with count unchanged)
        let countChanged = await waitForCountChange(from: countAfterFirstChange)

        // Count should be stable - no new callbacks registered after loop stopped
        XCTAssertFalse(
            countChanged,
            "Count should stabilize after observation loop stops (first change may fire pending callback, second should not)"
        )
        XCTAssertEqual(
            sut.statusBarIconUpdateCount,
            countAfterFirstChange,
            "statusBarIconUpdateCount should remain unchanged after second state change"
        )

        // Task should still be nil
        XCTAssertNil(sut.observationTask, "Task should remain nil after changes")
    }

    func testTearDown_cancelsObservationTask_preventingLeaks() {
        // Create a new delegate and start observation
        let localStub = CGSStub()
        localStub.activeDisplayIdentifier = "Main"
        localStub.displays = [
            CGSStub.makeDisplay(displayID: "Main", spaces: [(id: 100, isFullscreen: false)], activeSpaceID: 100),
        ]
        let localAppState = AppState(displaySpaceProvider: localStub, skipObservers: true, store: store)
        let localDelegate = AppDelegate(
            appState: localAppState,
            confirmAction: StubConfirmAction().callAsFunction,
            launchAtLogin: StubLaunchAtLoginProvider()
        )

        localDelegate.startObservingAppState()
        XCTAssertNotNil(localDelegate.observationTask, "Task should be running")

        // Simulate tearDown
        localDelegate.stopObservingAppState()

        XCTAssertNil(localDelegate.observationTask, "Task should be nil after cleanup")
    }

    // MARK: - Preference Observation

    func testExternalNonIconKeyWriteInvalidatesMemoCache() async throws {
        sut.startObservingPreferences()
        defer { sut.stopObservingPreferences() }

        // Prime the memo cache with the current value
        XCTAssertEqual(store.scrollSensitivity, Layout.defaultScrollSensitivity)

        // External writes bypassing the store's subscript (e.g. `defaults write`).
        // Each retry writes a new value: the observation stream subscribes
        // asynchronously, so an early write can land before the observer
        // exists, and rewriting an unchanged value emits no KVO event
        let key = store.keyFor(KeySpecs.scrollSensitivity)
        let deadline = ContinuousClock.now.advanced(by: .seconds(2))
        var external = Layout.defaultScrollSensitivity
        while store.scrollSensitivity == Layout.defaultScrollSensitivity, ContinuousClock.now < deadline {
            external += 1
            Defaults[key] = external
            try await Task.sleep(for: .milliseconds(25))
        }
        XCTAssertEqual(store.scrollSensitivity, external)
    }

    func testPreservingSystemSpaceNumbersRebuildsSnapshot() async throws {
        stub.activeDisplayIdentifier = "DisplayB"
        stub.displays = [
            CGSStub.makeDisplay(
                displayID: "DisplayB",
                spaces: [(id: 200, isFullscreen: false), (id: 201, isFullscreen: false)],
                activeSpaceID: 200
            ),
            CGSStub.makeDisplay(
                displayID: "DisplayA",
                spaces: [
                    (id: 100, isFullscreen: false),
                    (id: 101, isFullscreen: false),
                    (id: 102, isFullscreen: false),
                ],
                activeSpaceID: 100
            ),
        ]
        stub.displayBoundsMap = [
            "DisplayA": CGRect(x: 0, y: 0, width: 1728, height: 1117),
            "DisplayB": CGRect(x: 1728, y: 0, width: 2560, height: 1440),
        ]
        // The physical order only takes effect while every display is shown
        store.showAllDisplays = true
        store.displayOrder = .physical
        store.preserveSystemSpaceNumbers = false
        appState.forceSpaceUpdate()
        XCTAssertEqual(appState.allDisplaysSpaceInfo.map(\.globalStartIndex), [1, 4])

        sut.startObservingPreferences()
        defer { sut.stopObservingPreferences() }

        let deadline = ContinuousClock.now.advanced(by: .seconds(2))
        while appState.allDisplaysSpaceInfo.map(\.globalStartIndex) != [3, 1], ContinuousClock.now < deadline {
            store.preserveSystemSpaceNumbers = false
            try await Task.sleep(for: .milliseconds(25))
            store.preserveSystemSpaceNumbers = true
            try await Task.sleep(for: .milliseconds(25))
        }

        XCTAssertEqual(appState.allDisplaysSpaceInfo.map(\.globalStartIndex), [3, 1])
    }

    func testPaddingEditWhileShrunkReturnsIconToFullSize() async throws {
        sut.startObservingPreferences()
        defer { sut.stopObservingPreferences() }
        appState.shrinkLevel = .compact

        // Written through the store, as every edit in Settings is: the memo
        // and the icon cache counter both move before the observer runs, so
        // the reset cannot depend on reading a width from either
        let deadline = ContinuousClock.now.advanced(by: .seconds(2))
        var padding = store.paddingScale
        while appState.shrinkLevel != .full, ContinuousClock.now < deadline {
            padding += 1
            store.paddingScale = padding
            try await Task.sleep(for: .milliseconds(25))
        }

        XCTAssertEqual(appState.shrinkLevel, .full)
    }

    func testColorEditWhileShrunkLeavesTheIconShrunk() async throws {
        sut.startObservingPreferences()
        defer { sut.stopObservingPreferences() }
        appState.shrinkLevel = .compact

        // Growing back reflows every icon to the left of ours, which a repaint
        // has not earned
        store.spaceColors = [1: SpaceColors(foreground: .red, background: .blue)]
        try await Task.sleep(for: .milliseconds(250))

        XCTAssertEqual(appState.shrinkLevel, .compact)
    }

    // MARK: - Settings Reset

    func testResetAllSettings_restoresDefaultsAndTurnsOffLaunchAtLogin() {
        store.showAllSpaces = true
        store.sizeScale = Layout.defaultSizeScale + 25
        SpacePreferences.setLabel("Work", forSpace: 1, store: store)
        launchAtLoginStub.isEnabled = true
        confirmStub.shouldConfirm = true

        sut.actionHandler.resetAllSettings()

        XCTAssertFalse(store.showAllSpaces)
        XCTAssertEqual(store.sizeScale, Layout.defaultSizeScale)
        XCTAssertTrue(store.spaceLabels.isEmpty)
        XCTAssertFalse(launchAtLoginStub.isEnabled)
        XCTAssertEqual(confirmStub.alertsShown.count, 1)
        XCTAssertTrue(confirmStub.alertsShown[0].isDestructive)
    }

    func testResetAllSettings_declinedLeavesEverythingAlone() {
        store.showAllSpaces = true
        launchAtLoginStub.isEnabled = true
        confirmStub.shouldConfirm = false

        sut.actionHandler.resetAllSettings()

        XCTAssertTrue(store.showAllSpaces)
        XCTAssertTrue(launchAtLoginStub.isEnabled)
    }

    /// The default reset action is a no-op precisely so these tests cannot
    /// wipe the developer's recorded hotkeys; the spy proves the seam fires
    /// only on a confirmed reset.
    func testResetAllSettings_invokesInjectedHotkeyReset() {
        var resetCount = 0
        // Bound to a local first: a trailing closure here would bind to
        // `missionControlNotificationSender`, the initializer's first
        // closure parameter.
        let resetHotkeysAction: () -> Void = { resetCount += 1 }
        let localSut = AppDelegate(
            appState: appState,
            confirmAction: confirmStub.callAsFunction,
            launchAtLogin: launchAtLoginStub,
            resetHotkeysAction: resetHotkeysAction
        )
        defer {
            localSut.stopObservingAppState()
        }

        confirmStub.shouldConfirm = false
        localSut.actionHandler.resetAllSettings()
        XCTAssertEqual(resetCount, 0)

        confirmStub.shouldConfirm = true
        localSut.actionHandler.resetAllSettings()
        XCTAssertEqual(resetCount, 1)
    }

    /// The injected spy keeps the test off Sparkle's real SU* defaults, the
    /// same way the hotkey seam above protects recorded hotkeys.
    func testResetAllSettings_invokesInjectedUpdaterSettingsReset() {
        var resetCount = 0
        let resetUpdaterSettingsAction: () -> Void = { resetCount += 1 }
        let localSut = AppDelegate(
            appState: appState,
            confirmAction: confirmStub.callAsFunction,
            launchAtLogin: launchAtLoginStub,
            resetUpdaterSettingsAction: resetUpdaterSettingsAction
        )
        defer {
            localSut.stopObservingAppState()
        }

        confirmStub.shouldConfirm = false
        localSut.actionHandler.resetAllSettings()
        XCTAssertEqual(resetCount, 0)

        confirmStub.shouldConfirm = true
        localSut.actionHandler.resetAllSettings()
        XCTAssertEqual(resetCount, 1)
    }
}
