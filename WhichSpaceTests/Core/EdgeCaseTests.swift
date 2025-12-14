import Cocoa
import Defaults
import XCTest
@testable import WhichSpace

// MARK: - Error Recovery Tests

final class ErrorRecoveryTests: IsolatedDefaultsTestCase {
    private var bridge: SpaceColors.Bridge!
    private var fontBridge: SpaceFont.Bridge!

    override func setUp() {
        super.setUp()
        bridge = SpaceColors.Bridge()
        fontBridge = SpaceFont.Bridge()
    }

    override func tearDown() {
        bridge = nil
        fontBridge = nil
        super.tearDown()
    }

    // MARK: - Corrupted Preference Data Tests

    func testDeserializeWithCorruptedForegroundData() {
        let validBackground = try! NSKeyedArchiver.archivedData(
            withRootObject: NSColor.blue,
            requiringSecureCoding: true
        )
        let corruptedData = Data([0xDE, 0xAD, 0xBE, 0xEF])

        let result = bridge.deserialize([
            "foreground": corruptedData,
            "background": validBackground,
        ])

        XCTAssertNil(result, "Should return nil for corrupted foreground data")
    }

    func testDeserializeWithCorruptedBackgroundData() {
        let validForeground = try! NSKeyedArchiver.archivedData(
            withRootObject: NSColor.red,
            requiringSecureCoding: true
        )
        let corruptedData = Data([0xCA, 0xFE, 0xBA, 0xBE])

        let result = bridge.deserialize([
            "foreground": validForeground,
            "background": corruptedData,
        ])

        XCTAssertNil(result, "Should return nil for corrupted background data")
    }

    func testDeserializeWithBothCorruptedData() {
        let corruptedData = Data([0x00, 0x01, 0x02, 0x03])

        let result = bridge.deserialize([
            "foreground": corruptedData,
            "background": corruptedData,
        ])

        XCTAssertNil(result, "Should return nil when both colors are corrupted")
    }

    func testDeserializeWithEmptyData() {
        let emptyData = Data()

        let result = bridge.deserialize([
            "foreground": emptyData,
            "background": emptyData,
        ])

        XCTAssertNil(result, "Should return nil for empty data")
    }

    func testDeserializeWithWrongObjectType() {
        // Archive a string instead of NSColor
        let wrongTypeData = try! NSKeyedArchiver.archivedData(
            withRootObject: "not a color" as NSString,
            requiringSecureCoding: true
        )
        let validBackground = try! NSKeyedArchiver.archivedData(
            withRootObject: NSColor.blue,
            requiringSecureCoding: true
        )

        let result = bridge.deserialize([
            "foreground": wrongTypeData,
            "background": validBackground,
        ])

        XCTAssertNil(result, "Should return nil when archived object is wrong type")
    }

    func testDeserializeWithPartiallyValidData() {
        let validForeground = try! NSKeyedArchiver.archivedData(
            withRootObject: NSColor.red,
            requiringSecureCoding: true
        )

        // Missing background entirely
        let result = bridge.deserialize(["foreground": validForeground])
        XCTAssertNil(result, "Should return nil when background is missing")
    }

    func testDeserializeWithExtraKeys() {
        let validForeground = try! NSKeyedArchiver.archivedData(
            withRootObject: NSColor.red,
            requiringSecureCoding: true
        )
        let validBackground = try! NSKeyedArchiver.archivedData(
            withRootObject: NSColor.blue,
            requiringSecureCoding: true
        )

        let result = bridge.deserialize([
            "foreground": validForeground,
            "background": validBackground,
            "extraKey": Data([0x00]),
        ])

        XCTAssertNotNil(result, "Should successfully deserialize even with extra keys")
        XCTAssertEqual(result?.foreground, .red)
        XCTAssertEqual(result?.background, .blue)
    }

    // MARK: - Font Bridge Tests

