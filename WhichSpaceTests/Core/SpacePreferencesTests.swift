import Defaults
import Testing
@testable import WhichSpace

@MainActor
struct SpacePreferencesTests {
    private let store: DefaultsStore
    private let testSuite: TestSuite

    init() {
        testSuite = TestSuiteFactory.createSuite()
        store = DefaultsStore(suite: testSuite.suite)
    }

    // MARK: - Decoded Value Cache

    @Test("cached reads reflect writes and external invalidation")
    func cachedValues_reflectWritesAndInvalidation() {
        SpacePreferences.setLabel("A", forSpace: 1, store: store)
        #expect(SpacePreferences.label(forSpace: 1, store: store) == "A")
        // Second read is served from the cache
        #expect(SpacePreferences.label(forSpace: 1, store: store) == "A")

        // A write bypassing the store is picked up after invalidation
        Defaults[KeySpecs.spaceLabels.key(suite: store.suite)] = [1: "B"]
        store.invalidateCachedValues()
        #expect(SpacePreferences.label(forSpace: 1, store: store) == "B")
    }

    @Test("separatorColor survives invalidation and a cold read")
    func separatorColor_survivesInvalidation() {
        store.separatorColor = .red
        store.invalidateCachedValues()
        #expect(store.separatorColor == .red)

        // A fresh store over the same suite reads the persisted value
        let cold = DefaultsStore(suite: testSuite.suite)
        #expect(cold.separatorColor == .red)
    }

    // MARK: - Colors Tests

    @Test("colors get returns nil when not set")
    func colorsGetReturnsNilWhenNotSet() {
        #expect(SpacePreferences.colors(forSpace: 1, store: store) == nil)
        #expect(SpacePreferences.colors(forSpace: 5, store: store) == nil)
    }

    @Test("colors set and get")
    func colorsSetAndGet() {
        let colors = SpaceColors(foreground: .red, background: .blue)
        SpacePreferences.setColors(colors, forSpace: 1, store: store)

        let retrieved = SpacePreferences.colors(forSpace: 1, store: store)
        #expect(retrieved != nil)
        #expect(retrieved?.foreground == colors.foreground)
        #expect(retrieved?.background == colors.background)
    }

    @Test("colors set nil removes")
    func colorsSetNilRemoves() {
        let colors = SpaceColors(foreground: .green, background: .yellow)
        SpacePreferences.setColors(colors, forSpace: 2, store: store)
        #expect(SpacePreferences.colors(forSpace: 2, store: store) != nil)

        SpacePreferences.setColors(nil, forSpace: 2, store: store)
        #expect(SpacePreferences.colors(forSpace: 2, store: store) == nil)
    }

    @Test("colors clear")
    func colorsClear() {
        let colors = SpaceColors(foreground: .cyan, background: .magenta)
        SpacePreferences.setColors(colors, forSpace: 3, store: store)
        #expect(SpacePreferences.colors(forSpace: 3, store: store) != nil)

        SpacePreferences.clearColors(forSpace: 3, store: store)
        #expect(SpacePreferences.colors(forSpace: 3, store: store) == nil)
    }

    @Test("colors multiple spaces")
    func colorsMultipleSpaces() {
        let colors1 = SpaceColors(foreground: .red, background: .white)
        let colors2 = SpaceColors(foreground: .blue, background: .black)

        SpacePreferences.setColors(colors1, forSpace: 1, store: store)
        SpacePreferences.setColors(colors2, forSpace: 2, store: store)

        #expect(SpacePreferences.colors(forSpace: 1, store: store)?.foreground == .red)
        #expect(SpacePreferences.colors(forSpace: 2, store: store)?.foreground == .blue)
    }

    // MARK: - Icon Style Tests

    @Test("icon style get returns nil when not set")
    func iconStyleGetReturnsNilWhenNotSet() {
        #expect(SpacePreferences.iconStyle(forSpace: 1, store: store) == nil)
        #expect(SpacePreferences.iconStyle(forSpace: 5, store: store) == nil)
    }

    @Test("icon style set and get")
    func iconStyleSetAndGet() {
        SpacePreferences.setIconStyle(.circle, forSpace: 1, store: store)
        #expect(SpacePreferences.iconStyle(forSpace: 1, store: store) == .circle)
    }

    @Test("icon style set nil removes")
    func iconStyleSetNilRemoves() {
        SpacePreferences.setIconStyle(.hexagon, forSpace: 2, store: store)
        #expect(SpacePreferences.iconStyle(forSpace: 2, store: store) == .hexagon)

        SpacePreferences.setIconStyle(nil, forSpace: 2, store: store)
        #expect(SpacePreferences.iconStyle(forSpace: 2, store: store) == nil)
    }

