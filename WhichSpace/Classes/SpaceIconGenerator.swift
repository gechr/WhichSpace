//
//  SpaceIconGenerator.swift
//  WhichSpace
//
//  Created by George Christou.
//  Copyright © 2020 George Christou. All rights reserved.
//

import Cocoa

/// Generates status bar icon images using custom drawing
enum SpaceIconGenerator {
    private static let cornerRadius: CGFloat = 4
    private static let fontSize: CGFloat = 14
    private static let fontSizeSmall: CGFloat = 12
    private static let fontSizeTiny: CGFloat = 8
    private static let iconSize: CGFloat = 20
    private static let outlineWidth: CGFloat = 1.5
    private static let statusItemSize = NSSize(width: 24, height: 22)

    // swiftlint:disable:next function_body_length
    static func generateIcon(
        for spaceNumber: String,
        darkMode: Bool,
        customColors: SpaceColors? = nil,
        style: IconStyle = .square
    ) -> NSImage {
        switch style {
        case .square:
            generateSquareIcon(
                for: spaceNumber,
                darkMode: darkMode,
                customColors: customColors,
                filled: true
            )
        case .squareOutline:
            generateSquareIcon(
                for: spaceNumber,
                darkMode: darkMode,
                customColors: customColors,
                filled: false
            )
        case .circle:
            generateCircleIcon(
                for: spaceNumber,
                darkMode: darkMode,
                customColors: customColors,
                filled: true
            )
        case .circleOutline:
            generateCircleIcon(
                for: spaceNumber,
                darkMode: darkMode,
                customColors: customColors,
                filled: false
            )
        case .triangle:
            generateTriangleIcon(
                for: spaceNumber,
                darkMode: darkMode,
                customColors: customColors,
                filled: true
            )
        case .triangleOutline:
            generateTriangleIcon(
                for: spaceNumber,
                darkMode: darkMode,
                customColors: customColors,
                filled: false
            )
        case .pentagon:
            generatePolygonIcon(
                for: spaceNumber,
                darkMode: darkMode,
                customColors: customColors,
                filled: true,
                sides: 5
            )
        case .pentagonOutline:
            generatePolygonIcon(
                for: spaceNumber,
                darkMode: darkMode,
                customColors: customColors,
                filled: false,
                sides: 5
            )
        case .hexagon:
            generatePolygonIcon(
                for: spaceNumber,
                darkMode: darkMode,
                customColors: customColors,
                filled: true,
                sides: 6
            )
        case .hexagonOutline:
            generatePolygonIcon(
                for: spaceNumber,
                darkMode: darkMode,
                customColors: customColors,
                filled: false,
                sides: 6
            )
        }
    }

    private static func getColors(
        darkMode: Bool,
        customColors: SpaceColors?,
        filled: Bool
    ) -> (foreground: NSColor, background: NSColor) {
        if let customColors {
            (customColors.foregroundColor, customColors.backgroundColor)
        } else if filled {
            if darkMode {
                (NSColor(calibratedWhite: 0, alpha: 1), NSColor(calibratedWhite: 0.7, alpha: 1))
            } else {
                (NSColor(calibratedWhite: 1, alpha: 1), NSColor(calibratedWhite: 0.3, alpha: 1))
            }
        } else {
            // Outline style - use single color
            if darkMode {
                (NSColor(calibratedWhite: 0.7, alpha: 1), NSColor(calibratedWhite: 0.7, alpha: 1))
            } else {
                (NSColor(calibratedWhite: 0.3, alpha: 1), NSColor(calibratedWhite: 0.3, alpha: 1))
            }
        }
    }

