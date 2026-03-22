import Cocoa

// MARK: - Badge Input View

final class BadgeInput: NSView {
    private let textField: NSTextField

    private let padding = 28.0
    private let fieldWidth = 40.0
    private let fieldHeight = 22.0

    var onCharacterChanged: ((String?) -> Void)?

    var currentCharacter: String? {
        get {
            let value = textField.stringValue
            return value.isEmpty ? nil : value
        }
        set {
            textField.stringValue = newValue ?? ""
        }
    }

    init() {
        textField = NSTextField()

        super.init(frame: .zero)

        setupTextField()
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Setup

    private func setupTextField() {
        textField.font = NSFont.boldSystemFont(ofSize: Layout.menuFontSize)
        textField.alignment = .center
        textField.placeholderString = "#"
        textField.delegate = self
        textField.maximumNumberOfLines = 1
        textField.usesSingleLineMode = true
        addSubview(textField)
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

        onCharacterChanged?(text.isEmpty ? nil : text)
    }
}
