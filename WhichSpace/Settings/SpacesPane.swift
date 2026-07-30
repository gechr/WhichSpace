import AppKit
import SwiftUI

/// The Spaces settings pane: a Space list on the left (with a pinned
/// "Default Style" template entry and a display picker when several
/// displays are connected) and the editor with a live preview on the right.
/// Container-agnostic - it knows nothing about the window chrome hosting it.
struct SpacesPane: View {
    let model: SpaceEditorModel
    let onOpenCustomSoundsFolder: () -> Void

    @State private var colorPanel = ColorPanelCoordinator()

    var body: some View {
        HStack(alignment: .top, spacing: Layout.settingsSectionSpacing) {
            listColumn
                .frame(minWidth: Layout.settingsSpaceListWidth, alignment: .leading)
            editorColumn
                .frame(width: editorWidth)
        }
        .padding(Layout.settingsPanePadding)
        .toggleStyle(.switch)
        .font(.system(size: Layout.settingsRowFontSize))
        .onAppear {
            model.normalizeSelection()
        }
    }

    /// The editor column keeps its base-configuration width; the pane's
    /// total width follows the list's natural width.
    private var editorWidth: Double {
        Layout.settingsSpacesPaneWidth - Layout.settingsSpaceListWidth
            - Layout.settingsSectionSpacing - 2 * Layout.settingsPanePadding
    }

    // MARK: - Space List

