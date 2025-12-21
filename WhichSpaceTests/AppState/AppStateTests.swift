import XCTest
@testable import WhichSpace

@MainActor
final class AppStateTests: XCTestCase {
    private var stub: CGSStub!
    private var sut: AppState!
    private var store: DefaultsStore!
    private var testSuite: TestSuite!

    override func setUp() {
        super.setUp()
        testSuite = TestSuiteFactory.createSuite()
        store = DefaultsStore(suite: testSuite.suite)
        stub = CGSStub()
    }

    override func tearDown() {
        sut = nil
        stub = nil
        if let store, let testSuite {
            store.resetAll()
            TestSuiteFactory.destroySuite(testSuite)
        }
        store = nil
        testSuite = nil
        super.tearDown()
    }

    // MARK: - Space Detection Tests

    func testSingleDisplayWithThreeRegularSpaces_activeIndexCorrect() {
        // Given: Single display with 3 regular spaces, space 2 active
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

        // When
        sut = AppState(displaySpaceProvider: stub, skipObservers: true, store: store)

        // Then
        XCTAssertEqual(sut.currentSpace, 2, "Active space should be index 2 (1-based)")
        XCTAssertEqual(sut.currentSpaceLabel, "2", "Label should be '2'")
    }

    func testSingleDisplayWithThreeRegularSpaces_labelsIncrementAsExpected() {
        // Given: Single display with 3 regular spaces
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

        // When
        sut = AppState(displaySpaceProvider: stub, skipObservers: true, store: store)

        // Then
        XCTAssertEqual(sut.allSpaceLabels, ["1", "2", "3"], "Labels should increment 1, 2, 3")
    }

    func testFullscreenSpaceLabeling() {
        // Given: Display with regular, fullscreen, regular spaces
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

        // When
        sut = AppState(displaySpaceProvider: stub, skipObservers: true, store: store)

        // Then
        XCTAssertEqual(
            sut.allSpaceLabels,
            ["1", Labels.fullscreen, "2"],
            "Fullscreen should be 'F', numbering resumes after"
        )
        XCTAssertEqual(sut.currentSpaceLabel, Labels.fullscreen, "Active fullscreen space label should be 'F'")
    }

    func testFullscreenSpace_numberingResumesAfterward() {
        // Given: Display with regular, fullscreen, regular, fullscreen, regular spaces
        stub.activeDisplayIdentifier = "Main"
        stub.displays = [
            CGSStub.makeDisplay(
                displayID: "Main",
                spaces: [
                    (id: 100, isFullscreen: false),
                    (id: 101, isFullscreen: true),
                    (id: 102, isFullscreen: false),
                    (id: 103, isFullscreen: true),
                    (id: 104, isFullscreen: false),
                ],
                activeSpaceID: 104
            ),
        ]

        // When
        sut = AppState(displaySpaceProvider: stub, skipObservers: true, store: store)

        // Then
        XCTAssertEqual(sut.allSpaceLabels, ["1", Labels.fullscreen, "2", Labels.fullscreen, "3"])
        XCTAssertEqual(sut.currentSpace, 5, "Active space index should be 5")
        XCTAssertEqual(sut.currentSpaceLabel, "3", "Label should be '3' (3rd regular space)")
    }

    func testInactiveDisplayIgnored() {
        // Given: Two displays, only one is active menu bar display
        stub.activeDisplayIdentifier = "DisplayA"
        stub.displays = [
            CGSStub.makeDisplay(
                displayID: "DisplayA",
                spaces: [
                    (id: 100, isFullscreen: false),
                    (id: 101, isFullscreen: false),
                ],
                activeSpaceID: 100
            ),
            CGSStub.makeDisplay(
                displayID: "DisplayB",
                spaces: [
                    (id: 200, isFullscreen: false),
                    (id: 201, isFullscreen: false),
                    (id: 202, isFullscreen: false),
                ],
                activeSpaceID: 201
            ),
        ]

        // When
        sut = AppState(displaySpaceProvider: stub, skipObservers: true, store: store)

        // Then: Should use DisplayA (active), not DisplayB
        XCTAssertEqual(sut.allSpaceLabels, ["1", "2"], "Should show spaces from active display only")
        XCTAssertEqual(sut.currentSpace, 1, "Should show space 1 from active display")
    }

