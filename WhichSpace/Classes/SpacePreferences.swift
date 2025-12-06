//
//  SpacePreferences.swift
//  WhichSpace
//
//  Created by George Christou.
//  Copyright © 2020 George Christou. All rights reserved.
//

import Cocoa

enum IconStyle: String, CaseIterable, Codable {
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

struct SpaceColors: Codable, Equatable {
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

enum SpacePreferences {
    private static let colorsKey = "spaceColors"
    private static let iconStylesKey = "spaceIconStyles"

    // MARK: - Icon Style

    static func iconStyle(forSpace spaceNumber: Int) -> IconStyle? {
        guard let data = UserDefaults.standard.data(forKey: iconStylesKey),
              let allStyles = try? JSONDecoder().decode([Int: IconStyle].self, from: data)
        else {
            return nil
        }
        return allStyles[spaceNumber]
    }

    static func setIconStyle(_ style: IconStyle?, forSpace spaceNumber: Int) {
        var allStyles = getAllIconStyles()
        if let style {
            allStyles[spaceNumber] = style
        } else {
            allStyles.removeValue(forKey: spaceNumber)
        }
        saveAllIconStyles(allStyles)
    }

    static func clearIconStyle(forSpace spaceNumber: Int) {
        setIconStyle(nil, forSpace: spaceNumber)
    }

    private static func getAllIconStyles() -> [Int: IconStyle] {
        guard let data = UserDefaults.standard.data(forKey: iconStylesKey),
              let allStyles = try? JSONDecoder().decode([Int: IconStyle].self, from: data)
        else {
            return [:]
        }
        return allStyles
    }

    private static func saveAllIconStyles(_ styles: [Int: IconStyle]) {
        if let data = try? JSONEncoder().encode(styles) {
            UserDefaults.standard.set(data, forKey: iconStylesKey)
        }
    }

    // MARK: - Colors

    static func colors(forSpace spaceNumber: Int) -> SpaceColors? {
        guard let data = UserDefaults.standard.data(forKey: colorsKey),
              let allColors = try? JSONDecoder().decode([Int: SpaceColors].self, from: data)
        else {
            return nil
        }
        return allColors[spaceNumber]
    }

    static func setColors(_ colors: SpaceColors?, forSpace spaceNumber: Int) {
        var allColors = getAllColors()
        if let colors {
            allColors[spaceNumber] = colors
        } else {
            allColors.removeValue(forKey: spaceNumber)
        }
        saveAllColors(allColors)
    }

    static func clearColors(forSpace spaceNumber: Int) {
        setColors(nil, forSpace: spaceNumber)
    }

    private static func getAllColors() -> [Int: SpaceColors] {
        guard let data = UserDefaults.standard.data(forKey: colorsKey),
              let allColors = try? JSONDecoder().decode([Int: SpaceColors].self, from: data)
        else {
            return [:]
        }
        return allColors
    }

    private static func saveAllColors(_ colors: [Int: SpaceColors]) {
        if let data = try? JSONEncoder().encode(colors) {
            UserDefaults.standard.set(data, forKey: colorsKey)
        }
    }
}
