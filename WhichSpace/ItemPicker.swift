import Cocoa
import Defaults
import EmojiKit

// MARK: - ToneLabelView

/// A clickable view that displays the skin tone emoji and handles clicks
/// Draws text directly to avoid subviews intercepting mouse events
private final class ToneLabelView: NSView {
    private var emoji: String

    var onClick: (() -> Void)?

    override var acceptsFirstResponder: Bool { true }
    override var isFlipped: Bool { true }

    init(emoji: String) {
        self.emoji = emoji
        super.init(frame: .zero)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func setEmoji(_ newEmoji: String) {
        emoji = newEmoji
        display() // Force immediate redraw (needsDisplay doesn't work reliably in menus)
    }

    override func draw(_ dirtyRect: CGRect) {
        super.draw(dirtyRect)

        let font = NSFont.systemFont(ofSize: 16)
        let attributes: [NSAttributedString.Key: Any] = [.font: font]
        let size = emoji.size(withAttributes: attributes)

        // Center the emoji in the view
        let x = (bounds.width - size.width) / 2
        let y = (bounds.height - size.height) / 2
        emoji.draw(at: NSPoint(x: x, y: y), withAttributes: attributes)
    }

    override func mouseUp(with event: NSEvent) {
        let location = convert(event.locationInWindow, from: nil)
        if bounds.contains(location) {
            onClick?()
        } else {
            super.mouseUp(with: event)
        }
    }
}

// MARK: - ItemPicker

/// A reusable picker component that displays a searchable grid of items (symbols or emojis)
final class ItemPicker: NSView {
    // MARK: - Item Type

    enum ItemType {
        case symbols
        case emojis

        var items: [String] {
            switch self {
            case .symbols:
                ItemData.symbols
            case .emojis:
                ItemData.emojis
            }
        }

        var searchPlaceholder: String {
            Localization.search
        }

        var itemSize: Double {
            switch self {
            case .symbols:
                24
            case .emojis:
                28
            }
        }

        var columns: Int {
            switch self {
            case .symbols:
                8
            case .emojis:
                10
            }
        }
    }

    // MARK: - Configuration

    private let padding: Double = 8
    private let scrollbarWidth: Double = 15
    private let searchFieldHeight: Double = 22
    private let spacing: Double = 6
    private let visibleRows = 8

    // MARK: - Public Properties

    var darkMode = false {
        didSet {
            gridView.darkMode = darkMode
            gridView.needsDisplay = true
        }
    }

    var onItemHoverEnd: (() -> Void)?
    var onItemHoverStart: ((String) -> Void)?
    var onItemSelected: ((String?) -> Void)?
    var selectedItem: String?

    // MARK: - Private Properties

    private let gridView: ItemGridView
    private let itemType: ItemType
    private let searchField = NSSearchField()
    private let scrollView = NSScrollView()

    private var allItems: [String]
    private var filteredItems: [String]
    private var toneLabelView: ToneLabelView?

    // MARK: - Computed Properties

    override var acceptsFirstResponder: Bool { true }

    override var intrinsicContentSize: CGSize {
        let gridWidth = padding * 2 + Double(itemType.columns) * itemType.itemSize
            + Double(itemType.columns - 1) * spacing + scrollbarWidth
        let maxGridHeight = Double(visibleRows) * itemType.itemSize + Double(visibleRows - 1) * spacing + padding
        let totalHeight = padding + searchFieldHeight + padding + maxGridHeight + padding
        return CGSize(width: gridWidth, height: totalHeight)
    }

    // MARK: - Initialization

    init(type: ItemType) {
        itemType = type
        allItems = type.items
        filteredItems = allItems
        gridView = ItemGridView(
            items: allItems,
            columns: type.columns,
            itemSize: type.itemSize,
            spacing: spacing,
            itemType: type
        )
        super.init(frame: .zero)
        setupViews()
    }

