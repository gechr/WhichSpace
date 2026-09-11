import AppKit

// MARK: - Dock Tile Spec

/// Everything the Dock tile draws for the current Space, resolved from the
/// same per-Space preferences as the status item so the two never disagree.
struct DockTileSpec {
    /// The user-visible Space number, shown in the badge
    var number: Int
    /// What fills the centre when there is no symbol, emoji or app icon:
    /// the Space number as the status item labels it, or "F" for a
    /// fullscreen Space whose app is unknown
    var centerText: String
    /// The custom label, shown in a pill along the bottom edge
    var label: String?
    /// SF Symbol name or emoji string
    var symbol: String?
    var skinTone: SkinTone
    /// The owning app's icon for a fullscreen Space
    var appIcon: NSImage?
    var foreground: NSColor
    var background: NSColor
    var symbolTint: NSColor
    /// Custom font for the centre text; nil uses the system font
    var font: NSFont?
    var badgeBackground: NSColor
    var badgeForeground: NSColor

    /// Whether the centre already shows the Space number, in which case a
    /// badge would only repeat it
    var centerIsNumber: Bool {
        symbol == nil && appIcon == nil && label == nil
    }

    /// The label pill only accompanies an icon; without one the label is
    /// the icon and fills the centre instead
    var showsLabelPill: Bool {
        label != nil && (symbol != nil || appIcon != nil)
    }
}

// MARK: - Dock Tile Renderer

/// Draws a `DockTileSpec` in the shape of a macOS app icon: a rounded square
/// in the Space's background colour holding the Space's symbol, emoji or
/// number, with the label in a pill and the number in a badge.
///
/// The image draws at display time, so the Dock renders it at its own
/// backing scale and the text and symbols stay sharp.
enum DockTileRenderer {
    /// Points; the Dock scales the tile itself
    static let tileSize: Double = 128
    /// The tile's rounded square sits inside the canvas like a real app icon
    static let tileInset = 0.06
    static let cornerRadiusRatio = 0.225
    /// Badge diameter as a fraction of the canvas
    static let badgeRatio = 0.44

    static func image(for spec: DockTileSpec) -> NSImage {
        NSImage(size: CGSize(width: tileSize, height: tileSize), flipped: false) { rect in
            draw(spec, in: rect)
            return true
        }
    }

    /// Where the badge is drawn, for tests that sample it
    static func badgeRect(in rect: CGRect) -> CGRect {
        let diameter = rect.width * badgeRatio
        let margin = rect.width * 0.01
        return CGRect(
            x: rect.maxX - diameter - margin,
            y: rect.maxY - diameter - margin,
            width: diameter,
            height: diameter
        )
    }

    private static func draw(_ spec: DockTileSpec, in rect: CGRect) {
        let tile = rect.insetBy(dx: rect.width * tileInset, dy: rect.height * tileInset)
        spec.background.setFill()
        NSBezierPath(
            roundedRect: tile,
            xRadius: tile.width * cornerRadiusRatio,
            yRadius: tile.height * cornerRadiusRatio
        ).fill()

        // Leave the bottom of the tile to the pill when there is one
        let content = spec.showsLabelPill
            ? CGRect(x: tile.minX, y: tile.minY + tile.height * 0.2, width: tile.width, height: tile.height * 0.8)
            : tile

        if let appIcon = spec.appIcon {
            let side = content.height * 0.78
            appIcon.draw(in: CGRect(x: content.midX - side / 2, y: content.midY - side / 2, width: side, height: side))
        } else if let symbol = spec.symbol {
            let iconArea = content.offsetBy(dx: -content.width * 0.04, dy: -content.height * 0.03)
            if symbol.allSatisfy(\.isASCII) {
                drawSymbol(symbol, in: iconArea, tint: spec.symbolTint)
            } else {
                drawEmoji(symbol, skinTone: spec.skinTone, in: iconArea)
            }
        } else if let label = spec.label {
            drawText(
                label,
                in: CGRect(
                    x: content.minX + content.width * 0.08,
                    y: content.minY + content.height * 0.1,
                    width: content.width * 0.84,
                    height: content.height * 0.66
                ),
                maxPointSize: content.height * 0.4,
                color: spec.foreground,
                weight: .bold,
                wraps: true
            )
        } else {
            let font = spec.font.map { NSFont(descriptor: $0.fontDescriptor, size: content.height * 0.74) ?? $0 }
            drawText(
                spec.centerText,
                in: content.insetBy(dx: content.width * 0.1, dy: 0),
                maxPointSize: content.height * 0.74,
                color: spec.foreground,
                weight: .bold,
                font: font
            )
        }

        if spec.showsLabelPill, let label = spec.label {
            drawPill(label, in: tile, fill: spec.badgeBackground, textColor: spec.badgeForeground)
        }
        if !spec.centerIsNumber {
            drawBadge(
                String(spec.number),
                in: badgeRect(in: rect),
                fill: spec.badgeBackground,
                textColor: spec.badgeForeground
            )
        }
    }

