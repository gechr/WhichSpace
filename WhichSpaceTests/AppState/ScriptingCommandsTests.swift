import Testing
@testable import WhichSpace

@MainActor
struct ScriptingCommandsTests {
    private let store: DefaultsStore
    private let testSuite: TestSuite
    private let stub: CGSStub

    init() {
        testSuite = TestSuiteFactory.createSuite()
        store = DefaultsStore(suite: testSuite.suite)
        stub = CGSStub()
    }

    @Test("current space label resolves template with displayed number")
    func currentSpaceLabel_templateUsesDisplayedNumber() {
        stub.activeDisplayIdentifier = "Main"
        stub.displays = [
            CGSStub.makeDisplay(
                displayID: "Main",
                spaces: [
                    (id: 100, isFullscreen: true),
                    (id: 101, isFullscreen: false),
                ],
                activeSpaceID: 101
            ),
        ]
        store.localSpaceNumbers = true
        let appState = AppState(displaySpaceProvider: stub, skipObservers: true, store: store)
        // Labels are keyed by fullscreen-inclusive position (2), but the
        // displayed number for this space is its regular index (1)
        SpacePreferences.setLabel("S{number}", forSpace: appState.currentSpace, store: store)

        let label = ScriptingHelpers.resolveCurrentLabel(appState: appState, store: store)

        #expect(label == "S1", "{number} should resolve to the displayed number, not the array position")
    }

    // MARK: - currentSpaceNumber Tests

    @Test("currentSpaceNumber returns correct number")
    func currentSpaceNumber_returnsCorrectNumberFromAppState() {
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
        let appState = AppState(displaySpaceProvider: stub, skipObservers: true, store: store)

        #expect(appState.currentSpace == 2, "currentSpaceNumber should return 2 for the second space")
    }

    @Test("currentSpaceNumber space 1 active")
    func currentSpaceNumber_space1Active() {
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
    }

    @Test("currentSpaceNumber space 3 active")
    func currentSpaceNumber_space3Active() {
        stub.activeDisplayIdentifier = "Main"
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
        let appState = AppState(displaySpaceProvider: stub, skipObservers: true, store: store)

        #expect(appState.currentSpace == 3)
    }

    // MARK: - currentSpaceLabel Tests

    @Test("currentSpaceLabel returns correct label")
    func currentSpaceLabel_returnsCorrectLabel() {
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
        let appState = AppState(displaySpaceProvider: stub, skipObservers: true, store: store)

        #expect(appState.currentSpaceLabel == "2")
    }

    @Test("currentSpaceLabel with fullscreen space")
    func currentSpaceLabel_withFullscreenSpace() {
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
        let appState = AppState(displaySpaceProvider: stub, skipObservers: true, store: store)

        #expect(appState.currentSpaceLabel == Labels.fullscreen)
    }

