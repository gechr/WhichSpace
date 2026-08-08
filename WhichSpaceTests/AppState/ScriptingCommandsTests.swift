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
        SpacePreferences.setLabel("S{#}", forSpace: appState.currentSpace, store: store)

        let label = ScriptingHelpers.resolveCurrentLabel(appState: appState, store: store)

        #expect(label == "S1", "{#} should resolve to the displayed number, not the array position")
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
        SpacePreferences.setLabel("Work {#}", forSpace: 2, store: store)

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

    @Test("setCurrentLabel with empty string resets the label")
    func setCurrentLabel_emptyStringResetsLabel() {
        let appState = makeAppState()
        SpacePreferences.setLabel("Work", forSpace: 2, display: appState.currentDisplayID, store: store)

        ScriptingHelpers.setCurrentLabel("", appState: appState, store: store)

        #expect(
            SpacePreferences.label(forSpace: 2, display: appState.currentDisplayID, store: store) == nil,
            "An empty set is a synonym for resetCurrentLabel"
        )
        #expect(ScriptingHelpers.resolveCurrentLabel(appState: appState, store: store) == "2")
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

    @Test("setCurrentLabel keeps the symbol so both can combine")
    func setCurrentLabel_keepsSymbol() {
        let appState = makeAppState()
        SpacePreferences.setSymbol("star", forSpace: 2, display: appState.currentDisplayID, store: store)

        ScriptingHelpers.setCurrentLabel("Work", appState: appState, store: store)

        #expect(SpacePreferences.symbol(forSpace: 2, display: appState.currentDisplayID, store: store) == "star")
        #expect(SpacePreferences.label(forSpace: 2, display: appState.currentDisplayID, store: store) == "Work")
    }

    @Test("setCurrentLabel truncates over-limit labels with an ellipsis")
    func setCurrentLabel_overLimitTruncatesWithEllipsis() {
        let appState = makeAppState()

        ScriptingHelpers.setCurrentLabel(String(repeating: "A", count: 25), appState: appState, store: store)

        #expect(
            SpacePreferences.label(forSpace: 2, display: appState.currentDisplayID, store: store) ==
                String(repeating: "A", count: 19) + "…"
        )
    }

    @Test("setCurrentLabel at exactly the limit is stored unchanged")
    func setCurrentLabel_atLimitIsStoredUnchanged() {
        let appState = makeAppState()

        ScriptingHelpers.setCurrentLabel(String(repeating: "A", count: 20), appState: appState, store: store)

        #expect(
            SpacePreferences.label(forSpace: 2, display: appState.currentDisplayID, store: store) ==
                String(repeating: "A", count: 20)
        )
    }

    @Test("setCurrentLabel excludes {#} tokens from the limit")
    func setCurrentLabel_tokensExcludedFromLimit() {
        let appState = makeAppState()

        ScriptingHelpers.setCurrentLabel("{#} - ABCDEFG", appState: appState, store: store)

        #expect(
            SpacePreferences
                .label(forSpace: 2, display: appState.currentDisplayID, store: store) == "{#} - ABCDEFG",
            "Tokens are free; only content characters count toward the limit"
        )
    }

    @Test("setCurrentLabel trims leading and trailing whitespace")
    func setCurrentLabel_trimsWhitespace() {
        let appState = makeAppState()

        ScriptingHelpers.setCurrentLabel("  Work Space  ", appState: appState, store: store)

        #expect(
            SpacePreferences.label(forSpace: 2, display: appState.currentDisplayID, store: store) == "Work Space",
            "Only the surrounding whitespace is stripped; internal spaces are kept"
        )
    }

    @Test("setCurrentLabel with whitespace-only string resets the label")
    func setCurrentLabel_whitespaceOnlyResetsLabel() {
        let appState = makeAppState()
        SpacePreferences.setLabel("Work", forSpace: 2, display: appState.currentDisplayID, store: store)

        ScriptingHelpers.setCurrentLabel("   ", appState: appState, store: store)

        #expect(SpacePreferences.label(forSpace: 2, display: appState.currentDisplayID, store: store) == nil)
    }

    @Test("setLabel targets a space that is not current")
    func setLabel_targetsNonCurrentSpace() {
        let appState = makeAppState(activeSpaceID: 100)

        ScriptingHelpers.setLabel("Work", forSpace: 2, appState: appState, store: store)

        #expect(appState.currentSpace == 1, "Space 1 stays current; only Space 2's label changes")
        #expect(SpacePreferences.label(forSpace: 2, display: appState.currentDisplayID, store: store) == "Work")
        #expect(SpacePreferences.label(forSpace: 1, display: appState.currentDisplayID, store: store) == nil)
    }

    @Test("setBadge targets a space that is not current")
    func setBadge_targetsNonCurrentSpace() throws {
        let appState = makeAppState(activeSpaceID: 100)

        try ScriptingHelpers.setBadge("A", forSpace: 2, appState: appState, store: store)

        #expect(appState.currentSpace == 1, "Space 1 stays current; only Space 2's badge changes")
        #expect(SpacePreferences.badge(forSpace: 2, display: appState.currentDisplayID, store: store)?.character == "A")
        #expect(SpacePreferences.badge(forSpace: 1, display: appState.currentDisplayID, store: store) == nil)
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

        ScriptingHelpers.setCurrentLabel("S{#}", appState: appState, store: store)

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

    @Test("setCurrentBadge with empty string resets the badge")
    func setCurrentBadge_emptyStringResetsBadge() throws {
        let appState = makeAppState()
        SpacePreferences.setBadge(
            SpaceBadge(character: "A", position: .topRight),
            forSpace: 2,
            display: appState.currentDisplayID,
            store: store
        )

        try ScriptingHelpers.setCurrentBadge("", appState: appState, store: store)

        #expect(
            SpacePreferences.badge(forSpace: 2, display: appState.currentDisplayID, store: store) == nil,
            "An empty set is a synonym for resetCurrentBadge"
        )
    }

    @Test("setCurrentBadge trims leading and trailing whitespace")
    func setCurrentBadge_trimsWhitespace() throws {
        let appState = makeAppState()

        try ScriptingHelpers.setCurrentBadge("  A  ", appState: appState, store: store)

        #expect(SpacePreferences.badge(forSpace: 2, display: appState.currentDisplayID, store: store)?.character == "A")
    }

    @Test("setCurrentBadge with whitespace-only string resets the badge")
    func setCurrentBadge_whitespaceOnlyResetsBadge() throws {
        let appState = makeAppState()
        SpacePreferences.setBadge(
            SpaceBadge(character: "A", position: .topLeft),
            forSpace: 2,
            display: appState.currentDisplayID,
            store: store
        )

        try ScriptingHelpers.setCurrentBadge("   ", appState: appState, store: store)

        #expect(SpacePreferences.badge(forSpace: 2, display: appState.currentDisplayID, store: store) == nil)
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

    // MARK: - Enumeration Tests

    @Test("space elements match the switchable range on a single display")
    func spaceElements_matchSwitchableRange() {
        let appState = makeAppState()

        // Asserted structurally against the array `switchToSpace` indexes.
        // Calling `switchToSpace` here would gate on `AXIsProcessTrusted`,
        // which is granted on a developer machine but never on CI
        #expect(ScriptingHelpers.scriptableSpaces(appState: appState, store: store).count
            == appState.allSpaceEntries.count)
    }

    @Test("scriptable elements are empty when no Spaces are available")
    func scriptableElements_emptyWithoutSpaces() {
        let appState = AppState(displaySpaceProvider: stub, skipObservers: true, store: store)

        #expect(ScriptingHelpers.scriptableSpaces(appState: appState, store: store).isEmpty)
        #expect(ScriptingHelpers.scriptableDisplays(appState: appState, store: store).isEmpty)
    }

    @Test("space labels return defaults when no labels are customized")
    func spaceLabels_defaults() {
        let appState = makeAppState()

        let labels = ScriptingHelpers.scriptableSpaces(appState: appState, store: store).map(\.label)

        #expect(labels == ["1", "2"])
    }

    @Test("space labels include custom labels for non-current Spaces")
    func spaceLabels_includeCustomLabels() {
        let appState = makeAppState(activeSpaceID: 101)
        SpacePreferences.setLabel("Mail", forSpace: 1, display: appState.currentDisplayID, store: store)

        let labels = ScriptingHelpers.scriptableSpaces(appState: appState, store: store).map(\.label)

        #expect(labels == ["Mail", "2"])
    }

    @Test("space labels resolve templates against each Space's number")
    func spaceLabels_resolveTemplatePerSpace() {
        let appState = makeAppState()
        SpacePreferences.setLabel("S{#}", forSpace: 1, display: appState.currentDisplayID, store: store)
        SpacePreferences.setLabel("S{#}", forSpace: 2, display: appState.currentDisplayID, store: store)

        let labels = ScriptingHelpers.scriptableSpaces(appState: appState, store: store).map(\.label)

        #expect(labels == ["S1", "S2"])
    }

    @Test("space labels mark fullscreen Spaces with the default label")
    func spaceLabels_fullscreen() {
        // Local numbering: fullscreen entries keep a position in the list.
        // Global numbering drops them, covered by the global tests below.
        store.localSpaceNumbers = true
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
        let appState = AppState(displaySpaceProvider: stub, skipObservers: true, store: store)

        #expect(
            ScriptingHelpers.scriptableSpaces(appState: appState, store: store).map(\.label)
                == ["1", Labels.fullscreen, "2"],
            "Fullscreen entries occupy a position but do not consume a Space number"
        )
    }

    @Test("space badges yield an empty string for unbadged Spaces")
    func spaceBadges_emptyWhenUnset() throws {
        let appState = makeAppState()
        try ScriptingHelpers.setBadge("A", forSpace: 1, appState: appState, store: store)

        let badges = ScriptingHelpers.scriptableSpaces(appState: appState, store: store).map(\.badge)

        #expect(badges == ["A", ""])
    }

    @Test("space badges resolve the number token per Space")
    func spaceBadges_resolveSpaceToken() throws {
        let appState = makeAppState()
        try ScriptingHelpers.setBadge(
            BadgeTemplate.spaceToken,
            forSpace: 1,
            appState: appState,
            store: store
        )
        try ScriptingHelpers.setBadge(
            BadgeTemplate.spaceToken,
            forSpace: 2,
            appState: appState,
            store: store
        )

        let badges = ScriptingHelpers.scriptableSpaces(appState: appState, store: store).map(\.badge)

        #expect(badges == ["1", "2"])
    }

    @Test("enumeration order matches switchToSpace indexing")
    func enumeration_orderMatchesSwitchIndexing() throws {
        let appState = makeAppState(activeSpaceID: 100)
        SpacePreferences.setLabel("Target", forSpace: 2, display: appState.currentDisplayID, store: store)

        let labels = ScriptingHelpers.scriptableSpaces(appState: appState, store: store).map(\.label)
        let index = try #require(labels.firstIndex(of: "Target"))

        // On a single display element order equals switch order; with global
        // numbering across displays `switch to space number` spans displays
        // while elements stay per-display
        #expect(appState.allSpaceEntries[index].id == 101)
    }

    // MARK: - Global Numbering Tests

    private func makeMultiDisplayAppState() -> AppState {
        stub.activeDisplayIdentifier = "Main"
        stub.displays = [
            CGSStub.makeDisplay(
                displayID: "Main",
                spaces: [(id: 100, isFullscreen: false), (id: 101, isFullscreen: false)],
                activeSpaceID: 100
            ),
            CGSStub.makeDisplay(
                displayID: "Side",
                spaces: [
                    (id: 200, isFullscreen: true),
                    (id: 201, isFullscreen: false),
                    (id: 202, isFullscreen: false),
                ],
                activeSpaceID: 201
            ),
        ]
        return AppState(displaySpaceProvider: stub, skipObservers: true, store: store)
    }

    @Test("global numbering enumerates Desktops across displays")
    func globalNumbering_enumeratesAcrossDisplays() {
        store.localSpaceNumbers = false
        let appState = makeMultiDisplayAppState()

        #expect(appState.globalDesktopEntries.count == 4)
        let labels = ScriptingHelpers.scriptableDisplays(appState: appState, store: store)
            .flatMap { $0.scriptableSpaces.map(\.label) }
        #expect(
            labels == ["1", "2", Labels.fullscreen, "3", "4"],
            "Default labels follow global numbering; fullscreen Spaces carry no Desktop number"
        )
    }

    @Test("global numbered labels write to the owning display")
    func globalNumbering_labelsKeyTheOwningDisplay() {
        store.localSpaceNumbers = false
        let appState = makeMultiDisplayAppState()

        ScriptingHelpers.setLabel("Mail", forSpace: 3, appState: appState, store: store)

        // Desktop 3 is the second display's first regular Space, stored at
        // its fullscreen-inclusive entry position
        #expect(SpacePreferences.label(forSpace: 2, display: "Side", store: store) == "Mail")
        let side = ScriptingHelpers.scriptableDisplays(appState: appState, store: store)[1]
        #expect(side.scriptableSpaces[1].label == "Mail")
    }

    @Test("global numbered badges resolve the number token globally")
    func globalNumbering_badgeTokenResolvesGlobally() throws {
        store.localSpaceNumbers = false
        let appState = makeMultiDisplayAppState()

        try ScriptingHelpers.setBadge(
            BadgeTemplate.spaceToken,
            forSpace: 4,
            appState: appState,
            store: store
        )

        let badges = ScriptingHelpers.scriptableDisplays(appState: appState, store: store)
            .flatMap { $0.scriptableSpaces.map(\.badge) }
        #expect(badges == ["", "", "", "", "4"])
    }

    @Test("global numbered writes past the last Desktop are ignored")
    func globalNumbering_writesPastLastDesktop_ignored() {
        store.localSpaceNumbers = false
        let appState = makeMultiDisplayAppState()

        ScriptingHelpers.setLabel("Ghost", forSpace: 5, appState: appState, store: store)

        let labels = ScriptingHelpers.scriptableDisplays(appState: appState, store: store)
            .flatMap { $0.scriptableSpaces.map(\.label) }
        #expect(labels == ["1", "2", Labels.fullscreen, "3", "4"])
    }

    @Test("fullscreen current Space falls back to its entry position in global mode")
    func globalNumbering_fullscreenCurrentSpace_fallsBackToPosition() {
        store.localSpaceNumbers = false
        stub.activeDisplayIdentifier = "Side"
        stub.displays = [
            CGSStub.makeDisplay(
                displayID: "Main",
                spaces: [(id: 100, isFullscreen: false), (id: 101, isFullscreen: false)],
                activeSpaceID: 100
            ),
            CGSStub.makeDisplay(
                displayID: "Side",
                spaces: [(id: 201, isFullscreen: false), (id: 202, isFullscreen: true)],
                activeSpaceID: 202
            ),
        ]
        let appState = AppState(displaySpaceProvider: stub, skipObservers: true, store: store)

        // The display's Desktops start at global number 3; borrowing that for
        // the fullscreen Space would name an unrelated Desktop
        #expect(appState.currentSpace == 2)
        #expect(appState.currentSpaceDisplayNumber == 2)
    }

    @Test("global numbering caps at macOS's numbered Desktop range")
    func globalNumbering_capsAtNumberedShortcutRange() {
        store.localSpaceNumbers = false
        stub.activeDisplayIdentifier = "Main"
        stub.displays = [
            CGSStub.makeDisplay(
                displayID: "Main",
                spaces: (0 ..< 9).map { (id: 100 + $0, isFullscreen: false) },
                activeSpaceID: 100
            ),
            CGSStub.makeDisplay(
                displayID: "Side",
                spaces: (0 ..< 8).map { (id: 200 + $0, isFullscreen: false) },
                activeSpaceID: 200
            ),
        ]
        let appState = AppState(displaySpaceProvider: stub, skipObservers: true, store: store)

        // 17 regular Spaces exist, but macOS's numbered shortcuts stop at 16,
        // so Desktop 17 is not addressable by global number on any surface
        #expect(appState.globalDesktopEntries.count == 16)
    }

    // MARK: - Scriptable Object Model Tests

    @Test("scriptableDisplays lists displays in CGS order")
    func scriptableDisplays_listsDisplaysInOrder() {
        let appState = makeMultiDisplayAppState()

        let displays = ScriptingHelpers.scriptableDisplays(appState: appState, store: store)

        #expect(displays.map(\.displayNumber) == [1, 2])
        #expect(displays.map(\.displayID) == ["Main", "Side"])
    }

    @Test("display Spaces use fullscreen-inclusive entry positions")
    func displaySpaces_fullscreenInclusivePositions() {
        let appState = makeMultiDisplayAppState()

        let side = ScriptingHelpers.scriptableDisplays(appState: appState, store: store)[1]

        #expect(side.scriptableSpaces.map(\.spaceNumber) == [1, 2, 3])
    }

    @Test("app-level Spaces follow the current display regardless of numbering mode")
    func appLevelSpaces_followCurrentDisplay() {
        store.localSpaceNumbers = false
        let appState = makeMultiDisplayAppState()

        let spaces = ScriptingHelpers.scriptableSpaces(appState: appState, store: store)

        #expect(spaces.map(\.spaceNumber) == [1, 2])
        #expect(spaces.map(\.displayID) == ["Main", "Main"])
    }

    @Test("space label templates follow the numbering mode per display")
    func spaceLabel_templateFollowsNumberingMode() {
        store.localSpaceNumbers = false
        let appState = makeMultiDisplayAppState()
        SpacePreferences.setLabel("S{#}", forSpace: 3, display: "Side", store: store)

        let side = ScriptingHelpers.scriptableDisplays(appState: appState, store: store)[1]

        // Side's Desktops start at global number 3, so its second regular
        // Space (entry position 3) renders the global number 4
        #expect(side.scriptableSpaces[2].label == "S4")
        store.localSpaceNumbers = true
        #expect(side.scriptableSpaces[2].label == "S2")
    }

    @Test("space label setter writes the raw entry key on the owning display")
    func spaceLabel_setterWritesRawKey() {
        store.localSpaceNumbers = false
        let appState = makeMultiDisplayAppState()

        let side = ScriptingHelpers.scriptableDisplays(appState: appState, store: store)[1]
        side.scriptableSpaces[1].label = "Mail"

        // Entry position 2 on the owning display, untouched by the global
        // Desktop numbering that `setLabel(forSpace:)` applies
        #expect(SpacePreferences.label(forSpace: 2, display: "Side", store: store) == "Mail")
        #expect(side.scriptableSpaces[1].label == "Mail")
    }

    @Test("space label setter trims, clears on empty, and truncates")
    func spaceLabel_setterTrimsClearsAndTruncates() {
        let appState = makeAppState()
        let spaces = ScriptingHelpers.scriptableSpaces(appState: appState, store: store)

        spaces[0].label = "  Work  "
        #expect(SpacePreferences.label(forSpace: 1, display: "Main", store: store) == "Work")

        spaces[0].label = String(repeating: "x", count: LabelTemplate.maxContentLength + 5)
        let stored = SpacePreferences.label(forSpace: 1, display: "Main", store: store)
        #expect(stored?.count == LabelTemplate.maxContentLength)
        #expect(stored?.hasSuffix("…") == true)

        spaces[0].label = "   "
        #expect(SpacePreferences.label(forSpace: 1, display: "Main", store: store) == nil)
    }

    @Test("space badge setter validates and preserves the badge corner")
    func spaceBadge_setterValidatesAndPreservesCorner() {
        let appState = makeAppState()
        let spaces = ScriptingHelpers.scriptableSpaces(appState: appState, store: store)
        SpacePreferences.setBadge(
            SpaceBadge(character: "A", position: .bottomRight),
            forSpace: 1,
            display: "Main",
            store: store
        )

        spaces[0].badge = "👍🏽"
        let updated = SpacePreferences.badge(forSpace: 1, display: "Main", store: store)
        #expect(updated?.character == "👍🏽", "A multi-scalar emoji is a single character")
        #expect(updated?.position == .bottomRight)

        spaces[0].badge = "XY"
        #expect(
            SpacePreferences.badge(forSpace: 1, display: "Main", store: store)?.character == "👍🏽",
            "An invalid badge leaves the stored badge untouched"
        )

        spaces[0].badge = ""
        #expect(SpacePreferences.badge(forSpace: 1, display: "Main", store: store) == nil)
        #expect(spaces[1].badge.isEmpty)
    }

    @Test("space badge number token follows the numbering mode per display")
    func spaceBadge_tokenFollowsNumberingMode() throws {
        store.localSpaceNumbers = false
        let appState = makeMultiDisplayAppState()
        try ScriptingHelpers.setBadge(BadgeTemplate.spaceToken, at: (3, "Side"), store: store)

        let side = ScriptingHelpers.scriptableDisplays(appState: appState, store: store)[1]

        #expect(side.scriptableSpaces[2].badge == "4")
        store.localSpaceNumbers = true
        #expect(side.scriptableSpaces[2].badge == "2")
    }

    @Test("currentScriptableSpace matches the current Space surface")
    func currentScriptableSpace_matchesCurrentSurface() {
        let appState = makeAppState()

        let current = ScriptingHelpers.currentScriptableSpace(appState: appState, store: store)

        #expect(current?.spaceNumber == appState.currentSpace)
        #expect(current?.displayID == "Main")
        #expect(
            current?.label == ScriptingHelpers.resolveCurrentLabel(appState: appState, store: store),
            "The element and the Shortcuts surface agree on the current label"
        )
    }

    @Test("currentScriptableSpace is nil while the snapshot is empty")
    func currentScriptableSpace_nilWhenEmpty() {
        let appState = AppState(displaySpaceProvider: stub, skipObservers: true, store: store)

        #expect(ScriptingHelpers.currentScriptableSpace(appState: appState, store: store) == nil)
    }

    @Test("display name is empty when no attached screen matches")
    func displayName_emptyForUnmatchedDisplay() {
        let appState = makeAppState()

        let displays = ScriptingHelpers.scriptableDisplays(appState: appState, store: store)

        #expect(displays[0].name.isEmpty, "Stub display IDs match no real screen UUID")
    }

    @Test("disconnected displays and out-of-range entries resolve to nothing")
    func scriptableSpaces_outOfRangeAndDisconnected() {
        let appState = makeAppState()

        #expect(ScriptingHelpers.scriptableSpaces(
            onDisplay: "Gone",
            container: .application,
            appState: appState,
            store: store
        ).isEmpty)
        #expect(ScriptingHelpers.resolveLabel(
            atEntry: 99,
            displayID: "Main",
            appState: appState,
            store: store
        ).isEmpty)
        #expect(ScriptingHelpers.resolveBadge(
            atEntry: 99,
            displayID: "Main",
            appState: appState,
            store: store
        ).isEmpty)
    }
}
