import Cocoa

final class ColorSwatch: Swatch {
    // MARK: - Static Properties

    static let presetColors: [NSColor] = [
        .black,
        .white,
        .systemRed,
        .systemOrange,
        .systemYellow,
        .systemGreen,
        .systemBlue,
        .systemPurple,
    ]

    // MARK: - Configuration

    var onColorSelected: ((NSColor) -> Void)?
    var onCustomColorRequested: (() -> Void)?
    /// When set, a "no color" cell is shown after the custom color button;
    /// selecting it invokes this callback
    var onClearRequested: (() -> Void)?

    /// Index of the optional clear cell (last, after the custom button)
    static var clearIndex: Int {
        presetColors.count + 1
    }

    // MARK: - SwatchView Overrides

    override var itemCount: Int {
        Self.presetColors.count + 1 + (onClearRequested != nil ? 1 : 0)
    } // +1 for custom color button, +1 for the optional clear cell
    override var swatchSize: Double {
        16.0
    }

    override var spacing: Double {
        6.0
    }

    override func drawItem(at index: Int, in rect: CGRect, highlighted: Bool) {
        if index < Self.presetColors.count {
            drawColorSwatch(Self.presetColors[index], in: rect, highlighted: highlighted)
        } else if index == Self.presetColors.count {
            drawCustomColorButton(in: rect, highlighted: highlighted)
        } else {
            drawClearButton(in: rect, highlighted: highlighted)
        }
    }

    override func handleSelection(at index: Int) {
        if index < Self.presetColors.count {
            onColorSelected?(Self.presetColors[index])
        } else if index == Self.presetColors.count {
            onCustomColorRequested?()
        } else {
            onClearRequested?()
        }
    }

    // MARK: - Private Methods

    private func drawColorSwatch(_ color: NSColor, in rect: CGRect, highlighted: Bool) {
        if highlighted {
            let highlightRect = rect.insetBy(dx: -2, dy: -2)
            let highlightPath = NSBezierPath(ovalIn: highlightRect)
            NSColor.selectedContentBackgroundColor.setFill()
            highlightPath.fill()
        }

        let path = NSBezierPath(ovalIn: rect.insetBy(dx: 1, dy: 1))

        // Draw border for light colors
        NSColor.gray.withAlphaComponent(0.5).setStroke()
        path.lineWidth = 1
        path.stroke()

        color.setFill()
        path.fill()
    }

    private func drawClearButton(in rect: CGRect, highlighted: Bool) {
        if highlighted {
            let highlightRect = rect.insetBy(dx: -2, dy: -2)
            let highlightPath = NSBezierPath(ovalIn: highlightRect)
            NSColor.selectedContentBackgroundColor.setFill()
            highlightPath.fill()
        }

        let inset = rect.insetBy(dx: 1, dy: 1)
        let path = NSBezierPath(ovalIn: inset)
        NSColor.gray.withAlphaComponent(0.5).setStroke()
        path.lineWidth = 1
        path.stroke()

        // Diagonal slash marking "no color"
        let slash = NSBezierPath()
        let offset = inset.width * 0.15
        slash.move(to: CGPoint(x: inset.minX + offset, y: inset.minY + offset))
        slash.line(to: CGPoint(x: inset.maxX - offset, y: inset.maxY - offset))
        NSColor.systemRed.setStroke()
        slash.lineWidth = 1.5
        slash.stroke()
    }

    private func drawCustomColorButton(in rect: CGRect, highlighted: Bool) {
        if highlighted {
            let highlightRect = rect.insetBy(dx: -2, dy: -2)
            let highlightPath = NSBezierPath(ovalIn: highlightRect)
            NSColor.selectedContentBackgroundColor.setFill()
            highlightPath.fill()
        }

        let path = NSBezierPath(ovalIn: rect.insetBy(dx: 1, dy: 1))

        // Draw a simple "+" or gradient to indicate custom
        NSColor.gray.withAlphaComponent(0.5).setStroke()
        path.lineWidth = 1
        path.stroke()

        // Draw rainbow-ish gradient
        let colors = [NSColor.systemRed, NSColor.systemYellow, NSColor.systemGreen, NSColor.systemBlue]
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let radius = swatchSize / 2 - 2

        for (index, color) in colors.enumerated() {
            let startAngle = Double(index) * 90
            let endAngle = Double(index + 1) * 90
            let wedge = NSBezierPath()
            wedge.move(to: center)
            wedge.appendArc(withCenter: center, radius: radius, startAngle: startAngle, endAngle: endAngle)
            wedge.close()
            color.setFill()
            wedge.fill()
        }
    }
}
