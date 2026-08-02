import AppKit
import Testing
@testable import WhichSpace

@MainActor
struct SettingsIconTests {
    private let store: DefaultsStore
    private let stub: CGSStub

    init() {
        let testSuite = TestSuiteFactory.createSuite()
        store = DefaultsStore(suite: testSuite.suite)
        stub = CGSStub()
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
    }

    /// AppState lives inside each test rather than on the suite: the suite
    /// value deallocates off the main actor, where AppState's deinit traps.
    private func makeAppState() -> AppState {
        AppState(displaySpaceProvider: stub, skipObservers: true, store: store)
    }

    private func pixels(_ image: NSImage) -> Data? {
        image.tiffRepresentation
    }

    @Test("honors per-Space preferences for a non-current Space")
    func honorsNonCurrentSpacePreferences() {
        let appState = makeAppState()
        let plain = appState.renderer.settingsIcon(forSpace: 3, display: "Main")
        SpacePreferences.setColors(
            SpaceColors(foreground: .red, background: .blue),
            forSpace: 3,
            display: "Main",
            store: store
        )
        let styled = appState.renderer.settingsIcon(forSpace: 3, display: "Main")
        #expect(pixels(styled) != pixels(plain))

        // Other Spaces stay unaffected
        let neighbor = appState.renderer.settingsIcon(forSpace: 2, display: "Main")
        let neighborAfter = appState.renderer.settingsIcon(forSpace: 2, display: "Main")
        #expect(pixels(neighbor) == pixels(neighborAfter))
    }

    @Test("resolves custom labels with the Space number")
    func resolvesLabels() {
        let appState = makeAppState()
        let plain = appState.renderer.settingsIcon(forSpace: 2, display: "Main")
        SpacePreferences.setLabel("Space {#}", forSpace: 2, display: "Main", store: store)
        let labeled = appState.renderer.settingsIcon(forSpace: 2, display: "Main")
        #expect(pixels(labeled) != pixels(plain))
        // Labels widen the icon beyond the single-number canvas
        #expect(labeled.size.width > plain.size.width)
    }

    @Test("space 0 renders the default-style template from shared storage")
    func rendersTemplate() {
        let appState = makeAppState()
        let plain = appState.renderer.settingsIcon(forSpace: 0, display: nil)
        SpacePreferences.setColors(
            SpaceColors(foreground: .yellow, background: .purple),
            forSpace: SpacePreferences.defaultStyleSpace,
            display: nil,
            store: store
        )
        let styled = appState.renderer.settingsIcon(forSpace: 0, display: nil)
        #expect(pixels(styled) != pixels(plain))
    }

    @Test("shared labels show through on displays without an override")
    func sharedLabelShowsThroughOnDisplays() {
        let appState = makeAppState()
        let plain = appState.renderer.settingsIcon(forSpace: 2, display: "Main")
        SpacePreferences.setLabel("Space {#}", forSpace: 2, display: nil, store: store)
        let labeled = appState.renderer.settingsIcon(forSpace: 2, display: "Main")
        #expect(labeled.size.width > plain.size.width)

        // An empty override is the "no label" sentinel and suppresses the
        // shared label on that display alone
        SpacePreferences.setLabel("", forSpace: 2, display: "Main", store: store)
        let suppressed = appState.renderer.settingsIcon(forSpace: 2, display: "Main")
        #expect(suppressed.size.width == plain.size.width)
    }

    @Test("the scale override multiplies the rendered size")
    func scaleOverride() {
        let appState = makeAppState()
        let base = appState.renderer.settingsIcon(forSpace: 1, display: "Main")
        let enlarged = appState.renderer.settingsIcon(forSpace: 1, display: "Main", sizeScale: 300)
        #expect(enlarged.size.width == base.size.width * 3)
        #expect(enlarged.size.height == base.size.height * 3)
    }

    // MARK: - Hover Preview Overrides

    @Test("nil overrides render identically to no overrides")
    func nilOverridesMatchBaseline() {
        let appState = makeAppState()
        let base = appState.renderer.settingsIcon(forSpace: 1, display: "Main")
        let explicit = appState.renderer.settingsIcon(forSpace: 1, display: "Main", overrides: nil)
        #expect(pixels(base) == pixels(explicit))
    }

    /// Pins the contract that a hover shows exactly what clicking commits:
    /// the overridden render must match a fresh render after the same value
    /// is stored.
    @Test("a style override renders what committing the style renders")
    func stylePreviewEqualsCommit() {
        let appState = makeAppState()
        let previewed = appState.renderer.settingsIcon(
            forSpace: 2, display: "Main", overrides: IconPreviewOverrides(style: .circle)
        )
        SpacePreferences.setIconStyle(.circle, forSpace: 2, display: "Main", store: store)
        let committed = appState.renderer.settingsIcon(forSpace: 2, display: "Main")
        #expect(pixels(previewed) == pixels(committed))
    }

