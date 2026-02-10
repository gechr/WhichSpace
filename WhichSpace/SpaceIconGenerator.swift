//
//  SpaceIconGenerator.swift
//  WhichSpace
//
//  Created by George Christou.
//  Copyright © 2020 George Christou. All rights reserved.
//

import Cocoa

// MARK: - IconStyle Shape Metadata

enum ShapeType {
    case square
    case slim
    case circle
    case triangle
    case polygon(sides: Int)
    case stroke
    case transparent
}

extension IconStyle {
    var shapeType: ShapeType {
        switch self {
        case .square, .squareOutline:
            .square
        case .slim, .slimOutline:
            .slim
        case .circle, .circleOutline:
            .circle
        case .triangle, .triangleOutline:
            .triangle
        case .pentagon, .pentagonOutline:
            .polygon(sides: 5)
        case .hexagon, .hexagonOutline:
            .polygon(sides: 6)
        case .stroke:
            .stroke
        case .transparent:
            .transparent
        }
    }

    var isFilled: Bool {
        switch self {
        case .square, .slim, .circle, .triangle, .pentagon, .hexagon:
            true
        case .squareOutline, .slimOutline, .circleOutline, .triangleOutline,
             .pentagonOutline, .hexagonOutline, .stroke, .transparent:
            false
        }
    }
}

/// Generates status bar icon images using custom drawing
enum SpaceIconGenerator {
    // MARK: - Properties

    private static let statusItemSize = Layout.statusItemSize
    /// Maximum icon size must fit within status item bounds with margin
    private static let maxIconSize = min(statusItemSize.width, statusItemSize.height) - 1

    private static func squareSize(scale: Double) -> Double {
        min(Layout.baseSquareSize * scale, maxIconSize)
    }

    private static func polygonSize(scale: Double) -> Double {
        min(Layout.basePolygonSize * scale, maxIconSize)
    }

    // MARK: - Public API

    static func generateIcon(
        for spaceNumber: String,
        darkMode: Bool,
        customColors: SpaceColors? = nil,
        customFont: NSFont? = nil,
        style: IconStyle = .square,
        sizeScale: Double = Layout.defaultSizeScale
    ) -> NSImage {
        let scale = sizeScale / 100.0
        let filled = style.isFilled

        switch style.shapeType {
        case .square:
            let size = squareSize(scale: scale)
            let iconSize = CGSize(width: size, height: size)
            return generateShapedIcon(
                for: spaceNumber,
                darkMode: darkMode,
                customColors: customColors,
                customFont: customFont,
                filled: filled,
                scale: scale
            ) { rect, color, filled in
                let shapeRect = centeredRect(size: iconSize, in: rect)
                let path = NSBezierPath(
                    roundedRect: shapeRect,
                    xRadius: Layout.Icon.cornerRadius,
                    yRadius: Layout.Icon.cornerRadius
                )
                fillOrStroke(path: path, color: color, filled: filled)
                return shapeRect
            }

        case .slim:
            return generateShapedIcon(
                for: spaceNumber,
                darkMode: darkMode,
                customColors: customColors,
                customFont: customFont,
                filled: filled,
                scale: scale
            ) { rect, color, filled in
                let font = scaledFont(for: spaceNumber.count, customFont: customFont, scale: scale)
                let attributes: [NSAttributedString.Key: Any] = [.font: font]
                let textSize = spaceNumber.size(withAttributes: attributes)
                let horizontalPadding = 4.0 * scale
                let iconSize = CGSize(
                    width: textSize.width + horizontalPadding * 2, height: squareSize(scale: scale)
                )
                let shapeRect = centeredRect(size: iconSize, in: rect)
                let path = NSBezierPath(
                    roundedRect: shapeRect,
                    xRadius: Layout.Icon.cornerRadius,
                    yRadius: Layout.Icon.cornerRadius
                )
                fillOrStroke(path: path, color: color, filled: filled)
                return shapeRect
            }

        case .circle:
            let size = squareSize(scale: scale)
            let iconSize = CGSize(width: size, height: size)
            return generateShapedIcon(
                for: spaceNumber,
                darkMode: darkMode,
                customColors: customColors,
                customFont: customFont,
                filled: filled,
                scale: scale
            ) { rect, color, filled in
                let shapeRect = centeredRect(size: iconSize, in: rect)
                let path = NSBezierPath(ovalIn: shapeRect)
                fillOrStroke(path: path, color: color, filled: filled)
                return shapeRect
            }

        case .triangle:
            let size = polygonSize(scale: scale)
            let iconSize = CGSize(width: size, height: size)
            let sizeAdjustment = spaceNumber.count <= 2 ? -2.0 : -1.0
            let yOffset = spaceNumber.count > 1 ? -4.0 : -2.0
            return generateShapedIcon(
                for: spaceNumber,
                darkMode: darkMode,
                customColors: customColors,
                customFont: customFont,
                filled: filled,
                scale: scale,
                fontSizeAdjustment: sizeAdjustment,
                textYOffset: yOffset
            ) { rect, color, filled in
                let shapeRect = centeredRect(size: iconSize, in: rect)
                let top = CGPoint(x: shapeRect.midX, y: shapeRect.maxY)
                let bottomLeft = CGPoint(x: shapeRect.minX, y: shapeRect.minY)
                let bottomRight = CGPoint(x: shapeRect.maxX, y: shapeRect.minY)
                let path = createRoundedPolygonPath(
                    vertices: [top, bottomRight, bottomLeft],
                    cornerRadius: Layout.Icon.triangleCornerRadius
                )
                fillOrStroke(path: path, color: color, filled: filled)
                return shapeRect
            }

        case let .polygon(sides):
            let sizeAdjustment: Double = switch (spaceNumber.count, sides) {
            case (2, 5):
                -2
            case (2, 6):
                -1
            default:
                0
            }
            return generateShapedIcon(
                for: spaceNumber,
                darkMode: darkMode,
                customColors: customColors,
                customFont: customFont,
                filled: filled,
                scale: scale,
                fontSizeAdjustment: sizeAdjustment
            ) { rect, color, filled in
                let centerX = rect.width / 2
                let centerY = rect.height / 2
                let vertices = generatePolygonVertices(
                    sides: sides,
                    centerX: centerX,
                    centerY: centerY,
                    iconSize: polygonSize(scale: scale)
                )
                let path = createRoundedPolygonPath(vertices: vertices)
                fillOrStroke(path: path, color: color, filled: filled)
                return rect
            }

        case .transparent:
            return generateShapedIcon(
                for: spaceNumber,
                darkMode: darkMode,
                customColors: customColors,
                customFont: customFont,
                filled: false,
                scale: scale,
                fontSizeAdjustment: 1
            ) { rect, _, _ in
                rect
            }

        case .stroke:
            return generateStrokeIcon(
                for: spaceNumber,
                darkMode: darkMode,
                customColors: customColors,
                customFont: customFont,
                scale: scale
            )
        }
    }

