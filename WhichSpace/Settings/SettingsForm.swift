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

/// A single card row: label leading, control pinned to the trailing edge.
struct SettingsRow<Label: View, Control: View>: View {
    @ViewBuilder var label: Label
    @ViewBuilder var control: Control

    var body: some View {
        HStack {
            label
            Spacer()
            control
        }
        .padding(.horizontal, Layout.settingsRowHorizontalPadding)
        .padding(.vertical, Layout.settingsRowVerticalPadding)
    }
}

/// A toggle row with the switch at the trailing edge.
struct SettingsToggleRow: View {
    let title: String
    let isOn: Binding<Bool>

    var body: some View {
        SettingsRow {
            Text(title)
        } control: {
            Toggle(title, isOn: isOn)
                .labelsHidden()
                .controlSize(.mini)
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
