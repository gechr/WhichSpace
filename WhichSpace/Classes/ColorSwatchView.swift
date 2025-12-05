//
//  ColorSwatchView.swift
//  WhichSpace
//
//  Created by George Christou.
//  Copyright © 2020 George Christou. All rights reserved.
//

import Cocoa

class ColorSwatchView: NSView {
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

    private let swatchSize: CGFloat = 16
    private let spacing: CGFloat = 6
    private let padding: CGFloat = 12

    var onColorSelected: ((NSColor) -> Void)?
    var onCustomColorRequested: (() -> Void)?

    override var intrinsicContentSize: NSSize {
        let count = CGFloat(Self.presetColors.count + 1) // +1 for custom color button
        let width = padding * 2 + count * swatchSize + (count - 1) * spacing
        let height = swatchSize + padding
        return NSSize(width: width, height: height)
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        var xOffset = padding
        let yOffset = (bounds.height - swatchSize) / 2

        // Draw preset color swatches
        for color in Self.presetColors {
            let swatchRect = NSRect(x: xOffset, y: yOffset, width: swatchSize, height: swatchSize)
            drawSwatch(color: color, in: swatchRect)
            xOffset += swatchSize + spacing
        }

        // Draw custom color button (rainbow gradient circle)
        let customRect = NSRect(x: xOffset, y: yOffset, width: swatchSize, height: swatchSize)
        drawCustomColorButton(in: customRect)
    }

    private func drawSwatch(color: NSColor, in rect: NSRect) {
        let path = NSBezierPath(ovalIn: rect.insetBy(dx: 1, dy: 1))

        // Draw border for light colors
        NSColor.gray.withAlphaComponent(0.5).setStroke()
        path.lineWidth = 1
        path.stroke()

        color.setFill()
        path.fill()
    }

    private func drawCustomColorButton(in rect: NSRect) {
        let path = NSBezierPath(ovalIn: rect.insetBy(dx: 1, dy: 1))

        // Draw a simple "+" or gradient to indicate custom
        NSColor.gray.withAlphaComponent(0.5).setStroke()
        path.lineWidth = 1
        path.stroke()

        // Draw rainbow-ish gradient
        let colors = [NSColor.systemRed, NSColor.systemYellow, NSColor.systemGreen, NSColor.systemBlue]
        let center = NSPoint(x: rect.midX, y: rect.midY)
        let radius = swatchSize / 2 - 2

        for (index, color) in colors.enumerated() {
            let startAngle = CGFloat(index) * 90
            let endAngle = CGFloat(index + 1) * 90
            let wedge = NSBezierPath()
            wedge.move(to: center)
            wedge.appendArc(withCenter: center, radius: radius, startAngle: startAngle, endAngle: endAngle)
            wedge.close()
            color.setFill()
            wedge.fill()
        }
    }

    override func mouseUp(with event: NSEvent) {
        let location = convert(event.locationInWindow, from: nil)
        var xOffset = padding
        let yOffset = (bounds.height - swatchSize) / 2

        // Check preset colors
        for color in Self.presetColors {
            let swatchRect = NSRect(x: xOffset, y: yOffset, width: swatchSize, height: swatchSize)
            if swatchRect.contains(location) {
                onColorSelected?(color)
                return
            }
            xOffset += swatchSize + spacing
        }

        // Check custom color button
        let customRect = NSRect(x: xOffset, y: yOffset, width: swatchSize, height: swatchSize)
        if customRect.contains(location) {
            onCustomColorRequested?()
        }
    }
}
