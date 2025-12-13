import Defaults
import XCTest
@testable import WhichSpace

final class SpacePreferencesTests: IsolatedDefaultsTestCase {
    // MARK: - Colors Tests

    func testColorsGetReturnsNilWhenNotSet() {
        XCTAssertNil(SpacePreferences.colors(forSpace: 1, store: store))
        XCTAssertNil(SpacePreferences.colors(forSpace: 5, store: store))
    }

    func testColorsSetAndGet() {
        let colors = SpaceColors(foreground: .red, background: .blue)
        SpacePreferences.setColors(colors, forSpace: 1, store: store)

        let retrieved = SpacePreferences.colors(forSpace: 1, store: store)
        XCTAssertNotNil(retrieved)
        XCTAssertEqual(retrieved?.foreground, colors.foreground)
        XCTAssertEqual(retrieved?.background, colors.background)
    }

    func testColorsSetNilRemoves() {
        let colors = SpaceColors(foreground: .green, background: .yellow)
        SpacePreferences.setColors(colors, forSpace: 2, store: store)
        XCTAssertNotNil(SpacePreferences.colors(forSpace: 2, store: store))

        SpacePreferences.setColors(nil, forSpace: 2, store: store)
        XCTAssertNil(SpacePreferences.colors(forSpace: 2, store: store))
    }

    func testColorsClear() {
        let colors = SpaceColors(foreground: .cyan, background: .magenta)
        SpacePreferences.setColors(colors, forSpace: 3, store: store)
        XCTAssertNotNil(SpacePreferences.colors(forSpace: 3, store: store))

        SpacePreferences.clearColors(forSpace: 3, store: store)
        XCTAssertNil(SpacePreferences.colors(forSpace: 3, store: store))
    }

    func testColorsMultipleSpaces() {
        let colors1 = SpaceColors(foreground: .red, background: .white)
        let colors2 = SpaceColors(foreground: .blue, background: .black)

        SpacePreferences.setColors(colors1, forSpace: 1, store: store)
        SpacePreferences.setColors(colors2, forSpace: 2, store: store)

        XCTAssertEqual(SpacePreferences.colors(forSpace: 1, store: store)?.foreground, .red)
        XCTAssertEqual(SpacePreferences.colors(forSpace: 2, store: store)?.foreground, .blue)
    }

    // MARK: - Icon Style Tests

    func testIconStyleGetReturnsNilWhenNotSet() {
        XCTAssertNil(SpacePreferences.iconStyle(forSpace: 1, store: store))
        XCTAssertNil(SpacePreferences.iconStyle(forSpace: 5, store: store))
    }

    func testIconStyleSetAndGet() {
        SpacePreferences.setIconStyle(.circle, forSpace: 1, store: store)
        XCTAssertEqual(SpacePreferences.iconStyle(forSpace: 1, store: store), .circle)
    }

    func testIconStyleSetNilRemoves() {
        SpacePreferences.setIconStyle(.hexagon, forSpace: 2, store: store)
        XCTAssertEqual(SpacePreferences.iconStyle(forSpace: 2, store: store), .hexagon)

        SpacePreferences.setIconStyle(nil, forSpace: 2, store: store)
        XCTAssertNil(SpacePreferences.iconStyle(forSpace: 2, store: store))
    }

    func testIconStyleClear() {
        SpacePreferences.setIconStyle(.triangle, forSpace: 3, store: store)
        XCTAssertEqual(SpacePreferences.iconStyle(forSpace: 3, store: store), .triangle)

        SpacePreferences.clearIconStyle(forSpace: 3, store: store)
        XCTAssertNil(SpacePreferences.iconStyle(forSpace: 3, store: store))
    }

    func testIconStyleAllCases() {
        for (index, style) in IconStyle.allCases.enumerated() {
            SpacePreferences.setIconStyle(style, forSpace: index, store: store)
            XCTAssertEqual(SpacePreferences.iconStyle(forSpace: index, store: store), style)
        }
    }

    // MARK: - Symbol Tests

    func testSymbolGetReturnsNilWhenNotSet() {
        XCTAssertNil(SpacePreferences.symbol(forSpace: 1, store: store))
        XCTAssertNil(SpacePreferences.symbol(forSpace: 5, store: store))
    }

    func testSymbolSetAndGet() {
        SpacePreferences.setSymbol("star.fill", forSpace: 1, store: store)
        XCTAssertEqual(SpacePreferences.symbol(forSpace: 1, store: store), "star.fill")
    }

    func testSymbolSetNilRemoves() {
        SpacePreferences.setSymbol("heart.fill", forSpace: 2, store: store)
        XCTAssertEqual(SpacePreferences.symbol(forSpace: 2, store: store), "heart.fill")

        SpacePreferences.setSymbol(nil, forSpace: 2, store: store)
        XCTAssertNil(SpacePreferences.symbol(forSpace: 2, store: store))
    }

    func testSymbolClear() {
        SpacePreferences.setSymbol("moon.fill", forSpace: 3, store: store)
        XCTAssertEqual(SpacePreferences.symbol(forSpace: 3, store: store), "moon.fill")

        SpacePreferences.clearSymbol(forSpace: 3, store: store)
        XCTAssertNil(SpacePreferences.symbol(forSpace: 3, store: store))
    }

