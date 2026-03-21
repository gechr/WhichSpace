import Cocoa

// MARK: - Label Input View

final class LabelInput: NSView {
    private let textField: NSTextField

    private let padding = 28.0
    private let fieldWidth = 80.0
    private let fieldHeight = 22.0

    let maxLength = 6
    var onLabelChanged: ((String?) -> Void)?

    var currentLabel: String? {
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
        textField.alignment = .left
        textField.placeholderString = ""
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

extension LabelInput: NSTextFieldDelegate {
    func controlTextDidChange(_ obj: Notification) {
        guard let field = obj.object as? NSTextField else {
            return
        }

        var text = field.stringValue
        if text.count > maxLength {
            text = String(text.prefix(maxLength))
            field.stringValue = text
        }

        onLabelChanged?(text.isEmpty ? nil : text)
    }
}