    override init(frame frameRect: CGRect) {
        itemType = .symbols
        allItems = itemType.items
        filteredItems = allItems
        gridView = ItemGridView(
            items: allItems,
            columns: itemType.columns,
            itemSize: itemType.itemSize,
            spacing: spacing,
            itemType: itemType
        )
        super.init(frame: frameRect)
        setupViews()
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Private Methods

    private func setupViews() {
        // Search field at top
        searchField.placeholderString = itemType.searchPlaceholder
        searchField.delegate = self
        searchField.translatesAutoresizingMaskIntoConstraints = false
        addSubview(searchField)

        // Tone label (emoji picker only) - custom view that handles mouseUp
        // Clicking cycles through skin tones (yellow -> light -> medium-light -> medium -> medium-dark -> dark)
        if itemType == .emojis {
            let labelView = ToneLabelView(emoji: toneEmojis[Defaults[.emojiPickerSkinTone].rawValue])
            labelView.translatesAutoresizingMaskIntoConstraints = false
            labelView.onClick = { [weak self] in
                self?.cycleTone()
            }
            addSubview(labelView)
            toneLabelView = labelView
        }

        // Scroll view for grid
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.scrollerStyle = .legacy
        scrollView.autohidesScrollers = false
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = false
        addSubview(scrollView)

        // Grid view inside scroll view
        gridView.onItemSelected = { [weak self] item in
            guard let self else {
                return
            }
            // Save the base emoji without skin tone - the per-space skin tone
            // from the Color menu will be applied at render time
            self.onItemSelected?(item)
        }
        gridView.onItemHoverStart = { [weak self] item in
            self?.onItemHoverStart?(item)
        }
        gridView.onItemHoverEnd = { [weak self] in
            self?.onItemHoverEnd?()
        }
        scrollView.documentView = gridView

        var constraints = [
            searchField.topAnchor.constraint(equalTo: topAnchor, constant: padding),
            searchField.leadingAnchor.constraint(equalTo: leadingAnchor, constant: padding),
            searchField.heightAnchor.constraint(equalToConstant: searchFieldHeight),

            scrollView.topAnchor.constraint(equalTo: searchField.bottomAnchor, constant: padding),
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor),
        ]

        if let toneLabelView {
            constraints.append(contentsOf: [
                searchField.trailingAnchor.constraint(equalTo: toneLabelView.leadingAnchor, constant: -4),
                toneLabelView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -padding),
                toneLabelView.centerYAnchor.constraint(equalTo: searchField.centerYAnchor),
                toneLabelView.widthAnchor.constraint(equalToConstant: 36),
                toneLabelView.heightAnchor.constraint(equalToConstant: searchFieldHeight),
            ])
        } else {
            constraints.append(
                searchField.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -padding)
            )
        }

        NSLayoutConstraint.activate(constraints)
        updateGridView()
    }

    // MARK: - Skin Tone Support

    private let toneEmojis = ["🖐️", "🖐🏻", "🖐🏼", "🖐🏽", "🖐🏾", "🖐🏿"]

    private func updateGridView() {
        let darkModeChanged = gridView.darkMode != darkMode
        gridView.items = filteredItems
        gridView.selectedItem = selectedItem
        gridView.darkMode = darkMode
        gridView.skinToneModifier = Defaults[.emojiPickerSkinTone].modifier
        gridView.updateSize()
        if darkModeChanged {
            gridView.clearImageCache()
        }
        gridView.needsDisplay = true
    }

    // MARK: - Tone Selection

    private func cycleTone() {
        let currentTone = Defaults[.emojiPickerSkinTone]
        let nextIndex = (currentTone.rawValue + 1) % SkinTone.allCases.count
        let nextTone = SkinTone(rawValueOrDefault: nextIndex)
        Defaults[.emojiPickerSkinTone] = nextTone
        toneLabelView?.setEmoji(toneEmojis[nextIndex])
        gridView.skinToneModifier = nextTone.modifier
        gridView.display()
    }
}

// MARK: - NSSearchFieldDelegate

extension ItemPicker: NSSearchFieldDelegate {
    func controlTextDidChange(_: Notification) {
        let searchText = searchField.stringValue
        if searchText.isEmpty {
            filteredItems = allItems
        } else {
            switch itemType {
            case .symbols:
                // For symbols, do simple case-insensitive substring match
                filteredItems = allItems.filter { $0.lowercased().contains(searchText.lowercased()) }
            case .emojis:
                // For emojis, use EmojiKit's semantic search (by name/keywords)
                let matchingEmojis = Emoji.all.matching(searchText)
                let matchingChars = Set(matchingEmojis.map(\.char))
                filteredItems = allItems.filter { matchingChars.contains($0) }
            }
        }
        updateGridView()
    }
}