    func testSymbolMultipleSpaces() {
        SpacePreferences.setSymbol("1.circle", forSpace: 1, store: store)
        SpacePreferences.setSymbol("2.circle", forSpace: 2, store: store)
        SpacePreferences.setSymbol("3.circle", forSpace: 3, store: store)

        XCTAssertEqual(SpacePreferences.symbol(forSpace: 1, store: store), "1.circle")
        XCTAssertEqual(SpacePreferences.symbol(forSpace: 2, store: store), "2.circle")
        XCTAssertEqual(SpacePreferences.symbol(forSpace: 3, store: store), "3.circle")
    }

    // MARK: - Cross-Preference Tests

    func testDifferentPreferencesAreIndependent() {
        let colors = SpaceColors(foreground: .red, background: .blue)
        SpacePreferences.setColors(colors, forSpace: 1, store: store)
        SpacePreferences.setIconStyle(.circle, forSpace: 1, store: store)
        SpacePreferences.setSymbol("star", forSpace: 1, store: store)

        // Clear one, others should remain
        SpacePreferences.clearColors(forSpace: 1, store: store)

        XCTAssertNil(SpacePreferences.colors(forSpace: 1, store: store))
        XCTAssertEqual(SpacePreferences.iconStyle(forSpace: 1, store: store), .circle)
        XCTAssertEqual(SpacePreferences.symbol(forSpace: 1, store: store), "star")
    }

    // MARK: - Per-Display Tests

    func testSharedPreferencesWhenUniqueIconsDisabled() {
        // Default: uniqueIconsPerDisplay is false
        XCTAssertFalse(store.uniqueIconsPerDisplay)

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
        XCTAssertNotNil(SpacePreferences.colors(forSpace: 1, store: store))
        XCTAssertEqual(SpacePreferences.iconStyle(forSpace: 1, store: store), .circle)
        XCTAssertEqual(SpacePreferences.symbol(forSpace: 1, store: store), "star")

        // Same values accessible with any display ID (still uses shared storage)
        XCTAssertNotNil(SpacePreferences.colors(forSpace: 1, display: "Display2", store: store))
        XCTAssertEqual(SpacePreferences.iconStyle(forSpace: 1, display: "Display2", store: store), .circle)
        XCTAssertEqual(SpacePreferences.symbol(forSpace: 1, display: "Display2", store: store), "star")
    }

    func testPerDisplayPreferencesWhenEnabled() {
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
        XCTAssertEqual(colors1?.foreground, .red)
        XCTAssertEqual(SpacePreferences.iconStyle(forSpace: 1, display: display1, store: store), .circle)

        // Display2 should have its own settings
        let colors2 = SpacePreferences.colors(forSpace: 1, display: display2, store: store)
        XCTAssertEqual(colors2?.foreground, .green)
        XCTAssertEqual(SpacePreferences.iconStyle(forSpace: 1, display: display2, store: store), .hexagon)
    }

    func testTogglingPreservesSettings() {
        // Set shared preferences
        store.uniqueIconsPerDisplay = false
        SpacePreferences.setIconStyle(.square, forSpace: 1, store: store)

        // Enable per-display and set display-specific preferences
        store.uniqueIconsPerDisplay = true
        SpacePreferences.setIconStyle(.circle, forSpace: 1, display: "Display1", store: store)

        // Verify per-display setting
        XCTAssertEqual(SpacePreferences.iconStyle(forSpace: 1, display: "Display1", store: store), .circle)

        // Toggle back to shared - should get original shared value
        store.uniqueIconsPerDisplay = false
        XCTAssertEqual(SpacePreferences.iconStyle(forSpace: 1, store: store), .square)

        // Toggle to per-display again - should get per-display value back
        store.uniqueIconsPerDisplay = true
        XCTAssertEqual(SpacePreferences.iconStyle(forSpace: 1, display: "Display1", store: store), .circle)
    }

    func testClearAllClearsEverything() {
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
        XCTAssertNil(SpacePreferences.iconStyle(forSpace: 1, display: "Display1", store: store))
        XCTAssertNil(SpacePreferences.iconStyle(forSpace: 1, display: "Display2", store: store))

        // All shared settings should be cleared
        store.uniqueIconsPerDisplay = false
        XCTAssertNil(SpacePreferences.iconStyle(forSpace: 1, store: store))
        XCTAssertNil(SpacePreferences.colors(forSpace: 1, store: store))
    }

    func testPerDisplayWithNilDisplayFallsBackToShared() {
        store.uniqueIconsPerDisplay = true

        // Set shared preference (by passing nil display when enabled)
        // This should still use shared storage when display is nil
        SpacePreferences.setIconStyle(.square, forSpace: 1, display: nil, store: store)

        // Since display is nil even with uniqueIconsPerDisplay=true, should use shared
        XCTAssertEqual(SpacePreferences.iconStyle(forSpace: 1, display: nil, store: store), .square)

        // Per-display storage should be empty
        XCTAssertNil(store.displaySpaceIconStyles["SomeDisplay"]?[1])
    }
}
