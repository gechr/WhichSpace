import Cocoa

// MARK: - Size Row View

final class SizeSlider: NSView {
    private let slider: NSSlider
    private let titleLabel: NSTextField
    private let valueLabel: NSTextField
    private let valueFormatter: (Double) -> String

    private static let titleFont = NSFont.systemFont(ofSize: 12, weight: .semibold)
    private static let valueFont = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .regular)

    private static let labelGap = 8.0
    private static let minimumContentWidth = 168.0

    private let bottomPadding = 5.0
    private let controlHeight = 18.0
    private let padding = 16.0
    private let rowGap = 5.0
    private let titleHeight = 16.0
    private let topPadding = 7.0

    private let increment = 1.0
    private let range: ClosedRange<Double>

    /// Content width that fits the title next to the widest formatted value
    private var requiredContentWidth = 0.0

    var onSizeChanged: ((Double) -> Void)?

    private var value: Double {
        didSet {
            slider.doubleValue = value
            valueLabel.stringValue = valueFormatter(value)
            needsLayout = true
        }
    }

    var currentSize: Double {
        get { value }
        set { value = newValue }
    }

    init(
        title: String,
        initialSize: Double,
        range: ClosedRange<Double>,
        numberOfTickMarks: Int? = nil,
        valueFormatter: @escaping (Double) -> String = { String(format: "%.0f%%", $0) }
    ) {
        self.range = range
        self.valueFormatter = valueFormatter
        value = initialSize

        slider = NSSlider(
            value: initialSize,
            minValue: range.lowerBound,
            maxValue: range.upperBound,
            target: nil,
            action: nil
        )
        titleLabel = NSTextField(labelWithString: title)
        valueLabel = NSTextField(labelWithString: valueFormatter(initialSize))

        super.init(frame: .zero)

        autoresizingMask = [.width]
        setupSlider(numberOfTickMarks: numberOfTickMarks)
        setupLabels()
        measureRequiredContentWidth(numberOfTickMarks: numberOfTickMarks)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Setup

    private func setupSlider(numberOfTickMarks: Int?) {
        slider.controlSize = .small
        slider.target = self
        slider.action = #selector(sliderChanged)
        slider.isContinuous = true
        if let numberOfTickMarks {
            slider.numberOfTickMarks = numberOfTickMarks
            slider.allowsTickMarkValuesOnly = true
        }
        addSubview(slider)
    }

    /// Measures with the actual labels so NSTextField's internal padding is included.
    /// Discrete sliders can show a word per tick, so measure every stop; numeric
    /// labels use monospaced digits, so the endpoints are the widest.
    private func measureRequiredContentWidth(numberOfTickMarks: Int?) {
        let sampleValues: [Double]
        if let numberOfTickMarks, numberOfTickMarks > 1 {
            let step = (range.upperBound - range.lowerBound) / Double(numberOfTickMarks - 1)
            sampleValues = (0 ..< numberOfTickMarks).map { range.lowerBound + Double($0) * step }
        } else {
            sampleValues = [range.lowerBound, range.upperBound]
        }
        var maxValueWidth = 0.0
        for sampleValue in sampleValues {
            valueLabel.stringValue = valueFormatter(sampleValue)
            maxValueWidth = max(maxValueWidth, valueLabel.intrinsicContentSize.width)
        }
        valueLabel.stringValue = valueFormatter(value)

        let titleWidth = titleLabel.intrinsicContentSize.width
        requiredContentWidth = max(Self.minimumContentWidth, ceil(titleWidth + Self.labelGap + maxValueWidth))
        invalidateIntrinsicContentSize()
    }

    private func setupLabels() {
        titleLabel.font = Self.titleFont
        titleLabel.textColor = .secondaryLabelColor
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.alignment = .left
        addSubview(titleLabel)

        valueLabel.font = Self.valueFont
        valueLabel.textColor = .labelColor
        valueLabel.alignment = .right
        addSubview(valueLabel)
    }

    // MARK: - Layout

    override var intrinsicContentSize: CGSize {
        let width = padding + requiredContentWidth + padding
        let height = bottomPadding + controlHeight + rowGap + titleHeight + topPadding
        return CGSize(width: width, height: height)
    }

    override func layout() {
        super.layout()

        let contentWidth = max(bounds.width - padding * 2, requiredContentWidth)
        let sliderY = bottomPadding
        let titleY = sliderY + controlHeight + rowGap

        slider.frame = CGRect(x: padding, y: sliderY, width: contentWidth, height: controlHeight)

        valueLabel.sizeToFit()
        let valueWidth = min(valueLabel.frame.width, contentWidth)
        valueLabel.frame = CGRect(
            x: padding + contentWidth - valueWidth,
            y: titleY,
            width: valueWidth,
            height: titleHeight
        )
        titleLabel.frame = CGRect(
            x: padding,
            y: titleY,
            width: max(0, contentWidth - valueWidth - Self.labelGap),
            height: titleHeight
        )
    }

    // MARK: - Mouse Events

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        super.mouseDown(with: event)
    }

    // MARK: - Keyboard Events

    override var acceptsFirstResponder: Bool {
        true
    }

    private enum KeyCode {
        static let leftArrow: UInt16 = 0x7B
        static let rightArrow: UInt16 = 0x7C
        static let downArrow: UInt16 = 0x7D
        static let upArrow: UInt16 = 0x7E
    }

    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case KeyCode.leftArrow, KeyCode.downArrow:
            step(by: -1)
        case KeyCode.rightArrow, KeyCode.upArrow:
            step(by: 1)
        default:
            super.keyDown(with: event)
        }
    }

    // MARK: - Scroll Events

    /// Accumulated precise scroll delta; a step fires each time it crosses the threshold
    private static let scrollStepThreshold = 10.0
    private var scrollAccumulator = 0.0

    override func scrollWheel(with event: NSEvent) {
        // Ignore momentum-phase events so a trackpad flick doesn't slam min-to-max
        guard event.momentumPhase.isEmpty else {
            return
        }
        // Each gesture starts from a clean slate so leftovers don't carry
        // over and fight a direction change
        if event.phase == .began {
            scrollAccumulator = 0
        }

        // Positive deltaY = scroll up = increase value
        // Negative deltaY = scroll down = decrease value
        let steps: Double
        if event.hasPreciseScrollingDeltas {
            // Trackpads emit many small deltas per gesture; accumulate to a threshold
            scrollAccumulator += event.scrollingDeltaY
            steps = (scrollAccumulator / Self.scrollStepThreshold).rounded(.towardZero)
            scrollAccumulator -= steps * Self.scrollStepThreshold
        } else {
            // Mouse wheels emit one event per notch; step directly
            steps = event.deltaY > 0 ? 1 : (event.deltaY < 0 ? -1 : 0)
        }
        guard steps != 0 else {
            return
        }

        step(by: steps)
    }

    // MARK: - Actions

    /// Adjusts the value by a number of increments, clamped to the range.
    /// Always notifies, matching stepper-style semantics at the bounds.
    private func step(by steps: Double) {
        window?.makeFirstResponder(self)
        value = (value + steps * increment).clamped(to: range)
        onSizeChanged?(value)
    }

    @objc private func sliderChanged() {
        window?.makeFirstResponder(self)
        let newValue = round(slider.doubleValue)
        let changed = newValue != value
        value = newValue
        if changed {
            onSizeChanged?(newValue)
        }
    }
}