    func testMainDisplayFallback() {
        // Given: Display with "Main" identifier should be used
        stub.activeDisplayIdentifier = "SomeOther"
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

        // When
        sut = AppState(displaySpaceProvider: stub, skipObservers: true, store: store)

        // Then
        XCTAssertEqual(sut.currentSpace, 2)
        XCTAssertEqual(sut.allSpaceLabels, ["1", "2"])
    }

    // MARK: - showAllSpaces Rendering Tests

    func testShowAllSpaces_iconWidthEqualsCountTimesStatusItemWidth() {
        // Given
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

        sut = AppState(displaySpaceProvider: stub, skipObservers: true, store: store)

        // When
        let icon = sut.statusBarIcon

        // Then
        let expectedWidth = Double(sut.allSpaceLabels.count) * Layout.statusItemWidth
        XCTAssertEqual(icon.size.width, expectedWidth, accuracy: 0.1)
    }

    func testShowAllSpaces_fiveSpaces_correctWidth() {
        // Given: 5 spaces
        stub.activeDisplayIdentifier = "Main"
        stub.displays = [
            CGSStub.makeDisplay(
                displayID: "Main",
                spaces: [
                    (id: 100, isFullscreen: false),
                    (id: 101, isFullscreen: false),
                    (id: 102, isFullscreen: false),
                    (id: 103, isFullscreen: false),
                    (id: 104, isFullscreen: false),
                ],
                activeSpaceID: 100
            ),
        ]
        store.showAllSpaces = true

        sut = AppState(displaySpaceProvider: stub, skipObservers: true, store: store)

        // When
        let icon = sut.statusBarIcon

        // Then
        let expectedWidth = 5.0 * Layout.statusItemWidth
        XCTAssertEqual(icon.size.width, expectedWidth, accuracy: 0.1)
    }

    func testShowAllSpaces_inactiveSpacesHaveReducedAlpha() {
        // Given: 3 spaces, space 2 is active
        store.showAllSpaces = true

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

        sut = AppState(displaySpaceProvider: stub, skipObservers: true, store: store)

        // When
        let icon = sut.statusBarIcon

        // Then: Sample alpha values from each segment
        guard let bitmap = icon.bitmapRepresentation() else {
            XCTFail("Could not create bitmap representation")
            return
        }

        // Account for Retina scaling: bitmap pixels may be 2x the point size
        let scale = Double(bitmap.pixelsWide) / icon.size.width
        let segmentWidth = Int(Layout.statusItemWidth * scale)
        let sampleY = bitmap.pixelsHigh / 2

        // Space 1 (inactive) - sample from center of first segment
        let inactiveX1 = segmentWidth / 2
        let alphaInactive1 = bitmap.sampleMaxAlpha(inRect: CGRect(
            x: inactiveX1 - 2,
            y: sampleY - 2,
            width: 4,
            height: 4
        ))

        // Space 2 (active) - sample from center of second segment
        let activeX = segmentWidth + segmentWidth / 2
        let alphaActive = bitmap.sampleMaxAlpha(inRect: CGRect(x: activeX - 2, y: sampleY - 2, width: 4, height: 4))

        // Space 3 (inactive) - sample from center of third segment
        let inactiveX3 = 2 * segmentWidth + segmentWidth / 2
        let alphaInactive3 = bitmap.sampleMaxAlpha(inRect: CGRect(
            x: inactiveX3 - 2,
            y: sampleY - 2,
            width: 4,
            height: 4
        ))

        // Active space should have higher alpha than inactive spaces
        XCTAssertGreaterThan(alphaActive, alphaInactive1, "Active space should have higher alpha than inactive space 1")
        XCTAssertGreaterThan(alphaActive, alphaInactive3, "Active space should have higher alpha than inactive space 3")

        // Inactive spaces should have similar (reduced) alpha
        XCTAssertEqual(alphaInactive1, alphaInactive3, accuracy: 0.1, "Inactive spaces should have similar alpha")
    }

