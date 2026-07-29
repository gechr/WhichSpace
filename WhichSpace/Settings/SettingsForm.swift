import SwiftUI

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
    private let content: Content

    init(_ title: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
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
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color(nsColor: .quaternarySystemFill))
            )
        }
    }
}

// MARK: - SettingsRow

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
    var indented = false
    @ViewBuilder var label: Label
    @ViewBuilder var control: Control

    var body: some View {
        HStack {
            Group {
                // Baseline alignment pins the icon to the title line rather
                // than floating it beside the title + subtitle block
                HStack(alignment: .firstTextBaseline, spacing: 5) {
                    if let icon {
                        Image(systemName: icon)
                            .foregroundStyle(disabled ? .tertiary : .secondary)
                            .frame(width: Layout.settingsRowIconWidth)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        label
                        if let subtitle {
                            Text(subtitle)
                                .font(.system(size: Layout.settingsRowSubtitleFontSize))
                                .foregroundStyle(disabled ? .tertiary : .secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                Spacer()
                // The mini switch does not visibly dim when disabled, so
                // fade the control explicitly
                control
                    .opacity(disabled ? 0.5 : 1)
            }
            .disabled(disabled)
        }
        .padding(.leading, indented ? Layout.settingsRowIndent : 0)
        .padding(.horizontal, Layout.settingsRowHorizontalPadding)
        .padding(.vertical, Layout.settingsRowVerticalPadding)
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
    var subtitle: String?

    var body: some View {
        SettingsRow(icon: icon, subtitle: subtitle, disabled: disabled, indented: indented) {
            Text(title)
                .foregroundStyle(disabled ? .tertiary : .primary)
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
    var valueFormatter: (Double) -> String = { String(format: "%.0f%%", $0) }

    var body: some View {
        SettingsRow(icon: icon, subtitle: subtitle, disabled: disabled) {
            Text(title)
                .foregroundStyle(disabled ? .tertiary : .primary)
        } control: {
            // The value reads as subtext beneath a fixed-width slider column,
            // so changing label widths never shove the row layout around and
            // sliders line up across rows
            VStack(spacing: 2) {
                slider
                    .labelsHidden()
                Text(valueFormatter(value.wrappedValue))
                    .font(.system(size: Layout.settingsSliderValueFontSize))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
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
    private var slider: some View {
        if let step {
            Slider(value: value, in: range, step: step) {
                Text(title)
            }
        } else {
            Slider(value: value, in: range) {
                Text(title)
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
