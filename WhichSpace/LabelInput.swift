import Cocoa

// MARK: - Label Input View

final class LabelInput: NSView {
    private let textField: NSTextField
    private let clearButton = NSButton()

    private let padding = 28.0
    private let fieldWidth = 180.0
    private let fieldHeight = 22.0
    private let clearButtonSize = 16.0

    var onLabelChanged: ((String?) -> Void)?

    var currentLabel: String? {
        get {
            let value = textField.stringValue
            return value.isEmpty ? nil : value
        }
        set {
            textField.stringValue = newValue ?? ""
            clearButton.isHidden = newValue?.isEmpty != false
        }
    }

    init() {
        textField = NSTextField()

        super.init(frame: .zero)

        setupTextField()
        setupClearButton()
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Setup

    private func setupTextField() {
        textField.font = NSFont.boldSystemFont(ofSize: Layout.menuFontSize)
        textField.alignment = .left
        textField.placeholderString = "{number}"
        textField.toolTip = Localization.tipLabelInput
        textField.delegate = self
        textField.maximumNumberOfLines = 1
        textField.usesSingleLineMode = true
        textField.cell?.isScrollable = true
        textField.cell?.wraps = false
        addSubview(textField)
    }

    private func setupClearButton() {
        clearButton.image = NSImage(
            systemSymbolName: "xmark.circle.fill",
            accessibilityDescription: Localization.actionResetLabelToDefault
        )
        clearButton.contentTintColor = .secondaryLabelColor
        clearButton.isBordered = false
        clearButton.target = self
        clearButton.action = #selector(clearLabel)
        clearButton.isHidden = true
        addSubview(clearButton)
    }

    @objc private func clearLabel() {
        textField.stringValue = ""
        clearButton.isHidden = true
        onLabelChanged?(nil)
        window?.makeFirstResponder(textField)
    }

    // MARK: - Focus

    override var acceptsFirstResponder: Bool {
        true
    }

    override func mouseDown(with _: NSEvent) {
        window?.makeFirstResponder(textField)
    }

    // MARK: - Layout

    override var intrinsicContentSize: CGSize {
        CGSize(width: padding + fieldWidth + padding, height: fieldHeight + 12)
    }

    override func layout() {
        super.layout()

        let yCenter = (bounds.height - fieldHeight) / 2
        textField.frame = CGRect(x: padding, y: yCenter, width: fieldWidth, height: fieldHeight)
        clearButton.frame = CGRect(
            x: padding + fieldWidth - clearButtonSize - 4,
            y: (bounds.height - clearButtonSize) / 2,
            width: clearButtonSize,
            height: clearButtonSize
        )
    }
}

// MARK: - NSTextFieldDelegate

extension LabelInput: NSTextFieldDelegate {
    func controlTextDidChange(_ obj: Notification) {
        guard let field = obj.object as? NSTextField else {
            return
        }

        var text = field.stringValue
        if LabelTemplate.contentLength(text) > LabelTemplate.maxContentLength {
            text = LabelTemplate.truncate(text)
            field.stringValue = text
        }

        clearButton.isHidden = text.isEmpty
        onLabelChanged?(text.isEmpty ? nil : text)
    }
}
