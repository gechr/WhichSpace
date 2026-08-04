import AppKit
import SwiftUI

// MARK: - SpaceEditorView

/// The editor column of the Spaces pane: every per-Space preference for the
/// selected entry, grouped into the same sections as the status menu, with
/// section and row visibility mirroring the menu's gating.
struct SpaceEditorView: View {
    let model: SpaceEditorModel
    let colorPanel: ColorPanelCoordinator
    let onOpenCustomSoundsFolder: () -> Void

    @State private var symbolCatalog = SymbolGridView.Catalog.symbols
    @State private var userSounds: [String] = []

    @Environment(SettingsHighlighter.self) private var highlighter: SettingsHighlighter?

    var body: some View {
        let rules = model.clearRules
        VStack(alignment: .leading, spacing: Layout.settingsSectionSpacing) {
            colorsSection(rules)
            fontSection
            numberSection(rules)
            labelSection(rules)
            if !rules.symbolAlone {
                badgeSection
            }
            glyphSection(rules)
            soundSection
        }
        .task {
            await rescanUserSounds()
        }
        // Dropping a file into ~/Library/Sounds happens in Finder, so the
        // return trip makes the settings window key again - rescan then,
        // rather than only on first appearance
        .onReceive(
            NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)
        ) { _ in
            Task {
                await rescanUserSounds()
            }
        }
    }

    private func rescanUserSounds() async {
        userSounds = await Task.detached(priority: .userInitiated) {
            SoundCatalog.discoverUserSounds()
        }.value
    }

    /// Cell identity for state that must reset when the edited entry changes.
    private var entryIdentity: String {
        "\(model.editingDisplay ?? "")-\(model.editingSpace)"
    }

    private var previewNumber: String {
        String(model.editingDisplayNumber)
    }

    // MARK: - Label

    private func labelSection(_ rules: ClearCellRules) -> some View {
        SettingsSection(Localization.menuLabel) {
            SettingsRow(icon: "character.textbox", subtitle: Localization.tipLabelInput, anchor: .spaceLabel) {
                Text(Localization.menuLabel)
            } control: {
                CommittingTextField(
                    placeholder: LabelTemplate.spaceToken,
                    initialValue: model.label ?? "",
                    clearHelp: Localization.tipClearLabel,
                    fieldWidth: 140,
                    clamp: { LabelTemplate.truncate($0) }
                ) { model.setLabel($0) }
            }
            .id("label-\(entryIdentity)")
            if rules.hasLabel {
                SettingsRowDivider()
                StyleGridView(
                    styles: StyleGridView.labelStyles,
                    selected: model.labelStyle,
                    previewNumber: previewNumber,
                    previewText: model.label.map {
                        LabelTemplate.resolve($0, space: model.editingDisplayNumber)
                    },
                    previewFont: model.font,
                    customColors: model.colors,
                    darkMode: model.darkMode,
                    usesLabelTitles: true,
                    onHover: { model.previewLabelStyle($0, hovering: $1) }
                ) { model.setLabelStyle($0) }
                    .padding(.horizontal, Layout.settingsRowHorizontalPadding)
                    .padding(.vertical, Layout.settingsRowVerticalPadding)
            }
            if rules.hasLabel, rules.symbolIsActive {
                symbolLayoutRows(rules)
            }
        }
    }

    /// Position/wrap/gap only apply when a symbol and a label are combined.
    @ViewBuilder
    private func symbolLayoutRows(_ rules: ClearCellRules) -> some View {
        SettingsRowDivider()
        SettingsRow(icon: "arrow.left.and.right", anchor: .symbolPosition) {
            Text(Localization.labelSymbolPosition)
        } control: {
            Picker(Localization.labelSymbolPosition, selection: symbolPositionBinding) {
                Text(Localization.labelLeft).tag(SymbolPosition.left)
                Text(Localization.labelRight).tag(SymbolPosition.right)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
            .segmentHover(count: 2) { index, hovering in
                model.previewSymbolPosition(index == 0 ? .left : .right, hovering: hovering)
            }
        }
        // Wrap only applies when the label shape can stretch around the
        // symbol; other shapes always render the side-by-side layout
        if rules.labelStyleCanWrap {
            SettingsRowDivider()
            SettingsRow(icon: "rectangle.dashed", anchor: .symbolWrap) {
                Text(Localization.labelSymbolWrap)
            } control: {
                Picker(Localization.labelSymbolWrap, selection: symbolWrapBinding) {
                    Text(Localization.labelInside).tag(SymbolWrap.inside)
                    Text(Localization.labelOutside).tag(SymbolWrap.outside)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
                .segmentHover(count: 2) { index, hovering in
                    model.previewSymbolWrap(index == 0 ? .inside : .outside, hovering: hovering)
                }
            }
        }
        SettingsRowDivider()
        SettingsSliderRow(
            title: Localization.menuPadding,
            value: symbolGapBinding,
            range: Layout.symbolGapScaleRange,
            defaultValue: Layout.defaultSymbolGapScale,
            icon: "arrow.left.and.right",
            anchor: .symbolGap
        )
    }

    private var symbolPositionBinding: Binding<SymbolPosition> {
        Binding(get: { model.symbolPosition }, set: { model.setSymbolPosition($0) })
    }

    private var symbolWrapBinding: Binding<SymbolWrap> {
        Binding(get: { model.symbolWrap }, set: { model.setSymbolWrap($0) })
    }

    private var symbolGapBinding: Binding<Double> {
        Binding(get: { model.symbolGap }, set: { model.setSymbolGap($0) })
    }

    // MARK: - Number

    private func numberSection(_ rules: ClearCellRules) -> some View {
        SettingsSection(Localization.menuNumber, anchor: .numberStyle) {
            StyleGridView(
                styles: StyleGridView.numberStyles,
                // A symbol replaces the number entirely, so no style reads
                // as active while one is set
                selected: rules.symbolIsActive ? nil : model.iconStyle,
                previewNumber: previewNumber,
                customColors: model.colors,
                darkMode: model.darkMode,
                onHover: { model.previewIconStyle($0, hovering: $1) }
            ) { model.setIconStyle($0) }
                .padding(.horizontal, Layout.settingsRowHorizontalPadding)
                .padding(.vertical, Layout.settingsRowVerticalPadding)
        }
    }

    // MARK: - Glyph

    /// Both `symbol` and `emoji` links land here, so the section keeps the
    /// former as its fixed anchor and `SettingsAnchor.target` folds the latter
    /// onto it.
    private func glyphSection(_ rules: ClearCellRules) -> some View {
        SettingsSection(Localization.labelGlyph, anchor: .symbol) {
            VStack(spacing: 8) {
                Picker(Localization.menuSymbol, selection: $symbolCatalog) {
                    Text(Localization.menuSymbol).tag(SymbolGridView.Catalog.symbols)
                    Text(Localization.menuEmoji).tag(SymbolGridView.Catalog.emojis)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                SymbolGridView(
                    catalog: symbolCatalog,
                    selected: model.symbol,
                    pickerSkinTone: model.pickerSkinTone,
                    // Clicking the selected cell toggles the symbol off, so
                    // its hover previews the removal, not the symbol
                    onHover: { item, hovering in
                        if model.symbol == item {
                            model.previewSymbolClear(hovering: hovering)
                        } else {
                            model.previewSymbol(item, hovering: hovering)
                        }
                    }
                ) { symbol in
                    // Toggle-off writes the "none" sentinel rather than a
                    // clear, so a template symbol cannot bleed back through
                    if let symbol {
                        model.setSymbol(symbol)
                    } else {
                        model.removeSymbol()
                    }
                }
            }
            .padding(.horizontal, Layout.settingsRowHorizontalPadding)
            .padding(.vertical, Layout.settingsRowVerticalPadding)
            if symbolCatalog == .emojis || rules.symbolIsEmoji {
                SettingsRowDivider()
                SettingsControlRow(anchor: .skinTone) {
                    SkinToneRow(
                        selected: rules.symbolIsEmoji ? model.skinTone : model.pickerSkinTone,
                        // Without an emoji set, a tone changes no icon, so
                        // there is nothing to preview, matching the click path
                        onHover: rules.symbolIsEmoji
                            ? { model.previewSkinTone($0, hovering: $1) }
                            : nil
                    ) { tone in
                        model.setPickerSkinTone(tone)
                        if rules.symbolIsEmoji {
                            model.setSkinTone(tone)
                        }
                    }
                }
            }
        }
        .onAppear {
            if rules.symbolIsEmoji {
                symbolCatalog = .emojis
            }
        }
        // Emoji is not the default catalog, so a link naming it has to switch
        // the picker over rather than only pointing at the section. Skin tone
        // goes further: its row exists only while the emoji catalog is up.
        .onChange(of: highlighter?.anchor) { _, anchor in
            switch anchor {
            case .emoji, .skinTone:
                symbolCatalog = .emojis
            case .symbol:
                symbolCatalog = .symbols
            default:
                break
            }
        }
    }

    // MARK: - Colors

    private func colorsSection(_ rules: ClearCellRules) -> some View {
        let defaults = IconColors.filledColors(darkMode: model.darkMode)
        return SettingsSection(Localization.menuColor) {
            if rules.symbolIsActive, !rules.symbolIsEmoji {
                SettingsRow(icon: "burst.fill", anchor: .symbolColor) {
                    // The "(Foreground)" qualifier only earns its place when
                    // a background row is shown alongside
                    Text(
                        rules.symbolBackgroundVisible
                            ? Localization.labelSymbolForeground
                            : Localization.labelSymbol
                    )
                } control: {
                    SwatchRow(
                        currentColor: model.colors?.symbol,
                        showsClearCell: rules.showsSymbolClear,
                        onSelect: { model.setSymbolColor($0) },
                        onClear: { model.setSymbolColor(.clear) },
                        onCustom: {
                            colorPanel.show(
                                currentColor: model.colors?.symbol ?? defaults.foreground
                            ) { model.setSymbolColor($0) }
                        },
                        onHoverSelect: { model.previewSymbolColor($0, hovering: $1) },
                        onHoverClear: { model.previewSymbolColor(.clear, hovering: $0) }
                    )
                }
                SettingsRowDivider()
            }
            if rules.symbolBackgroundVisible {
                SettingsRow(icon: "burst", anchor: .symbolBackground) {
                    Text(Localization.labelSymbolBackground)
                } control: {
                    SwatchRow(
                        currentColor: model.colors?.symbolBackground,
                        showsClearCell: rules.showsSymbolBackgroundClear,
                        onSelect: { model.setSymbolBackgroundColor($0) },
                        onClear: { model.clearSymbolBackgroundColor() },
                        onCustom: {
                            colorPanel.show(
                                currentColor: model.colors?.symbolBackground ?? defaults.background
                            ) { model.setSymbolBackgroundColor($0) }
                        },
                        onHoverSelect: { model.previewSymbolBackgroundColor($0, hovering: $1) },
                        onHoverClear: { model.previewSymbolBackgroundClear(hovering: $0) }
                    )
                }
                SettingsRowDivider()
            }
            if !rules.symbolAlone {
                SettingsRow(icon: "square.2.layers.3d.top.filled", anchor: .foregroundColor) {
                    Text(foregroundTitle(rules))
                } control: {
                    SwatchRow(
                        currentColor: model.colors?.foreground,
                        showsClearCell: rules.showsForegroundClear,
                        onSelect: { model.setForegroundColor($0) },
                        onClear: { model.setForegroundColor(.clear) },
                        onCustom: {
                            colorPanel.show(
                                currentColor: model.colors?.foreground ?? defaults.foreground
                            ) { model.setForegroundColor($0) }
                        },
                        onHoverSelect: { model.previewForegroundColor($0, hovering: $1) },
                        onHoverClear: { model.previewForegroundColor(.clear, hovering: $0) }
                    )
                }
                // Transparent styles have no background to color
                if rules.styleForColors != .transparent {
                    SettingsRowDivider()
                    SettingsRow(icon: "square.2.layers.3d.bottom.filled", anchor: .backgroundColor) {
                        Text(
                            rules.hasLabel
                                ? Localization.labelLabelBackground
                                : Localization.labelNumberBackground
                        )
                    } control: {
                        SwatchRow(
                            currentColor: model.colors?.background,
                            showsClearCell: rules.showsBackgroundClear,
                            onSelect: { model.setBackgroundColor($0) },
                            onClear: { model.setBackgroundColor(.clear) },
                            onCustom: {
                                colorPanel.show(
                                    currentColor: model.colors?.background ?? defaults.background
                                ) { model.setBackgroundColor($0) }
                            },
                            onHoverSelect: { model.previewBackgroundColor($0, hovering: $1) },
                            onHoverClear: { model.previewBackgroundColor(.clear, hovering: $0) }
                        )
                    }
                }
                SettingsRowDivider()
                SettingsRow(
                    icon: "arrow.left.arrow.right",
                    subtitle: Localization.tipInvertColors,
                    anchor: .invertColors
                ) {
                    Text(Localization.actionInvertColors)
                } control: {
                    Button(Localization.buttonSwap) {
                        model.invertColors()
                    }
                    .onHover { hovering in
                        model.previewInvertedColors(hovering: hovering)
                    }
                }
            }
        }
    }

    /// Foreground headers name what they color: the label when one is set,
    /// otherwise the number; transparent styles drop the suffix because
    /// there is no background counterpart.
    private func foregroundTitle(_ rules: ClearCellRules) -> String {
        if rules.styleForColors == .transparent {
            return rules.hasLabel ? Localization.menuLabel : Localization.labelNumber
        }
        return rules.hasLabel ? Localization.labelLabelForeground : Localization.labelNumberForeground
    }

    // MARK: - Badge

    private var badgeSection: some View {
        SettingsSection(Localization.menuBadge) {
            SettingsRow(icon: "tag", subtitle: Localization.tipBadgeInput, anchor: .badge) {
                Text(Localization.menuBadge)
            } control: {
                CommittingTextField(
                    placeholder: BadgeTemplate.spaceToken,
                    initialValue: model.badge?.character ?? "",
                    clearHelp: Localization.tipClearBadge,
                    fieldWidth: 44,
                    centered: true
                ) { model.setBadgeCharacter($0) }
            }
            .id("badge-\(entryIdentity)")
            SettingsRowDivider()
            badgePositionRow
        }
    }

    private var badgePositionRow: some View {
        let hasCharacter = !(model.badge?.character ?? "").isEmpty
        return SettingsRow(
            icon: "arrow.up.and.down.and.arrow.left.and.right",
            subtitle: Localization.tipBadgePosition,
            disabled: !hasCharacter,
            anchor: .badgePosition
        ) {
            Text(Localization.labelBadgePosition)
                .foregroundStyle(hasCharacter ? .primary : .tertiary)
        } control: {
            Picker(Localization.labelBadgePosition, selection: badgePositionBinding) {
                Image(systemName: "rectangle.inset.topleft.filled").tag(BadgePosition.topLeft)
                Image(systemName: "rectangle.inset.topright.filled").tag(BadgePosition.topRight)
                Image(systemName: "rectangle.inset.bottomleft.filled").tag(BadgePosition.bottomLeft)
                Image(systemName: "rectangle.inset.bottomright.filled").tag(BadgePosition.bottomRight)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
            .segmentHover(count: 4) { index, hovering in
                model.previewBadgePosition(Self.badgePositions[index], hovering: hovering)
            }
        }
    }

    /// Segment order of the badge position picker.
    private static let badgePositions: [BadgePosition] = [
        .topLeft, .topRight, .bottomLeft, .bottomRight,
    ]

    private var badgePositionBinding: Binding<BadgePosition> {
        Binding(
            get: { model.badge?.position ?? .topLeft },
            set: { model.setBadgePosition($0) }
        )
    }

    // MARK: - Font

    private var fontSection: some View {
        SettingsSection(Localization.labelFont) {
            SettingsRow(icon: "textformat", subtitle: Localization.tipFont, anchor: .font) {
                Text(Localization.labelFont)
            } control: {
                FontPickerButton(
                    current: model.font,
                    onHover: { model.previewFont($0, hovering: $1) },
                    onDismiss: { model.clearPreview() }
                ) { model.setFont($0) }
                Button {
                    model.clearFont()
                } label: {
                    Image(systemName: "arrow.counterclockwise")
                }
                .buttonStyle(.borderless)
                .disabled(model.font == nil)
                .help(Localization.buttonReset)
            }
        }
    }

    // MARK: - Sound

    private var soundSection: some View {
        SettingsSection(Localization.menuSound) {
            // A Space's sound plays on arrival at that Space; only the
            // template row edits the sound for every switch
            SettingsRow(
                icon: "speaker.wave.2",
                subtitle: model.isEditingDefaultStyle ? Localization.tipSound : Localization.tipSoundSpace,
                anchor: .sound
            ) {
                Text(Localization.menuSound)
            } control: {
                soundPicker
                    .labelsHidden()
            }
            SettingsRowDivider()
            SettingsRow(anchor: .customSounds) {
                EmptyView()
            } control: {
                Button(Localization.soundCustom) {
                    onOpenCustomSoundsFolder()
                }
            }
        }
    }

    private var soundPicker: some View {
        Picker(Localization.menuSound, selection: soundBinding) {
            if !model.isEditingDefaultStyle {
                Text("[\(Localization.labelDefault)]").tag(String?.none)
                Divider()
            }
            Text(Localization.soundNone).tag(String?.some(""))
            // The group headers only disambiguate when both groups exist;
            // with no user sounds the system list stands alone unlabeled
            if userSounds.isEmpty {
                Divider()
                ForEach(SoundCatalog.systemSounds, id: \.self) { sound in
                    Text(sound).tag(String?.some(sound))
                }
            } else {
                Section(Localization.soundUser) {
                    ForEach(userSounds, id: \.self) { sound in
                        Text(sound).tag(String?.some(sound))
                    }
                }
                Section(Localization.soundSystem) {
                    ForEach(SoundCatalog.systemSounds, id: \.self) { sound in
                        Text(sound).tag(String?.some(sound))
                    }
                }
            }
        }
    }

    /// The template row edits the live global default; a Space row edits the
    /// per-space override (nil = inherit). Selecting previews the effective
    /// sound.
    private var soundBinding: Binding<String?> {
        Binding(
            get: {
                model.isEditingDefaultStyle ? model.globalSoundName : model.spaceSound
            },
            set: { name in
                if model.isEditingDefaultStyle {
                    model.setGlobalSoundName(name ?? "")
                } else {
                    model.setSpaceSound(name)
                }
                let effective = name ?? model.globalSoundName
                guard !effective.isEmpty,
                      let sound = NSSound(named: NSSound.Name(effective))?.copy() as? NSSound
                else {
                    return
                }
                sound.play()
            }
        )
    }
}

// MARK: - FontPickerButton

/// A dropdown showing the entry's font family, opening a searchable list of
/// the installed families with each name rendered in its own typeface.
private struct FontPickerButton: View {
    let current: NSFont?
    /// Hover preview callback: the hovered family converted like a
    /// selection, and whether the pointer entered (true) or left (false)
    var onHover: ((NSFont, Bool) -> Void)?
    /// Called when the popover closes; a closing popover can swallow the
    /// hovered row's exit event, so the preview is dropped here instead
    var onDismiss: (() -> Void)?
    let onSelect: (NSFont) -> Void

    @State private var isPresented = false
    @State private var searchText = ""

    private static let systemFont = NSFont.boldSystemFont(ofSize: Layout.baseFontSize)

    var body: some View {
        Button {
            isPresented.toggle()
        } label: {
            HStack(spacing: 4) {
                // The system font's internal family name is not presentable
                Text(currentFamily ?? Localization.labelDefault)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
            }
        }
        .popover(isPresented: $isPresented, arrowEdge: .bottom) {
            familyList
        }
        .onChange(of: isPresented) { _, presented in
            if !presented {
                onDismiss?()
            }
        }
    }

    private var currentFamily: String? {
        current?.familyName
    }

    private var filteredFamilies: [String] {
        let families = NSFontManager.shared.availableFontFamilies
        guard !searchText.isEmpty else {
            return families
        }
        return families.filter { $0.localizedCaseInsensitiveContains(searchText) }
    }

    private var familyList: some View {
        VStack(spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField(Localization.search, text: $searchText)
                    .textFieldStyle(.plain)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color(nsColor: .quaternarySystemFill))
            )
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(filteredFamilies, id: \.self) { family in
                        familyRow(family)
                    }
                }
            }
        }
        .padding(10)
        .frame(width: 260, height: 320)
    }

    /// The family as selecting it would store it: converted from the
    /// current font so size and traits carry over.
    private func convertedFont(for family: String) -> NSFont {
        NSFontManager.shared.convert(current ?? Self.systemFont, toFamily: family)
    }

    private func familyRow(_ family: String) -> some View {
        let isSelected = family == currentFamily
        return Button {
            onSelect(convertedFont(for: family))
            isPresented = false
        } label: {
            HStack {
                Text(family)
                    .font(.custom(family, size: Layout.settingsRowFontSize))
                    .lineLimit(1)
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 10, weight: .semibold))
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .contentShape(Rectangle())
            .background(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(isSelected ? AnyShapeStyle(.selection.opacity(0.35)) : AnyShapeStyle(.clear))
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            onHover?(convertedFont(for: family), hovering)
        }
    }
}

