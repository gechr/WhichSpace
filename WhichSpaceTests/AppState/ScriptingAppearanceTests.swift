import AppKit
import Defaults
import Testing
@testable import WhichSpace

@MainActor
struct ScriptingAppearanceTests {
    private let store: DefaultsStore
    private let testSuite: TestSuite
    private let stub: CGSStub
    private let key: ScriptingHelpers.SpaceKey = (2, "Main")

    init() {
        testSuite = TestSuiteFactory.createSuite()
        store = DefaultsStore(suite: testSuite.suite)
        stub = CGSStub()
    }

    private func makeAppState() -> AppState {
        stub.activeDisplayIdentifier = "Main"
        stub.displays = [
            CGSStub.makeDisplay(
                displayID: "Main",
                spaces: [(id: 100, isFullscreen: false), (id: 101, isFullscreen: false)],
                activeSpaceID: 100
            ),
            CGSStub.makeDisplay(
                displayID: "Side",
                spaces: [
                    (id: 200, isFullscreen: true),
                    (id: 201, isFullscreen: false),
                    (id: 202, isFullscreen: false),
                ],
                activeSpaceID: 201
            ),
        ]
        return AppState(displaySpaceProvider: stub, skipObservers: true, store: store)
    }

    // MARK: - Hex colours

    @Test("hex colours parse case-insensitively and format uppercase", arguments: [
        ("cc30e0", "CC30E0"),
        ("CC30E0FF", "CC30E0"),
        ("cc30e080", "CC30E080"),
        ("CC30E000", "CC30E000"),
        ("  000000 ", "000000"),
    ])
    func hexRoundTrip(input: String, expected: String) throws {
        let color = try #require(HexColor.parse(input))
        #expect(HexColor.format(color) == expected)
    }

    @Test("malformed hex colours are rejected", arguments: [
        "", "#CC30E0", "CC30E", "CC30E0F", "CC30E0FFF", "GG30E0", "+C30E0", "+CC30E0", "-C30E0", "CC 30E0",
        "０００００0",
    ])
    func hexRejects(input: String) {
        #expect(HexColor.parse(input) == nil)
    }

    @Test("formatting converts other colour spaces to sRGB")
    func hexFormatsCalibratedColors() {
        #expect(HexColor.format(NSColor(calibratedWhite: 1, alpha: 1)) == "FFFFFF")
        #expect(HexColor.format(NSColor(calibratedWhite: 0, alpha: 0.5)) == "00000080")
    }

    // MARK: - Colour getters and setters

    @Test("colour getters are empty until the Space has colours")
    func colorGettersEmptyWhenUnset() {
        #expect(ScriptingHelpers.foregroundColor(at: key, store: store).isEmpty)
        #expect(ScriptingHelpers.backgroundColor(at: key, store: store).isEmpty)
        #expect(ScriptingHelpers.symbolColor(at: key, store: store).isEmpty)
        #expect(ScriptingHelpers.symbolBackgroundColor(at: key, store: store).isEmpty)
    }

