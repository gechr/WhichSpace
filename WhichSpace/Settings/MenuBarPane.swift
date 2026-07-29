import AppKit
import SwiftUI

/// The Menu Bar settings pane: icon sizing, which Spaces appear in the
/// status item, and per-display presentation. Container-agnostic - it knows
/// nothing about the window chrome hosting it.
struct MenuBarPane: View {
    let model: SettingsModel

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        SettingsForm {
            SettingsSection {
                SettingsSliderRow(
                    title: Localization.menuIcon,
                    value: model.binding(\.sizeScale),
                    range: Layout.sizeScaleRange,
                    defaultValue: Layout.defaultSizeScale,
                    icon: "arrow.up.left.and.down.right.and.arrow.up.right.and.down.left"
                )
                SettingsRowDivider()
                SettingsSliderRow(
                    title: Localization.menuPadding,
                    value: model.binding(\.paddingScale),
                    range: Layout.paddingScaleRange,
                    defaultValue: Layout.defaultPaddingScale,
                    icon: "arrow.left.and.right"
                )
            }
            visibilitySection
            displaySection
        }
    }

    /// Which Spaces get an icon. The dim/hide rows only apply when more than
    /// the current Space is shown, mirroring the status menu's gating.
    private var visibilitySection: some View {
        let dependentDisabled = !(model.value(\.showAllSpaces) || model.value(\.showAllDisplays))
        return SettingsSection {
            SettingsToggleRow(
                title: Localization.toggleShowAllSpaces,
                isOn: model.showAllSpacesBinding,
                icon: "square.grid.3x1.below.line.grid.1x2",
                subtitle: Localization.tipShowAllSpaces
            )
            SettingsRowDivider()
            SettingsToggleRow(
                title: Localization.toggleShowAllDisplays,
                isOn: model.showAllDisplaysBinding,
                icon: "display.2",
                subtitle: Localization.tipShowAllDisplays
            )
            SettingsRowDivider()
            SettingsToggleRow(
                title: Localization.toggleDimInactiveSpaces,
                isOn: model.binding(\.dimInactiveSpaces),
                icon: "aqi.low",
                indented: true,
                disabled: dependentDisabled,
                subtitle: Localization.tipDimInactiveSpaces
            )
            SettingsRowDivider()
            SettingsToggleRow(
                title: Localization.toggleHideEmptySpaces,
                isOn: model.binding(\.hideEmptySpaces),
                icon: "eye.slash.fill",
                indented: true,
                disabled: dependentDisabled,
                subtitle: Localization.tipHideEmptySpaces
            )
            SettingsRowDivider()
            SettingsToggleRow(
                title: Localization.toggleHideSingleSpace,
                isOn: model.binding(\.hideSingleSpace),
                icon: "eye.slash.fill",
                indented: true,
                disabled: dependentDisabled,
                subtitle: Localization.tipHideSingleSpace
            )
            SettingsRowDivider()
            SettingsToggleRow(
                title: Localization.toggleHideFullscreenApps,
                isOn: model.binding(\.hideFullscreenApps),
                icon: "eye.slash.fill",
                indented: true,
                disabled: dependentDisabled,
                subtitle: Localization.tipHideFullscreenApps
            )
            SettingsRowDivider()
            SettingsToggleRow(
                title: Localization.toggleUseFForFullscreenApps,
                isOn: fullscreenLetterBinding,
                icon: "f.square",
                // Irrelevant while fullscreen Spaces are hidden altogether
                disabled: model.value(\.hideFullscreenApps),
                subtitle: Localization.tipUseFForFullscreenApps
            )
        }
    }

    private var displaySection: some View {
        SettingsSection {
            SettingsToggleRow(
                title: Localization.toggleUniqueIconsPerDisplay,
                isOn: model.binding(\.uniqueIconsPerDisplay),
                icon: "theatermasks",
                subtitle: Localization.tipUniqueIconsPerDisplay
            )
            SettingsRowDivider()
            SettingsToggleRow(
                title: Localization.toggleLocalSpaceNumbers,
                isOn: model.binding(\.localSpaceNumbers),
                icon: "1.square",
                subtitle: Localization.tipLocalSpaceNumbers
            )
            SettingsRowDivider()
            separatorColorRow
        }
    }

    /// Separators only render between displays, so the row follows the
    /// `showAllDisplays` toggle.
    private var separatorColorRow: some View {
        let disabled = !model.value(\.showAllDisplays)
        return SettingsRow(icon: "poweron", subtitle: Localization.tipSeparator, disabled: disabled) {
            Text(Localization.labelSeparator)
                .foregroundStyle(disabled ? .tertiary : .primary)
        } control: {
            ColorPicker(Localization.labelSeparator, selection: separatorColorBinding)
                .labelsHidden()
            Button {
                model.binding(\.separatorColor).wrappedValue = nil
            } label: {
                Image(systemName: "arrow.counterclockwise")
            }
            .buttonStyle(.borderless)
            .disabled(model.value(\.separatorColor) == nil)
            .help(Localization.buttonReset)
        }
    }

    private var separatorColorBinding: Binding<Color> {
        let stored = model.binding(\.separatorColor)
        let fallback = IconColors.defaultSeparator(darkMode: colorScheme == .dark)
        return Binding(
            get: { Color(nsColor: stored.wrappedValue ?? fallback) },
            set: { stored.wrappedValue = NSColor($0) }
        )
    }

    private var fullscreenLetterBinding: Binding<Bool> {
        let stored = model.binding(\.fullscreenIconStyle)
        return Binding(
            get: { stored.wrappedValue == .letter },
            set: { stored.wrappedValue = $0 ? .letter : .appIcon }
        )
    }
}
