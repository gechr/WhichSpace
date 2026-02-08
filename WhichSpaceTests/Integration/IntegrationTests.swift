import Testing
@testable import WhichSpace

/// Integration tests that verify the full AppState -> StatusBarRenderer -> icon generation flow.
@Suite("Integration")
@MainActor
struct IntegrationTests {
    private let store: DefaultsStore
    private let testSuite: TestSuite
    private let stub: CGSStub

    init() {
        testSuite = TestSuiteFactory.createSuite()
        store = DefaultsStore(suite: testSuite.suite)
        stub = CGSStub()
    }

    // MARK: - Full Flow: AppState -> Renderer -> Icon

    @Test("full flow: app state produces correct labels and icon")
    func fullFlow_appStateProducesCorrectLabelsAndIcon() {
        // Given: A single display with 3 spaces, space 1 active
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

        // When: Create AppState and get status bar icon
        let appState = AppState(displaySpaceProvider: stub, skipObservers: true, store: store)

        // Then: Correct labels are produced
        #expect(appState.allSpaceLabels == ["1", "2", "3"])
        #expect(appState.currentSpace == 1)
        #expect(appState.currentSpaceLabel == "1")

        // Then: Status bar icon is generated successfully
        let icon = appState.statusBarIcon
        #expect(icon.size.width > 0, "Icon should have non-zero width")
        #expect(icon.size.height > 0, "Icon should have non-zero height")
    }

    @Test("full flow: space change updates state")
    func fullFlow_spaceChangeUpdatesState() {
        // Given: Start on space 1
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

        let appState = AppState(displaySpaceProvider: stub, skipObservers: true, store: store)
        #expect(appState.currentSpace == 1)
        #expect(appState.currentSpaceLabel == "1")

        // When: Switch to space 3 via CGSStub and force update
        stub.displays = [
            CGSStub.makeDisplay(
                displayID: "Main",
                spaces: [
                    (id: 100, isFullscreen: false),
                    (id: 101, isFullscreen: false),
                    (id: 102, isFullscreen: false),
                ],
                activeSpaceID: 102
            ),
        ]
        appState.forceSpaceUpdate()

        // Then: State reflects the new space
        #expect(appState.currentSpace == 3)
        #expect(appState.currentSpaceLabel == "3")

        // And icon is still valid
        let icon = appState.statusBarIcon
        #expect(icon.size.width > 0)
    }

    @Test("full flow: show all spaces icon reflects multiple spaces")
    func fullFlow_showAllSpaces_iconReflectsMultipleSpaces() {
        // Given: 4 spaces, showAllSpaces enabled
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
        store.showAllSpaces = true

        let appState = AppState(displaySpaceProvider: stub, skipObservers: true, store: store)

        // When
        let icon = appState.statusBarIcon

        // Then: Combined icon width should be 4 * statusItemWidth
        let expectedWidth = 4.0 * Layout.statusItemWidth
        #expect(abs(icon.size.width - expectedWidth) <= 0.1)
    }

