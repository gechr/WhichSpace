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

enum SpacePreferences {}

// MARK: - SpacePreferences + SF Symbols

extension SpacePreferences {
    static func sfSymbol(forSpace spaceNumber: Int) -> String? {
        Defaults[.spaceSFSymbols][spaceNumber]
    }

    static func setSFSymbol(_ symbol: String?, forSpace spaceNumber: Int) {
        if let symbol {
            Defaults[.spaceSFSymbols][spaceNumber] = symbol
        } else {
            Defaults[.spaceSFSymbols].removeValue(forKey: spaceNumber)
        }
    }

    static func clearSFSymbol(forSpace spaceNumber: Int) {
        Defaults[.spaceSFSymbols].removeValue(forKey: spaceNumber)
    }
}

// MARK: - SpacePreferences + Icon Style

extension SpacePreferences {
    static func iconStyle(forSpace spaceNumber: Int) -> IconStyle? {
        Defaults[.spaceIconStyles][spaceNumber]
    }

    static func setIconStyle(_ style: IconStyle?, forSpace spaceNumber: Int) {
        if let style {
            Defaults[.spaceIconStyles][spaceNumber] = style
        } else {
            Defaults[.spaceIconStyles].removeValue(forKey: spaceNumber)
        }
    }

    static func clearIconStyle(forSpace spaceNumber: Int) {
        Defaults[.spaceIconStyles].removeValue(forKey: spaceNumber)
    }
}

// MARK: - SpacePreferences + Colors

extension SpacePreferences {
    static func colors(forSpace spaceNumber: Int) -> SpaceColors? {
        Defaults[.spaceColors][spaceNumber]
    }

    static func setColors(_ colors: SpaceColors?, forSpace spaceNumber: Int) {
        if let colors {
            Defaults[.spaceColors][spaceNumber] = colors
        } else {
            Defaults[.spaceColors].removeValue(forKey: spaceNumber)
        }
    }

    static func clearColors(forSpace spaceNumber: Int) {
        Defaults[.spaceColors].removeValue(forKey: spaceNumber)
    }
}