    private static func generateSquareIcon(
        for spaceNumber: String,
        darkMode: Bool,
        customColors: SpaceColors?,
        filled: Bool
    ) -> NSImage {
        NSImage(size: statusItemSize, flipped: false) { rect in
            let colors = getColors(darkMode: darkMode, customColors: customColors, filled: filled)

            // Center the rounded rect within the status item
            let xStart = (rect.width - iconSize) / 2
            let yStart = (rect.height - iconSize) / 2
            let backgroundRect = NSRect(x: xStart, y: yStart, width: iconSize, height: iconSize)

            // Draw rounded rectangle
            let roundedPath = NSBezierPath(
                roundedRect: backgroundRect,
                xRadius: cornerRadius,
                yRadius: cornerRadius
            )

            if filled {
                colors.background.setFill()
                roundedPath.fill()
            } else {
                colors.background.setStroke()
                roundedPath.lineWidth = outlineWidth
                roundedPath.stroke()
            }

            // Draw centered text - use smaller font for multi-digit numbers
            let currentFontSize: CGFloat = switch spaceNumber.count {
            case 1: fontSize
            case 2: fontSizeSmall
            default: fontSizeTiny
            }
            let font = NSFont.boldSystemFont(ofSize: currentFontSize)
            let attributes: [NSAttributedString.Key: Any] = [
                .font: font,
                .foregroundColor: colors.foreground,
            ]
            let textSize = spaceNumber.size(withAttributes: attributes)
            let textX = backgroundRect.origin.x + (backgroundRect.width - textSize.width) / 2
            let textY = backgroundRect.origin.y + (backgroundRect.height - textSize.height) / 2
            let textRect = NSRect(x: textX, y: textY, width: textSize.width, height: textSize.height)

            spaceNumber.draw(in: textRect, withAttributes: attributes)

            return true
        }
    }

    private static func generateCircleIcon(
        for spaceNumber: String,
        darkMode: Bool,
        customColors: SpaceColors?,
        filled: Bool
    ) -> NSImage {
        NSImage(size: statusItemSize, flipped: false) { rect in
            let colors = getColors(darkMode: darkMode, customColors: customColors, filled: filled)

            // Center the circle within the status item
            let xStart = (rect.width - iconSize) / 2
            let yStart = (rect.height - iconSize) / 2
            let circleRect = NSRect(x: xStart, y: yStart, width: iconSize, height: iconSize)

            // Draw circle
            let circlePath = NSBezierPath(ovalIn: circleRect)

            if filled {
                colors.background.setFill()
                circlePath.fill()
            } else {
                colors.background.setStroke()
                circlePath.lineWidth = outlineWidth
                circlePath.stroke()
            }

            // Draw centered text - use smaller font for multi-digit numbers
            let currentFontSize: CGFloat = switch spaceNumber.count {
            case 1: fontSize
            case 2: fontSizeSmall
            default: fontSizeTiny
            }
            let font = NSFont.boldSystemFont(ofSize: currentFontSize)
            let attributes: [NSAttributedString.Key: Any] = [
                .font: font,
                .foregroundColor: colors.foreground,
            ]
            let textSize = spaceNumber.size(withAttributes: attributes)
            let textX = circleRect.origin.x + (circleRect.width - textSize.width) / 2
            let textY = circleRect.origin.y + (circleRect.height - textSize.height) / 2
            let textRect = NSRect(x: textX, y: textY, width: textSize.width, height: textSize.height)

            spaceNumber.draw(in: textRect, withAttributes: attributes)

            return true
        }
    }