    @Test("a style override forces the plain number over a stored label")
    func stylePreviewForcesPlainNumber() {
        let appState = makeAppState()
        SpacePreferences.setLabel("Work", forSpace: 2, display: "Main", store: store)
        let previewed = appState.renderer.settingsIcon(
            forSpace: 2, display: "Main", overrides: IconPreviewOverrides(style: .circle)
        )
        // Committing a number style clears the label and symbol sentinels
        SpacePreferences.setSymbol("", forSpace: 2, display: "Main", store: store)
        SpacePreferences.setLabel("", forSpace: 2, display: "Main", store: store)
        SpacePreferences.setIconStyle(.circle, forSpace: 2, display: "Main", store: store)
        let committed = appState.renderer.settingsIcon(forSpace: 2, display: "Main")
        #expect(pixels(previewed) == pixels(committed))
    }

    @Test("a style override keeps the stored badge, as committing does")
    func stylePreviewKeepsStoredBadge() {
        let appState = makeAppState()
        SpacePreferences.setBadge(
            SpaceBadge(character: "!", position: .topRight), forSpace: 2, display: "Main", store: store
        )
        let previewed = appState.renderer.settingsIcon(
            forSpace: 2, display: "Main", overrides: IconPreviewOverrides(style: .circle)
        )
        SpacePreferences.setSymbol("", forSpace: 2, display: "Main", store: store)
        SpacePreferences.setLabel("", forSpace: 2, display: "Main", store: store)
        SpacePreferences.setIconStyle(.circle, forSpace: 2, display: "Main", store: store)
        let committed = appState.renderer.settingsIcon(forSpace: 2, display: "Main")
        #expect(pixels(previewed) == pixels(committed))
    }

    @Test("a clear preview renders what toggling the symbol off renders")
    func symbolClearPreviewEqualsToggleOff() {
        let appState = makeAppState()
        // A template symbol must not bleed through the toggle-off, so the
        // commit writes the "none" sentinel rather than a clear
        SpacePreferences.setSymbol(
            "circle", forSpace: SpacePreferences.defaultStyleSpace, display: nil, store: store
        )
        SpacePreferences.setSymbol("star", forSpace: 2, display: "Main", store: store)
        let previewed = appState.renderer.settingsIcon(
            forSpace: 2, display: "Main", overrides: IconPreviewOverrides(clearSymbol: true)
        )
        SpacePreferences.setSymbol("", forSpace: 2, display: "Main", store: store)
        let committed = appState.renderer.settingsIcon(forSpace: 2, display: "Main")
        #expect(pixels(previewed) == pixels(committed))
    }

    @Test("a symbol wrap override renders what committing it renders")
    func symbolWrapPreviewEqualsCommit() {
        let appState = makeAppState()
        SpacePreferences.setLabel("Work", forSpace: 2, display: "Main", store: store)
        SpacePreferences.setSymbol("star", forSpace: 2, display: "Main", store: store)
        let previewed = appState.renderer.settingsIcon(
            forSpace: 2, display: "Main", overrides: IconPreviewOverrides(symbolWrap: .outside)
        )
        SpacePreferences.setSymbolWrap(.outside, forSpace: 2, display: "Main", store: store)
        let committed = appState.renderer.settingsIcon(forSpace: 2, display: "Main")
        #expect(pixels(previewed) == pixels(committed))
    }

    @Test("a symbol override renders what committing the symbol renders")
    func symbolPreviewEqualsCommit() {
        let appState = makeAppState()
        let previewed = appState.renderer.settingsIcon(
            forSpace: 2, display: "Main", overrides: IconPreviewOverrides(symbol: "star")
        )
        SpacePreferences.setSymbol("star", forSpace: 2, display: "Main", store: store)
        let committed = appState.renderer.settingsIcon(forSpace: 2, display: "Main")
        #expect(pixels(previewed) == pixels(committed))
    }

    @Test("an emoji override with a tone renders what committing renders")
    func emojiPreviewEqualsCommit() {
        let appState = makeAppState()
        let previewed = appState.renderer.settingsIcon(
            forSpace: 2,
            display: "Main",
            overrides: IconPreviewOverrides(skinTone: .dark, symbol: "\u{1F44B}")
        )
        SpacePreferences.setSymbol("\u{1F44B}", forSpace: 2, display: "Main", store: store)
        SpacePreferences.setSkinTone(.dark, forSpace: 2, display: "Main", store: store)
        let committed = appState.renderer.settingsIcon(forSpace: 2, display: "Main")
        #expect(pixels(previewed) == pixels(committed))
    }

