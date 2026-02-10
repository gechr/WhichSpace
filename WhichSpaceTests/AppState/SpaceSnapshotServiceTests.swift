import Testing
@testable import WhichSpace

@Suite("SpaceSnapshotService")
@MainActor
struct SpaceSnapshotServiceTests {
    // MARK: - Nil CGS Data

    @Test("nil displays returns empty snapshot")
    func nilDisplays_returnsEmpty() {
        let stub = CGSStub()
        // displays empty => copyManagedDisplaySpaces returns nil
        stub.activeDisplayIdentifier = "Main"

        let snapshot = SpaceSnapshotService.buildSnapshot(provider: stub, localSpaceNumbers: true)

        #expect(snapshot == .empty)
    }

    @Test("nil active display returns empty snapshot")
    func nilActiveDisplay_returnsEmpty() {
        let stub = CGSStub()
        stub.displays = [
            CGSStub.makeDisplay(displayID: "Main", spaces: [(id: 100, isFullscreen: false)], activeSpaceID: 100),
        ]
        // activeDisplayIdentifier is nil

        let snapshot = SpaceSnapshotService.buildSnapshot(provider: stub, localSpaceNumbers: true)

        #expect(snapshot == .empty)
    }

    // MARK: - Multi-Display Global Numbering

    @Test("multi-display global numbering is sequential across displays")
    func multiDisplay_globalNumbering() {
        let stub = CGSStub()
        stub.activeDisplayIdentifier = "DisplayA"
        stub.displays = [
            CGSStub.makeDisplay(
                displayID: "DisplayA",
                spaces: [(id: 100, isFullscreen: false), (id: 101, isFullscreen: false)],
                activeSpaceID: 100
            ),
            CGSStub.makeDisplay(
                displayID: "DisplayB",
                spaces: [
                    (id: 200, isFullscreen: false),
                    (id: 201, isFullscreen: false),
                    (id: 202, isFullscreen: false),
                ],
                activeSpaceID: 200
            ),
        ]

        let snapshot = SpaceSnapshotService.buildSnapshot(provider: stub, localSpaceNumbers: true)

        // DisplayA has 2 regular spaces => globalStartIndex 1
        // DisplayB has 3 regular spaces => globalStartIndex 3
        #expect(snapshot.allDisplaysSpaceInfo.count == 2)
        #expect(snapshot.allDisplaysSpaceInfo[0].globalStartIndex == 1)
        #expect(snapshot.allDisplaysSpaceInfo[0].regularSpaceCount == 2)
        #expect(snapshot.allDisplaysSpaceInfo[1].globalStartIndex == 3)
        #expect(snapshot.allDisplaysSpaceInfo[1].regularSpaceCount == 3)
    }

    // MARK: - Local vs Global Space Numbers

    @Test("localSpaceNumbers: true uses local labels")
    func localSpaceNumbers_true_usesLocalLabels() {
        let stub = CGSStub()
        stub.activeDisplayIdentifier = "DisplayB"
        stub.displays = [
            CGSStub.makeDisplay(
                displayID: "DisplayA",
                spaces: [(id: 100, isFullscreen: false), (id: 101, isFullscreen: false)],
                activeSpaceID: 100
            ),
            CGSStub.makeDisplay(
                displayID: "DisplayB",
                spaces: [(id: 200, isFullscreen: false), (id: 201, isFullscreen: false)],
                activeSpaceID: 200
            ),
        ]

        let snapshot = SpaceSnapshotService.buildSnapshot(provider: stub, localSpaceNumbers: true)

        // Active display is DisplayB, local numbering => label "1"
        #expect(snapshot.currentSpaceLabel == "1")
    }

    @Test("localSpaceNumbers: false uses global labels")
    func localSpaceNumbers_false_usesGlobalLabels() {
        let stub = CGSStub()
        stub.activeDisplayIdentifier = "DisplayB"
        stub.displays = [
            CGSStub.makeDisplay(
                displayID: "DisplayA",
                spaces: [(id: 100, isFullscreen: false), (id: 101, isFullscreen: false)],
                activeSpaceID: 100
            ),
            CGSStub.makeDisplay(
                displayID: "DisplayB",
                spaces: [(id: 200, isFullscreen: false), (id: 201, isFullscreen: false)],
                activeSpaceID: 200
            ),
        ]

        let snapshot = SpaceSnapshotService.buildSnapshot(provider: stub, localSpaceNumbers: false)

        // DisplayA has 2 spaces, so DisplayB starts at global index 3
        #expect(snapshot.currentSpaceLabel == "3")
        #expect(snapshot.currentGlobalSpaceIndex == 3)
    }

