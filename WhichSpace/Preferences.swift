import Cocoa
import Defaults

// MARK: - IconStyle

enum IconStyle: String, CaseIterable, Defaults.Serializable {
    case circle
    case circleOutline
    case hexagon
    case hexagonOutline
    case pentagon
    case pentagonOutline
    case pill
    case pillOutline
    case slim
    case slimOutline
    case square
    case squareOutline
    case stroke
    case transparent
    case triangle
    case triangleOutline

    var localizedTitle: String {
        NSLocalizedString("style_\(rawValue)", comment: "")
    }
}

// MARK: - FullscreenIconStyle

/// How Spaces occupied by a full-screen application are rendered in the
/// status bar. String-backed so future styles (e.g. app name) can be added
/// without a key migration; an absent key resolves to `.appIcon`.
enum FullscreenIconStyle: String, CaseIterable, Defaults.Serializable {
    /// The owning application's icon
    case appIcon
    /// The classic "F" glyph
    case letter
}

// MARK: - SeparatorStyle

/// The separator drawn between display groups in the status bar.
/// String-backed so future styles can be added without a key migration;
/// an absent key resolves to `.line`.
enum SeparatorStyle: String, CaseIterable, Defaults.Serializable {
    /// A space, keeping displays apart without drawing anything between them
    case blank
    /// A stroked vertical line, the pipe look
    case line
    /// A middle dot glyph
    case middleDot
    /// A bullet glyph
    case bullet
    /// A slash glyph
    case slash

    /// The drawn character; nil for the stroked line.
    var glyph: String? {
        switch self {
        case .blank:
            " "
        case .line:
            nil
        case .middleDot:
            "·"
        case .bullet:
            "•"
        case .slash:
            "/"
        }
    }

    /// The style's character as shown in the settings dropdown; the line
    /// style reads as a pipe there.
    var pickerGlyph: String {
        glyph ?? "|"
    }

    /// The localized name shown beside the glyph in the settings dropdown.
    var localizedName: String {
        switch self {
        case .blank:
            Localization.labelSeparatorNone
        case .line:
            Localization.labelSeparatorLine
        case .middleDot:
            Localization.labelSeparatorDot
        case .bullet:
            Localization.labelSeparatorBullet
        case .slash:
            Localization.labelSeparatorSlash
        }
    }
}

// MARK: - SpaceFont

struct SpaceFont: Equatable, Defaults.Serializable {
    struct Bridge: Defaults.Bridge {
        typealias Value = SpaceFont
        typealias Serializable = Data

        func serialize(_ value: SpaceFont?) -> Data? {
            guard let value else {
                return nil
            }
            do {
                return try NSKeyedArchiver.archivedData(
                    withRootObject: value.font,
                    requiringSecureCoding: true
                )
            } catch {
                NSLog("SpaceFont: failed to archive font: %@", error.localizedDescription)
                return nil
            }
        }

        func deserialize(_ object: Data?) -> SpaceFont? {
            guard let object else {
                return nil
            }
            do {
                guard let font = try NSKeyedUnarchiver.unarchivedObject(ofClass: NSFont.self, from: object) else {
                    return nil
                }
                return SpaceFont(font: font)
            } catch {
                NSLog("SpaceFont: failed to unarchive font: %@", error.localizedDescription)
                return nil
            }
        }
    }

    static let bridge = Bridge()

    var font: NSFont
}

// MARK: - SpaceColors

struct SpaceColors: Equatable, Defaults.Serializable {
    struct Bridge: Defaults.Bridge {
        typealias Value = SpaceColors
        typealias Serializable = [String: Data]

        // swiftlint:disable:next discouraged_optional_collection
        func serialize(_ value: SpaceColors?) -> [String: Data]? {
            guard let value else {
                return nil
            }
            do {
                let foregroundData = try NSKeyedArchiver.archivedData(
                    withRootObject: value.foreground,
                    requiringSecureCoding: true
                )
                let backgroundData = try NSKeyedArchiver.archivedData(
                    withRootObject: value.background,
                    requiringSecureCoding: true
                )
                var serialized = [
                    "foreground": foregroundData,
                    "background": backgroundData,
                ]
                if let symbol = value.symbol {
                    serialized["symbol"] = try NSKeyedArchiver.archivedData(
                        withRootObject: symbol,
                        requiringSecureCoding: true
                    )
                }
                if let symbolBackground = value.symbolBackground {
                    serialized["symbolBackground"] = try NSKeyedArchiver.archivedData(
                        withRootObject: symbolBackground,
                        requiringSecureCoding: true
                    )
                }
                return serialized
            } catch {
                NSLog("SpaceColors: failed to archive colors: %@", error.localizedDescription)
                return nil
            }
        }