    func testFontBridgeDeserializeWithCorruptedData() {
        let corruptedData = Data([0xDE, 0xAD, 0xBE, 0xEF])
        let result = fontBridge.deserialize(corruptedData)
        XCTAssertNil(result, "Should return nil for corrupted font data")
    }

    func testFontBridgeDeserializeWithEmptyData() {
        let result = fontBridge.deserialize(Data())
        XCTAssertNil(result, "Should return nil for empty font data")
    }

    func testFontBridgeDeserializeWithNil() {
        let result = fontBridge.deserialize(nil)
        XCTAssertNil(result, "Should return nil for nil font data")
    }

    func testFontBridgeRoundTrip() {
        let originalFont = NSFont.boldSystemFont(ofSize: 14)
        let spaceFont = SpaceFont(font: originalFont)

        let serialized = fontBridge.serialize(spaceFont)
        XCTAssertNotNil(serialized)

        let deserialized = fontBridge.deserialize(serialized)
        XCTAssertNotNil(deserialized)
        XCTAssertEqual(deserialized?.font.pointSize, originalFont.pointSize)
    }

    // MARK: - Recovery from Bad State Tests

    func testPreferencesRecoverFromCorruptedStorage() {
        // Set valid preferences
        let validColors = SpaceColors(foreground: .red, background: .blue)
        SpacePreferences.setColors(validColors, forSpace: 1, store: store)

        // Verify retrieval works
        let retrieved = SpacePreferences.colors(forSpace: 1, store: store)
        XCTAssertNotNil(retrieved)

        // Clear and verify clean state
        SpacePreferences.clearColors(forSpace: 1, store: store)
        XCTAssertNil(SpacePreferences.colors(forSpace: 1, store: store))

        // Should be able to set again after clearing
        let newColors = SpaceColors(foreground: .green, background: .yellow)
        SpacePreferences.setColors(newColors, forSpace: 1, store: store)
        let newRetrieved = SpacePreferences.colors(forSpace: 1, store: store)
        XCTAssertEqual(newRetrieved?.foreground, .green)
    }
}

// MARK: - Complex Unicode Tests

final class ComplexUnicodeTests: IsolatedDefaultsTestCase {
    // MARK: - Multi-Person ZWJ Sequences

    func testMultiPersonFamilyEmoji() {
        // Family with man, woman, girl, boy (👨‍👩‍👧‍👦)
        let family = "👨‍👩‍👧‍👦"
        Defaults[.emojiPickerSkinTone] = .medium

        // Multi-person ZWJ sequences shouldn't get skin tones applied (not supported)
        let result = SkinTone.apply(to: family)

        // The family emoji should render without error
        let image = SpaceIconGenerator.generateSymbolIcon(
            symbolName: family,
            darkMode: false,
            customColors: nil,
            skinTone: .medium
        )
        XCTAssertTrue(hasVisibleContent(image), "Family emoji should render with visible content")
    }

    func testCoupleWithHeartEmoji() {
        // Couple with heart (👩‍❤️‍👨)
        let couple = "👩‍❤️‍👨"

        let image = SpaceIconGenerator.generateSymbolIcon(
            symbolName: couple,
            darkMode: false,
            customColors: nil,
            skinTone: .default
        )
        XCTAssertTrue(hasVisibleContent(image), "Couple emoji should render with visible content")
    }

    // MARK: - Regional Indicator Sequences (Flags)

    func testRegionalIndicatorFlags() {
        let flags = ["🇺🇸", "🇬🇧", "🇯🇵", "🇫🇷", "🇩🇪", "🇨🇦"]

        for flag in flags {
            let image = SpaceIconGenerator.generateSymbolIcon(
                symbolName: flag,
                darkMode: false,
                customColors: nil,
                skinTone: nil
            )
            XCTAssertTrue(hasVisibleContent(image), "Flag \(flag) should render with visible content")
        }
    }