    // MARK: - Malformed Display Data

    @Test("display missing 'Spaces' key is skipped")
    func missingSpacesKey_skipped() {
        let stub = CGSStub()
        stub.activeDisplayIdentifier = "Good"
        stub.displays = [
            // Malformed: no "Spaces" key
            ["Display Identifier": "Bad", "Current Space": ["ManagedSpaceID": 1]] as NSDictionary,
            CGSStub.makeDisplay(displayID: "Good", spaces: [(id: 100, isFullscreen: false)], activeSpaceID: 100),
        ]

        let snapshot = SpaceSnapshotService.buildSnapshot(provider: stub, localSpaceNumbers: true)

        #expect(snapshot.allDisplaysSpaceInfo.count == 1)
        #expect(snapshot.allDisplaysSpaceInfo[0].displayID == "Good")
    }

    @Test("display missing 'Display Identifier' key is skipped")
    func missingDisplayIdentifier_skipped() {
        let stub = CGSStub()
        stub.activeDisplayIdentifier = "Good"
        stub.displays = [
            // Malformed: no "Display Identifier" key
            ["Spaces": [["ManagedSpaceID": 1]]] as NSDictionary,
            CGSStub.makeDisplay(displayID: "Good", spaces: [(id: 100, isFullscreen: false)], activeSpaceID: 100),
        ]

        let snapshot = SpaceSnapshotService.buildSnapshot(provider: stub, localSpaceNumbers: true)

        #expect(snapshot.allDisplaysSpaceInfo.count == 1)
        #expect(snapshot.allDisplaysSpaceInfo[0].displayID == "Good")
    }

    @Test("space missing ManagedSpaceID is skipped")
    func missingManagedSpaceID_skipped() {
        let stub = CGSStub()
        stub.activeDisplayIdentifier = "Main"
        // Build manually so we can include a broken space entry
        stub.displays = [
            [
                "Display Identifier": "Main",
                "Spaces": [
                    ["ManagedSpaceID": 100],
                    ["BadKey": 999], // Missing ManagedSpaceID
                    ["ManagedSpaceID": 102],
                ],
                "Current Space": ["ManagedSpaceID": 100],
            ] as NSDictionary,
        ]

        let snapshot = SpaceSnapshotService.buildSnapshot(provider: stub, localSpaceNumbers: true)

        // Should have 2 entries (the broken one skipped)
        #expect(snapshot.allSpaceEntries.count == 2)
        #expect(snapshot.allSpaceEntries.map(\.label) == ["1", "2"])
    }

    // MARK: - Fullscreen Space Numbering

    @Test("fullscreen spaces are labeled 'F' and don't increment regular index")
    func fullscreenSpaces_labeledCorrectly() {
        let stub = CGSStub()
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

        let snapshot = SpaceSnapshotService.buildSnapshot(provider: stub, localSpaceNumbers: true)

        let labels = snapshot.allSpaceEntries.map(\.label)
        #expect(labels == ["1", "F", "2", "F"])

        let regularIndices = snapshot.allSpaceEntries.map(\.regularIndex)
        #expect(regularIndices == [1, nil, 2, nil])
    }

    @Test("fullscreen spaces don't count toward global numbering")
    func fullscreenSpaces_dontAffectGlobalNumbering() {
        let stub = CGSStub()
        stub.activeDisplayIdentifier = "DisplayB"
        stub.displays = [
            CGSStub.makeDisplay(
                displayID: "DisplayA",
                spaces: [
                    (id: 100, isFullscreen: false),
                    (id: 101, isFullscreen: true),
                    (id: 102, isFullscreen: false),
                ],
                activeSpaceID: 100
            ),
            CGSStub.makeDisplay(
                displayID: "DisplayB",
                spaces: [(id: 200, isFullscreen: false)],
                activeSpaceID: 200
            ),
        ]

        let snapshot = SpaceSnapshotService.buildSnapshot(provider: stub, localSpaceNumbers: false)

        // DisplayA has 2 regular spaces (fullscreen doesn't count)
        // So DisplayB starts at global index 3
        #expect(snapshot.allDisplaysSpaceInfo[1].globalStartIndex == 3)
        #expect(snapshot.currentGlobalSpaceIndex == 3)
        #expect(snapshot.currentSpaceLabel == "3")
    }
}