// MARK: - CommittingTextField

/// A text field owning its edit buffer locally, pushing each change through
/// the given commit handler. The parent resets it via `.id` when the edited
/// entry changes, so normalization on write (trimming, truncation) never
/// fights the user's in-progress typing. Writes from elsewhere are adopted
/// while the field is unfocused, keeping the buffer in step with the store.
struct CommittingTextField: View {
    let placeholder: String
    let initialValue: String
    let clearHelp: String
    let fieldWidth: Double
    let centered: Bool
    let clamp: ((String) -> String)?
    let onChange: (String) -> Void

    @State private var text: String
    @FocusState private var isFocused: Bool

    init(
        placeholder: String,
        initialValue: String,
        clearHelp: String,
        fieldWidth: Double,
        centered: Bool = false,
        clamp: ((String) -> String)? = nil,
        onChange: @escaping (String) -> Void
    ) {
        self.placeholder = placeholder
        self.initialValue = initialValue
        self.clearHelp = clearHelp
        self.fieldWidth = fieldWidth
        self.centered = centered
        self.clamp = clamp
        self.onChange = onChange
        _text = State(initialValue: initialValue)
    }

    var body: some View {
        // The clear button sits outside the field: any control overlapping
        // the focused field editor keeps the I-beam cursor regardless of
        // its own cursor handling. The width applies to the field alone so
        // the button never squeezes it, and hiding rather than removing the
        // button keeps the layout stable as text appears and disappears.
        HStack(spacing: 4) {
            TextField(placeholder, text: $text)
                .textFieldStyle(.roundedBorder)
                .multilineTextAlignment(centered ? .center : .leading)
                .frame(width: fieldWidth)
                .focused($isFocused)
            Button {
                text = ""
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .arrowCursorOnHover()
            .help(clearHelp)
            .opacity(text.isEmpty ? 0 : 1)
            .disabled(text.isEmpty)
        }
        // Rejecting over-limit input here keeps the visible text equal to
        // what the model stores, which truncates on its own. The assignment
        // re-enters this handler with the clamped value, which then commits.
        .onChange(of: text) { _, newValue in
            let clamped = clamp?(newValue) ?? newValue
            guard clamped == newValue else {
                text = clamped
                return
            }
            // Adopting an external value assigns the buffer too, and the
            // store already holds what it assigned. Skipping that write also
            // keeps the adoption from echoing back as a change of its own.
            guard newValue != initialValue else {
                return
            }
            onChange(newValue)
        }
        // A write from outside this field - a settings reset, a backup
        // import, a scripting change - leaves the buffer holding text the
        // store no longer has, which the next keystroke would commit straight
        // back. Take the new value while the field is unfocused, so the swap
        // never lands under the user's typing.
        .onChange(of: initialValue) { _, newValue in
            guard !isFocused, text != newValue else {
                return
            }
            text = newValue
        }
    }
}

// MARK: - Cursor helpers

extension View {
    /// Shows the arrow cursor while hovering a control embedded in a text
    /// field, which would otherwise keep the field's I-beam cursor.
    func arrowCursorOnHover() -> some View {
        overlay(ArrowCursorArea())
    }

