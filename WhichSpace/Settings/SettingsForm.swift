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

/// Commits a value field being typed in, by dropping the focus it holds on to
/// until something else takes it.
@MainActor
func endFieldEditing() {
    NSApp.keyWindow?.makeFirstResponder(nil)
}

extension View {
    /// Paints the deep-link highlight behind a control hosted outside a row
    /// or section, and registers its scroll target.
    func settingsHighlight(_ anchor: SettingsAnchor) -> some View {
        modifier(SettingsRowHighlight(anchor: anchor))
    }

    /// Commits a value field being typed in when the click lands off it.
    func endsFieldEditingOnTap() -> some View {
        contentShape(Rectangle())
            .onTapGesture {
                endFieldEditing()
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
///
/// The stack sits in a scroll view capped at a share of the screen height,
/// so a pane taller than that scrolls instead of running the window off the
/// screen. A pane that fits reports its content height as the scroll view's
/// ideal, keeping the window sized to the pane exactly as before.
///
/// A `header` pins above the scroll view - the permission banner stays put
/// while the sections scroll beneath it.
struct SettingsForm<Header: View, Content: View>: View {
    private let header: Header
    private let content: Content
    /// Distinguishes a real pinned header from the placeholder, so headerless
    /// forms keep their top padding
    private let hasHeader: Bool

    @Environment(SettingsHighlighter.self) private var highlighter: SettingsHighlighter?

    init(@ViewBuilder content: () -> Content) where Header == EmptyView {
        header = EmptyView()
        self.content = content()
        hasHeader = false
    }

    init(@ViewBuilder header: () -> Header, @ViewBuilder content: () -> Content) {
        self.header = header()
        self.content = content()
        hasHeader = true
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Layout.settingsSectionSpacing) {
            if hasHeader {
                header
                    .padding([.top, .horizontal], Layout.settingsPanePadding)
                    .frame(width: Layout.settingsPaneContentWidth)
            }
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: Layout.settingsSectionSpacing) {
                        content
                    }
                    .padding(
                        hasHeader ? [.horizontal, .bottom] : .all,
                        Layout.settingsPanePadding
                    )
                    .frame(width: Layout.settingsPaneContentWidth)
                }
                .frame(maxHeight: maxPaneHeight)
                // A deep link can point at a row the cap has scrolled out of
                // view, so bring the anchor in rather than only highlighting it
                .onAppear {
                    scroll(proxy, to: highlighter?.anchor)
                }
                .onChange(of: highlighter?.anchor) { _, anchor in
                    scroll(proxy, to: anchor)
                }
            }
        }
        .toggleStyle(.switch)
        .font(.system(size: Layout.settingsRowFontSize))
        .endsFieldEditingOnTap()
    }

    /// The tallest a pane may grow before it scrolls: a fixed share of the
    /// screen height.
    private var maxPaneHeight: Double {
        guard let screen = NSScreen.main else {
            return Layout.settingsPaneMaxHeightFallback
        }
        return screen.frame.height * Layout.settingsPaneMaxHeightRatio
    }

    private func scroll(_ proxy: ScrollViewProxy, to anchor: SettingsAnchor?) {
        guard let anchor else {
            return
        }
        withAnimation {
            proxy.scrollTo(anchor.target, anchor: .center)
        }
    }
}

// MARK: - SettingsSection

/// One grouped card: an optional bold header above a rounded, slightly
/// lighter background containing rows.
struct SettingsSection<Content: View>: View {
    private let title: String?
    private let anchor: SettingsAnchor?
    private let emphasized: Bool
    private let tint: Color?
    private let content: Content

    /// `anchor` identifies sections whose content is a grid rather than rows,
    /// so a deep link can point at the section as a whole. `emphasized` marks
    /// a card that sits outside the scrolling stack, which needs a stronger
    /// fill and an edge to read as separate from the cards scrolling past it.
    init(
        _ title: String? = nil,
        anchor: SettingsAnchor? = nil,
        emphasized: Bool = false,
        tint: Color? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.anchor = anchor
        self.emphasized = emphasized
        self.tint = tint
        self.content = content()
    }

