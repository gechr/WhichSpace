import Cocoa
import Defaults
import XCTest
@testable import WhichSpace

// MARK: - Input Validation Tests

final class InputValidationTests: IsolatedDefaultsTestCase {
    // MARK: - Space Number Edge Cases

    func testSpaceNumberZero() {
        // Space 0 is often used as "unknown" state
        SpacePreferences.setIconStyle(.circle, forSpace: 0, store: store)
        XCTAssertEqual(SpacePreferences.iconStyle(forSpace: 0, store: store), .circle)

        SpacePreferences.clearIconStyle(forSpace: 0, store: store)
        XCTAssertNil(SpacePreferences.iconStyle(forSpace: 0, store: store))
    }

    func testNegativeSpaceNumber() {
        // Negative space numbers (edge case)
        SpacePreferences.setIconStyle(.square, forSpace: -1, store: store)
        XCTAssertEqual(SpacePreferences.iconStyle(forSpace: -1, store: store), .square)
    }

    func testVeryLargeSpaceNumber() {
        // Very large space numbers
        let largeNumber = Int.max - 1
        SpacePreferences.setSymbol("star", forSpace: largeNumber, store: store)
        XCTAssertEqual(SpacePreferences.symbol(forSpace: largeNumber, store: store), "star")
    }

    // MARK: - Symbol Name Edge Cases

    func testEmptySymbolName() {
        SpacePreferences.setSymbol("", forSpace: 1, store: store)
        XCTAssertEqual(SpacePreferences.symbol(forSpace: 1, store: store), "")
    }

    func testVeryLongSymbolName() {
        let longName = String(repeating: "a", count: 10_000)
        SpacePreferences.setSymbol(longName, forSpace: 1, store: store)
        XCTAssertEqual(SpacePreferences.symbol(forSpace: 1, store: store), longName)
    }

    func testSymbolNameWithSpecialCharacters() {
        let specialChars = "star.fill<>&\"'\n\t\0"
        SpacePreferences.setSymbol(specialChars, forSpace: 1, store: store)
        XCTAssertEqual(SpacePreferences.symbol(forSpace: 1, store: store), specialChars)
    }

    func testSymbolNameWithUnicodeNullCharacter() {
        let withNull = "star\u{0000}fill"
        SpacePreferences.setSymbol(withNull, forSpace: 1, store: store)
        XCTAssertEqual(SpacePreferences.symbol(forSpace: 1, store: store), withNull)
    }

    // MARK: - Display ID Edge Cases

    func testEmptyDisplayID() {
        store.uniqueIconsPerDisplay = true
        SpacePreferences.setIconStyle(.hexagon, forSpace: 1, display: "", store: store)
        XCTAssertEqual(SpacePreferences.iconStyle(forSpace: 1, display: "", store: store), .hexagon)
    }

    func testDisplayIDWithSpecialCharacters() {
        store.uniqueIconsPerDisplay = true
        let specialID = "Display<>\"'&\n\t"
        SpacePreferences.setIconStyle(.circle, forSpace: 1, display: specialID, store: store)
        XCTAssertEqual(SpacePreferences.iconStyle(forSpace: 1, display: specialID, store: store), .circle)
    }

    // MARK: - Color Edge Cases

    func testColorWithZeroAlpha() {
        let transparentColors = SpaceColors(
            foreground: NSColor(calibratedWhite: 0, alpha: 0),
            background: NSColor(calibratedWhite: 1, alpha: 0)
        )
        SpacePreferences.setColors(transparentColors, forSpace: 1, store: store)

        let retrieved = SpacePreferences.colors(forSpace: 1, store: store)
        XCTAssertNotNil(retrieved)
        XCTAssertEqual(retrieved?.foreground.alphaComponent, 0)
    }

    func testColorWithPartialAlpha() {
        let semiTransparent = SpaceColors(
            foreground: NSColor(calibratedWhite: 0.5, alpha: 0.5),
            background: NSColor(calibratedWhite: 0.5, alpha: 0.5)
        )
        SpacePreferences.setColors(semiTransparent, forSpace: 1, store: store)

        let retrieved = SpacePreferences.colors(forSpace: 1, store: store)
        XCTAssertEqual(Double(retrieved?.foreground.alphaComponent ?? 0), 0.5, accuracy: 0.01)
    }

