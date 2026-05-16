import AppKit
import Testing
@testable import WhichSpace

@MainActor
struct AppStateTests {
    private let stub: CGSStub
    private let store: DefaultsStore
    private let testSuite: TestSuite

    init() {
        testSuite = TestSuiteFactory.createSuite()
        store = DefaultsStore(suite: testSuite.suite)
        stub = CGSStub()
    }

    // MARK: - Space Detection Tests

    @Test("single display with three regular spaces: active index correct")
    func singleDisplayWithThreeRegularSpaces_activeIndexCorrect() {
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

        let sut = AppState(displaySpaceProvider: stub, skipObservers: true, store: store)

        #expect(sut.currentSpace == 2)
        #expect(sut.currentSpaceLabel == "2")
    }

    @Test("single display with three regular spaces: labels increment 1, 2, 3")
    func singleDisplayWithThreeRegularSpaces_labelsIncrementAsExpected() {
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

        let sut = AppState(displaySpaceProvider: stub, skipObservers: true, store: store)

        #expect(sut.allSpaceLabels == ["1", "2", "3"])
    }

    @Test("fullscreen space gets fullscreen label")
    func fullscreenSpaceLabeling() {
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

        let sut = AppState(displaySpaceProvider: stub, skipObservers: true, store: store)

        #expect(sut.allSpaceLabels == ["1", Labels.fullscreen, "2"])
        #expect(sut.currentSpaceLabel == Labels.fullscreen)
    }

    @Test("fullscreen space: numbering resumes afterward")
    func fullscreenSpace_numberingResumesAfterward() {
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

        let sut = AppState(displaySpaceProvider: stub, skipObservers: true, store: store)

        #expect(sut.allSpaceLabels == ["1", Labels.fullscreen, "2", Labels.fullscreen, "3"])
        #expect(sut.currentSpace == 5)
        #expect(sut.currentSpaceLabel == "3")
    }

    @Test("inactive display ignored")
    func inactiveDisplayIgnored() {
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

        let sut = AppState(displaySpaceProvider: stub, skipObservers: true, store: store)

        #expect(sut.allSpaceLabels == ["1", "2"])
        #expect(sut.currentSpace == 1)
    }

    @Test("falls back to Main display when active display not in list")
    func mainDisplayFallback() {
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

        let sut = AppState(displaySpaceProvider: stub, skipObservers: true, store: store)

        #expect(sut.currentSpace == 2)
        #expect(sut.allSpaceLabels == ["1", "2"])
    }

    // MARK: - showAllSpaces Rendering Tests

    @Test("showAllSpaces: icon width equals count times status item width")
    func showAllSpaces_iconWidthEqualsCountTimesStatusItemWidth() {
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

        let sut = AppState(displaySpaceProvider: stub, skipObservers: true, store: store)

        let icon = sut.statusBarIcon

        let expectedWidth = Double(sut.allSpaceLabels.count) * Layout.statusItemWidth
        #expect(abs(icon.size.width - expectedWidth) < 0.1)
    }

    @Test("showAllSpaces: five spaces produces correct width")
    func showAllSpaces_fiveSpaces_correctWidth() {
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

        let sut = AppState(displaySpaceProvider: stub, skipObservers: true, store: store)

        let icon = sut.statusBarIcon

        let expectedWidth = 5.0 * Layout.statusItemWidth
        #expect(abs(icon.size.width - expectedWidth) < 0.1)
    }

