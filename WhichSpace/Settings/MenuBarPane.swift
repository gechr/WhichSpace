import AppKit
import SwiftUI

/// The Menu Bar settings pane: which Spaces appear in the status item, how
/// each icon is drawn, and how the item as a whole behaves. Container-agnostic
/// - it knows nothing about the window chrome hosting it.
///
/// The sections are ordered so that a row always appears below the toggles
/// that gate it. Both visibility masters lead the pane, which puts the rows
/// they dim - the fullscreen letter, and shrinking to fit - in reading order
/// after the settings that explain the dimming.
struct MenuBarPane: View {
    let model: SettingsModel

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        SettingsForm {
            spacesSection
            appearanceSection
            behaviorSection
        }
    }

    /// Whether the status item comes down to one icon for the current Space on
    /// the current display, leaving nothing beside it to give up.
    private var showsCurrentSpaceOnly: Bool {
        !(model.value(\.showAllSpaces) || model.value(\.showAllDisplays))
    }

    // MARK: - Spaces

    /// Which Spaces get an icon: the two masters that decide it, each leading
    /// the rows that only apply while it is on.
    private var spacesSection: some View {
        SettingsSection(Localization.labelSpaces) {
            spaceVisibilityRows
            // Full-width and undimmed, unlike SettingsRowDivider, so the two
            // masters read as groups of their own rather than one long list
            Divider()
                .padding(.vertical, 3)
            displayVisibilityRows
        }
    }

    /// Which of this display's Spaces get an icon. The dim/hide rows only
    /// apply when more than the current Space is shown.
    @ViewBuilder
    private var spaceVisibilityRows: some View {
        SettingsToggleRow(
            title: Localization.toggleShowAllSpaces,
            isOn: model.showAllSpacesBinding,
            icon: "square.grid.3x1.below.line.grid.1x2",
            subtitle: Localization.tipShowAllSpaces,
            anchor: .showAllSpaces
        )
        SettingsRowDivider()
        SettingsSliderRow(
            title: Localization.labelInactiveSpaceOpacity,
            value: model.binding(\.inactiveSpaceOpacity),
            range: Layout.inactiveSpaceOpacityRange,
            defaultValue: Layout.defaultInactiveSpaceOpacity,
            icon: "aqi.low",
            indented: true,
            disabled: showsCurrentSpaceOnly,
            subtitle: Localization.tipInactiveSpaceOpacity,
            anchor: .dimInactiveSpaces
        )
        SettingsRowDivider()
        SettingsToggleRow(
            title: Localization.toggleHideEmptySpaces,
            isOn: model.binding(\.hideEmptySpaces),
            icon: "eye.slash.fill",
            indented: true,
            disabled: showsCurrentSpaceOnly,
            subtitle: Localization.tipHideEmptySpaces,
            anchor: .hideEmptySpaces
        )
        SettingsRowDivider()
        SettingsToggleRow(
            title: Localization.toggleHideFullscreenApps,
            isOn: model.binding(\.hideFullscreenApps),
            icon: "eye.slash.fill",
            indented: true,
            disabled: showsCurrentSpaceOnly,
            subtitle: Localization.tipHideFullscreenApps,
            anchor: .hideFullscreenApps
        )
    }

    /// Whether other displays' Spaces are shown, and how the groups they form
    /// are told apart. The separator rows only apply while they are shown.
    @ViewBuilder
    private var displayVisibilityRows: some View {
        SettingsToggleRow(
            title: Localization.toggleShowAllDisplays,
            isOn: model.showAllDisplaysBinding,
            icon: "display.2",
            subtitle: Localization.tipShowAllDisplays,
            anchor: .showAllDisplays
        )
        SettingsRowDivider()
        displayOrderRow
        SettingsRowDivider()
        preserveSystemSpaceNumbersRow
        SettingsRowDivider()
        separatorColorRow
        SettingsRowDivider()
        separatorStyleRow
    }

    // MARK: - Appearance

    /// How big each icon is drawn and what it is labelled with: the numbering,
    /// which applies to every display whether or not their Spaces are shown,
    /// and what stands in for the number on a full-screen Space.
    private var appearanceSection: some View {
        SettingsSection(Localization.labelAppearance) {
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

    // MARK: - Behavior

    /// What the status item as a whole does: how much it gives up when the
    /// menu bar runs out of room, and when it stands down altogether.
    private var behaviorSection: some View {
        SettingsSection(Localization.labelBehavior) {
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
                title: Localization.toggleHideSingleSpace,
                isOn: model.binding(\.hideSingleSpace),
                icon: "eye.slash.fill",
                subtitle: Localization.tipHideSingleSpace,
                anchor: .hideSingleSpace
            )
            SettingsRowDivider()
            SettingsSliderRow(
                title: Localization.labelPickerAppIcons,
                value: spacePickerMaxAppIconsBinding,
                range: 0 ... Double(Layout.spacePickerMaxAppIconsRange.upperBound),
                step: 1,
                defaultValue: Double(Layout.defaultSpacePickerMaxAppIcons),
                icon: "app.badge",
                // The picker menu only appears in single-icon mode, so the
                // rows fade while the bar shows every Space
                dimmed: !showsCurrentSpaceOnly,
                subtitle: Localization.tipPickerAppIcons,
                anchor: .spacePickerIcons,
                // Explicit so the trailing closure reads as the formatter
                // rather than the parser
                valueParser: SettingsSliderRow.parseNumber
            ) { $0 == 0 ? Localization.labelOff : String(Int($0)) }
            SettingsRowDivider()
            spacePickerStyleRow
        }
    }

    /// What each picker row shows beside its Space icon, nested under the
    /// slider that decides whether app icons appear at all.
    private var spacePickerStyleRow: some View {
        let dimmed = !showsCurrentSpaceOnly
            || (model.value(\.spacePickerMaxAppIcons) == 0 && model.value(\.spacePickerStyle) != SpacePickerStyle.none)
        return SettingsRow(
            icon: "list.bullet.rectangle",
            subtitle: Localization.tipPickerStyle,
            dimmed: dimmed,
            indented: true,
            anchor: .spacePickerStyle
        ) {
            Text(Localization.labelPickerStyle)
                .foregroundStyle(dimmed ? .tertiary : .primary)
        } control: {
            Picker(Localization.labelPickerStyle, selection: model.binding(\.spacePickerStyle)) {
                Text(SpacePickerStyle.none.localizedName).tag(SpacePickerStyle.none)
                Divider()
                ForEach(SpacePickerStyle.allCases.filter { $0 != .none }, id: \.self) { style in
                    Text(style.localizedName).tag(style)
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .fixedSize()
        }
    }

    // MARK: - Display Order Row

    /// Whether display groups follow their physical left-to-right arrangement,
    /// nested under the toggle that puts more than one of them in the menu bar.
    private var displayOrderRow: some View {
        SettingsToggleRow(
            title: Localization.labelDisplayOrder,
            isOn: model.physicalDisplayOrderBinding,
            icon: "rectangle.3.group",
            indented: true,
            disabled: !model.value(\.showAllDisplays),
            subtitle: Localization.tipDisplayOrder,
            anchor: .displayOrder
        )
    }

    /// Whether a physical reorder changes only group placement while each
    /// Desktop keeps the number assigned by macOS.
    private var preserveSystemSpaceNumbersRow: some View {
        let physicalOrderEnabled = model.value(\.displayOrder) == .physical
        return SettingsToggleRow(
            title: Localization.togglePreserveSystemSpaceNumbers,
            isOn: model.binding(\.preserveSystemSpaceNumbers),
            icon: "123.rectangle",
            indented: true,
            disabled: !model.value(\.showAllDisplays) || model.value(\.localSpaceNumbers),
            dimmed: !physicalOrderEnabled,
            subtitle: Localization.tipPreserveSystemSpaceNumbers,
            anchor: .preserveSystemSpaceNumbers
        )
    }

    // MARK: - Separator Rows

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

    // MARK: - Bindings

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

    private var spacePickerMaxAppIconsBinding: Binding<Double> {
        let stored = model.binding(\.spacePickerMaxAppIcons)
        return Binding(
            get: { Double(stored.wrappedValue) },
            set: { stored.wrappedValue = Int($0) }
        )
    }
}
