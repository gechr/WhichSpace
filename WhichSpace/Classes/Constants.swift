//
//  Constants.swift
//  WhichSpace
//
//  Created by George Christou.
//  Copyright © 2020 George Christou. All rights reserved.
//

import Cocoa

enum Layout {
    static let iconSize: CGFloat = 20
    static let statusItemWidth: CGFloat = 24
    static let statusItemHeight: CGFloat = 22
    static let statusItemSize = NSSize(width: statusItemWidth, height: statusItemHeight)
    static let menuFontSize: CGFloat = 13
}

enum IconColors {
    static let filledDarkForeground = NSColor(calibratedWhite: 0, alpha: 1)
    static let filledDarkBackground = NSColor(calibratedWhite: 0.7, alpha: 1)
    static let filledLightForeground = NSColor(calibratedWhite: 1, alpha: 1)
    static let filledLightBackground = NSColor(calibratedWhite: 0.3, alpha: 1)
    static let outlineDark = NSColor(calibratedWhite: 0.7, alpha: 1)
    static let outlineLight = NSColor(calibratedWhite: 0.3, alpha: 1)

    static func filledColors(darkMode: Bool) -> (foreground: NSColor, background: NSColor) {
        if darkMode {
            (filledDarkForeground, filledDarkBackground)
        } else {
            (filledLightForeground, filledLightBackground)
        }
    }

    static func outlineColors(darkMode: Bool) -> (foreground: NSColor, background: NSColor) {
        let color = darkMode ? outlineDark : outlineLight
        return (color, color)
    }
}