    @Test("showAllSpaces: inactive spaces have reduced alpha")
    func showAllSpaces_inactiveSpacesHaveReducedAlpha() throws {
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

        let sut = AppState(displaySpaceProvider: stub, skipObservers: true, store: store)

        let icon = sut.statusBarIcon

        let bitmap = try #require(icon.bitmapRepresentation())

        let scale = Double(bitmap.pixelsWide) / icon.size.width
        let segmentWidth = Int(Layout.statusItemWidth * scale)
        let sampleY = bitmap.pixelsHigh / 2

        let inactiveX1 = segmentWidth / 2
        let alphaInactive1 = bitmap.sampleMaxAlpha(inRect: CGRect(
            x: inactiveX1 - 2,
            y: sampleY - 2,
            width: 4,
            height: 4
        ))

        let activeX = segmentWidth + segmentWidth / 2
        let alphaActive = bitmap.sampleMaxAlpha(inRect: CGRect(x: activeX - 2, y: sampleY - 2, width: 4, height: 4))

        let inactiveX3 = 2 * segmentWidth + segmentWidth / 2
        let alphaInactive3 = bitmap.sampleMaxAlpha(inRect: CGRect(
            x: inactiveX3 - 2,
            y: sampleY - 2,
            width: 4,
            height: 4
        ))

        #expect(alphaActive > alphaInactive1)
        #expect(alphaActive > alphaInactive3)
        #expect(abs(alphaInactive1 - alphaInactive3) < 0.1)
    }

    @Test("showAllSpaces: active-to-inactive alpha ratio between 20% and 50%")
    func showAllSpaces_activeVsInactiveAlphaRatio() throws {
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

        let sut = AppState(displaySpaceProvider: stub, skipObservers: true, store: store)

        let icon = sut.statusBarIcon

        let bitmap = try #require(icon.bitmapRepresentation())

        let scale = Double(bitmap.pixelsWide) / icon.size.width
        let segmentWidth = Int(Layout.statusItemWidth * scale)
        let sampleY = bitmap.pixelsHigh / 2

        let activeX = segmentWidth / 2
        let alphaActive = bitmap.sampleMaxAlpha(inRect: CGRect(x: activeX - 3, y: sampleY - 3, width: 6, height: 6))

        let inactiveX = segmentWidth + segmentWidth / 2
        let alphaInactive = bitmap.sampleMaxAlpha(inRect: CGRect(x: inactiveX - 3, y: sampleY - 3, width: 6, height: 6))

        if alphaActive > 0 {
            let ratio = alphaInactive / alphaActive
            #expect(ratio < 0.5)
            #expect(ratio > 0.2)
        }
    }

    @Test("showAllSpaces with dimInactive disabled: all spaces equal alpha")
    func showAllSpaces_dimInactiveDisabled_allSpacesSameAlpha() throws {
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

        let sut = AppState(displaySpaceProvider: stub, skipObservers: true, store: store)

        let icon = sut.statusBarIcon

        let bitmap = try #require(icon.bitmapRepresentation())

        let scale = Double(bitmap.pixelsWide) / icon.size.width
        let segmentWidth = Int(Layout.statusItemWidth * scale)
        let sampleY = bitmap.pixelsHigh / 2

        let activeX = segmentWidth / 2
        let alphaActive = bitmap.sampleMaxAlpha(inRect: CGRect(x: activeX - 3, y: sampleY - 3, width: 6, height: 6))

        let inactiveX = segmentWidth + segmentWidth / 2
        let alphaInactive = bitmap.sampleMaxAlpha(inRect: CGRect(x: inactiveX - 3, y: sampleY - 3, width: 6, height: 6))

        #expect(abs(alphaActive - alphaInactive) < 0.1)
    }

    @Test("hideEmptySpaces hides empty spaces in the rendered icon")
    func showAllSpaces_hideEmptySpaces_hidesEmptySpaces() {
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
        stub.spacesWithWindowsSet = [100]

        let sut = AppState(displaySpaceProvider: stub, skipObservers: true, store: store)

        let icon = sut.statusBarIcon

        let expectedWidth = 2 * Layout.statusItemWidth
        #expect(abs(icon.size.width - expectedWidth) < 0.1)
    }

