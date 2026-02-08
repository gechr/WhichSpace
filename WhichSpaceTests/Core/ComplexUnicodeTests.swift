import Cocoa
import Defaults
import Testing
@testable import WhichSpace

// MARK: - Complex Unicode Tests

@Suite("Complex Unicode")
@MainActor
struct ComplexUnicodeTests {
    private let testSuite: TestSuite

    init() {
        testSuite = TestSuiteFactory.createSuite()
    }

    // MARK: - Multi-Person ZWJ Sequences

    @Test("multi-person family emoji")
    func multiPersonFamilyEmoji() {
        // Family with man, woman, girl, boy (👨‍👩‍👧‍👦)
        let family = "👨‍👩‍👧‍👦"
        Defaults[.emojiPickerSkinTone] = .medium

        // Multi-person ZWJ sequences shouldn't get skin tones applied (not supported)
        _ = SkinTone.apply(to: family)

        // The family emoji should render without error
        let image = SpaceIconGenerator.generateSymbolIcon(
            symbolName: family,
            darkMode: false,
            customColors: nil,
            skinTone: .medium
        )
        #expect(hasVisibleContent(image), "Family emoji should render with visible content")
    }

    @Test("couple with heart emoji")
    func coupleWithHeartEmoji() {
        // Couple with heart (👩‍❤️‍👨)
        let couple = "👩‍❤️‍👨"

        let image = SpaceIconGenerator.generateSymbolIcon(
            symbolName: couple,
            darkMode: false,
            customColors: nil,
            skinTone: .default
        )
        #expect(hasVisibleContent(image), "Couple emoji should render with visible content")
    }

    // MARK: - Regional Indicator Sequences (Flags)

    @Test("regional indicator flags")
    func regionalIndicatorFlags() {
        let flags = ["🇺🇸", "🇬🇧", "🇯🇵", "🇫🇷", "🇩🇪", "🇨🇦"]

        for flag in flags {
            let image = SpaceIconGenerator.generateSymbolIcon(
                symbolName: flag,
                darkMode: false,
                customColors: nil,
                skinTone: nil
            )
            #expect(hasVisibleContent(image), "Flag \(flag) should render with visible content")
        }
    }

    @Test("subdivision flags")
    func subdivisionFlags() {
        // England, Scotland, Wales flags
        let subdivisionFlags = ["🏴󠁧󠁢󠁥󠁮󠁧󠁿", "🏴󠁧󠁢󠁳󠁣󠁴󠁿", "🏴󠁧󠁢󠁷󠁬󠁳󠁿"]

        for flag in subdivisionFlags {
            // These complex flags may not render on all systems, but shouldn't crash
            _ = SpaceIconGenerator.generateSymbolIcon(
                symbolName: flag,
                darkMode: false,
                customColors: nil,
                skinTone: nil
            )
        }
    }

    // MARK: - Keycap Sequences

    @Test("keycap sequences")
    func keycapSequences() {
        let keycaps = ["0️⃣", "1️⃣", "2️⃣", "3️⃣", "4️⃣", "5️⃣", "6️⃣", "7️⃣", "8️⃣", "9️⃣", "#️⃣", "*️⃣"]

        for keycap in keycaps {
            let image = SpaceIconGenerator.generateSymbolIcon(
                symbolName: keycap,
                darkMode: false,
                customColors: nil,
                skinTone: nil
            )
            #expect(hasVisibleContent(image), "Keycap \(keycap) should render with visible content")
        }
    }

    // MARK: - Emoji Presentation Variants

    @Test("emoji presentation variants")
    func emojiPresentationVariants() {
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

        #expect(hasVisibleContent(imageEmoji), "Emoji presentation heart should render")
        #expect(hasVisibleContent(imageText), "Text presentation heart should render")
    }

    // MARK: - Skin Tone Edge Cases