    /// An emphasized card carries a border of its own, so its fill only has to
    /// lift it a little. Half the system fill lands it at 0.024 alpha against
    /// the regular cards' 0.027, leaving the icon it carries the brightest
    /// thing on it.
    private var fill: Color {
        if let tint {
            return tint.opacity(0.12)
        }
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
            // The highlight sits over the card's fill and under its content,
            // keeping a lit grid legible
            .background {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(fill)
                    SettingsHighlightFill(anchor: anchor, cornerRadius: 10)
                }
            }
            // A hairline separator is too faint to carry the card on its own,
            // so the edge is drawn in a label colour at a point and a half
            .overlay {
                if let tint {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(tint.opacity(0.35), lineWidth: 1.5)
                } else if emphasized {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(Color(nsColor: .tertiaryLabelColor), lineWidth: 1.5)
                }
            }
        }
        .settingsScrollAnchor(anchor)
    }
}

// MARK: - SettingsHighlightFill

/// Paints the deep-link highlight: two pulses, a hold, then a fade once the
/// highlighter lets go. The pulses announce a row on a pane that came up
/// already scrolled to it, where a fill that simply appeared would read as
/// part of the pane.
private struct SettingsHighlightFill: View {
    /// Top of each pulse, and the tint they settle onto
    private static let peakOpacity = 0.4
    private static let holdOpacity = 0.15
    /// One up or down swing of a pulse
    private static let swing = 0.25
    private static let fade = 1.0

    /// In, out, in, out, one swing per beat, resting on the hold
    private static let opening = [peakOpacity, holdOpacity, peakOpacity, holdOpacity]

    let anchor: SettingsAnchor?
    let cornerRadius: Double
    /// Insets the fill from the card edge, so a lit row does not read as a
    /// second card stacked on the section
    var inset = 0.0

    @Environment(SettingsHighlighter.self) private var highlighter: SettingsHighlighter?

    @State private var opacity = 0.0
    @State private var beats: Task<Void, Never>?

    private var isHighlighted: Bool {
        highlighter?.isEmphasizing(anchor) == true
    }

    /// A fresh value for every link that lands here, so a repeat link replays
    /// the pulse rather than leaving the row already lit
    private var lit: Int? {
        isHighlighted ? highlighter?.pointCount : nil
    }

    var body: some View {
        // Opacity rather than the fill's own alpha: a shape's fill colour
        // snaps between values where opacity interpolates
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(Color.accentColor)
            .opacity(opacity)
            .padding(.horizontal, inset)
            // A row can come up already lit, so `initial` pulses that case too
            .onChange(of: lit, initial: true) { _, lit in
                if lit != nil {
                    pulse()
                } else if opacity > 0 {
                    beats?.cancel()
                    withAnimation(.easeOut(duration: Self.fade)) {
                        opacity = 0
                    }
                }
            }
    }

    /// Plays the beats in turn. Awaiting each one is what keeps them: several
    /// animations of one value in a single pass leave only the last.
    private func pulse() {
        // A repeat link restarts the rhythm from the top rather than picking
        // up wherever the run it interrupts had reached
        beats?.cancel()
        opacity = 0
        // A row built already lit renders its first beat at the final value,
        // so the rhythm starts a turn later, on screen and unlit
        beats = Task { @MainActor in
            for level in Self.opening {
                // A link landing elsewhere mid-pulse leaves this row fading
                // rather than finishing
                guard isHighlighted, !Task.isCancelled else {
                    return
                }
                withAnimation(.easeIn(duration: Self.swing)) {
                    opacity = level
                }
                try? await Task.sleep(for: .seconds(Self.swing))
            }
        }
    }
}

// MARK: - SettingsRow

/// Paints the deep-link highlight on a card row and registers its scroll
/// target.
private struct SettingsRowHighlight: ViewModifier {
    let anchor: SettingsAnchor?