    @Test("icon style clear")
    func iconStyleClear() {
        SpacePreferences.setIconStyle(.triangle, forSpace: 3, store: store)
        #expect(SpacePreferences.iconStyle(forSpace: 3, store: store) == .triangle)

        SpacePreferences.clearIconStyle(forSpace: 3, store: store)
        #expect(SpacePreferences.iconStyle(forSpace: 3, store: store) == nil)
    }

    @Test("icon style all cases")
    func iconStyleAllCases() {
        for (index, style) in IconStyle.allCases.enumerated() {
            SpacePreferences.setIconStyle(style, forSpace: index, store: store)
            #expect(SpacePreferences.iconStyle(forSpace: index, store: store) == style)
        }
    }

    // MARK: - Symbol Tests

    @Test("symbol get returns nil when not set")
    func symbolGetReturnsNilWhenNotSet() {
        #expect(SpacePreferences.symbol(forSpace: 1, store: store) == nil)
        #expect(SpacePreferences.symbol(forSpace: 5, store: store) == nil)
    }

    @Test("symbol set and get")
    func symbolSetAndGet() {
        SpacePreferences.setSymbol("star.fill", forSpace: 1, store: store)
        #expect(SpacePreferences.symbol(forSpace: 1, store: store) == "star.fill")
    }

    @Test("symbol set nil removes")
    func symbolSetNilRemoves() {
        SpacePreferences.setSymbol("heart.fill", forSpace: 2, store: store)
        #expect(SpacePreferences.symbol(forSpace: 2, store: store) == "heart.fill")

        SpacePreferences.setSymbol(nil, forSpace: 2, store: store)
        #expect(SpacePreferences.symbol(forSpace: 2, store: store) == nil)
    }

    @Test("symbol clear")
    func symbolClear() {
        SpacePreferences.setSymbol("moon.fill", forSpace: 3, store: store)
        #expect(SpacePreferences.symbol(forSpace: 3, store: store) == "moon.fill")

        SpacePreferences.clearSymbol(forSpace: 3, store: store)
        #expect(SpacePreferences.symbol(forSpace: 3, store: store) == nil)
    }

    @Test("symbol multiple spaces")
    func symbolMultipleSpaces() {
        SpacePreferences.setSymbol("1.circle", forSpace: 1, store: store)
        SpacePreferences.setSymbol("2.circle", forSpace: 2, store: store)
        SpacePreferences.setSymbol("3.circle", forSpace: 3, store: store)

        #expect(SpacePreferences.symbol(forSpace: 1, store: store) == "1.circle")
        #expect(SpacePreferences.symbol(forSpace: 2, store: store) == "2.circle")
        #expect(SpacePreferences.symbol(forSpace: 3, store: store) == "3.circle")
    }

    // MARK: - Badge Tests

    @Test("badge get returns nil when not set")
    func badgeGetReturnsNilWhenNotSet() {
        #expect(SpacePreferences.badge(forSpace: 1, store: store) == nil)
        #expect(SpacePreferences.badge(forSpace: 5, store: store) == nil)
    }

    @Test("badge set and get")
    func badgeSetAndGet() {
        let badge = SpaceBadge(character: "A", position: .topRight)
        SpacePreferences.setBadge(badge, forSpace: 1, store: store)

        let retrieved = SpacePreferences.badge(forSpace: 1, store: store)
        #expect(retrieved != nil)
        #expect(retrieved?.character == "A")
        #expect(retrieved?.position == .topRight)
    }

    @Test("badge set nil removes")
    func badgeSetNilRemoves() {
        let badge = SpaceBadge(character: "B", position: .bottomLeft)
        SpacePreferences.setBadge(badge, forSpace: 2, store: store)
        #expect(SpacePreferences.badge(forSpace: 2, store: store) != nil)

        SpacePreferences.setBadge(nil, forSpace: 2, store: store)
        #expect(SpacePreferences.badge(forSpace: 2, store: store) == nil)
    }

    @Test("badge clear")
    func badgeClear() {
        let badge = SpaceBadge(character: "C", position: .topLeft)
        SpacePreferences.setBadge(badge, forSpace: 3, store: store)
        #expect(SpacePreferences.badge(forSpace: 3, store: store) != nil)

        SpacePreferences.clearBadge(forSpace: 3, store: store)
        #expect(SpacePreferences.badge(forSpace: 3, store: store) == nil)
    }

    @Test("badge multiple spaces")
    func badgeMultipleSpaces() {
        SpacePreferences.setBadge(SpaceBadge(character: "1", position: .topLeft), forSpace: 1, store: store)
        SpacePreferences.setBadge(SpaceBadge(character: "2", position: .topRight), forSpace: 2, store: store)

        #expect(SpacePreferences.badge(forSpace: 1, store: store)?.character == "1")
        #expect(SpacePreferences.badge(forSpace: 2, store: store)?.character == "2")
    }