    func testShowAllSpaces_activeVsInactiveAlphaRatio() {
        // Given: 2 spaces, space 1 is active
        store.showAllSpaces = true

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

        sut = AppState(displaySpaceProvider: stub, skipObservers: true, store: store)

        // When
        let icon = sut.statusBarIcon

        guard let bitmap = icon.bitmapRepresentation() else {
            XCTFail("Could not create bitmap representation")
            return
        }

        // Account for Retina scaling: bitmap pixels may be 2x the point size
        let scale = Double(bitmap.pixelsWide) / icon.size.width
        let segmentWidth = Int(Layout.statusItemWidth * scale)
        let sampleY = bitmap.pixelsHigh / 2

        // Space 1 (active)
        let activeX = segmentWidth / 2
        let alphaActive = bitmap.sampleMaxAlpha(inRect: CGRect(x: activeX - 3, y: sampleY - 3, width: 6, height: 6))

        // Space 2 (inactive)
        let inactiveX = segmentWidth + segmentWidth / 2
        let alphaInactive = bitmap.sampleMaxAlpha(inRect: CGRect(x: inactiveX - 3, y: sampleY - 3, width: 6, height: 6))

        // The inactive alpha should be roughly 0.35 of active (as per generateCombinedIcon)
        // Active alpha: 1.0, Inactive alpha: 0.35
        // So inactive should be significantly less than active
        if alphaActive > 0 {
            let ratio = alphaInactive / alphaActive
            XCTAssertLessThan(ratio, 0.5, "Inactive alpha should be less than 50% of active alpha")
            XCTAssertGreaterThan(ratio, 0.2, "Inactive alpha should be at least 20% of active alpha")
        }
    }

    func testShowAllSpaces_dimInactiveDisabled_allSpacesSameAlpha() {
        // Given: 2 spaces, space 1 is active, dimming disabled
        store.showAllSpaces = true
        store.dimInactiveSpaces = false

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

        sut = AppState(displaySpaceProvider: stub, skipObservers: true, store: store)

        // When
        let icon = sut.statusBarIcon

        guard let bitmap = icon.bitmapRepresentation() else {
            XCTFail("Could not create bitmap representation")
            return
        }

        // Account for Retina scaling: bitmap pixels may be 2x the point size
        let scale = Double(bitmap.pixelsWide) / icon.size.width
        let segmentWidth = Int(Layout.statusItemWidth * scale)
        let sampleY = bitmap.pixelsHigh / 2

        // Space 1 (active)
        let activeX = segmentWidth / 2
        let alphaActive = bitmap.sampleMaxAlpha(inRect: CGRect(x: activeX - 3, y: sampleY - 3, width: 6, height: 6))

        // Space 2 (inactive but dimming disabled)
        let inactiveX = segmentWidth + segmentWidth / 2
        let alphaInactive = bitmap.sampleMaxAlpha(inRect: CGRect(x: inactiveX - 3, y: sampleY - 3, width: 6, height: 6))

        // Both should have similar alpha when dimming is disabled
        XCTAssertEqual(
            alphaActive,
            alphaInactive,
            accuracy: 0.1,
            "Active and inactive spaces should have same alpha when dimming is disabled"
        )
    }