// MARK: - ItemGridView

private final class ItemGridView: NSView {
    // MARK: - Properties

    var darkMode = false
    var items: [String]
    var onItemHoverEnd: (() -> Void)?
    var onItemHoverStart: ((String) -> Void)?
    var onItemSelected: ((String) -> Void)?
    var selectedItem: String?
    var skinToneModifier: String?

    // MARK: - Private Properties

    private let columns: Int
    private let itemSize: Double
    private let itemType: ItemPicker.ItemType
    private let padding: Double = 8
    private let spacing: Double

    private var hoveredIndex: Int?
    private var imageCache: [String: NSImage] = [:]

    // MARK: - Computed Properties

    override var isFlipped: Bool { true }

    // MARK: - Initialization

    init(items: [String], columns: Int, itemSize: Double, spacing: Double, itemType: ItemPicker.ItemType) {
        self.items = items
        self.columns = columns
        self.itemSize = itemSize
        self.spacing = spacing
        self.itemType = itemType
        super.init(frame: .zero)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Public Methods

    func updateSize() {
        let rows = (items.count + columns - 1) / columns
        let width = padding * 2 + Double(columns) * itemSize + Double(columns - 1) * spacing
        let height = padding * 2 + Double(rows) * itemSize + Double(rows - 1) * spacing
        let newFrame = CGRect(x: 0, y: 0, width: width, height: max(height, 50))

        // Only update frame if size changed to avoid unnecessary layout passes
        if frame.size != newFrame.size {
            frame = newFrame
        }
    }

    func clearImageCache() {
        imageCache.removeAll()
    }

    // MARK: - Drawing

    override func draw(_ dirtyRect: CGRect) {
        super.draw(dirtyRect)

        guard !items.isEmpty else {
            return
        }

        let cellHeight = itemSize + spacing
        let cellWidth = itemSize + spacing
        let totalRows = (items.count + columns - 1) / columns

        let minRow = max(0, Int((dirtyRect.minY - padding) / cellHeight))
        let maxRow = min(totalRows, Int((dirtyRect.maxY - padding) / cellHeight) + 1)

        guard minRow < maxRow else {
            return
        }

        for row in minRow ..< maxRow {
            for col in 0 ..< columns {
                let index = row * columns + col
                guard index < items.count else { continue }

                let item = items[index]
                let xOffset = padding + Double(col) * cellWidth
                let yOffset = padding + Double(row) * cellHeight

                let itemRect = CGRect(x: xOffset, y: yOffset, width: itemSize, height: itemSize)

                guard itemRect.intersects(dirtyRect) else { continue }

                let isHighlighted = hoveredIndex == index
                let isSelected = selectedItem == item
                drawItem(item, in: itemRect, highlighted: isHighlighted, selected: isSelected)
            }
        }
    }

    private func drawItem(_ item: String, in rect: CGRect, highlighted: Bool, selected: Bool) {
        if highlighted || selected {
            let highlightRect = rect.insetBy(dx: -2, dy: -2)
            let highlightPath = NSBezierPath(roundedRect: highlightRect, xRadius: 4, yRadius: 4)
            if selected {
                NSColor.selectedContentBackgroundColor.setFill()
            } else {
                NSColor.selectedContentBackgroundColor.withAlphaComponent(0.5).setFill()
            }
            highlightPath.fill()
        }

        switch itemType {
        case .symbols:
            drawSymbol(item, in: rect)
        case .emojis:
            drawEmoji(item, in: rect)
        }
    }

    private func drawSymbol(_ symbolName: String, in rect: CGRect) {
        let cacheKey = "\(symbolName)_\(darkMode)"
        let tintedImage: NSImage
        if let cached = imageCache[cacheKey] {
            tintedImage = cached
        } else {
            let config = NSImage.SymbolConfiguration(pointSize: 17, weight: .medium)
            guard let image = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil)?
                .withSymbolConfiguration(config)
            else {
                return
            }
            let color = darkMode ? NSColor(calibratedWhite: 0.7, alpha: 1) : NSColor(calibratedWhite: 0.3, alpha: 1)
            tintedImage = image.tinted(with: color)
            imageCache[cacheKey] = tintedImage
        }

        let imageSize = tintedImage.size
        let xStart = rect.origin.x + (rect.width - imageSize.width) / 2
        let yStart = rect.origin.y + (rect.height - imageSize.height) / 2
        let imageRect = NSRect(x: xStart, y: yStart, width: imageSize.width, height: imageSize.height)

        tintedImage.draw(in: imageRect)
    }

