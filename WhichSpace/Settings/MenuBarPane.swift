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
                    icon: "arrow.up.left.and.down.right.and.arrow.up.right.and.down.left",
                    subtitle: Localization.tipIconSize,
                    anchor: .iconSize
                )
                SettingsRowDivider()
                SettingsSliderRow(
                    title: Localization.menuPadding,
                    value: model.binding(\.paddingScale),
                    range: Layout.paddingScaleRange,
                    defaultValue: Layout.defaultPaddingScale,
                    icon: "arrow.left.and.right",
                    subtitle: Localization.tipIconPadding,
                    anchor: .iconPadding
                )
            }
            iconSection
            displaysSection
            visibilitySection
        }
    }

    /// Whether the status item comes down to one icon for the current Space on
    /// the current display, leaving nothing beside it to give up.
    private var showsCurrentSpaceOnly: Bool {
        !(model.value(\.showAllSpaces) || model.value(\.showAllDisplays))
    }

    /// Whether other displays' Spaces are shown, and how the groups they form
    /// are told apart. The separator rows only apply while they are shown.
    private var displaysSection: some View {
        SettingsSection {
            SettingsToggleRow(
                title: Localization.toggleShowAllDisplays,
                isOn: model.showAllDisplaysBinding,
                icon: "display.2",
                subtitle: Localization.tipShowAllDisplays,
                anchor: .showAllDisplays
            )
            SettingsRowDivider()
            separatorColorRow
            SettingsRowDivider()
            separatorStyleRow
        }
    }

    /// Which Spaces get an icon. The dim/hide rows only apply when more than
    /// the current Space is shown.
    private var visibilitySection: some View {
        let dependentDisabled = showsCurrentSpaceOnly
        return SettingsSection {
            SettingsToggleRow(
                title: Localization.toggleShowAllSpaces,
                isOn: model.showAllSpacesBinding,
                icon: "square.grid.3x1.below.line.grid.1x2",
                subtitle: Localization.tipShowAllSpaces,
                anchor: .showAllSpaces
            )
            SettingsRowDivider()
            SettingsToggleRow(
                title: Localization.toggleDimInactiveSpaces,
                isOn: model.binding(\.dimInactiveSpaces),
                icon: "aqi.low",
                indented: true,
                disabled: dependentDisabled,
                subtitle: Localization.tipDimInactiveSpaces,
                anchor: .dimInactiveSpaces
            )
            SettingsRowDivider()
            SettingsToggleRow(
                title: Localization.toggleHideEmptySpaces,
                isOn: model.binding(\.hideEmptySpaces),
                icon: "eye.slash.fill",
                indented: true,
                disabled: dependentDisabled,
                subtitle: Localization.tipHideEmptySpaces,
                anchor: .hideEmptySpaces
            )
            SettingsRowDivider()
            SettingsToggleRow(
                title: Localization.toggleHideSingleSpace,
                isOn: model.binding(\.hideSingleSpace),
                icon: "eye.slash.fill",
                indented: true,
                disabled: dependentDisabled,
                subtitle: Localization.tipHideSingleSpace,
                anchor: .hideSingleSpace
            )
            SettingsRowDivider()
            SettingsToggleRow(
                title: Localization.toggleHideFullscreenApps,
                isOn: model.binding(\.hideFullscreenApps),
                icon: "eye.slash.fill",
                indented: true,
                disabled: dependentDisabled,
                subtitle: Localization.tipHideFullscreenApps,
                anchor: .hideFullscreenApps
            )
        }
    }

    /// How much the icon gives up when the menu bar runs out of room, and what
    /// each icon is labelled with: the numbering, which applies to every
    /// display whether or not their Spaces are shown, and what stands in for
    /// the number on a full-screen Space.
    private var iconSection: some View {
        SettingsSection {
            SettingsToggleRow(
                title: Localization.toggleShrinkToFit,
                isOn: model.binding(\.shrinkIconToFit),
                icon: "arrow.down.right.and.arrow.up.left",
                // A single icon has no Spaces or displays to drop, leaving
                // only its own padding and styling to give up, so the row
                // fades while staying live
                dimmed: showsCurrentSpaceOnly,
                subtitle: String(format: Localization.tipShrinkToFit, AppInfo.appName),
                anchor: .shrinkToFit
            )
            SettingsRowDivider()
            SettingsToggleRow(
                title: Localization.toggleLocalSpaceNumbers,
                isOn: model.binding(\.localSpaceNumbers),
                icon: "1.square",
                subtitle: Localization.tipLocalSpaceNumbers,
                anchor: .localSpaceNumbers
            )
            SettingsRowDivider()
            SettingsToggleRow(
                title: Localization.toggleUseFForFullscreenApps,
                isOn: fullscreenLetterBinding,
                icon: "f.square",
                // Irrelevant while fullscreen Spaces are hidden altogether
                disabled: model.value(\.hideFullscreenApps),
                subtitle: Localization.tipUseFForFullscreenApps,
                anchor: .fullscreenLetter
            )
        }
    }

    /// Separators only render between displays, so the row nests under the
    /// `showAllDisplays` toggle.
    private var separatorColorRow: some View {
        let disabled = !model.value(\.showAllDisplays)
        return SettingsRow(
            icon: "poweron",
            subtitle: Localization.tipSeparator,
            disabled: disabled,
            indented: true,
            anchor: .separatorColor
        ) {
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

    /// The glyph drawn between display groups, sitting beside the colour row
    /// it accompanies and gated the same way.
    private var separatorStyleRow: some View {
        let disabled = !model.value(\.showAllDisplays)
        return SettingsRow(
            icon: "ellipsis",
            subtitle: Localization.tipSeparatorStyle,
            disabled: disabled,
            indented: true,
            anchor: .separatorStyle
        ) {
            Text(Localization.labelSeparatorStyle)
                .foregroundStyle(disabled ? .tertiary : .primary)
        } control: {
            Picker(Localization.labelSeparatorStyle, selection: model.binding(\.separatorStyle)) {
                // Drawing nothing is set apart from the glyphs that draw
                // something, the same way the sound picker sets None apart
                Text(SeparatorStyle.blank.localizedName).tag(SeparatorStyle.blank)
                Divider()
                ForEach(SeparatorStyle.allCases.filter { $0 != .blank }, id: \.self) { style in
                    Text("\(style.pickerGlyph)  \(style.localizedName)").tag(style)
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .fixedSize()
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