    @Test("currentSpaceLabel multiple displays returns active display label")
    func currentSpaceLabel_multipleDisplays_returnsActiveDisplayLabel() {
        stub.activeDisplayIdentifier = "DisplayA"
        stub.displays = [
            CGSStub.makeDisplay(
                displayID: "DisplayA",
                spaces: [
                    (id: 100, isFullscreen: false),
                    (id: 101, isFullscreen: false),
                ],
                activeSpaceID: 101
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
        let appState = AppState(displaySpaceProvider: stub, skipObservers: true, store: store)

        #expect(appState.currentSpaceLabel == "2")
    }

    // MARK: - Number vs Label Difference

    @Test("currentSpaceLabel resolves template tokens in custom labels")
    func currentSpaceLabel_resolvesTemplateTokens() {
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
        SpacePreferences.setLabel("Work {number}", forSpace: 2, store: store)

        let label = ScriptingHelpers.resolveCurrentLabel(appState: appState, store: store)
        #expect(label == "Work 2")
    }

    // MARK: - setCurrentLabel Tests

    private func makeAppState(activeSpaceID: Int = 101) -> AppState {
        stub.activeDisplayIdentifier = "Main"
        stub.displays = [
            CGSStub.makeDisplay(
                displayID: "Main",
                spaces: [
                    (id: 100, isFullscreen: false),
                    (id: 101, isFullscreen: false),
                ],
                activeSpaceID: activeSpaceID
            ),
        ]
        return AppState(displaySpaceProvider: stub, skipObservers: true, store: store)
    }

    @Test("setCurrentLabel persists label for the current space")
    func setCurrentLabel_persistsLabel() {
        let appState = makeAppState()

        ScriptingHelpers.setCurrentLabel("Work", appState: appState, store: store)

        #expect(SpacePreferences.label(forSpace: 2, display: appState.currentDisplayID, store: store) == "Work")
        #expect(ScriptingHelpers.resolveCurrentLabel(appState: appState, store: store) == "Work")
    }

    @Test("setCurrentLabel with empty string is a no-op")
    func setCurrentLabel_emptyStringIsNoOp() {
        let appState = makeAppState()
        SpacePreferences.setLabel("Work", forSpace: 2, display: appState.currentDisplayID, store: store)

        ScriptingHelpers.setCurrentLabel("", appState: appState, store: store)

        #expect(
            SpacePreferences.label(forSpace: 2, display: appState.currentDisplayID, store: store) == "Work",
            "Clearing must be deliberate via resetCurrentLabel, not an empty set"
        )
    }

    @Test("resetCurrentLabel removes the custom label")
    func resetCurrentLabel_removesLabel() {
        let appState = makeAppState()
        SpacePreferences.setLabel("Work", forSpace: 2, display: appState.currentDisplayID, store: store)

        ScriptingHelpers.resetCurrentLabel(appState: appState, store: store)

        #expect(SpacePreferences.label(forSpace: 2, display: appState.currentDisplayID, store: store) == nil)
        #expect(ScriptingHelpers.resolveCurrentLabel(appState: appState, store: store) == "2")
    }

    @Test("clearAllLabels removes shared and per-display labels")
    func clearAllLabels_removesSharedAndPerDisplayLabels() {
        let appState = makeAppState()
        SpacePreferences.setLabel("Shared", forSpace: 1, store: store)
        store.uniqueIconsPerDisplay = true
        SpacePreferences.setLabel("Work", forSpace: 2, display: appState.currentDisplayID, store: store)

        SpacePreferences.clearAllLabels(store: store)

        #expect(SpacePreferences.label(forSpace: 1, store: store) == nil)
        #expect(SpacePreferences.label(forSpace: 2, display: appState.currentDisplayID, store: store) == nil)
    }

    @Test("resetCurrentLabel is a no-op when no current space")
    func resetCurrentLabel_noCurrentSpace_isNoOp() {
        stub.activeDisplayIdentifier = "Main"
        stub.displays = []
        let appState = AppState(displaySpaceProvider: stub, skipObservers: true, store: store)

        ScriptingHelpers.resetCurrentLabel(appState: appState, store: store)

        #expect(SpacePreferences.label(forSpace: 0, display: appState.currentDisplayID, store: store) == nil)
    }

    @Test("setCurrentLabel clears symbol so label takes effect")
    func setCurrentLabel_clearsSymbol() {
        let appState = makeAppState()
        SpacePreferences.setSymbol("star", forSpace: 2, display: appState.currentDisplayID, store: store)

        ScriptingHelpers.setCurrentLabel("Work", appState: appState, store: store)

        #expect(SpacePreferences.symbol(forSpace: 2, display: appState.currentDisplayID, store: store) == nil)
    }

    @Test("setCurrentLabel truncates over-limit labels with an ellipsis")
    func setCurrentLabel_overLimitTruncatesWithEllipsis() {
        let appState = makeAppState()

        ScriptingHelpers.setCurrentLabel("ABCDEFGHIJKLMNOP", appState: appState, store: store)

        #expect(SpacePreferences.label(forSpace: 2, display: appState.currentDisplayID, store: store) == "ABCDEFGHI…")
    }

    @Test("setCurrentLabel at exactly the limit is stored unchanged")
    func setCurrentLabel_atLimitIsStoredUnchanged() {
        let appState = makeAppState()

        ScriptingHelpers.setCurrentLabel("ABCDEFGHIJ", appState: appState, store: store)

        #expect(SpacePreferences.label(forSpace: 2, display: appState.currentDisplayID, store: store) == "ABCDEFGHIJ")
    }

    @Test("setCurrentLabel excludes {number} tokens from the limit")
    func setCurrentLabel_tokensExcludedFromLimit() {
        let appState = makeAppState()

        ScriptingHelpers.setCurrentLabel("{number} - ABCDEFG", appState: appState, store: store)

        #expect(
            SpacePreferences
                .label(forSpace: 2, display: appState.currentDisplayID, store: store) == "{number} - ABCDEFG",
            "Tokens are free; only content characters count toward the limit"
        )
    }

    @Test("setCurrentLabel is a no-op when no current space")
    func setCurrentLabel_noCurrentSpace_isNoOp() {
        stub.activeDisplayIdentifier = "Main"
        stub.displays = []
        let appState = AppState(displaySpaceProvider: stub, skipObservers: true, store: store)

        ScriptingHelpers.setCurrentLabel("Work", appState: appState, store: store)

        #expect(SpacePreferences.label(forSpace: 0, display: appState.currentDisplayID, store: store) == nil)
    }

    @Test("setCurrentLabel resolves template on read")
    func setCurrentLabel_templateResolvesOnRead() {
        let appState = makeAppState()

        ScriptingHelpers.setCurrentLabel("S{number}", appState: appState, store: store)

        #expect(ScriptingHelpers.resolveCurrentLabel(appState: appState, store: store) == "S2")
    }

    // MARK: - Badge Tests