    @Test("hideEmptySpaces always shows active space even if empty")
    func showAllSpaces_hideEmptySpaces_alwaysShowsActiveSpace() {
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
        stub.spacesWithWindowsSet = [100]

        let sut = AppState(displaySpaceProvider: stub, skipObservers: true, store: store)

        let icon = sut.statusBarIcon

        let expectedWidth = 2 * Layout.statusItemWidth
        #expect(abs(icon.size.width - expectedWidth) < 0.1)
    }

    @Test("hideEmptySpaces disabled: shows all spaces")
    func showAllSpaces_hideEmptySpacesDisabled_showsAllSpaces() {
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
        stub.spacesWithWindowsSet = [100]

        let sut = AppState(displaySpaceProvider: stub, skipObservers: true, store: store)

        let icon = sut.statusBarIcon

        let expectedWidth = 3 * Layout.statusItemWidth
        #expect(abs(icon.size.width - expectedWidth) < 0.1)
    }

    // MARK: - Dark Mode Tests

    @Test("dark appearance enables darkModeEnabled")
    func updateDarkModeStatus_darkAppearance() {
        stub.activeDisplayIdentifier = "Main"
        stub.displays = [
            CGSStub.makeDisplay(displayID: "Main", spaces: [(id: 100, isFullscreen: false)], activeSpaceID: 100),
        ]
        let sut = AppState(displaySpaceProvider: stub, skipObservers: true, store: store)

        let previousAppearance = NSApp.appearance
        NSApp.appearance = NSAppearance(named: .darkAqua)
        sut.updateDarkModeStatus()

        #expect(sut.darkModeEnabled)

        NSApp.appearance = previousAppearance
    }

    // MARK: - Visible Icon Slots

    @Test("statusBarLayout showAllSpaces uses labels and offsets")
    func statusBarLayout_showAllSpacesUsesLabelsAndOffsets() {
        let sut = AppState(displaySpaceProvider: stub, skipObservers: true, store: store)
        sut.setSpaceState(
            labels: ["1", "2", "3"],
            currentSpace: 2,
            currentLabel: "2",
            displayID: "Main"
        )
        store.showAllSpaces = true

        let layout = sut.statusBarLayout()
        let slots = layout.slots

        #expect(slots.map(\.targetSpace) == [1, 2, 3])
        #expect(slots.map(\.startX) == [0, Layout.statusItemWidth, Layout.statusItemWidth * 2])
    }

    @Test("statusBarLayout showAllSpaces uses rendered widths for transparent icons")
    func statusBarLayout_showAllSpaces_usesRenderedWidthsForTransparentIcons() {
        let sut = AppState(displaySpaceProvider: stub, skipObservers: true, store: store)
        sut.setSpaceState(
            labels: ["1", "2", "3"],
            currentSpace: 2,
            currentLabel: "2",
            displayID: "Main"
        )
        store.showAllSpaces = true
        store.paddingScale = 0

        let transparentColors = SpaceColors(foreground: .white, background: .clear)
        for space in 1 ... 3 {
            SpacePreferences.setIconStyle(.transparent, forSpace: space, store: store)
            SpacePreferences.setColors(transparentColors, forSpace: space, store: store)
        }

        let layout = sut.statusBarLayout()
        let slots = layout.slots
        let expectedWidths: [Double] = ["1", "2", "3"].map {
            SpaceIconGenerator.generateIcon(
                for: $0,
                darkMode: sut.darkModeEnabled,
                customColors: transparentColors,
                style: .transparent,
                sizeScale: store.sizeScale,
                paddingScale: store.paddingScale
            ).size.width
        }
        let expectedStartX: [Double] = [0, expectedWidths[0], expectedWidths[0] + expectedWidths[1]]

        #expect(slots.count == expectedWidths.count)
        #expect(slots.map(\.width) == expectedWidths)
        #expect(slots.map(\.startX) == expectedStartX)
        #expect(layout.totalWidth < Layout.statusItemWidth * 3)
    }