    /// Generates an icon for a symbol (SF Symbol name) or emoji string
    /// - Parameters:
    ///   - symbolName: The SF Symbol name or emoji character
    ///   - darkMode: Whether dark mode is enabled
    ///   - customColors: Optional custom colors for the icon
    ///   - skinTone: Optional skin tone for emojis. If nil, uses global default.
    ///   - sizeScale: The size scale percentage (default 100)
    static func generateSymbolIcon(
        symbolName: String,
        darkMode: Bool,
        customColors: SpaceColors? = nil,
        skinTone: SkinTone? = nil,
        sizeScale: Double = Layout.defaultSizeScale
    ) -> NSImage {
        let scale = sizeScale / 100.0

        // Check if it's an emoji (contains emoji Unicode characters)
        if symbolName.containsEmoji {
            return generateEmojiIcon(
                emoji: symbolName,
                skinTone: skinTone,
                scale: scale
            )
        }

        // Try SF Symbol
        let scaledPointSize = Layout.Icon.sfSymbolPointSize * scale
        let symbolConfig = NSImage.SymbolConfiguration(pointSize: scaledPointSize, weight: .medium)
        guard let sfImage = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil)?
            .withSymbolConfiguration(symbolConfig)
        else {
            // Fallback to question mark if symbol not found
            return generateIcon(for: "?", darkMode: darkMode, customColors: customColors, sizeScale: sizeScale)
        }

        let color: NSColor = if let customColors {
            customColors.foreground
        } else if darkMode {
            NSColor(calibratedWhite: 0.7, alpha: 1)
        } else {
            NSColor(calibratedWhite: 0.3, alpha: 1)
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
        skinTone: SkinTone? = nil,
        scale: Double
    ) -> NSImage {
        let displayEmoji = SkinTone.apply(to: emoji, tone: skinTone)
        return NSImage(size: statusItemSize, flipped: false) { rect in
            // Use smaller font for emoji to fit nicely in the status bar
            let fontSize = 13.0 * scale
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
            (customColors.foreground, customColors.background)
        } else if filled {
            IconColors.filledColors(darkMode: darkMode)
        } else {
            IconColors.outlineColors(darkMode: darkMode)
        }
    }

