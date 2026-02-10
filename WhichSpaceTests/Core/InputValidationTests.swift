import Cocoa
import Defaults
import Testing
@testable import WhichSpace

// MARK: - Input Validation Tests

@Suite("Input Validation")
@MainActor
struct InputValidationTests {
    private let store: DefaultsStore
    private let testSuite: TestSuite

    init() {
        testSuite = TestSuiteFactory.createSuite()
        store = DefaultsStore(suite: testSuite.suite)
    }

    // MARK: - Space Number Edge Cases

    @Test("space number zero can be set and cleared")
    func spaceNumberZero() {
        // Space 0 is often used as "unknown" state
        SpacePreferences.setIconStyle(.circle, forSpace: 0, store: store)
        #expect(SpacePreferences.iconStyle(forSpace: 0, store: store) == .circle)

        SpacePreferences.clearIconStyle(forSpace: 0, store: store)
        #expect(SpacePreferences.iconStyle(forSpace: 0, store: store) == nil)
    }

    @Test("negative space number stores icon style")
    func negativeSpaceNumber() {
        // Negative space numbers (edge case)
        SpacePreferences.setIconStyle(.square, forSpace: -1, store: store)
        #expect(SpacePreferences.iconStyle(forSpace: -1, store: store) == .square)
    }

    @Test("very large space number stores symbol")
    func veryLargeSpaceNumber() {
        // Very large space numbers
        let largeNumber = Int.max - 1
        SpacePreferences.setSymbol("star", forSpace: largeNumber, store: store)
        #expect(SpacePreferences.symbol(forSpace: largeNumber, store: store) == "star")
    }

    // MARK: - Symbol Name Edge Cases

    @Test("empty symbol name can be stored")
    func emptySymbolName() throws {
        SpacePreferences.setSymbol("", forSpace: 1, store: store)
        let symbol = try #require(SpacePreferences.symbol(forSpace: 1, store: store))
        #expect(symbol.isEmpty)
    }

    @Test("very long symbol name can be stored")
    func veryLongSymbolName() {
        let longName = String(repeating: "a", count: 10_000)
        SpacePreferences.setSymbol(longName, forSpace: 1, store: store)
        #expect(SpacePreferences.symbol(forSpace: 1, store: store) == longName)
    }

    @Test("symbol name with special characters can be stored")
    func symbolNameWithSpecialCharacters() {
        let specialChars = "star.fill<>&\"'\n\t\0"
        SpacePreferences.setSymbol(specialChars, forSpace: 1, store: store)
        #expect(SpacePreferences.symbol(forSpace: 1, store: store) == specialChars)
    }

    @Test("symbol name with unicode null character can be stored")
    func symbolNameWithUnicodeNullCharacter() {
        let withNull = "star\u{0000}fill"
        SpacePreferences.setSymbol(withNull, forSpace: 1, store: store)
        #expect(SpacePreferences.symbol(forSpace: 1, store: store) == withNull)
    }

    // MARK: - Display ID Edge Cases

    @Test("empty display ID stores icon style")
    func emptyDisplayID() {
        store.uniqueIconsPerDisplay = true
        SpacePreferences.setIconStyle(.hexagon, forSpace: 1, display: "", store: store)
        #expect(SpacePreferences.iconStyle(forSpace: 1, display: "", store: store) == .hexagon)
    }

    @Test("display ID with special characters stores icon style")
    func displayIDWithSpecialCharacters() {
        store.uniqueIconsPerDisplay = true
        let specialID = "Display<>\"'&\n\t"
        SpacePreferences.setIconStyle(.circle, forSpace: 1, display: specialID, store: store)
        #expect(SpacePreferences.iconStyle(forSpace: 1, display: specialID, store: store) == .circle)
    }

    // MARK: - Color Edge Cases

    @Test("color with zero alpha can be stored and retrieved")
    func colorWithZeroAlpha() {
        let transparentColors = SpaceColors(
            foreground: NSColor(calibratedWhite: 0, alpha: 0),
            background: NSColor(calibratedWhite: 1, alpha: 0)
        )
        SpacePreferences.setColors(transparentColors, forSpace: 1, store: store)

        let retrieved = SpacePreferences.colors(forSpace: 1, store: store)
        #expect(retrieved != nil)
        #expect(retrieved?.foreground.alphaComponent == 0)
    }