    @Test("a foreground override merges with the stored background")
    func foregroundPreviewEqualsCommit() {
        let appState = makeAppState()
        SpacePreferences.setColors(
            SpaceColors(foreground: .white, background: .blue),
            forSpace: 2,
            display: "Main",
            store: store
        )
        let previewed = appState.renderer.settingsIcon(
            forSpace: 2, display: "Main", overrides: IconPreviewOverrides(foreground: .red)
        )
        SpacePreferences.setColors(
            SpaceColors(foreground: .red, background: .blue),
            forSpace: 2,
            display: "Main",
            store: store
        )
        let committed = appState.renderer.settingsIcon(forSpace: 2, display: "Main")
        #expect(pixels(previewed) == pixels(committed))
    }

    @Test("a full-colors override renders what committing the swap renders")
    func invertPreviewEqualsCommit() {
        let appState = makeAppState()
        let colors = SpaceColors(foreground: .red, background: .blue)
        SpacePreferences.setColors(colors, forSpace: 2, display: "Main", store: store)
        let previewed = appState.renderer.settingsIcon(
            forSpace: 2,
            display: "Main",
            overrides: IconPreviewOverrides(colors: colors.inverted(for: nil))
        )
        SpacePreferences.setColors(colors.inverted(for: nil), forSpace: 2, display: "Main", store: store)
        let committed = appState.renderer.settingsIcon(forSpace: 2, display: "Main")
        #expect(pixels(previewed) == pixels(committed))
    }

    @Test("clearSymbolBackground strips a stored symbol chip color")
    func clearSymbolBackgroundOverride() {
        let appState = makeAppState()
        SpacePreferences.setLabel("Work", forSpace: 2, display: "Main", store: store)
        SpacePreferences.setSymbol("star", forSpace: 2, display: "Main", store: store)
        // The chip only draws in the outside-label layout
        SpacePreferences.setSymbolWrap(.outside, forSpace: 2, display: "Main", store: store)
        SpacePreferences.setColors(
            SpaceColors(foreground: .white, background: .blue, symbol: .red, symbolBackground: .green),
            forSpace: 2,
            display: "Main",
            store: store
        )
        let base = appState.renderer.settingsIcon(forSpace: 2, display: "Main")
        let stripped = appState.renderer.settingsIcon(
            forSpace: 2,
            display: "Main",
            overrides: IconPreviewOverrides(clearSymbolBackground: true)
        )
        #expect(pixels(stripped) != pixels(base))
    }

    @Test("a badge position override renders what committing it renders")
    func badgePositionPreviewEqualsCommit() {
        let appState = makeAppState()
        SpacePreferences.setBadge(
            SpaceBadge(character: "A", position: .topLeft), forSpace: 2, display: "Main", store: store
        )
        let previewed = appState.renderer.settingsIcon(
            forSpace: 2, display: "Main", overrides: IconPreviewOverrides(badgePosition: .bottomRight)
        )
        SpacePreferences.setBadge(
            SpaceBadge(character: "A", position: .bottomRight), forSpace: 2, display: "Main", store: store
        )
        let committed = appState.renderer.settingsIcon(forSpace: 2, display: "Main")
        #expect(pixels(previewed) == pixels(committed))
    }

    @Test("a symbol position override renders what committing it renders")
    func symbolPositionPreviewEqualsCommit() {
        let appState = makeAppState()
        SpacePreferences.setLabel("Work", forSpace: 2, display: "Main", store: store)
        SpacePreferences.setSymbol("star", forSpace: 2, display: "Main", store: store)
        let previewed = appState.renderer.settingsIcon(
            forSpace: 2, display: "Main", overrides: IconPreviewOverrides(symbolPosition: .right)
        )
        SpacePreferences.setSymbolPosition(.right, forSpace: 2, display: "Main", store: store)
        let committed = appState.renderer.settingsIcon(forSpace: 2, display: "Main")
        #expect(pixels(previewed) == pixels(committed))
    }

    @Test("overrides never touch the status bar icon")
    func overridesLeaveStatusBarAlone() {
        let appState = makeAppState()
        let barBefore = appState.renderer.statusBarIcon(level: .full)
        _ = appState.renderer.settingsIcon(
            forSpace: 1,
            display: "Main",
            overrides: IconPreviewOverrides(background: .orange)
        )
        let barAfter = appState.renderer.statusBarIcon(level: .full)
        #expect(pixels(barBefore) == pixels(barAfter))
    }
}