        // swiftlint:disable:next discouraged_optional_collection
        func deserialize(_ object: [String: Data]?) -> SpaceColors? {
            guard let object,
                  let foregroundData = object["foreground"],
                  let backgroundData = object["background"]
            else {
                return nil
            }
            do {
                guard let foreground = try NSKeyedUnarchiver.unarchivedObject(
                    ofClass: NSColor.self,
                    from: foregroundData
                ),
                    let background = try NSKeyedUnarchiver.unarchivedObject(
                        ofClass: NSColor.self,
                        from: backgroundData
                    )
                else {
                    return nil
                }
                // Absent in payloads written before these colors existed
                let symbol = try object["symbol"].flatMap {
                    try NSKeyedUnarchiver.unarchivedObject(ofClass: NSColor.self, from: $0)
                }
                let symbolBackground = try object["symbolBackground"].flatMap {
                    try NSKeyedUnarchiver.unarchivedObject(ofClass: NSColor.self, from: $0)
                }
                return SpaceColors(
                    foreground: foreground,
                    background: background,
                    symbol: symbol,
                    symbolBackground: symbolBackground
                )
            } catch {
                NSLog("SpaceColors: failed to unarchive colors: %@", error.localizedDescription)
                return nil
            }
        }
    }

    static let bridge = Bridge()

    var foreground: NSColor
    var background: NSColor
    var symbol: NSColor?
    var symbolBackground: NSColor?

    var hasVisibleSymbolBackground: Bool {
        (symbolBackground?.alphaComponent ?? 0) > 0.001
    }

    init(
        foreground: NSColor,
        background: NSColor,
        symbol: NSColor? = nil,
        symbolBackground: NSColor? = nil
    ) {
        self.foreground = foreground
        self.background = background
        self.symbol = symbol
        self.symbolBackground = symbolBackground
    }

    func inverted(for symbolLayout: CombinedSymbolLayout?) -> Self {
        var result = Self(
            foreground: background,
            background: foreground,
            symbol: symbol,
            symbolBackground: symbolBackground
        )
        switch symbolLayout {
        case .insideLabel:
            result.symbol = background
        case .outsideLabel where hasVisibleSymbolBackground:
            result.symbol = symbolBackground
            result.symbolBackground = symbol ?? foreground
        case .outsideLabel, nil:
            break
        }
        return result
    }
}

// MARK: - BadgePosition

enum BadgePosition: String, CaseIterable, Codable, Defaults.Serializable {
    case topLeft
    case topRight
    case bottomLeft
    case bottomRight
}

// MARK: - SpaceBadge

struct SpaceBadge: Codable, Equatable, Defaults.Serializable {
    let character: String
    let position: BadgePosition
}

// MARK: - SymbolPosition

/// Where a symbol/emoji is drawn relative to a custom label when both are
/// set. An absent key resolves to `.left`.
enum SymbolPosition: String, CaseIterable, Codable, Defaults.Serializable {
    case left
    case right
}

// MARK: - SymbolWrap

/// Whether the label's background shape wraps the symbol together with the
/// text, or the symbol is drawn bare beside the styled label. An absent key
/// resolves to `.inside`.
enum SymbolWrap: String, CaseIterable, Codable, Defaults.Serializable {
    case inside
    case outside
}

// MARK: - SpacePreferences

/// Manages per-space preferences (colors, icon styles, symbols/emojis).
///
/// All methods accept an optional `DefaultsStore` parameter. In production the
/// default is `AppEnvironment.shared.store`. In tests, pass a per-test store for isolation.
///
/// Preferences resolve through a scope cascade: a display's override map
/// (keyed by display identifier) wins over the shared maps, which win over
/// the default style template (space 0, always shared).
@MainActor
enum SpacePreferences {
    // MARK: - Generic Accessor

    @MainActor private struct Accessor<T> {
        let shared: ReferenceWritableKeyPath<DefaultsStore, [Int: T]>
        let perDisplay: ReferenceWritableKeyPath<DefaultsStore, [String: [Int: T]]>

        /// The value in effect at the given scope: a per-display override
        /// when one exists, otherwise the shared value.
        func get(forSpace spaceNumber: Int, display: String?, store: DefaultsStore) -> T? {
            if let display, let override = store[keyPath: perDisplay][display]?[spaceNumber] {
                return override
            }
            return store[keyPath: shared][spaceNumber]
        }

        /// Writes to the exact scope: the display's override map when
        /// `display` is set, else the shared map. A nil value removes the
        /// entry - clearing an override reveals the shared value again.
        func set(_ value: T?, forSpace spaceNumber: Int, display: String?, store: DefaultsStore) {
            if let display {
                var perDisplayMap = store[keyPath: perDisplay]
                var spaceMap = perDisplayMap[display] ?? [:]
                if let value {
                    spaceMap[spaceNumber] = value
                } else {
                    spaceMap.removeValue(forKey: spaceNumber)
                }
                perDisplayMap[display] = spaceMap
                store[keyPath: perDisplay] = perDisplayMap
            } else {
                if let value {
                    store[keyPath: shared][spaceNumber] = value
                } else {
                    store[keyPath: shared].removeValue(forKey: spaceNumber)
                }
            }
        }

        /// The value the space renders with: the effective value at its
        /// scope (override, then shared) when present, otherwise the
        /// default style template (space 0, shared storage). An own value
        /// always wins, so a stored empty-string sentinel stops the
        /// cascade before the template is consulted.
        func resolve(forSpace spaceNumber: Int, display: String?, store: DefaultsStore) -> T? {
            if let own = get(forSpace: spaceNumber, display: display, store: store) {
                return own
            }
            guard spaceNumber != SpacePreferences.defaultStyleSpace else {
                return nil
            }
            return get(forSpace: SpacePreferences.defaultStyleSpace, display: nil, store: store)
        }