    func testSubdivisionFlags() {
        // England, Scotland, Wales flags
        let subdivisionFlags = ["🏴󠁧󠁢󠁥󠁮󠁧󠁿", "🏴󠁧󠁢󠁳󠁣󠁴󠁿", "🏴󠁧󠁢󠁷󠁬󠁳󠁿"]

        for flag in subdivisionFlags {
            let image = SpaceIconGenerator.generateSymbolIcon(
                symbolName: flag,
                darkMode: false,
                customColors: nil,
                skinTone: nil
            )
            // These complex flags may not render on all systems, but shouldn't crash
            XCTAssertNotNil(image, "Subdivision flag should not crash")
        }
    }

    // MARK: - Keycap Sequences

    func testKeycapSequences() {
        let keycaps = ["0️⃣", "1️⃣", "2️⃣", "3️⃣", "4️⃣", "5️⃣", "6️⃣", "7️⃣", "8️⃣", "9️⃣", "#️⃣", "*️⃣"]

        for keycap in keycaps {
            let image = SpaceIconGenerator.generateSymbolIcon(
                symbolName: keycap,
                darkMode: false,
                customColors: nil,
                skinTone: nil
            )
            XCTAssertTrue(hasVisibleContent(image), "Keycap \(keycap) should render with visible content")
        }
    }

    // MARK: - Emoji Presentation Variants

    func testEmojiPresentationVariants() {
        // Text vs emoji presentation
        let heart = "❤️" // With emoji presentation selector
        let heartText = "❤" // Without selector

        let imageEmoji = SpaceIconGenerator.generateSymbolIcon(
            symbolName: heart,
            darkMode: false,
            customColors: nil,
            skinTone: nil
        )
        let imageText = SpaceIconGenerator.generateSymbolIcon(
            symbolName: heartText,
            darkMode: false,
            customColors: nil,
            skinTone: nil
        )

        XCTAssertTrue(hasVisibleContent(imageEmoji), "Emoji presentation heart should render")
        XCTAssertTrue(hasVisibleContent(imageText), "Text presentation heart should render")
    }

    // MARK: - Skin Tone Edge Cases

    func testSkinToneModifierWithoutBaseEmoji() {
        // Standalone skin tone modifiers (should handle gracefully)
        let modifiers = ["\u{1F3FB}", "\u{1F3FC}", "\u{1F3FD}", "\u{1F3FE}", "\u{1F3FF}"]

        for modifier in modifiers {
            let image = SpaceIconGenerator.generateSymbolIcon(
                symbolName: modifier,
                darkMode: false,
                customColors: nil,
                skinTone: nil
            )
            // Should not crash, may or may not have visible content
            XCTAssertNotNil(image, "Standalone skin tone modifier should not crash")
        }
    }

    func testSkinToneOnAlreadyModifiedEmoji() {
        // Emoji already has a skin tone, try to apply another
        let alreadyToned = "👋🏿" // Dark skin
        Defaults[.emojiPickerSkinTone] = .light // Try to apply light

        let result = SkinTone.apply(to: alreadyToned)
        // Should strip existing and apply new
        XCTAssertEqual(result, "👋🏻", "Should replace existing skin tone")
    }

    func testSkinToneOutOfBounds() {
        // Test with out-of-bounds tone values using rawValueOrDefault
        let emoji = "👋"

        // Tone 6 and above should be clamped to default
        let highTone = SkinTone(rawValueOrDefault: 10)
        let resultHigh = SkinTone.apply(to: emoji, tone: highTone)
        XCTAssertNotNil(resultHigh, "Should handle high tone value without crash")
        XCTAssertEqual(highTone, .default, "Out-of-bounds tone should clamp to default")

        // Negative tone should clamp to default
        let negativeTone = SkinTone(rawValueOrDefault: -1)
        let resultNegative = SkinTone.apply(to: emoji, tone: negativeTone)
        XCTAssertNotNil(resultNegative, "Should handle negative tone value without crash")
        XCTAssertEqual(negativeTone, .default, "Negative tone should clamp to default")
    }

    // MARK: - Zero-Width Joiner Edge Cases

