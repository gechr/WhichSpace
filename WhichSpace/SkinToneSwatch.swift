import Cocoa
import Defaults

final class SkinToneSwatch: Swatch {
    // MARK: - Static Properties

    /// Base emoji to display with skin tone modifiers (waving hand)
    private static let baseEmoji = "\u{1F44B}"

    /// The 6 skin tone options (yellow + 5 skin tones)
    static let skinToneEmojis: [String] = SkinTone.modifiers.map { modifier in
        if let modifier {
            return baseEmoji + modifier
        }
        return baseEmoji
    }

    // MARK: - Configuration

    /// The currently selected skin tone. Set this from outside to reflect per-space tone.
    var currentTone: SkinTone = .default {
        didSet {
            if currentTone != oldValue {
                needsDisplay = true
            }
        }
    }

    var onToneSelected: ((SkinTone) -> Void)?
    var onToneHoverStart: ((SkinTone) -> Void)?

    // MARK: - Swatch Overrides

    override var itemCount: Int {
        Self.skinToneEmojis.count
    }

    override var spacing: Double {
        12.0
    }

    override func drawItem(at index: Int, in rect: CGRect, highlighted: Bool) {
        let emoji = Self.skinToneEmojis[index]
        let isSelected = index == currentTone.rawValue

        // Draw selection ring
        if isSelected {
            let ringRect = rect.insetBy(dx: -2, dy: -2)
            let ringPath = NSBezierPath(ovalIn: ringRect)
            NSColor.controlAccentColor.setStroke()
            ringPath.lineWidth = 2
            ringPath.stroke()
        }

        // Draw hover highlight
        if highlighted, !isSelected {
            let highlightRect = rect.insetBy(dx: -1, dy: -1)
            let highlightPath = NSBezierPath(ovalIn: highlightRect)
            NSColor.selectedContentBackgroundColor.withAlphaComponent(0.3).setFill()
            highlightPath.fill()
        }

        // Draw the emoji centered in the rect
        let font = NSFont.systemFont(ofSize: swatchSize * 0.8)
        let attributes: [NSAttributedString.Key: Any] = [.font: font]
        let attrString = NSAttributedString(string: emoji, attributes: attributes)
        let textSize = attrString.size()
        let textRect = CGRect(
            x: rect.midX - textSize.width / 2,
            y: rect.midY - textSize.height / 2,
            width: textSize.width,
            height: textSize.height
        )
        attrString.draw(in: textRect)
    }

    override func handleSelection(at index: Int) {
        guard let tone = SkinTone(rawValue: index) else {
            return
        }
        onToneSelected?(tone)
        needsDisplay = true
    }

    override func mouseMoved(with event: NSEvent) {
        super.mouseMoved(with: event)
        if let index = hoveredIndex, let tone = SkinTone(rawValue: index) {
            onToneHoverStart?(tone)
        }
    }
}
