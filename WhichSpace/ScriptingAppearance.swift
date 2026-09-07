import Cocoa

/// The scripting surface's colour form: "RRGGBB" or "RRGGBBAA",
/// case-insensitive on input and uppercase on output. Colours are parsed
/// and reported in sRGB, matching the JSON backup format.
enum HexColor {
    static func parse(_ text: String) -> NSColor? {
        let digits = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard digits.count == 6 || digits.count == 8,
              digits.allSatisfy(\.isHexDigit),
              let value = UInt32(digits, radix: 16)
        else {
            return nil
        }
        let hasAlpha = digits.count == 8
        let rgb = hasAlpha ? value >> 8 : value
        let alpha = hasAlpha ? Double(value & 0xFF) / 255 : 1
        return NSColor(
            srgbRed: Double((rgb >> 16) & 0xFF) / 255,
            green: Double((rgb >> 8) & 0xFF) / 255,
            blue: Double(rgb & 0xFF) / 255,
            alpha: alpha
        )
    }

    /// Six digits when the colour is opaque, eight otherwise (including a
    /// zero alpha), so a stored translucency always survives a round trip.
    static func format(_ color: NSColor) -> String {
        let srgb = color.usingColorSpace(.sRGB) ?? color
        let rgb = String(
            format: "%02X%02X%02X",
            byte(srgb.redComponent),
            byte(srgb.greenComponent),
            byte(srgb.blueComponent)
        )
        let alpha = byte(srgb.alphaComponent)
        return alpha == 0xFF ? rgb : rgb + String(format: "%02X", alpha)
    }

    private static func byte(_ component: Double) -> Int {
        Int((component.clamped(to: 0 ... 1) * 255).rounded())
    }
}

/// Errors thrown by the appearance setters. Surfaces to AppleScript
/// callers via `NSScriptCommand.scriptErrorString` and to URL callers
/// through an alert.
enum AppearanceError: LocalizedError, Equatable {
    case invalidColor
    case colorResetRequired
    case unknownSymbol
    case notASingleEmoji
    case displayOutOfRange(requested: Int, max: Int)
    case spaceOutOfRange(requested: Int, max: Int)

    var errorDescription: String? {
        switch self {
        case .invalidColor:
            Localization.errorScriptingExpectedHexColor
        case .colorResetRequired:
            Localization.errorScriptingColorResetRequired
        case .unknownSymbol:
            Localization.errorScriptingUnknownSymbol
        case .notASingleEmoji:
            Localization.errorScriptingExpectedSingleEmoji
        case let .displayOutOfRange(requested, max):
            String(format: Localization.errorScriptingDisplayOutOfRange, requested, max)
        case let .spaceOutOfRange(requested, max):
            String(format: Localization.errorScriptingSpaceOutOfRange, requested, max)
        }
    }
}

/// The appearance fields a `whichspace://space/N` URL can carry. A nil
/// field is untouched; an empty string is the same clear the matching
/// AppleScript property performs.
struct AppearancePatch: Equatable {
    var symbol: String?
    var emoji: String?
    var foreground: String?
    var background: String?
    var symbolColor: String?
    var symbolBackground: String?
    var label: String?
    var badge: String?

    var isEmpty: Bool {
        [symbol, emoji, foreground, background, symbolColor, symbolBackground, label, badge]
            .allSatisfy { $0 == nil }
    }
}

/// Per-Space appearance for the scripting and URL surfaces. Every write
/// lands in the display-override tier, the same tier labels and badges
/// use, so a clear reveals the shared or default-style value beneath it.
extension ScriptingHelpers {
    typealias SpaceKey = (position: Int, displayID: String?)

    // MARK: - Getters

    /// The stored SF Symbol name, or "" when the Space shows an emoji or
    /// no symbol.
    static func symbol(at key: SpaceKey, store: DefaultsStore) -> String {
        guard let symbol = SpacePreferences.symbol(forSpace: key.position, display: key.displayID, store: store),
              !symbol.containsEmoji
        else {
            return ""
        }
        return symbol
    }

    /// The stored emoji with its skin tone applied, or "" when the Space
    /// shows an SF Symbol or no symbol. A scripted emoji is stored with an
    /// explicit default tone, so it reads back exactly as written.
    static func emoji(at key: SpaceKey, store: DefaultsStore) -> String {
        guard let symbol = SpacePreferences.symbol(forSpace: key.position, display: key.displayID, store: store),
              symbol.containsEmoji
        else {
            return ""
        }
        let tone = SpacePreferences.skinTone(forSpace: key.position, display: key.displayID, store: store) ?? .default
        return SkinTone.display(symbol, tone: tone)
    }

