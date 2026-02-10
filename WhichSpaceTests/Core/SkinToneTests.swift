import Defaults
import Testing
@testable import WhichSpace

@Suite("Skin Tone")
@MainActor
struct SkinToneTests {
    private let store: DefaultsStore
    private let testSuite: TestSuite

    init() {
        testSuite = TestSuiteFactory.createSuite()
        store = DefaultsStore(suite: testSuite.suite)
    }

    // MARK: - Modifier Application

    @Test("apply returns original when tone is default")
    func applyReturnsOriginalWhenToneIsDefault() {
        Defaults[.emojiPickerSkinTone] = .default
        #expect(SkinTone.apply(to: "👋") == "👋")
        #expect(SkinTone.apply(to: "😀") == "😀")
    }

    @Test("apply adds tone to supported emoji")
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

    @Test("apply works with various hand gestures")
    func applyWorksWithVariousHandGestures() {
        Defaults[.emojiPickerSkinTone] = .mediumLight
        #expect(SkinTone.apply(to: "👍") == "👍🏼")
        #expect(SkinTone.apply(to: "🤞") == "🤞🏼")
    }

    @Test("apply strips variation selector before applying tone")
    func applyStripsVariationSelectorBeforeApplyingTone() {
        Defaults[.emojiPickerSkinTone] = .mediumLight
        #expect(SkinTone.apply(to: "✌️") == "✌🏼")
        #expect(SkinTone.apply(to: "☝️") == "☝🏼")
        #expect(SkinTone.apply(to: "🖐️") == "🖐🏼")
    }

    @Test("apply modifies ZWJ sequences with person base")
    func applyModifiesZWJSequencesWithPersonBase() {
        Defaults[.emojiPickerSkinTone] = .medium
        #expect(SkinTone.apply(to: "👨‍🦲") == "👨🏽‍🦲")
        #expect(SkinTone.apply(to: "👩‍🦰") == "👩🏽‍🦰")
        #expect(SkinTone.apply(to: "👨‍🍳") == "👨🏽‍🍳")
        #expect(SkinTone.apply(to: "👩‍💻") == "👩🏽‍💻")
    }

    @Test("apply does not modify non-person ZWJ sequences")
    func applyDoesNotModifyNonPersonZWJSequences() {
        Defaults[.emojiPickerSkinTone] = .medium
        #expect(SkinTone.apply(to: "❤️‍🔥") == "❤️‍🔥")
        #expect(SkinTone.apply(to: "🏳️‍🌈") == "🏳️‍🌈")
    }

    @Test("apply does not modify emojis without skin tone support")
    func applyDoesNotModifyEmojisWithoutSkinToneSupport() {
        Defaults[.emojiPickerSkinTone] = .medium
        #expect(SkinTone.apply(to: "👯") == "👯")
        #expect(SkinTone.apply(to: "👯‍♀️") == "👯‍♀️")
        #expect(SkinTone.apply(to: "👯‍♂️") == "👯‍♂️")
        #expect(SkinTone.apply(to: "🤼") == "🤼")
        #expect(SkinTone.apply(to: "🤼‍♀️") == "🤼‍♀️")
        #expect(SkinTone.apply(to: "🤼‍♂️") == "🤼‍♂️")
    }

    @Test("apply with explicit tone parameter")
    func applyWithExplicitToneParameter() {
        Defaults[.emojiPickerSkinTone] = .light
        #expect(SkinTone.apply(to: "👋", tone: .dark) == "👋🏿")
        #expect(SkinTone.apply(to: "👋", tone: .default) == "👋")
        #expect(SkinTone.apply(to: "👋", tone: nil) == "👋🏻")
    }

    @Test("apply with tone default strips existing modifier")
    func applyWithToneDefaultStripsExistingModifier() {
        #expect(SkinTone.apply(to: "👋🏿", tone: .default) == "👋")
        #expect(SkinTone.apply(to: "👍🏻", tone: .default) == "👍")
    }

    // MARK: - Modifiers Array

    @Test("modifiers array has correct count")
    func modifiersArrayHasCorrectCount() {
        #expect(SkinTone.modifiers.count == 6)
    }

    @Test("modifiers array first is nil")
    func modifiersArrayFirstIsNil() {
        #expect(SkinTone.modifiers[0] == nil)
    }

    @Test("modifiers array contains all tones")
    func modifiersArrayContainsAllTones() {
        #expect(SkinTone.modifiers[1] == "\u{1F3FB}")
        #expect(SkinTone.modifiers[2] == "\u{1F3FC}")
        #expect(SkinTone.modifiers[3] == "\u{1F3FD}")
        #expect(SkinTone.modifiers[4] == "\u{1F3FE}")
        #expect(SkinTone.modifiers[5] == "\u{1F3FF}")
    }
}
