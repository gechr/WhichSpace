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
            userSounds = await Task.detached(priority: .userInitiated) {
                SoundCatalog.discoverUserSounds()
            }.value
        }
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
            SettingsRow(icon: "character.textbox", subtitle: Localization.tipLabelInput) {
                Text(Localization.menuLabel)
            } control: {
                CommittingTextField(
                    placeholder: LabelTemplate.spaceToken,
                    initialValue: model.label ?? "",
                    clearHelp: Localization.tipClearLabel
                ) { model.setLabel($0) }
                    .frame(width: 140)
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
                    usesLabelTitles: true
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
        SettingsRow(icon: "arrow.left.and.right") {
            Text(Localization.labelSymbolPosition)
        } control: {
            Picker(Localization.labelSymbolPosition, selection: symbolPositionBinding) {
                Text(Localization.labelLeft).tag(SymbolPosition.left)
                Text(Localization.labelRight).tag(SymbolPosition.right)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
        }
        // Wrap only applies when the label shape can stretch around the
        // symbol; other shapes always render the side-by-side layout
        if rules.labelStyleCanWrap {
            SettingsRowDivider()
            SettingsRow(icon: "rectangle.dashed") {
                Text(Localization.labelSymbolWrap)
            } control: {
                Picker(Localization.labelSymbolWrap, selection: symbolWrapBinding) {
                    Text(Localization.labelInside).tag(SymbolWrap.inside)
                    Text(Localization.labelOutside).tag(SymbolWrap.outside)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
            }
        }
        SettingsRowDivider()
        SettingsSliderRow(
            title: Localization.menuPadding,
            value: symbolGapBinding,
            range: Layout.symbolGapScaleRange,
            defaultValue: Layout.defaultSymbolGapScale,
            icon: "arrow.left.and.right"
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
        SettingsSection(Localization.menuNumber) {
            StyleGridView(
                styles: IconStyle.allCases,
                // A symbol replaces the number entirely, so no style reads
                // as active while one is set
                selected: rules.symbolIsActive ? nil : model.iconStyle,
                previewNumber: previewNumber,
                customColors: model.colors,
                darkMode: model.darkMode
            ) { model.setIconStyle($0) }
                .padding(.horizontal, Layout.settingsRowHorizontalPadding)
                .padding(.vertical, Layout.settingsRowVerticalPadding)
        }
    }

    // MARK: - Glyph

    private func glyphSection(_ rules: ClearCellRules) -> some View {
        SettingsSection(Localization.labelGlyph) {
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
                    pickerSkinTone: model.pickerSkinTone
                ) { model.setSymbol($0) }
            }
            .padding(.horizontal, Layout.settingsRowHorizontalPadding)
            .padding(.vertical, Layout.settingsRowVerticalPadding)
            if symbolCatalog == .emojis || rules.symbolIsEmoji {
                SettingsRowDivider()
                SettingsRow(icon: "hand.wave") {
                    Text(Localization.labelSkinTone)
                } control: {
                    SkinToneRow(selected: rules.symbolIsEmoji ? model.skinTone : model.pickerSkinTone) { tone in
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
    }

    // MARK: - Colors

    private func colorsSection(_ rules: ClearCellRules) -> some View {
        let defaults = IconColors.filledColors(darkMode: model.darkMode)
        return SettingsSection(Localization.menuColor) {
            if rules.symbolIsActive, !rules.symbolIsEmoji {
                SettingsRow(icon: "burst.fill") {
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
                        }
                    )
                }
                SettingsRowDivider()
            }
            if rules.symbolBackgroundVisible {
                SettingsRow(icon: "burst") {
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
                        }
                    )
                }
                SettingsRowDivider()
            }
            if !rules.symbolAlone {
                SettingsRow(icon: "square.2.layers.3d.top.filled") {
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
                        }
                    )
                }
                // Transparent styles have no background to color
                if rules.styleForColors != .transparent {
                    SettingsRowDivider()
                    SettingsRow(icon: "square.2.layers.3d.bottom.filled") {
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
                            }
                        )
                    }
                }
                SettingsRowDivider()
                SettingsRow(icon: "arrow.left.arrow.right", subtitle: Localization.tipInvertColors) {
                    Text(Localization.actionInvertColors)
                } control: {
                    Button(Localization.buttonSwap) {
                        model.invertColors()
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
            SettingsRow(icon: "tag", subtitle: Localization.tipBadgeInput) {
                Text(Localization.menuBadge)
            } control: {
                CommittingTextField(
                    placeholder: BadgeTemplate.spaceToken,
                    initialValue: model.badge?.character ?? "",
                    clearHelp: Localization.tipClearBadge
                ) { model.setBadgeCharacter($0) }
                    .frame(width: 44)
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
            disabled: !hasCharacter
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
        }
    }

    private var badgePositionBinding: Binding<BadgePosition> {
        Binding(
            get: { model.badge?.position ?? .topLeft },
            set: { model.setBadgePosition($0) }
        )
    }

    // MARK: - Font

    private var fontSection: some View {
        SettingsSection(Localization.labelFont) {
            SettingsRow(icon: "textformat", subtitle: Localization.tipFont) {
                Text(Localization.labelFont)
            } control: {
                FontPickerButton(current: model.font) { model.setFont($0) }
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
            SettingsRow(icon: "speaker.wave.2", subtitle: Localization.tipSound) {
                Text(Localization.menuSound)
            } control: {
                soundPicker
                    .labelsHidden()
            }
            SettingsRowDivider()
            SettingsRow {
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
            if !userSounds.isEmpty {
                Divider()
                ForEach(userSounds, id: \.self) { sound in
                    Text(sound).tag(String?.some(sound))
                }
            }
            Divider()
            ForEach(SoundCatalog.systemSounds, id: \.self) { sound in
                Text(sound).tag(String?.some(sound))
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

    private func familyRow(_ family: String) -> some View {
        let isSelected = family == currentFamily
        return Button {
            // Converting preserves the current size and traits, so picking
            // a family never resets a chosen weight
            let base = current ?? Self.systemFont
            onSelect(NSFontManager.shared.convert(base, toFamily: family))
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
    }
}

// MARK: - CommittingTextField

/// A text field owning its edit buffer locally, pushing each change through
/// the given commit handler. The parent resets it via `.id` when the edited
/// entry changes, so normalization on write (trimming, truncation) never
/// fights the user's in-progress typing.
struct CommittingTextField: View {
    let placeholder: String
    let initialValue: String
    let clearHelp: String
    let onChange: (String) -> Void

    @State private var text: String

    init(
        placeholder: String,
        initialValue: String,
        clearHelp: String,
        onChange: @escaping (String) -> Void
    ) {
        self.placeholder = placeholder
        self.initialValue = initialValue
        self.clearHelp = clearHelp
        self.onChange = onChange
        _text = State(initialValue: initialValue)
    }

    var body: some View {
        TextField(placeholder, text: $text)
            .textFieldStyle(.roundedBorder)
            .overlay(alignment: .trailing) {
                if !text.isEmpty {
                    Button {
                        text = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .padding(.trailing, 4)
                    .help(clearHelp)
                }
            }
            .onChange(of: text) { _, newValue in
                onChange(newValue)
            }
    }
}