    /// Reports hover per segment of an equal-width segmented control.
    /// `onHover` receives the segment index and whether the pointer just
    /// entered (true) or left (false) it.
    func segmentHover(count: Int, _ onHover: @escaping (Int, Bool) -> Void) -> some View {
        overlay(SegmentHoverArea(count: count, onHover: onHover))
    }
}

/// A segmented `Picker` bridges to one `NSSegmentedControl`, so its segments
/// are not SwiftUI views and `.onHover` cannot see them. Tracking-area
/// events are delivered geometrically, independent of hit testing, so this
/// overlay divides its own bounds into equal segments and reports which one
/// the pointer is over while staying transparent to clicks.
private struct SegmentHoverArea: NSViewRepresentable {
    let count: Int
    let onHover: (Int, Bool) -> Void

    private final class HoverView: NSView {
        var count = 1
        var onHover: ((Int, Bool) -> Void)?
        private var hoveredIndex: Int?

        override func updateTrackingAreas() {
            super.updateTrackingAreas()
            trackingAreas.forEach(removeTrackingArea)
            addTrackingArea(NSTrackingArea(
                rect: .zero,
                options: [.mouseEnteredAndExited, .mouseMoved, .activeInKeyWindow, .inVisibleRect],
                owner: self
            ))
        }

