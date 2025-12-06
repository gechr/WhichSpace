//
//  SpacePreferences.swift
//  WhichSpace
//
//  Created by George Christou.
//  Copyright © 2020 George Christou. All rights reserved.
//

import Cocoa
import Defaults

enum IconStyle: String, CaseIterable, Codable, Defaults.Serializable {
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

struct SpaceColors: Codable, Equatable, Defaults.Serializable {
    var foreground: Data
    var background: Data

    init(foreground: NSColor, background: NSColor) {
        self.foreground = (try? NSKeyedArchiver.archivedData(
            withRootObject: foreground,
            requiringSecureCoding: false
        )) ?? Data()
        self.background = (try? NSKeyedArchiver.archivedData(
            withRootObject: background,
            requiringSecureCoding: false
        )) ?? Data()
    }

    var foregroundColor: NSColor {
        (try? NSKeyedUnarchiver.unarchivedObject(ofClass: NSColor.self, from: foreground)) ?? .white
    }

    var backgroundColor: NSColor {
        (try? NSKeyedUnarchiver.unarchivedObject(ofClass: NSColor.self, from: background)) ?? .black
    }
}

extension Defaults.Keys {
    static let spaceColors = Key<[Int: SpaceColors]>("spaceColors", default: [:])
    static let spaceIconStyles = Key<[Int: IconStyle]>("spaceIconStyles", default: [:])
    static let spaceSFSymbols = Key<[Int: String]>("spaceSFSymbols", default: [:])
}

enum SpacePreferences {
    // MARK: - SF Symbol

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

    // MARK: - All Configured Spaces

    static func allConfiguredSpaces() -> Set<Int> {
        var spaces = Set<Int>()
        spaces.formUnion(Defaults[.spaceColors].keys)
        spaces.formUnion(Defaults[.spaceIconStyles].keys)
        spaces.formUnion(Defaults[.spaceSFSymbols].keys)
        return spaces
    }

    // MARK: - Icon Style

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

    // MARK: - Colors

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
