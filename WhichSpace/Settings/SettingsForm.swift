import AppKit
import SwiftUI

private extension View {
    /// Registers a scroll target for anchored rows and sections, so a
    /// `ScrollViewReader` can bring a deep-linked setting into view.
    @ViewBuilder
    func settingsScrollAnchor(_ anchor: SettingsAnchor?) -> some View {
        if let anchor {
            id(anchor)
        } else {
            self
        }
    }
}

// MARK: - SettingsForm

/// Vertical stack of grouped-card sections for a settings pane.
///
/// SwiftUI's grouped `Form` is list-backed and reports no intrinsic height,
/// which forces a hardcoded pane height and leaves blank space below short
/// panes. This VStack-based recreation of the same visual style sizes to its
/// content, so the window fits each pane exactly.
struct SettingsForm<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: Layout.settingsSectionSpacing) {
            content
        }
        .padding(Layout.settingsPanePadding)
        .frame(width: Layout.settingsPaneContentWidth)
        .toggleStyle(.switch)
        .font(.system(size: Layout.settingsRowFontSize))
    }
}

// MARK: - SettingsSection

/// One grouped card: an optional bold header above a rounded, slightly
/// lighter background containing rows.
struct SettingsSection<Content: View>: View {
    private let title: String?
    private let anchor: SettingsAnchor?
    private let emphasized: Bool
    private let content: Content

    @Environment(SettingsHighlighter.self) private var highlighter: SettingsHighlighter?

    /// `anchor` identifies sections whose content is a grid rather than rows,
    /// so a deep link can point at the section as a whole. `emphasized` marks
    /// a card that sits outside the scrolling stack, which needs a stronger
    /// fill and an edge to read as separate from the cards scrolling past it.
    init(
        _ title: String? = nil,
        anchor: SettingsAnchor? = nil,
        emphasized: Bool = false,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.anchor = anchor
        self.emphasized = emphasized
        self.content = content()
    }

    private var isHighlighted: Bool {
        highlighter?.isEmphasizing(anchor) == true
    }

    /// An emphasized card carries a border of its own, so its fill only has to
    /// lift it a little. Half the system fill lands it at 0.024 alpha against
    /// the regular cards' 0.027, leaving the icon it carries the brightest
    /// thing on it.
    private var fill: Color {
        let base = Color(nsColor: emphasized ? .tertiarySystemFill : .quaternarySystemFill)
        return emphasized ? base.opacity(0.5) : base
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let title {
                Text(title)
                    .font(.headline)
                    .padding(.leading, 4)
            }
            VStack(alignment: .leading, spacing: 0) {
                content
            }
            // Tinting the card itself, rather than layering a second shape
            // over it, keeps the grid content legible while lit
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(
                        isHighlighted
                            ? AnyShapeStyle(Color.accentColor.opacity(0.25))
                            : AnyShapeStyle(fill)
                    )
            )
            // A hairline separator is too faint to carry the card on its own,
            // so the edge is drawn in a label colour at a point and a half
            .overlay {
                if emphasized {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(Color(nsColor: .tertiaryLabelColor), lineWidth: 1.5)
                }
            }
            .animation(.easeInOut(duration: 0.25), value: isHighlighted)
        }
        .settingsScrollAnchor(anchor)
    }
}

// MARK: - SettingsRow

/// Paints the deep-link highlight on a card row and registers its scroll
/// target. The fill is inset from the card edge so the highlight reads as one
/// row rather than a second card stacked on the section.
private struct SettingsRowHighlight: ViewModifier {
    let anchor: SettingsAnchor?

    @Environment(SettingsHighlighter.self) private var highlighter: SettingsHighlighter?

    private var isHighlighted: Bool {
        highlighter?.isEmphasizing(anchor) == true
    }

    func body(content: Content) -> some View {
        content
            .background {
                if isHighlighted {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color.accentColor.opacity(0.25))
                        .padding(.horizontal, 4)
                }
            }
            .animation(.easeInOut(duration: 0.25), value: isHighlighted)
            .settingsScrollAnchor(anchor)
    }
}

/// A single card row: an optional SF Symbol (mirroring the status menu's
/// icon for the same setting), the label with an optional always-visible
/// subtitle, and the control pinned to the trailing edge.
///
/// Rows take `disabled` as a parameter rather than the `.disabled` modifier
/// so the icon, label, and subtitle can dim to match the control.
struct SettingsRow<Label: View, Control: View>: View {
    var icon: String?
    var subtitle: String?
    var disabled = false
    /// Fades the row like a disabled one while leaving it live. Marks a
    /// setting that still applies but has next to nothing to act on in the
    /// current arrangement.
    var dimmed = false
    var indented = false
    /// Identifies the row to `whichspace://settings?highlight=` deep links
    var anchor: SettingsAnchor?
    @ViewBuilder var label: Label
    @ViewBuilder var control: Control

    private var faded: Bool {
        disabled || dimmed
    }