    private static func generateTriangleIcon(
        for spaceNumber: String,
        darkMode: Bool,
        customColors: SpaceColors?,
        filled: Bool
    ) -> NSImage {
        NSImage(size: statusItemSize, flipped: false) { rect in
            let colors = getColors(darkMode: darkMode, customColors: customColors, filled: filled)

            // Center the triangle within the status item
            let xStart = (rect.width - iconSize) / 2
            let yStart = (rect.height - iconSize) / 2

            // Create equilateral triangle path with rounded corners (pointing up)
            let trianglePath = NSBezierPath()
            let radius: CGFloat = 4.5

            let topPoint = NSPoint(x: xStart + iconSize / 2, y: yStart + iconSize)
            let bottomLeft = NSPoint(x: xStart, y: yStart)
            let bottomRight = NSPoint(x: xStart + iconSize, y: yStart)

            // Start from a point on the left edge, moving toward top
            trianglePath.move(to: NSPoint(x: bottomLeft.x + radius * 0.5, y: bottomLeft.y + radius * 0.87))
            trianglePath.line(to: NSPoint(x: topPoint.x - radius * 0.5, y: topPoint.y - radius * 0.87))
            trianglePath.curve(to: NSPoint(x: topPoint.x + radius * 0.5, y: topPoint.y - radius * 0.87),
                               controlPoint1: topPoint, controlPoint2: topPoint)
            trianglePath.line(to: NSPoint(x: bottomRight.x - radius * 0.5, y: bottomRight.y + radius * 0.87))
            trianglePath.curve(to: NSPoint(x: bottomRight.x - radius, y: bottomRight.y),
                               controlPoint1: bottomRight, controlPoint2: bottomRight)
            trianglePath.line(to: NSPoint(x: bottomLeft.x + radius, y: bottomLeft.y))
            trianglePath.curve(to: NSPoint(x: bottomLeft.x + radius * 0.5, y: bottomLeft.y + radius * 0.87),
                               controlPoint1: bottomLeft, controlPoint2: bottomLeft)
            trianglePath.close()

            if filled {
                colors.background.setFill()
                trianglePath.fill()
            } else {
                colors.background.setStroke()
                trianglePath.lineWidth = outlineWidth
                trianglePath.stroke()
            }

            // Draw centered text - use smaller font for multi-digit numbers
            // Triangle gets extra reduction for better fit
            let currentFontSize: CGFloat = switch spaceNumber.count {
            case 1: fontSize - 2
            case 2: fontSizeSmall - 4
            default: fontSizeTiny - 2
            }
            let font = NSFont.boldSystemFont(ofSize: currentFontSize)
            let attributes: [NSAttributedString.Key: Any] = [
                .font: font,
                .foregroundColor: colors.foreground,
            ]
            let textSize = spaceNumber.size(withAttributes: attributes)
            let textX = xStart + (iconSize - textSize.width) / 2
            // Position text in the center of the triangle (lower for 2+ digits)
            let yOffset: CGFloat = spaceNumber.count > 1 ? -4 : -2
            let textY = yStart + (iconSize - textSize.height) / 2 + yOffset
            let textRect = NSRect(x: textX, y: textY, width: textSize.width, height: textSize.height)

            spaceNumber.draw(in: textRect, withAttributes: attributes)

            return true
        }
    }

    private static func generatePolygonIcon(
        for spaceNumber: String,
        darkMode: Bool,
        customColors: SpaceColors?,
        filled: Bool,
        sides: Int
    ) -> NSImage {
        NSImage(size: statusItemSize, flipped: false) { rect in
            let colors = getColors(darkMode: darkMode, customColors: customColors, filled: filled)

            let centerX = rect.width / 2
            let centerY = rect.height / 2
            let vertices = generatePolygonVertices(sides: sides, centerX: centerX, centerY: centerY)
            let polygonPath = createRoundedPolygonPath(vertices: vertices)

            if filled {
                colors.background.setFill()
                polygonPath.fill()
            } else {
                colors.background.setStroke()
                polygonPath.lineWidth = outlineWidth
                polygonPath.stroke()
            }

            drawPolygonText(
                spaceNumber,
                sides: sides,
                centerX: centerX,
                centerY: centerY,
                foregroundColor: colors.foreground
            )

            return true
        }
    }

    private static func generatePolygonVertices(
        sides: Int,
        centerX: CGFloat,
        centerY: CGFloat
    ) -> [NSPoint] {
        let radius = iconSize / 2
        let angleOffset: CGFloat = switch sides {
        case 5: .pi / 2
        case 6: .pi / 6
        default: -.pi / 2
        }

        var vertices: [NSPoint] = []
        for idx in 0 ..< sides {
            let angle = angleOffset + (CGFloat(idx) * 2 * .pi / CGFloat(sides))
            let ptX = centerX + radius * cos(angle)
            let ptY = centerY + radius * sin(angle)
            vertices.append(NSPoint(x: ptX, y: ptY))
        }
        return vertices
    }

