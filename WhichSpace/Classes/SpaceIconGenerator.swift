//
//  SpaceIconGenerator.swift
//  WhichSpace
//
//  Created by George Christou.
//  Copyright © 2020 George Christou. All rights reserved.
//

import Cocoa

/// Generates status bar icon images using only public APIs
enum SpaceIconGenerator {
    private static let iconSize: CGFloat = 20
    private static let cornerRadius: CGFloat = 4
    private static let fontSize: CGFloat = 14
    private static let statusItemSize = NSSize(width: 24, height: 22)

    static func generateIcon(
        for spaceNumber: String,
        darkMode: Bool,
        customColors: SpaceColors? = nil
    ) -> NSImage {
        let image = NSImage(size: statusItemSize, flipped: false) { rect in
            let foregroundColor: NSColor
            let backgroundColor: NSColor

            if let customColors {
                foregroundColor = customColors.foregroundColor
                backgroundColor = customColors.backgroundColor
            } else if darkMode {
                foregroundColor = NSColor(calibratedWhite: 0, alpha: 1)
                backgroundColor = NSColor(calibratedWhite: 0.7, alpha: 1)
            } else {
                foregroundColor = NSColor(calibratedWhite: 1, alpha: 1)
                backgroundColor = NSColor(calibratedWhite: 0.3, alpha: 1)
            }

            // Center the rounded rect within the status item
            let xStart = (rect.width - iconSize) / 2
            let yStart = (rect.height - iconSize) / 2
            let backgroundRect = NSRect(x: xStart, y: yStart, width: iconSize, height: iconSize)

            // Draw rounded rectangle background
            let roundedPath = NSBezierPath(roundedRect: backgroundRect, xRadius: cornerRadius, yRadius: cornerRadius)
            backgroundColor.setFill()
            roundedPath.fill()

            // Draw centered text
            let font = NSFont.boldSystemFont(ofSize: fontSize)
            let attributes: [NSAttributedString.Key: Any] = [
                .font: font,
                .foregroundColor: foregroundColor,
            ]
            let textSize = spaceNumber.size(withAttributes: attributes)
            let textX = backgroundRect.origin.x + (backgroundRect.width - textSize.width) / 2
            let textY = backgroundRect.origin.y + (backgroundRect.height - textSize.height) / 2
            let textRect = NSRect(x: textX, y: textY, width: textSize.width, height: textSize.height)

            spaceNumber.draw(in: textRect, withAttributes: attributes)

            return true
        }

        return image
    }
}
