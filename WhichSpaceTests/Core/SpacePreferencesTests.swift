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

    @Test("badge per-display when enabled")
    func badgePerDisplayWhenEnabled() {
        store.uniqueIconsPerDisplay = true

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

    @Test("shared preferences when unique icons disabled")
    func sharedPreferencesWhenUniqueIconsDisabled() {
        // Default: uniqueIconsPerDisplay is false
        #expect(!store.uniqueIconsPerDisplay)

        // Set preferences with a display ID - should use shared storage
        SpacePreferences.setColors(
            SpaceColors(foreground: .red, background: .blue),
            forSpace: 1,
            display: "Display1",
            store: store
        )
        SpacePreferences.setIconStyle(.circle, forSpace: 1, display: "Display1", store: store)
        SpacePreferences.setSymbol("star", forSpace: 1, display: "Display1", store: store)

        // Should be stored in shared storage, accessible without display ID
        #expect(SpacePreferences.colors(forSpace: 1, store: store) != nil)
        #expect(SpacePreferences.iconStyle(forSpace: 1, store: store) == .circle)
        #expect(SpacePreferences.symbol(forSpace: 1, store: store) == "star")

        // Same values accessible with any display ID (still uses shared storage)
        #expect(SpacePreferences.colors(forSpace: 1, display: "Display2", store: store) != nil)
        #expect(SpacePreferences.iconStyle(forSpace: 1, display: "Display2", store: store) == .circle)
        #expect(SpacePreferences.symbol(forSpace: 1, display: "Display2", store: store) == "star")
    }

    @Test("per-display preferences when enabled")
    func perDisplayPreferencesWhenEnabled() {
        store.uniqueIconsPerDisplay = true

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

    @Test("toggling preserves settings")
    func togglingPreservesSettings() {
        // Set shared preferences
        store.uniqueIconsPerDisplay = false
        SpacePreferences.setIconStyle(.square, forSpace: 1, store: store)

        // Enable per-display and set display-specific preferences
        store.uniqueIconsPerDisplay = true
        SpacePreferences.setIconStyle(.circle, forSpace: 1, display: "Display1", store: store)

        // Verify per-display setting
        #expect(SpacePreferences.iconStyle(forSpace: 1, display: "Display1", store: store) == .circle)

        // Toggle back to shared - should get original shared value
        store.uniqueIconsPerDisplay = false
        #expect(SpacePreferences.iconStyle(forSpace: 1, store: store) == .square)

        // Toggle to per-display again - should get per-display value back
        store.uniqueIconsPerDisplay = true
        #expect(SpacePreferences.iconStyle(forSpace: 1, display: "Display1", store: store) == .circle)
    }

    @Test("clear all clears everything")
    func clearAllClearsEverything() {
        // Set up both shared and per-display preferences
        store.uniqueIconsPerDisplay = false
        SpacePreferences.setIconStyle(.square, forSpace: 1, store: store)
        SpacePreferences.setColors(SpaceColors(foreground: .red, background: .blue), forSpace: 1, store: store)

        store.uniqueIconsPerDisplay = true
        SpacePreferences.setIconStyle(.circle, forSpace: 1, display: "Display1", store: store)
        SpacePreferences.setIconStyle(.triangle, forSpace: 1, display: "Display2", store: store)

        // Clear everything
        SpacePreferences.clearAll(store: store)

        // All per-display settings should be cleared
        #expect(SpacePreferences.iconStyle(forSpace: 1, display: "Display1", store: store) == nil)
        #expect(SpacePreferences.iconStyle(forSpace: 1, display: "Display2", store: store) == nil)

        // All shared settings should be cleared
        store.uniqueIconsPerDisplay = false
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

    @Test("hasAnyPreference checks per-display when enabled")
    func hasAnyPreferenceChecksPerDisplay() {
        store.uniqueIconsPerDisplay = true
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
        SpacePreferences.setLabelStyle(.rounded, forSpace: 1, store: store)

        SpacePreferences.copyPreferences(from: 1, to: 2, store: store)

        #expect(SpacePreferences.colors(forSpace: 2, store: store)?.foreground == .red)
        #expect(SpacePreferences.iconStyle(forSpace: 2, store: store) == .circle)
        #expect(SpacePreferences.symbol(forSpace: 2, store: store) == "star")
        #expect(SpacePreferences.badge(forSpace: 2, store: store)?.character == "A")
        #expect(SpacePreferences.label(forSpace: 2, store: store) == "Work")
        #expect(SpacePreferences.labelStyle(forSpace: 2, store: store) == .rounded)
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

    @Test("copyPreferences respects per-display mode")
    func copyPreferencesRespectsPerDisplay() {
        store.uniqueIconsPerDisplay = true

        SpacePreferences.setIconStyle(.circle, forSpace: 1, display: "Display1", store: store)
        SpacePreferences.copyPreferences(from: 1, to: 2, display: "Display1", store: store)

        #expect(SpacePreferences.iconStyle(forSpace: 2, display: "Display1", store: store) == .circle)
        // Other display should be unaffected
        #expect(SpacePreferences.iconStyle(forSpace: 2, display: "Display2", store: store) == nil)
    }

    @Test("per-display with nil display falls back to shared")
    func perDisplayWithNilDisplayFallsBackToShared() {
        store.uniqueIconsPerDisplay = true

        // Set shared preference (by passing nil display when enabled)
        // This should still use shared storage when display is nil
        SpacePreferences.setIconStyle(.square, forSpace: 1, display: nil, store: store)

        // Since display is nil even with uniqueIconsPerDisplay=true, should use shared
        #expect(SpacePreferences.iconStyle(forSpace: 1, display: nil, store: store) == .square)

        // Per-display storage should be empty
        #expect(store.displaySpaceIconStyles["SomeDisplay"]?[1] == nil)
    }
}
