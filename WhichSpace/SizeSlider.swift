import Cocoa

// MARK: - Size Row View

final class SizeSlider: NSView {
    private let maxLabel: NSTextField
    private let minLabel: NSTextField
    private let slider: NSSlider
    private let stepper: NSStepper
    private let valueLabel: NSTextField

    private let controlHeight = 20.0
    private let labelHeight = 12.0
    private let padding = 16.0
    private let sliderWidth = 140.0
    private let stepperWidth = 20.0
    private let valueLabelHeight = 20.0

    var onSizeChanged: ((Double) -> Void)?

    var currentSize: Double {
        get { slider.doubleValue }
        set {
            slider.doubleValue = newValue
            stepper.doubleValue = newValue
            valueLabel.stringValue = String(format: "%.0f%%", newValue)
        }
    }

    init(initialSize: Double, range: ClosedRange<Double>) {
        slider = NSSlider(
            value: initialSize,
            minValue: range.lowerBound,
            maxValue: range.upperBound,
            target: nil,
            action: nil
        )
        stepper = NSStepper()
        minLabel = NSTextField(labelWithString: String(format: "%.0f%%", range.lowerBound))
        maxLabel = NSTextField(labelWithString: String(format: "%.0f%%", range.upperBound))
        valueLabel = NSTextField(labelWithString: String(format: "%.0f%%", initialSize))

        super.init(frame: .zero)

        setupSlider(range: range)
        setupStepper(range: range)
        setupLabels()
        currentSize = initialSize
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Setup

    private func setupSlider(range: ClosedRange<Double>) {
        slider.minValue = range.lowerBound
        slider.maxValue = range.upperBound
        slider.target = self
        slider.action = #selector(sliderChanged)
        slider.isContinuous = true
        addSubview(slider)
    }

    private func setupStepper(range: ClosedRange<Double>) {
        stepper.minValue = range.lowerBound
        stepper.maxValue = range.upperBound
        stepper.increment = 1
        stepper.valueWraps = false
        stepper.target = self
        stepper.action = #selector(stepperChanged)
        addSubview(stepper)
    }

    private func setupLabels() {
        let smallFont = NSFont.monospacedDigitSystemFont(ofSize: 9, weight: .regular)
        let smallColor = NSColor.secondaryLabelColor

        minLabel.font = smallFont
        minLabel.textColor = smallColor
        minLabel.alignment = .left
        addSubview(minLabel)

        maxLabel.font = smallFont
        maxLabel.textColor = smallColor
        maxLabel.alignment = .right
        addSubview(maxLabel)

        valueLabel.font = NSFont.monospacedDigitSystemFont(ofSize: 13, weight: .bold)
        valueLabel.textColor = .labelColor
        valueLabel.alignment = .center
        addSubview(valueLabel)
    }

    // MARK: - Layout

    override var intrinsicContentSize: CGSize {
        let width = padding + sliderWidth + 8 + stepperWidth + padding
        return CGSize(width: width, height: controlHeight + labelHeight + valueLabelHeight + 12)
    }

    override func layout() {
        super.layout()

        let bottomLabelY = 2.0
        let yControls = bottomLabelY + labelHeight + 2
        let topLabelY = yControls + controlHeight + 2

        slider.frame = CGRect(x: padding, y: yControls, width: sliderWidth, height: controlHeight)
        stepper.frame = CGRect(x: padding + sliderWidth + 8, y: yControls, width: stepperWidth, height: controlHeight)

        let labelWidth = 32.0
        minLabel.frame = CGRect(x: padding, y: bottomLabelY, width: labelWidth, height: labelHeight)
        maxLabel.frame = CGRect(
            x: padding + sliderWidth - labelWidth,
            y: bottomLabelY,
            width: labelWidth,
            height: labelHeight
        )
        valueLabel.frame = CGRect(x: padding, y: topLabelY, width: sliderWidth, height: valueLabelHeight)
    }

    // MARK: - Mouse Events

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        let location = convert(event.locationInWindow, from: nil)

        if stepper.frame.contains(location) {
            let stepperMidY = stepper.frame.midY
            if location.y > stepperMidY {
                stepper.doubleValue += stepper.increment
            } else {
                stepper.doubleValue -= stepper.increment
            }
            stepperChanged()
            return
        }

        super.mouseDown(with: event)
    }

    // MARK: - Keyboard Events

    override var acceptsFirstResponder: Bool { true }

    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 123, 125: // Left arrow, Down arrow
            stepper.doubleValue = max(stepper.minValue, stepper.doubleValue - stepper.increment)
            stepperChanged()
        case 124, 126: // Right arrow, Up arrow
            stepper.doubleValue = min(stepper.maxValue, stepper.doubleValue + stepper.increment)
            stepperChanged()
        default:
            super.keyDown(with: event)
        }
    }

    // MARK: - Scroll Events

    override func scrollWheel(with event: NSEvent) {
        // Positive deltaY = scroll up = increase value
        // Negative deltaY = scroll down = decrease value
        if event.deltaY > 0 {
            stepper.doubleValue = min(stepper.maxValue, stepper.doubleValue + stepper.increment)
            stepperChanged()
        } else if event.deltaY < 0 {
            stepper.doubleValue = max(stepper.minValue, stepper.doubleValue - stepper.increment)
            stepperChanged()
        }
    }

    // MARK: - Actions

    @objc private func sliderChanged() {
        let value = round(slider.doubleValue)
        slider.doubleValue = value
        stepper.doubleValue = value
        valueLabel.stringValue = String(format: "%.0f%%", value)
        onSizeChanged?(value)
    }

    @objc private func stepperChanged() {
        let value = stepper.doubleValue
        slider.doubleValue = value
        valueLabel.stringValue = String(format: "%.0f%%", value)
        onSizeChanged?(value)
    }
}