    @Test("badges scoped per display")
    func badgePerDisplay() {
        let display1 = "Display1"
        let display2 = "Display2"

        SpacePreferences.setBadge(
            SpaceBadge(character: "A", position: .topLeft),
            forSpace: 1,
            display: display1,
            store: store
        )
        SpacePreferences.setBadge(
            SpaceBadge(character: "B", position: .bottomRight),
            forSpace: 1,
            display: display2,
            store: store
        )

        #expect(SpacePreferences.badge(forSpace: 1, display: display1, store: store)?.character == "A")
        #expect(SpacePreferences.badge(forSpace: 1, display: display2, store: store)?.character == "B")
    }

    // MARK: - Cross-Preference Tests

    @Test("different preferences are independent")
    func differentPreferencesAreIndependent() {
        let colors = SpaceColors(foreground: .red, background: .blue)
        SpacePreferences.setColors(colors, forSpace: 1, store: store)
        SpacePreferences.setIconStyle(.circle, forSpace: 1, store: store)
        SpacePreferences.setSymbol("star", forSpace: 1, store: store)

        // Clear one, others should remain
        SpacePreferences.clearColors(forSpace: 1, store: store)

        #expect(SpacePreferences.colors(forSpace: 1, store: store) == nil)
        #expect(SpacePreferences.iconStyle(forSpace: 1, store: store) == .circle)
        #expect(SpacePreferences.symbol(forSpace: 1, store: store) == "star")
    }

    // MARK: - Per-Display Tests

    @Test("display overrides win over shared values")
    func overrideWinsOverShared() {
        SpacePreferences.setSymbol("shared", forSpace: 1, store: store)
        SpacePreferences.setSymbol("override", forSpace: 1, display: "Display1", store: store)

        #expect(SpacePreferences.symbol(forSpace: 1, store: store) == "shared")
        #expect(SpacePreferences.symbol(forSpace: 1, display: "Display1", store: store) == "override")

        // A display without an override shows the shared value through
        #expect(SpacePreferences.symbol(forSpace: 1, display: "Display2", store: store) == "shared")

        // Clearing the override reveals the shared value again
        SpacePreferences.setSymbol(nil, forSpace: 1, display: "Display1", store: store)
        #expect(SpacePreferences.symbol(forSpace: 1, display: "Display1", store: store) == "shared")
    }

    @Test("scoped writes land in their own storage family")
    func scopedWritesAreIndependent() {
        SpacePreferences.setIconStyle(.square, forSpace: 1, store: store)
        SpacePreferences.setIconStyle(.circle, forSpace: 1, display: "Display1", store: store)

        #expect(store.spaceIconStyles[1] == .square)
        #expect(store.displaySpaceIconStyles["Display1"]?[1] == .circle)
        #expect(SpacePreferences.iconStyle(forSpace: 1, store: store) == .square)
        #expect(SpacePreferences.iconStyle(forSpace: 1, display: "Display1", store: store) == .circle)
    }

    @Test("displays hold independent overrides")
    func perDisplayPreferences() {
        let display1 = "Display1"
        let display2 = "Display2"

        // Set different preferences for each display
        SpacePreferences.setColors(
            SpaceColors(foreground: .red, background: .blue),
            forSpace: 1,
            display: display1,
            store: store
        )
        SpacePreferences.setIconStyle(.circle, forSpace: 1, display: display1, store: store)

        SpacePreferences.setColors(
            SpaceColors(foreground: .green, background: .yellow),
            forSpace: 1,
            display: display2,
            store: store
        )
        SpacePreferences.setIconStyle(.hexagon, forSpace: 1, display: display2, store: store)

        // Display1 should have its own settings
        let colors1 = SpacePreferences.colors(forSpace: 1, display: display1, store: store)
        #expect(colors1?.foreground == .red)
        #expect(SpacePreferences.iconStyle(forSpace: 1, display: display1, store: store) == .circle)

        // Display2 should have its own settings
        let colors2 = SpacePreferences.colors(forSpace: 1, display: display2, store: store)
        #expect(colors2?.foreground == .green)
        #expect(SpacePreferences.iconStyle(forSpace: 1, display: display2, store: store) == .hexagon)
    }

    @Test("empty-string override blocks shared and template values")
    func emptyOverrideBlocksCascade() {
        SpacePreferences.setLabel("T", forSpace: SpacePreferences.defaultStyleSpace, store: store)
        SpacePreferences.setLabel("Shared", forSpace: 1, store: store)
        SpacePreferences.setLabel("", forSpace: 1, display: "Display1", store: store)

        // The label getter maps the empty sentinel to nil instead of
        // falling through to the shared or template value
        #expect(SpacePreferences.label(forSpace: 1, display: "Display1", store: store) == nil)
        #expect(SpacePreferences.label(forSpace: 1, display: "Display2", store: store) == "Shared")
        #expect(SpacePreferences.label(forSpace: 2, display: "Display1", store: store) == "T")
    }