    private static func scaledFont(
        for digitCount: Int,
        customFont: NSFont? = nil,
        sizeAdjustment: Double = 0,
        scale: Double
    ) -> NSFont {
        let baseFontSize: Double = switch digitCount {
        case 1:
            Layout.baseFontSize
        case 2:
            Layout.baseFontSizeSmall
        default:
            Layout.baseFontSizeTiny
        }

        if let customFont {
            // Scale the custom font proportionally
            let scaledSize = customFont.pointSize * scale
            return NSFontManager.shared.convert(customFont, toSize: scaledSize)
        }
        return NSFont.boldSystemFont(ofSize: (baseFontSize + sizeAdjustment) * scale)
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

    private static func generateShapedIcon(
        for spaceNumber: String,
        darkMode: Bool,
        customColors: SpaceColors?,
        customFont: NSFont?,
        filled: Bool,
        scale: Double,
        fontSizeAdjustment: Double = 0,
        textYOffset: Double = 0,
        drawShape: @escaping (CGRect, NSColor, Bool) -> CGRect
    ) -> NSImage {
        NSImage(size: statusItemSize, flipped: false) { rect in
            let colors = getColors(darkMode: darkMode, customColors: customColors, filled: filled)
            let textRect = drawShape(rect, colors.background, filled)

            let font = scaledFont(
                for: spaceNumber.count,
                customFont: customFont,
                sizeAdjustment: fontSizeAdjustment,
                scale: scale
            )
            drawCenteredText(
                spaceNumber, in: textRect, font: font, color: colors.foreground, yOffset: textYOffset
            )
            return true
        }
    }

    private static func generateStrokeIcon(
        for spaceNumber: String,
        darkMode: Bool,
        customColors: SpaceColors?,
        customFont: NSFont?,
        scale: Double
    ) -> NSImage {
        NSImage(size: statusItemSize, flipped: false) { rect in
            guard let context = NSGraphicsContext.current?.cgContext else {
                return false
            }

            // Get colors - foreground is fill, background is stroke
            let fillColor: NSColor
            let strokeColor: NSColor
            if let customColors {
                fillColor = customColors.foreground
                strokeColor = customColors.background
            } else {
                let colors = IconColors.filledColors(darkMode: darkMode)
                fillColor = colors.foreground
                strokeColor = colors.background
            }

            // Use larger font for stroke mode to match visual weight of other styles
            let baseFont = scaledFont(for: spaceNumber.count, customFont: customFont, scale: scale)
            let enlargedSize = baseFont.pointSize * 1.1
            let font = NSFontManager.shared.convert(baseFont, toSize: enlargedSize)
            let ctFont = font as CTFont
            let strokeWidth = 4.0 * scale

            // Create attributed string for measuring
            let attributes: [NSAttributedString.Key: Any] = [.font: font]
            let textSize = spaceNumber.size(withAttributes: attributes)
            let textX = (rect.width - textSize.width) / 2

            // Account for font metrics - CTFont draws from baseline
            let ascent = CTFontGetAscent(ctFont)
            let descent = CTFontGetDescent(ctFont)
            let textHeight = ascent + descent
            let textY = (rect.height - textHeight) / 2 + descent

            let textPath = textPath(for: spaceNumber, font: font)

            context.saveGState()
            context.translateBy(x: textX, y: textY)

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

    /// Builds a CGPath from the glyphs in a string using CoreText
    private static func textPath(for string: String, font: NSFont) -> CGMutablePath {
        let attrString = NSAttributedString(string: string, attributes: [.font: font])
        let line = CTLineCreateWithAttributedString(attrString)
        let glyphRuns = CTLineGetGlyphRuns(line) as? [CTRun] ?? []

        let path = CGMutablePath()
        for run in glyphRuns {
            let glyphCount = CTRunGetGlyphCount(run)
            let attributes = CTRunGetAttributes(run) as NSDictionary
            guard let runFontValue = attributes[kCTFontAttributeName],
                  CFGetTypeID(runFontValue as CFTypeRef) == CTFontGetTypeID()
            else { continue }
            let runFont = runFontValue as! CTFont

            for index in 0 ..< glyphCount {
                let range = CFRange(location: index, length: 1)
                var glyph = CGGlyph()
                var position = CGPoint()
                CTRunGetGlyphs(run, range, &glyph)
                CTRunGetPositions(run, range, &position)

                if let glyphPath = CTFontCreatePathForGlyph(runFont, glyph, nil) {
                    let transform = CGAffineTransform(translationX: position.x, y: position.y)
                    path.addPath(glyphPath, transform: transform)
                }
            }
        }
        return path
    }

    // MARK: - Polygon Helpers

    private static func generatePolygonVertices(
        sides: Int,
        centerX: Double,
        centerY: Double,
        iconSize: Double
    ) -> [CGPoint] {
        let radius = iconSize / 2
        let angleOffset: Double = switch sides {
        case 5:
            .pi / 2
        case 6:
            .pi / 6
        default:
            -.pi / 2
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
    func tinted(with color: NSColor) -> NSImage {
        let size = size
        return NSImage(size: size, flipped: false) { rect in
            self.draw(in: rect)
            color.set()
            rect.fill(using: .sourceAtop)
            return true
        }
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
        // An emoji needs isEmoji=true plus one of:
        // - Default emoji presentation (most common emojis)
        // - Multiple scalars (has FE0F variation selector, skin tone, ZWJ, etc.)
        // - Scalar value >= 0x00A9 (text-default emojis stored without FE0F;
        //   excludes keycap bases #, *, 0-9 which need FE0F+U+20E3 to be emoji)
        return scalar.properties.isEmoji && (
            scalar.properties.isEmojiPresentation || unicodeScalars.count > 1 || scalar.value >= 0x00A9
        )
    }
}