    var body: some View {
        HStack {
            Group {
                // Baseline alignment pins the icon to the title line rather
                // than floating it beside the title + subtitle block
                HStack(alignment: .firstTextBaseline, spacing: 5) {
                    if let icon {
                        Image(systemName: icon)
                            .foregroundStyle(faded ? .tertiary : .secondary)
                            .frame(width: Layout.settingsRowIconWidth)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        label
                        if let subtitle {
                            Text(subtitle)
                                .font(.system(size: Layout.settingsRowSubtitleFontSize))
                                .foregroundStyle(faded ? .tertiary : .secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                Spacer()
                // The mini switch does not visibly dim when disabled, so
                // fade the control explicitly
                control
                    .opacity(faded ? 0.5 : 1)
            }
            .disabled(disabled)
        }
        .padding(.leading, indented ? Layout.settingsRowIndent : 0)
        .padding(.horizontal, Layout.settingsRowHorizontalPadding)
        .padding(.vertical, Layout.settingsRowVerticalPadding)
        .modifier(SettingsRowHighlight(anchor: anchor))
    }
}

/// A card row holding only a control, centered across the row. Suits controls
/// whose own contents name the setting, leaving no label to lead with.
struct SettingsControlRow<Control: View>: View {
    /// Identifies the row to `whichspace://settings?highlight=` deep links
    var anchor: SettingsAnchor?
    @ViewBuilder var control: Control

    var body: some View {
        control
            .frame(maxWidth: .infinity)
            .padding(.horizontal, Layout.settingsRowHorizontalPadding)
            .padding(.vertical, Layout.settingsRowVerticalPadding)
            .modifier(SettingsRowHighlight(anchor: anchor))
    }
}

/// A toggle row with the switch at the trailing edge. `indented` marks a row
/// dependent on the toggle above it.
struct SettingsToggleRow: View {
    let title: String
    let isOn: Binding<Bool>
    var icon: String?
    var indented = false
    var disabled = false
    /// Fades the row while leaving the switch live, matching `SettingsRow`
    var dimmed = false
    var subtitle: String?
    var anchor: SettingsAnchor?

    var body: some View {
        SettingsRow(
            icon: icon,
            subtitle: subtitle,
            disabled: disabled,
            dimmed: dimmed,
            indented: indented,
            anchor: anchor
        ) {
            Text(title)
                .foregroundStyle(disabled || dimmed ? .tertiary : .primary)
        } control: {
            Toggle(title, isOn: isOn)
                .labelsHidden()
                .controlSize(.mini)
        }
    }
}

/// A slider row: label leading; slider, current value, and a reset-to-default
/// button trailing.
struct SettingsSliderRow: View {
    let title: String
    let value: Binding<Double>
    let range: ClosedRange<Double>
    var step: Double?
    let defaultValue: Double
    var icon: String?
    var disabled = false
    var subtitle: String?
    var anchor: SettingsAnchor?
    /// Reads a typed value back out of the formatted display, so the number
    /// can be set exactly rather than dragged for. Rows whose display has no
    /// numeric reading - the haptic detent names - pass nil and stay a label.
    var valueParser: ((String) -> Double?)? = Self.parseNumber
    var valueFormatter: (Double) -> String = { String(format: "%.0f%%", $0) }

    /// Takes the number out of a display string, discarding whatever unit the
    /// formatter added and accepting either decimal separator.
    nonisolated static func parseNumber(_ text: String) -> Double? {
        let number = text.filter { $0.isNumber || $0 == "." || $0 == "," || $0 == "-" }
        return Double(number.replacingOccurrences(of: ",", with: "."))
    }

    var body: some View {
        SettingsRow(icon: icon, subtitle: subtitle, disabled: disabled, anchor: anchor) {
            Text(title)
                .foregroundStyle(disabled ? .tertiary : .primary)
        } control: {
            // The value reads as subtext beneath a fixed-width slider column,
            // so changing label widths never shove the row layout around and
            // sliders line up across rows
            VStack(spacing: 2) {
                slider
                    .labelsHidden()
                valueDisplay
            }
            .frame(width: Layout.settingsSliderWidth)
            Button {
                value.wrappedValue = defaultValue
            } label: {
                Image(systemName: "arrow.counterclockwise")
            }
            .buttonStyle(.borderless)
            .disabled(value.wrappedValue == defaultValue)
            .help(Localization.buttonReset)
        }
    }

    @ViewBuilder
    private var valueDisplay: some View {
        if let valueParser {
            SliderValueField(
                value: value,
                range: range,
                formatter: valueFormatter,
                parse: valueParser
            )
        } else {
            Text(valueFormatter(value.wrappedValue))
                .font(.system(size: Layout.settingsSliderValueFontSize))
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var slider: some View {
        if let step {
            Slider(value: value, in: range, step: step) {
                Text(title)
            }
        } else if anchorsDefault {
            Slider(value: anchoredPosition, in: 0 ... 1) {
                Text(title)
            }
            // The slider carries a track position rather than the setting, so
            // spell the setting out for VoiceOver
            .accessibilityValue(Text(valueFormatter(value.wrappedValue)))
        } else {
            Slider(value: value, in: range) {
                Text(title)
            }
        }
    }

    /// A default sitting on either bound has no room for one of the two
    /// segments, and a stepped slider steps in units of the setting rather
    /// than of the track, so both keep the plain linear mapping.
    private var anchorsDefault: Bool {
        step == nil && defaultValue > range.lowerBound && defaultValue < range.upperBound
    }

    /// Maps the setting onto a 0-1 track that is linear either side of
    /// `defaultValue`, putting every row's default at the same position.
    /// The lower and upper segments cover different amounts of the range
    /// whenever the default is off-centre, so the slider moves the setting at
    /// a different rate in each half.
    private var anchoredPosition: Binding<Double> {
        let anchor = Layout.settingsSliderDefaultPosition
        return Binding {
            let current = value.wrappedValue.clamped(to: range)
            return if current <= defaultValue {
                anchor * (current - range.lowerBound) / (defaultValue - range.lowerBound)
            } else {
                anchor + (1 - anchor) * (current - defaultValue) / (range.upperBound - defaultValue)
            }
        } set: { position in
            let mapped = if position < anchor {
                range.lowerBound + (defaultValue - range.lowerBound) * position / anchor
            } else {
                defaultValue + (range.upperBound - defaultValue) * (position - anchor) / (1 - anchor)
            }
            // Whole units only: the row reads the value back as a rounded
            // percentage, and the reset button compares against the default
            // exactly, so a fraction of a percent would show as "100%" with
            // reset still enabled
            value.wrappedValue = mapped.rounded()
        }
    }
}

/// The slider's value, typed as well as dragged.
///
/// Reads as the same subtext label until it is clicked, so the row keeps its
/// look and the field is found by aiming at the number. Editing shows the
/// bare number, dropping the unit the formatter adds so the value can be
/// replaced outright rather than typed around.
private struct SliderValueField: View {
    let value: Binding<Double>
    let range: ClosedRange<Double>
    let formatter: (Double) -> String
    let parse: (String) -> Double?

    @State private var text = ""
    @FocusState private var isEditing: Bool

    var body: some View {
        TextField("", text: $text)
            .textFieldStyle(.plain)
            .multilineTextAlignment(.center)
            .font(.system(size: Layout.settingsSliderValueFontSize))
            .monospacedDigit()
            .foregroundStyle(.secondary)
            .focused($isEditing)
            .background(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(
                        isEditing
                            ? AnyShapeStyle(Color(nsColor: .quaternarySystemFill))
                            : AnyShapeStyle(.clear)
                    )
            )
            .onSubmit {
                commit()
            }
            .onChange(of: isEditing) { _, editing in
                if editing {
                    text = String(format: "%.0f", value.wrappedValue)
                } else {
                    commit()
                }
            }
            // A drag moves the setting underneath the field, which only shows
            // its own buffer; leave the buffer alone while it is being typed in
            .onChange(of: value.wrappedValue) { _, current in
                guard !isEditing else {
                    return
                }
                text = formatter(current)
            }
            .onAppear {
                text = formatter(value.wrappedValue)
            }
    }

    /// Applies the typed number, or puts the current value back when it does
    /// not read as one. Rounding matches the slider, which moves the setting
    /// in whole units.
    private func commit() {
        defer {
            text = formatter(value.wrappedValue)
        }
        guard let parsed = parse(text) else {
            return
        }
        value.wrappedValue = parsed.rounded().clamped(to: range)
    }
}

/// Shown until accessibility permission is granted; switching cannot work
/// without it, so every pane offering a switching surface leads with it.
/// The button both opens the Accessibility pane and registers a grant watch
/// so the banner clears live.
struct AccessibilityBannerSection: View {
    let model: SettingsModel

    var body: some View {
        SettingsSection {
            SettingsRow(anchor: .accessibility) {
                HStack(spacing: 10) {
                    Image(systemName: "lock.shield.fill")
                        .font(.system(size: 22))
                        .foregroundStyle(.orange)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(Localization.alertAccessibilityRequired)
                            .fontWeight(.semibold)
                        Text(Localization.bannerAccessibilityDetail)
                            .foregroundStyle(.secondary)
                    }
                }
            } control: {
                Button(Localization.actionOpenSystemSettings) {
                    model.requestAccessibility()
                    Accessibility.openSettingsPane()
                }
            }
        }
    }
}

/// Hairline between card rows: thinner and lower-contrast than a plain
/// `Divider`, matching the native grouped-form separator.
struct SettingsRowDivider: View {
    var body: some View {
        Divider()
            .opacity(0.5)
            .padding(.leading, Layout.settingsRowHorizontalPadding)
    }
}