    private var listColumn: some View {
        VStack(alignment: .leading, spacing: Layout.settingsSectionSpacing) {
            if model.displays.count > 1 {
                listHeader(Localization.labelDisplays)
                displayPicker
            }
            listHeader(Localization.paneSpaces)
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    listRow(for: .defaultStyle, title: "[\(Localization.labelDefault)]")
                    // Full-width and undimmed, unlike SettingsRowDivider, so the
                    // template entry reads as separate from the real Spaces below
                    Divider()
                        .padding(.vertical, 3)
                    ForEach(model.spaceEntries, id: \.number) { candidate in
                        listRow(
                            for: .space(candidate.number),
                            title: model.spaceName(for: candidate),
                            dimmed: candidate.entry == nil
                        )
                    }
                }
                // Ideal width instead of the proposed width, so the list
                // sizes to its widest row - whatever the font - rather
                // than truncating against a predicted width
                .fixedSize(horizontal: true, vertical: false)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color(nsColor: .quaternarySystemFill))
                )
                // The overlay scroller must not cover row text
                .padding(.trailing, listOverflows ? Layout.settingsSpaceListScrollerWidth : 0)
            }
            .frame(height: min(listContentHeight, Layout.settingsSpaceListMaxHeight))
        }
    }

    private var listOverflows: Bool {
        listContentHeight > Layout.settingsSpaceListMaxHeight
    }

    /// The height the list needs to show every row without scrolling: each
    /// row is its icon or text (whichever is taller) plus vertical padding,
    /// and the template divider adds its own height and padding.
    private var listContentHeight: Double {
        let font = NSFont.systemFont(ofSize: Layout.settingsRowFontSize)
        let textHeight = ("Ag" as NSString).size(withAttributes: [.font: font]).height
        var rowHeights = [max(model.listIcon(for: .defaultStyle).size.height, textHeight) + 2 * 6]
        for candidate in model.spaceEntries {
            let icon = model.listIcon(for: .space(candidate.number))
            rowHeights.append(max(icon.size.height, textHeight) + 2 * 6)
        }
        return ceil(rowHeights.reduce(0, +) + 1 + 2 * 3)
    }

    private func listHeader(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 16, weight: .bold))
            .padding(.leading, 4)
    }

    private var displayPicker: some View {
        Picker(Localization.labelDisplays, selection: displayBinding) {
            ForEach(Array(model.displays.enumerated()), id: \.element.displayID) { index, display in
                Text(String(index + 1)).tag(display.displayID as String?)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .focusable(false)
    }

    private var displayBinding: Binding<String?> {
        Binding(
            get: { model.selectedDisplayID },
            set: {
                model.selectedDisplayID = $0
                model.normalizeSelection()
            }
        )
    }

    /// Dimmed rows are placeholders for Spaces that do not exist yet -
    /// stylable ahead of time but not real Spaces. The template row renders
    /// bold instead to stand apart from the numbered rows.
    private func listRow(
        for selection: SpaceEditorModel.Selection, title: String?, dimmed: Bool = false
    ) -> some View {
        let isSelected = model.selection == selection
        let icon = model.listIcon(for: selection)
        return Button {
            model.selection = selection
        } label: {
            HStack(spacing: 8) {
                if selection == .defaultStyle {
                    Image(systemName: "paintbrush.fill")
                        .font(.system(size: icon.size.height * 0.5, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: icon.size.width, height: icon.size.height)
                } else {
                    Image(nsImage: icon)
                }
                if let title {
                    Text(title)
                        .lineLimit(1)
                        .fontWeight(selection == .defaultStyle ? .bold : .regular)
                        .foregroundStyle(
                            selection == .defaultStyle
                                ? AnyShapeStyle(.secondary)
                                : dimmed ? AnyShapeStyle(.secondary) : AnyShapeStyle(.primary)
                        )
                }
                Spacer(minLength: 0)
            }
            .opacity(dimmed ? 0.5 : 1)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .contentShape(Rectangle())
            // The keyboard focus ring follows the inset highlight shape;
            // the button's full bounds would clip against the scroll edges
            .contentShape(
                .focusEffect,
                RoundedRectangle(cornerRadius: 6, style: .continuous).inset(by: 4)
            )
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(isSelected ? AnyShapeStyle(.selection.opacity(0.35)) : AnyShapeStyle(.clear))
                    .padding(.horizontal, 4)
            )
        }
        .buttonStyle(.plain)
        .focusable(false)
    }

    // MARK: - Editor

    private var editorColumn: some View {
        VStack(alignment: .leading, spacing: Layout.settingsSectionSpacing) {
            if model.isEditingDefaultStyle {
                defaultStyleBanner
            }
            SettingsSection(Localization.labelPreview) {
                previewRow
            }
            ScrollView {
                SpaceEditorView(
                    model: model,
                    colorPanel: colorPanel,
                    onOpenCustomSoundsFolder: onOpenCustomSoundsFolder
                )
            }
            .frame(height: Layout.settingsSpacesEditorHeight)
        }
    }

    /// Explains what the selected template entry is - it is not a Space.
    /// One fill step stronger than the regular cards so it reads as a notice.
    private var defaultStyleBanner: some View {
        VStack(alignment: .leading, spacing: 0) {
            SettingsRow {
                HStack(spacing: 10) {
                    Image(systemName: "info.circle.fill")
                        .font(.system(size: 22))
                        .foregroundStyle(.tint)
                    Text(Localization.bannerDefaultStyleDetail)
                }
            } control: {
                EmptyView()
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.accentColor.opacity(0.12))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color.accentColor.opacity(0.35))
        )
    }

    /// The edited entry rendered large; the image is handler-backed, so the
    /// enlargement re-renders sharply rather than scaling a small bitmap.
    /// The card's spare width carries the copy/save/reset actions.
    private var previewRow: some View {
        HStack(spacing: 10) {
            // Leading-anchored in whatever width the action buttons leave
            // over, so a wide icon can never run underneath them
            Image(nsImage: model.icon(sizeScale: Layout.settingsSpacesPreviewScale))
                .frame(maxWidth: .infinity, alignment: .leading)
            VStack(alignment: .trailing, spacing: 6) {
                if !model.isEditingDefaultStyle {
                    Button(Localization.actionSetAsDefault) {
                        model.saveAsDefaultStyle()
                    }
                    .help(Localization.tipSetDefaultStyle)
                }
                copyToMenu
                resetMenu
            }
        }
        .padding(.horizontal, Layout.settingsRowHorizontalPadding)
        .frame(height: Layout.settingsSpacesPreviewHeight)
    }

    /// Both items confirm through the model before clearing anything. The
    /// first names the template rather than a Space while it is selected.
    private var resetMenu: some View {
        Menu(Localization.actionReset) {
            Button(
                model.isEditingDefaultStyle
                    ? Localization.labelDefaultStyle
                    : Localization.actionResetCurrentSpace
            ) {
                model.resetToDefault()
            }
            Button(Localization.actionResetAllSpaces) {
                model.resetAllSpacesToDefault()
            }
        }
        .fixedSize()
        .help(Localization.tipResetSpaceToDefault)
    }

    /// Both targets confirm through the model before writing anything.
    private var copyToMenu: some View {
        Menu(Localization.actionCopyTo) {
            Button(Localization.labelAllSpacesThisDisplay) {
                model.copyToAllSpaces()
            }
            Button(Localization.labelAllSpacesAllDisplays) {
                model.copyToAllDisplays()
            }
        }
        .fixedSize()
        .help(Localization.tipCopyTo)
    }
}
