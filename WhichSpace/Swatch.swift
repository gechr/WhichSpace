import Cocoa

// Base class for swatch-style picker views (colors, skin tones, etc.)
// swiftlint:disable:next final_class
class Swatch: NSView {
    // MARK: - Configuration (override in subclasses)

    /// Number of items to display
    var itemCount: Int {
        0
    }

    /// Size of each swatch circle/item
    var swatchSize: Double {
        20.0
    }

    /// Spacing between swatches
    var spacing: Double {
        4.0
    }

    /// Left padding before first swatch
    var leftPadding: Double {
        16.0
    }

    /// Right padding after last swatch
    var rightPadding: Double {
        12.0
    }

    // MARK: - Callbacks

    var onHoverEnd: (() -> Void)?
    var onHoverStart: ((Int) -> Void)?

    // MARK: - State

    private(set) var hoveredIndex: Int?

    // MARK: - NSView Overrides

    override var intrinsicContentSize: CGSize {
        let count = Double(itemCount)
        let width = leftPadding + rightPadding + count * swatchSize + max(0, count - 1) * spacing
        let height = swatchSize + rightPadding
        return CGSize(width: width, height: height)
    }

    override func draw(_ dirtyRect: CGRect) {
        super.draw(dirtyRect)

        var xOffset = leftPadding
        let yOffset = (bounds.height - swatchSize) / 2

        for index in 0 ..< itemCount {
            let swatchRect = CGRect(x: xOffset, y: yOffset, width: swatchSize, height: swatchSize)
            let isHovered = index == hoveredIndex
            drawItem(at: index, in: swatchRect, highlighted: isHovered)
            xOffset += swatchSize + spacing
        }
    }

    override func mouseUp(with event: NSEvent) {
        let location = convert(event.locationInWindow, from: nil)
        if let index = indexForLocation(location) {
            handleSelection(at: index)
        }
    }

    override func mouseMoved(with event: NSEvent) {
        let location = convert(event.locationInWindow, from: nil)
        let newIndex = indexForLocation(location)
        if newIndex != hoveredIndex {
            let oldIndex = hoveredIndex
            hoveredIndex = newIndex
            needsDisplay = true
            if let new = newIndex {
                onHoverStart?(new)
            } else if oldIndex != nil {
                onHoverEnd?()
            }
        }
    }

    override func mouseExited(with _: NSEvent) {
        if hoveredIndex != nil {
            hoveredIndex = nil
            needsDisplay = true
            onHoverEnd?()
        }
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

    // MARK: - Subclass Overrides

    /// Draw the item at the given index. Override in subclasses.
    func drawItem(at _: Int, in _: CGRect, highlighted _: Bool) {
        // Override in subclasses
    }

    /// Handle selection of item at index. Override in subclasses.
    func handleSelection(at _: Int) {
        // Override in subclasses
    }

    // MARK: - Helper Methods

    /// Returns the index of the item at the given location, or nil if none.
    func indexForLocation(_ location: CGPoint) -> Int? {
        var xOffset = leftPadding
        let yOffset = (bounds.height - swatchSize) / 2

        for index in 0 ..< itemCount {
            let swatchRect = CGRect(x: xOffset, y: yOffset, width: swatchSize, height: swatchSize)
            if swatchRect.contains(location) {
                return index
            }
            xOffset += swatchSize + spacing
        }

        return nil
    }
}
