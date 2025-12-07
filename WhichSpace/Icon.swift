//
//  Icon.swift
//  WhichSpace
//
//  Created by George Christou.
//  Copyright © 2020 George Christou. All rights reserved.
//

import Cocoa
import Defaults

/// Generates status bar icon images using custom drawing
enum SpaceIconGenerator {
    private static var sizeScale: Double { Defaults[.sizeScale] / 100.0 }
    private static var iconSize: Double { Layout.baseIconSize * sizeScale }
    private static let statusItemSize = Layout.statusItemSize

    private static func scaledFont(for digitCount: Int) -> NSFont {
        let baseFontSize: Double
        switch digitCount {
        case 1:
            baseFontSize = Layout.baseFontSize
        case 2:
            baseFontSize = Layout.baseFontSizeSmall
        default:
            baseFontSize = Layout.baseFontSizeTiny
        }
        return NSFont.boldSystemFont(ofSize: baseFontSize * sizeScale)
    }

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
            IconColors.filledColors(darkMode: darkMode)
        } else {
            IconColors.outlineColors(darkMode: darkMode)
        }
    }

    private static func generateSquareIcon(
        for spaceNumber: String,
        darkMode: Bool,
        customColors: SpaceColors?,
        filled: Bool
    ) -> NSImage {
        let currentIconSize = iconSize
        return NSImage(size: statusItemSize, flipped: false) { rect in
            let colors = getColors(darkMode: darkMode, customColors: customColors, filled: filled)

            // Center the rounded rect within the status item
            let xStart = (rect.width - currentIconSize) / 2
            let yStart = (rect.height - currentIconSize) / 2
            let backgroundRect = CGRect(x: xStart, y: yStart, width: currentIconSize, height: currentIconSize)

            // Draw rounded rectangle
            let roundedPath = NSBezierPath(
                roundedRect: backgroundRect,
                xRadius: Layout.Icon.cornerRadius,
                yRadius: Layout.Icon.cornerRadius
            )

            if filled {
                colors.background.setFill()
                roundedPath.fill()
            } else {
                colors.background.setStroke()
                roundedPath.lineWidth = Layout.Icon.outlineWidth
                roundedPath.stroke()
            }

            // Draw centered text - use smaller font for multi-digit numbers
            let font = scaledFont(for: spaceNumber.count)
            let attributes: [NSAttributedString.Key: Any] = [
                .font: font,
                .foregroundColor: colors.foreground,
            ]
            let textSize = spaceNumber.size(withAttributes: attributes)
            let textX = backgroundRect.origin.x + (backgroundRect.width - textSize.width) / 2
            let textY = backgroundRect.origin.y + (backgroundRect.height - textSize.height) / 2
            let textRect = CGRect(x: textX, y: textY, width: textSize.width, height: textSize.height)

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
        let currentIconSize = iconSize
        return NSImage(size: statusItemSize, flipped: false) { rect in
            let colors = getColors(darkMode: darkMode, customColors: customColors, filled: filled)

            // Center the circle within the status item
            let xStart = (rect.width - currentIconSize) / 2
            let yStart = (rect.height - currentIconSize) / 2
            let circleRect = CGRect(x: xStart, y: yStart, width: currentIconSize, height: currentIconSize)

            // Draw circle
            let circlePath = NSBezierPath(ovalIn: circleRect)

            if filled {
                colors.background.setFill()
                circlePath.fill()
            } else {
                colors.background.setStroke()
                circlePath.lineWidth = Layout.Icon.outlineWidth
                circlePath.stroke()
            }

            // Draw centered text - use smaller font for multi-digit numbers
            let font = scaledFont(for: spaceNumber.count)
            let attributes: [NSAttributedString.Key: Any] = [
                .font: font,
                .foregroundColor: colors.foreground,
            ]
            let textSize = spaceNumber.size(withAttributes: attributes)
            let textX = circleRect.origin.x + (circleRect.width - textSize.width) / 2
            let textY = circleRect.origin.y + (circleRect.height - textSize.height) / 2
            let textRect = CGRect(x: textX, y: textY, width: textSize.width, height: textSize.height)

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
        let currentIconSize = iconSize
        return NSImage(size: statusItemSize, flipped: false) { rect in
            let colors = getColors(darkMode: darkMode, customColors: customColors, filled: filled)

            // Center the triangle within the status item
            let xStart = (rect.width - currentIconSize) / 2
            let yStart = (rect.height - currentIconSize) / 2

            // Create equilateral triangle path with rounded corners (pointing up)
            let trianglePath = NSBezierPath()
            let radius = Layout.Icon.triangleCornerRadius

            let topPoint = CGPoint(x: xStart + currentIconSize / 2, y: yStart + currentIconSize)
            let bottomLeft = CGPoint(x: xStart, y: yStart)
            let bottomRight = CGPoint(x: xStart + currentIconSize, y: yStart)

            // Start from a point on the left edge, moving toward top
            trianglePath.move(to: CGPoint(x: bottomLeft.x + radius * 0.5, y: bottomLeft.y + radius * 0.87))
            trianglePath.line(to: CGPoint(x: topPoint.x - radius * 0.5, y: topPoint.y - radius * 0.87))
            trianglePath.curve(
                to: CGPoint(x: topPoint.x + radius * 0.5, y: topPoint.y - radius * 0.87),
                controlPoint1: topPoint,
                controlPoint2: topPoint
            )
            trianglePath.line(to: CGPoint(x: bottomRight.x - radius * 0.5, y: bottomRight.y + radius * 0.87))
            trianglePath.curve(
                to: CGPoint(x: bottomRight.x - radius, y: bottomRight.y),
                controlPoint1: bottomRight,
                controlPoint2: bottomRight
            )
            trianglePath.line(to: CGPoint(x: bottomLeft.x + radius, y: bottomLeft.y))
            trianglePath.curve(
                to: CGPoint(x: bottomLeft.x + radius * 0.5, y: bottomLeft.y + radius * 0.87),
                controlPoint1: bottomLeft,
                controlPoint2: bottomLeft
            )
            trianglePath.close()

            if filled {
                colors.background.setFill()
                trianglePath.fill()
            } else {
                colors.background.setStroke()
                trianglePath.lineWidth = Layout.Icon.outlineWidth
                trianglePath.stroke()
            }

            // Draw centered text - use smaller font for multi-digit numbers
            // Triangle gets extra reduction for better fit
            let baseFontSize: Double
            switch spaceNumber.count {
            case 1:
                baseFontSize = Layout.baseFontSize - 2
            case 2:
                baseFontSize = Layout.baseFontSizeSmall - 2
            default:
                baseFontSize = Layout.baseFontSizeTiny - 1
            }
            let font = NSFont.boldSystemFont(ofSize: baseFontSize * sizeScale)
            let attributes: [NSAttributedString.Key: Any] = [
                .font: font,
                .foregroundColor: colors.foreground,
            ]
            let textSize = spaceNumber.size(withAttributes: attributes)
            let textX = xStart + (currentIconSize - textSize.width) / 2
            // Position text in the center of the triangle (lower for 2+ digits)
            let yOffset: Double = spaceNumber.count > 1 ? -4 : -2
            let textY = yStart + (currentIconSize - textSize.height) / 2 + yOffset
            let textRect = CGRect(x: textX, y: textY, width: textSize.width, height: textSize.height)

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
        let currentIconSize = iconSize
        return NSImage(size: statusItemSize, flipped: false) { rect in
            let colors = getColors(darkMode: darkMode, customColors: customColors, filled: filled)

            let centerX = rect.width / 2
            let centerY = rect.height / 2
            let vertices = generatePolygonVertices(
                sides: sides,
                centerX: centerX,
                centerY: centerY,
                iconSize: currentIconSize
            )
            let polygonPath = createRoundedPolygonPath(vertices: vertices)

            if filled {
                colors.background.setFill()
                polygonPath.fill()
            } else {
                colors.background.setStroke()
                polygonPath.lineWidth = Layout.Icon.outlineWidth
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
        centerX: Double,
        centerY: Double,
        iconSize: Double
    ) -> [CGPoint] {
        let radius = iconSize / 2
        let angleOffset: Double
        switch sides {
        case 5:
            angleOffset = .pi / 2
        case 6:
            angleOffset = .pi / 6
        default:
            angleOffset = -.pi / 2
        }

        var vertices: [CGPoint] = []
        for idx in 0 ..< sides {
            let angle = angleOffset + (Double(idx) * 2 * .pi / Double(sides))
            let ptX = centerX + radius * cos(angle)
            let ptY = centerY + radius * sin(angle)
            vertices.append(CGPoint(x: ptX, y: ptY))
        }
        return vertices
    }

    private static func createRoundedPolygonPath(vertices: [CGPoint]) -> NSBezierPath {
        let path = NSBezierPath()
        let cornerRadius = Layout.Icon.polygonCornerRadius
        let sides = vertices.count

        for idx in 0 ..< sides {
            let current = vertices[idx]
            let next = vertices[(idx + 1) % sides]
            let prev = vertices[(idx - 1 + sides) % sides]

            let toPrev = CGPoint(x: prev.x - current.x, y: prev.y - current.y)
            let toNext = CGPoint(x: next.x - current.x, y: next.y - current.y)

            let lenPrev = sqrt(toPrev.x * toPrev.x + toPrev.y * toPrev.y)
            let lenNext = sqrt(toNext.x * toNext.x + toNext.y * toNext.y)

            let normPrev = CGPoint(x: toPrev.x / lenPrev, y: toPrev.y / lenPrev)
            let normNext = CGPoint(x: toNext.x / lenNext, y: toNext.y / lenNext)

            let startPoint = CGPoint(
                x: current.x + normPrev.x * cornerRadius,
                y: current.y + normPrev.y * cornerRadius
            )
            let endPoint = CGPoint(
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
        centerX: Double,
        centerY: Double,
        foregroundColor: NSColor
    ) {
        let sizeAdjustment: Double
        switch (spaceNumber.count, sides) {
        case (2, 5):
            sizeAdjustment = -2
        case (2, 6):
            sizeAdjustment = -1
        default:
            sizeAdjustment = 0
        }
        let baseFontSize: Double
        switch spaceNumber.count {
        case 1:
            baseFontSize = Layout.baseFontSize + sizeAdjustment
        case 2:
            baseFontSize = Layout.baseFontSizeSmall + sizeAdjustment
        default:
            baseFontSize = Layout.baseFontSizeTiny + sizeAdjustment
        }
        let font = NSFont.boldSystemFont(ofSize: baseFontSize * sizeScale)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: foregroundColor,
        ]
        let textSize = spaceNumber.size(withAttributes: attributes)
        let textX = centerX - textSize.width / 2
        let textY = centerY - textSize.height / 2
        let textRect = CGRect(x: textX, y: textY, width: textSize.width, height: textSize.height)

        spaceNumber.draw(in: textRect, withAttributes: attributes)
    }

    // MARK: - SF Symbol Icon

    static func generateSFSymbolIcon(
        symbolName: String,
        darkMode: Bool,
        customColors: SpaceColors? = nil
    ) -> NSImage {
        let scaledPointSize = Layout.Icon.sfSymbolPointSize * sizeScale
        let symbolConfig = NSImage.SymbolConfiguration(pointSize: scaledPointSize, weight: .medium)
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
            let imageRect = CGRect(x: xStart, y: yStart, width: imageSize.width, height: imageSize.height)
            tintedImage.draw(in: imageRect)
            return true
        }
    }
}

// MARK: - NSImage Tinting Extension

extension NSImage {
    fileprivate func tinted(with color: NSColor) -> NSImage {
        guard let image = copy() as? NSImage else {
            return self
        }
        image.lockFocus()
        color.set()
        let imageRect = CGRect(origin: .zero, size: image.size)
        imageRect.fill(using: .sourceAtop)
        image.unlockFocus()
        return image
    }
}