    @Test("full flow: show all displays icon includes multiple displays")
    func fullFlow_showAllDisplays_iconIncludesMultipleDisplays() {
        // Given: Two displays with different spaces
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
                ],
                activeSpaceID: 200
            ),
        ]
        store.showAllDisplays = true

        let appState = AppState(displaySpaceProvider: stub, skipObservers: true, store: store)

        // When
        let icon = appState.statusBarIcon

        // Then: Width should be 4 spaces + 1 separator
        let expectedWidth = 4.0 * Layout.statusItemWidth + Layout.displaySeparatorWidth
        #expect(abs(icon.size.width - expectedWidth) <= 0.1)
    }

    // MARK: - Preference Combinations

    @Test("icon generation: custom colors produces valid icon")
    func iconGeneration_customColors_producesValidIcon() {
        // Given: Custom colors set for space 1
        stub.activeDisplayIdentifier = "Main"
        stub.displays = [
            CGSStub.makeDisplay(
                displayID: "Main",
                spaces: [(id: 100, isFullscreen: false)],
                activeSpaceID: 100
            ),
        ]
        store.spaceColors = [1: SpaceColors(foreground: .red, background: .blue)]

        let appState = AppState(displaySpaceProvider: stub, skipObservers: true, store: store)

        // When
        let icon = appState.statusBarIcon

        // Then
        #expect(icon.size.width > 0, "Icon with custom colors should be valid")
        #expect(icon.size.height > 0)
    }

    @Test("icon generation: all icon styles produce valid icons")
    func iconGeneration_allIconStyles_produceValidIcons() {
        // Given
        stub.activeDisplayIdentifier = "Main"
        stub.displays = [
            CGSStub.makeDisplay(
                displayID: "Main",
                spaces: [(id: 100, isFullscreen: false)],
                activeSpaceID: 100
            ),
        ]

        let appState = AppState(displaySpaceProvider: stub, skipObservers: true, store: store)

        // When/Then: Each icon style produces a valid icon
        for style in IconStyle.allCases {
            store.spaceIconStyles = [1: style]
            let icon = appState.statusBarIcon
            #expect(icon.size.width > 0, "Icon style \(style) should produce valid width")
            #expect(icon.size.height > 0, "Icon style \(style) should produce valid height")
        }
    }

    @Test("icon generation: SF Symbol produces valid icon")
    func iconGeneration_sfSymbol_producesValidIcon() {
        // Given: SF Symbol assigned to space 1
        stub.activeDisplayIdentifier = "Main"
        stub.displays = [
            CGSStub.makeDisplay(
                displayID: "Main",
                spaces: [(id: 100, isFullscreen: false)],
                activeSpaceID: 100
            ),
        ]
        store.spaceSymbols = [1: "star.fill"]

        let appState = AppState(displaySpaceProvider: stub, skipObservers: true, store: store)

        // When
        let icon = appState.statusBarIcon

        // Then
        #expect(icon.size.width > 0, "Icon with SF Symbol should be valid")
    }

    @Test("icon generation: emoji symbol produces valid icon")
    func iconGeneration_emojiSymbol_producesValidIcon() {
        // Given: Emoji assigned to space 1
        stub.activeDisplayIdentifier = "Main"
        stub.displays = [
            CGSStub.makeDisplay(
                displayID: "Main",
                spaces: [(id: 100, isFullscreen: false)],
                activeSpaceID: 100
            ),
        ]
        store.spaceSymbols = [1: "\u{1F680}"]

        let appState = AppState(displaySpaceProvider: stub, skipObservers: true, store: store)

        // When
        let icon = appState.statusBarIcon

        // Then
        #expect(icon.size.width > 0, "Icon with emoji should be valid")
    }

    @Test("icon generation: custom size scale produces valid icon")
    func iconGeneration_customSizeScale_producesValidIcon() {
        // Given: Custom size scale
        stub.activeDisplayIdentifier = "Main"
        stub.displays = [
            CGSStub.makeDisplay(
                displayID: "Main",
                spaces: [(id: 100, isFullscreen: false)],
                activeSpaceID: 100
            ),
        ]
        store.sizeScale = 150.0

        let appState = AppState(displaySpaceProvider: stub, skipObservers: true, store: store)

        // When
        let icon = appState.statusBarIcon

        // Then
        #expect(icon.size.width > 0, "Icon with custom size scale should be valid")
    }

    @Test("icon generation: show all spaces with dimming produces valid icon")
    func iconGeneration_showAllSpacesWithDimming_producesValidIcon() {
        // Given: Show all spaces with dimming enabled
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
        store.showAllSpaces = true
        store.dimInactiveSpaces = true

        let appState = AppState(displaySpaceProvider: stub, skipObservers: true, store: store)

        // When
        let icon = appState.statusBarIcon

        // Then
        let expectedWidth = 2.0 * Layout.statusItemWidth
        #expect(abs(icon.size.width - expectedWidth) <= 0.1)
    }

    @Test("icon generation: fullscreen space mixed produces valid icon")
    func iconGeneration_fullscreenSpaceMixed_producesValidIcon() {
        // Given: Mix of regular and fullscreen spaces with various preferences
        stub.activeDisplayIdentifier = "Main"
        stub.displays = [
            CGSStub.makeDisplay(
                displayID: "Main",
                spaces: [
                    (id: 100, isFullscreen: false),
                    (id: 101, isFullscreen: true),
                    (id: 102, isFullscreen: false),
                ],
                activeSpaceID: 100
            ),
        ]
        store.showAllSpaces = true
        store.spaceColors = [1: SpaceColors(foreground: .white, background: .black)]
        store.spaceIconStyles = [1: .circle, 3: .hexagon]

        let appState = AppState(displaySpaceProvider: stub, skipObservers: true, store: store)

        // When
        let icon = appState.statusBarIcon

        // Then: Icon width should reflect 3 spaces
        let expectedWidth = 3.0 * Layout.statusItemWidth
        #expect(abs(icon.size.width - expectedWidth) <= 0.1)
    }

    // MARK: - StatusBarLayout Integration

    @Test("status bar layout: show all spaces correct slot count")
    func statusBarLayout_showAllSpaces_correctSlotCount() {
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
                activeSpaceID: 101
            ),
        ]
        store.showAllSpaces = true

        let appState = AppState(displaySpaceProvider: stub, skipObservers: true, store: store)

        // When
        let layout = appState.statusBarLayout()

        // Then
        #expect(layout.slots.count == 3, "Should have 3 slots for 3 spaces")
        #expect(layout.slots.map(\.targetSpace) == [1, 2, 3])
    }

    @Test("status bar layout: show all displays includes separator")
    func statusBarLayout_showAllDisplays_includesSeparator() {
        // Given: Two displays
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
                ],
                activeSpaceID: 200
            ),
        ]
        store.showAllDisplays = true

        let appState = AppState(displaySpaceProvider: stub, skipObservers: true, store: store)

        // When
        let layout = appState.statusBarLayout()

        // Then: 3 total slots (2 from DisplayA + 1 from DisplayB)
        #expect(layout.slots.count == 3)

        // Second display's slot starts after separator
        let expectedStartX = 2.0 * Layout.statusItemWidth + Layout.displaySeparatorWidth
        #expect(abs(layout.slots[2].startX - expectedStartX) <= 0.1)
    }
}