    @Test("color with partial alpha can be stored and retrieved")
    func colorWithPartialAlpha() {
        let semiTransparent = SpaceColors(
            foreground: NSColor(calibratedWhite: 0.5, alpha: 0.5),
            background: NSColor(calibratedWhite: 0.5, alpha: 0.5)
        )
        SpacePreferences.setColors(semiTransparent, forSpace: 1, store: store)

        let retrieved = SpacePreferences.colors(forSpace: 1, store: store)
        #expect(abs(Double(retrieved?.foreground.alphaComponent ?? 0) - 0.5) <= 0.01)
    }

    @Test("colors in different color spaces can be stored and retrieved")
    func colorInDifferentColorSpaces() {
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
        #expect(SpacePreferences.colors(forSpace: 1, store: store) != nil)
        #expect(SpacePreferences.colors(forSpace: 2, store: store) != nil)
        #expect(SpacePreferences.colors(forSpace: 3, store: store) != nil)
    }

    // MARK: - Skin Tone Edge Cases

    @Test("skin tone at boundaries can be stored")
    func skinToneAtBoundaries() {
        // Valid range is default through dark
        SpacePreferences.setSkinTone(.default, forSpace: 1, store: store)
        #expect(SpacePreferences.skinTone(forSpace: 1, store: store) == .default)

        SpacePreferences.setSkinTone(.dark, forSpace: 2, store: store)
        #expect(SpacePreferences.skinTone(forSpace: 2, store: store) == .dark)
    }

    @Test("all skin tone variants can be stored and retrieved")
    func skinToneAllVariants() {
        // Test all skin tone variants can be stored and retrieved
        for (index, tone) in SkinTone.allCases.enumerated() {
            SpacePreferences.setSkinTone(tone, forSpace: index + 1, store: store)
            #expect(SpacePreferences.skinTone(forSpace: index + 1, store: store) == tone)
        }
    }

    // MARK: - Icon Generation Edge Cases

    @Test("icon generation handles very long number")
    func iconGenerationWithVeryLongNumber() {
        let longNumber = "12345678901234567890"
        let image = SpaceIconGenerator.generateIcon(
            for: longNumber,
            darkMode: false,
            customColors: nil,
            customFont: nil,
            style: .square
        )
        #expect(image.size.height > 0, "Should handle very long numbers")
        #expect(image.size.width > 0)
    }

    @Test("icon generation handles special characters")
    func iconGenerationWithSpecialCharacters() {
        let specialChars = "!@#$%"
        let image = SpaceIconGenerator.generateIcon(
            for: specialChars,
            darkMode: false,
            customColors: nil,
            customFont: nil,
            style: .circle
        )
        #expect(image.size.width > 0, "Should handle special characters")
        #expect(image.size.height > 0, "Should handle special characters")
    }

    @Test("icon generation handles empty string")
    func iconGenerationWithEmptyString() {
        let image = SpaceIconGenerator.generateIcon(
            for: "",
            darkMode: false,
            customColors: nil,
            customFont: nil,
            style: .square
        )
        #expect(image.size.width > 0, "Should handle empty string")
        #expect(image.size.height > 0, "Should handle empty string")
    }

    @Test("icon generation handles newlines")
    func iconGenerationWithNewlines() {
        let multiline = "1\n2"
        let image = SpaceIconGenerator.generateIcon(
            for: multiline,
            darkMode: false,
            customColors: nil,
            customFont: nil,
            style: .square
        )
        #expect(image.size.width > 0, "Should handle newlines in text")
        #expect(image.size.height > 0, "Should handle newlines in text")
    }

    @Test("icon generation handles fullscreen label")
    func iconGenerationFullscreenLabel() {
        let image = SpaceIconGenerator.generateIcon(
            for: Labels.fullscreen,
            darkMode: false,
            customColors: nil,
            customFont: nil,
            style: .square
        )
        #expect(image.size.width > 0, "Should handle fullscreen label 'F'")
        #expect(image.size.height > 0, "Should handle fullscreen label 'F'")
    }
}
