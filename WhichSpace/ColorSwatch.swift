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

    // MARK: - SwatchView Overrides

    override var itemCount: Int { Self.presetColors.count + 1 } // +1 for custom color button
    override var swatchSize: Double { 16.0 }
    override var spacing: Double { 6.0 }

    override func drawItem(at index: Int, in rect: CGRect, highlighted: Bool) {
        if index < Self.presetColors.count {
            drawColorSwatch(Self.presetColors[index], in: rect, highlighted: highlighted)
        } else {
            drawCustomColorButton(in: rect, highlighted: highlighted)
        }
    }

    override func handleSelection(at index: Int) {
        if index < Self.presetColors.count {
            onColorSelected?(Self.presetColors[index])
        } else {
            onCustomColorRequested?()
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