        /// Reads directly from one storage family (shared when `context` is
        /// nil, else that display's map), bypassing the override cascade.
        /// Migration uses this to inspect stamped copies wherever they live.
        func raw(forSpace spaceNumber: Int, context display: String?, store: DefaultsStore) -> T? {
            if let display {
                return store[keyPath: perDisplay][display]?[spaceNumber]
            }
            return store[keyPath: shared][spaceNumber]
        }

        /// Removes a value from one storage family, bypassing the
        /// override cascade.
        func removeRaw(forSpace spaceNumber: Int, context display: String?, store: DefaultsStore) {
            if let display {
                var perDisplayMap = store[keyPath: perDisplay]
                guard var spaceMap = perDisplayMap[display] else {
                    return
                }
                spaceMap.removeValue(forKey: spaceNumber)
                perDisplayMap[display] = spaceMap
                store[keyPath: perDisplay] = perDisplayMap
            } else {
                store[keyPath: shared].removeValue(forKey: spaceNumber)
            }
        }
    }

    private static let symbols = Accessor<String>(
        shared: \.spaceSymbols, perDisplay: \.displaySpaceSymbols
    )
    private static let iconStyles = Accessor<IconStyle>(
        shared: \.spaceIconStyles, perDisplay: \.displaySpaceIconStyles
    )
    private static let colorsAccessor = Accessor<SpaceColors>(
        shared: \.spaceColors, perDisplay: \.displaySpaceColors
    )
    private static let fonts = Accessor<SpaceFont>(
        shared: \.spaceFonts, perDisplay: \.displaySpaceFonts
    )
    private static let badges = Accessor<SpaceBadge>(
        shared: \.spaceBadges, perDisplay: \.displaySpaceBadges
    )
    private static let labels = Accessor<String>(
        shared: \.spaceLabels, perDisplay: \.displaySpaceLabels
    )
    private static let labelStyles = Accessor<IconStyle>(
        shared: \.spaceLabelStyles, perDisplay: \.displaySpaceLabelStyles
    )
    private static let skinTones = Accessor<SkinTone>(
        shared: \.spaceSkinTones, perDisplay: \.displaySpaceSkinTones
    )
    private static let symbolGaps = Accessor<Double>(
        shared: \.spaceSymbolGaps, perDisplay: \.displaySpaceSymbolGaps
    )
    private static let symbolPositions = Accessor<SymbolPosition>(
        shared: \.spaceSymbolPositions, perDisplay: \.displaySpaceSymbolPositions
    )
    private static let symbolWraps = Accessor<SymbolWrap>(
        shared: \.spaceSymbolWraps, perDisplay: \.displaySpaceSymbolWraps
    )
    private static let sounds = Accessor<String>(
        shared: \.spaceSounds, perDisplay: \.displaySpaceSounds
    )

    // MARK: - Template Accessors

    /// Type-erased handle over one template-eligible accessor (every
    /// per-space preference except sound), shared by template saves and
    /// the stamped-copy migration.
    private struct TemplateAccessor {
        let clear: (Int, String?, DefaultsStore) -> Void
        let hasRaw: (Int, String?, DefaultsStore) -> Bool
        let rawMatchesTemplate: (Int, String?, DefaultsStore) -> Bool
        let removeRaw: (Int, String?, DefaultsStore) -> Void
        let displayKeys: (DefaultsStore) -> [String]
    }

    /// Colors and fonts compare through their serialized form: their
    /// NSColor/NSFont equality is representation-sensitive, while equal
    /// archives are what "same stored value" actually means here.
    private static func erase<T: Equatable>(
        _ accessor: Accessor<T>,
        equals: @escaping (T?, T?) -> Bool = { $0 == $1 }
    ) -> TemplateAccessor {
        TemplateAccessor(
            clear: { space, display, store in
                accessor.set(nil, forSpace: space, display: display, store: store)
            },
            hasRaw: { space, context, store in
                accessor.raw(forSpace: space, context: context, store: store) != nil
            },
            rawMatchesTemplate: { space, context, store in
                equals(
                    accessor.raw(forSpace: space, context: context, store: store),
                    accessor.raw(forSpace: defaultStyleSpace, context: nil, store: store)
                )
            },
            removeRaw: { space, context, store in
                accessor.removeRaw(forSpace: space, context: context, store: store)
            },
            displayKeys: { store in
                Array(store[keyPath: accessor.perDisplay].keys)
            }
        )
    }

    private static let templateAccessors: [TemplateAccessor] = [
        erase(colorsAccessor) {
            SpaceColors.bridge.serialize($0) == SpaceColors.bridge.serialize($1)
        },
        erase(fonts) {
            SpaceFont.bridge.serialize($0) == SpaceFont.bridge.serialize($1)
        },
        erase(iconStyles),
        erase(symbols),
        erase(badges),
        erase(labels),
        erase(labelStyles),
        erase(skinTones),
        erase(symbolGaps),
        erase(symbolPositions),
        erase(symbolWraps),
    ]

    // MARK: - Symbols (SF Symbols or Emojis)

    /// The getters below resolve through the default style template: a
    /// space without its own value inherits the template's, per key. A
    /// stored empty string is an explicit "none" for symbol and label -
    /// it stops the cascade and reads as nil, the same idiom
    /// `resolvedSoundName` uses for silence.
    static func symbol(
        forSpace spaceNumber: Int,
        display: String? = nil,
        store: DefaultsStore = AppEnvironment.shared.store
    ) -> String? {
        let symbol = symbols.resolve(forSpace: spaceNumber, display: display, store: store)
        return symbol?.isEmpty == false ? symbol : nil
    }

