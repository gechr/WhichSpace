import Cocoa
import Defaults
import XCTest
@testable import WhichSpace

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
