import Cocoa

final class ColorSwatch: NSView {
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

    // MARK: - Private Properties

    private let swatchSize = 16.0
    private let spacing = 6.0
    private let padding = 12.0
    private var hoveredIndex: Int?

    private var colors: [NSColor] { Self.presetColors }

    // MARK: - NSView Overrides

    override var intrinsicContentSize: CGSize {
        let count = Double(colors.count + 1) // +1 for custom color button
        let width = padding * 2 + count * swatchSize + (count - 1) * spacing
        let height = swatchSize + padding
        return CGSize(width: width, height: height)
    }

    override func draw(_ dirtyRect: CGRect) {
        super.draw(dirtyRect)

        var xOffset = padding
        let yOffset = (bounds.height - swatchSize) / 2

        // Draw color swatches
        for (index, color) in colors.enumerated() {
            let swatchRect = CGRect(x: xOffset, y: yOffset, width: swatchSize, height: swatchSize)
            drawSwatch(color: color, in: swatchRect, highlighted: hoveredIndex == index)
            xOffset += swatchSize + spacing
        }

        // Draw custom color button (rainbow gradient circle)
        let customRect = CGRect(x: xOffset, y: yOffset, width: swatchSize, height: swatchSize)
        let customHighlighted = hoveredIndex == colors.count
        drawCustomColorButton(in: customRect, highlighted: customHighlighted)
    }

    override func mouseUp(with event: NSEvent) {
        let location = convert(event.locationInWindow, from: nil)

        var xOffset = padding
        let yOffset = (bounds.height - swatchSize) / 2

        // Check color swatches
        for color in colors {
            let swatchRect = CGRect(x: xOffset, y: yOffset, width: swatchSize, height: swatchSize)
            if swatchRect.contains(location) {
                onColorSelected?(color)
                return
            }
            xOffset += swatchSize + spacing
        }

        // Check custom color button
        let customRect = CGRect(x: xOffset, y: yOffset, width: swatchSize, height: swatchSize)
        if customRect.contains(location) {
            onCustomColorRequested?()
        }
    }

    override func mouseMoved(with event: NSEvent) {
        let location = convert(event.locationInWindow, from: nil)
        let newIndex = indexForLocation(location)
        if newIndex != hoveredIndex {
            hoveredIndex = newIndex
            needsDisplay = true
        }
    }

    override func mouseExited(with _: NSEvent) {
        hoveredIndex = nil
        needsDisplay = true
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in trackingAreas {
            removeTrackingArea(area)
        }
        addTrackingArea(NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .mouseMoved, .activeAlways],
            owner: self,
            userInfo: nil
        ))
    }

    // MARK: - Private Methods

    private func indexForLocation(_ location: CGPoint) -> Int? {
        var xOffset = padding
        let yOffset = (bounds.height - swatchSize) / 2

        for index in 0 ..< colors.count {
            let swatchRect = CGRect(x: xOffset, y: yOffset, width: swatchSize, height: swatchSize)
            if swatchRect.contains(location) {
                return index
            }
            xOffset += swatchSize + spacing
        }

        // Check custom color button
        let customRect = CGRect(x: xOffset, y: yOffset, width: swatchSize, height: swatchSize)
        if customRect.contains(location) {
            return colors.count
        }

        return nil
    }

    private func drawSwatch(color: NSColor, in rect: CGRect, highlighted: Bool) {
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
