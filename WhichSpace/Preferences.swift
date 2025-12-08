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

    var localizedTitle: String {
        NSLocalizedString("icon_style_\(rawValue)", comment: "Icon style name")
    }
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
enum SpacePreferences {
    // MARK: - SF Symbols

    static func sfSymbol(forSpace spaceNumber: Int, store: DefaultsStore = .shared) -> String? {
        store.spaceSFSymbols[spaceNumber]
    }

    static func setSFSymbol(_ symbol: String?, forSpace spaceNumber: Int, store: DefaultsStore = .shared) {
        if let symbol {
            store.spaceSFSymbols[spaceNumber] = symbol
        } else {
            store.spaceSFSymbols.removeValue(forKey: spaceNumber)
        }
    }

    static func clearSFSymbol(forSpace spaceNumber: Int, store: DefaultsStore = .shared) {
        store.spaceSFSymbols.removeValue(forKey: spaceNumber)
    }

    // MARK: - Icon Style

    static func iconStyle(forSpace spaceNumber: Int, store: DefaultsStore = .shared) -> IconStyle? {
        store.spaceIconStyles[spaceNumber]
    }

    static func setIconStyle(_ style: IconStyle?, forSpace spaceNumber: Int, store: DefaultsStore = .shared) {
        if let style {
            store.spaceIconStyles[spaceNumber] = style
        } else {
            store.spaceIconStyles.removeValue(forKey: spaceNumber)
        }
    }

    static func clearIconStyle(forSpace spaceNumber: Int, store: DefaultsStore = .shared) {
        store.spaceIconStyles.removeValue(forKey: spaceNumber)
    }

    // MARK: - Colors

    static func colors(forSpace spaceNumber: Int, store: DefaultsStore = .shared) -> SpaceColors? {
        store.spaceColors[spaceNumber]
    }

    static func setColors(_ colors: SpaceColors?, forSpace spaceNumber: Int, store: DefaultsStore = .shared) {
        if let colors {
            store.spaceColors[spaceNumber] = colors
        } else {
            store.spaceColors.removeValue(forKey: spaceNumber)
        }
    }

    static func clearColors(forSpace spaceNumber: Int, store: DefaultsStore = .shared) {
        store.spaceColors.removeValue(forKey: spaceNumber)
    }

    // MARK: - Clear All

    /// Clears all per-space preferences (colors, icon styles, SF symbols).
    static func clearAll(store: DefaultsStore = .shared) {
        store.spaceColors = [:]
        store.spaceIconStyles = [:]
        store.spaceSFSymbols = [:]
    }
}