    @Test("clear all clears everything")
    func clearAllClearsEverything() {
        // Set up both shared and per-display preferences
        SpacePreferences.setIconStyle(.square, forSpace: 1, store: store)
        SpacePreferences.setColors(SpaceColors(foreground: .red, background: .blue), forSpace: 1, store: store)
        SpacePreferences.setIconStyle(.circle, forSpace: 1, display: "Display1", store: store)
        SpacePreferences.setIconStyle(.triangle, forSpace: 1, display: "Display2", store: store)

        // Clear everything
        SpacePreferences.clearAll(store: store)

        #expect(SpacePreferences.iconStyle(forSpace: 1, display: "Display1", store: store) == nil)
        #expect(SpacePreferences.iconStyle(forSpace: 1, display: "Display2", store: store) == nil)
        #expect(SpacePreferences.iconStyle(forSpace: 1, store: store) == nil)
        #expect(SpacePreferences.colors(forSpace: 1, store: store) == nil)
    }

    // MARK: - hasAnyPreference Tests

    @Test("hasAnyPreference returns false when nothing set")
    func hasAnyPreferenceReturnsFalseWhenNothingSet() {
        #expect(!SpacePreferences.hasAnyPreference(forSpace: 1, store: store))
    }

    @Test("hasAnyPreference returns true when colors set")
    func hasAnyPreferenceReturnsTrueWhenColorsSet() {
        SpacePreferences.setColors(SpaceColors(foreground: .red, background: .blue), forSpace: 1, store: store)
        #expect(SpacePreferences.hasAnyPreference(forSpace: 1, store: store))
    }

    @Test("hasAnyPreference returns true when icon style set")
    func hasAnyPreferenceReturnsTrueWhenIconStyleSet() {
        SpacePreferences.setIconStyle(.circle, forSpace: 1, store: store)
        #expect(SpacePreferences.hasAnyPreference(forSpace: 1, store: store))
    }

    @Test("hasAnyPreference returns true when symbol set")
    func hasAnyPreferenceReturnsTrueWhenSymbolSet() {
        SpacePreferences.setSymbol("star", forSpace: 1, store: store)
        #expect(SpacePreferences.hasAnyPreference(forSpace: 1, store: store))
    }

    @Test("hasAnyPreference returns true when badge set")
    func hasAnyPreferenceReturnsTrueWhenBadgeSet() {
        SpacePreferences.setBadge(SpaceBadge(character: "A", position: .topRight), forSpace: 1, store: store)
        #expect(SpacePreferences.hasAnyPreference(forSpace: 1, store: store))
    }

    @Test("hasAnyPreference returns true when label set")
    func hasAnyPreferenceReturnsTrueWhenLabelSet() {
        SpacePreferences.setLabel("Work", forSpace: 1, store: store)
        #expect(SpacePreferences.hasAnyPreference(forSpace: 1, store: store))
    }

    @Test("hasAnyPreference sees overrides on their own display only")
    func hasAnyPreferenceChecksPerDisplay() {
        SpacePreferences.setIconStyle(.circle, forSpace: 1, display: "Display1", store: store)

        #expect(SpacePreferences.hasAnyPreference(forSpace: 1, display: "Display1", store: store))
        #expect(!SpacePreferences.hasAnyPreference(forSpace: 1, display: "Display2", store: store))
    }

    // MARK: - copyPreferences Tests

    @Test("copyPreferences copies all set preferences")
    func copyPreferencesCopiesAllSetPreferences() {
        let colors = SpaceColors(foreground: .red, background: .blue)
        SpacePreferences.setColors(colors, forSpace: 1, store: store)
        SpacePreferences.setIconStyle(.circle, forSpace: 1, store: store)
        SpacePreferences.setSymbol("star", forSpace: 1, store: store)
        SpacePreferences.setBadge(SpaceBadge(character: "A", position: .topRight), forSpace: 1, store: store)
        SpacePreferences.setLabel("Work", forSpace: 1, store: store)
        SpacePreferences.setLabelStyle(.pill, forSpace: 1, store: store)

        SpacePreferences.copyPreferences(from: 1, to: 2, store: store)

        #expect(SpacePreferences.colors(forSpace: 2, store: store)?.foreground == .red)
        #expect(SpacePreferences.iconStyle(forSpace: 2, store: store) == .circle)
        #expect(SpacePreferences.symbol(forSpace: 2, store: store) == "star")
        #expect(SpacePreferences.badge(forSpace: 2, store: store)?.character == "A")
        #expect(SpacePreferences.label(forSpace: 2, store: store) == "Work")
        #expect(SpacePreferences.labelStyle(forSpace: 2, store: store) == .pill)
    }

