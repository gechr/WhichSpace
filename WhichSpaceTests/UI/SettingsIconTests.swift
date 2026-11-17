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

@MainActor
struct NativeMenuBarTintTests {
    private let store: DefaultsStore
    private let stub = CGSStub()

    init() {
        store = DefaultsStore(suite: TestSuiteFactory.createSuite().suite)
        stub.activeDisplayIdentifier = "Main"
        stub.displays = [
            CGSStub.makeDisplay(
                displayID: "Main",
                spaces: [(id: 100, isFullscreen: false), (id: 101, isFullscreen: false)],
                activeSpaceID: 100
            ),
        ]
    }

    private func makeAppState() -> AppState {
        AppState(displaySpaceProvider: stub, skipObservers: true, store: store)
    }

    private func bitmap(_ image: NSImage) throws -> NSBitmapImageRep {
        let data = try #require(image.tiffRepresentation)
        return try #require(NSBitmapImageRep(data: data))
    }

    @Test("native tint is the default and explicit colors take precedence")
    func defaultTintHonorsCustomColors() {
        let appState = makeAppState()
        let tinted = appState.renderer.statusBarIcon(level: .full)
        #expect(tinted.isTemplate)
        #expect(tinted === appState.renderer.statusBarIcon(level: .full))

        store.spaceColors = [1: SpaceColors(foreground: .yellow, background: .blue)]
        let custom = appState.renderer.statusBarIcon(level: .full)
        let preview = appState.renderer.settingsIcon(forSpace: 1, display: "Main")
        #expect(!custom.isTemplate)
        #expect(custom.size == tinted.size)
        #expect(custom.tiffRepresentation == preview.tiffRepresentation)

        store.spaceColors = [:]
        #expect(appState.renderer.statusBarIcon(level: .full).isTemplate)
    }

    /// A mixed strip must leave even its otherwise eligible first label
    /// unchanged, including the foreground rather than punching a hole in it.
    private func expectConfiguredFirstSlot(_ image: NSImage, appState: AppState) throws {
        let actual = try bitmap(image)
        let expected = try bitmap(appState.renderer.settingsIcon(forSpace: 1, display: "Main"))
        for y in 0 ..< expected.pixelsHigh {
            for x in 0 ..< expected.pixelsWide {
                #expect(actual.colorAt(x: x, y: y) == expected.colorAt(x: x, y: y))
            }
        }
    }

    @Test("filled styles support native tint", arguments: IconStyle.allCases.filter(\.isFilled))
    func filledStyles(style: IconStyle) {
        store.spaceIconStyles = [1: style]
        let appState = makeAppState()
        #expect(appState.renderer.statusBarIcon(level: .full).isTemplate)
    }

    @Test("unfilled styles keep their artwork", arguments: IconStyle.allCases.filter { !$0.isFilled })
    func unfilledStyles(style: IconStyle) {
        store.spaceIconStyles = [1: style]
        let appState = makeAppState()
        let original = appState.renderer.settingsIcon(forSpace: 1, display: "Main").tiffRepresentation
        let image = appState.renderer.statusBarIcon(level: .full)
        #expect(!image.isTemplate)
        #expect(image.tiffRepresentation == original)
    }

    @Test("template pixels are black with a transparent label")
    func transparentLabel() throws {
        let appState = makeAppState()
        let rep = try bitmap(appState.renderer.statusBarIcon(level: .full))
        var opaquePixels = 0
        var centralHoles = 0
        for y in 0 ..< rep.pixelsHigh {
            for x in 0 ..< rep.pixelsWide {
                let color = try #require(rep.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB))
                if color.alphaComponent > 0.9 {
                    opaquePixels += 1
                    #expect(color.redComponent < 0.01)
                    #expect(color.greenComponent < 0.01)
                    #expect(color.blueComponent < 0.01)
                }
                if x > rep.pixelsWide * 4 / 10, x < rep.pixelsWide * 6 / 10,
                   y > rep.pixelsHigh * 4 / 10, y < rep.pixelsHigh * 6 / 10,
                   color.alphaComponent < 0.1
                {
                    centralHoles += 1
                }
            }
        }
        #expect(opaquePixels > 0)
        #expect(centralHoles > 0)
    }