    static func setSymbol(
        _ symbol: String?,
        forSpace spaceNumber: Int,
        display: String? = nil,
        store: DefaultsStore = AppEnvironment.shared.store
    ) {
        symbols.set(symbol, forSpace: spaceNumber, display: display, store: store)
    }

    static func clearSymbol(
        forSpace spaceNumber: Int,
        display: String? = nil,
        store: DefaultsStore = AppEnvironment.shared.store
    ) {
        symbols.set(nil, forSpace: spaceNumber, display: display, store: store)
    }

    // MARK: - Icon Style

    static func iconStyle(
        forSpace spaceNumber: Int,
        display: String? = nil,
        store: DefaultsStore = AppEnvironment.shared.store
    ) -> IconStyle? {
        iconStyles.resolve(forSpace: spaceNumber, display: display, store: store)
    }

    static func setIconStyle(
        _ style: IconStyle?,
        forSpace spaceNumber: Int,
        display: String? = nil,
        store: DefaultsStore = AppEnvironment.shared.store
    ) {
        iconStyles.set(style, forSpace: spaceNumber, display: display, store: store)
    }

    static func clearIconStyle(
        forSpace spaceNumber: Int,
        display: String? = nil,
        store: DefaultsStore = AppEnvironment.shared.store
    ) {
        iconStyles.set(nil, forSpace: spaceNumber, display: display, store: store)
    }

    // MARK: - Label

    static func label(
        forSpace spaceNumber: Int,
        display: String? = nil,
        store: DefaultsStore = AppEnvironment.shared.store
    ) -> String? {
        let label = labels.resolve(forSpace: spaceNumber, display: display, store: store)
        return label?.isEmpty == false ? label : nil
    }

    static func setLabel(
        _ label: String?,
        forSpace spaceNumber: Int,
        display: String? = nil,
        store: DefaultsStore = AppEnvironment.shared.store
    ) {
        labels.set(label, forSpace: spaceNumber, display: display, store: store)
    }

    static func clearLabel(
        forSpace spaceNumber: Int,
        display: String? = nil,
        store: DefaultsStore = AppEnvironment.shared.store
    ) {
        labels.set(nil, forSpace: spaceNumber, display: display, store: store)
    }

    /// Clears the labels of all Spaces, for all displays and shared settings.
    static func clearAllLabels(store: DefaultsStore = AppEnvironment.shared.store) {
        store.spaceLabels = [:]
        store.displaySpaceLabels = [:]
    }

    // MARK: - Label Style

    static func labelStyle(
        forSpace spaceNumber: Int,
        display: String? = nil,
        store: DefaultsStore = AppEnvironment.shared.store
    ) -> IconStyle? {
        labelStyles.resolve(forSpace: spaceNumber, display: display, store: store)
    }

    static func setLabelStyle(
        _ style: IconStyle?,
        forSpace spaceNumber: Int,
        display: String? = nil,
        store: DefaultsStore = AppEnvironment.shared.store
    ) {
        labelStyles.set(style, forSpace: spaceNumber, display: display, store: store)
    }

    static func clearLabelStyle(
        forSpace spaceNumber: Int,
        display: String? = nil,
        store: DefaultsStore = AppEnvironment.shared.store
    ) {
        labelStyles.set(nil, forSpace: spaceNumber, display: display, store: store)
    }

    // MARK: - Colors

    static func colors(
        forSpace spaceNumber: Int,
        display: String? = nil,
        store: DefaultsStore = AppEnvironment.shared.store
    ) -> SpaceColors? {
        colorsAccessor.resolve(forSpace: spaceNumber, display: display, store: store)
    }

    static func setColors(
        _ colors: SpaceColors?,
        forSpace spaceNumber: Int,
        display: String? = nil,
        store: DefaultsStore = AppEnvironment.shared.store
    ) {
        colorsAccessor.set(colors, forSpace: spaceNumber, display: display, store: store)
    }

    static func clearColors(
        forSpace spaceNumber: Int,
        display: String? = nil,
        store: DefaultsStore = AppEnvironment.shared.store
    ) {
        colorsAccessor.set(nil, forSpace: spaceNumber, display: display, store: store)
    }

    // MARK: - Font

    static func font(
        forSpace spaceNumber: Int,
        display: String? = nil,
        store: DefaultsStore = AppEnvironment.shared.store
    ) -> SpaceFont? {
        fonts.resolve(forSpace: spaceNumber, display: display, store: store)
    }

    static func setFont(
        _ font: SpaceFont?,
        forSpace spaceNumber: Int,
        display: String? = nil,
        store: DefaultsStore = AppEnvironment.shared.store
    ) {
        fonts.set(font, forSpace: spaceNumber, display: display, store: store)
    }

    static func clearFont(
        forSpace spaceNumber: Int,
        display: String? = nil,
        store: DefaultsStore = AppEnvironment.shared.store
    ) {
        fonts.set(nil, forSpace: spaceNumber, display: display, store: store)
    }

    // MARK: - Badge