    private static func drawSymbol(_ name: String, in rect: CGRect, tint: NSColor) {
        let config = NSImage.SymbolConfiguration(pointSize: min(rect.height * 0.6, tileSize * 0.42), weight: .medium)
        guard let symbol = NSImage(systemSymbolName: name, accessibilityDescription: nil)?
            .withSymbolConfiguration(config)
        else {
            drawText("?", in: rect, maxPointSize: rect.height * 0.5, color: tint, weight: .bold)
            return
        }
        // Tint in an image of its own so the fill cannot bleed onto the tile
        let tinted = NSImage(size: symbol.size, flipped: false) { bounds in
            symbol.draw(in: bounds)
            tint.setFill()
            bounds.fill(using: .sourceAtop)
            return true
        }
        let size = tinted.size
        tinted.draw(in: CGRect(
            x: rect.midX - size.width / 2,
            y: rect.midY - size.height / 2,
            width: size.width,
            height: size.height
        ))
    }

    private static func drawEmoji(_ emoji: String, skinTone: SkinTone, in rect: CGRect) {
        let text = SkinTone.apply(to: emoji, tone: skinTone)
        let font = NSFont.systemFont(ofSize: min(rect.height * 0.68, tileSize * 0.48))
        let string = NSAttributedString(string: text, attributes: [.font: font])
        let size = string.size()
        string.draw(at: CGPoint(x: rect.midX - size.width / 2, y: rect.midY - size.height / 2))
    }

    /// Draws `text` centred in `rect`, shrinking the font until it fits.
    /// `font` supplies a custom face; its size is replaced. With `wraps`
    /// the text breaks onto further lines before it shrinks, for labels.
    private static func drawText(
        _ text: String,
        in rect: CGRect,
        maxPointSize: Double,
        color: NSColor,
        weight: NSFont.Weight,
        font: NSFont? = nil,
        wraps: Bool = false
    ) {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        paragraph.lineBreakMode = wraps ? .byWordWrapping : .byClipping
        let minPointSize = maxPointSize * 0.25
        var pointSize = maxPointSize
        var attributed: NSAttributedString
        var bounds: CGRect
        repeat {
            let resolved = font.map { NSFont(descriptor: $0.fontDescriptor, size: pointSize) ?? $0 }
                ?? NSFont.systemFont(ofSize: pointSize, weight: weight)
            attributed = NSAttributedString(
                string: text,
                attributes: [.font: resolved, .foregroundColor: color, .paragraphStyle: paragraph]
            )
            bounds = attributed.boundingRect(
                with: CGSize(width: wraps ? rect.width : .greatestFiniteMagnitude, height: .greatestFiniteMagnitude),
                options: [.usesLineFragmentOrigin]
            )
            pointSize *= 0.9
            // Wrapped text shrinks until no word has to break in the middle
            if wraps, let resolvedFont = attributed.attribute(.font, at: 0, effectiveRange: nil) as? NSFont {
                let longestWord = text.split(whereSeparator: \.isWhitespace)
                    .map { NSAttributedString(string: String($0), attributes: [.font: resolvedFont]).size().width }
                    .max() ?? 0
                bounds.size.width = max(bounds.width, longestWord)
            }
        } while (bounds.width > rect.width || bounds.height > rect.height) && pointSize > minPointSize

        // Centre single lines on the cap height rather than the line box,
        // which carries descender space below digits and capitals
        var offset = 0.0
        if !wraps, let resolvedFont = attributed.attribute(.font, at: 0, effectiveRange: nil) as? NSFont {
            offset = (resolvedFont.ascender + resolvedFont.descender - resolvedFont.capHeight) / 2 * 0.5
        }
        let drawRect = CGRect(
            x: wraps ? rect.minX : rect.midX - bounds.width / 2,
            y: rect.midY - bounds.height / 2 + offset,
            width: wraps ? rect.width : bounds.width,
            height: bounds.height
        )
        attributed.draw(with: drawRect, options: [.usesLineFragmentOrigin])
    }