    func testShowAllSpaces_hideEmptySpaces_hidesEmptySpaces() {
        // Given: 3 spaces, space 2 is active, space 1 has windows, space 3 is empty
        store.showAllSpaces = true
        store.hideEmptySpaces = true

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
        // Space 100 has windows, space 101 is active, space 102 is empty
        stub.spacesWithWindowsSet = [100]

        sut = AppState(displaySpaceProvider: stub, skipObservers: true, store: store)

        // When
        let icon = sut.statusBarIcon

        // Then: Should only show 2 spaces (100 with windows, 101 active), not 102 (empty)
        // Width should be 2 * statusItemWidth instead of 3
        let expectedWidth = 2 * Layout.statusItemWidth
        XCTAssertEqual(
            icon.size.width,
            expectedWidth,
            accuracy: 0.1,
            "Icon should only show 2 spaces (one with windows, one active)"
        )
    }

    func testShowAllSpaces_hideEmptySpaces_alwaysShowsActiveSpace() {
        // Given: 2 spaces, space 2 is active but empty
        store.showAllSpaces = true
        store.hideEmptySpaces = true

        stub.activeDisplayIdentifier = "Main"
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
        // Only space 100 has windows, but 101 is active
        stub.spacesWithWindowsSet = [100]

        sut = AppState(displaySpaceProvider: stub, skipObservers: true, store: store)

        // When
        let icon = sut.statusBarIcon

        // Then: Should show both spaces (100 with windows, 101 active even though empty)
        let expectedWidth = 2 * Layout.statusItemWidth
        XCTAssertEqual(
            icon.size.width,
            expectedWidth,
            accuracy: 0.1,
            "Active space should always be shown even if empty"
        )
    }

    func testShowAllSpaces_hideEmptySpacesDisabled_showsAllSpaces() {
        // Given: 3 spaces, hideEmptySpaces is disabled
        store.showAllSpaces = true
        store.hideEmptySpaces = false

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
        // Only space 100 has windows
        stub.spacesWithWindowsSet = [100]

        sut = AppState(displaySpaceProvider: stub, skipObservers: true, store: store)

        // When
        let icon = sut.statusBarIcon

        // Then: Should show all 3 spaces since hideEmptySpaces is disabled
        let expectedWidth = 3 * Layout.statusItemWidth
        XCTAssertEqual(
            icon.size.width,
            expectedWidth,
            accuracy: 0.1,
            "All spaces should be shown when hideEmptySpaces is disabled"
        )
    }

    // MARK: - Dark Mode Tests

    func testUpdateDarkModeStatus_darkAppearance() {
        // Given
        stub.activeDisplayIdentifier = "Main"
        stub.displays = [
            CGSStub.makeDisplay(displayID: "Main", spaces: [(id: 100, isFullscreen: false)], activeSpaceID: 100),
        ]
        sut = AppState(displaySpaceProvider: stub, skipObservers: true, store: store)

        // When: Force dark appearance
        let previousAppearance = NSApp.appearance
        NSApp.appearance = NSAppearance(named: .darkAqua)
        sut.updateDarkModeStatus()

        // Then
        XCTAssertTrue(sut.darkModeEnabled, "darkModeEnabled should be true for dark appearance")

        // Cleanup
        NSApp.appearance = previousAppearance
    }

    // MARK: - Visible Icon Slots

    func testStatusBarLayout_showAllSpacesUsesLabelsAndOffsets() {
        sut = AppState(displaySpaceProvider: stub, skipObservers: true, store: store)
        sut.setSpaceState(
            labels: ["1", "2", "3"],
            currentSpace: 2,
            currentLabel: "2",
            displayID: "Main"
        )
        store.showAllSpaces = true

        let slots = sut.statusBarLayout().slots

        XCTAssertEqual(slots.map(\.targetSpace), [1, 2, 3])
        XCTAssertEqual(slots.map(\.startX), [0, Layout.statusItemWidth, Layout.statusItemWidth * 2])
    }