    static func badge(
        forSpace spaceNumber: Int,
        display: String? = nil,
        store: DefaultsStore = AppEnvironment.shared.store
    ) -> SpaceBadge? {
        badges.resolve(forSpace: spaceNumber, display: display, store: store)
    }

    static func setBadge(
        _ badge: SpaceBadge?,
        forSpace spaceNumber: Int,
        display: String? = nil,
        store: DefaultsStore = AppEnvironment.shared.store
    ) {
        badges.set(badge, forSpace: spaceNumber, display: display, store: store)
    }

    static func clearBadge(
        forSpace spaceNumber: Int,
        display: String? = nil,
        store: DefaultsStore = AppEnvironment.shared.store
    ) {
        badges.set(nil, forSpace: spaceNumber, display: display, store: store)
    }

    /// Clears the badges of all Spaces, for all displays and shared settings.
    static func clearAllBadges(store: DefaultsStore = AppEnvironment.shared.store) {
        store.spaceBadges = [:]
        store.displaySpaceBadges = [:]
    }

    // MARK: - Skin Tone

    static func skinTone(
        forSpace spaceNumber: Int,
        display: String? = nil,
        store: DefaultsStore = AppEnvironment.shared.store
    ) -> SkinTone? {
        skinTones.resolve(forSpace: spaceNumber, display: display, store: store)
    }

    static func setSkinTone(
        _ tone: SkinTone?,
        forSpace spaceNumber: Int,
        display: String? = nil,
        store: DefaultsStore = AppEnvironment.shared.store
    ) {
        skinTones.set(tone, forSpace: spaceNumber, display: display, store: store)
    }

    static func clearSkinTone(
        forSpace spaceNumber: Int,
        display: String? = nil,
        store: DefaultsStore = AppEnvironment.shared.store
    ) {
        skinTones.set(nil, forSpace: spaceNumber, display: display, store: store)
    }

    // MARK: - Symbol Gap

    static func symbolGap(
        forSpace spaceNumber: Int,
        display: String? = nil,
        store: DefaultsStore = AppEnvironment.shared.store
    ) -> Double? {
        symbolGaps.resolve(forSpace: spaceNumber, display: display, store: store)
    }

    static func setSymbolGap(
        _ gap: Double?,
        forSpace spaceNumber: Int,
        display: String? = nil,
        store: DefaultsStore = AppEnvironment.shared.store
    ) {
        symbolGaps.set(gap, forSpace: spaceNumber, display: display, store: store)
    }

    static func clearSymbolGap(
        forSpace spaceNumber: Int,
        display: String? = nil,
        store: DefaultsStore = AppEnvironment.shared.store
    ) {
        symbolGaps.set(nil, forSpace: spaceNumber, display: display, store: store)
    }

    // MARK: - Symbol Position

    static func symbolPosition(
        forSpace spaceNumber: Int,
        display: String? = nil,
        store: DefaultsStore = AppEnvironment.shared.store
    ) -> SymbolPosition? {
        symbolPositions.resolve(forSpace: spaceNumber, display: display, store: store)
    }

    static func setSymbolPosition(
        _ position: SymbolPosition?,
        forSpace spaceNumber: Int,
        display: String? = nil,
        store: DefaultsStore = AppEnvironment.shared.store
    ) {
        symbolPositions.set(position, forSpace: spaceNumber, display: display, store: store)
    }

    static func clearSymbolPosition(
        forSpace spaceNumber: Int,
        display: String? = nil,
        store: DefaultsStore = AppEnvironment.shared.store
    ) {
        symbolPositions.set(nil, forSpace: spaceNumber, display: display, store: store)
    }

    // MARK: - Symbol Wrap

    static func symbolWrap(
        forSpace spaceNumber: Int,
        display: String? = nil,
        store: DefaultsStore = AppEnvironment.shared.store
    ) -> SymbolWrap? {
        symbolWraps.resolve(forSpace: spaceNumber, display: display, store: store)
    }

    static func setSymbolWrap(
        _ wrap: SymbolWrap?,
        forSpace spaceNumber: Int,
        display: String? = nil,
        store: DefaultsStore = AppEnvironment.shared.store
    ) {
        symbolWraps.set(wrap, forSpace: spaceNumber, display: display, store: store)
    }

    static func clearSymbolWrap(
        forSpace spaceNumber: Int,
        display: String? = nil,
        store: DefaultsStore = AppEnvironment.shared.store
    ) {
        symbolWraps.set(nil, forSpace: spaceNumber, display: display, store: store)
    }

    // MARK: - Sound

    static func sound(
        forSpace spaceNumber: Int,
        display: String? = nil,
        store: DefaultsStore = AppEnvironment.shared.store
    ) -> String? {
        sounds.get(forSpace: spaceNumber, display: display, store: store)
    }

    static func setSound(
        _ sound: String?,
        forSpace spaceNumber: Int,
        display: String? = nil,
        store: DefaultsStore = AppEnvironment.shared.store
    ) {
        sounds.set(sound, forSpace: spaceNumber, display: display, store: store)
    }

    static func clearSound(
        forSpace spaceNumber: Int,
        display: String? = nil,
        store: DefaultsStore = AppEnvironment.shared.store
    ) {
        sounds.set(nil, forSpace: spaceNumber, display: display, store: store)
    }