    @Test(
        "mixed artwork preserves the entire strip",
        arguments: ["symbol", "emoji", "label", "badge", "outline", "color"]
    )
    func mixedArtwork(kind: String) throws {
        store.showAllSpaces = true
        switch kind {
        case "symbol":
            store.spaceSymbols = [2: "star.fill"]
        case "emoji":
            store.spaceSymbols = [2: "🌿"]
        case "label":
            store.spaceLabels = [2: "🌿"]
        case "badge":
            store.spaceBadges = [2: SpaceBadge(character: "🌿", position: .topRight)]
        case "color":
            store.spaceColors = [2: SpaceColors(foreground: .yellow, background: .blue)]
        default:
            store.spaceIconStyles = [2: .circleOutline]
        }
        let appState = makeAppState()
        let image = appState.renderer.statusBarIcon(level: .full)
        #expect(!image.isTemplate)
        try expectConfiguredFirstSlot(image, appState: appState)
    }

    @Test("inherited custom colors retain their artwork", arguments: [false, true])
    func inheritedColors(perDisplay: Bool) {
        let colors = SpaceColors(foreground: .yellow, background: .blue)
        if perDisplay {
            store.displaySpaceColors = ["Main": [1: colors]]
        } else {
            store.spaceColors = [SpacePreferences.defaultStyleSpace: colors]
        }
        let appState = makeAppState()
        let image = appState.renderer.statusBarIcon(level: .full)
        #expect(!image.isTemplate)
        #expect(image.tiffRepresentation == appState.renderer.settingsIcon(forSpace: 1, display: "Main")
            .tiffRepresentation)
    }

    @Test("fullscreen app artwork prevents tint but its letter fallback supports it")
    func fullscreenArtwork() throws {
        store.showAllSpaces = true
        stub.displays = [
            CGSStub.makeDisplay(
                displayID: "Main",
                spaces: [(id: 100, isFullscreen: false), (id: 101, isFullscreen: true)],
                activeSpaceID: 100
            ),
        ]
        stub.fullscreenOwnerPIDsMap = [101: 42]
        let appState = makeAppState()
        appState.renderer.fullscreenAppIconResolver = { _ in
            NSImage(size: NSSize(width: 20, height: 20), flipped: false) { rect in
                NSColor.green.setFill()
                rect.fill()
                return true
            }
        }
        appState.renderer.invalidateIconCache()
        let image = appState.renderer.statusBarIcon(level: .full)
        #expect(!image.isTemplate)
        try expectConfiguredFirstSlot(image, appState: appState)

        appState.renderer.fullscreenAppIconResolver = { _ in nil }
        appState.renderer.invalidateIconCache()
        #expect(appState.renderer.statusBarIcon(level: .full).isTemplate)
    }

    @Test("text labels and badges support tint without changing layout")
    func textLabelAndBadge() {
        store.spaceLabels = [1: "Work {#}"]
        store.spaceBadges = [1: SpaceBadge(character: "x", position: .topRight)]
        let appState = makeAppState()
        let original = appState.renderer.settingsIcon(forSpace: 1, display: "Main")
        let image = appState.renderer.statusBarIcon(level: .full)
        #expect(image.isTemplate)
        #expect(image.size == original.size)
    }

    @Test("combined templates retain inactive opacity")
    func inactiveOpacity() throws {
        store.showAllSpaces = true
        store.inactiveSpaceOpacity = 25
        let appState = makeAppState()
        let image = appState.renderer.statusBarIcon(level: .full)
        #expect(image.isTemplate)
        let rep = try bitmap(image)
        var activeAlpha = 0.0
        var inactiveAlpha = 0.0
        for y in 0 ..< rep.pixelsHigh {
            for x in 0 ..< rep.pixelsWide {
                let alpha = try Double(#require(rep.colorAt(x: x, y: y)).alphaComponent)
                if x < rep.pixelsWide / 2 {
                    activeAlpha = max(activeAlpha, alpha)
                } else {
                    inactiveAlpha = max(inactiveAlpha, alpha)
                }
            }
        }
        #expect(activeAlpha > 0.99)
        #expect(abs(inactiveAlpha - 0.25) < 0.01)
    }

    @Test("only visible custom separators prevent native tint")
    func displaySeparators() throws {
        store.showAllDisplays = true
        store.separatorColor = .red
        let appState = makeAppState()
        #expect(appState.renderer.statusBarIcon(level: .full).isTemplate)

        stub.displays.append(CGSStub.makeDisplay(
            displayID: "Secondary",
            spaces: [(id: 200, isFullscreen: false)],
            activeSpaceID: 200
        ))
        appState.forceSpaceUpdate()
        let mixed = appState.renderer.statusBarIcon(level: .full)
        #expect(!mixed.isTemplate)
        try expectConfiguredFirstSlot(mixed, appState: appState)

        store.separatorStyle = .blank
        #expect(appState.renderer.statusBarIcon(level: .full).isTemplate)

        store.separatorStyle = .line
        store.separatorColor = nil
        let tinted = appState.renderer.statusBarIcon(level: .full)
        #expect(tinted.isTemplate)
        let rep = try bitmap(tinted)
        let slots = appState.renderer.statusBarLayout(level: .full).slots
        let separatorStart = slots[1].startX - Layout.displaySeparatorWidth
        let scale = Double(rep.pixelsWide) / tinted.size.width
        let start = Int(separatorStart * scale)
        let end = Int((separatorStart + Layout.displaySeparatorWidth) * scale)
        // Integrate the stroke across its antialiased pixels.
        var alpha = 0.0
        for x in start ..< end {
            try alpha += Double(#require(rep.colorAt(x: x, y: rep.pixelsHigh / 2)).alphaComponent)
        }
        #expect(abs(alpha / scale - 0.6) < 0.05)
    }

    @Test("native tint preserves slot widths", arguments: IconStyle.allCases.filter(\.isFilled), [0.0, 100.0])
    func matchingLayoutWidths(style: IconStyle, padding: Double) {
        store.showAllSpaces = true
        store.spaceLabels = [1: "Long label", 2: "Another label"]
        store.spaceLabelStyles = [1: style, 2: style]
        store.paddingScale = padding
        let appState = makeAppState()
        let icon = appState.renderer.statusBarIcon(level: .full)
        let width = appState.renderer.statusBarLayout(level: .full).slots.reduce(0) { $0 + $1.width }
        #expect(abs(icon.size.width - width) < 0.01)

        store.spaceColors = [1: SpaceColors(foreground: .blue, background: .clear)]
        let custom = appState.renderer.statusBarIcon(level: .full)
        let customWidth = appState.renderer.statusBarLayout(level: .full).slots.reduce(0) { $0 + $1.width }
        #expect(!custom.isTemplate)
        #expect(abs(custom.size.width - customWidth) < 0.01)
    }

    @Test("artwork on another display prevents tint across every display")
    func crossDisplayArtwork() throws {
        store.showAllDisplays = true
        stub.displays.append(CGSStub.makeDisplay(
            displayID: "Secondary",
            spaces: [(id: 200, isFullscreen: false)],
            activeSpaceID: 200
        ))
        store.displaySpaceColors = ["Secondary": [1: SpaceColors(foreground: .yellow, background: .blue)]]
        let appState = makeAppState()
        let image = appState.renderer.statusBarIcon(level: .full)
        #expect(!image.isTemplate)
        try expectConfiguredFirstSlot(image, appState: appState)
    }

    @Test("hidden artwork and shrunk-away symbols do not prevent tint")
    func visibleArtworkOnly() {
        store.showAllSpaces = true
        store.spaceSymbols = [2: "star.fill"]
        let appState = makeAppState()
        #expect(!appState.renderer.statusBarIcon(level: .full).isTemplate)
        #expect(appState.renderer.statusBarIcon(level: .compact).isTemplate)
        #expect(appState.renderer.statusBarIcon(level: .currentOnly).isTemplate)

        store.hideEmptySpaces = true
        stub.spacesWithWindowsSet = [100]
        #expect(appState.renderer.statusBarIcon(level: .full).isTemplate)
    }
}
