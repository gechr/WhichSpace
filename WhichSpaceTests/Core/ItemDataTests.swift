import XCTest
@testable import WhichSpace

final class ItemDataTests: XCTestCase {
    // MARK: - Skin Tone Modifiers

    private let skinToneModifiers: Set<Unicode.Scalar> = [
        Unicode.Scalar(0x1F3FB)!, // Light
        Unicode.Scalar(0x1F3FC)!, // Medium-light
        Unicode.Scalar(0x1F3FD)!, // Medium
        Unicode.Scalar(0x1F3FE)!, // Medium-dark
        Unicode.Scalar(0x1F3FF)!, // Dark
    ]

    // MARK: - Emoji List Tests

    func testEmojisListIsNotEmpty() {
        XCTAssertFalse(ItemData.emojis.isEmpty)
        XCTAssertGreaterThan(ItemData.emojis.count, 100, "Should have a substantial number of emojis")
    }

    func testEmojisListContainsNoSkinToneModifiers() {
        for emoji in ItemData.emojis {
            let hasSkinTone = emoji.unicodeScalars.contains { skinToneModifiers.contains($0) }
            XCTAssertFalse(hasSkinTone, "Emoji '\(emoji)' should not contain skin tone modifier")
        }
    }

    func testEmojisListContainsBasicEmojis() {
        // Common emojis that should always be present
        XCTAssertTrue(ItemData.emojis.contains("😀"), "Should contain grinning face")
        XCTAssertTrue(ItemData.emojis.contains("👋"), "Should contain waving hand")
        XCTAssertTrue(ItemData.emojis.contains("❤️"), "Should contain red heart")
        XCTAssertTrue(ItemData.emojis.contains("🎉"), "Should contain party popper")
    }

    func testEmojisListHasNoDuplicates() {
        let uniqueEmojis = Set(ItemData.emojis)
        XCTAssertEqual(uniqueEmojis.count, ItemData.emojis.count, "Emoji list should have no duplicates")
    }

    // MARK: - Symbols List Tests

    func testSymbolsListIsNotEmpty() {
        XCTAssertFalse(ItemData.symbols.isEmpty)
        XCTAssertGreaterThan(ItemData.symbols.count, 50, "Should have a substantial number of symbols")
    }

    func testSymbolsListContainsCommonSymbols() {
        XCTAssertTrue(ItemData.symbols.contains("star.fill"), "Should contain star.fill")
        XCTAssertTrue(ItemData.symbols.contains("heart.fill"), "Should contain heart.fill")
        XCTAssertTrue(ItemData.symbols.contains("house.fill"), "Should contain house.fill")
    }
}
