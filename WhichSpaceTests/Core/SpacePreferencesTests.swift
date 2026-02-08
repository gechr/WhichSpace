import Defaults
import Testing
@testable import WhichSpace

@Suite("Space Preferences")
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