    /// The effective Space-change sound: the per-space override when set
    /// ("" = explicitly silent), otherwise the global default ("" = none).
    /// Returns nil when no sound should play.
    static func resolvedSoundName(
        forSpace spaceNumber: Int,
        display: String? = nil,
        store: DefaultsStore = AppEnvironment.shared.store
    ) -> String? {
        let name = sounds.get(forSpace: spaceNumber, display: display, store: store) ?? store.soundName
        return name.isEmpty ? nil : name
    }

    // MARK: - Inheritance

    /// Returns true if the space has any per-space preference set.
    static func hasAnyPreference(
        forSpace spaceNumber: Int,
        display: String? = nil,
        store: DefaultsStore = AppEnvironment.shared.store
    ) -> Bool {
        colorsAccessor.get(forSpace: spaceNumber, display: display, store: store) != nil
            || iconStyles.get(forSpace: spaceNumber, display: display, store: store) != nil
            || fonts.get(forSpace: spaceNumber, display: display, store: store) != nil
            || symbols.get(forSpace: spaceNumber, display: display, store: store) != nil
            || badges.get(forSpace: spaceNumber, display: display, store: store) != nil
            || labels.get(forSpace: spaceNumber, display: display, store: store) != nil
            || labelStyles.get(forSpace: spaceNumber, display: display, store: store) != nil
            || skinTones.get(forSpace: spaceNumber, display: display, store: store) != nil
            || symbolGaps.get(forSpace: spaceNumber, display: display, store: store) != nil
            || symbolPositions.get(forSpace: spaceNumber, display: display, store: store) != nil
            || symbolWraps.get(forSpace: spaceNumber, display: display, store: store) != nil
            || sounds.get(forSpace: spaceNumber, display: display, store: store) != nil
    }

    /// Returns true if the space has any preference stored at exactly the
    /// given scope (shared when `context` is nil, else that display's
    /// overrides), without the cascade - what `clearPreferences` for the
    /// same scope would remove.
    static func hasAnyScopedPreference(
        forSpace spaceNumber: Int,
        context display: String? = nil,
        store: DefaultsStore = AppEnvironment.shared.store
    ) -> Bool {
        colorsAccessor.raw(forSpace: spaceNumber, context: display, store: store) != nil
            || iconStyles.raw(forSpace: spaceNumber, context: display, store: store) != nil
            || fonts.raw(forSpace: spaceNumber, context: display, store: store) != nil
            || symbols.raw(forSpace: spaceNumber, context: display, store: store) != nil
            || badges.raw(forSpace: spaceNumber, context: display, store: store) != nil
            || labels.raw(forSpace: spaceNumber, context: display, store: store) != nil
            || labelStyles.raw(forSpace: spaceNumber, context: display, store: store) != nil
            || skinTones.raw(forSpace: spaceNumber, context: display, store: store) != nil
            || symbolGaps.raw(forSpace: spaceNumber, context: display, store: store) != nil
            || symbolPositions.raw(forSpace: spaceNumber, context: display, store: store) != nil
            || symbolWraps.raw(forSpace: spaceNumber, context: display, store: store) != nil
            || sounds.raw(forSpace: spaceNumber, context: display, store: store) != nil
    }

    /// Copies all per-space preferences from one space to another.
    /// Only copies preferences that exist on the source; does not clear existing target preferences.
    static func copyPreferences(
        from source: Int,
        to target: Int,
        display: String? = nil,
        store: DefaultsStore = AppEnvironment.shared.store
    ) {
        copyPreferences(from: source, to: target, fromDisplay: display, toDisplay: display, store: store)
    }

    /// Copies all per-space preferences between spaces, allowing different source/target displays.
    /// `includeSound` is false only when saving the default style template, which never holds a
    /// sound - the template row edits the live global default instead.
    static func copyPreferences(
        from source: Int,
        to target: Int,
        fromDisplay: String? = nil,
        toDisplay: String? = nil,
        includeSound: Bool = true,
        store: DefaultsStore = AppEnvironment.shared.store
    ) {
        if let colors = colorsAccessor.get(forSpace: source, display: fromDisplay, store: store) {
            colorsAccessor.set(colors, forSpace: target, display: toDisplay, store: store)
        }
        if let style = iconStyles.get(forSpace: source, display: fromDisplay, store: store) {
            iconStyles.set(style, forSpace: target, display: toDisplay, store: store)
        }
        if let font = fonts.get(forSpace: source, display: fromDisplay, store: store) {
            fonts.set(font, forSpace: target, display: toDisplay, store: store)
        }
        if let symbol = symbols.get(forSpace: source, display: fromDisplay, store: store) {
            symbols.set(symbol, forSpace: target, display: toDisplay, store: store)
        }
        if let badge = badges.get(forSpace: source, display: fromDisplay, store: store) {
            badges.set(badge, forSpace: target, display: toDisplay, store: store)
        }
        if let label = labels.get(forSpace: source, display: fromDisplay, store: store) {
            labels.set(label, forSpace: target, display: toDisplay, store: store)
        }
        if let labelStyle = labelStyles.get(forSpace: source, display: fromDisplay, store: store) {
            labelStyles.set(labelStyle, forSpace: target, display: toDisplay, store: store)
        }
        if let tone = skinTones.get(forSpace: source, display: fromDisplay, store: store) {
            skinTones.set(tone, forSpace: target, display: toDisplay, store: store)
        }
        if let gap = symbolGaps.get(forSpace: source, display: fromDisplay, store: store) {
            symbolGaps.set(gap, forSpace: target, display: toDisplay, store: store)
        }
        if let position = symbolPositions.get(forSpace: source, display: fromDisplay, store: store) {
            symbolPositions.set(position, forSpace: target, display: toDisplay, store: store)
        }
        if let wrap = symbolWraps.get(forSpace: source, display: fromDisplay, store: store) {
            symbolWraps.set(wrap, forSpace: target, display: toDisplay, store: store)
        }
        if includeSound, let sound = sounds.get(forSpace: source, display: fromDisplay, store: store) {
            sounds.set(sound, forSpace: target, display: toDisplay, store: store)
        }
    }

