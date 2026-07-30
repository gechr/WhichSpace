import AppKit
import SwiftUI

/// The Spaces settings pane: a Space list on the left (with a pinned
/// "Default Style" template entry and a display picker when several
/// displays are connected) and the editor with a live preview on the right.
/// Container-agnostic - it knows nothing about the window chrome hosting it.
struct SpacesPane: View {
    let model: SpaceEditorModel

    @State private var colorPanel = ColorPanelCoordinator()

    var body: some View {
        let listWidth = listWidth
        HStack(alignment: .top, spacing: Layout.settingsSectionSpacing) {
            listColumn
                .frame(width: listWidth)
            editorColumn
        }
        .padding(Layout.settingsPanePadding)
        .frame(width: Layout.settingsSpacesPaneWidth + listWidth - Layout.settingsSpaceListWidth)
        .toggleStyle(.switch)
        .font(.system(size: Layout.settingsRowFontSize))
        .onAppear {
            model.normalizeSelection()
        }
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
                        listRow(for: .space(candidate.number), title: model.spaceName(for: candidate))
                    }
                }
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color(nsColor: .quaternarySystemFill))
                )
            }
        }
        .frame(maxHeight: Layout.settingsSpacesEditorHeight + Layout.settingsSpacesPreviewHeight
            + Layout.settingsSectionSpacing)
    }

    /// The list column's width: wide enough for its longest row, never
    /// narrower than the base width. The pane widens by the same amount so
    /// the editor column keeps its layout.
    private var listWidth: Double {
        let font = NSFont.systemFont(ofSize: Layout.settingsRowFontSize)
        var rows: [(icon: NSImage, title: String?)] = [
            (model.listIcon(for: .defaultStyle), "[\(Localization.labelDefault)]"),
        ]
        for candidate in model.spaceEntries {
            rows.append((model.listIcon(for: .space(candidate.number)), model.spaceName(for: candidate)))
        }
        let widths = rows.map { row -> Double in
            let text = row.title.map { ($0 as NSString).size(withAttributes: [.font: font]).width } ?? 0
            return row.icon.size.width + 8 + text + 2 * 10
        }
        let widest = widths.max() ?? 0
        return max(Layout.settingsSpaceListWidth, ceil(widest) + 2)
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

    private func listRow(for selection: SpaceEditorModel.Selection, title: String?) -> some View {
        let isSelected = model.selection == selection
        return Button {
            model.selection = selection
        } label: {
            HStack(spacing: 8) {
                Image(nsImage: model.listIcon(for: selection))
                if let title {
                    Text(title)
                        .lineLimit(1)
                        .foregroundStyle(
                            selection == .defaultStyle
                                ? AnyShapeStyle(.secondary)
                                : AnyShapeStyle(.primary)
                        )
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .contentShape(Rectangle())
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(isSelected ? AnyShapeStyle(.selection.opacity(0.35)) : AnyShapeStyle(.clear))
                    .padding(.horizontal, 4)
            )
        }
        .buttonStyle(.plain)
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
                SpaceEditorView(model: model, colorPanel: colorPanel)
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