    @Test("setting the foreground fills the background from the appearance default")
    func foregroundFillsBackground() throws {
        try ScriptingHelpers.setForegroundColor("cc30e0", at: key, darkMode: false, store: store)

        #expect(ScriptingHelpers.foregroundColor(at: key, store: store) == "CC30E0")
        #expect(ScriptingHelpers.backgroundColor(at: key, store: store)
            == HexColor.format(IconColors.filledLightBackground))
        #expect(ScriptingHelpers.symbolColor(at: key, store: store).isEmpty)
        #expect(store.displaySpaceColors["Main"]?[2] != nil)
        #expect(store.spaceColors[2] == nil)
    }

    @Test("setting the background in dark mode fills the dark foreground")
    func backgroundFillsDarkForeground() throws {
        try ScriptingHelpers.setBackgroundColor("202020", at: key, darkMode: true, store: store)

        #expect(ScriptingHelpers.backgroundColor(at: key, store: store) == "202020")
        #expect(ScriptingHelpers.foregroundColor(at: key, store: store)
            == HexColor.format(IconColors.filledDarkForeground))
    }

    @Test("setting one channel keeps the others")
    func channelsAreIndependent() throws {
        try ScriptingHelpers.setForegroundColor("111111", at: key, darkMode: false, store: store)
        try ScriptingHelpers.setSymbolColor("222222", at: key, darkMode: false, store: store)
        try ScriptingHelpers.setSymbolBackgroundColor("33333380", at: key, darkMode: false, store: store)
        try ScriptingHelpers.setBackgroundColor("444444", at: key, darkMode: false, store: store)

        #expect(ScriptingHelpers.foregroundColor(at: key, store: store) == "111111")
        #expect(ScriptingHelpers.symbolColor(at: key, store: store) == "222222")
        #expect(ScriptingHelpers.symbolBackgroundColor(at: key, store: store) == "33333380")
        #expect(ScriptingHelpers.backgroundColor(at: key, store: store) == "444444")
    }

    @Test("empty foreground and background are refused, malformed colours rejected")
    func requiredColorErrors() {
        #expect(throws: AppearanceError.colorResetRequired) {
            try ScriptingHelpers.setForegroundColor("", at: key, darkMode: false, store: store)
        }
        #expect(throws: AppearanceError.colorResetRequired) {
            try ScriptingHelpers.setBackgroundColor("  ", at: key, darkMode: false, store: store)
        }
        #expect(throws: AppearanceError.invalidColor) {
            try ScriptingHelpers.setForegroundColor("CC30E", at: key, darkMode: false, store: store)
        }
        #expect(throws: AppearanceError.invalidColor) {
            try ScriptingHelpers.setSymbolColor("#12345", at: key, darkMode: false, store: store)
        }
        #expect(store.displaySpaceColors.isEmpty)
    }

    @Test("empty symbol colours clear their channel, and are a no-op without colours")
    func optionalChannelsClear() throws {
        try ScriptingHelpers.setSymbolColor("", at: key, darkMode: false, store: store)
        try ScriptingHelpers.setSymbolBackgroundColor("", at: key, darkMode: false, store: store)
        #expect(store.displaySpaceColors.isEmpty)

        try ScriptingHelpers.setSymbolColor("222222", at: key, darkMode: false, store: store)
        try ScriptingHelpers.setSymbolBackgroundColor("333333", at: key, darkMode: false, store: store)
        try ScriptingHelpers.setSymbolColor("", at: key, darkMode: false, store: store)
        try ScriptingHelpers.setSymbolBackgroundColor("", at: key, darkMode: false, store: store)

        let colors = try #require(store.displaySpaceColors["Main"]?[2])
        #expect(colors.symbol == nil)
        #expect(colors.symbolBackground == nil)
        #expect(ScriptingHelpers.symbolColor(at: key, store: store).isEmpty)
        #expect(ScriptingHelpers.symbolBackgroundColor(at: key, store: store).isEmpty)
    }

    @Test("colour getters read through the shared and template tiers")
    func colorGettersFollowCascade() throws {
        SpacePreferences.setColors(
            SpaceColors(foreground: .white, background: .black), forSpace: 0, store: store
        )
        #expect(ScriptingHelpers.foregroundColor(at: key, store: store) == "FFFFFF")

        SpacePreferences.setColors(
            SpaceColors(foreground: .red, background: .black), forSpace: 2, store: store
        )
        #expect(ScriptingHelpers.foregroundColor(at: key, store: store) == "FF0000")

        // Editing one channel copies the inherited bundle into the override
        try ScriptingHelpers.setBackgroundColor("123456", at: key, darkMode: false, store: store)
        #expect(ScriptingHelpers.foregroundColor(at: key, store: store) == "FF0000")
        #expect(ScriptingHelpers.backgroundColor(at: key, store: store) == "123456")
    }

    @Test("reset color removes the override and reveals the shared colours")
    func resetColorsRevealsShared() throws {
        SpacePreferences.setColors(
            SpaceColors(foreground: .red, background: .black), forSpace: 2, store: store
        )
        try ScriptingHelpers.setForegroundColor("00FF00", at: key, darkMode: false, store: store)
        ScriptingHelpers.setLabel("Work", at: key, store: store)

        ScriptingHelpers.resetColors(at: key, store: store)

        #expect(ScriptingHelpers.foregroundColor(at: key, store: store) == "FF0000")
        #expect(store.displaySpaceColors["Main"]?[2] == nil)
        #expect(SpacePreferences.label(forSpace: 2, display: "Main", store: store) == "Work")
    }

    // MARK: - Symbols and emoji

    @Test("symbol and emoji getters are empty until set and never report the other kind")
    func symbolAndEmojiGetters() throws {
        #expect(ScriptingHelpers.symbol(at: key, store: store).isEmpty)
        #expect(ScriptingHelpers.emoji(at: key, store: store).isEmpty)

        try ScriptingHelpers.setSymbol("curlybraces", at: key, store: store)
        #expect(ScriptingHelpers.symbol(at: key, store: store) == "curlybraces")
        #expect(ScriptingHelpers.emoji(at: key, store: store).isEmpty)

        try ScriptingHelpers.setEmoji("🎨", at: key, store: store)
        #expect(ScriptingHelpers.symbol(at: key, store: store).isEmpty)
        #expect(ScriptingHelpers.emoji(at: key, store: store) == "🎨")
    }

    @Test("unknown symbol names are rejected without a write")
    func unknownSymbolRejected() {
        #expect(throws: AppearanceError.unknownSymbol) {
            try ScriptingHelpers.setSymbol("not.a.symbol.name", at: key, store: store)
        }
        #expect(throws: AppearanceError.unknownSymbol) {
            try ScriptingHelpers.setSymbol("🎨", at: key, store: store)
        }
        #expect(store.displaySpaceSymbols.isEmpty)
    }

    @Test("emoji round-trip exactly as written", arguments: [
        "🎨", "👨‍👩‍👧‍👦", "🇬🇧", "1️⃣", "☀️", "🫱🏽‍🫲🏻", "👍🏽", "🏴󠁧󠁢󠁳󠁣󠁴󠁿",
    ])
    func emojiRoundTrip(emoji: String) throws {
        store.emojiPickerSkinTone = .dark
        try ScriptingHelpers.setEmoji(" \(emoji) ", at: key, store: store)

        #expect(ScriptingHelpers.emoji(at: key, store: store) == emoji)
        #expect(store.displaySpaceSymbols["Main"]?[2] == emoji)
        #expect(store.displaySpaceSkinTones["Main"]?[2] == SkinTone.default)
    }

    @Test("anything but a single emoji is rejected", arguments: ["a", "ab", "👍👍", "curlybraces", "1"])
    func emojiRejects(input: String) {
        #expect(throws: AppearanceError.notASingleEmoji) {
            try ScriptingHelpers.setEmoji(input, at: key, store: store)
        }
        #expect(store.displaySpaceSymbols.isEmpty)
    }

    @Test("an empty symbol or emoji stores the none sentinel so a template symbol stays hidden")
    func emptyClearsWithSentinel() throws {
        SpacePreferences.setSymbol("star", forSpace: 0, store: store)
        #expect(ScriptingHelpers.symbol(at: key, store: store) == "star")

        try ScriptingHelpers.setSymbol("", at: key, store: store)
        #expect(store.displaySpaceSymbols["Main"]?[2]?.isEmpty == true)
        #expect(ScriptingHelpers.symbol(at: key, store: store).isEmpty)

        try ScriptingHelpers.setEmoji("🎨", at: key, store: store)
        try ScriptingHelpers.setEmoji("", at: key, store: store)
        #expect(store.displaySpaceSymbols["Main"]?[2]?.isEmpty == true)
        #expect(ScriptingHelpers.emoji(at: key, store: store).isEmpty)
    }

    @Test("reset icon clears symbol and skin tone overrides and reveals both inherited values")
    func resetIconRevealsInherited() throws {
        SpacePreferences.setSymbol("👋", forSpace: 2, store: store)
        SpacePreferences.setSkinTone(.medium, forSpace: 2, store: store)
        try ScriptingHelpers.setEmoji("🎨", at: key, store: store)
        ScriptingHelpers.setLabel("Work", at: key, store: store)
        try ScriptingHelpers.setBadge("A", at: key, store: store)
        try ScriptingHelpers.setForegroundColor("111111", at: key, darkMode: false, store: store)

        ScriptingHelpers.resetIcon(at: key, store: store)

        #expect(store.displaySpaceSymbols["Main"]?[2] == nil)
        #expect(store.displaySpaceSkinTones["Main"]?[2] == nil)
        #expect(ScriptingHelpers.emoji(at: key, store: store) == "👋🏽")
        #expect(SpacePreferences.skinTone(forSpace: 2, display: "Main", store: store) == .medium)
        #expect(SpacePreferences.label(forSpace: 2, display: "Main", store: store) == "Work")
        #expect(SpacePreferences.badge(forSpace: 2, display: "Main", store: store)?.character == "A")
        #expect(ScriptingHelpers.foregroundColor(at: key, store: store) == "111111")
    }

    @Test("reset space clears every override of the Space and nothing else")
    func resetSpaceClearsEverything() throws {
        SpacePreferences.setSymbol("star", forSpace: 2, store: store)
        SpacePreferences.setLabel("Shared", forSpace: 2, store: store)
        try ScriptingHelpers.setEmoji("🎨", at: key, store: store)
        try ScriptingHelpers.setForegroundColor("111111", at: key, darkMode: false, store: store)
        ScriptingHelpers.setLabel("Work", at: key, store: store)
        try ScriptingHelpers.setBadge("A", at: key, store: store)
        SpacePreferences.setFont(SpaceFont(font: .systemFont(ofSize: 11)), forSpace: 2, display: "Main", store: store)
        ScriptingHelpers.setLabel("Other", at: (1, "Main"), store: store)

        ScriptingHelpers.resetSpace(at: key, store: store)

        #expect(SpacePreferences.hasAnyScopedPreference(forSpace: 2, context: "Main", store: store) == false)
        #expect(ScriptingHelpers.symbol(at: key, store: store) == "star")
        #expect(SpacePreferences.label(forSpace: 2, display: "Main", store: store) == "Shared")
        #expect(SpacePreferences.badge(forSpace: 2, display: "Main", store: store) == nil)
        #expect(ScriptingHelpers.foregroundColor(at: key, store: store).isEmpty)
        #expect(SpacePreferences.label(forSpace: 1, display: "Main", store: store) == "Other")
    }

    // MARK: - Skin tone display

    @Test("display leaves an explicit default tone untouched and applies any other")
    func skinToneDisplay() {
        #expect(SkinTone.display("👍🏽", tone: .default) == "👍🏽")
        #expect(SkinTone.display("☀️", tone: .default) == "☀️")
        #expect(SkinTone.display("🫱🏽‍🫲🏻", tone: .default) == "🫱🏽‍🫲🏻")
        #expect(SkinTone.display("👍🏽", tone: .light) == "👍🏻")
        #expect(SkinTone.display("👍", tone: .dark) == "👍🏿")

        Defaults[.emojiPickerSkinTone] = .medium
        #expect(SkinTone.display("👍", tone: nil) == "👍🏽")
    }

    @Test("choosing a tone in the editor rebases a scripted toned emoji")
    func editorRebasesTonedEmoji() throws {
        let appState = makeAppState()
        let editorKey: ScriptingHelpers.SpaceKey = (1, "Main")
        try ScriptingHelpers.setEmoji("👍🏽", at: editorKey, store: store)
        let model = SpaceEditorModel(
            appState: appState,
            confirmAction: { _, _, _, _ in true },
            previewApplyDelay: .milliseconds(1)
        )
        model.selectedDisplayID = "Main"
        model.selection = .space(1)

        model.setSkinTone(.dark)
        #expect(store.displaySpaceSymbols["Main"]?[1] == "👍")
        #expect(store.displaySpaceSkinTones["Main"]?[1] == SkinTone.dark)
        #expect(ScriptingHelpers.emoji(at: editorKey, store: store) == "👍🏿")

        try ScriptingHelpers.setEmoji("👍🏽", at: editorKey, store: store)
        model.setSkinTone(.default)
        #expect(ScriptingHelpers.emoji(at: editorKey, store: store) == "👍")
    }

    // MARK: - URL patches

    @Test("spaceKey resolves the display index and position, or reports which is out of range")
    func spaceKeyResolution() throws {
        let appState = makeAppState()

        let current = try ScriptingHelpers.spaceKey(position: 2, display: nil, appState: appState)
        #expect(current.position == 2 && current.displayID == "Main")
        let side = try ScriptingHelpers.spaceKey(position: 3, display: 2, appState: appState)
        #expect(side.position == 3 && side.displayID == "Side")

        #expect(throws: AppearanceError.displayOutOfRange(requested: 3, max: 2)) {
            try ScriptingHelpers.spaceKey(position: 1, display: 3, appState: appState)
        }
        #expect(throws: AppearanceError.spaceOutOfRange(requested: 3, max: 2)) {
            try ScriptingHelpers.spaceKey(position: 3, display: nil, appState: appState)
        }
        #expect(throws: AppearanceError.spaceOutOfRange(requested: 4, max: 3)) {
            try ScriptingHelpers.spaceKey(position: 4, display: 2, appState: appState)
        }
    }

    @Test("applyAppearance writes every field of a valid patch")
    func applyAppearanceWritesAll() throws {
        let patch = AppearancePatch(
            symbol: "curlybraces",
            foreground: "cc30e0",
            background: "202020",
            symbolColor: "ffffff",
            symbolBackground: "00000080",
            label: "Code",
            badge: "#"
        )
        try ScriptingHelpers.applyAppearance(patch, at: key, darkMode: false, store: store)

        #expect(ScriptingHelpers.symbol(at: key, store: store) == "curlybraces")
        #expect(ScriptingHelpers.foregroundColor(at: key, store: store) == "CC30E0")
        #expect(ScriptingHelpers.backgroundColor(at: key, store: store) == "202020")
        #expect(ScriptingHelpers.symbolColor(at: key, store: store) == "FFFFFF")
        #expect(ScriptingHelpers.symbolBackgroundColor(at: key, store: store) == "00000080")
        #expect(SpacePreferences.label(forSpace: 2, display: "Main", store: store) == "Code")
        #expect(SpacePreferences.badge(forSpace: 2, display: "Main", store: store)?.character == "#")
    }

    @Test("applyAppearance leaves every value unchanged when any field is invalid", arguments: [
        AppearancePatch(symbol: "not.a.symbol.name", foreground: "cc30e0", label: "Code"),
        AppearancePatch(emoji: "ab", foreground: "cc30e0", label: "Code"),
        AppearancePatch(symbol: "curlybraces", foreground: "cc30e", label: "Code"),
        AppearancePatch(symbol: "curlybraces", background: "", label: "Code"),
        AppearancePatch(symbol: "curlybraces", symbolColor: "#12345", label: "Code"),
        AppearancePatch(symbol: "curlybraces", foreground: "cc30e0", label: "Code", badge: "AB"),
    ])
    func applyAppearanceIsAtomic(patch: AppearancePatch) throws {
        try ScriptingHelpers.setSymbol("star", at: key, store: store)
        try ScriptingHelpers.setForegroundColor("111111", at: key, darkMode: false, store: store)
        ScriptingHelpers.setLabel("Before", at: key, store: store)
        let symbols = store.displaySpaceSymbols
        let colors = store.displaySpaceColors
        let labels = store.displaySpaceLabels
        let badges = store.displaySpaceBadges
        let tones = store.displaySpaceSkinTones

        #expect(throws: (any Error).self) {
            try ScriptingHelpers.applyAppearance(patch, at: key, darkMode: false, store: store)
        }

        #expect(store.displaySpaceSymbols == symbols)
        #expect(store.displaySpaceColors == colors)
        #expect(store.displaySpaceLabels == labels)
        #expect(store.displaySpaceBadges == badges)
        #expect(store.displaySpaceSkinTones == tones)
    }

    @Test("empty patch values clear like the AppleScript properties")
    func applyAppearanceClears() throws {
        try ScriptingHelpers.setEmoji("🎨", at: key, store: store)
        try ScriptingHelpers.setSymbolColor("222222", at: key, darkMode: false, store: store)
        ScriptingHelpers.setLabel("Work", at: key, store: store)

        try ScriptingHelpers.applyAppearance(
            AppearancePatch(emoji: "", symbolColor: "", label: ""), at: key, darkMode: false, store: store
        )

        #expect(store.displaySpaceSymbols["Main"]?[2]?.isEmpty == true)
        #expect(ScriptingHelpers.symbolColor(at: key, store: store).isEmpty)
        #expect(SpacePreferences.label(forSpace: 2, display: "Main", store: store) == nil)
    }
}
