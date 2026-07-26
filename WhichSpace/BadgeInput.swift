import Cocoa

// MARK: - Badge Input View

final class BadgeInput: NSView {
    private let textField: NSTextField
    private let clearButton = NSButton()

    private let padding = 28.0
    private let fieldWidth = 40.0
    private let fieldHeight = 22.0
    private let clearButtonSize = 16.0

    var onCharacterChanged: ((String?) -> Void)?

    var currentCharacter: String? {
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
        textField.alignment = .center
        textField.placeholderString = BadgeTemplate.spaceToken
        textField.toolTip = Localization.tipBadgeInput
        textField.delegate = self
        textField.maximumNumberOfLines = 1
        textField.usesSingleLineMode = true
        addSubview(textField)
    }

    private func setupClearButton() {
        clearButton.image = NSImage(
            systemSymbolName: "xmark.circle.fill",
            accessibilityDescription: Localization.actionResetBadgeToDefault
        )
        clearButton.contentTintColor = .secondaryLabelColor
        clearButton.toolTip = Localization.tipClearBadge
        clearButton.isBordered = false
        clearButton.target = self
        clearButton.action = #selector(clearCharacter)
        clearButton.isHidden = true
        addSubview(clearButton)
    }

    @objc private func clearCharacter() {
        textField.stringValue = ""
        clearButton.isHidden = true
        onCharacterChanged?(nil)
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
            x: padding + fieldWidth + 4,
            y: (bounds.height - clearButtonSize) / 2,
            width: clearButtonSize,
            height: clearButtonSize
        )
    }
}

// MARK: - NSTextFieldDelegate

extension BadgeInput: NSTextFieldDelegate {
    func controlTextDidChange(_ obj: Notification) {
        guard let field = obj.object as? NSTextField else {
            return
        }

        // Limit to a single character (including multi-scalar emoji)
        var text = field.stringValue
        if !text.isEmpty {
            text = String(text.prefix(1))
            if field.stringValue != text {
                field.stringValue = text
            }
        }

        clearButton.isHidden = text.isEmpty
        onCharacterChanged?(text.isEmpty ? nil : text)
    }
}