    @Test("copyPreferences only copies preferences that exist on source")
    func copyPreferencesOnlyCopiesExistingPrefs() {
        // Only set colors on source
        SpacePreferences.setColors(SpaceColors(foreground: .red, background: .blue), forSpace: 1, store: store)

        SpacePreferences.copyPreferences(from: 1, to: 2, store: store)

        #expect(SpacePreferences.colors(forSpace: 2, store: store) != nil)
        #expect(SpacePreferences.iconStyle(forSpace: 2, store: store) == nil)
        #expect(SpacePreferences.symbol(forSpace: 2, store: store) == nil)
    }

    @Test("copyPreferences does not overwrite existing target preferences")
    func copyPreferencesDoesNotOverwriteExisting() {
        // Source has circle style
        SpacePreferences.setIconStyle(.circle, forSpace: 1, store: store)
        SpacePreferences.setColors(SpaceColors(foreground: .red, background: .blue), forSpace: 1, store: store)

        // Target already has hexagon style
        SpacePreferences.setIconStyle(.hexagon, forSpace: 2, store: store)

        // copyPreferences copies all source prefs (including style) - the guard is in the caller
        SpacePreferences.copyPreferences(from: 1, to: 2, store: store)

        // copyPreferences overwrites - it's the caller's job to check hasAnyPreference first
        #expect(SpacePreferences.iconStyle(forSpace: 2, store: store) == .circle)
        #expect(SpacePreferences.colors(forSpace: 2, store: store)?.foreground == .red)
    }

    @Test("copyPreferences copies within a display scope")
    func copyPreferencesRespectsPerDisplay() {
        SpacePreferences.setIconStyle(.circle, forSpace: 1, display: "Display1", store: store)
        SpacePreferences.copyPreferences(from: 1, to: 2, display: "Display1", store: store)

        #expect(SpacePreferences.iconStyle(forSpace: 2, display: "Display1", store: store) == .circle)
        // Other display should be unaffected
        #expect(SpacePreferences.iconStyle(forSpace: 2, display: "Display2", store: store) == nil)
    }

    @Test("nil display reads and writes shared storage")
    func perDisplayWithNilDisplayFallsBackToShared() {
        SpacePreferences.setIconStyle(.square, forSpace: 1, display: nil, store: store)

        #expect(SpacePreferences.iconStyle(forSpace: 1, display: nil, store: store) == .square)

        // Per-display storage should be empty
        #expect(store.displaySpaceIconStyles["SomeDisplay"]?[1] == nil)
    }

    // MARK: - Combined Symbol Layout Tests

    @Test("label and symbol can coexist")
    func labelAndSymbolCanCoexist() {
        SpacePreferences.setLabel("Work", forSpace: 2, store: store)
        SpacePreferences.setSymbol("star.fill", forSpace: 2, store: store)

        #expect(SpacePreferences.label(forSpace: 2, store: store) == "Work")
        #expect(SpacePreferences.symbol(forSpace: 2, store: store) == "star.fill")
    }

    @Test("symbol position set, get, and clear")
    func symbolPositionSetGetClear() {
        #expect(SpacePreferences.symbolPosition(forSpace: 2, store: store) == nil)

        SpacePreferences.setSymbolPosition(.right, forSpace: 2, store: store)
        #expect(SpacePreferences.symbolPosition(forSpace: 2, store: store) == .right)

        SpacePreferences.clearSymbolPosition(forSpace: 2, store: store)
        #expect(SpacePreferences.symbolPosition(forSpace: 2, store: store) == nil)
    }

    @Test("symbol wrap set, get, and clear")
    func symbolWrapSetGetClear() {
        #expect(SpacePreferences.symbolWrap(forSpace: 2, store: store) == nil)

        SpacePreferences.setSymbolWrap(.outside, forSpace: 2, store: store)
        #expect(SpacePreferences.symbolWrap(forSpace: 2, store: store) == .outside)

        SpacePreferences.clearSymbolWrap(forSpace: 2, store: store)
        #expect(SpacePreferences.symbolWrap(forSpace: 2, store: store) == nil)
    }

    @Test("symbol gap set, get, and clear")
    func symbolGapSetGetClear() {
        #expect(SpacePreferences.symbolGap(forSpace: 2, store: store) == nil)

        SpacePreferences.setSymbolGap(6.0, forSpace: 2, store: store)
        #expect(SpacePreferences.symbolGap(forSpace: 2, store: store) == 6.0)

        SpacePreferences.clearSymbolGap(forSpace: 2, store: store)
        #expect(SpacePreferences.symbolGap(forSpace: 2, store: store) == nil)
    }