    static func foregroundColor(at key: SpaceKey, store: DefaultsStore) -> String {
        colors(at: key, store: store).map { HexColor.format($0.foreground) } ?? ""
    }

    static func backgroundColor(at key: SpaceKey, store: DefaultsStore) -> String {
        colors(at: key, store: store).map { HexColor.format($0.background) } ?? ""
    }

    /// "" when the symbol follows the foreground colour.
    static func symbolColor(at key: SpaceKey, store: DefaultsStore) -> String {
        colors(at: key, store: store)?.symbol.map(HexColor.format) ?? ""
    }

    /// "" when the symbol has no background chip.
    static func symbolBackgroundColor(at key: SpaceKey, store: DefaultsStore) -> String {
        colors(at: key, store: store)?.symbolBackground.map(HexColor.format) ?? ""
    }

    private static func colors(at key: SpaceKey, store: DefaultsStore) -> SpaceColors? {
        SpacePreferences.colors(forSpace: key.position, display: key.displayID, store: store)
    }

    // MARK: - Symbol and emoji

    /// Applies an SF Symbol by name; "" removes the icon. The empty string
    /// is stored as the explicit "none" sentinel, as the Settings editor
    /// writes, so a default-style symbol cannot bleed back through.
    static func setSymbol(_ name: String, at key: SpaceKey, store: DefaultsStore) throws(AppearanceError) {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else {
            SpacePreferences.setSymbol("", forSpace: key.position, display: key.displayID, store: store)
            return
        }
        try validateSymbol(name)
        SpacePreferences.setSymbol(name, forSpace: key.position, display: key.displayID, store: store)
    }

    /// Applies a single emoji exactly as written, including any skin tone
    /// modifiers, alongside an explicit default tone so the renderer draws
    /// it unchanged. "" removes the icon.
    static func setEmoji(_ emoji: String, at key: SpaceKey, store: DefaultsStore) throws(AppearanceError) {
        let emoji = emoji.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !emoji.isEmpty else {
            SpacePreferences.setSymbol("", forSpace: key.position, display: key.displayID, store: store)
            return
        }
        try validateEmoji(emoji)
        SpacePreferences.setSymbol(emoji, forSpace: key.position, display: key.displayID, store: store)
        SpacePreferences.setSkinTone(.default, forSpace: key.position, display: key.displayID, store: store)
    }

    /// Clears the symbol and skin tone overrides so the Space shows the
    /// shared or default-style icon again.
    static func resetIcon(at key: SpaceKey, store: DefaultsStore) {
        SpacePreferences.clearSymbol(forSpace: key.position, display: key.displayID, store: store)
        SpacePreferences.clearSkinTone(forSpace: key.position, display: key.displayID, store: store)
    }

    /// Clears every override of the Space, as the Reset button in Settings
    /// does, so it follows the shared or default style again.
    static func resetSpace(at key: SpaceKey, store: DefaultsStore) {
        SpacePreferences.clearPreferences(forSpace: key.position, display: key.displayID, store: store)
    }

    private static func validateSymbol(_ name: String) throws(AppearanceError) {
        guard ItemData.symbols.contains(name) else {
            throw .unknownSymbol
        }
    }

    private static func validateEmoji(_ emoji: String) throws(AppearanceError) {
        guard emoji.count == 1, emoji.containsEmoji else {
            throw .notASingleEmoji
        }
    }

    // MARK: - Colors

    /// Foreground and background are stored as a pair: setting one fills
    /// the other from the current appearance default, as the Settings
    /// editor does. "" is refused because the pair cannot be cleared one
    /// channel at a time; `resetColors` clears the whole bundle.
    static func setForegroundColor(
        _ text: String,
        at key: SpaceKey,
        darkMode: Bool,
        store: DefaultsStore
    ) throws(AppearanceError) {
        let color = try requiredColor(text)
        updateColors(at: key, darkMode: darkMode, store: store) { $0.foreground = color }
    }

    static func setBackgroundColor(
        _ text: String,
        at key: SpaceKey,
        darkMode: Bool,
        store: DefaultsStore
    ) throws(AppearanceError) {
        let color = try requiredColor(text)
        updateColors(at: key, darkMode: darkMode, store: store) { $0.background = color }
    }

    /// "" clears the channel so the symbol follows the foreground again; a
    /// no-op when the Space has no colours at all.
    static func setSymbolColor(
        _ text: String,
        at key: SpaceKey,
        darkMode: Bool,
        store: DefaultsStore
    ) throws(AppearanceError) {
        let color = try optionalColor(text)
        guard color != nil || colors(at: key, store: store) != nil else {
            return
        }
        updateColors(at: key, darkMode: darkMode, store: store) { $0.symbol = color }
    }