        override func hitTest(_: CGPoint) -> NSView? {
            nil
        }

        override func mouseEntered(with event: NSEvent) {
            update(with: event)
        }

        override func mouseMoved(with event: NSEvent) {
            update(with: event)
        }

        override func mouseExited(with _: NSEvent) {
            setHovered(nil)
        }

        private func update(with event: NSEvent) {
            guard bounds.width > 0, count >= 1 else {
                return
            }
            let x = convert(event.locationInWindow, from: nil).x
            var index = min(max(Int(x / (bounds.width / Double(count))), 0), count - 1)
            if userInterfaceLayoutDirection == .rightToLeft {
                index = count - 1 - index
            }
            setHovered(index)
        }

        /// Enter for the new segment goes out before exit for the old one,
        /// so the model's match gate treats the old exit as stale and the
        /// preview never drops between two segments.
        private func setHovered(_ index: Int?) {
            guard index != hoveredIndex else {
                return
            }
            let previous = hoveredIndex
            hoveredIndex = index
            if let index {
                onHover?(index, true)
            }
            if let previous {
                onHover?(previous, false)
            }
        }
    }

    func makeNSView(context _: Context) -> NSView {
        let view = HoverView()
        view.count = count
        view.onHover = onHover
        return view
    }

    func updateNSView(_ view: NSView, context _: Context) {
        guard let view = view as? HoverView else {
            return
        }
        view.count = count
        view.onHover = onHover
    }
}

/// The field editor owns an I-beam cursor rect, and overlapping tracking-area
/// callbacks race with undefined order, so setting the cursor from hover
/// events cannot reliably win. A nested AppKit cursor rect is the native
/// arbitration mechanism; this view claims one for the arrow while staying
/// transparent to clicks.
private struct ArrowCursorArea: NSViewRepresentable {
    private final class CursorView: NSView {
        override func resetCursorRects() {
            super.resetCursorRects()
            // The intersection is null while the view is fully clipped, such
            // as during the pane's initial layout, and addCursorRect throws
            // on a null rect
            let rect = bounds.intersection(visibleRect)
            guard !rect.isEmpty else {
                return
            }
            addCursorRect(rect, cursor: .arrow)
        }

        override func hitTest(_: CGPoint) -> NSView? {
            nil
        }
    }

    func makeNSView(context _: Context) -> NSView {
        CursorView()
    }

    func updateNSView(_: NSView, context _: Context) {}
}
