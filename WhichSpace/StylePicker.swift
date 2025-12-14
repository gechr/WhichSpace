import Cocoa

final class StylePicker: NSView {
    private let iconSize = Layout.defaultIconSize
    private let style: IconStyle

    private var isHighlighted = false

    var customColors: SpaceColors?
    var darkMode = false
    var isChecked = false {
        didSet { needsDisplay = true }
    }

    var onHoverEnd: (() -> Void)?
    var onHoverStart: ((IconStyle) -> Void)?
    var onSelected: (() -> Void)?
    var previewNumber = "1"

    init(style: IconStyle) {
        self.style = style
        super.init(frame: .zero)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var intrinsicContentSize: CGSize {
        CGSize(width: 180, height: Layout.statusItemHeight)
    }

    override func draw(_ dirtyRect: CGRect) {
        super.draw(dirtyRect)

        if isHighlighted {
            NSColor.selectedContentBackgroundColor.setFill()
            let highlightRect = bounds.insetBy(dx: 5, dy: 1)
            NSBezierPath(roundedRect: highlightRect, xRadius: 4, yRadius: 4).fill()
        }

        // Checkmark
        if isChecked {
            let checkAttrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.menuFont(ofSize: Layout.menuFontSize),
                .foregroundColor: isHighlighted ? NSColor.white : NSColor.labelColor,
            ]
            "✓".draw(at: CGPoint(x: 9, y: 3), withAttributes: checkAttrs)
        }

        // Icon
        let icon = SpaceIconGenerator.generateIcon(
            for: previewNumber,
            darkMode: darkMode,
            customColors: customColors,
            style: style
        )
        let iconRect = CGRect(x: 24, y: (bounds.height - iconSize) / 2, width: iconSize, height: iconSize)
        icon.draw(in: iconRect)

        // Label
        let labelAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.menuFont(ofSize: Layout.menuFontSize),
            .foregroundColor: isHighlighted ? NSColor.white : NSColor.labelColor,
        ]
        let labelPoint = CGPoint(x: 24 + iconSize + 8, y: 3)
        style.localizedTitle.draw(at: labelPoint, withAttributes: labelAttrs)
    }

    override func mouseEntered(with _: NSEvent) {
        isHighlighted = true
        needsDisplay = true
        onHoverStart?(style)
    }

    override func mouseExited(with _: NSEvent) {
        isHighlighted = false
        needsDisplay = true
        onHoverEnd?()
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