    private func drawEmoji(_ emoji: String, in rect: CGRect) {
        var displayEmoji = emoji
        if skinToneModifier != nil {
            displayEmoji = SkinTone.apply(to: emoji)
        }

        let font = NSFont.systemFont(ofSize: itemSize * 0.7)
        let attributes: [NSAttributedString.Key: Any] = [.font: font]
        let emojiTextSize = displayEmoji.size(withAttributes: attributes)

        let xStart = rect.origin.x + (rect.width - emojiTextSize.width) / 2
        let yStart = rect.origin.y + (rect.height - emojiTextSize.height) / 2
        let textRect = NSRect(x: xStart, y: yStart, width: emojiTextSize.width, height: emojiTextSize.height)

        displayEmoji.draw(in: textRect, withAttributes: attributes)
    }

    // MARK: - Event Handling

    override func mouseUp(with event: NSEvent) {
        let location = convert(event.locationInWindow, from: nil)
        if let index = indexForLocation(location), index < items.count {
            onItemSelected?(items[index])
        }
    }

    override func mouseMoved(with event: NSEvent) {
        let location = convert(event.locationInWindow, from: nil)
        let newIndex = indexForLocation(location)
        if newIndex != hoveredIndex {
            let oldIndex = hoveredIndex
            hoveredIndex = newIndex

            if let old = oldIndex {
                setNeedsDisplay(rectForIndex(old))
            }
            if let new = newIndex {
                setNeedsDisplay(rectForIndex(new))
                if itemType == .symbols {
                    toolTip = items[new]
                }
                onItemHoverStart?(items[new])
            } else {
                toolTip = nil
                if oldIndex != nil {
                    onItemHoverEnd?()
                }
            }
        }
    }

    override func mouseExited(with _: NSEvent) {
        if let old = hoveredIndex {
            hoveredIndex = nil
            setNeedsDisplay(rectForIndex(old))
            onItemHoverEnd?()
        }
        toolTip = nil
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

    // MARK: - Private Helpers

    private func rectForIndex(_ index: Int) -> CGRect {
        let col = index % columns
        let row = index / columns
        let xOffset = padding + Double(col) * (itemSize + spacing)
        let yOffset = padding + Double(row) * (itemSize + spacing)
        return CGRect(x: xOffset - 2, y: yOffset - 2, width: itemSize + 4, height: itemSize + 4)
    }

    private func indexForLocation(_ location: CGPoint) -> Int? {
        let col = Int((location.x - padding) / (itemSize + spacing))
        let row = Int((location.y - padding) / (itemSize + spacing))

        guard col >= 0, col < columns, row >= 0 else {
            return nil
        }

        let index = row * columns + col
        guard index < items.count else {
            return nil
        }

        let cellX = padding + Double(col) * (itemSize + spacing)
        let cellY = padding + Double(row) * (itemSize + spacing)
        let cellRect = CGRect(x: cellX, y: cellY, width: itemSize, height: itemSize)

        return cellRect.contains(location) ? index : nil
    }
}

// MARK: - NSImage + Tinting

private extension NSImage {
    func tinted(with color: NSColor) -> NSImage {
        guard let image = copy() as? NSImage else {
            return self
        }
        image.lockFocus()
        color.set()
        let imageRect = CGRect(origin: .zero, size: image.size)
        imageRect.fill(using: .sourceAtop)
        image.unlockFocus()
        return image
    }
}
