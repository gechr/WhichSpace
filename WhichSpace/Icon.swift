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
    // MARK: - Properties

    private static let statusItemSize = Layout.statusItemSize
    /// Maximum icon size must fit within status item bounds with margin
    private static let maxIconSize = min(statusItemSize.width, statusItemSize.height) - 1

    private static var sizeScale: Double { Defaults[.sizeScale] / 100.0 }
    private static var squareSize: Double { min(Layout.baseSquareSize * sizeScale, maxIconSize) }
    private static var polygonSize: Double { min(Layout.basePolygonSize * sizeScale, maxIconSize) }

    // MARK: - Public API

    // swiftlint:disable:next function_body_length
    static func generateIcon(
        for spaceNumber: String,
        darkMode: Bool,
        customColors: SpaceColors? = nil,
        customFont: NSFont? = nil,
        style: IconStyle = .square
    ) -> NSImage {
        switch style {
        case .square:
            generateSquareIcon(
                for: spaceNumber,
                darkMode: darkMode,
                customColors: customColors,
                customFont: customFont,
                filled: true
            )
        case .squareOutline:
            generateSquareIcon(
                for: spaceNumber,
                darkMode: darkMode,
                customColors: customColors,
                customFont: customFont,
                filled: false
            )
        case .slim:
            generateSlimIcon(
                for: spaceNumber,
                darkMode: darkMode,
                customColors: customColors,
                customFont: customFont,
                filled: true
            )
        case .slimOutline:
            generateSlimIcon(
                for: spaceNumber,
                darkMode: darkMode,
                customColors: customColors,
                customFont: customFont,
                filled: false
            )
        case .circle:
            generateCircleIcon(
                for: spaceNumber,
                darkMode: darkMode,
                customColors: customColors,
                customFont: customFont,
                filled: true
            )
        case .circleOutline:
            generateCircleIcon(
                for: spaceNumber,
                darkMode: darkMode,
                customColors: customColors,
                customFont: customFont,
                filled: false
            )
        case .triangle:
            generateTriangleIcon(
                for: spaceNumber,
                darkMode: darkMode,
                customColors: customColors,
                customFont: customFont,
                filled: true
            )
        case .triangleOutline:
            generateTriangleIcon(
                for: spaceNumber,
                darkMode: darkMode,
                customColors: customColors,
                customFont: customFont,
                filled: false
            )
        case .pentagon:
            generatePolygonIcon(
                for: spaceNumber,
                darkMode: darkMode,
                customColors: customColors,
                customFont: customFont,
                filled: true,
                sides: 5
            )
        case .pentagonOutline:
            generatePolygonIcon(
                for: spaceNumber,
                darkMode: darkMode,
                customColors: customColors,
                customFont: customFont,
                filled: false,
                sides: 5
            )
        case .hexagon:
            generatePolygonIcon(
                for: spaceNumber,
                darkMode: darkMode,
                customColors: customColors,
                customFont: customFont,
                filled: true,
                sides: 6
            )
        case .hexagonOutline:
            generatePolygonIcon(
                for: spaceNumber,
                darkMode: darkMode,
                customColors: customColors,
                customFont: customFont,
                filled: false,
                sides: 6
            )
        case .stroke:
            generateStrokeIcon(
                for: spaceNumber,
                darkMode: darkMode,
                customColors: customColors,
                customFont: customFont
            )
        case .transparent:
            generateTransparentIcon(
                for: spaceNumber,
                darkMode: darkMode,
                customColors: customColors,
                customFont: customFont
            )
        }
    }

    /// Generates an icon for a symbol (SF Symbol name) or emoji string
    /// - Parameters:
    ///   - symbolName: The SF Symbol name or emoji character
    ///   - darkMode: Whether dark mode is enabled
    ///   - customColors: Optional custom colors for the icon
    ///   - skinTone: Optional skin tone for emojis. If nil, uses global default.
    static func generateSymbolIcon(
        symbolName: String,
        darkMode: Bool,
        customColors: SpaceColors? = nil,
        skinTone: SkinTone? = nil
    ) -> NSImage {
        // Check if it's an emoji (contains emoji Unicode characters)
        if symbolName.containsEmoji {
            return generateEmojiIcon(
                emoji: symbolName,
                darkMode: darkMode,
                customColors: customColors,
                skinTone: skinTone
            )
        }

        // Try SF Symbol
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

    /// Generates an icon for an emoji character
    private static func generateEmojiIcon(
        emoji: String,
        darkMode _: Bool,
        customColors _: SpaceColors? = nil,
        skinTone: SkinTone? = nil
    ) -> NSImage {
        let displayEmoji = SkinTone.apply(to: emoji, tone: skinTone)
        return NSImage(size: statusItemSize, flipped: false) { rect in
            // Use smaller font for emoji to fit nicely in the status bar
            let fontSize = 13.0 * sizeScale
            let font = NSFont.systemFont(ofSize: fontSize)

            let attributes: [NSAttributedString.Key: Any] = [.font: font]
            let emojiSize = displayEmoji.size(withAttributes: attributes)

            // Center the emoji in the rect
            let xStart = (rect.width - emojiSize.width) / 2
            let yStart = (rect.height - emojiSize.height) / 2
            let emojiRect = CGRect(x: xStart, y: yStart, width: emojiSize.width, height: emojiSize.height)

            displayEmoji.draw(in: emojiRect, withAttributes: attributes)
            return true
        }
    }

    // MARK: - Private Helpers

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

    private static func scaledFont(
        for digitCount: Int,
        customFont: NSFont? = nil,
        sizeAdjustment: Double = 0
    ) -> NSFont {
        let baseFontSize: Double
        switch digitCount {
        case 1:
            baseFontSize = Layout.baseFontSize
        case 2:
            baseFontSize = Layout.baseFontSizeSmall
        default:
            baseFontSize = Layout.baseFontSizeTiny
        }

        if let customFont {
            // Scale the custom font proportionally
            let scaledSize = customFont.pointSize * sizeScale
            return NSFontManager.shared.convert(customFont, toSize: scaledSize)
        }
        return NSFont.boldSystemFont(ofSize: (baseFontSize + sizeAdjustment) * sizeScale)
    }

    private static func centeredRect(size: CGSize, in container: CGRect) -> CGRect {
        let x = container.origin.x + (container.width - size.width) / 2
        let y = container.origin.y + (container.height - size.height) / 2
        return CGRect(x: x, y: y, width: size.width, height: size.height)
    }

    private static func fillOrStroke(
        path: NSBezierPath,
        color: NSColor,
        filled: Bool
    ) {
        if filled {
            color.setFill()
            path.fill()
        } else {
            color.setStroke()
            path.lineWidth = Layout.Icon.outlineWidth
            path.stroke()
        }
    }

    private static func drawCenteredText(
        _ text: String,
        in rect: CGRect,
        font: NSFont,
        color: NSColor,
        yOffset: Double = 0
    ) {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: color,
        ]
        let textSize = text.size(withAttributes: attributes)
        var textRect = centeredRect(size: textSize, in: rect)
        textRect.origin.y += yOffset
        text.draw(in: textRect, withAttributes: attributes)
    }

    // MARK: - Shape Generators

    private static func generateSquareIcon(
        for spaceNumber: String,
        darkMode: Bool,
        customColors: SpaceColors?,
        customFont: NSFont?,
        filled: Bool
    ) -> NSImage {
        let iconSize = CGSize(width: squareSize, height: squareSize)
        return NSImage(size: statusItemSize, flipped: false) { rect in
            let colors = getColors(darkMode: darkMode, customColors: customColors, filled: filled)
            let backgroundRect = centeredRect(size: iconSize, in: rect)

            let roundedPath = NSBezierPath(
                roundedRect: backgroundRect,
                xRadius: Layout.Icon.cornerRadius,
                yRadius: Layout.Icon.cornerRadius
            )
            fillOrStroke(path: roundedPath, color: colors.background, filled: filled)

            let font = scaledFont(for: spaceNumber.count, customFont: customFont)
            drawCenteredText(spaceNumber, in: backgroundRect, font: font, color: colors.foreground)

            return true
        }
    }

    private static func generateSlimIcon(
        for spaceNumber: String,
        darkMode: Bool,
        customColors: SpaceColors?,
        customFont: NSFont?,
        filled: Bool
    ) -> NSImage {
        NSImage(size: statusItemSize, flipped: false) { rect in
            let colors = getColors(darkMode: darkMode, customColors: customColors, filled: filled)
            let font = scaledFont(for: spaceNumber.count, customFont: customFont)

            // Calculate dynamic width based on text
            let attributes: [NSAttributedString.Key: Any] = [.font: font]
            let textSize = spaceNumber.size(withAttributes: attributes)
            let horizontalPadding = 4.0 * sizeScale
            let iconSize = CGSize(width: textSize.width + horizontalPadding * 2, height: squareSize)
            let backgroundRect = centeredRect(size: iconSize, in: rect)

            let roundedPath = NSBezierPath(
                roundedRect: backgroundRect,
                xRadius: Layout.Icon.cornerRadius,
                yRadius: Layout.Icon.cornerRadius
            )
            fillOrStroke(path: roundedPath, color: colors.background, filled: filled)
            drawCenteredText(spaceNumber, in: backgroundRect, font: font, color: colors.foreground)

            return true
        }
    }

    private static func generateCircleIcon(
        for spaceNumber: String,
        darkMode: Bool,
        customColors: SpaceColors?,
        customFont: NSFont?,
        filled: Bool
    ) -> NSImage {
        let iconSize = CGSize(width: squareSize, height: squareSize)
        return NSImage(size: statusItemSize, flipped: false) { rect in
            let colors = getColors(darkMode: darkMode, customColors: customColors, filled: filled)
            let circleRect = centeredRect(size: iconSize, in: rect)

            let circlePath = NSBezierPath(ovalIn: circleRect)
            fillOrStroke(path: circlePath, color: colors.background, filled: filled)

            let font = scaledFont(for: spaceNumber.count, customFont: customFont)
            drawCenteredText(spaceNumber, in: circleRect, font: font, color: colors.foreground)

            return true
        }
    }

    private static func generateTriangleIcon(
        for spaceNumber: String,
        darkMode: Bool,
        customColors: SpaceColors?,
        customFont: NSFont?,
        filled: Bool
    ) -> NSImage {
        let iconSize = CGSize(width: polygonSize, height: polygonSize)
        return NSImage(size: statusItemSize, flipped: false) { rect in
            let colors = getColors(darkMode: darkMode, customColors: customColors, filled: filled)
            let shapeRect = centeredRect(size: iconSize, in: rect)

            // Triangle vertices (pointing up)
            let top = CGPoint(x: shapeRect.midX, y: shapeRect.maxY)
            let bottomLeft = CGPoint(x: shapeRect.minX, y: shapeRect.minY)
            let bottomRight = CGPoint(x: shapeRect.maxX, y: shapeRect.minY)
            let vertices = [top, bottomRight, bottomLeft]

            let trianglePath = createRoundedPolygonPath(
                vertices: vertices,
                cornerRadius: Layout.Icon.triangleCornerRadius
            )
            fillOrStroke(path: trianglePath, color: colors.background, filled: filled)

            // Triangle uses smaller font and lower text position
            let sizeAdjustment = spaceNumber.count <= 2 ? -2.0 : -1.0
            let yOffset = spaceNumber.count > 1 ? -4.0 : -2.0
            let font = scaledFont(for: spaceNumber.count, customFont: customFont, sizeAdjustment: sizeAdjustment)
            drawCenteredText(spaceNumber, in: shapeRect, font: font, color: colors.foreground, yOffset: yOffset)

            return true
        }
    }

    private static func generatePolygonIcon(
        for spaceNumber: String,
        darkMode: Bool,
        customColors: SpaceColors?,
        customFont: NSFont?,
        filled: Bool,
        sides: Int
    ) -> NSImage {
        NSImage(size: statusItemSize, flipped: false) { rect in
            let colors = getColors(darkMode: darkMode, customColors: customColors, filled: filled)

            let centerX = rect.width / 2
            let centerY = rect.height / 2
            let vertices = generatePolygonVertices(
                sides: sides,
                centerX: centerX,
                centerY: centerY,
                iconSize: polygonSize
            )
            let polygonPath = createRoundedPolygonPath(vertices: vertices)
            fillOrStroke(path: polygonPath, color: colors.background, filled: filled)

            // Polygon font size adjustment depends on digit count and shape
            let sizeAdjustment: Double
            switch (spaceNumber.count, sides) {
            case (2, 5):
                sizeAdjustment = -2
            case (2, 6):
                sizeAdjustment = -1
            default:
                sizeAdjustment = 0
            }
            let font = scaledFont(for: spaceNumber.count, customFont: customFont, sizeAdjustment: sizeAdjustment)
            drawCenteredText(spaceNumber, in: rect, font: font, color: colors.foreground)

            return true
        }
    }

    private static func generateTransparentIcon(
        for spaceNumber: String,
        darkMode: Bool,
        customColors: SpaceColors?,
        customFont: NSFont?
    ) -> NSImage {
        NSImage(size: statusItemSize, flipped: false) { rect in
            let textColor: NSColor
            if let customColors {
                textColor = customColors.foregroundColor
            } else {
                textColor = darkMode ? IconColors.outlineDark : IconColors.outlineLight
            }

            // Transparent style uses slightly larger font since there's no background shape
            let font = scaledFont(for: spaceNumber.count, customFont: customFont, sizeAdjustment: 1)
            drawCenteredText(spaceNumber, in: rect, font: font, color: textColor)

            return true
        }
    }

    private static func generateStrokeIcon(
        for spaceNumber: String,
        darkMode: Bool,
        customColors: SpaceColors?,
        customFont: NSFont?
    ) -> NSImage {
        NSImage(size: statusItemSize, flipped: false) { rect in
            guard let context = NSGraphicsContext.current?.cgContext else {
                return false
            }

            // Get colors - foreground is fill, background is stroke
            let fillColor: NSColor
            let strokeColor: NSColor
            if let customColors {
                fillColor = customColors.foregroundColor
                strokeColor = customColors.backgroundColor
            } else {
                let colors = IconColors.filledColors(darkMode: darkMode)
                fillColor = colors.foreground
                strokeColor = colors.background
            }

            // Use larger font for stroke mode to match visual weight of other styles
            let baseFont = scaledFont(for: spaceNumber.count, customFont: customFont)
            let enlargedSize = baseFont.pointSize * 1.1
            let font = NSFontManager.shared.convert(baseFont, toSize: enlargedSize)
            let ctFont = font as CTFont
            let strokeWidth = 4.0 * sizeScale

            // Create attributed string for measuring
            let attributes: [NSAttributedString.Key: Any] = [.font: font]
            let textSize = spaceNumber.size(withAttributes: attributes)
            let textX = (rect.width - textSize.width) / 2

            // Account for font metrics - CTFont draws from baseline
            let ascent = CTFontGetAscent(ctFont)
            let descent = CTFontGetDescent(ctFont)
            let textHeight = ascent + descent
            let textY = (rect.height - textHeight) / 2 + descent

            // Create text path
            let attrString = NSAttributedString(string: spaceNumber, attributes: [.font: font])
            let line = CTLineCreateWithAttributedString(attrString)
            let glyphRuns = CTLineGetGlyphRuns(line) as! [CTRun]

            context.saveGState()
            context.translateBy(x: textX, y: textY)

            // Build path from all glyphs
            let textPath = CGMutablePath()
            for run in glyphRuns {
                let glyphCount = CTRunGetGlyphCount(run)
                let runFont = (CTRunGetAttributes(run) as Dictionary)[kCTFontAttributeName] as! CTFont

                for index in 0 ..< glyphCount {
                    let range = CFRange(location: index, length: 1)
                    var glyph = CGGlyph()
                    var position = CGPoint()
                    CTRunGetGlyphs(run, range, &glyph)
                    CTRunGetPositions(run, range, &position)

                    if let glyphPath = CTFontCreatePathForGlyph(runFont, glyph, nil) {
                        let transform = CGAffineTransform(translationX: position.x, y: position.y)
                        textPath.addPath(glyphPath, transform: transform)
                    }
                }
            }

            // Draw stroke (behind)
            context.addPath(textPath)
            context.setStrokeColor(strokeColor.cgColor)
            context.setLineWidth(strokeWidth)
            context.setLineJoin(.round)
            context.strokePath()

            // Draw fill (on top)
            context.addPath(textPath)
            context.setFillColor(fillColor.cgColor)
            context.fillPath()

            context.restoreGState()

            return true
        }
    }

    // MARK: - Polygon Helpers

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

    private static func createRoundedPolygonPath(
        vertices: [CGPoint],
        cornerRadius: Double = Layout.Icon.polygonCornerRadius
    ) -> NSBezierPath {
        let path = NSBezierPath()
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

// MARK: - String Emoji Detection Extension

extension String {
    /// Returns true if the string contains emoji characters
    var containsEmoji: Bool {
        contains(where: \.isEmoji)
    }
}

extension Character {
    /// Returns true if the character is an emoji
    var isEmoji: Bool {
        guard let scalar = unicodeScalars.first else {
            return false
        }
        // Check for emoji presentation or emoji modifier base
        return scalar.properties.isEmoji && (
            scalar.properties.isEmojiPresentation || unicodeScalars.count > 1
        )
    }
}
