import Defaults
import Testing
@testable import WhichSpace

/// Swift Testing proof-of-concept: reimplements a subset of SkinToneTests
/// to demonstrate coexistence with XCTest in the same target.
@MainActor
struct SkinToneSwiftTests {
    private let store: DefaultsStore
    private let testSuite: TestSuite

    init() {
        testSuite = TestSuiteFactory.createSuite()
        store = DefaultsStore(suite: testSuite.suite)
    }

    // MARK: - Modifier Application

    @Test("apply returns original emoji when tone is .default")
    func applyReturnsOriginalWhenToneIsDefault() {
        Defaults[.emojiPickerSkinTone] = .default
        #expect(SkinTone.apply(to: "👋") == "👋")
        #expect(SkinTone.apply(to: "😀") == "😀")
    }

    @Test("apply adds skin tone modifier to supported emoji")
    func applyAddsToneToSupportedEmoji() {
        Defaults[.emojiPickerSkinTone] = .light
        #expect(SkinTone.apply(to: "👋") == "👋🏻")

        Defaults[.emojiPickerSkinTone] = .medium
        #expect(SkinTone.apply(to: "👋") == "👋🏽")

        Defaults[.emojiPickerSkinTone] = .dark
        #expect(SkinTone.apply(to: "👋") == "👋🏿")
    }

    @Test("apply returns original for unsupported emoji")
    func applyReturnsOriginalForUnsupportedEmoji() {
        Defaults[.emojiPickerSkinTone] = .medium
        #expect(SkinTone.apply(to: "😀") == "😀")
        #expect(SkinTone.apply(to: "🎉") == "🎉")
        #expect(SkinTone.apply(to: "⭐") == "⭐")
    }

    @Test("apply strips existing tone before applying new one")
    func applyStripsExistingToneBeforeApplyingNew() {
        Defaults[.emojiPickerSkinTone] = .dark
        #expect(SkinTone.apply(to: "👋🏽") == "👋🏿")
    }

    @Test("apply with explicit tone parameter overrides global default")
    func applyWithExplicitToneParameter() {
        Defaults[.emojiPickerSkinTone] = .light
        #expect(SkinTone.apply(to: "👋", tone: .dark) == "👋🏿")
        #expect(SkinTone.apply(to: "👋", tone: .default) == "👋")
        #expect(SkinTone.apply(to: "👋", tone: nil) == "👋🏻")
    }

    // MARK: - Modifiers Array

    @Test("modifiers array has correct count")
    func modifiersArrayHasCorrectCount() {
        #expect(SkinTone.modifiers.count == 6)
    }

    @Test("modifiers array first element is nil")
    func modifiersArrayFirstIsNil() {
        #expect(SkinTone.modifiers[0] == nil)
    }

    @Test(
        "modifiers array contains all five skin tone scalars",
        arguments: zip(
            1 ... 5,
            ["\u{1F3FB}", "\u{1F3FC}", "\u{1F3FD}", "\u{1F3FE}", "\u{1F3FF}"]
        )
    )
    func modifiersArrayContainsAllTones(index: Int, expected: String) {
        #expect(SkinTone.modifiers[index] == expected)
    }
}
