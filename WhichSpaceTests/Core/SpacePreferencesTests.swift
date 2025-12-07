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

    // MARK: - SF Symbol Tests

    func testSFSymbolGetReturnsNilWhenNotSet() {
        XCTAssertNil(SpacePreferences.sfSymbol(forSpace: 1, store: store))
        XCTAssertNil(SpacePreferences.sfSymbol(forSpace: 5, store: store))
    }

    func testSFSymbolSetAndGet() {
        SpacePreferences.setSFSymbol("star.fill", forSpace: 1, store: store)
        XCTAssertEqual(SpacePreferences.sfSymbol(forSpace: 1, store: store), "star.fill")
    }

    func testSFSymbolSetNilRemoves() {
        SpacePreferences.setSFSymbol("heart.fill", forSpace: 2, store: store)
        XCTAssertEqual(SpacePreferences.sfSymbol(forSpace: 2, store: store), "heart.fill")

        SpacePreferences.setSFSymbol(nil, forSpace: 2, store: store)
        XCTAssertNil(SpacePreferences.sfSymbol(forSpace: 2, store: store))
    }

    func testSFSymbolClear() {
        SpacePreferences.setSFSymbol("moon.fill", forSpace: 3, store: store)
        XCTAssertEqual(SpacePreferences.sfSymbol(forSpace: 3, store: store), "moon.fill")

        SpacePreferences.clearSFSymbol(forSpace: 3, store: store)
        XCTAssertNil(SpacePreferences.sfSymbol(forSpace: 3, store: store))
    }

    func testSFSymbolMultipleSpaces() {
        SpacePreferences.setSFSymbol("1.circle", forSpace: 1, store: store)
        SpacePreferences.setSFSymbol("2.circle", forSpace: 2, store: store)
        SpacePreferences.setSFSymbol("3.circle", forSpace: 3, store: store)

        XCTAssertEqual(SpacePreferences.sfSymbol(forSpace: 1, store: store), "1.circle")
        XCTAssertEqual(SpacePreferences.sfSymbol(forSpace: 2, store: store), "2.circle")
        XCTAssertEqual(SpacePreferences.sfSymbol(forSpace: 3, store: store), "3.circle")
    }

    // MARK: - Cross-Preference Tests

    func testDifferentPreferencesAreIndependent() {
        let colors = SpaceColors(foreground: .red, background: .blue)
        SpacePreferences.setColors(colors, forSpace: 1, store: store)
        SpacePreferences.setIconStyle(.circle, forSpace: 1, store: store)
        SpacePreferences.setSFSymbol("star", forSpace: 1, store: store)

        // Clear one, others should remain
        SpacePreferences.clearColors(forSpace: 1, store: store)

        XCTAssertNil(SpacePreferences.colors(forSpace: 1, store: store))
        XCTAssertEqual(SpacePreferences.iconStyle(forSpace: 1, store: store), .circle)
        XCTAssertEqual(SpacePreferences.sfSymbol(forSpace: 1, store: store), "star")
    }
}
