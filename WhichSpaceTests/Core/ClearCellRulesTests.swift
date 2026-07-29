import AppKit
import Testing
@testable import WhichSpace

@MainActor
struct ClearCellRulesTests {
    private static func rules(
        customColors: SpaceColors? = nil,
        symbol: String? = nil,
        hasLabel: Bool = false,
        iconStyle: IconStyle = .square,
        labelStyle: IconStyle = .square,
        wrap: SymbolWrap = .inside
    ) -> ClearCellRules {
        ClearCellRules(
            customColors: customColors,
            symbol: symbol,
            hasLabel: hasLabel,
            iconStyle: iconStyle,
            labelStyle: labelStyle,
            wrap: wrap
        )
    }

    // MARK: - Derived Configuration

    @Test("symbol background applies when the symbol renders bare")
    func symbolBackgroundVisibility() {
        #expect(Self.rules(symbol: "star.fill").symbolBackgroundVisible)
        #expect(Self.rules(symbol: "star.fill", hasLabel: true, wrap: .outside).symbolBackgroundVisible)
        // A non-wrapping label style always renders side-by-side
        #expect(Self.rules(symbol: "star.fill", hasLabel: true, labelStyle: .stroke).symbolBackgroundVisible)
        #expect(!Self.rules(symbol: "star.fill", hasLabel: true, wrap: .inside).symbolBackgroundVisible)
        #expect(!Self.rules(hasLabel: true).symbolBackgroundVisible)
    }

    @Test("colors apply to the label style when a label is set")
    func styleForColors() {
        #expect(Self.rules(iconStyle: .circle, labelStyle: .pill).styleForColors == .circle)
        #expect(Self.rules(hasLabel: true, iconStyle: .circle, labelStyle: .pill).styleForColors == .pill)
    }

    // MARK: - Gating Matrix

    @Test("defaults offer foreground, background, and symbol background clears")
    func defaultGating() {
        let rules = Self.rules()
        #expect(rules.showsForegroundClear)
        #expect(rules.showsBackgroundClear)
        #expect(!rules.showsSymbolClear)
        #expect(rules.showsSymbolBackgroundClear)
    }

    @Test("transparent style withholds the foreground clear")
    func transparentStyle() {
        #expect(!Self.rules(iconStyle: .transparent).showsForegroundClear)
        // The label style governs once a label is set
        #expect(!Self.rules(hasLabel: true, labelStyle: .transparent).showsForegroundClear)
        #expect(Self.rules(hasLabel: true, iconStyle: .transparent).showsForegroundClear)
    }

    @Test("a clear foreground withholds the background clear")
    func clearForeground() {
        let colors = SpaceColors(foreground: .clear, background: .black)
        let rules = Self.rules(customColors: colors)
        #expect(!rules.showsBackgroundClear)
        #expect(rules.showsForegroundClear)
    }

    @Test("a clear background withholds the foreground clear")
    func clearBackground() {
        let colors = SpaceColors(foreground: .white, background: .clear)
        let rules = Self.rules(customColors: colors)
        #expect(!rules.showsForegroundClear)
        #expect(rules.showsBackgroundClear)
    }

    @Test("a symbol chip backdrop enables the symbol clear")
    func symbolChipBackdrop() {
        let colors = SpaceColors(foreground: .white, background: .black, symbolBackground: .red)
        #expect(Self.rules(customColors: colors, symbol: "star.fill").showsSymbolClear)
        #expect(!Self.rules(symbol: "star.fill").showsSymbolClear)
    }

    @Test("a filled wrapping label backdrop enables the symbol clear")
    func symbolLabelBackdrop() {
        let rules = Self.rules(symbol: "star.fill", hasLabel: true, labelStyle: .pill, wrap: .inside)
        #expect(rules.showsSymbolClear)
        // Outline label shapes leave nothing to knock out of
        #expect(
            !Self.rules(symbol: "star.fill", hasLabel: true, labelStyle: .pillOutline, wrap: .inside)
                .showsSymbolClear
        )
        // Side-by-side layouts take the chip path instead
        #expect(
            !Self.rules(symbol: "star.fill", hasLabel: true, labelStyle: .pill, wrap: .outside)
                .showsSymbolClear
        )
        // A transparent label background removes the backdrop
        let clearBackground = SpaceColors(foreground: .white, background: .clear)
        #expect(
            !Self.rules(customColors: clearBackground, symbol: "star.fill", hasLabel: true, labelStyle: .pill)
                .showsSymbolClear
        )
    }

    @Test("a clear SF Symbol tint withholds the symbol background clear")
    func clearSymbolTint() {
        let colors = SpaceColors(foreground: .white, background: .black, symbol: .clear)
        #expect(!Self.rules(customColors: colors, symbol: "star.fill").showsSymbolBackgroundClear)
    }

    @Test("emoji ignore a stale clear symbol tint")
    func emojiIgnoresClearTint() {
        let colors = SpaceColors(foreground: .white, background: .black, symbol: .clear)
        #expect(Self.rules(customColors: colors, symbol: "😀").showsSymbolBackgroundClear)
    }

    // MARK: - Preference Loading

    @Test("loads a Space's stored preferences")
    func loadsFromStore() {
        let testSuite = TestSuiteFactory.createSuite()
        let store = DefaultsStore(suite: testSuite.suite)
        SpacePreferences.setSymbol("star.fill", forSpace: 2, display: nil, store: store)
        SpacePreferences.setLabel("Work", forSpace: 2, display: nil, store: store)
        SpacePreferences.setLabelStyle(.pillOutline, forSpace: 2, display: nil, store: store)
        SpacePreferences.setSymbolWrap(.outside, forSpace: 2, display: nil, store: store)

        let rules = ClearCellRules(forSpace: 2, display: nil, store: store)
        #expect(rules.symbol == "star.fill")
        #expect(rules.hasLabel)
        #expect(rules.labelStyle == .pillOutline)
        #expect(rules.wrap == .outside)

        let untouched = ClearCellRules(forSpace: 1, display: nil, store: store)
        #expect(untouched.symbol == nil)
        #expect(!untouched.hasLabel)
        TestSuiteFactory.destroySuite(testSuite)
    }
}
