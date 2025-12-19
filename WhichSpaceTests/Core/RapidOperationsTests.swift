import Cocoa
import Defaults
import XCTest
@testable import WhichSpace

// MARK: - Rapid Operations Tests

final class RapidOperationsTests: IsolatedDefaultsTestCase {
    // MARK: - Rapid Preference Changes

    func testRapidColorChanges() {
        // Rapidly change colors many times
        for idx in 0 ..< 100 {
            let colors = SpaceColors(
                foreground: NSColor(calibratedHue: Double(idx) / 100.0, saturation: 1, brightness: 1, alpha: 1),
                background: NSColor(calibratedHue: Double(99 - idx) / 100.0, saturation: 1, brightness: 1, alpha: 1)
            )
            SpacePreferences.setColors(colors, forSpace: 1, store: store)
        }

        // Final state should be last set value
        let final = SpacePreferences.colors(forSpace: 1, store: store)
        XCTAssertNotNil(final)
    }

    func testRapidStyleChanges() {
        // Rapidly cycle through all styles
        for _ in 0 ..< 50 {
            for style in IconStyle.allCases {
                SpacePreferences.setIconStyle(style, forSpace: 1, store: store)
            }
        }

        // Should end on last style
        XCTAssertEqual(SpacePreferences.iconStyle(forSpace: 1, store: store), IconStyle.allCases.last)
    }

    func testRapidSymbolChanges() {
        let symbols = ItemData.symbols
        for _ in 0 ..< 20 {
            for symbol in symbols.prefix(50) {
                SpacePreferences.setSymbol(symbol, forSpace: 1, store: store)
            }
        }

        // Should not crash and have valid state
        XCTAssertNotNil(SpacePreferences.symbol(forSpace: 1, store: store))
    }

    // MARK: - Rapid Toggle Operations

    func testRapidUniqueIconsPerDisplayToggle() {
        for _ in 0 ..< 100 {
            store.uniqueIconsPerDisplay = true
            SpacePreferences.setIconStyle(.circle, forSpace: 1, display: "Display1", store: store)

            store.uniqueIconsPerDisplay = false
            SpacePreferences.setIconStyle(.square, forSpace: 1, store: store)
        }

        // Both storage locations should have values
        store.uniqueIconsPerDisplay = true
        XCTAssertEqual(SpacePreferences.iconStyle(forSpace: 1, display: "Display1", store: store), .circle)

        store.uniqueIconsPerDisplay = false
        XCTAssertEqual(SpacePreferences.iconStyle(forSpace: 1, store: store), .square)
    }

    // MARK: - Concurrent-Like Access Patterns

    func testManySpacesSimultaneously() {
        // Set preferences for many spaces at once
        for space in 1 ... 100 {
            SpacePreferences.setIconStyle(.circle, forSpace: space, store: store)
            SpacePreferences.setSymbol("star.fill", forSpace: space, store: store)
            SpacePreferences.setColors(
                SpaceColors(foreground: .red, background: .blue),
                forSpace: space,
                store: store
            )
        }

        // Verify all were set
        for space in 1 ... 100 {
            XCTAssertEqual(SpacePreferences.iconStyle(forSpace: space, store: store), .circle)
            XCTAssertEqual(SpacePreferences.symbol(forSpace: space, store: store), "star.fill")
            XCTAssertNotNil(SpacePreferences.colors(forSpace: space, store: store))
        }
    }

    func testManyDisplaysSimultaneously() {
        store.uniqueIconsPerDisplay = true

        // Set preferences for many displays
        for displayNum in 1 ... 20 {
            let displayID = "Display\(displayNum)"
            for space in 1 ... 10 {
                SpacePreferences.setIconStyle(.hexagon, forSpace: space, display: displayID, store: store)
            }
        }

        // Verify all were set
        for displayNum in 1 ... 20 {
            let displayID = "Display\(displayNum)"
            for space in 1 ... 10 {
                XCTAssertEqual(
                    SpacePreferences.iconStyle(forSpace: space, display: displayID, store: store),
                    .hexagon
                )
            }
        }
    }

    // MARK: - Clear All Under Load

    func testClearAllWithManyPreferences() {
        // Set up many preferences
        for space in 1 ... 50 {
            SpacePreferences.setIconStyle(.circle, forSpace: space, store: store)
            SpacePreferences.setSymbol("star", forSpace: space, store: store)
            SpacePreferences.setColors(
                SpaceColors(foreground: .red, background: .blue),
                forSpace: space,
                store: store
            )
        }

        store.uniqueIconsPerDisplay = true
        for displayNum in 1 ... 5 {
            let displayID = "Display\(displayNum)"
            for space in 1 ... 10 {
                SpacePreferences.setIconStyle(.square, forSpace: space, display: displayID, store: store)
            }
        }

        // Clear all at once
        SpacePreferences.clearAll(store: store)

        // Verify everything is cleared
        for space in 1 ... 50 {
            XCTAssertNil(SpacePreferences.iconStyle(forSpace: space, store: store))
            XCTAssertNil(SpacePreferences.symbol(forSpace: space, store: store))
            XCTAssertNil(SpacePreferences.colors(forSpace: space, store: store))
        }

        for displayNum in 1 ... 5 {
            let displayID = "Display\(displayNum)"
            for space in 1 ... 10 {
                XCTAssertNil(SpacePreferences.iconStyle(forSpace: space, display: displayID, store: store))
            }
        }
    }

    // MARK: - Icon Generation Under Load

    func testRapidIconGeneration() {
        // Generate many icons rapidly
        for _ in 0 ..< 100 {
            for style in IconStyle.allCases {
                let image = SpaceIconGenerator.generateIcon(
                    for: "1",
                    darkMode: false,
                    customColors: nil,
                    customFont: nil,
                    style: style
                )
                XCTAssertNotNil(image)
            }
        }
    }

    func testRapidSymbolIconGeneration() {
        let symbols = ["star.fill", "heart.fill", "circle.fill", "square.fill", "triangle.fill"]

        for _ in 0 ..< 50 {
            for symbol in symbols {
                let image = SpaceIconGenerator.generateSymbolIcon(
                    symbolName: symbol,
                    darkMode: false,
                    customColors: nil,
                    skinTone: nil
                )
                XCTAssertNotNil(image)
            }
        }
    }

    func testRapidEmojiIconGeneration() {
        let emojis = ["😀", "👋", "🎉", "❤️", "🌟"]

        for _ in 0 ..< 50 {
            for emoji in emojis {
                for tone in SkinTone.allCases {
                    let image = SpaceIconGenerator.generateSymbolIcon(
                        symbolName: emoji,
                        darkMode: false,
                        customColors: nil,
                        skinTone: tone
                    )
                    XCTAssertNotNil(image)
                }
            }
        }
    }
}