    func testZWJWithoutProperBase() {
        // ZWJ character alone
        let zwj = "\u{200D}"
        let image = SpaceIconGenerator.generateSymbolIcon(
            symbolName: zwj,
            darkMode: false,
            customColors: nil,
            skinTone: nil
        )
        // Should not crash
        XCTAssertNotNil(image, "ZWJ alone should not crash")
    }

    func testMalformedZWJSequence() {
        // ZWJ sequence with invalid components
        let malformed = "A\u{200D}B" // Letters with ZWJ

        let image = SpaceIconGenerator.generateSymbolIcon(
            symbolName: malformed,
            darkMode: false,
            customColors: nil,
            skinTone: nil
        )
        XCTAssertNotNil(image, "Malformed ZWJ sequence should not crash")
    }

    // MARK: - Variation Selector Edge Cases

    func testVariationSelectorStripping() {
        // Emoji with variation selector
        let withSelector = "✌️" // U+270C U+FE0F
        Defaults[.emojiPickerSkinTone] = .mediumLight

        let result = SkinTone.apply(to: withSelector)
        // Should strip variation selector before applying skin tone
        XCTAssertEqual(result, "✌🏼")
    }

    func testMultipleVariationSelectors() {
        // Text with multiple variation selectors (edge case)
        let multiSelector = "☺\u{FE0F}\u{FE0E}" // Mixed selectors

        let image = SpaceIconGenerator.generateSymbolIcon(
            symbolName: multiSelector,
            darkMode: false,
            customColors: nil,
            skinTone: nil
        )
        XCTAssertNotNil(image, "Multiple variation selectors should not crash")
    }

    // MARK: - Empty and Whitespace Strings

    func testEmptyStringHandling() {
        let image = SpaceIconGenerator.generateSymbolIcon(
            symbolName: "",
            darkMode: false,
            customColors: nil,
            skinTone: nil
        )
        // Should not crash, will fall back to "?" icon
        XCTAssertNotNil(image, "Empty string should not crash")
    }

    func testWhitespaceOnlyString() {
        let whitespace = "   "
        let image = SpaceIconGenerator.generateSymbolIcon(
            symbolName: whitespace,
            darkMode: false,
            customColors: nil,
            skinTone: nil
        )
        XCTAssertNotNil(image, "Whitespace-only string should not crash")
    }

    func testNewlineCharacter() {
        let newline = "\n"
        let image = SpaceIconGenerator.generateSymbolIcon(
            symbolName: newline,
            darkMode: false,
            customColors: nil,
            skinTone: nil
        )
        XCTAssertNotNil(image, "Newline character should not crash")
    }

    // MARK: - Unicode Normalization

    func testCombiningCharacters() {
        // é as e + combining acute (NFC vs NFD)
        let nfc = "é" // Single character
        let nfd = "e\u{0301}" // e + combining acute

        let imageNFC = SpaceIconGenerator.generateSymbolIcon(
            symbolName: nfc,
            darkMode: false,
            customColors: nil,
            skinTone: nil
        )
        let imageNFD = SpaceIconGenerator.generateSymbolIcon(
            symbolName: nfd,
            darkMode: false,
            customColors: nil,
            skinTone: nil
        )

        XCTAssertNotNil(imageNFC)
        XCTAssertNotNil(imageNFD)
    }

    // MARK: - Helpers

    private func hasVisibleContent(_ image: NSImage) -> Bool {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return false
        }

        let width = cgImage.width
        let height = cgImage.height
        let bytesPerPixel = 4
        let bytesPerRow = width * bytesPerPixel
        let totalBytes = height * bytesPerRow

        var pixelData = [UInt8](repeating: 0, count: totalBytes)
        guard let context = CGContext(
            data: &pixelData,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return false
        }

        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))

        for idx in stride(from: 3, to: totalBytes, by: bytesPerPixel) {
            if pixelData[idx] > 0 {
                return true
            }
        }

        return false
    }
}

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
