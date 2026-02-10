import Testing
@testable import WhichSpace

@Suite("ItemData")
struct ItemDataTests {
    // MARK: - Skin Tone Modifiers

    private static let skinToneModifiers: Set<Unicode.Scalar> = [
        Unicode.Scalar(0x1F3FB)!, // Light
        Unicode.Scalar(0x1F3FC)!, // Medium-light
        Unicode.Scalar(0x1F3FD)!, // Medium
        Unicode.Scalar(0x1F3FE)!, // Medium-dark
        Unicode.Scalar(0x1F3FF)!, // Dark
    ]

    // MARK: - Emoji List Tests

    @Test("emojis list is not empty and has substantial count")
    func emojisListIsNotEmpty() {
        #expect(!ItemData.emojis.isEmpty)
        #expect(ItemData.emojis.count > 100, "Should have a substantial number of emojis")
    }

    @Test("emojis list contains no skin tone modifiers")
    func emojisListContainsNoSkinToneModifiers() {
        for emoji in ItemData.emojis {
            let hasSkinTone = emoji.unicodeScalars.contains { Self.skinToneModifiers.contains($0) }
            #expect(!hasSkinTone, "Emoji '\(emoji)' should not contain skin tone modifier")
        }
    }

    @Test("emojis list contains basic emojis")
    func emojisListContainsBasicEmojis() {
        #expect(ItemData.emojis.contains("😀"), "Should contain grinning face")
        #expect(ItemData.emojis.contains("👋"), "Should contain waving hand")
        #expect(ItemData.emojis.contains("❤️"), "Should contain red heart")
        #expect(ItemData.emojis.contains("🎉"), "Should contain party popper")
    }

    @Test("emojis list has no duplicates")
    func emojisListHasNoDuplicates() {
        let uniqueEmojis = Set(ItemData.emojis)
        #expect(uniqueEmojis.count == ItemData.emojis.count, "Emoji list should have no duplicates")
    }

    // MARK: - Symbols List Tests

    @Test("symbols list is not empty and has substantial count")
    func symbolsListIsNotEmpty() {
        #expect(!ItemData.symbols.isEmpty)
        #expect(ItemData.symbols.count > 50, "Should have a substantial number of symbols")
    }

    @Test("symbols list contains common symbols")
    func symbolsListContainsCommonSymbols() {
        #expect(ItemData.symbols.contains("star.fill"), "Should contain star.fill")
        #expect(ItemData.symbols.contains("heart.fill"), "Should contain heart.fill")
        #expect(ItemData.symbols.contains("house.fill"), "Should contain house.fill")
    }
}
