import Cocoa
import Defaults

// MARK: - IconStyle

enum IconStyle: String, CaseIterable, Defaults.Serializable {
    case square
    case squareOutline
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
        String(localized: String.LocalizationValue("style_\(rawValue)"))
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

    // MARK: - Clear All

    /// Clears all preferences for all displays and shared settings.
    static func clearAll(store: DefaultsStore = AppEnvironment.shared.store) {
        store.spaceColors = [:]
        store.spaceIconStyles = [:]
        store.spaceSymbols = [:]
        store.spaceFonts = [:]
        store.spaceSkinTones = [:]
        store.displaySpaceColors = [:]
        store.displaySpaceIconStyles = [:]
        store.displaySpaceSymbols = [:]
        store.displaySpaceFonts = [:]
        store.displaySpaceSkinTones = [:]
    }
}
