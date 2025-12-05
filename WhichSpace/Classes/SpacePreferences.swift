//
//  SpacePreferences.swift
//  WhichSpace
//
//  Created by George Christou.
//  Copyright © 2020 George Christou. All rights reserved.
//

import Cocoa

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
    private static let userDefaultsKey = "spaceColors"

    static func colors(forSpace spaceNumber: Int) -> SpaceColors? {
        guard let data = UserDefaults.standard.data(forKey: userDefaultsKey),
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
        guard let data = UserDefaults.standard.data(forKey: userDefaultsKey),
              let allColors = try? JSONDecoder().decode([Int: SpaceColors].self, from: data)
        else {
            return [:]
        }
        return allColors
    }

    private static func saveAllColors(_ colors: [Int: SpaceColors]) {
        if let data = try? JSONEncoder().encode(colors) {
            UserDefaults.standard.set(data, forKey: userDefaultsKey)
        }
    }
}