    func body(content: Content) -> some View {
        content
            .background {
                SettingsHighlightFill(anchor: anchor, cornerRadius: 6, inset: 4)
            }
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
    /// Overrides the switch accent - nil keeps the standard tint
    var tint: Color?
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
                .foregroundStyle(titleStyle)
        } control: {
            Toggle(title, isOn: isOn)
                .labelsHidden()
                .controlSize(.mini)
                .tint(tint?.opacity(0.5))
        }
        // The row's hierarchical styles resolve against this, so a tinted
        // row renders in shades of the tint rather than gray
        .foregroundStyle(tint.map(AnyShapeStyle.init) ?? AnyShapeStyle(.foreground))
    }

    /// A tinted row dims its title to the subtitle's shade - the tint itself
    /// carries the warning.
    private var titleStyle: AnyShapeStyle {
        if disabled || dimmed {
            AnyShapeStyle(.tertiary)
        } else if tint != nil {
            AnyShapeStyle(.secondary)
        } else {
            AnyShapeStyle(.primary)
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
    var dimmed = false
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
        SettingsRow(icon: icon, subtitle: subtitle, disabled: disabled, dimmed: dimmed, anchor: anchor) {
            Text(title)
                .foregroundStyle(disabled || dimmed ? .tertiary : .primary)
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
                // The button does not take focus, so a field being typed in
                // keeps it and would commit over the reset on its way out
                endFieldEditing()
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
            .frame(width: Layout.settingsSliderValueWidth)
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
/// An AppKit field rather than a SwiftUI one: it draws the standard editable
/// bezel, keeps its text still when the field editor takes over, and leaves
/// clicking, selecting, and Return and Escape to the platform.
private struct SliderValueField: NSViewRepresentable {
    let value: Binding<Double>
    let range: ClosedRange<Double>
    let formatter: (Double) -> String
    let parse: (String) -> Double?

    func makeNSView(context: Context) -> NSTextField {
        let field = NSTextField(string: formatter(value.wrappedValue))
        field.delegate = context.coordinator
        field.alignment = .center
        field.controlSize = .small
        field.font = .monospacedDigitSystemFont(
            ofSize: Layout.settingsSliderValueFontSize,
            weight: .regular
        )
        field.bezelStyle = .roundedBezel
        return field
    }

    func updateNSView(_ field: NSTextField, context: Context) {
        context.coordinator.field = self
        // A drag moves the setting underneath the field, which shows what is
        // being typed into it; leave that alone until the editor goes away
        guard field.currentEditor() == nil else {
            return
        }
        field.stringValue = formatter(value.wrappedValue)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(field: self)
    }

    /// Applies the typed number, or puts the current value back when it does
    /// not read as one. Rounding matches the slider, which moves the setting
    /// in whole units.
    fileprivate func commit(_ field: NSTextField) {
        defer {
            field.stringValue = formatter(value.wrappedValue)
        }
        guard let parsed = parse(field.stringValue) else {
            return
        }
        value.wrappedValue = parsed.rounded().clamped(to: range)
    }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        /// Reassigned on every update, so a commit reads the bindings the
        /// pane holds now rather than the ones it was built with
        var field: SliderValueField

        init(field: SliderValueField) {
            self.field = field
        }

        /// Covers Return, Tab, and the focus leaving for any other reason
        func controlTextDidEndEditing(_ notification: Notification) {
            guard let control = notification.object as? NSTextField else {
                return
            }
            field.commit(control)
        }

        /// Escape puts the current value back rather than committing it
        func control(
            _ control: NSControl,
            textView _: NSTextView,
            doCommandBy selector: Selector
        ) -> Bool {
            guard selector == #selector(NSResponder.cancelOperation(_:)) else {
                return false
            }
            control.stringValue = field.formatter(field.value.wrappedValue)
            control.window?.makeFirstResponder(nil)
            return true
        }
    }
}

/// Shown until accessibility permission is granted; switching cannot work
/// without it, so every pane offering a switching surface leads with it.
/// Never granted, the button requests permission and registers a grant watch
/// so the banner clears live. Revoked mid-session, it deep-links System
/// Settings instead: the request flow starts with a `tccutil reset`, which
/// must stay unreachable from the probe-driven state.
struct AccessibilityBannerSection: View {
    let model: SettingsModel

    var body: some View {
        SettingsSection(tint: Color(nsColor: .systemRed)) {
            SettingsRow(anchor: .accessibility) {
                HStack(spacing: 10) {
                    Image(systemName: "lock.shield.fill")
                        .font(.system(size: 22))
                        .foregroundStyle(.red)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(Localization.alertAccessibilityRequired)
                            .fontWeight(.semibold)
                        Text(Localization.bannerAccessibilityDetail)
                            .foregroundStyle(.secondary)
                    }
                }
            } control: {
                Button(Localization.actionOpenSystemSettings) {
                    if model.accessibilityRevoked {
                        Accessibility.recoverFromRevocation()
                    } else {
                        model.requestAccessibility()
                    }
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

// MARK: - Window Fitting

/// Sizes `window` around the pane it shows.
///
/// Grows or shrinks from the top-left corner, the same corner a tab switch
/// sizes around, so the list the user is looking at stays put while the editor
/// beside it moves.
@MainActor
func fitSettingsWindow(_ window: NSWindow, to pane: NSView) {
    let content = CGRect(origin: .zero, size: pane.fittingSize)
    let size = window.frameRect(forContentRect: content).size
    guard size.width > 0, size.height > 0 else {
        return
    }
    var frame = window.frame
    guard abs(frame.width - size.width) > 0.5 || abs(frame.height - size.height) > 0.5 else {
        return
    }
    frame.origin.y += frame.height - size.height
    frame.size = size
    window.setFrame(frame, display: true)
}

/// Resizes the settings window around its pane whenever `measured` changes.
///
/// The window is sized to the pane it shows only while a tab is activated, so
/// a pane that grows once it is on screen - the Space list widening as a label
/// is typed - spills out of the window it was measured into, and only looks
/// right again after a tab switch.
private struct SettingsWindowFitter: NSViewRepresentable {
    /// Any value that moves when the pane's ideal size does
    let measured: CGSize

    func makeNSView(context _: Context) -> NSView {
        NSView()
    }

    func updateNSView(_ view: NSView, context _: Context) {
        // The pane reports its new fitting size only once SwiftUI has
        // finished the update that changed it
        Task { @MainActor in
            fit(view)
        }
    }

    /// A snap resize during a tab crossfade interrupts the transition and can
    /// strand the incoming pane as a stale half-faded snapshot, so the fit
    /// waits for the fade to drain first.
    private func fit(_ view: NSView, retriesLeft: Int = 3) {
        guard let window = view.window, let pane = paneView(containing: view) else {
            return
        }
        if retriesLeft > 0, hasRunningPaneAnimation(in: window) {
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(350))
                fit(view, retriesLeft: retriesLeft - 1)
            }
            return
        }
        fitSettingsWindow(window, to: pane)
    }

    /// Whether a tab crossfade is animating a pane root view.
    private func hasRunningPaneAnimation(in window: NSWindow) -> Bool {
        guard let contentView = window.contentView else {
            return false
        }
        if contentView.layer?.animationKeys()?.isEmpty == false {
            return true
        }
        return contentView.subviews.contains { $0.layer?.animationKeys()?.isEmpty == false }
    }

    /// The pane's own root view - the content view's child this view descends
    /// from - measured rather than the content view so a pane fading out of a
    /// tab transition cannot widen the result.
    private func paneView(containing view: NSView) -> NSView? {
        guard let contentView = view.window?.contentView else {
            return nil
        }
        var candidate = view
        while let parent = candidate.superview, parent != contentView {
            candidate = parent
        }
        return candidate.superview == contentView ? candidate : nil
    }
}

extension View {
    /// Keeps the settings window fitted to this pane as its ideal size
    /// changes, with `measured` naming the values that change it.
    func fitsSettingsWindow(measuring measured: CGSize) -> some View {
        background(SettingsWindowFitter(measured: measured))
    }
}