    @Test("skin tone modifier without base emoji")
    func skinToneModifierWithoutBaseEmoji() {
        // Standalone skin tone modifiers (should handle gracefully)
        let modifiers = ["\u{1F3FB}", "\u{1F3FC}", "\u{1F3FD}", "\u{1F3FE}", "\u{1F3FF}"]

        for modifier in modifiers {
            // Should not crash, may or may not have visible content
            _ = SpaceIconGenerator.generateSymbolIcon(
                symbolName: modifier,
                darkMode: false,
                customColors: nil,
                skinTone: nil
            )
        }
    }

    @Test("skin tone on already modified emoji")
    func skinToneOnAlreadyModifiedEmoji() {
        // Emoji already has a skin tone, try to apply another
        let alreadyToned = "👋🏿" // Dark skin
        Defaults[.emojiPickerSkinTone] = .light // Try to apply light

        let result = SkinTone.apply(to: alreadyToned)
        // Should strip existing and apply new
        #expect(result == "👋🏻", "Should replace existing skin tone")
    }

    @Test("skin tone out of bounds")
    func skinToneOutOfBounds() {
        // Test with out-of-bounds tone values using rawValueOrDefault
        let emoji = "👋"

        // Tone 6 and above should be clamped to default
        let highTone = SkinTone(rawValueOrDefault: 10)
        _ = SkinTone.apply(to: emoji, tone: highTone)
        #expect(highTone == .default, "Out-of-bounds tone should clamp to default")

        // Negative tone should clamp to default
        let negativeTone = SkinTone(rawValueOrDefault: -1)
        _ = SkinTone.apply(to: emoji, tone: negativeTone)
        #expect(negativeTone == .default, "Negative tone should clamp to default")
    }

    // MARK: - Zero-Width Joiner Edge Cases

    @Test("ZWJ without proper base")
    func zwjWithoutProperBase() {
        // ZWJ character alone
        let zwj = "\u{200D}"
        // Should not crash
        _ = SpaceIconGenerator.generateSymbolIcon(
            symbolName: zwj,
            darkMode: false,
            customColors: nil,
            skinTone: nil
        )
    }

    @Test("malformed ZWJ sequence")
    func malformedZWJSequence() {
        // ZWJ sequence with invalid components
        let malformed = "A\u{200D}B" // Letters with ZWJ

        _ = SpaceIconGenerator.generateSymbolIcon(
            symbolName: malformed,
            darkMode: false,
            customColors: nil,
            skinTone: nil
        )
    }

    // MARK: - Variation Selector Edge Cases

    @Test("variation selector stripping")
    func variationSelectorStripping() {
        // Emoji with variation selector
        let withSelector = "✌️" // U+270C U+FE0F
        Defaults[.emojiPickerSkinTone] = .mediumLight

        let result = SkinTone.apply(to: withSelector)
        // Should strip variation selector before applying skin tone
        #expect(result == "✌🏼")
    }

    @Test("multiple variation selectors")
    func multipleVariationSelectors() {
        // Text with multiple variation selectors (edge case)
        let multiSelector = "☺\u{FE0F}\u{FE0E}" // Mixed selectors

        _ = SpaceIconGenerator.generateSymbolIcon(
            symbolName: multiSelector,
            darkMode: false,
            customColors: nil,
            skinTone: nil
        )
    }

    // MARK: - Empty and Whitespace Strings

    @Test("empty string handling")
    func emptyStringHandling() {
        // Should not crash, will fall back to "?" icon
        _ = SpaceIconGenerator.generateSymbolIcon(
            symbolName: "",
            darkMode: false,
            customColors: nil,
            skinTone: nil
        )
    }

    @Test("whitespace-only string")
    func whitespaceOnlyString() {
        let whitespace = "   "
        _ = SpaceIconGenerator.generateSymbolIcon(
            symbolName: whitespace,
            darkMode: false,
            customColors: nil,
            skinTone: nil
        )
    }

    @Test("newline character")
    func newlineCharacter() {
        let newline = "\n"
        _ = SpaceIconGenerator.generateSymbolIcon(
            symbolName: newline,
            darkMode: false,
            customColors: nil,
            skinTone: nil
        )
    }

    // MARK: - Unicode Normalization

    @Test("combining characters")
    func combiningCharacters() {
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

        #expect(hasVisibleContent(imageNFC))
        #expect(hasVisibleContent(imageNFD))
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