    @Test("symbol layout preferences scope per display")
    func symbolLayoutRespectsPerDisplay() {
        SpacePreferences.setSymbolPosition(.right, forSpace: 1, display: "Display1", store: store)
        SpacePreferences.setSymbolWrap(.outside, forSpace: 1, display: "Display1", store: store)
        SpacePreferences.setSymbolGap(8.0, forSpace: 1, display: "Display1", store: store)

        #expect(SpacePreferences.symbolPosition(forSpace: 1, display: "Display1", store: store) == .right)
        #expect(SpacePreferences.symbolPosition(forSpace: 1, display: "Display2", store: store) == nil)
        #expect(SpacePreferences.symbolWrap(forSpace: 1, display: "Display2", store: store) == nil)
        #expect(SpacePreferences.symbolGap(forSpace: 1, display: "Display2", store: store) == nil)
    }

    @Test("hasAnyPreference sees symbol layout preferences")
    func hasAnyPreferenceSeesSymbolLayout() {
        #expect(!SpacePreferences.hasAnyPreference(forSpace: 4, store: store))

        SpacePreferences.setSymbolPosition(.right, forSpace: 4, store: store)
        #expect(SpacePreferences.hasAnyPreference(forSpace: 4, store: store))

        SpacePreferences.clearPreferences(forSpace: 4, store: store)
        #expect(!SpacePreferences.hasAnyPreference(forSpace: 4, store: store))

        SpacePreferences.setSymbolGap(5.0, forSpace: 4, store: store)
        #expect(SpacePreferences.hasAnyPreference(forSpace: 4, store: store))
    }

    @Test("copyPreferences copies symbol layout")
    func copyPreferencesCopiesSymbolLayout() {
        SpacePreferences.setSymbolPosition(.right, forSpace: 1, store: store)
        SpacePreferences.setSymbolWrap(.outside, forSpace: 1, store: store)
        SpacePreferences.setSymbolGap(7.0, forSpace: 1, store: store)

        SpacePreferences.copyPreferences(from: 1, to: 2, store: store)

        #expect(SpacePreferences.symbolPosition(forSpace: 2, store: store) == .right)
        #expect(SpacePreferences.symbolWrap(forSpace: 2, store: store) == .outside)
        #expect(SpacePreferences.symbolGap(forSpace: 2, store: store) == 7.0)
    }

    @Test("clearAll removes symbol layout preferences")
    func clearAllRemovesSymbolLayout() {
        SpacePreferences.setSymbolPosition(.right, forSpace: 1, store: store)
        SpacePreferences.setSymbolWrap(.outside, forSpace: 2, store: store)
        SpacePreferences.setSymbolGap(9.0, forSpace: 3, store: store)

        SpacePreferences.clearAll(store: store)

        #expect(SpacePreferences.symbolPosition(forSpace: 1, store: store) == nil)
        #expect(SpacePreferences.symbolWrap(forSpace: 2, store: store) == nil)
        #expect(SpacePreferences.symbolGap(forSpace: 3, store: store) == nil)
    }

    // MARK: - Symbol Color Tests

    @Test("symbol color stored independently of foreground")
    func symbolColorIndependentOfForeground() {
        SpacePreferences.setColors(
            SpaceColors(foreground: .red, background: .blue, symbol: .green),
            forSpace: 2,
            store: store
        )

        let colors = SpacePreferences.colors(forSpace: 2, store: store)
        #expect(colors?.foreground == .red)
        #expect(colors?.background == .blue)
        #expect(colors?.symbol == .green)
    }

    @Test("symbol color defaults to nil")
    func symbolColorDefaultsToNil() {
        SpacePreferences.setColors(
            SpaceColors(foreground: .red, background: .blue),
            forSpace: 2,
            store: store
        )

        #expect(SpacePreferences.colors(forSpace: 2, store: store)?.symbol == nil)
    }

    // MARK: - Sound Tests

    @Test("sound set, get, and clear")
    func soundSetGetClear() {
        #expect(SpacePreferences.sound(forSpace: 1, store: store) == nil)

        SpacePreferences.setSound("Pop", forSpace: 1, store: store)
        #expect(SpacePreferences.sound(forSpace: 1, store: store) == "Pop")

        SpacePreferences.setSound(nil, forSpace: 1, store: store)
        #expect(SpacePreferences.sound(forSpace: 1, store: store) == nil)

        SpacePreferences.setSound("Blow", forSpace: 2, store: store)
        SpacePreferences.clearSound(forSpace: 2, store: store)
        #expect(SpacePreferences.sound(forSpace: 2, store: store) == nil)
    }

