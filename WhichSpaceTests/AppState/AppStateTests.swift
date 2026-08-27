import AppKit
import Testing
@testable import WhichSpace

private final class NotificationRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var recordedCount = 0

    var count: Int {
        lock.lock()
        defer { lock.unlock() }
        return recordedCount
    }

    var hasNotifications: Bool {
        lock.lock()
        defer { lock.unlock() }
        return recordedCount != 0
    }

    func record() {
        lock.lock()
        recordedCount += 1
        lock.unlock()
    }
}

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

    @Test("transient snapshot without current space keeps prior state")
    func transientSnapshotWithoutCurrentSpace_keepsPriorState() {
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
        let appState = AppState(displaySpaceProvider: stub, skipObservers: true, store: store)
        #expect(appState.currentSpace == 2)

        // During display reconfiguration the reported current space can be
        // missing from the space list - the update should be dropped
        stub.displays = [
            CGSStub.makeDisplay(
                displayID: "Main",
                spaces: [
                    (id: 100, isFullscreen: false),
                    (id: 101, isFullscreen: false),
                ],
                activeSpaceID: 999
            ),
        ]
        appState.forceSpaceUpdate()

        #expect(appState.currentSpace == 2, "transient zero-space snapshot should not clobber state")
        #expect(appState.currentSpaceLabel == "2")
    }

    @Test("same-display Space changes post one focused notification")
    func sameDisplaySpaceChange_postsFocusedNotification() {
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
        let appState = AppState(displaySpaceProvider: stub, skipObservers: true, store: store)
        let recorder = NotificationRecorder()
        let observer = NotificationCenter.default.addObserver(
            forName: .currentDisplaySpaceDidChange,
            object: appState,
            queue: .main
        ) { _ in
            recorder.record()
        }
        defer { NotificationCenter.default.removeObserver(observer) }

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
        appState.forceSpaceUpdate()

        #expect(recorder.count == 1)
    }

    @Test("active display changes do not post Space notifications")
    func activeDisplayChange_doesNotPostSpaceNotification() {
        stub.activeDisplayIdentifier = "DisplayA"
        stub.displays = [
            CGSStub.makeDisplay(
                displayID: "DisplayA",
                spaces: [(id: 100, isFullscreen: false)],
                activeSpaceID: 100
            ),
            CGSStub.makeDisplay(
                displayID: "DisplayB",
                spaces: [(id: 200, isFullscreen: false)],
                activeSpaceID: 200
            ),
        ]
        let appState = AppState(displaySpaceProvider: stub, skipObservers: true, store: store)
        let recorder = NotificationRecorder()
        let observer = NotificationCenter.default.addObserver(
            forName: .currentDisplaySpaceDidChange,
            object: appState,
            queue: .main
        ) { _ in
            recorder.record()
        }
        defer { NotificationCenter.default.removeObserver(observer) }

        stub.activeDisplayIdentifier = "DisplayB"
        appState.forceSpaceUpdate()

        #expect(!recorder.hasNotifications)
    }

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

    // MARK: - Previous Space Tests

    /// Three regular Spaces on one display, with `activeSpaceID` the only
    /// thing the previous-Space tests vary between snapshots.
    private func mainDisplay(activeSpaceID: Int, spaceIDs: [Int] = [100, 101, 102]) -> [NSDictionary] {
        [
            CGSStub.makeDisplay(
                displayID: "Main",
                spaces: spaceIDs.map { (id: $0, isFullscreen: false) },
                activeSpaceID: activeSpaceID
            ),
        ]
    }

    @Test("no previous Space before the first Space change")
    func previousSpace_isNilBeforeFirstChange() {
        stub.activeDisplayIdentifier = "Main"
        stub.displays = mainDisplay(activeSpaceID: 100)

        let appState = AppState(displaySpaceProvider: stub, skipObservers: true, store: store)

        #expect(appState.previousSpaceNumber == nil)
    }

    @Test("previous Space is the one just left")
    func previousSpace_isTheSpaceJustLeft() {
        stub.activeDisplayIdentifier = "Main"
        stub.displays = mainDisplay(activeSpaceID: 100)
        let appState = AppState(displaySpaceProvider: stub, skipObservers: true, store: store)

        stub.displays = mainDisplay(activeSpaceID: 102)
        appState.forceSpaceUpdate()

        #expect(appState.currentSpace == 3)
        #expect(appState.previousSpaceNumber == 1)
    }

    @Test("previous Space tracks only the last hop, so switching there toggles")
    func previousSpace_tracksOnlyTheLastHop() {
        stub.activeDisplayIdentifier = "Main"
        stub.displays = mainDisplay(activeSpaceID: 100)
        let appState = AppState(displaySpaceProvider: stub, skipObservers: true, store: store)

        stub.displays = mainDisplay(activeSpaceID: 101)
        appState.forceSpaceUpdate()
        #expect(appState.previousSpaceNumber == 1)

        stub.displays = mainDisplay(activeSpaceID: 102)
        appState.forceSpaceUpdate()
        #expect(appState.previousSpaceNumber == 2)

        // Going back records the Space being left, which is what makes the
        // hotkey toggle between two Spaces rather than walk a history
        stub.displays = mainDisplay(activeSpaceID: 101)
        appState.forceSpaceUpdate()
        #expect(appState.previousSpaceNumber == 3)
    }

    @Test("a removed previous Space stops being offered")
    func previousSpace_isNilOnceRemoved() {
        stub.activeDisplayIdentifier = "Main"
        stub.displays = mainDisplay(activeSpaceID: 100)
        let appState = AppState(displaySpaceProvider: stub, skipObservers: true, store: store)

        stub.displays = mainDisplay(activeSpaceID: 101)
        appState.forceSpaceUpdate()
        #expect(appState.previousSpaceNumber == 1)

        stub.displays = mainDisplay(activeSpaceID: 101, spaceIDs: [101, 102])
        appState.forceSpaceUpdate()

        #expect(appState.previousSpaceNumber == nil)
    }

    @Test("moving between displays records neither display's history")
    func previousSpace_ignoresDisplayChanges() {
        stub.activeDisplayIdentifier = "Main"
        let both = { (mainActive: Int, externalActive: Int) in
            [
                CGSStub.makeDisplay(
                    displayID: "Main",
                    spaces: [(id: 100, isFullscreen: false), (id: 101, isFullscreen: false)],
                    activeSpaceID: mainActive
                ),
                CGSStub.makeDisplay(
                    displayID: "External",
                    spaces: [(id: 200, isFullscreen: false), (id: 201, isFullscreen: false)],
                    activeSpaceID: externalActive
                ),
            ]
        }
        stub.displays = both(100, 200)
        let appState = AppState(displaySpaceProvider: stub, skipObservers: true, store: store)

        stub.displays = both(101, 200)
        appState.forceSpaceUpdate()
        #expect(appState.previousSpaceNumber == 1, "Main should remember the Space it left")

        // The external display was never left mid-session, so arriving on it
        // is not a Space visit and it has nothing to go back to
        stub.activeDisplayIdentifier = "External"
        appState.forceSpaceUpdate()
        #expect(appState.currentDisplayID == "External")
        #expect(appState.previousSpaceNumber == nil)

        // Main's own history survived the trip
        stub.activeDisplayIdentifier = "Main"
        appState.forceSpaceUpdate()
        #expect(appState.previousSpaceNumber == 1)
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

    @Test("showAllDisplays: inactive Space uses configured opacity")
    func showAllDisplays_inactiveSpaceUsesConfiguredOpacity() throws {
        store.showAllDisplays = true
        store.inactiveSpaceOpacity = 65
        stub.activeDisplayIdentifier = "DisplayA"
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

        let sut = AppState(displaySpaceProvider: stub, skipObservers: true, store: store)
        let bitmap = try #require(sut.statusBarIcon.bitmapRepresentation())

        let scale = Double(bitmap.pixelsWide) / sut.statusBarIcon.size.width
        let segmentWidth = Int(Layout.statusItemWidth * scale)
        let separatorWidth = Int(Layout.displaySeparatorWidth * scale)
        let activeAlpha = bitmap.sampleMaxAlpha(inRect: CGRect(
            x: 0,
            y: 0,
            width: segmentWidth,
            height: bitmap.pixelsHigh
        ))
        let inactiveAlpha = bitmap.sampleMaxAlpha(inRect: CGRect(
            x: segmentWidth + separatorWidth,
            y: 0,
            width: segmentWidth,
            height: bitmap.pixelsHigh
        ))

        let ratio = inactiveAlpha / activeAlpha
        #expect(ratio > 0.55)
        #expect(ratio < 0.75)
    }

    @Test("combined mode: only the current Space is undimmed across displays")
    func combinedMode_onlyCurrentSpaceIsUndimmedAcrossDisplays() throws {
        store.showAllDisplays = true
        store.showAllSpaces = true
        store.inactiveSpaceOpacity = Layout.defaultInactiveSpaceOpacity
        stub.activeDisplayIdentifier = "DisplayA"
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

        let sut = AppState(displaySpaceProvider: stub, skipObservers: true, store: store)
        let icon = sut.statusBarIcon
        let bitmap = try #require(icon.bitmapRepresentation())

        let scale = Double(bitmap.pixelsWide) / icon.size.width
        let segmentWidth = Int(Layout.statusItemWidth * scale)
        let separatorWidth = Int(Layout.displaySeparatorWidth * scale)
        let segmentStarts = [0, segmentWidth, 2 * segmentWidth + separatorWidth, 3 * segmentWidth + separatorWidth]
        let alphas = segmentStarts.map { startX in
            bitmap.sampleMaxAlpha(inRect: CGRect(
                x: startX,
                y: 0,
                width: segmentWidth,
                height: bitmap.pixelsHigh
            ))
        }

        for inactiveAlpha in alphas.dropFirst() {
            #expect(alphas[0] > inactiveAlpha)
            #expect(inactiveAlpha / alphas[0] < 0.5)
        }
    }

    @Test("showAllSpaces with 100% inactive opacity: all spaces equal alpha")
    func showAllSpaces_fullInactiveOpacity_allSpacesSameAlpha() throws {
        store.showAllSpaces = true
        store.inactiveSpaceOpacity = 100

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

    @Test("statusBarLayout combined mode includes all Spaces on every display")
    func statusBarLayout_combinedModeIncludesAllSpacesOnEveryDisplay() {
        let sut = AppState(displaySpaceProvider: stub, skipObservers: true, store: store)
        let displayA = DisplaySpaceInfo(
            displayID: "DisplayA",
            labels: ["1", Labels.fullscreen],
            spaceIDs: [100, 101],
            activeSpaceID: 100,
            globalStartIndex: 1
        )
        let displayB = DisplaySpaceInfo(
            displayID: "DisplayB",
            labels: ["1", "2"],
            spaceIDs: [200, 201],
            activeSpaceID: 201,
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
        store.showAllSpaces = true

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
            currentSpace: 5,
            currentLabel: "5",
            displayID: "Main",
            spaceIDs: [100, 101, 102, 103, 104],
            allDisplays: [display],
            globalSpaceIndex: 5
        )
        store.showAllDisplays = true
        store.hideEmptySpaces = true
        stub.spacesWithWindowsSet = [100, 104]

        let slots = sut.statusBarLayout().slots

        #expect(slots.map(\.targetSpace) == [5])
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

    // MARK: - Display Order Gating

    @Test("physical display order is suspended while other displays are hidden")
    func displayOrder_suspendedWithoutShowAllDisplays() {
        stub.activeDisplayIdentifier = "DisplayB"
        stub.displays = [
            CGSStub.makeDisplay(
                displayID: "DisplayB",
                spaces: [(id: 200, isFullscreen: false), (id: 201, isFullscreen: false)],
                activeSpaceID: 200
            ),
            CGSStub.makeDisplay(
                displayID: "DisplayA",
                spaces: [(id: 100, isFullscreen: false), (id: 101, isFullscreen: false)],
                activeSpaceID: 100
            ),
        ]
        stub.displayBoundsMap = [
            "DisplayA": CGRect(x: 0, y: 0, width: 1728, height: 1117),
            "DisplayB": CGRect(x: 1728, y: 0, width: 2560, height: 1440),
        ]
        store.displayOrder = .physical
        store.showAllDisplays = false
        let appState = AppState(displaySpaceProvider: stub, skipObservers: true, store: store)

        // The greyed-out order setting keeps its stored value but stops
        // affecting numbering while only the active display is shown
        #expect(appState.allDisplaysSpaceInfo.map(\.displayID) == ["DisplayB", "DisplayA"])
        #expect(appState.currentGlobalSpaceIndex == 1)

        store.showAllDisplays = true
        appState.forceSpaceUpdate()

        #expect(appState.allDisplaysSpaceInfo.map(\.displayID) == ["DisplayA", "DisplayB"])
        #expect(appState.currentGlobalSpaceIndex == 3)
    }

    // MARK: - Space Order Reconciliation

    /// Builds a "Main" display whose Space IDs stay glued to their UUIDs, so
    /// a reordered call reproduces what CGS reports after a Mission Control
    /// drag: same Spaces, new positions.
    private func makeMainDisplay(uuids: [String], activeSpaceID: Int = 100) -> NSDictionary {
        let ids = ["A": 100, "B": 101, "C": 102, "D": 103]
        return CGSStub.makeDisplay(
            displayID: "Main",
            uuidSpaces: uuids.map { uuid in
                (id: ids[uuid] ?? 199, uuid: uuid, isFullscreen: false)
            },
            activeSpaceID: activeSpaceID
        )
    }

    @Test("Mission Control reorder moves preferences with their Spaces")
    func spaceReorder_movesPreferencesWithSpaces() {
        stub.activeDisplayIdentifier = "Main"
        stub.displays = [makeMainDisplay(uuids: ["A", "B", "C"])]
        let appState = AppState(displaySpaceProvider: stub, skipObservers: true, store: store)
        SpacePreferences.setLabel("Work", forSpace: 2, store: store)
        SpacePreferences.setSymbol("star", forSpace: 2, store: store)

        // Space B moves from position 2 to position 3
        stub.displays = [makeMainDisplay(uuids: ["A", "C", "B"])]
        appState.forceSpaceUpdate()

        #expect(SpacePreferences.label(forSpace: 3, store: store) == "Work")
        #expect(SpacePreferences.symbol(forSpace: 3, store: store) == "star")
        #expect(SpacePreferences.label(forSpace: 2, store: store) == nil)
    }

    @Test("a confirmed middle insertion moves later preferences with their Spaces")
    func spaceInsertedInMiddle_movesLaterPreferences() {
        stub.activeDisplayIdentifier = "Main"
        stub.displays = [makeMainDisplay(uuids: ["A", "B"])]
        let appState = AppState(displaySpaceProvider: stub, skipObservers: true, store: store)
        SpacePreferences.setLabel("Work", forSpace: 2, store: store)

        // A new Space lands between the existing two - not a permutation,
        // so the first observation only records a candidate
        stub.displays = [makeMainDisplay(uuids: ["A", "C", "B"])]
        appState.forceSpaceUpdate()

        #expect(SpacePreferences.label(forSpace: 2, store: store) == "Work")

        // The second observation confirms the insertion: B's profile
        // follows it to position 3 and the new Space starts unstyled
        appState.forceSpaceUpdate()

        #expect(store.spaceOrders["Main"] == ["A", "C", "B"])
        #expect(SpacePreferences.label(forSpace: 3, store: store) == "Work")
        #expect(SpacePreferences.label(forSpace: 2, store: store) == nil)

        // The confirmed order is the new baseline: a later reorder remaps
        stub.displays = [makeMainDisplay(uuids: ["A", "B", "C"])]
        appState.forceSpaceUpdate()

        #expect(SpacePreferences.label(forSpace: 2, store: store) == "Work")
        #expect(SpacePreferences.label(forSpace: 3, store: store) == nil)
    }

    @Test("a confirmed head insertion shifts every preference up")
    func spaceInsertedAtHead_shiftsPreferences() {
        stub.activeDisplayIdentifier = "Main"
        stub.displays = [makeMainDisplay(uuids: ["B", "C"], activeSpaceID: 101)]
        let appState = AppState(displaySpaceProvider: stub, skipObservers: true, store: store)
        SpacePreferences.setLabel("One", forSpace: 1, store: store)
        SpacePreferences.setLabel("Two", forSpace: 2, store: store)

        stub.displays = [makeMainDisplay(uuids: ["A", "B", "C"], activeSpaceID: 101)]
        appState.forceSpaceUpdate()
        appState.forceSpaceUpdate()

        #expect(SpacePreferences.label(forSpace: 1, store: store) == nil)
        #expect(SpacePreferences.label(forSpace: 2, store: store) == "One")
        #expect(SpacePreferences.label(forSpace: 3, store: store) == "Two")
    }

    @Test("an appended Space starts unstyled and moves nothing")
    func spaceAppendedAtTail_leavesPreferencesInPlace() {
        stub.activeDisplayIdentifier = "Main"
        stub.displays = [makeMainDisplay(uuids: ["A", "B"])]
        let appState = AppState(displaySpaceProvider: stub, skipObservers: true, store: store)
        SpacePreferences.setLabel("One", forSpace: 1, store: store)
        SpacePreferences.setLabel("Two", forSpace: 2, store: store)

        stub.displays = [makeMainDisplay(uuids: ["A", "B", "C"])]
        appState.forceSpaceUpdate()
        appState.forceSpaceUpdate()

        #expect(store.spaceOrders["Main"] == ["A", "B", "C"])
        #expect(SpacePreferences.label(forSpace: 1, store: store) == "One")
        #expect(SpacePreferences.label(forSpace: 2, store: store) == "Two")
        #expect(SpacePreferences.label(forSpace: 3, store: store) == nil)
    }

    @Test("a confirmed middle deletion compacts later preferences")
    func spaceDeletedInMiddle_compactsPreferences() {
        stub.activeDisplayIdentifier = "Main"
        stub.displays = [makeMainDisplay(uuids: ["A", "B", "C"])]
        let appState = AppState(displaySpaceProvider: stub, skipObservers: true, store: store)
        SpacePreferences.setLabel("One", forSpace: 1, store: store)
        SpacePreferences.setLabel("Two", forSpace: 2, store: store)
        SpacePreferences.setLabel("Three", forSpace: 3, store: store)

        stub.displays = [makeMainDisplay(uuids: ["A", "C"])]
        appState.forceSpaceUpdate()

        // The first observation is only a candidate and moves nothing
        #expect(SpacePreferences.label(forSpace: 3, store: store) == "Three")

        appState.forceSpaceUpdate()

        #expect(store.spaceOrders["Main"] == ["A", "C"])
        #expect(SpacePreferences.label(forSpace: 1, store: store) == "One")
        #expect(SpacePreferences.label(forSpace: 2, store: store) == "Three")
        #expect(SpacePreferences.label(forSpace: 3, store: store) == nil)
    }

    @Test("a confirmed head deletion compacts every preference")
    func spaceDeletedAtHead_compactsPreferences() {
        stub.activeDisplayIdentifier = "Main"
        stub.displays = [makeMainDisplay(uuids: ["A", "B", "C"], activeSpaceID: 101)]
        let appState = AppState(displaySpaceProvider: stub, skipObservers: true, store: store)
        SpacePreferences.setLabel("One", forSpace: 1, store: store)
        SpacePreferences.setLabel("Two", forSpace: 2, store: store)
        SpacePreferences.setLabel("Three", forSpace: 3, store: store)

        stub.displays = [makeMainDisplay(uuids: ["B", "C"], activeSpaceID: 101)]
        appState.forceSpaceUpdate()
        appState.forceSpaceUpdate()

        #expect(SpacePreferences.label(forSpace: 1, store: store) == "Two")
        #expect(SpacePreferences.label(forSpace: 2, store: store) == "Three")
        #expect(SpacePreferences.label(forSpace: 3, store: store) == nil)
    }

    @Test("a confirmed tail deletion clears the vacated position")
    func spaceDeletedAtTail_clearsVacatedPosition() {
        stub.activeDisplayIdentifier = "Main"
        stub.displays = [makeMainDisplay(uuids: ["A", "B", "C"])]
        let appState = AppState(displaySpaceProvider: stub, skipObservers: true, store: store)
        SpacePreferences.setLabel("One", forSpace: 1, store: store)
        SpacePreferences.setLabel("Two", forSpace: 2, store: store)
        SpacePreferences.setLabel("Three", forSpace: 3, store: store)

        stub.displays = [makeMainDisplay(uuids: ["A", "B"])]
        appState.forceSpaceUpdate()
        appState.forceSpaceUpdate()

        #expect(SpacePreferences.label(forSpace: 1, store: store) == "One")
        #expect(SpacePreferences.label(forSpace: 2, store: store) == "Two")
        #expect(SpacePreferences.label(forSpace: 3, store: store) == nil)
    }

    @Test("profiles stored past the live Space count shift with the change")
    func profilesPastLiveCount_shiftBothWays() {
        stub.activeDisplayIdentifier = "Main"
        stub.displays = [makeMainDisplay(uuids: ["A", "B"])]
        let appState = AppState(displaySpaceProvider: stub, skipObservers: true, store: store)
        SpacePreferences.setLabel("One", forSpace: 1, store: store)
        SpacePreferences.setLabel("Two", forSpace: 2, store: store)
        // Spaces configured before they exist
        SpacePreferences.setLabel("Future", forSpace: 3, store: store)
        SpacePreferences.setLabel("Later", forSpace: 4, store: store)

        // An appended Space displaces the preconfigured positions rather
        // than adopting or overwriting their values
        stub.displays = [makeMainDisplay(uuids: ["A", "B", "C"])]
        appState.forceSpaceUpdate()
        appState.forceSpaceUpdate()

        #expect(SpacePreferences.label(forSpace: 3, store: store) == nil)
        #expect(SpacePreferences.label(forSpace: 4, store: store) == "Future")
        #expect(SpacePreferences.label(forSpace: 5, store: store) == "Later")

        // Deleting it shifts them back down
        stub.displays = [makeMainDisplay(uuids: ["A", "B"])]
        appState.forceSpaceUpdate()
        appState.forceSpaceUpdate()

        #expect(SpacePreferences.label(forSpace: 3, store: store) == "Future")
        #expect(SpacePreferences.label(forSpace: 4, store: store) == "Later")
        #expect(SpacePreferences.label(forSpace: 5, store: store) == nil)
    }

    @Test("a fullscreen Space insertion shifts fullscreen-inclusive positions")
    func fullscreenInsertion_shiftsPositions() {
        stub.activeDisplayIdentifier = "Main"
        stub.displays = [
            CGSStub.makeDisplay(
                displayID: "Main",
                uuidSpaces: [(id: 100, uuid: "A", isFullscreen: false), (id: 101, uuid: "B", isFullscreen: false)],
                activeSpaceID: 100
            ),
        ]
        let appState = AppState(displaySpaceProvider: stub, skipObservers: true, store: store)
        SpacePreferences.setLabel("One", forSpace: 1, store: store)
        SpacePreferences.setLabel("Two", forSpace: 2, store: store)

        // An app entering fullscreen creates a Space between the desktops
        stub.displays = [
            CGSStub.makeDisplay(
                displayID: "Main",
                uuidSpaces: [
                    (id: 100, uuid: "A", isFullscreen: false),
                    (id: 150, uuid: "F", isFullscreen: true),
                    (id: 101, uuid: "B", isFullscreen: false),
                ],
                activeSpaceID: 100
            ),
        ]
        appState.forceSpaceUpdate()
        appState.forceSpaceUpdate()

        #expect(SpacePreferences.label(forSpace: 1, store: store) == "One")
        #expect(SpacePreferences.label(forSpace: 2, store: store) == nil)
        #expect(SpacePreferences.label(forSpace: 3, store: store) == "Two")
    }

    @Test("a deletion on one display moves only that display's overrides")
    func multiDisplayDeletion_keepsSharedAndOtherDisplays() {
        stub.activeDisplayIdentifier = "DisplayA"
        let displayA = CGSStub.makeDisplay(
            displayID: "DisplayA",
            uuidSpaces: [(id: 100, uuid: "A", isFullscreen: false), (id: 101, uuid: "B", isFullscreen: false)],
            activeSpaceID: 100
        )
        stub.displays = [
            displayA,
            CGSStub.makeDisplay(
                displayID: "DisplayB",
                uuidSpaces: [(id: 200, uuid: "C", isFullscreen: false), (id: 201, uuid: "D", isFullscreen: false)],
                activeSpaceID: 200
            ),
        ]
        let appState = AppState(displaySpaceProvider: stub, skipObservers: true, store: store)
        SpacePreferences.setLabel("Shared", forSpace: 2, store: store)
        SpacePreferences.setLabel("Override", forSpace: 2, display: "DisplayB", store: store)
        SpacePreferences.setLabel("KeepA", forSpace: 2, display: "DisplayA", store: store)

        // DisplayB loses its first Space; DisplayA is untouched
        stub.displays = [
            displayA,
            CGSStub.makeDisplay(
                displayID: "DisplayB",
                uuidSpaces: [(id: 201, uuid: "D", isFullscreen: false)],
                activeSpaceID: 201
            ),
        ]
        appState.forceSpaceUpdate()
        appState.forceSpaceUpdate()

        #expect(store.spaceLabels == [2: "Shared"])
        #expect(store.displaySpaceLabels["DisplayB"] == [1: "Override"])
        #expect(store.displaySpaceLabels["DisplayA"] == [2: "KeepA"])
    }

    @Test("a display disappearing alongside a deletion moves nothing")
    func displayRemovedWithDeletion_movesNothing() {
        stub.activeDisplayIdentifier = "DisplayA"
        stub.displays = [
            CGSStub.makeDisplay(
                displayID: "DisplayA",
                uuidSpaces: [(id: 100, uuid: "A", isFullscreen: false), (id: 101, uuid: "B", isFullscreen: false)],
                activeSpaceID: 100
            ),
            CGSStub.makeDisplay(
                displayID: "DisplayB",
                uuidSpaces: [(id: 200, uuid: "C", isFullscreen: false)],
                activeSpaceID: 200
            ),
        ]
        let appState = AppState(displaySpaceProvider: stub, skipObservers: true, store: store)
        SpacePreferences.setLabel("KeepA", forSpace: 2, display: "DisplayA", store: store)

        stub.displays = [
            CGSStub.makeDisplay(
                displayID: "DisplayA",
                uuidSpaces: [(id: 100, uuid: "A", isFullscreen: false)],
                activeSpaceID: 100
            ),
        ]
        appState.forceSpaceUpdate()
        appState.forceSpaceUpdate()

        #expect(store.spaceOrders == ["DisplayA": ["A"]])
        #expect(store.displaySpaceLabels["DisplayA"] == [2: "KeepA"])
    }

    @Test("a simultaneous add and remove moves nothing")
    func simultaneousAddAndRemove_movesNothing() {
        stub.activeDisplayIdentifier = "Main"
        stub.displays = [makeMainDisplay(uuids: ["A", "B", "C"])]
        let appState = AppState(displaySpaceProvider: stub, skipObservers: true, store: store)
        SpacePreferences.setLabel("One", forSpace: 1, store: store)
        SpacePreferences.setLabel("Two", forSpace: 2, store: store)
        SpacePreferences.setLabel("Three", forSpace: 3, store: store)

        stub.displays = [makeMainDisplay(uuids: ["A", "D", "C"])]
        appState.forceSpaceUpdate()
        appState.forceSpaceUpdate()

        #expect(store.spaceOrders["Main"] == ["A", "D", "C"])
        #expect(store.spaceLabels == [1: "One", 2: "Two", 3: "Three"])
    }

    @Test("a noncontiguous deletion compacts across the gaps")
    func noncontiguousDeletion_compactsAcrossGaps() {
        stub.activeDisplayIdentifier = "Main"
        stub.displays = [makeMainDisplay(uuids: ["A", "B", "C", "D"])]
        let appState = AppState(displaySpaceProvider: stub, skipObservers: true, store: store)
        SpacePreferences.setLabel("One", forSpace: 1, store: store)
        SpacePreferences.setLabel("Two", forSpace: 2, store: store)
        SpacePreferences.setLabel("Three", forSpace: 3, store: store)
        SpacePreferences.setLabel("Four", forSpace: 4, store: store)

        // B and D vanish in the same confirmed change
        stub.displays = [makeMainDisplay(uuids: ["A", "C"])]
        appState.forceSpaceUpdate()
        appState.forceSpaceUpdate()

        #expect(store.spaceLabels == [1: "One", 2: "Three"])
    }

    @Test("a noncontiguous insertion shifts around the gaps")
    func noncontiguousInsertion_shiftsAroundGaps() {
        stub.activeDisplayIdentifier = "Main"
        stub.displays = [makeMainDisplay(uuids: ["A", "C"])]
        let appState = AppState(displaySpaceProvider: stub, skipObservers: true, store: store)
        SpacePreferences.setLabel("One", forSpace: 1, store: store)
        SpacePreferences.setLabel("Two", forSpace: 2, store: store)

        // B lands between the survivors and D after them, together
        stub.displays = [makeMainDisplay(uuids: ["A", "B", "C", "D"])]
        appState.forceSpaceUpdate()
        appState.forceSpaceUpdate()

        #expect(store.spaceLabels == [1: "One", 3: "Two"])
    }

    @Test("simultaneous deletions on two displays both remap")
    func simultaneousDeletionsOnTwoDisplays_bothRemap() {
        stub.activeDisplayIdentifier = "DisplayA"
        stub.displays = [
            CGSStub.makeDisplay(
                displayID: "DisplayA",
                uuidSpaces: [(id: 100, uuid: "A", isFullscreen: false), (id: 101, uuid: "B", isFullscreen: false)],
                activeSpaceID: 100
            ),
            CGSStub.makeDisplay(
                displayID: "DisplayB",
                uuidSpaces: [(id: 200, uuid: "C", isFullscreen: false), (id: 201, uuid: "D", isFullscreen: false)],
                activeSpaceID: 200
            ),
        ]
        let appState = AppState(displaySpaceProvider: stub, skipObservers: true, store: store)
        SpacePreferences.setLabel("Shared", forSpace: 2, store: store)
        SpacePreferences.setLabel("GoneA", forSpace: 2, display: "DisplayA", store: store)
        SpacePreferences.setLabel("OverB", forSpace: 2, display: "DisplayB", store: store)

        // DisplayA loses its second Space and DisplayB its first, in the
        // same confirmed change
        stub.displays = [
            CGSStub.makeDisplay(
                displayID: "DisplayA",
                uuidSpaces: [(id: 100, uuid: "A", isFullscreen: false)],
                activeSpaceID: 100
            ),
            CGSStub.makeDisplay(
                displayID: "DisplayB",
                uuidSpaces: [(id: 201, uuid: "D", isFullscreen: false)],
                activeSpaceID: 201
            ),
        ]
        appState.forceSpaceUpdate()
        appState.forceSpaceUpdate()

        #expect(store.spaceLabels == [2: "Shared"])
        #expect(store.displaySpaceLabels["DisplayA"]?.isEmpty == true)
        #expect(store.displaySpaceLabels["DisplayB"] == [1: "OverB"])
    }

    @Test("opposite-direction changes across displays move nothing")
    func oppositeDirectionChangesAcrossDisplays_moveNothing() {
        stub.activeDisplayIdentifier = "DisplayA"
        stub.displays = [
            CGSStub.makeDisplay(
                displayID: "DisplayA",
                uuidSpaces: [(id: 100, uuid: "A", isFullscreen: false), (id: 101, uuid: "B", isFullscreen: false)],
                activeSpaceID: 100
            ),
            CGSStub.makeDisplay(
                displayID: "DisplayB",
                uuidSpaces: [(id: 200, uuid: "C", isFullscreen: false), (id: 201, uuid: "D", isFullscreen: false)],
                activeSpaceID: 200
            ),
        ]
        let appState = AppState(displaySpaceProvider: stub, skipObservers: true, store: store)
        SpacePreferences.setLabel("OvA", forSpace: 2, display: "DisplayA", store: store)
        SpacePreferences.setLabel("OvB", forSpace: 2, display: "DisplayB", store: store)

        // DisplayA gains a Space while DisplayB loses one - neither a pure
        // insertion nor a pure deletion, so nothing may move
        stub.displays = [
            CGSStub.makeDisplay(
                displayID: "DisplayA",
                uuidSpaces: [
                    (id: 100, uuid: "A", isFullscreen: false),
                    (id: 101, uuid: "B", isFullscreen: false),
                    (id: 102, uuid: "E", isFullscreen: false),
                ],
                activeSpaceID: 100
            ),
            CGSStub.makeDisplay(
                displayID: "DisplayB",
                uuidSpaces: [(id: 200, uuid: "C", isFullscreen: false)],
                activeSpaceID: 200
            ),
        ]
        appState.forceSpaceUpdate()
        appState.forceSpaceUpdate()

        #expect(store.spaceOrders == ["DisplayA": ["A", "B", "E"], "DisplayB": ["C"]])
        #expect(store.displaySpaceLabels["DisplayA"] == [2: "OvA"])
        #expect(store.displaySpaceLabels["DisplayB"] == [2: "OvB"])
    }

    @Test("an insertion combined with a reorder moves nothing")
    func insertionCombinedWithReorder_movesNothing() {
        stub.activeDisplayIdentifier = "Main"
        stub.displays = [makeMainDisplay(uuids: ["A", "B"])]
        let appState = AppState(displaySpaceProvider: stub, skipObservers: true, store: store)
        SpacePreferences.setLabel("One", forSpace: 1, store: store)
        SpacePreferences.setLabel("Two", forSpace: 2, store: store)

        stub.displays = [makeMainDisplay(uuids: ["B", "C", "A"])]
        appState.forceSpaceUpdate()
        appState.forceSpaceUpdate()

        #expect(store.spaceOrders["Main"] == ["B", "C", "A"])
        #expect(store.spaceLabels == [1: "One", 2: "Two"])
    }

    @Test("multi-display reorder remaps overrides but not shared positions")
    func multiDisplayReorder_remapsOverridesOnly() {
        stub.activeDisplayIdentifier = "DisplayA"
        stub.displays = [
            CGSStub.makeDisplay(
                displayID: "DisplayA",
                uuidSpaces: [(id: 100, uuid: "A", isFullscreen: false), (id: 101, uuid: "B", isFullscreen: false)],
                activeSpaceID: 100
            ),
            CGSStub.makeDisplay(
                displayID: "DisplayB",
                uuidSpaces: [(id: 200, uuid: "C", isFullscreen: false), (id: 201, uuid: "D", isFullscreen: false)],
                activeSpaceID: 200
            ),
        ]
        let appState = AppState(displaySpaceProvider: stub, skipObservers: true, store: store)
        SpacePreferences.setLabel("Shared", forSpace: 1, store: store)
        SpacePreferences.setLabel("Override", forSpace: 1, display: "DisplayB", store: store)

        // DisplayB's Spaces swap; DisplayA is untouched
        stub.displays = [
            stub.displays[0],
            CGSStub.makeDisplay(
                displayID: "DisplayB",
                uuidSpaces: [(id: 201, uuid: "D", isFullscreen: false), (id: 200, uuid: "C", isFullscreen: false)],
                activeSpaceID: 200
            ),
        ]
        appState.forceSpaceUpdate()

        #expect(store.spaceLabels == [1: "Shared"])
        #expect(store.displaySpaceLabels["DisplayB"] == [2: "Override"])
    }

    @Test("spaces without UUIDs are not order-tracked")
    func missingUUIDs_skipOrderTracking() {
        stub.activeDisplayIdentifier = "Main"
        stub.displays = [
            CGSStub.makeDisplay(
                displayID: "Main",
                spaces: [(id: 100, isFullscreen: false), (id: 101, isFullscreen: false)],
                activeSpaceID: 100
            ),
        ]
        let appState = AppState(displaySpaceProvider: stub, skipObservers: true, store: store)
        SpacePreferences.setLabel("Work", forSpace: 2, store: store)

        stub.displays = [
            CGSStub.makeDisplay(
                displayID: "Main",
                spaces: [(id: 101, isFullscreen: false), (id: 100, isFullscreen: false)],
                activeSpaceID: 100
            ),
        ]
        appState.forceSpaceUpdate()

        #expect(store.spaceOrders.isEmpty)
        #expect(SpacePreferences.label(forSpace: 2, store: store) == "Work")
    }

    @Test("a transient partial snapshot cannot poison the order baseline")
    func transientPartialSnapshot_keepsBaselineAndRemapsWhenSettled() {
        stub.activeDisplayIdentifier = "Main"
        stub.displays = [makeMainDisplay(uuids: ["A", "B", "C"])]
        let appState = AppState(displaySpaceProvider: stub, skipObservers: true, store: store)
        SpacePreferences.setLabel("Work", forSpace: 2, store: store)

        // A racy CGS read drops Space B but still reports a current Space
        stub.displays = [makeMainDisplay(uuids: ["A", "C"])]
        appState.forceSpaceUpdate()

        #expect(store.spaceOrders["Main"] == ["A", "B", "C"])

        // The settled read shows the real state: a reorder of the same set,
        // which must still be recognized against the unpoisoned baseline
        stub.displays = [makeMainDisplay(uuids: ["A", "C", "B"])]
        appState.forceSpaceUpdate()

        #expect(SpacePreferences.label(forSpace: 3, store: store) == "Work")
        #expect(SpacePreferences.label(forSpace: 2, store: store) == nil)
        #expect(store.spaceOrders["Main"] == ["A", "C", "B"])
    }

    @Test("a transient observed twice is adopted as a deletion and compacts profiles")
    func transientObservedTwice_adoptsAsDeletionAndCompacts() {
        stub.activeDisplayIdentifier = "Main"
        stub.displays = [makeMainDisplay(uuids: ["A", "B", "C"])]
        let appState = AppState(displaySpaceProvider: stub, skipObservers: true, store: store)
        SpacePreferences.setLabel("Work", forSpace: 2, store: store)
        SpacePreferences.setLabel("Play", forSpace: 3, store: store)

        // The documented residual of the double-observation heuristic: a
        // partial read that survives two consecutive snapshots is
        // indistinguishable from a real Space removal, so it becomes the
        // baseline and compacts profiles - the dropped Space's value is
        // cleared and later values shift down
        stub.displays = [makeMainDisplay(uuids: ["A", "C"])]
        appState.forceSpaceUpdate()
        appState.forceSpaceUpdate()

        #expect(store.spaceOrders["Main"] == ["A", "C"])
        #expect(SpacePreferences.label(forSpace: 2, store: store) == "Play")
        #expect(SpacePreferences.label(forSpace: 3, store: store) == nil)

        // The dropped Space reappearing reads as an insertion: surviving
        // profiles move back up, but the cleared value stays gone
        stub.displays = [makeMainDisplay(uuids: ["A", "B", "C"])]
        appState.forceSpaceUpdate()
        appState.forceSpaceUpdate()

        #expect(store.spaceOrders["Main"] == ["A", "B", "C"])
        #expect(SpacePreferences.label(forSpace: 2, store: store) == nil)
        #expect(SpacePreferences.label(forSpace: 3, store: store) == "Play")
    }

    @Test("a snapshot with an unreadable UUID changes neither baseline nor candidate")
    func unreadableUUID_leavesTrackingStateAlone() {
        stub.activeDisplayIdentifier = "Main"
        stub.displays = [makeMainDisplay(uuids: ["A", "B", "C"])]
        let appState = AppState(displaySpaceProvider: stub, skipObservers: true, store: store)
        SpacePreferences.setLabel("Work", forSpace: 2, store: store)

        // Two reads with one UUID unreadable must not erode the baseline -
        // dropping the display instead would erase it after confirmation
        stub.displays = [
            CGSStub.makeDisplay(
                displayID: "Main",
                uuidSpaces: [
                    (id: 100, uuid: "A", isFullscreen: false),
                    (id: 101, uuid: nil, isFullscreen: false),
                    (id: 102, uuid: "C", isFullscreen: false),
                ],
                activeSpaceID: 100
            ),
        ]
        appState.forceSpaceUpdate()
        appState.forceSpaceUpdate()
        #expect(store.spaceOrders["Main"] == ["A", "B", "C"])

        // Identities return in reordered form: still recognized against the
        // preserved baseline
        stub.displays = [makeMainDisplay(uuids: ["A", "C", "B"])]
        appState.forceSpaceUpdate()

        #expect(SpacePreferences.label(forSpace: 3, store: store) == "Work")
        #expect(SpacePreferences.label(forSpace: 2, store: store) == nil)
    }

    @Test("a transient single-display read cannot permute shared positions")
    func transientSingleDisplayRead_protectsSharedMaps() {
        stub.activeDisplayIdentifier = "DisplayA"
        let displayA = CGSStub.makeDisplay(
            displayID: "DisplayA",
            uuidSpaces: [(id: 100, uuid: "A", isFullscreen: false), (id: 101, uuid: "B", isFullscreen: false)],
            activeSpaceID: 100
        )
        let displayB = CGSStub.makeDisplay(
            displayID: "DisplayB",
            uuidSpaces: [(id: 200, uuid: "C", isFullscreen: false), (id: 201, uuid: "D", isFullscreen: false)],
            activeSpaceID: 200
        )
        stub.displays = [displayA, displayB]
        let appState = AppState(displaySpaceProvider: stub, skipObservers: true, store: store)
        SpacePreferences.setLabel("Shared", forSpace: 1, store: store)

        // A racy CGS read drops DisplayB entirely while DisplayA arrives
        // reordered - the momentary single-display view must not make the
        // shared maps follow DisplayA's permutation
        let reorderedA = CGSStub.makeDisplay(
            displayID: "DisplayA",
            uuidSpaces: [(id: 101, uuid: "B", isFullscreen: false), (id: 100, uuid: "A", isFullscreen: false)],
            activeSpaceID: 100
        )
        stub.displays = [reorderedA]
        appState.forceSpaceUpdate()

        #expect(store.spaceLabels == [1: "Shared"])
        #expect(store.spaceOrders["DisplayA"] == ["A", "B"])

        // The settled read restores DisplayB: a pure reorder of DisplayA,
        // remapped without touching shared positions
        stub.displays = [reorderedA, displayB]
        appState.forceSpaceUpdate()

        #expect(store.spaceLabels == [1: "Shared"])
        #expect(store.spaceOrders["DisplayA"] == ["B", "A"])
    }

    @Test("a reorder done while the app was not running reconciles at launch")
    func offlineReorder_reconcilesAtLaunch() {
        stub.activeDisplayIdentifier = "Main"
        stub.displays = [makeMainDisplay(uuids: ["A", "B", "C"])]
        _ = AppState(displaySpaceProvider: stub, skipObservers: true, store: store)
        SpacePreferences.setLabel("Work", forSpace: 2, store: store)

        stub.displays = [makeMainDisplay(uuids: ["B", "A", "C"])]
        _ = AppState(displaySpaceProvider: stub, skipObservers: true, store: store)

        #expect(SpacePreferences.label(forSpace: 1, store: store) == "Work")
        #expect(SpacePreferences.label(forSpace: 2, store: store) == nil)
        #expect(store.spaceOrders["Main"] == ["B", "A", "C"])
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
