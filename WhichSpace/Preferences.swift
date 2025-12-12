import Cocoa
import Defaults

// MARK: - IconStyle

enum IconStyle: String, CaseIterable, Defaults.Serializable {
    case square
    case squareOutline
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
        NSLocalizedString("style_\(rawValue)", comment: "Icon style name")
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
            return try? NSKeyedArchiver.archivedData(
                withRootObject: value.font,
                requiringSecureCoding: true
            )
        }

        func deserialize(_ object: Data?) -> SpaceFont? {
            guard let object,
                  let font = try? NSKeyedUnarchiver.unarchivedObject(ofClass: NSFont.self, from: object)
            else {
                return nil
            }
            return SpaceFont(font: font)
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
            return [
                "foreground": try! NSKeyedArchiver.archivedData(
                    withRootObject: value.foreground,
                    requiringSecureCoding: true
                ),
                "background": try! NSKeyedArchiver.archivedData(
                    withRootObject: value.background,
                    requiringSecureCoding: true
                ),
            ]
        }

        // swiftlint:disable:next discouraged_optional_collection
        func deserialize(_ object: [String: Data]?) -> SpaceColors? {
            guard let object,
                  let foregroundData = object["foreground"],
                  let backgroundData = object["background"],
                  let foreground = try? NSKeyedUnarchiver.unarchivedObject(ofClass: NSColor.self, from: foregroundData),
                  let background = try? NSKeyedUnarchiver.unarchivedObject(ofClass: NSColor.self, from: backgroundData)
            else {
                return nil
            }
            return SpaceColors(foreground: foreground, background: background)
        }
    }

    static let bridge = Bridge()

    var foreground: NSColor
    var background: NSColor

    // Backwards compatibility aliases
    var foregroundColor: NSColor { foreground }
    var backgroundColor: NSColor { background }
}

// MARK: - SpacePreferences

/// Manages per-space preferences (colors, icon styles, SF symbols).
///
/// All methods accept an optional `DefaultsStore` parameter. In production, pass
/// `.shared` (the default). In tests, pass a per-test store for isolation.
///
/// When `uniqueIconsPerDisplay` is enabled, preferences are stored per-display
/// using the display identifier. When disabled, shared preferences are used.
/// Both sets of preferences are stored separately for backwards compatibility.
enum SpacePreferences {
    // MARK: - SF Symbols

    static func sfSymbol(
        forSpace spaceNumber: Int,
        display: String? = nil,
        store: DefaultsStore = .shared
    ) -> String? {
        if store.uniqueIconsPerDisplay, let display {
            return store.displaySpaceSFSymbols[display]?[spaceNumber]
        }
        return store.spaceSFSymbols[spaceNumber]
    }

    static func setSFSymbol(
        _ symbol: String?,
        forSpace spaceNumber: Int,
        display: String? = nil,
        store: DefaultsStore = .shared
    ) {
        if store.uniqueIconsPerDisplay, let display {
            var displaySymbols = store.displaySpaceSFSymbols
            var spaceSymbols = displaySymbols[display] ?? [:]
            if let symbol {
                spaceSymbols[spaceNumber] = symbol
            } else {
                spaceSymbols.removeValue(forKey: spaceNumber)
            }
            displaySymbols[display] = spaceSymbols
            store.displaySpaceSFSymbols = displaySymbols
        } else {
            if let symbol {
                store.spaceSFSymbols[spaceNumber] = symbol
            } else {
                store.spaceSFSymbols.removeValue(forKey: spaceNumber)
            }
        }
    }

    static func clearSFSymbol(forSpace spaceNumber: Int, display: String? = nil, store: DefaultsStore = .shared) {
        setSFSymbol(nil, forSpace: spaceNumber, display: display, store: store)
    }

    // MARK: - Icon Style

    static func iconStyle(
        forSpace spaceNumber: Int,
        display: String? = nil,
        store: DefaultsStore = .shared
    ) -> IconStyle? {
        if store.uniqueIconsPerDisplay, let display {
            return store.displaySpaceIconStyles[display]?[spaceNumber]
        }
        return store.spaceIconStyles[spaceNumber]
    }