    @Test("sounds scope per display")
    func soundPerDisplayWhenEnabled() {
        SpacePreferences.setSound("Pop", forSpace: 1, display: "Display1", store: store)
        SpacePreferences.setSound("Blow", forSpace: 1, display: "Display2", store: store)

        #expect(SpacePreferences.sound(forSpace: 1, display: "Display1", store: store) == "Pop")
        #expect(SpacePreferences.sound(forSpace: 1, display: "Display2", store: store) == "Blow")

        // Shared storage stays untouched
        #expect(store.spaceSounds[1] == nil)
    }

    @Test("hasAnyPreference returns true when sound set")
    func hasAnyPreferenceReturnsTrueWhenSoundSet() {
        SpacePreferences.setSound("Pop", forSpace: 1, store: store)
        #expect(SpacePreferences.hasAnyPreference(forSpace: 1, store: store))
    }

    @Test("copyPreferences copies sound unless excluded")
    func copyPreferencesCopiesSoundUnlessExcluded() {
        SpacePreferences.setSound("Pop", forSpace: 1, store: store)

        SpacePreferences.copyPreferences(from: 1, to: 2, store: store)
        #expect(SpacePreferences.sound(forSpace: 2, store: store) == "Pop")

        SpacePreferences.copyPreferences(from: 1, to: 3, includeSound: false, store: store)
        #expect(SpacePreferences.sound(forSpace: 3, store: store) == nil)
    }

    @Test("clearPreferences clears sound")
    func clearPreferencesClearsSound() {
        SpacePreferences.setSound("Pop", forSpace: 1, store: store)
        SpacePreferences.clearPreferences(forSpace: 1, store: store)
        #expect(SpacePreferences.sound(forSpace: 1, store: store) == nil)
    }

    @Test("clearAll removes shared and per-display sounds")
    func clearAllRemovesSounds() {
        SpacePreferences.setSound("Pop", forSpace: 1, store: store)
        SpacePreferences.setSound("Blow", forSpace: 1, display: "Display1", store: store)

        SpacePreferences.clearAll(store: store)

        #expect(SpacePreferences.sound(forSpace: 1, display: "Display1", store: store) == nil)
        #expect(SpacePreferences.sound(forSpace: 1, store: store) == nil)
    }

    @Test("default style template excludes sound")
    func defaultStyleTemplateExcludesSound() {
        SpacePreferences.setLabel("Work", forSpace: 1, store: store)
        SpacePreferences.setSound("Pop", forSpace: 1, store: store)

        SpacePreferences.saveDefaultStyle(fromSpace: 1, store: store)

        #expect(SpacePreferences.sound(forSpace: SpacePreferences.defaultStyleSpace, store: store) == nil)
        #expect(SpacePreferences.hasDefaultStyle(store: store))

        // A space with only a sound yields no template at all
        SpacePreferences.clearDefaultStyle(store: store)
        SpacePreferences.clearLabel(forSpace: 1, store: store)
        SpacePreferences.saveDefaultStyle(fromSpace: 1, store: store)
        #expect(!SpacePreferences.hasDefaultStyle(store: store))
    }

    @Test("resolvedSoundName override wins over global")
    func resolvedSoundNameOverrideWins() {
        store.soundName = "Glass"
        SpacePreferences.setSound("Pop", forSpace: 1, store: store)

        #expect(SpacePreferences.resolvedSoundName(forSpace: 1, store: store) == "Pop")
    }

    @Test("resolvedSoundName empty override silences despite global")
    func resolvedSoundNameEmptyOverrideSilences() {
        store.soundName = "Glass"
        SpacePreferences.setSound("", forSpace: 1, store: store)

        #expect(SpacePreferences.resolvedSoundName(forSpace: 1, store: store) == nil)
    }

    @Test("resolvedSoundName falls back to global when unset")
    func resolvedSoundNameFallsBackToGlobal() {
        store.soundName = "Glass"

        #expect(SpacePreferences.resolvedSoundName(forSpace: 1, store: store) == "Glass")
    }

    @Test("resolvedSoundName nil when nothing set")
    func resolvedSoundNameNilWhenNothingSet() {
        #expect(SpacePreferences.resolvedSoundName(forSpace: 1, store: store) == nil)
    }

    @Test("resolvedSoundName respects per-display override")
    func resolvedSoundNameRespectsPerDisplay() {
        store.soundName = "Glass"
        SpacePreferences.setSound("Pop", forSpace: 1, display: "Display1", store: store)

        #expect(SpacePreferences.resolvedSoundName(forSpace: 1, display: "Display1", store: store) == "Pop")
        #expect(SpacePreferences.resolvedSoundName(forSpace: 1, display: "Display2", store: store) == "Glass")
    }

    // MARK: - remapPositions Tests