    /// "" clears the channel so the symbol draws without a background chip;
    /// a no-op when the Space has no colours at all.
    static func setSymbolBackgroundColor(
        _ text: String,
        at key: SpaceKey,
        darkMode: Bool,
        store: DefaultsStore
    ) throws(AppearanceError) {
        let color = try optionalColor(text)
        guard color != nil || colors(at: key, store: store) != nil else {
            return
        }
        updateColors(at: key, darkMode: darkMode, store: store) { $0.symbolBackground = color }
    }

    /// Clears the colour override so the Space follows the shared or
    /// default-style colours again.
    static func resetColors(at key: SpaceKey, store: DefaultsStore) {
        SpacePreferences.clearColors(forSpace: key.position, display: key.displayID, store: store)
    }

    private static func requiredColor(_ text: String) throws(AppearanceError) -> NSColor {
        guard let color = try optionalColor(text) else {
            throw .colorResetRequired
        }
        return color
    }

    private static func optionalColor(_ text: String) throws(AppearanceError) -> NSColor? {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            return nil
        }
        guard let color = HexColor.parse(text) else {
            throw .invalidColor
        }
        return color
    }

    private static func updateColors(
        at key: SpaceKey,
        darkMode: Bool,
        store: DefaultsStore,
        _ mutate: (inout SpaceColors) -> Void
    ) {
        let defaults = IconColors.filledColors(darkMode: darkMode)
        var colors = colors(at: key, store: store)
            ?? SpaceColors(foreground: defaults.foreground, background: defaults.background)
        mutate(&colors)
        SpacePreferences.setColors(colors, forSpace: key.position, display: key.displayID, store: store)
    }

    // MARK: - URL patches

    /// Resolves a URL's positional address to the preference key it names:
    /// the display by its 1-based picker index (the current display when
    /// nil), then the fullscreen-inclusive position on it.
    static func spaceKey(
        position: Int,
        display: Int?,
        appState: AppState
    ) throws(AppearanceError) -> SpaceKey {
        let displays = appState.allDisplaysSpaceInfo
        let info: DisplaySpaceInfo?
        if let display {
            guard displays.indices.contains(display - 1) else {
                throw .displayOutOfRange(requested: display, max: displays.count)
            }
            info = displays[display - 1]
        } else {
            info = displays.first { $0.displayID == appState.currentDisplayID }
        }
        guard let info, info.entries.indices.contains(position - 1) else {
            throw .spaceOutOfRange(requested: position, max: info?.entries.count ?? 0)
        }
        return (position, info.displayID)
    }

    /// Validates every field of the patch, then applies them all. An
    /// invalid field leaves the Space untouched.
    static func applyAppearance(
        _ patch: AppearancePatch,
        at key: SpaceKey,
        darkMode: Bool,
        store: DefaultsStore
    ) throws {
        var writes: [() throws -> Void] = []
        if let symbol = patch.symbol {
            let trimmed = symbol.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                try validateSymbol(trimmed)
            }
            writes.append { try setSymbol(symbol, at: key, store: store) }
        }
        if let emoji = patch.emoji {
            let trimmed = emoji.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                try validateEmoji(trimmed)
            }
            writes.append { try setEmoji(emoji, at: key, store: store) }
        }
        if let foreground = patch.foreground {
            _ = try requiredColor(foreground)
            writes.append { try setForegroundColor(foreground, at: key, darkMode: darkMode, store: store) }
        }
        if let background = patch.background {
            _ = try requiredColor(background)
            writes.append { try setBackgroundColor(background, at: key, darkMode: darkMode, store: store) }
        }
        if let symbolColor = patch.symbolColor {
            _ = try optionalColor(symbolColor)
            writes.append { try setSymbolColor(symbolColor, at: key, darkMode: darkMode, store: store) }
        }
        if let symbolBackground = patch.symbolBackground {
            _ = try optionalColor(symbolBackground)
            writes.append {
                try setSymbolBackgroundColor(symbolBackground, at: key, darkMode: darkMode, store: store)
            }
        }
        if let label = patch.label {
            writes.append { setLabel(label, at: key, store: store) }
        }
        if let badge = patch.badge {
            let trimmed = badge.trimmingCharacters(in: .whitespacesAndNewlines)
            guard trimmed.isEmpty || trimmed.count == 1 else {
                throw BadgeError.notASingleCharacter
            }
            writes.append { try setBadge(badge, at: key, store: store) }
        }
        for write in writes {
            try write()
        }
    }
}