    static func setIconStyle(
        _ style: IconStyle?,
        forSpace spaceNumber: Int,
        display: String? = nil,
        store: DefaultsStore = .shared
    ) {
        if store.uniqueIconsPerDisplay, let display {
            var displayStyles = store.displaySpaceIconStyles
            var spaceStyles = displayStyles[display] ?? [:]
            if let style {
                spaceStyles[spaceNumber] = style
            } else {
                spaceStyles.removeValue(forKey: spaceNumber)
            }
            displayStyles[display] = spaceStyles
            store.displaySpaceIconStyles = displayStyles
        } else {
            if let style {
                store.spaceIconStyles[spaceNumber] = style
            } else {
                store.spaceIconStyles.removeValue(forKey: spaceNumber)
            }
        }
    }

    static func clearIconStyle(forSpace spaceNumber: Int, display: String? = nil, store: DefaultsStore = .shared) {
        setIconStyle(nil, forSpace: spaceNumber, display: display, store: store)
    }

    // MARK: - Colors

    static func colors(
        forSpace spaceNumber: Int,
        display: String? = nil,
        store: DefaultsStore = .shared
    ) -> SpaceColors? {
        if store.uniqueIconsPerDisplay, let display {
            return store.displaySpaceColors[display]?[spaceNumber]
        }
        return store.spaceColors[spaceNumber]
    }

    static func setColors(
        _ colors: SpaceColors?,
        forSpace spaceNumber: Int,
        display: String? = nil,
        store: DefaultsStore = .shared
    ) {
        if store.uniqueIconsPerDisplay, let display {
            var displayColors = store.displaySpaceColors
            var spaceColors = displayColors[display] ?? [:]
            if let colors {
                spaceColors[spaceNumber] = colors
            } else {
                spaceColors.removeValue(forKey: spaceNumber)
            }
            displayColors[display] = spaceColors
            store.displaySpaceColors = displayColors
        } else {
            if let colors {
                store.spaceColors[spaceNumber] = colors
            } else {
                store.spaceColors.removeValue(forKey: spaceNumber)
            }
        }
    }

    static func clearColors(forSpace spaceNumber: Int, display: String? = nil, store: DefaultsStore = .shared) {
        setColors(nil, forSpace: spaceNumber, display: display, store: store)
    }

    // MARK: - Font

    static func font(
        forSpace spaceNumber: Int,
        display: String? = nil,
        store: DefaultsStore = .shared
    ) -> SpaceFont? {
        if store.uniqueIconsPerDisplay, let display {
            return store.displaySpaceFonts[display]?[spaceNumber]
        }
        return store.spaceFonts[spaceNumber]
    }

    static func setFont(
        _ font: SpaceFont?,
        forSpace spaceNumber: Int,
        display: String? = nil,
        store: DefaultsStore = .shared
    ) {
        if store.uniqueIconsPerDisplay, let display {
            var displayFonts = store.displaySpaceFonts
            var spaceFonts = displayFonts[display] ?? [:]
            if let font {
                spaceFonts[spaceNumber] = font
            } else {
                spaceFonts.removeValue(forKey: spaceNumber)
            }
            displayFonts[display] = spaceFonts
            store.displaySpaceFonts = displayFonts
        } else {
            if let font {
                store.spaceFonts[spaceNumber] = font
            } else {
                store.spaceFonts.removeValue(forKey: spaceNumber)
            }
        }
    }

    static func clearFont(forSpace spaceNumber: Int, display: String? = nil, store: DefaultsStore = .shared) {
        setFont(nil, forSpace: spaceNumber, display: display, store: store)
    }

    // MARK: - Clear All

    /// Clears all preferences for all displays and shared settings.
    static func clearAll(store: DefaultsStore = .shared) {
        store.spaceColors = [:]
        store.spaceIconStyles = [:]
        store.spaceSFSymbols = [:]
        store.spaceFonts = [:]
        store.displaySpaceColors = [:]
        store.displaySpaceIconStyles = [:]
        store.displaySpaceSFSymbols = [:]
        store.displaySpaceFonts = [:]
    }
}