    @Test("remapPositions moves shared values between positions")
    func remapPositionsMovesSharedValues() {
        SpacePreferences.setLabel("One", forSpace: 1, store: store)
        SpacePreferences.setLabel("Two", forSpace: 2, store: store)
        SpacePreferences.setSymbol("star", forSpace: 1, store: store)

        SpacePreferences.remapPositions([1: 2, 2: 1], display: "Main", includeShared: true, store: store)

        #expect(SpacePreferences.label(forSpace: 1, store: store) == "Two")
        #expect(SpacePreferences.label(forSpace: 2, store: store) == "One")
        #expect(SpacePreferences.symbol(forSpace: 2, store: store) == "star")
        #expect(SpacePreferences.symbol(forSpace: 1, store: store) == nil)
    }

    @Test("remapPositions moves every preference family")
    func remapPositionsMovesAllFamilies() {
        SpacePreferences.setColors(
            SpaceColors(foreground: .red, background: .blue), forSpace: 1, store: store
        )
        SpacePreferences.setIconStyle(.hexagon, forSpace: 1, store: store)
        SpacePreferences.setFont(SpaceFont(font: .systemFont(ofSize: 13)), forSpace: 1, store: store)
        SpacePreferences.setSymbol("star", forSpace: 1, store: store)
        SpacePreferences.setBadge(SpaceBadge(character: "!", position: .topLeft), forSpace: 1, store: store)
        SpacePreferences.setLabel("Work", forSpace: 1, store: store)
        SpacePreferences.setLabelStyle(.pill, forSpace: 1, store: store)
        SpacePreferences.setSkinTone(.medium, forSpace: 1, store: store)
        SpacePreferences.setSymbolGap(4.0, forSpace: 1, store: store)
        SpacePreferences.setSymbolPosition(.right, forSpace: 1, store: store)
        SpacePreferences.setSymbolWrap(.outside, forSpace: 1, store: store)
        SpacePreferences.setSound("Glass", forSpace: 1, store: store)

        SpacePreferences.remapPositions([1: 2, 2: 1], display: "Main", includeShared: true, store: store)

        #expect(SpacePreferences.colors(forSpace: 2, store: store)?.foreground == .red)
        #expect(SpacePreferences.iconStyle(forSpace: 2, store: store) == .hexagon)
        #expect(SpacePreferences.font(forSpace: 2, store: store)?.font == .systemFont(ofSize: 13))
        #expect(SpacePreferences.symbol(forSpace: 2, store: store) == "star")
        #expect(SpacePreferences.badge(forSpace: 2, store: store)?.character == "!")
        #expect(SpacePreferences.label(forSpace: 2, store: store) == "Work")
        #expect(SpacePreferences.labelStyle(forSpace: 2, store: store) == .pill)
        #expect(SpacePreferences.skinTone(forSpace: 2, store: store) == .medium)
        #expect(SpacePreferences.symbolGap(forSpace: 2, store: store) == 4.0)
        #expect(SpacePreferences.symbolPosition(forSpace: 2, store: store) == .right)
        #expect(SpacePreferences.symbolWrap(forSpace: 2, store: store) == .outside)
        #expect(SpacePreferences.sound(forSpace: 2, store: store) == "Glass")
        #expect(!SpacePreferences.hasAnyPreference(forSpace: 1, store: store))
    }

    @Test("remapPositions clears a destination whose source had no value")
    func remapPositionsClearsEmptySourceDestination() {
        SpacePreferences.setLabel("Two", forSpace: 2, store: store)

        SpacePreferences.remapPositions([1: 2, 2: 1], display: "Main", includeShared: true, store: store)

        #expect(SpacePreferences.label(forSpace: 1, store: store) == "Two")
        #expect(SpacePreferences.label(forSpace: 2, store: store) == nil)
    }

    @Test("remapPositions leaves shared maps alone when not included")
    func remapPositionsExcludesSharedWhenAsked() {
        SpacePreferences.setLabel("Shared", forSpace: 1, store: store)
        SpacePreferences.setLabel("Override", forSpace: 1, display: "Display1", store: store)

        SpacePreferences.remapPositions([1: 2, 2: 1], display: "Display1", includeShared: false, store: store)

        #expect(store.spaceLabels == [1: "Shared"])
        #expect(store.displaySpaceLabels["Display1"] == [2: "Override"])
    }

    @Test("remapPositions leaves the default style template untouched")
    func remapPositionsPreservesTemplate() {
        SpacePreferences.setLabel("Template", forSpace: SpacePreferences.defaultStyleSpace, store: store)
        SpacePreferences.setLabel("One", forSpace: 1, store: store)

        SpacePreferences.remapPositions([1: 2, 2: 1], display: "Main", includeShared: true, store: store)

        #expect(store.spaceLabels[SpacePreferences.defaultStyleSpace] == "Template")
        #expect(store.spaceLabels[2] == "One")
        #expect(store.spaceLabels[1] == nil)
    }
}