    @Test("setCurrentBadge persists badge for the current space")
    func setCurrentBadge_persistsBadge() throws {
        let appState = makeAppState()

        try ScriptingHelpers.setCurrentBadge("A", appState: appState, store: store)

        #expect(SpacePreferences.badge(forSpace: 2, display: appState.currentDisplayID, store: store)?.character == "A")
        #expect(ScriptingHelpers.resolveCurrentBadge(appState: appState, store: store) == "A")
    }

    @Test("setCurrentBadge accepts multi-scalar emoji as one character")
    func setCurrentBadge_acceptsMultiScalarEmoji() throws {
        let appState = makeAppState()

        try ScriptingHelpers.setCurrentBadge("👍🏽", appState: appState, store: store)

        #expect(ScriptingHelpers.resolveCurrentBadge(appState: appState, store: store) == "👍🏽")
    }

    @Test("setCurrentBadge throws for more than one character")
    func setCurrentBadge_multipleCharactersThrows() {
        let appState = makeAppState()

        #expect(throws: BadgeError.self) {
            try ScriptingHelpers.setCurrentBadge("AB", appState: appState, store: store)
        }
        #expect(
            SpacePreferences.badge(forSpace: 2, display: appState.currentDisplayID, store: store) == nil,
            "A rejected badge must not be stored"
        )
    }

    @Test("setCurrentBadge with empty string is a no-op")
    func setCurrentBadge_emptyStringIsNoOp() throws {
        let appState = makeAppState()
        SpacePreferences.setBadge(
            SpaceBadge(character: "A", position: .topRight),
            forSpace: 2,
            display: appState.currentDisplayID,
            store: store
        )

        try ScriptingHelpers.setCurrentBadge("", appState: appState, store: store)

        #expect(
            SpacePreferences.badge(forSpace: 2, display: appState.currentDisplayID, store: store)?.character == "A",
            "Clearing must be deliberate via resetCurrentBadge, not an empty set"
        )
    }

    @Test("setCurrentBadge preserves the existing badge position")
    func setCurrentBadge_preservesPosition() throws {
        let appState = makeAppState()
        SpacePreferences.setBadge(
            SpaceBadge(character: "A", position: .bottomRight),
            forSpace: 2,
            display: appState.currentDisplayID,
            store: store
        )

        try ScriptingHelpers.setCurrentBadge("B", appState: appState, store: store)

        let badge = SpacePreferences.badge(forSpace: 2, display: appState.currentDisplayID, store: store)
        #expect(badge?.character == "B")
        #expect(badge?.position == .bottomRight)
    }

    @Test("resolveCurrentBadge resolves the space number token")
    func resolveCurrentBadge_resolvesSpaceToken() throws {
        let appState = makeAppState()

        try ScriptingHelpers.setCurrentBadge(BadgeTemplate.spaceToken, appState: appState, store: store)

        #expect(
            SpacePreferences.badge(forSpace: 2, display: appState.currentDisplayID, store: store)?.character
                == BadgeTemplate.spaceToken,
            "The raw token is stored so the badge tracks the Space number"
        )
        #expect(ScriptingHelpers.resolveCurrentBadge(appState: appState, store: store) == "2")
    }

    @Test("resolveCurrentBadge returns empty string when unset")
    func resolveCurrentBadge_unsetReturnsEmpty() {
        let appState = makeAppState()

        #expect(ScriptingHelpers.resolveCurrentBadge(appState: appState, store: store).isEmpty)
    }

    @Test("resetCurrentBadge removes the badge")
    func resetCurrentBadge_removesBadge() throws {
        let appState = makeAppState()
        try ScriptingHelpers.setCurrentBadge("A", appState: appState, store: store)

        ScriptingHelpers.resetCurrentBadge(appState: appState, store: store)

        #expect(SpacePreferences.badge(forSpace: 2, display: appState.currentDisplayID, store: store) == nil)
    }

    @Test("clearAllBadges removes shared and per-display badges")
    func clearAllBadges_removesSharedAndPerDisplayBadges() {
        let appState = makeAppState()
        SpacePreferences.setBadge(SpaceBadge(character: "A", position: .topLeft), forSpace: 1, store: store)
        store.uniqueIconsPerDisplay = true
        SpacePreferences.setBadge(
            SpaceBadge(character: "B", position: .topRight),
            forSpace: 2,
            display: appState.currentDisplayID,
            store: store
        )

        SpacePreferences.clearAllBadges(store: store)

        #expect(SpacePreferences.badge(forSpace: 1, store: store) == nil)
        #expect(SpacePreferences.badge(forSpace: 2, display: appState.currentDisplayID, store: store) == nil)
    }

    @Test("fullscreen: number is index, label is F")
    func currentSpaceNumberAndLabel_fullscreen() {
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
        let appState = AppState(displaySpaceProvider: stub, skipObservers: true, store: store)

        #expect(appState.currentSpace == 2)
        #expect(appState.currentSpaceLabel == Labels.fullscreen)
    }
}