    @Test("statusBarLayout cross-display includes separator and skips fullscreen targets")
    func statusBarLayout_crossDisplayIncludesSeparatorAndSkipsFullscreenTargets() {
        let sut = AppState(displaySpaceProvider: stub, skipObservers: true, store: store)
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

        #expect(slots.map(\.targetSpace) == [1, nil, 3, 4])
        #expect(slots.map(\.startX) == [
            0,
            Layout.statusItemWidth,
            Layout.statusItemWidth * 2 + Layout.displaySeparatorWidth,
            Layout.statusItemWidth * 3 + Layout.displaySeparatorWidth,
        ])
    }

    @Test("statusBarLayout showAllSpaces hideEmptySpaces uses actual space number")
    func statusBarLayout_showAllSpaces_hideEmptySpaces_usesActualSpaceNumber() {
        let sut = AppState(displaySpaceProvider: stub, skipObservers: true, store: store)
        sut.setSpaceState(
            labels: ["1", "2", "3", "4", "5"],
            currentSpace: 1,
            currentLabel: "1",
            displayID: "Main"
        )
        store.showAllSpaces = true
        store.hideEmptySpaces = true
        stub.spacesWithWindowsSet = [100, 104]

        let slots = sut.statusBarLayout().slots

        #expect(slots.map(\.targetSpace) == [1, 5])
    }

    @Test("statusBarLayout showAllDisplays hideEmptySpaces uses actual space number")
    func statusBarLayout_showAllDisplays_hideEmptySpaces_usesActualSpaceNumber() {
        let sut = AppState(displaySpaceProvider: stub, skipObservers: true, store: store)
        let display = DisplaySpaceInfo(
            displayID: "Main",
            labels: ["1", "2", "3", "4", "5"],
            spaceIDs: [100, 101, 102, 103, 104],
            globalStartIndex: 1
        )
        sut.setSpaceState(
            labels: ["1", "2", "3", "4", "5"],
            currentSpace: 1,
            currentLabel: "1",
            displayID: "Main",
            spaceIDs: [100, 101, 102, 103, 104],
            allDisplays: [display],
            globalSpaceIndex: 1
        )
        store.showAllDisplays = true
        store.hideEmptySpaces = true
        stub.spacesWithWindowsSet = [100, 104]

        let slots = sut.statusBarLayout().slots

        #expect(slots.map(\.targetSpace) == [1, 5])
    }

    @Test("light appearance sets darkModeEnabled false")
    func updateDarkModeStatus_lightAppearance() {
        stub.activeDisplayIdentifier = "Main"
        stub.displays = [
            CGSStub.makeDisplay(displayID: "Main", spaces: [(id: 100, isFullscreen: false)], activeSpaceID: 100),
        ]
        let sut = AppState(displaySpaceProvider: stub, skipObservers: true, store: store)

        let previousAppearance = NSApp.appearance
        NSApp.appearance = NSAppearance(named: .aqua)
        sut.updateDarkModeStatus()

        #expect(!sut.darkModeEnabled)

        NSApp.appearance = previousAppearance
    }

    @Test("dark mode toggles flip correctly")
    func updateDarkModeStatus_flipsCorrectly() {
        stub.activeDisplayIdentifier = "Main"
        stub.displays = [
            CGSStub.makeDisplay(displayID: "Main", spaces: [(id: 100, isFullscreen: false)], activeSpaceID: 100),
        ]
        let sut = AppState(displaySpaceProvider: stub, skipObservers: true, store: store)
        let previousAppearance = NSApp.appearance

        NSApp.appearance = NSAppearance(named: .darkAqua)
        sut.updateDarkModeStatus()
        #expect(sut.darkModeEnabled)

        NSApp.appearance = NSAppearance(named: .aqua)
        sut.updateDarkModeStatus()
        #expect(!sut.darkModeEnabled)

        NSApp.appearance = NSAppearance(named: .darkAqua)
        sut.updateDarkModeStatus()
        #expect(sut.darkModeEnabled)

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