    func testColorInDifferentColorSpaces() {
        // DeviceRGB
        let deviceRGB = SpaceColors(
            foreground: NSColor(deviceRed: 1, green: 0, blue: 0, alpha: 1),
            background: NSColor(deviceRed: 0, green: 0, blue: 1, alpha: 1)
        )
        SpacePreferences.setColors(deviceRGB, forSpace: 1, store: store)

        // GenericRGB
        let genericRGB = SpaceColors(
            foreground: NSColor(red: 1, green: 0, blue: 0, alpha: 1),
            background: NSColor(red: 0, green: 0, blue: 1, alpha: 1)
        )
        SpacePreferences.setColors(genericRGB, forSpace: 2, store: store)

        // Calibrated
        let calibrated = SpaceColors(
            foreground: NSColor(calibratedRed: 1, green: 0, blue: 0, alpha: 1),
            background: NSColor(calibratedRed: 0, green: 0, blue: 1, alpha: 1)
        )
        SpacePreferences.setColors(calibrated, forSpace: 3, store: store)

        // All should be retrievable
        XCTAssertNotNil(SpacePreferences.colors(forSpace: 1, store: store))
        XCTAssertNotNil(SpacePreferences.colors(forSpace: 2, store: store))
        XCTAssertNotNil(SpacePreferences.colors(forSpace: 3, store: store))
    }

    // MARK: - Skin Tone Edge Cases

    func testSkinToneAtBoundaries() {
        // Valid range is default through dark
        SpacePreferences.setSkinTone(.default, forSpace: 1, store: store)
        XCTAssertEqual(SpacePreferences.skinTone(forSpace: 1, store: store), .default)

        SpacePreferences.setSkinTone(.dark, forSpace: 2, store: store)
        XCTAssertEqual(SpacePreferences.skinTone(forSpace: 2, store: store), .dark)
    }

    func testSkinToneAllVariants() {
        // Test all skin tone variants can be stored and retrieved
        for (index, tone) in SkinTone.allCases.enumerated() {
            SpacePreferences.setSkinTone(tone, forSpace: index + 1, store: store)
            XCTAssertEqual(SpacePreferences.skinTone(forSpace: index + 1, store: store), tone)
        }
    }

    // MARK: - Icon Generation Edge Cases

    func testIconGenerationWithVeryLongNumber() {
        let longNumber = "12345678901234567890"
        let image = SpaceIconGenerator.generateIcon(
            for: longNumber,
            darkMode: false,
            customColors: nil,
            customFont: nil,
            style: .square
        )
        XCTAssertNotNil(image, "Should handle very long numbers")
        XCTAssertGreaterThan(image.size.width, 0)
    }

    func testIconGenerationWithSpecialCharacters() {
        let specialChars = "!@#$%"
        let image = SpaceIconGenerator.generateIcon(
            for: specialChars,
            darkMode: false,
            customColors: nil,
            customFont: nil,
            style: .circle
        )
        XCTAssertNotNil(image, "Should handle special characters")
    }

    func testIconGenerationWithEmptyString() {
        let image = SpaceIconGenerator.generateIcon(
            for: "",
            darkMode: false,
            customColors: nil,
            customFont: nil,
            style: .square
        )
        XCTAssertNotNil(image, "Should handle empty string")
    }

    func testIconGenerationWithNewlines() {
        let multiline = "1\n2"
        let image = SpaceIconGenerator.generateIcon(
            for: multiline,
            darkMode: false,
            customColors: nil,
            customFont: nil,
            style: .square
        )
        XCTAssertNotNil(image, "Should handle newlines in text")
    }

    func testIconGenerationFullscreenLabel() {
        let image = SpaceIconGenerator.generateIcon(
            for: Labels.fullscreen,
            darkMode: false,
            customColors: nil,
            customFont: nil,
            style: .square
        )
        XCTAssertNotNil(image, "Should handle fullscreen label 'F'")
    }
}
