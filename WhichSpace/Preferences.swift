import Cocoa
import Defaults

// MARK: - IconStyle

enum IconStyle: String, CaseIterable, Defaults.Serializable {
    case square
    case squareOutline
    case rounded
    case roundedOutline
    case slim
    case slimOutline
    case circle
    case circleOutline
    case triangle
    case triangleOutline
    case pentagon
    case pentagonOutline
    case hexagon
    case hexagonOutline
    case stroke
    case transparent

    var localizedTitle: String {
        NSLocalizedString("style_\(rawValue)", comment: "")
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
                return [
                    "foreground": foregroundData,
                    "background": backgroundData,
                ]
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
                return SpaceColors(foreground: foreground, background: background)
            } catch {
                NSLog("SpaceColors: failed to unarchive colors: %@", error.localizedDescription)
                return nil
            }
        }
    }

    static let bridge = Bridge()

    var foreground: NSColor
    var background: NSColor
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

// MARK: - SpacePreferences

/// Manages per-space preferences (colors, icon styles, symbols/emojis).
///
/// All methods accept an optional `DefaultsStore` parameter. In production the
/// default is `AppEnvironment.shared.store`. In tests, pass a per-test store for isolation.
///
/// When `uniqueIconsPerDisplay` is enabled, preferences are stored per-display
/// using the display identifier. When disabled, shared preferences are used.
/// Both sets of preferences are stored separately for backwards compatibility.
@MainActor
enum SpacePreferences {
    // MARK: - Generic Accessor

    @MainActor private struct Accessor<T> {
        let shared: ReferenceWritableKeyPath<DefaultsStore, [Int: T]>
        let perDisplay: ReferenceWritableKeyPath<DefaultsStore, [String: [Int: T]]>

        func get(forSpace spaceNumber: Int, display: String?, store: DefaultsStore) -> T? {
            if store.uniqueIconsPerDisplay, let display {
                return store[keyPath: perDisplay][display]?[spaceNumber]
            }
            return store[keyPath: shared][spaceNumber]
        }

        func set(_ value: T?, forSpace spaceNumber: Int, display: String?, store: DefaultsStore) {
            if store.uniqueIconsPerDisplay, let display {
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

    // MARK: - Symbols (SF Symbols or Emojis)

    static func symbol(
        forSpace spaceNumber: Int,
        display: String? = nil,
        store: DefaultsStore = AppEnvironment.shared.store
    ) -> String? {
        symbols.get(forSpace: spaceNumber, display: display, store: store)
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
        iconStyles.get(forSpace: spaceNumber, display: display, store: store)
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
        labels.get(forSpace: spaceNumber, display: display, store: store)
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

    // MARK: - Label Style

    static func labelStyle(
        forSpace spaceNumber: Int,
        display: String? = nil,
        store: DefaultsStore = AppEnvironment.shared.store
    ) -> IconStyle? {
        labelStyles.get(forSpace: spaceNumber, display: display, store: store)
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
        colorsAccessor.get(forSpace: spaceNumber, display: display, store: store)
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
        fonts.get(forSpace: spaceNumber, display: display, store: store)
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
        badges.get(forSpace: spaceNumber, display: display, store: store)
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

    // MARK: - Skin Tone

    static func skinTone(
        forSpace spaceNumber: Int,
        display: String? = nil,
        store: DefaultsStore = AppEnvironment.shared.store
    ) -> SkinTone? {
        skinTones.get(forSpace: spaceNumber, display: display, store: store)
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
    static func copyPreferences(
        from source: Int,
        to target: Int,
        fromDisplay: String? = nil,
        toDisplay: String? = nil,
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
    }

    // MARK: - Default Style

    /// The sentinel space number used to store the default style template.
    static let defaultStyleSpace = 0

    /// Saves all preferences from the given space as the default style for new spaces.
    static func saveDefaultStyle(
        fromSpace spaceNumber: Int,
        display: String? = nil,
        store: DefaultsStore = AppEnvironment.shared.store
    ) {
        // Clear any existing default first
        clearDefaultStyle(store: store)

        // Copy each preference from the source space to the default template (space 0, no display)
        copyPreferences(from: spaceNumber, to: defaultStyleSpace, fromDisplay: display, toDisplay: nil, store: store)
    }

    /// Applies the stored default style to a new space, if a default is set.
    static func applyDefaultStyle(
        toSpace spaceNumber: Int,
        display: String? = nil,
        store: DefaultsStore = AppEnvironment.shared.store
    ) {
        guard hasAnyPreference(forSpace: defaultStyleSpace, store: store) else {
            return
        }
        copyPreferences(from: defaultStyleSpace, to: spaceNumber, fromDisplay: nil, toDisplay: display, store: store)
    }

    /// Clears the stored default style template.
    static func clearDefaultStyle(store: DefaultsStore = AppEnvironment.shared.store) {
        clearPreferences(forSpace: defaultStyleSpace, display: nil, store: store)
    }

    /// Returns true if a default style has been saved.
    static func hasDefaultStyle(store: DefaultsStore = AppEnvironment.shared.store) -> Bool {
        hasAnyPreference(forSpace: defaultStyleSpace, store: store)
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
        store.spaceFonts = [:]
        store.spaceSkinTones = [:]
        store.displaySpaceBadges = [:]
        store.displaySpaceColors = [:]
        store.displaySpaceIconStyles = [:]
        store.displaySpaceLabels = [:]
        store.displaySpaceLabelStyles = [:]
        store.displaySpaceSymbols = [:]
        store.displaySpaceFonts = [:]
        store.displaySpaceSkinTones = [:]
    }
}
