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

    @Environment(SettingsHighlighter.self) private var highlighter: SettingsHighlighter?

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
        // The list sizes itself to its rows, so the window has to follow it
        // rather than keep the width it was given when the pane opened
        .fitsSettingsWindow(measuring: listMetrics)
        .onAppear {
            model.normalizeSelection()
        }
        // Switching to another pane removes the hovered cell without a
        // guaranteed final hover exit, which would strand a stale preview
        // in the long-lived model
        .onDisappear {
            model.clearPreview()
        }
    }

    /// The editor column keeps its base-configuration width, widened by the
    /// gutter its cards give up to the scroller; the pane's total width
    /// follows the list's natural width.
    private var editorWidth: Double {
        Layout.settingsSpacesPaneWidth - Layout.settingsSpaceListWidth
            - Layout.settingsSectionSpacing - 2 * Layout.settingsPanePadding
            + Layout.settingsSpacesEditorGutter
    }

    // MARK: - Space List

    private var listColumn: some View {
        VStack(alignment: .leading, spacing: Layout.settingsSectionSpacing) {
            if model.displays.count > 1 {
                listHeader(Localization.labelDisplays)
                VStack(alignment: .leading, spacing: 4) {
                    displayPicker
                    displayNameCaption
                }
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
                            dimmed: candidate.entry == nil,
                            isCurrent: model.isCurrentSpace(candidate)
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

    /// The list dimensions that move while the pane is open: the icon column
    /// widens as a label is typed, and rows grow taller with the icon. Row
    /// titles are fixed for a given set of Spaces, so they need no watching.
    private var listMetrics: CGSize {
        CGSize(width: listIconColumnWidth, height: listContentHeight)
    }

    private var listOverflows: Bool {
        listContentHeight > Layout.settingsSpaceListMaxHeight
    }

    /// The width of the widest row icon. Styles like the pill auto-expand
    /// for two-digit numbers, so each row centers its icon in a shared
    /// column instead of letting wide icons eat the gap to the title.
    private var listIconColumnWidth: Double {
        var widths = [model.listIcon(for: .defaultStyle).size.width]
        for candidate in model.spaceEntries {
            widths.append(model.listIcon(for: .space(candidate.number)).size.width)
        }
        return widths.max() ?? 0
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

    /// A numbered segment edits that display's overrides; the trailing "All"
    /// segment edits the shared styles every display inherits.
    private var displayPicker: some View {
        Picker(Localization.labelDisplays, selection: displayBinding) {
            ForEach(Array(model.displays.enumerated()), id: \.element.displayID) { index, display in
                Text(String(index + 1)).tag(display.displayID as String?)
            }
            Text(Localization.labelAllDisplays).tag(nil as String?)
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .focusable(false)
    }

    /// Names the display the numbered picker has selected, or says what the
    /// "All" scope does while it is selected. The width is capped at the
    /// list's own so a long product name truncates rather than widening the
    /// pane around it.
    @ViewBuilder
    private var displayNameCaption: some View {
        if model.selectedDisplayID == nil {
            // The explanation may not fit one line, so it wraps instead of
            // truncating like a display name does
            caption(Localization.tipAllDisplays, lines: 2)
        } else if let name = model.displayName(for: model.selectedDisplayID) {
            caption(name)
        }
    }

    private func caption(_ text: String, lines: Int = 1) -> some View {
        Text(text)
            .font(.system(size: Layout.settingsRowSubtitleFontSize))
            .foregroundStyle(.secondary)
            .lineLimit(lines)
            .truncationMode(.tail)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: Layout.settingsSpaceListWidth, alignment: .leading)
            .padding(.leading, 4)
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
        for selection: SpaceEditorModel.Selection,
        title: String?,
        dimmed: Bool = false,
        isCurrent: Bool = false
    ) -> some View {
        let isSelected = model.selection == selection
        let icon = model.listIcon(for: selection)
        return Button {
            model.selection = selection
        } label: {
            HStack(spacing: 8) {
                Image(nsImage: icon)
                    .frame(width: listIconColumnWidth, alignment: .center)
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
                // Marks where the user is right now. The slot is reserved on
                // every row so the list width does not shift as the marker
                // moves between Spaces with the window open.
                ZStack {
                    if isCurrent {
                        Image(systemName: "circle.fill")
                            .font(.system(size: 6))
                            .foregroundStyle(.tint)
                    }
                }
                .frame(width: 8)
                // Rows with their own style carry a revert button; resetSpace
                // confirms through the model before clearing anything. The
                // slot is reserved on every row so the list width does not
                // jump when a Space first gains its own style.
                ZStack {
                    if case let .space(number) = selection, model.hasOwnStyle(for: selection) {
                        Button {
                            model.resetSpace(number)
                        } label: {
                            Image(systemName: "arrow.counterclockwise")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        .help(Localization.tipHasOwnStyle)
                    }
                }
                .frame(width: 14)
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
        .help(rowHelp(dimmed: dimmed, isCurrent: isCurrent))
    }

    /// Says what a row's appearance means. A dimmed row is the only clue that
    /// a Space can be styled before it exists, and the marker dot needs
    /// naming; an empty string leaves an ordinary row without a tooltip.
    private func rowHelp(dimmed: Bool, isCurrent: Bool) -> String {
        if dimmed {
            return Localization.tipSpacePlaceholder
        }
        return isCurrent ? Localization.tipCurrentSpace : ""
    }

    // MARK: - Editor

    private var editorColumn: some View {
        VStack(alignment: .leading, spacing: Layout.settingsSectionSpacing) {
            // These sit outside the scroll view, so they take the scroller
            // gutter themselves to stay aligned with the scrolling cards
            Group {
                if model.isEditingDefaultStyle {
                    defaultStyleBanner
                }
                // Emphasized so the pinned card reads as its own thing rather
                // than the first of the cards scrolling beneath it
                SettingsSection(Localization.labelPreview, anchor: .preview, emphasized: true) {
                    previewRow
                }
            }
            .padding(.trailing, Layout.settingsSpacesEditorGutter)
            // This is the one pane tall enough to scroll, so a deep-linked row
            // has to be brought into view rather than only highlighted
            ScrollViewReader { proxy in
                ScrollView {
                    SpaceEditorView(
                        model: model,
                        colorPanel: colorPanel,
                        onOpenCustomSoundsFolder: onOpenCustomSoundsFolder
                    )
                    // The scroller sits at the trailing edge, so the cards
                    // stop short of it rather than running up against it
                    .padding(.trailing, Layout.settingsSpacesEditorGutter)
                }
                // The Space list can make the pane taller than this column
                // needs, so the editor takes the leftover height rather than
                // leaving the pane blank beneath it. Stating the ideal keeps
                // the window measuring this column at the base height: a
                // scroll view without one reports its whole card stack.
                .frame(
                    minHeight: Layout.settingsSpacesEditorBaseHeight,
                    idealHeight: Layout.settingsSpacesEditorBaseHeight,
                    maxHeight: .infinity
                )
                // onAppear covers a link that opens the window on this pane,
                // where the anchor is already set before the editor exists
                .onAppear {
                    scroll(proxy, to: highlighter?.anchor)
                }
                .onChange(of: highlighter?.anchor) { _, anchor in
                    scroll(proxy, to: anchor)
                }
            }
        }
    }

    /// Centers the anchored row, leaving the pinned preview card alone since
    /// it sits above the scroll view.
    private func scroll(_ proxy: ScrollViewProxy, to anchor: SettingsAnchor?) {
        guard let anchor, anchor != .preview else {
            return
        }
        withAnimation {
            proxy.scrollTo(anchor.target, anchor: .center)
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
            PreviewCardIcon(model: model)
            VStack(alignment: .trailing, spacing: 6) {
                if !model.isEditingDefaultStyle {
                    Button(Localization.actionSetAsDefault) {
                        model.saveAsDefaultStyle()
                    }
                    .help(Localization.tipSetDefaultStyle)
                }
                copyFromMenu
                copyToMenu
                resetMenu
            }
        }
        .padding(.leading, Layout.settingsRowHorizontalPadding)
        .padding(.trailing, Layout.settingsSpacesPreviewTrailingPadding)
        .padding(.vertical, Layout.settingsRowVerticalPadding)
        .frame(minHeight: Layout.settingsSpacesPreviewMinHeight)
    }

    /// Leading-anchored in whatever width the action buttons leave over. The
    /// enlargement is a ceiling rather than a fixed size: a label wide enough
    /// to outgrow the card scales back down to fit instead of drawing across
    /// the buttons and out of the pane.
    ///
    /// A separate view so hover previews invalidate only this image; inlined
    /// in the pane body, every hover would re-render the Space list icons
    /// and re-measure the window.
    private struct PreviewCardIcon: View {
        let model: SpaceEditorModel

        var body: some View {
            let icon = model.icon(sizeScale: Layout.settingsSpacesPreviewScale)
            Image(nsImage: icon)
                .resizable()
                .scaledToFit()
                .frame(maxWidth: icon.size.width, maxHeight: icon.size.height)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
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

    /// Replaces the edited entry's style with the chosen Space's, confirming
    /// through the model first. No bulk item has a meaning here - a style can
    /// come from one Space only - so the sources stand alone without the
    /// divider the outbound menu needs.
    private var copyFromMenu: some View {
        Menu(Localization.actionCopyFrom) {
            ForEach(copyCandidates, id: \.number) { candidate in
                Button {
                    model.copyFromSpace(candidate.number)
                } label: {
                    Label {
                        Text(model.spaceName(for: candidate) ?? "")
                    } icon: {
                        Image(nsImage: model.listIcon(for: .space(candidate.number)))
                    }
                }
            }
        }
        .fixedSize()
        .help(Localization.tipCopyFrom)
    }

    /// All targets confirm through the model before writing anything. The
    /// all-displays item disappears under the "All" scope, whose edits
    /// already apply to every display; below the bulk targets, each other
    /// Space of the shown display is a single target, mirroring the list's
    /// icon and title so both read the same.
    private var copyToMenu: some View {
        Menu(Localization.actionCopyTo) {
            Button(bulkCopyTitle) {
                model.copyToAllSpaces()
            }
            if model.selectedDisplayID != nil {
                Button(Localization.labelAllSpacesAllDisplays) {
                    model.copyToAllDisplays()
                }
            }
            Divider()
            ForEach(copyCandidates, id: \.number) { candidate in
                Button {
                    model.copyToSpace(candidate.number)
                } label: {
                    // Fullscreen entries have no name and show icon only,
                    // matching their list rows
                    Label {
                        Text(model.spaceName(for: candidate) ?? "")
                    } icon: {
                        Image(nsImage: model.listIcon(for: .space(candidate.number)))
                    }
                }
            }
        }
        .fixedSize()
        .help(Localization.tipCopyTo)
    }

    /// Every list entry except the one being edited, serving both copy
    /// directions; the template edits space 0, so it offers every Space.
    private var copyCandidates: [(number: Int, entry: SpaceEntry?)] {
        model.spaceEntries.filter { model.selection != .space($0.number) }
    }

    /// What the bulk target is called. A lone display draws no distinction
    /// worth naming, so it names the Spaces alone; the two-way wording only
    /// earns its place alongside the display picker that explains it.
    private var bulkCopyTitle: String {
        guard model.displays.count > 1 else {
            return Localization.labelAllSpaces
        }
        return model.selectedDisplayID == nil
            ? Localization.labelAllSpacesAllDisplays
            : Localization.labelAllSpacesThisDisplay
    }
}

// MARK: - Live Window Fitting

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

    /// Grows or shrinks the window from its top-left corner, the same corner
    /// a tab switch sizes around, so the list the user is looking at stays put
    /// while the editor beside it moves.
    private func fit(_ view: NSView) {
        guard let window = view.window, let pane = paneView(containing: view) else {
            return
        }
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

private extension View {
    /// Keeps the settings window fitted to this pane as its ideal size
    /// changes, with `measured` naming the values that change it.
    func fitsSettingsWindow(measuring measured: CGSize) -> some View {
        background(SettingsWindowFitter(measured: measured))
    }
}