    func testStatusBarLayout_crossDisplayIncludesSeparatorAndSkipsFullscreenTargets() {
        sut = AppState(displaySpaceProvider: stub, skipObservers: true, store: store)
        let displayA = DisplaySpaceInfo(
            displayID: "DisplayA",
            labels: ["1", Labels.fullscreen],
            spaceIDs: [100, 101],
            globalStartIndex: 1
        )
        let displayB = DisplaySpaceInfo(
            displayID: "DisplayB",
            labels: ["1", "2"],
            spaceIDs: [200, 201],
            globalStartIndex: 3
        )

        sut.setSpaceState(
            labels: ["1", Labels.fullscreen],
            currentSpace: 1,
            currentLabel: "1",
            displayID: "DisplayA",
            spaceIDs: [100, 101],
            allDisplays: [displayA, displayB],
            globalSpaceIndex: 1
        )
        store.showAllDisplays = true

        let slots = sut.statusBarLayout().slots

        XCTAssertEqual(slots.map(\.targetSpace), [1, nil, 2, 3])
        XCTAssertEqual(
            slots.map(\.startX),
            [
                0,
                Layout.statusItemWidth,
                Layout.statusItemWidth * 2 + Layout.displaySeparatorWidth,
                Layout.statusItemWidth * 3 + Layout.displaySeparatorWidth,
            ]
        )
    }

    func testUpdateDarkModeStatus_lightAppearance() {
        // Given
        stub.activeDisplayIdentifier = "Main"
        stub.displays = [
            CGSStub.makeDisplay(displayID: "Main", spaces: [(id: 100, isFullscreen: false)], activeSpaceID: 100),
        ]
        sut = AppState(displaySpaceProvider: stub, skipObservers: true, store: store)

        // When: Force light appearance
        let previousAppearance = NSApp.appearance
        NSApp.appearance = NSAppearance(named: .aqua)
        sut.updateDarkModeStatus()

        // Then
        XCTAssertFalse(sut.darkModeEnabled, "darkModeEnabled should be false for light appearance")

        // Cleanup
        NSApp.appearance = previousAppearance
    }

    func testUpdateDarkModeStatus_flipsCorrectly() {
        // Given
        stub.activeDisplayIdentifier = "Main"
        stub.displays = [
            CGSStub.makeDisplay(displayID: "Main", spaces: [(id: 100, isFullscreen: false)], activeSpaceID: 100),
        ]
        sut = AppState(displaySpaceProvider: stub, skipObservers: true, store: store)
        let previousAppearance = NSApp.appearance

        // When/Then: Toggle dark -> light -> dark
        NSApp.appearance = NSAppearance(named: .darkAqua)
        sut.updateDarkModeStatus()
        XCTAssertTrue(sut.darkModeEnabled)

        NSApp.appearance = NSAppearance(named: .aqua)
        sut.updateDarkModeStatus()
        XCTAssertFalse(sut.darkModeEnabled)

        NSApp.appearance = NSAppearance(named: .darkAqua)
        sut.updateDarkModeStatus()
        XCTAssertTrue(sut.darkModeEnabled)

        // Cleanup
        NSApp.appearance = previousAppearance
    }
}

// MARK: - Bitmap Helpers

extension NSImage {
    fileprivate func bitmapRepresentation() -> NSBitmapImageRep? {
        guard let cgImage = cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return nil
        }
        return NSBitmapImageRep(cgImage: cgImage)
    }
}

extension NSBitmapImageRep {
    /// Samples the maximum alpha value within the given rect
    fileprivate func sampleMaxAlpha(inRect rect: CGRect) -> Double {
        var maxAlpha: Double = 0

        let startX = max(0, Int(rect.origin.x))
        let startY = max(0, Int(rect.origin.y))
        let endX = min(pixelsWide, Int(rect.origin.x + rect.size.width))
        let endY = min(pixelsHigh, Int(rect.origin.y + rect.size.height))

        for ptY in startY ..< endY {
            for ptX in startX ..< endX {
                if let color = colorAt(x: ptX, y: ptY) {
                    maxAlpha = max(maxAlpha, color.alphaComponent)
                }
            }
        }

        return maxAlpha
    }
}
