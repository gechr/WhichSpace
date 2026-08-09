import Testing
@testable import WhichSpace

@MainActor
struct SpaceSwitcherTests {
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
