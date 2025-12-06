//
//  MenuTextRowView.swift
//  WhichSpace
//
//  Created by George Christou.
//  Copyright © 2020 George Christou. All rights reserved.
//

import Cocoa

/// A simple text menu item view that doesn't close the menu on click
final class MenuTextRowView: NSView {
    private let title: String
    private var isHighlighted = false

    var onSelected: (() -> Void)?

    init(title: String) {
        self.title = title
        super.init(frame: .zero)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: 200, height: 22)
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        if isHighlighted {
            NSColor.selectedContentBackgroundColor.setFill()
            bounds.fill()
        }

        let textColor = isHighlighted ? NSColor.white : NSColor.labelColor
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 13),
            .foregroundColor: textColor,
        ]

        let textSize = title.size(withAttributes: attributes)
        let textY = (bounds.height - textSize.height) / 2
        let textRect = NSRect(x: 14, y: textY, width: bounds.width - 28, height: textSize.height)
        title.draw(in: textRect, withAttributes: attributes)
    }

    override func mouseUp(with event: NSEvent) {
        let location = convert(event.locationInWindow, from: nil)
        if bounds.contains(location) {
            onSelected?()
        }
    }

    override func mouseMoved(with event: NSEvent) {
        let location = convert(event.locationInWindow, from: nil)
        let shouldHighlight = bounds.contains(location)
        if shouldHighlight != isHighlighted {
            isHighlighted = shouldHighlight
            needsDisplay = true
        }
    }

    override func mouseEntered(with _: NSEvent) {
        isHighlighted = true
        needsDisplay = true
    }

    override func mouseExited(with _: NSEvent) {
        isHighlighted = false
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
}
