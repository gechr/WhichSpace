import AppKit

/// Status menu row that labels the current Space. Edits apply as typed;
/// Return closes, Escape undoes and closes, the clear button removes the
/// label.
@MainActor
final class SpaceLabelMenuField: NSView, NSSearchFieldDelegate {
    /// Exposed for tests
    let field = LabelSearchField()
    private var edited = false
    private var onChange: ((String) -> Void)?
    private var onRevert: (() -> Void)?

    override init(frame _: CGRect) {
        // The row is at least wide enough for the minimum character count
        // plus the text inset and clear button; the menu stretches it
        let font = NSFont.menuFont(ofSize: 0)
        let digits = String(repeating: "0", count: Layout.menuLabelFieldMinimumCharacters)
        let textWidth = (digits as NSString).size(withAttributes: [.font: font]).width
        let fieldWidth = ceil(textWidth + Layout.menuLabelFieldTextInset + Layout.menuLabelFieldClearButtonWidth)
        super.init(frame: CGRect(
            x: 0,
            y: 0,
            width: fieldWidth + Layout.menuLabelFieldInset * 2,
            height: Layout.menuLabelFieldRowHeight
        ))
        field.font = font
        field.placeholderString = Localization.menuLabel
        // A search field for the rounded shape and clear button
        field.sendsWholeSearchString = true
        field.sendsSearchStringImmediately = false
        field.cell?.sendsActionOnEndEditing = false
        field.toolTip = Localization.tipLabelInput
        field.delegate = self
        // The clear button fires the action without a text-change callback
        field.target = self
        field.action = #selector(fieldAction)
        addSubview(field)
        field.frame = CGRect(
            x: Layout.menuLabelFieldInset,
            y: (bounds.height - Layout.menuLabelFieldHeight) / 2,
            width: fieldWidth,
            height: Layout.menuLabelFieldHeight
        )
        autoresizingMask = [.width]
        field.autoresizingMask = [.width]
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        nil
    }

    var text: String {
        field.stringValue
    }

    /// Fills the row for one presentation: the label in effect, the label
    /// the Space falls back to as the placeholder, the edit callback, and
    /// the revert callback Escape uses after an edit. Disabled before the
    /// first snapshot names a Space.
    func configure(
        currentLabel: String?,
        placeholder: String = Localization.menuLabel,
        isEnabled: Bool = true,
        onChange: @escaping (String) -> Void,
        onRevert: @escaping () -> Void
    ) {
        field.stringValue = isEnabled ? currentLabel ?? "" : ""
        field.placeholderString = placeholder
        field.isEnabled = isEnabled
        edited = false
        self.onChange = onChange
        self.onRevert = onRevert
    }

    // MARK: - Focus

    /// The menu window exists only while tracking, so focus is taken here;
    /// otherwise typing drives the menu's type-to-select.
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard let window else {
            return
        }
        DispatchQueue.main.async { [weak self, weak window] in
            guard let self, let window, self.window === window else {
                return
            }
            window.makeFirstResponder(field)
        }
    }

    // MARK: - NSTextFieldDelegate

    func controlTextDidChange(_: Notification) {
        // Marked text is mid-composition; replacing it would end the composition
        if let editor = field.currentEditor() as? NSTextView, editor.hasMarkedText() {
            return
        }
        let clamped = LabelTemplate.truncate(field.stringValue)
        if clamped != field.stringValue {
            field.stringValue = clamped
        }
        edited = true
        onChange?(clamped)
    }

    func control(_: NSControl, textView _: NSTextView, doCommandBy selector: Selector) -> Bool {
        switch selector {
        case #selector(NSResponder.insertNewline(_:)):
            enclosingMenuItem?.menu?.cancelTracking()
            return true
        case #selector(NSResponder.cancelOperation(_:)):
            if edited {
                onRevert?()
            }
            enclosingMenuItem?.menu?.cancelTracking()
            return true
        default:
            return false
        }
    }

    // MARK: - Private

    @objc private func fieldAction() {
        edited = true
        onChange?(field.stringValue)
    }
}

// MARK: - LabelSearchField

/// A search field without the magnifier; the text inset it provided is
/// restored.
final class LabelSearchField: NSSearchField {
    override init(frame: CGRect) {
        super.init(frame: frame)
        (cell as? NSSearchFieldCell)?.searchButtonCell = nil
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        nil
    }

    override var searchButtonBounds: CGRect {
        .zero
    }

    override var searchTextBounds: CGRect {
        var textRect = super.searchTextBounds
        let inset = Layout.menuLabelFieldTextInset
        textRect.origin.x += inset
        textRect.size.width -= inset
        return textRect
    }
}