    /// Clears all preferences for a specific space.
    static func clearPreferences(
        forSpace spaceNumber: Int,
        display: String? = nil,
        store: DefaultsStore = AppEnvironment.shared.store
    ) {
        colorsAccessor.set(nil, forSpace: spaceNumber, display: display, store: store)
        iconStyles.set(nil, forSpace: spaceNumber, display: display, store: store)
        fonts.set(nil, forSpace: spaceNumber, display: display, store: store)
        symbols.set(nil, forSpace: spaceNumber, display: display, store: store)
        badges.set(nil, forSpace: spaceNumber, display: display, store: store)
        labels.set(nil, forSpace: spaceNumber, display: display, store: store)
        labelStyles.set(nil, forSpace: spaceNumber, display: display, store: store)
        skinTones.set(nil, forSpace: spaceNumber, display: display, store: store)
        symbolGaps.set(nil, forSpace: spaceNumber, display: display, store: store)
        symbolPositions.set(nil, forSpace: spaceNumber, display: display, store: store)
        symbolWraps.set(nil, forSpace: spaceNumber, display: display, store: store)
        sounds.set(nil, forSpace: spaceNumber, display: display, store: store)
    }

    // MARK: - Default Style

    /// The sentinel space number used to store the default style template.
    static let defaultStyleSpace = 0

    /// Saves all preferences from the given space as the default style, then
    /// clears the source's own copies: they are identical to the template it
    /// just became, and only as an inheritor does it track future template
    /// edits. Sound stays out of the template - the template row edits the
    /// live global default instead.
    static func saveDefaultStyle(
        fromSpace spaceNumber: Int,
        display: String? = nil,
        store: DefaultsStore = AppEnvironment.shared.store
    ) {
        // Clear any existing default first
        clearDefaultStyle(store: store)

        copyPreferences(
            from: spaceNumber,
            to: defaultStyleSpace,
            fromDisplay: display,
            toDisplay: nil,
            includeSound: false,
            store: store
        )

        for accessor in templateAccessors {
            accessor.clear(spaceNumber, display, store)
        }
    }

    /// Clears the stored default style template.
    static func clearDefaultStyle(store: DefaultsStore = AppEnvironment.shared.store) {
        clearPreferences(forSpace: defaultStyleSpace, display: nil, store: store)
    }

    /// Returns true if a default style has been saved.
    static func hasDefaultStyle(store: DefaultsStore = AppEnvironment.shared.store) -> Bool {
        hasAnyPreference(forSpace: defaultStyleSpace, store: store)
    }

    // MARK: - Migration

    /// One-time upgrade for installs from when the default style was stamped
    /// onto each new Space at creation. A Space whose stored template-eligible
    /// preferences exactly match the template - same keys present, equal
    /// values - loses its copies and becomes a live inheritor, rendering
    /// identically. Any difference leaves the Space untouched, and sound is
    /// never compared or removed. Both storage families are scanned, since
    /// stamps landed wherever the per-display toggle pointed at the time.
    /// `snapshot` runs once before anything is stripped.
    static func migrateStampedTemplateCopies(
        store: DefaultsStore = AppEnvironment.shared.store,
        snapshot: () -> Void = {}
    ) {
        guard store.spaceStyleMigrationVersion < 1 else {
            return
        }
        defer {
            store.spaceStyleMigrationVersion = 1
        }
        guard hasDefaultStyle(store: store) else {
            return
        }
        snapshot()

        let displays = Set(templateAccessors.flatMap { $0.displayKeys(store) })
        let contexts: [String?] = [nil] + displays.sorted()
        for context in contexts {
            for space in 1 ... Layout.maxSpacesPerDisplay {
                let hasAny = templateAccessors.contains { $0.hasRaw(space, context, store) }
                let matchesTemplate = templateAccessors.allSatisfy {
                    $0.rawMatchesTemplate(space, context, store)
                }
                guard hasAny, matchesTemplate else {
                    continue
                }
                for accessor in templateAccessors {
                    accessor.removeRaw(space, context, store)
                }
            }
        }
    }