    private static func drawPill(_ label: String, in tile: CGRect, fill: NSColor, textColor: NSColor) {
        let font = NSFont.systemFont(ofSize: tile.height * 0.17, weight: .semibold)
        let height = font.pointSize * 1.45
        let maxWidth = tile.width * 0.9
        let string = NSAttributedString(string: label, attributes: [.font: font, .foregroundColor: textColor])
        let width = min(maxWidth, string.size().width + height)
        let pill = CGRect(x: tile.midX - width / 2, y: tile.minY + tile.height * 0.08, width: width, height: height)
        withShadow {
            fill.setFill()
            NSBezierPath(roundedRect: pill, xRadius: height / 2, yRadius: height / 2).fill()
        }
        drawText(
            label,
            in: pill.insetBy(dx: height / 2, dy: 0),
            maxPointSize: font.pointSize,
            color: textColor,
            weight: .semibold
        )
    }

    private static func drawBadge(_ number: String, in rect: CGRect, fill: NSColor, textColor: NSColor) {
        withShadow {
            fill.setFill()
            NSBezierPath(ovalIn: rect).fill()
        }
        // A faint ring keeps a white badge separate from a light tile or Dock
        textColor.withAlphaComponent(0.25).setStroke()
        let ring = NSBezierPath(ovalIn: rect.insetBy(dx: 0.5, dy: 0.5))
        ring.lineWidth = 1
        ring.stroke()
        drawText(
            number,
            in: rect.insetBy(dx: rect.width * 0.14, dy: 0),
            maxPointSize: rect.height * 0.7,
            color: textColor,
            weight: .semibold
        )
    }

    private static func withShadow(_ draw: () -> Void) {
        guard let context = NSGraphicsContext.current?.cgContext else {
            draw()
            return
        }
        context.saveGState()
        context.setShadow(
            offset: CGSize(width: 0, height: -1),
            blur: 3,
            color: NSColor.black.withAlphaComponent(0.35).cgColor
        )
        draw()
        context.restoreGState()
    }
}

// MARK: - Dock Tile

/// Shows the rendered tile image on the app's Dock tile.
@MainActor
final class DockTileView: NSView {
    var icon: NSImage? {
        didSet {
            needsDisplay = true
        }
    }

    override func draw(_: CGRect) {
        guard let icon, icon.size.width > 0, icon.size.height > 0 else {
            return
        }
        // The renderer already leaves an app-icon margin; fit the square
        // image to the tile and keep its aspect ratio should they differ
        let scale = min(bounds.width / icon.size.width, bounds.height / icon.size.height)
        let size = CGSize(width: icon.size.width * scale, height: icon.size.height * scale)
        let origin = CGPoint(x: bounds.midX - size.width / 2, y: bounds.midY - size.height / 2)
        icon.draw(in: CGRect(origin: origin, size: size), from: .zero, operation: .sourceOver, fraction: 1)
    }
}

/// Owns the app's Dock tile content while `showInDock` is on.
@MainActor
enum DockTile {
    private static let view = DockTileView()

    /// Puts `icon` on the tile, installing the content view on first use.
    /// Skips the redraw when the same image is already shown.
    static func show(_ icon: NSImage) {
        let tile = NSApp.dockTile
        if tile.contentView !== view {
            tile.contentView = view
        }
        guard view.icon !== icon else {
            return
        }
        view.icon = icon
        tile.display()
    }

    /// Returns the tile to the app icon, for when the tile is withdrawn or
    /// the preference is turned off.
    static func clear() {
        view.icon = nil
        NSApp.dockTile.contentView = nil
        NSApp.dockTile.display()
    }
}
