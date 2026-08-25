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

    @Test("the classic fallback flips at the bounce threshold")
    func gestureBounce_thresholdFlipsFallback() {
        #expect(!SpaceSwitcher.shouldFallBackToClassic(bounceCount: 1))
        #expect(SpaceSwitcher.shouldFallBackToClassic(bounceCount: 2))
    }

    private func gestureSwitch() -> SpaceSwitcher.GestureSwitch {
        SpaceSwitcher.GestureSwitch(originSpaceID: 100, targetSpaceID: 101, madeAt: Date())
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