    /// One-time upgrade from the "Separate icons per Display" toggle to
    /// the scope cascade, where per-display entries always override the
    /// shared maps. Purges whichever storage family the toggle kept
    /// invisible, so every install renders identically after the switch:
    /// with the toggle off the per-display maps were dead data; with it
    /// on, the shared per-space entries were. The template (space 0) was
    /// live either way and stays. `snapshot` runs once before anything is
    /// purged.
    static func migrateDisplayScopeOverrides(
        store: DefaultsStore = AppEnvironment.shared.store,
        snapshot: () -> Void = {}
    ) {
        guard store.spaceStyleMigrationVersion < 2 else {
            return
        }
        defer {
            store.spaceStyleMigrationVersion = 2
        }
        let legacyKey = "uniqueIconsPerDisplay"
        let wasPerDisplay = store.suite.bool(forKey: legacyKey)
        defer {
            store.suite.removeObject(forKey: legacyKey)
        }
        let needsPurge = wasPerDisplay
            ? [
                Array(store.spaceBadges.keys), Array(store.spaceColors.keys),
                Array(store.spaceIconStyles.keys), Array(store.spaceLabels.keys),
                Array(store.spaceLabelStyles.keys), Array(store.spaceSymbols.keys),
                Array(store.spaceSymbolGaps.keys), Array(store.spaceSymbolPositions.keys),
                Array(store.spaceSymbolWraps.keys), Array(store.spaceFonts.keys),
                Array(store.spaceSkinTones.keys), Array(store.spaceSounds.keys),
            ].contains { $0.contains { $0 != defaultStyleSpace } }
            : ![
                store.displaySpaceBadges.isEmpty, store.displaySpaceColors.isEmpty,
                store.displaySpaceIconStyles.isEmpty, store.displaySpaceLabels.isEmpty,
                store.displaySpaceLabelStyles.isEmpty, store.displaySpaceSymbols.isEmpty,
                store.displaySpaceSymbolGaps.isEmpty, store.displaySpaceSymbolPositions.isEmpty,
                store.displaySpaceSymbolWraps.isEmpty, store.displaySpaceFonts.isEmpty,
                store.displaySpaceSkinTones.isEmpty, store.displaySpaceSounds.isEmpty,
            ].allSatisfy(\.self)
        guard needsPurge else {
            return
        }
        snapshot()
        purgeHiddenScopeData(perDisplayWasEnabled: wasPerDisplay, store: store)
    }

    /// Removes the storage family the retired per-display toggle kept
    /// invisible, so the scope cascade renders exactly what the toggle
    /// state did. Backup restore uses this too for legacy backup files.
    static func purgeHiddenScopeData(perDisplayWasEnabled: Bool, store: DefaultsStore) {
        if perDisplayWasEnabled {
            store.spaceBadges = store.spaceBadges.filter { $0.key == defaultStyleSpace }
            store.spaceColors = store.spaceColors.filter { $0.key == defaultStyleSpace }
            store.spaceIconStyles = store.spaceIconStyles.filter { $0.key == defaultStyleSpace }
            store.spaceLabels = store.spaceLabels.filter { $0.key == defaultStyleSpace }
            store.spaceLabelStyles = store.spaceLabelStyles.filter { $0.key == defaultStyleSpace }
            store.spaceSymbols = store.spaceSymbols.filter { $0.key == defaultStyleSpace }
            store.spaceSymbolGaps = store.spaceSymbolGaps.filter { $0.key == defaultStyleSpace }
            store.spaceSymbolPositions = store.spaceSymbolPositions.filter { $0.key == defaultStyleSpace }
            store.spaceSymbolWraps = store.spaceSymbolWraps.filter { $0.key == defaultStyleSpace }
            store.spaceFonts = store.spaceFonts.filter { $0.key == defaultStyleSpace }
            store.spaceSkinTones = store.spaceSkinTones.filter { $0.key == defaultStyleSpace }
            store.spaceSounds = store.spaceSounds.filter { $0.key == defaultStyleSpace }
        } else {
            store.displaySpaceBadges = [:]
            store.displaySpaceColors = [:]
            store.displaySpaceIconStyles = [:]
            store.displaySpaceLabels = [:]
            store.displaySpaceLabelStyles = [:]
            store.displaySpaceSymbols = [:]
            store.displaySpaceSymbolGaps = [:]
            store.displaySpaceSymbolPositions = [:]
            store.displaySpaceSymbolWraps = [:]
            store.displaySpaceFonts = [:]
            store.displaySpaceSkinTones = [:]
            store.displaySpaceSounds = [:]
        }
    }

    // MARK: - Clear All

    /// Clears all preferences for all displays and shared settings.
    static func clearAll(store: DefaultsStore = AppEnvironment.shared.store) {
        store.spaceBadges = [:]
        store.spaceColors = [:]
        store.spaceIconStyles = [:]
        store.spaceLabels = [:]
        store.spaceLabelStyles = [:]
        store.spaceSymbols = [:]
        store.spaceSymbolGaps = [:]
        store.spaceSymbolPositions = [:]
        store.spaceSymbolWraps = [:]
        store.spaceFonts = [:]
        store.spaceSkinTones = [:]
        store.spaceSounds = [:]
        store.displaySpaceBadges = [:]
        store.displaySpaceColors = [:]
        store.displaySpaceIconStyles = [:]
        store.displaySpaceLabels = [:]
        store.displaySpaceLabelStyles = [:]
        store.displaySpaceSymbols = [:]
        store.displaySpaceSymbolGaps = [:]
        store.displaySpaceSymbolPositions = [:]
        store.displaySpaceSymbolWraps = [:]
        store.displaySpaceFonts = [:]
        store.displaySpaceSkinTones = [:]
        store.displaySpaceSounds = [:]
    }
}
