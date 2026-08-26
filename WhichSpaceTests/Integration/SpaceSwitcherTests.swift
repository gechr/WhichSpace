import Foundation
import Testing
@testable import WhichSpace

@MainActor
struct SpaceSwitcherTests {
    @Test("status-item mouse-up stays instant only on macOS 27")
    func statusItemMouseUp_ignoresHeldButtonOnlyWhenPayloadIsRequired() {
        #expect(!SpaceSwitcher.heldButtonRequiresClassicPath(
            buttonIsPressed: true,
            fromStatusItemClick: true,
            requiresIOHIDPayload: true
        ))
        #expect(SpaceSwitcher.heldButtonRequiresClassicPath(
            buttonIsPressed: true,
            fromStatusItemClick: true,
            requiresIOHIDPayload: false
        ))
    }

    @Test("non-click switches preserve held-window classic fallback")
    func nonClickSwitch_heldButtonStillRequiresClassicPath() {
        #expect(SpaceSwitcher.heldButtonRequiresClassicPath(
            buttonIsPressed: true,
            fromStatusItemClick: false,
            requiresIOHIDPayload: true
        ))
        #expect(!SpaceSwitcher.heldButtonRequiresClassicPath(
            buttonIsPressed: false,
            fromStatusItemClick: false,
            requiresIOHIDPayload: true
        ))
    }

    @Test("any enabled horizontal trackpad gesture satisfies macOS 27")
    func spaceSwipeGestureSetting_anyNonzeroValueIsEnabled() {
        #expect(!SpaceSwitcher.hasEnabledSpaceSwipeGesture([nil, 0, 0, nil]))
        #expect(SpaceSwitcher.hasEnabledSpaceSwipeGesture([0, 2, 0, 0]))
        #expect(SpaceSwitcher.hasEnabledSpaceSwipeGesture([1]))
    }

    @Test("global Desktop five routes to the second display")
    func globalDesktopFive_routesAcrossDisplays() throws {
        let displays = try twoDisplays()

        #expect(
            SpaceSwitcher.desktopSwitchRoute(
                number: 5,
                activeDisplayID: "DisplayA",
                displays: displays
            ) == .otherDisplay(hotKey: 122)
        )
    }

    @Test("global Desktop one routes back to the first display")
    func globalDesktopOne_routesAcrossDisplays() throws {
        let displays = try twoDisplays()

        #expect(
            SpaceSwitcher.desktopSwitchRoute(
                number: 1,
                activeDisplayID: "DisplayB",
                displays: displays
            ) == .otherDisplay(hotKey: 118)
        )
    }

    @Test("same-display global Desktop uses its Space ID")
    func globalDesktopOnActiveDisplay_usesSpaceID() throws {
        let displays = try twoDisplays()

        #expect(
            SpaceSwitcher.desktopSwitchRoute(
                number: 2,
                activeDisplayID: "DisplayA",
                displays: displays
            ) == .activeDisplay(spaceID: 101)
        )
    }

    @Test("global numbering continues across three displays")
    func globalDesktopNumbering_threeDisplays() throws {
        let displays = try [
            managedDisplay(
                identifier: "DisplayA",
                spaces: [(100, false), (101, false)],
                currentSpaceID: 100
            ),
            managedDisplay(
                identifier: "DisplayB",
                spaces: [(200, false), (201, false)],
                currentSpaceID: 200
            ),
            managedDisplay(
                identifier: "DisplayC",
                spaces: [(300, false), (301, false)],
                currentSpaceID: 300
            ),
        ]

        #expect(
            SpaceSwitcher.desktopSwitchRoute(
                number: 5,
                activeDisplayID: "DisplayA",
                displays: displays
            ) == .otherDisplay(hotKey: 122)
        )
        #expect(
            SpaceSwitcher.desktopSwitchRoute(
                number: 6,
                activeDisplayID: "DisplayC",
                displays: displays
            ) == .activeDisplay(spaceID: 301)
        )
    }

    @Test("fullscreen Spaces do not consume global Desktop numbers")
    func fullscreenSpaces_doNotConsumeGlobalDesktopNumbers() throws {
        let display = try managedDisplay(
            identifier: "DisplayA",
            spaces: [(100, false), (150, true), (101, false)],
            currentSpaceID: 100
        )

        #expect(
            SpaceSwitcher.desktopSwitchRoute(
                number: 2,
                activeDisplayID: "DisplayA",
                displays: [display]
            ) == .activeDisplay(spaceID: 101)
        )
        #expect(
            SpaceSwitcher.desktopSwitchRoute(
                number: 3,
                activeDisplayID: "DisplayA",
                displays: [display]
            ) == nil
        )
    }

    @Test("reordered cross-display route posts the target's CGS Desktop number")
    func reorderedRoute_postsCGSDesktopNumber() throws {
        let cgsDisplays = try twoDisplays()
        let reordered = [cgsDisplays[1], cgsDisplays[0]]

        // DisplayB leads the menu bar, so Desktop 5 is DisplayA's first
        // Space, which macOS still numbers Desktop 1
        #expect(
            SpaceSwitcher.desktopSwitchRoute(
                number: 5,
                activeDisplayID: "DisplayB",
                displays: reordered,
                cgsDisplays: cgsDisplays
            ) == .otherDisplay(hotKey: 118)
        )
    }

    @Test("reordered same-display route still uses its Space ID")
    func reorderedRoute_sameDisplayUsesSpaceID() throws {
        let cgsDisplays = try twoDisplays()
        let reordered = [cgsDisplays[1], cgsDisplays[0]]

        #expect(
            SpaceSwitcher.desktopSwitchRoute(
                number: 2,
                activeDisplayID: "DisplayB",
                displays: reordered,
                cgsDisplays: cgsDisplays
            ) == .activeDisplay(spaceID: 201)
        )
    }

    @Test("reordered route has no target past macOS's last numbered Desktop")
    func reorderedRoute_beyondNumberedDesktops_returnsNil() throws {
        let cgsDisplays = try [
            managedDisplay(
                identifier: "DisplayA",
                spaces: (100 ..< 108).map { (id: $0, fullscreen: false) },
                currentSpaceID: 100
            ),
            managedDisplay(
                identifier: "DisplayB",
                spaces: (200 ..< 208).map { (id: $0, fullscreen: false) },
                currentSpaceID: 200
            ),
            managedDisplay(
                identifier: "DisplayC",
                spaces: (300 ..< 308).map { (id: $0, fullscreen: false) },
                currentSpaceID: 300
            ),
        ]
        let reordered = [cgsDisplays[2], cgsDisplays[0], cgsDisplays[1]]

        // Desktop 1 in the menu bar is DisplayC's first Space, which macOS
        // numbers Desktop 17 - past the numbered shortcuts
        #expect(
            SpaceSwitcher.desktopSwitchRoute(
                number: 1,
                activeDisplayID: "DisplayA",
                displays: reordered,
                cgsDisplays: cgsDisplays
            ) == nil
        )
    }

    @Test("Desktop numbers count regular Spaces across displays in CGS order")
    func desktopNumberForSpaceID_countsAcrossDisplays() throws {
        let displays = try [
            managedDisplay(
                identifier: "DisplayA",
                spaces: [(100, false), (150, true), (101, false)],
                currentSpaceID: 100
            ),
            managedDisplay(
                identifier: "DisplayB",
                spaces: [(200, false)],
                currentSpaceID: 200
            ),
        ]

        #expect(SpaceSwitcher.desktopNumber(forSpaceID: 101, displays: displays) == 2)
        #expect(SpaceSwitcher.desktopNumber(forSpaceID: 200, displays: displays) == 3)
        #expect(SpaceSwitcher.desktopNumber(forSpaceID: 150, displays: displays) == nil)
        #expect(SpaceSwitcher.desktopNumber(forSpaceID: 999, displays: displays) == nil)
    }

    @Test("relative target is the adjacent Space when nothing is skipped")
    func relativeTarget_adjacent() {
        #expect(
            SpaceSwitcher.relativeTargetIndex(
                from: 0, goRight: true, wrap: false, spaceIDs: [100, 101, 102]
            ) == 1
        )
        #expect(
            SpaceSwitcher.relativeTargetIndex(
                from: 2, goRight: false, wrap: false, spaceIDs: [100, 101, 102]
            ) == 1
        )
    }

    @Test("skipped Spaces are jumped over in the direction of travel")
    func relativeTarget_skipsInDirection() {
        #expect(
            SpaceSwitcher.relativeTargetIndex(
                from: 0, goRight: true, wrap: false, spaceIDs: [100, 101, 102], skipping: [101]
            ) == 2
        )
        #expect(
            SpaceSwitcher.relativeTargetIndex(
                from: 0, goRight: true, wrap: false, spaceIDs: [100, 101, 102, 103], skipping: [101, 102]
            ) == 3
        )
        #expect(
            SpaceSwitcher.relativeTargetIndex(
                from: 3, goRight: false, wrap: false, spaceIDs: [100, 101, 102, 103], skipping: [101, 102]
            ) == 0
        )
    }

    @Test("clamped at the edge without wrap")
    func relativeTarget_edgeClampsWithoutWrap() {
        #expect(
            SpaceSwitcher.relativeTargetIndex(
                from: 2, goRight: true, wrap: false, spaceIDs: [100, 101, 102]
            ) == nil
        )
        #expect(
            SpaceSwitcher.relativeTargetIndex(
                from: 0, goRight: false, wrap: false, spaceIDs: [100, 101, 102]
            ) == nil
        )
    }

    @Test("only skipped Spaces ahead yields no target without wrap")
    func relativeTarget_allSkippedAhead_returnsNil() {
        #expect(
            SpaceSwitcher.relativeTargetIndex(
                from: 0, goRight: true, wrap: false, spaceIDs: [100, 101, 102], skipping: [101, 102]
            ) == nil
        )
    }

    @Test("wrap resumes from the opposite edge")
    func relativeTarget_wrapsToOppositeEdge() {
        #expect(
            SpaceSwitcher.relativeTargetIndex(
                from: 2, goRight: true, wrap: true, spaceIDs: [100, 101, 102]
            ) == 0
        )
        #expect(
            SpaceSwitcher.relativeTargetIndex(
                from: 0, goRight: false, wrap: true, spaceIDs: [100, 101, 102]
            ) == 2
        )
    }

    @Test("wrap keeps skipping from the opposite edge")
    func relativeTarget_wrapSkipsFromOppositeEdge() {
        #expect(
            SpaceSwitcher.relativeTargetIndex(
                from: 2, goRight: true, wrap: true, spaceIDs: [100, 101, 102, 103], skipping: [100, 103]
            ) == 1
        )
        #expect(
            SpaceSwitcher.relativeTargetIndex(
                from: 1, goRight: false, wrap: true, spaceIDs: [100, 101, 102, 103], skipping: [100, 103]
            ) == 2
        )
    }

    @Test("wrap that reaches the current Space again yields no target")
    func relativeTarget_wrapExhausted_returnsNil() {
        #expect(
            SpaceSwitcher.relativeTargetIndex(
                from: 1, goRight: true, wrap: true, spaceIDs: [100, 101, 102], skipping: [100, 102]
            ) == nil
        )
        #expect(
            SpaceSwitcher.relativeTargetIndex(
                from: 0, goRight: true, wrap: true, spaceIDs: [100]
            ) == nil
        )
    }

    @Test("target sighting arms the record, and the origin returning then bounces")
    func gestureBounce_targetThenOrigin_counts() {
        let record = gestureSwitch()

        let judged = SpaceSwitcher.judgeGestureSwitch(record, currentSpaceID: 101, age: 0.1)
        guard case let .keep(armed) = judged else {
            Issue.record("expected the target sighting to keep and arm the record")
            return
        }
        #expect(armed.armed)

        #expect(SpaceSwitcher.judgeGestureSwitch(armed, currentSpaceID: 100, age: 0.2) == .bounce)
    }

    @Test("the origin before any target sighting is not a bounce")
    func gestureBounce_originBeforeTarget_doesNotCount() {
        let record = gestureSwitch()
        #expect(SpaceSwitcher.judgeGestureSwitch(record, currentSpaceID: 100, age: 0.1) == .keep(record))
    }

    @Test("a third Space current leaves the record unchanged")
    func gestureBounce_unrelatedSpaceCurrent_keepsRecord() {
        let record = gestureSwitch()
        #expect(SpaceSwitcher.judgeGestureSwitch(record, currentSpaceID: 102, age: 0.1) == .keep(record))
    }

    @Test("a record past the judgement window is dropped even when armed")
    func gestureBounce_expiredRecord_isDropped() {
        var armed = gestureSwitch()
        armed.armed = true
        #expect(SpaceSwitcher.judgeGestureSwitch(armed, currentSpaceID: 100, age: 0.5) == .drop)
    }

    @Test("a record whose origin equals its target is dropped")
    func gestureBounce_degenerateRecord_isDropped() {
        let record = SpaceSwitcher.GestureSwitch(originSpaceID: 100, targetSpaceID: 100, madeAt: Date())
        #expect(SpaceSwitcher.judgeGestureSwitch(record, currentSpaceID: 100, age: 0.1) == .drop)
    }

    @Test("bounce counts escalate the fallback stage")
    func gestureBounce_countsEscalateStage() {
        #expect(SpaceSwitcher.resolveFallbackStage(
            plainBounces: 1, reduceMotionBounces: 0, wrapEnabled: true
        ) == .gesture)
        #expect(SpaceSwitcher.resolveFallbackStage(
            plainBounces: 2, reduceMotionBounces: 0, wrapEnabled: true
        ) == .reduceMotionWrap)
        #expect(SpaceSwitcher.resolveFallbackStage(
            plainBounces: 2, reduceMotionBounces: 2, wrapEnabled: true
        ) == .classic)
    }

    @Test("bounces with Reduce Motion already on escalate straight to classic")
    func gestureBounce_reduceMotionBouncesSkipWrap() {
        #expect(SpaceSwitcher.resolveFallbackStage(
            plainBounces: 0, reduceMotionBounces: 2, wrapEnabled: true
        ) == .classic)
        #expect(SpaceSwitcher.resolveFallbackStage(
            plainBounces: 0, reduceMotionBounces: 1, wrapEnabled: true
        ) == .gesture)
    }

    @Test("without the wrap opt-in, bounces escalate straight to classic")
    func gestureBounce_wrapDisabledGoesClassic() {
        #expect(SpaceSwitcher.resolveFallbackStage(
            plainBounces: 2, reduceMotionBounces: 0, wrapEnabled: false
        ) == .classic)
        #expect(SpaceSwitcher.resolveFallbackStage(
            plainBounces: 1, reduceMotionBounces: 0, wrapEnabled: false
        ) == .gesture)
    }

    @Test("enabling the opt-in after a plain-bounce classic escalation moves to the wrap")
    func gestureBounce_optInAfterClassic_movesToWrap() {
        // The same counters resolve differently as the toggle changes, so a
        // user who discovers the setting after escalation is not stuck on
        // classic until relaunch
        #expect(SpaceSwitcher.resolveFallbackStage(
            plainBounces: 2, reduceMotionBounces: 0, wrapEnabled: false
        ) == .classic)
        #expect(SpaceSwitcher.resolveFallbackStage(
            plainBounces: 2, reduceMotionBounces: 0, wrapEnabled: true
        ) == .reduceMotionWrap)
        // A wrap that already proved useless never downgrades from classic
        #expect(SpaceSwitcher.resolveFallbackStage(
            plainBounces: 2, reduceMotionBounces: 2, wrapEnabled: true
        ) == .classic)
    }

    private func gestureSwitch() -> SpaceSwitcher.GestureSwitch {
        SpaceSwitcher.GestureSwitch(originSpaceID: 100, targetSpaceID: 101, madeAt: Date())
    }

    @Test("engage leaves an already-enabled setting untouched")
    func reduceMotion_alreadyOn_neverTouched() {
        let harness = ReduceMotionHarness()
        harness.systemEnabled = true
        let controller = harness.controller()

        controller.engageForSwitch()

        #expect(harness.events.isEmpty)
        #expect(harness.scheduled.isEmpty)
        #expect(!controller.temporarilyEnabled)
    }

    @Test("engage marks the leftover before enabling, then settles")
    func reduceMotion_engage_marksBeforeEnable() {
        let harness = ReduceMotionHarness()
        let controller = harness.controller()

        controller.engageForSwitch()

        #expect(harness.events == ["marker(true)", "write(true)", "settle"])
        #expect(controller.temporarilyEnabled)
        #expect(harness.scheduled.count == 1)
    }

    @Test("a second engage extends the restore without rewriting")
    func reduceMotion_secondEngage_onlyRearms() {
        let harness = ReduceMotionHarness()
        let controller = harness.controller()

        controller.engageForSwitch()
        controller.engageForSwitch()

        #expect(harness.events == ["marker(true)", "write(true)", "settle"])
        #expect(harness.scheduled.count == 2)
    }

    @Test("the fired restore disables the setting and clears the marker")
    func reduceMotion_restore_disablesAndClears() {
        let harness = ReduceMotionHarness()
        let controller = harness.controller()

        controller.engageForSwitch()
        harness.scheduled.last?()

        #expect(harness.events == ["marker(true)", "write(true)", "settle", "write(false)", "marker(false)"])
        #expect(!controller.temporarilyEnabled)
        #expect(!harness.systemEnabled)
    }

    @Test("restore without a preceding engage does nothing")
    func reduceMotion_restoreIdle_isNoOp() {
        let harness = ReduceMotionHarness()
        let controller = harness.controller()

        controller.restore()

        #expect(harness.events.isEmpty)
    }

    @Test("an external mid-session enable is seen live, not from a cached read")
    func reduceMotion_externalEnable_seenWithoutCache() {
        let harness = ReduceMotionHarness()
        let controller = harness.controller()

        // A cached implementation would freeze this first false reading
        #expect(!controller.isEffectivelyEnabled)
        harness.systemEnabled = true

        controller.engageForSwitch()

        #expect(harness.events.isEmpty)
        #expect(!harness.marker)
        #expect(!controller.temporarilyEnabled)
    }

    @Test("an unavailable setter disables engage entirely")
    func reduceMotion_unavailableSetter_engageIsNoOp() {
        let harness = ReduceMotionHarness()
        let controller = harness.controller(available: false)

        controller.engageForSwitch()

        #expect(harness.events.isEmpty)
        #expect(!harness.marker)
    }

    @Test("leftover recovery restores the setting and clears the marker")
    func reduceMotion_leftoverRecovery_restores() {
        let harness = ReduceMotionHarness()
        harness.marker = true
        harness.systemEnabled = true
        let controller = harness.controller()

        controller.restoreLeftoverFromPreviousLaunch()

        #expect(harness.events == ["write(false)", "marker(false)"])
        #expect(!harness.systemEnabled)
    }

    @Test("leftover recovery keeps the marker when the setter is unavailable")
    func reduceMotion_leftoverRecovery_retainsMarkerWithoutSetter() {
        let harness = ReduceMotionHarness()
        harness.marker = true
        let controller = harness.controller(available: false)

        controller.restoreLeftoverFromPreviousLaunch()

        #expect(harness.marker)
        #expect(harness.events.isEmpty)
    }

    @Test("activateAppOnSpace returns false for invalid space ID")
    func activateAppOnSpace_invalidID_returnsFalse() {
        // Space ID 0 should never match a real space
        let result = SpaceSwitcher.activateAppOnSpace(0)
        #expect(!result, "Should return false for nonexistent space ID")
    }

    @Test("activateAppOnSpace returns false for very large space ID")
    func activateAppOnSpace_largeID_returnsFalse() {
        let result = SpaceSwitcher.activateAppOnSpace(Int.max)
        #expect(!result, "Should return false for nonexistent space ID")
    }

    private func twoDisplays() throws -> [SpaceSwitcher.ManagedDisplay] {
        try [
            managedDisplay(
                identifier: "DisplayA",
                spaces: [(100, false), (101, false), (102, false), (103, false)],
                currentSpaceID: 100
            ),
            managedDisplay(
                identifier: "DisplayB",
                spaces: [(200, false), (201, false), (202, false), (203, false)],
                currentSpaceID: 200
            ),
        ]
    }

    private func managedDisplay(
        identifier: String,
        spaces: [(id: Int, fullscreen: Bool)],
        currentSpaceID: Int
    ) throws -> SpaceSwitcher.ManagedDisplay {
        let rawSpaces: [[String: Any]] = spaces.map { space in
            var raw: [String: Any] = ["ManagedSpaceID": space.id]
            if space.fullscreen {
                raw["TileLayoutManager"] = [String: Any]()
            }
            return raw
        }
        return try #require(SpaceSwitcher.ManagedDisplay(dict: [
            "Display Identifier": identifier,
            "Spaces": rawSpaces,
            "Current Space": ["ManagedSpaceID": currentSpaceID],
        ]))
    }
}

/// Fake system surface for `ReduceMotionController`: records marker and
/// setter activity in order, and hands out scheduled restores for manual
/// firing, so tests never touch the real Reduce Motion setting.
private final class ReduceMotionHarness {
    var systemEnabled = false
    var marker = false
    var events: [String] = []
    var scheduled: [@MainActor () -> Void] = []

    @MainActor
    func controller(available: Bool = true) -> SpaceSwitcher.ReduceMotionController {
        SpaceSwitcher.ReduceMotionController(
            readSystemEnabled: { self.systemEnabled },
            writeSystemEnabled: available ? { enabled in
                self.systemEnabled = enabled
                self.events.append("write(\(enabled))")
            } : nil,
            readMarker: { self.marker },
            writeMarker: { present in
                self.marker = present
                self.events.append("marker(\(present))")
            },
            scheduleRestore: { body in
                self.scheduled.append(body)
                return Task {}
            },
            settleAfterEnable: { self.events.append("settle") }
        )
    }
}