    private static func createRoundedPolygonPath(vertices: [NSPoint]) -> NSBezierPath {
        let path = NSBezierPath()
        let cornerRadius: CGFloat = 3.0
        let sides = vertices.count

        for idx in 0 ..< sides {
            let current = vertices[idx]
            let next = vertices[(idx + 1) % sides]
            let prev = vertices[(idx - 1 + sides) % sides]

            let toPrev = NSPoint(x: prev.x - current.x, y: prev.y - current.y)
            let toNext = NSPoint(x: next.x - current.x, y: next.y - current.y)

            let lenPrev = sqrt(toPrev.x * toPrev.x + toPrev.y * toPrev.y)
            let lenNext = sqrt(toNext.x * toNext.x + toNext.y * toNext.y)

            let normPrev = NSPoint(x: toPrev.x / lenPrev, y: toPrev.y / lenPrev)
            let normNext = NSPoint(x: toNext.x / lenNext, y: toNext.y / lenNext)

            let startPoint = NSPoint(
                x: current.x + normPrev.x * cornerRadius,
                y: current.y + normPrev.y * cornerRadius
            )
            let endPoint = NSPoint(
                x: current.x + normNext.x * cornerRadius,
                y: current.y + normNext.y * cornerRadius
            )

            if idx == 0 {
                path.move(to: startPoint)
            } else {
                path.line(to: startPoint)
            }

            path.curve(to: endPoint, controlPoint1: current, controlPoint2: current)
        }
        path.close()
        return path
    }

    private static func drawPolygonText(
        _ spaceNumber: String,
        sides: Int,
        centerX: CGFloat,
        centerY: CGFloat,
        foregroundColor: NSColor
    ) {
        let sizeAdjustment: CGFloat = switch (spaceNumber.count, sides) {
        case (2, 5): -2
        case (2, 6): -1
        default: 0
        }
        let currentFontSize: CGFloat = switch spaceNumber.count {
        case 1: fontSize + sizeAdjustment
        case 2: fontSizeSmall + sizeAdjustment
        default: fontSizeTiny + sizeAdjustment
        }
        let font = NSFont.boldSystemFont(ofSize: currentFontSize)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: foregroundColor,
        ]
        let textSize = spaceNumber.size(withAttributes: attributes)
        let textX = centerX - textSize.width / 2
        let textY = centerY - textSize.height / 2
        let textRect = NSRect(x: textX, y: textY, width: textSize.width, height: textSize.height)

        spaceNumber.draw(in: textRect, withAttributes: attributes)
    }

    // MARK: - SF Symbol Icon

    static func generateSFSymbolIcon(
        symbolName: String,
        darkMode: Bool,
        customColors: SpaceColors? = nil
    ) -> NSImage {
        let symbolConfig = NSImage.SymbolConfiguration(pointSize: 16, weight: .medium)
        guard let sfImage = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil)?
            .withSymbolConfiguration(symbolConfig)
        else {
            // Fallback to question mark if symbol not found
            return generateIcon(for: "?", darkMode: darkMode, customColors: customColors)
        }

        let color: NSColor
        if let customColors {
            color = customColors.foregroundColor
        } else if darkMode {
            color = NSColor(calibratedWhite: 0.7, alpha: 1)
        } else {
            color = NSColor(calibratedWhite: 0.3, alpha: 1)
        }

        return NSImage(size: statusItemSize, flipped: false) { rect in
            let tintedImage = sfImage.tinted(with: color)
            let imageSize = tintedImage.size
            let xStart = (rect.width - imageSize.width) / 2
            let yStart = (rect.height - imageSize.height) / 2
            let imageRect = NSRect(x: xStart, y: yStart, width: imageSize.width, height: imageSize.height)
            tintedImage.draw(in: imageRect)
            return true
        }
    }
}

// MARK: - NSImage Tinting Extension

private extension NSImage {
    func tinted(with color: NSColor) -> NSImage {
        guard let image = copy() as? NSImage else { return self }
        image.lockFocus()
        color.set()
        let imageRect = NSRect(origin: .zero, size: image.size)
        imageRect.fill(using: .sourceAtop)
        image.unlockFocus()
        return image
    }
}
