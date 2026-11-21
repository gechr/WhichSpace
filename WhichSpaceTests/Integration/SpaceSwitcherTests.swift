import AppKit
import Testing
@testable import WhichSpace

@MainActor
struct SpaceSwitcherTests {
    @Test("fullscreen gestures follow the target display and classic steps require focus there")
    func fullscreenDisplayRouting() {
        #expect(SpaceSwitcher.canStepToFullscreen(
            displayID: "B",
            pointerOnTarget: true,
            classic: false,
            focusedDisplay: "A"
        ))
        #expect(!SpaceSwitcher.canStepToFullscreen(
            displayID: "B",
            pointerOnTarget: false,
            classic: false,
            focusedDisplay: "B"
        ))
        #expect(!SpaceSwitcher.canStepToFullscreen(
            displayID: "B",
            pointerOnTarget: true,
            classic: true,
            focusedDisplay: "A"
        ))
        #expect(SpaceSwitcher.canStepToFullscreen(
            displayID: "B",
            pointerOnTarget: true,
            classic: true,
            focusedDisplay: "B"
        ))
        #expect(SpaceSwitcher.canStepToFullscreen(
            displayID: "Main",
            pointerOnTarget: false,
            classic: true,
            focusedDisplay: nil
        ))
    }

    @Test("a fullscreen jump focuses the matching window and can fall back to the other tile")
    func fullscreenFocusUsesWindowMembership() {
        func window(_ id: CGWindowID, pid: pid_t) -> [String: Any] {
            [kCGWindowLayer as String: 0, kCGWindowNumber as String: id, kCGWindowOwnerPID as String: pid]
        }
        let ownPID = ProcessInfo.processInfo.processIdentifier
        let windows = [
            window(5, pid: ownPID),
            window(4, pid: 22),
            window(1, pid: 15),
            window(2, pid: 15),
            window(3, pid: 15),
        ]
        let membership: [CGWindowID: [Int]] = [1: [70], 2: [70, 71], 3: [71], 4: [71], 5: [71]]
        var attempted: [CGWindowID] = []
        let focused = SpaceSwitcher.focusFullscreenWindow(
            on: 71,
            owners: [ownPID, 15, 22],
            windows: windows,
            membership: {
                membership[$0] ?? []
            }
        ) { window in
            attempted.append(window.id)
            return window.id == 4
        }
        #expect(focused)
        #expect(attempted == [3, 4])
        #expect(!SpaceSwitcher.focusFullscreenWindow(on: 72, owners: [15], windows: windows, membership: {
            membership[$0] ?? []
        }) { _ in true })
    }

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

    @Test("HID-backed swipes flip direction when Natural scrolling is off")
    func augmentedSwipe_flipsDirectionWithoutNaturalScrolling() {
        #expect(SpaceSwitcher.isNaturalScrollingEnabled(nil))
        #expect(SpaceSwitcher.isNaturalScrollingEnabled(1))
        #expect(!SpaceSwitcher.isNaturalScrollingEnabled(0))

        #expect(SpaceSwitcher.augmentedSwipeGoesRight(requested: true, naturalScrollingEnabled: true))
        #expect(!SpaceSwitcher.augmentedSwipeGoesRight(requested: false, naturalScrollingEnabled: true))
        #expect(!SpaceSwitcher.augmentedSwipeGoesRight(requested: true, naturalScrollingEnabled: false))
        #expect(SpaceSwitcher.augmentedSwipeGoesRight(requested: false, naturalScrollingEnabled: false))
    }

    @Test("system spaces are excluded from Desktop switching routes")
    func systemSpaces_excludedFromSwitching() throws {
        let display = try #require(SpaceSwitcher.ManagedDisplay(dict: [
            "Display Identifier": "DisplayA",
            "Spaces": [
                ["ManagedSpaceID": 90, "type": 2],
                ["ManagedSpaceID": 100, "type": 0],
                ["ManagedSpaceID": 150, "type": 4, "TileLayoutManager": [String: Any]()],
                ["ManagedSpaceID": 101],
            ],
            "Current Space": ["ManagedSpaceID": 100],
        ]))
        let displays = try [
            display,
            managedDisplay(identifier: "DisplayB", spaces: [(200, false)], currentSpaceID: 200),
        ]

        #expect(display.spaces.map(\.id) == [100, 150, 101])
        #expect(display.spaces.map(\.isFullscreen) == [false, true, false])
        #expect(SpaceSwitcher.desktopNumber(forSpaceID: 90, displays: displays) == nil)
        #expect(SpaceSwitcher.desktopNumber(forSpaceID: 101, displays: displays) == 2)
        #expect(SpaceSwitcher.desktopNumber(forSpaceID: 200, displays: displays) == 3)
        #expect(
            SpaceSwitcher.desktopSwitchRoute(to: .global(1), activeDisplayID: "DisplayA", displays: displays)
                == .activeDisplay(spaceID: 100)
        )
        #expect(
            SpaceSwitcher.desktopSwitchRoute(to: .global(2), activeDisplayID: "DisplayA", displays: displays)
                == .activeDisplay(spaceID: 101)
        )
        #expect(
            SpaceSwitcher.desktopSwitchRoute(to: .global(3), activeDisplayID: "DisplayA", displays: displays)
                == .otherDisplay(hotKey: 120)
        )
        #expect(SpaceSwitcher
            .desktopSwitchRoute(to: .global(4), activeDisplayID: "DisplayA", displays: displays) == nil)
    }

    @Test("gesture routing follows the pointer and falls back to focus")
    func receivingDisplay() throws {
        let displays = try twoDisplays()
        let bounds = { (id: String) -> CGRect? in
            CGRect(x: id == "DisplayA" ? 0 : 100, y: 0, width: 100, height: 100)
        }
        func display(at pointer: CGPoint?, classic: Bool = false) -> String? {
            SpaceSwitcher.switchingDisplay(
                in: displays,
                classic: classic,
                pointer: pointer,
                focusedDisplay: "DisplayA",
                bounds: bounds
            )?
                .identifier
        }
        let pointerDisplay = try #require(display(at: CGPoint(x: 125, y: 50)))
        #expect(pointerDisplay == "DisplayB")
        #expect(SpaceSwitcher.desktopSwitchRoute(to: .global(5), activeDisplayID: pointerDisplay, displays: displays)
            == .activeDisplay(spaceID: 200))
        #expect(display(at: CGPoint(x: 125, y: 50), classic: true) == "DisplayA")
        #expect(display(at: nil) == "DisplayA")
        #expect(display(at: CGPoint(x: -50, y: 50)) == "DisplayA")

        let shared = try managedDisplay(identifier: "Main", spaces: [(1, false)], currentSpaceID: 1)
        let display = SpaceSwitcher.switchingDisplay(
            in: [shared],
            classic: false,
            pointer: .zero,
            focusedDisplay: "A"
        ) { _ in nil }
        #expect(display?.identifier == "Main")
    }

    @Test("relative switches clamp at the edge of the receiving display")
    func relativeSwitchAtPointerDisplayEdge() throws {
        let displays = try [
            managedDisplay(identifier: "Left", spaces: [(41, false), (42, false)], currentSpaceID: 41),
            managedDisplay(identifier: "Right", spaces: [(51, false), (52, false)], currentSpaceID: 52),
        ]
        func target(classic: Bool) -> Int? {
            let route = SpaceSwitcher.relativeSwitchRoute(
                in: displays,
                classic: classic,
                goRight: true,
                wrap: false,
                pointer: CGPoint(x: 140, y: 30),
                focusedDisplay: "Left"
            ) { id in
                CGRect(x: id == "Right" ? 100 : 0, y: 0, width: 100, height: 100)
            }
            return route.map { $0.display.spaces[$0.targetIndex].id }
        }

        #expect(target(classic: false) == nil)
        #expect(target(classic: true) == 42)
    }

    @Test("numbered and absolute targets distinguish the pointer display from keyboard focus")
    func pointerAndFocusRoutes() throws {
        let displays = try [
            managedDisplay(identifier: "A", spaces: [(10, false), (11, false)], currentSpaceID: 11),
            managedDisplay(identifier: "B", spaces: [(20, false), (21, false), (22, true)], currentSpaceID: 20),
            managedDisplay(identifier: "C", spaces: [(30, false)], currentSpaceID: 30),
        ]
        func route(_ target: SpaceSwitcher.SwitchTarget) -> SpaceSwitcher.DesktopSwitchRoute? {
            SpaceSwitcher.desktopSwitchRoute(
                to: target,
                activeDisplayID: "B",
                focusedDisplayID: "A",
                displays: displays
            )
        }
        #expect(route(.local(2)) == .activeDisplay(spaceID: 21))
        #expect(route(.local(3)) == .fullscreen(spaceID: 22))
        #expect(route(.local(4)) == nil)
        #expect(route(.global(1)) == .focusedDisplay(spaceID: 10))
        #expect(route(.id(10)) == .focusedDisplay(spaceID: 10))
        #expect(route(.id(20)) == .otherDisplay(hotKey: 120))
        #expect(route(.global(3)) == .otherDisplay(hotKey: 120))
        #expect(route(.id(30)) == .otherDisplay(hotKey: 122))
    }

    @Test("cross-display gestures target the destination Desktop in global coordinates")
    func crossDisplayGestureRoute() throws {
        let displays = try [
            managedDisplay(identifier: "East", spaces: [(28, false), (29, false)], currentSpaceID: 28),
            managedDisplay(identifier: "North", spaces: [(31, false)], currentSpaceID: 31),
            managedDisplay(identifier: "South", spaces: [(40, false)], currentSpaceID: 40),
            managedDisplay(identifier: "West", spaces: [(14, false), (15, false)], currentSpaceID: 14),
        ]
        let west = CGRect(x: -900, y: -200, width: 900, height: 600)
        func route(_ target: SpaceSwitcher.SwitchTarget, focus: String, bounds: CGRect?) -> SpaceSwitcher
            .DesktopSwitchRoute?
        {
            let targetBounds = { (id: String) in id == "West" ? bounds : nil }
            return SpaceSwitcher.desktopSwitchRoute(
                to: target,
                activeDisplayID: "East",
                focusedDisplayID: focus,
                displays: displays,
                gestureBounds: targetBounds
            )
        }

        let gesture = SpaceSwitcher.DesktopSwitchRoute.targetedGesture(
            displayID: "West", spaceID: 15, location: CGPoint(x: -450, y: 100)
        )
        #expect(route(.global(6), focus: "North", bounds: west) == gesture)
        #expect(route(.id(15), focus: "West", bounds: west) == gesture)
        #expect(route(.global(5), focus: "North", bounds: west) == .otherDisplay(hotKey: 122))
        #expect(route(.global(6), focus: "North", bounds: nil) == .otherDisplay(hotKey: 123))
        #expect(route(.global(6), focus: "West", bounds: .zero) == .focusedDisplay(spaceID: 15))

        // A quick return to the original Desktop can precede the snapshot of the outward switch.
        let back = SpaceSwitcher.desktopSwitchRoute(
            to: .id(14),
            activeDisplayID: "East",
            focusedDisplayID: "North",
            displays: displays,
            predictedIndex: { $0 == "West" ? 1 : nil },
            gestureBounds: { _ in west }
        )
        #expect(back == .targetedGesture(displayID: "West", spaceID: 14, location: CGPoint(x: -450, y: 100)))
    }

    @Test("an unfocused pointer display routes from its predicted Desktop")
    func pointerDisplayPrediction() throws {
        let displays = try [
            managedDisplay(identifier: "A", spaces: [(11, false)], currentSpaceID: 11),
            managedDisplay(identifier: "B", spaces: [(21, false), (22, false)], currentSpaceID: 21),
        ]
        let prediction = { (display: String) in display == "B" ? 1 : nil }
        func route(to id: Int) -> SpaceSwitcher.DesktopSwitchRoute? {
            SpaceSwitcher.desktopSwitchRoute(
                to: .id(id),
                activeDisplayID: "B",
                focusedDisplayID: "A",
                displays: displays,
                predictedIndex: prediction
            )
        }
        #expect(route(to: 21) == .activeDisplay(spaceID: 21))
        #expect(route(to: 22) == .otherDisplay(hotKey: 120))
    }

    @Test("every phase of a targeted swipe carries the destination point")
    func targetedSwipeEvents() throws {
        let point = CGPoint(x: -415, y: 210)
        let phase = try #require(CGEventField(rawValue: 132))
        func verify(_ usesHIDPayload: Bool) {
            var events: [CGEvent] = []
            let posted = SpaceSwitcher.postSwipeGesture(
                goRight: true, velocity: 2000, at: point, usesHIDPayload: usesHIDPayload
            ) { events.append($0) }
            #expect(posted)
            #expect(events.map { $0.getIntegerValueField(phase) } == [1, 2, 4])
            #expect(events.map(\.location) == [point, point, point])
        }
        verify(false)
        if #available(macOS 27, *) {
            verify(true)
        }
    }

    @Test("global Desktop five routes to the second display")
    func globalDesktopFive_routesAcrossDisplays() throws {
        let displays = try twoDisplays()

        #expect(
            SpaceSwitcher.desktopSwitchRoute(
                to: .global(5),
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
                to: .global(1),
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
                to: .global(2),
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
                to: .global(5),
                activeDisplayID: "DisplayA",
                displays: displays
            ) == .otherDisplay(hotKey: 122)
        )
        #expect(
            SpaceSwitcher.desktopSwitchRoute(
                to: .global(6),
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
                to: .global(2),
                activeDisplayID: "DisplayA",
                displays: [display]
            ) == .activeDisplay(spaceID: 101)
        )
        #expect(
            SpaceSwitcher.desktopSwitchRoute(
                to: .global(3),
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
                to: .global(5),
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
                to: .global(2),
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
                to: .global(1),
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

    @Test("stalled full-screen selection retries with the other method", arguments: [true, false], [21, 22, 23, nil])
    func verifyFullscreenActivation(stepAccepted: Bool, current: Int?) async throws {
        let selection = FullscreenActivation()
        let spaces = [(21, false), (22, true), (23, false)]
        var display: SpaceSwitcher.ManagedDisplay? = try managedDisplay(
            identifier: "Main", spaces: spaces, currentSpaceID: 21
        )
        var events: [String] = []
        selection.select(
            target: 22,
            targetDisplay: { display },
            step: { _ in
                events.append("step")
                return stepAccepted
            },
            activate: { _ in
                events.append("activate")
                return true
            },
            delay: .zero
        ) { _ in events.append("stall") }
        let initial = stepAccepted ? ["step"] : ["step", "activate"]
        #expect(events == initial)
        display = try current.map { try managedDisplay(identifier: "Main", spaces: spaces, currentSpaceID: $0) }
        await selection.pending?.value
        let retry = ["stall", stepAccepted ? "activate" : "step"]
        #expect(events == (current == 21 ? initial + retry : initial))
    }

    @Test("a new selection cancels an earlier fullscreen retry")
    func supersedeFullscreenActivation() async throws {
        let selection = FullscreenActivation()
        let display = try managedDisplay(identifier: "Main", spaces: [(21, true), (22, true)], currentSpaceID: 21)
        var retried = false
        selection.select(
            target: 22,
            targetDisplay: { display },
            step: { _ in true },
            activate: { _ in
                retried = true
                return true
            },
            delay: .zero
        )
        let pending = try #require(selection.pending)
        selection.select(target: 21, targetDisplay: { display }, step: { _ in true }, activate: { _ in true })
        await pending.value
        #expect(!retried)
        #expect(selection.pending == nil)
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
