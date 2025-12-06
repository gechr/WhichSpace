//
//  IconStyleRowView.swift
//  WhichSpace
//
//  Created by George Christou.
//  Copyright © 2020 George Christou. All rights reserved.
//

import Cocoa

final class IconStyleRowView: NSView {
    private let style: IconStyle
    private let iconSize: CGFloat = 20
    private var isHighlighted = false

    var onSelected: (() -> Void)?
    var isChecked: Bool = false {
        didSet { needsDisplay = true }
    }

    var customColors: SpaceColors?
    var darkMode: Bool = false
    var previewNumber: String = "1"

    init(style: IconStyle) {
        self.style = style
        super.init(frame: .zero)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: 180, height: 22)
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        if isHighlighted {
            NSColor.selectedContentBackgroundColor.setFill()
            let highlightRect = bounds.insetBy(dx: 5, dy: 1)
            NSBezierPath(roundedRect: highlightRect, xRadius: 4, yRadius: 4).fill()
        }

        // Checkmark
        if isChecked {
            let checkAttrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.menuFont(ofSize: 13),
                .foregroundColor: isHighlighted ? NSColor.white : NSColor.labelColor,
            ]
            "✓".draw(at: NSPoint(x: 8, y: 3), withAttributes: checkAttrs)
        }

        // Icon
        let icon = SpaceIconGenerator.generateIcon(
            for: previewNumber,
            darkMode: darkMode,
            customColors: customColors,
            style: style
        )
        let iconRect = NSRect(x: 24, y: (bounds.height - iconSize) / 2, width: iconSize, height: iconSize)
        icon.draw(in: iconRect)

        // Label
        let labelAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.menuFont(ofSize: 13),
            .foregroundColor: isHighlighted ? NSColor.white : NSColor.labelColor,
        ]
        let labelPoint = NSPoint(x: 24 + iconSize + 8, y: 3)
        style.localizedTitle.draw(at: labelPoint, withAttributes: labelAttrs)
    }

    override func mouseEntered(with _: NSEvent) {
        isHighlighted = true
        needsDisplay = true
    }

    override func mouseExited(with _: NSEvent) {
        isHighlighted = false
        needsDisplay = true
    }

    override func mouseUp(with _: NSEvent) {
        onSelected?()
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
}
