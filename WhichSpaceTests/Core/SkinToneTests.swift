import Defaults
import XCTest
@testable import WhichSpace

final class SkinToneTests: IsolatedDefaultsTestCase {
    // MARK: - Modifier Application

    func testApplyReturnsOriginalWhenToneIsDefault() {
        Defaults[.emojiPickerSkinTone] = .default
        XCTAssertEqual(SkinTone.apply(to: "👋"), "👋")
        XCTAssertEqual(SkinTone.apply(to: "😀"), "😀")
    }

    func testApplyAddsToneToSupportedEmoji() {
        Defaults[.emojiPickerSkinTone] = .light
        XCTAssertEqual(SkinTone.apply(to: "👋"), "👋🏻")

        Defaults[.emojiPickerSkinTone] = .medium
        XCTAssertEqual(SkinTone.apply(to: "👋"), "👋🏽")

        Defaults[.emojiPickerSkinTone] = .dark
        XCTAssertEqual(SkinTone.apply(to: "👋"), "👋🏿")
    }

    func testApplyReturnsOriginalForUnsupportedEmoji() {
        Defaults[.emojiPickerSkinTone] = .medium
        // Face emojis don't support skin tones
        XCTAssertEqual(SkinTone.apply(to: "😀"), "😀")
        XCTAssertEqual(SkinTone.apply(to: "🎉"), "🎉")
        XCTAssertEqual(SkinTone.apply(to: "⭐"), "⭐")
    }

    func testApplyStripsExistingToneBeforeApplyingNew() {
        Defaults[.emojiPickerSkinTone] = .dark
        // Should strip medium tone and apply dark
        XCTAssertEqual(SkinTone.apply(to: "👋🏽"), "👋🏿")
    }

    func testApplyWorksWithVariousHandGestures() {
        Defaults[.emojiPickerSkinTone] = .mediumLight
        XCTAssertEqual(SkinTone.apply(to: "👍"), "👍🏼")
        XCTAssertEqual(SkinTone.apply(to: "🤞"), "🤞🏼")
    }

    func testApplyStripsVariationSelectorBeforeApplyingTone() {
        Defaults[.emojiPickerSkinTone] = .mediumLight
        // These emojis have variation selectors (U+FE0F)
        XCTAssertEqual(SkinTone.apply(to: "✌️"), "✌🏼") // ✌️ = U+270C U+FE0F
        XCTAssertEqual(SkinTone.apply(to: "☝️"), "☝🏼") // ☝️ = U+261D U+FE0F
        XCTAssertEqual(SkinTone.apply(to: "🖐️"), "🖐🏼") // 🖐️ = U+1F590 U+FE0F
    }

    func testApplyModifiesZWJSequencesWithPersonBase() {
        Defaults[.emojiPickerSkinTone] = .medium
        // Hair styles (person + ZWJ + hair)
        XCTAssertEqual(SkinTone.apply(to: "👨‍🦲"), "👨🏽‍🦲") // Man bald
        XCTAssertEqual(SkinTone.apply(to: "👩‍🦰"), "👩🏽‍🦰") // Woman red hair
        // Professions (person + ZWJ + object)
        XCTAssertEqual(SkinTone.apply(to: "👨‍🍳"), "👨🏽‍🍳") // Man cook
        XCTAssertEqual(SkinTone.apply(to: "👩‍💻"), "👩🏽‍💻") // Woman technologist
    }

    func testApplyDoesNotModifyNonPersonZWJSequences() {
        Defaults[.emojiPickerSkinTone] = .medium
        // These don't start with a modifier-base character
        XCTAssertEqual(SkinTone.apply(to: "❤️‍🔥"), "❤️‍🔥") // Heart on fire
        XCTAssertEqual(SkinTone.apply(to: "🏳️‍🌈"), "🏳️‍🌈") // Rainbow flag
    }

    func testApplyDoesNotModifyEmojisWithoutSkinToneSupport() {
        Defaults[.emojiPickerSkinTone] = .medium
        // EmojiKit's hasSkinTones correctly identifies these as not supporting skin tones
        XCTAssertEqual(SkinTone.apply(to: "👯"), "👯") // People with bunny ears
        XCTAssertEqual(SkinTone.apply(to: "👯‍♀️"), "👯‍♀️") // Women with bunny ears
        XCTAssertEqual(SkinTone.apply(to: "👯‍♂️"), "👯‍♂️") // Men with bunny ears
        XCTAssertEqual(SkinTone.apply(to: "🤼"), "🤼") // People wrestling
        XCTAssertEqual(SkinTone.apply(to: "🤼‍♀️"), "🤼‍♀️") // Women wrestling
        XCTAssertEqual(SkinTone.apply(to: "🤼‍♂️"), "🤼‍♂️") // Men wrestling
    }

    func testApplyWithExplicitToneParameter() {
        // Explicit tone should override the default
        Defaults[.emojiPickerSkinTone] = .light // (global default)
        XCTAssertEqual(SkinTone.apply(to: "👋", tone: .dark), "👋🏿") // Dark overrides
        XCTAssertEqual(SkinTone.apply(to: "👋", tone: .default), "👋") // Yellow/default
        XCTAssertEqual(SkinTone.apply(to: "👋", tone: nil), "👋🏻") // nil uses global
    }

    func testApplyWithToneDefaultStripsExistingModifier() {
        // When tone is .default, should strip any existing modifier
        XCTAssertEqual(SkinTone.apply(to: "👋🏿", tone: .default), "👋")
        XCTAssertEqual(SkinTone.apply(to: "👍🏻", tone: .default), "👍")
    }

    // MARK: - Modifiers Array

    func testModifiersArrayHasCorrectCount() {
        XCTAssertEqual(SkinTone.modifiers.count, 6)
    }

    func testModifiersArrayFirstIsNil() {
        XCTAssertNil(SkinTone.modifiers[0])
    }

    func testModifiersArrayContainsAllTones() {
        XCTAssertEqual(SkinTone.modifiers[1], "\u{1F3FB}") // Light
        XCTAssertEqual(SkinTone.modifiers[2], "\u{1F3FC}") // Medium-light
        XCTAssertEqual(SkinTone.modifiers[3], "\u{1F3FD}") // Medium
        XCTAssertEqual(SkinTone.modifiers[4], "\u{1F3FE}") // Medium-dark
        XCTAssertEqual(SkinTone.modifiers[5], "\u{1F3FF}") // Dark
    }
}
