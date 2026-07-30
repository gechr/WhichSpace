import AppKit
import Defaults

/// Binding layer between the Spaces pane and `SpacePreferences`.
///
/// Holds the edited (space, display) selection so any Space on any display
/// can be styled without switching to it; every read and write routes
/// through the existing `forSpace:display:` accessors, which decide between
/// shared and per-display storage from `uniqueIconsPerDisplay`. The pinned
/// "Default Style" entry edits the space-0 template with `display: nil`,
/// matching how `saveDefaultStyle` stores it.
///
/// Follows the `SettingsModel` freshness pattern: reads register a SwiftUI
/// dependency on `tick`, writes go through the store (bumping
/// `mutationCount`, so the status bar refreshes via the existing
/// `Defaults.updates` observers) and then bump `tick`.
@MainActor
@Observable
final class SpaceEditorModel {
    /// Which entry of the Space list is being edited.
    enum Selection: Equatable, Hashable {
        /// The space-0 template applied to newly created Spaces
        case defaultStyle
        /// A 1-based fullscreen-inclusive position on the selected display,
        /// the same key `SpacePreferences` uses everywhere
        case space(Int)
    }

    /// Bumped on every write and on observed external changes; reads touch
    /// it to register a SwiftUI observation dependency
    private(set) var tick = 0

    var selectedDisplayID: String?
    var selection: Selection

    @ObservationIgnored private let appState: AppState
    @ObservationIgnored private let store: DefaultsStore
    @ObservationIgnored private let confirmAction: ConfirmAction
    @ObservationIgnored private var observationTask: Task<Void, Never>?
    @ObservationIgnored private let customNamesURL: URL
    @ObservationIgnored private var customNamesCache: [String: String] = [:]
    @ObservationIgnored private var customNamesModified: Date?

    init(
        appState: AppState,
        confirmAction: @escaping ConfirmAction = {
            ConfirmationAlert(message: $0, detail: $1, confirmTitle: $2, isDestructive: $3).runModal()
        },
        customNamesURL: URL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Containers/com.alexbeals.spacesrenamer/com.alexbeals.spacesrenamer.plist")
    ) {
        self.appState = appState
        store = appState.store
        self.confirmAction = confirmAction
        self.customNamesURL = customNamesURL
        selectedDisplayID = appState.currentDisplayID
        selection = .space(max(appState.currentSpace, 1))
    }

    // MARK: - Editing Coordinates

    /// The preference key of the edited entry (0 = default-style template).
    var editingSpace: Int {
        switch selection {
        case .defaultStyle:
            SpacePreferences.defaultStyleSpace
        case let .space(number):
            number
        }
    }

    /// The display the edited entry belongs to. The template is display-less
    /// so it stays in the shared maps regardless of `uniqueIconsPerDisplay`.
    var editingDisplay: String? {
        selection == .defaultStyle ? nil : selectedDisplayID
    }

    var isEditingDefaultStyle: Bool {
        selection == .defaultStyle
    }

    // MARK: - Space List

    var displays: [DisplaySpaceInfo] {
        appState.allDisplaysSpaceInfo
    }

    /// Entries of the selected display, as (1-based position, entry) pairs,
    /// padded with nil entries up to the per-display Space limit so Spaces
    /// can be styled before they are created.
    var spaceEntries: [(number: Int, entry: SpaceEntry?)] {
        let info = displays.first { $0.displayID == selectedDisplayID }
        let entries = info?.entries ?? appState.allSpaceEntries
        let real = entries.enumerated().map { (number: $0.offset + 1, entry: SpaceEntry?($0.element)) }
        guard entries.count < Layout.maxSpacesPerDisplay else {
            return real
        }
        let placeholders = ((entries.count + 1) ... Layout.maxSpacesPerDisplay)
            .map { (number: $0, entry: SpaceEntry?.none) }
        return real + placeholders
    }

    /// The number of Spaces that exist right now on the selected display;
    /// list entries beyond it are placeholders for future Spaces.
    var existingSpaceCount: Int {
        let info = displays.first { $0.displayID == selectedDisplayID }
        return (info?.entries ?? appState.allSpaceEntries).count
    }

    /// Keeps the selection valid when the display changes or Spaces close.
    func normalizeSelection() {
        if selectedDisplayID == nil || !displays.contains(where: { $0.displayID == selectedDisplayID }) {
            selectedDisplayID = appState.currentDisplayID
        }
        if case let .space(number) = selection, !spaceEntries.contains(where: { $0.number == number }) {
            selection = .space(1)
        }
    }

    /// The user-visible number of the edited Space, used by style previews.
    var editingDisplayNumber: Int {
        guard case let .space(number) = selection else {
            return 1
        }
        guard let info = displays.first(where: { $0.displayID == selectedDisplayID }),
              info.entries.indices.contains(number - 1)
        else {
            return number
        }
        let entry = info.entries[number - 1]
        if store.localSpaceNumbers {
            return entry.regularIndex ?? number
        }
        return StatusBarRenderer.globalIndex(entry: entry, globalStartIndex: info.globalStartIndex)
    }

    // MARK: - Space Names

    /// The sidebar title for a Space list entry: the custom name a Space
    /// renaming tool stored for the Space's UUID when present, otherwise a
    /// localized "Desktop N" fallback numbered like Mission Control.
    /// Fullscreen entries carry no desktop number and stay untitled.
    /// Placeholder entries extrapolate the desktop number new Spaces would
    /// get - Mission Control appends new desktops after the existing ones.
    func spaceName(for candidate: (number: Int, entry: SpaceEntry?)) -> String? {
        _ = tick
        guard let entry = candidate.entry else {
            let info = displays.first { $0.displayID == selectedDisplayID }
            let entries = info?.entries ?? appState.allSpaceEntries
            let regularCount = entries.compactMap(\.regularIndex).max() ?? 0
            let number = regularCount + candidate.number - entries.count
            return String(format: Localization.labelDesktopNumber, number)
        }
        if let uuid = entry.uuid, let custom = customNames()[uuid] {
            let trimmed = custom.trimmingCharacters(in: .whitespaces)
            if !trimmed.isEmpty {
                return Self.truncatedName(trimmed)
            }
        }
        guard let regularIndex = entry.regularIndex else {
            return nil
        }
        return String(format: Localization.labelDesktopNumber, regularIndex)
    }

    /// Custom names are capped so one long name cannot stretch the list.
    /// Built-in "Desktop N" fallbacks bypass this - cutting their tail
    /// would drop the number that tells the rows apart.
    private static func truncatedName(_ name: String) -> String {
        guard name.count > Layout.settingsSpaceNameMaxLength else {
            return name
        }
        return name.prefix(Layout.settingsSpaceNameMaxLength)
            .trimmingCharacters(in: .whitespaces) + "…"
    }

    /// Names live under the tool's "spaces_renaming" key, keyed by Space
    /// UUID. Reread only when the plist's modification date changes.
    private func customNames() -> [String: String] {
        let modified = (try? customNamesURL.resourceValues(forKeys: [.contentModificationDateKey]))?
            .contentModificationDate
        if modified != customNamesModified {
            customNamesModified = modified
            customNamesCache = NSDictionary(contentsOf: customNamesURL)?["spaces_renaming"]
                as? [String: String] ?? [:]
        }
        return customNamesCache
    }

    // MARK: - Icons

    /// The edited entry's icon, rendered exactly as the status bar would.
    func icon(sizeScale: Double = 100) -> NSImage {
        _ = tick
        return appState.renderer.settingsIcon(
            forSpace: editingSpace, display: editingDisplay, sizeScale: sizeScale
        )
    }

    /// A list entry's icon at status bar rendering size.
    func listIcon(for selection: Selection) -> NSImage {
        _ = tick
        switch selection {
        case .defaultStyle:
            return appState.renderer.settingsIcon(
                forSpace: SpacePreferences.defaultStyleSpace, display: nil
            )
        case let .space(number):
            return appState.renderer.settingsIcon(forSpace: number, display: selectedDisplayID)
        }
    }

    // MARK: - Reads

    var darkMode: Bool {
        appState.darkModeEnabled
    }

    var sizeScale: Double {
        _ = tick
        return store.sizeScale
    }

    var symbol: String? {
        _ = tick
        return SpacePreferences.symbol(forSpace: editingSpace, display: editingDisplay, store: store)
    }

    var iconStyle: IconStyle {
        _ = tick
        return SpacePreferences.iconStyle(forSpace: editingSpace, display: editingDisplay, store: store) ?? .square
    }

    var label: String? {
        _ = tick
        return SpacePreferences.label(forSpace: editingSpace, display: editingDisplay, store: store)
    }

    var labelStyle: IconStyle {
        _ = tick
        return SpacePreferences.labelStyle(forSpace: editingSpace, display: editingDisplay, store: store) ?? .square
    }

    var colors: SpaceColors? {
        _ = tick
        return SpacePreferences.colors(forSpace: editingSpace, display: editingDisplay, store: store)
    }

    var font: NSFont? {
        _ = tick
        return SpacePreferences.font(forSpace: editingSpace, display: editingDisplay, store: store)?.font
    }

    var badge: SpaceBadge? {
        _ = tick
        return SpacePreferences.badge(forSpace: editingSpace, display: editingDisplay, store: store)
    }

    var skinTone: SkinTone {
        _ = tick
        return SpacePreferences.skinTone(forSpace: editingSpace, display: editingDisplay, store: store) ?? .default
    }

    /// The global picker tone used to render the emoji grid; per-Space tones
    /// are written on selection.
    var pickerSkinTone: SkinTone {
        _ = tick
        return store.emojiPickerSkinTone
    }

    func setPickerSkinTone(_ tone: SkinTone) {
        store.emojiPickerSkinTone = tone
        tick += 1
    }

    var symbolGap: Double {
        _ = tick
        return SpacePreferences.symbolGap(forSpace: editingSpace, display: editingDisplay, store: store)
            ?? Layout.defaultSymbolGapScale
    }

    var symbolPosition: SymbolPosition {
        _ = tick
        return SpacePreferences.symbolPosition(forSpace: editingSpace, display: editingDisplay, store: store) ?? .left
    }

    var symbolWrap: SymbolWrap {
        _ = tick
        return SpacePreferences.symbolWrap(forSpace: editingSpace, display: editingDisplay, store: store) ?? .inside
    }

    /// The per-space sound override; nil = inherit the global default.
    var spaceSound: String? {
        _ = tick
        return SpacePreferences.sound(forSpace: editingSpace, display: editingDisplay, store: store)
    }

    /// The app-wide default sound, edited from the template row.
    var globalSoundName: String {
        _ = tick
        return store.soundName
    }

    /// Section visibility and clear-cell gating for the edited entry.
    var clearRules: ClearCellRules {
        _ = tick
        return ClearCellRules(forSpace: editingSpace, display: editingDisplay, store: store)
    }

    var hasDefaultStyle: Bool {
        _ = tick
        return SpacePreferences.hasDefaultStyle(store: store)
    }

    /// Whether a Space list entry carries any style of its own instead of
    /// following the default style template. Drives the list's indicator dot.
    func hasOwnStyle(for selection: Selection) -> Bool {
        _ = tick
        guard case let .space(number) = selection else {
            return false
        }
        return SpacePreferences.hasAnyPreference(
            forSpace: number, display: selectedDisplayID, store: store
        )
    }

    // MARK: - Writes

    /// Selecting a number style returns the entry to plain-number mode. The
    /// empty strings are explicit "none" sentinels rather than clears - a
    /// clear would fall back to the default style template, letting an
    /// inherited symbol or label bleed through the plain number.
    func setIconStyle(_ style: IconStyle) {
        SpacePreferences.setSymbol("", forSpace: editingSpace, display: editingDisplay, store: store)
        SpacePreferences.setLabel("", forSpace: editingSpace, display: editingDisplay, store: store)
        SpacePreferences.setIconStyle(style, forSpace: editingSpace, display: editingDisplay, store: store)
        tick += 1
    }

    /// Ignores leading/trailing whitespace; a whitespace-only label clears.
    /// Content beyond the shared template limit is truncated.
    func setLabel(_ label: String?) {
        let trimmed = label?.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolved = trimmed.flatMap { $0.isEmpty ? nil : LabelTemplate.truncate($0) }
        SpacePreferences.setLabel(resolved, forSpace: editingSpace, display: editingDisplay, store: store)
        tick += 1
    }

    func setLabelStyle(_ style: IconStyle) {
        SpacePreferences.setLabelStyle(style, forSpace: editingSpace, display: editingDisplay, store: store)
        tick += 1
    }

    /// Setting an emoji also records the current picker skin tone for the
    /// entry, so the icon matches the grid the user picked from.
    func setSymbol(_ symbol: String?) {
        SpacePreferences.setSymbol(symbol, forSpace: editingSpace, display: editingDisplay, store: store)
        if let symbol, symbol.containsEmoji {
            SpacePreferences.setSkinTone(
                store.emojiPickerSkinTone, forSpace: editingSpace, display: editingDisplay, store: store
            )
        }
        tick += 1
    }

    func setSkinTone(_ tone: SkinTone) {
        SpacePreferences.setSkinTone(tone, forSpace: editingSpace, display: editingDisplay, store: store)
        tick += 1
    }

    func setSymbolPosition(_ position: SymbolPosition) {
        SpacePreferences.setSymbolPosition(position, forSpace: editingSpace, display: editingDisplay, store: store)
        tick += 1
    }

    func setSymbolWrap(_ wrap: SymbolWrap) {
        SpacePreferences.setSymbolWrap(wrap, forSpace: editingSpace, display: editingDisplay, store: store)
        tick += 1
    }

    func setSymbolGap(_ gap: Double) {
        SpacePreferences.setSymbolGap(
            gap.clamped(to: Layout.symbolGapScaleRange),
            forSpace: editingSpace,
            display: editingDisplay,
            store: store
        )
        tick += 1
    }

    /// An empty character keeps the badge record so the position survives
    /// until a new character is entered; input beyond one character keeps
    /// the first.
    func setBadgeCharacter(_ character: String?) {
        let trimmed = character?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let single = String(trimmed.prefix(1))
        let position = badge?.position ?? .topLeft
        SpacePreferences.setBadge(
            SpaceBadge(character: single, position: position),
            forSpace: editingSpace,
            display: editingDisplay,
            store: store
        )
        tick += 1
    }

    /// Position applies only while a badge character exists.
    func setBadgePosition(_ position: BadgePosition) {
        let character = badge?.character ?? ""
        guard !character.isEmpty else {
            return
        }
        SpacePreferences.setBadge(
            SpaceBadge(character: character, position: position),
            forSpace: editingSpace,
            display: editingDisplay,
            store: store
        )
        tick += 1
    }

    func setFont(_ font: NSFont) {
        SpacePreferences.setFont(
            SpaceFont(font: font), forSpace: editingSpace, display: editingDisplay, store: store
        )
        tick += 1
    }

    func clearFont() {
        SpacePreferences.clearFont(forSpace: editingSpace, display: editingDisplay, store: store)
        tick += 1
    }

    /// nil clears the override so the Space inherits the global default.
    func setSpaceSound(_ name: String?) {
        SpacePreferences.setSound(name, forSpace: editingSpace, display: editingDisplay, store: store)
        tick += 1
    }

    func setGlobalSoundName(_ name: String) {
        store.soundName = name
        tick += 1
    }

    // MARK: - Colors

    private var defaultColors: (foreground: NSColor, background: NSColor) {
        IconColors.filledColors(darkMode: appState.darkModeEnabled)
    }

    func setForegroundColor(_ color: NSColor) {
        let current = colors
        setColors(SpaceColors(
            foreground: color,
            background: current?.background ?? defaultColors.background,
            symbol: current?.symbol,
            symbolBackground: current?.symbolBackground
        ))
    }

    func setBackgroundColor(_ color: NSColor) {
        let current = colors
        setColors(SpaceColors(
            foreground: current?.foreground ?? defaultColors.foreground,
            background: color,
            symbol: current?.symbol,
            symbolBackground: current?.symbolBackground
        ))
    }

    func setSymbolColor(_ color: NSColor) {
        let current = colors
        setColors(SpaceColors(
            foreground: current?.foreground ?? defaultColors.foreground,
            background: current?.background ?? defaultColors.background,
            symbol: color,
            symbolBackground: current?.symbolBackground
        ))
    }

    func setSymbolBackgroundColor(_ color: NSColor) {
        let current = colors
        setColors(SpaceColors(
            foreground: current?.foreground ?? defaultColors.foreground,
            background: current?.background ?? defaultColors.background,
            symbol: current?.symbol,
            symbolBackground: color
        ))
    }

    func clearSymbolBackgroundColor() {
        guard var current = colors else {
            return
        }
        current.symbolBackground = nil
        setColors(current)
    }

    func invertColors() {
        let current = colors ?? SpaceColors(
            foreground: defaultColors.foreground, background: defaultColors.background
        )
        setColors(current.inverted(for: combinedSymbolLayout))
    }

    private func setColors(_ colors: SpaceColors) {
        SpacePreferences.setColors(colors, forSpace: editingSpace, display: editingDisplay, store: store)
        tick += 1
    }

    /// The combined layout of the edited entry, driving color inversion of
    /// the symbol chip.
    private var combinedSymbolLayout: CombinedSymbolLayout? {
        guard let symbol, !symbol.containsEmoji, let label, !label.isEmpty else {
            return nil
        }
        return labelStyle.combinedSymbolLayout(for: symbolWrap)
    }

    // MARK: - Actions

    func copyToAllSpaces() {
        guard confirmAction(
            Localization.confirmCopyToThisDisplay,
            Localization.detailCopyToThisDisplay,
            Localization.buttonCopy,
            false
        ) else {
            return
        }
        for (number, _) in spaceEntries where number != editingSpace {
            SpacePreferences.copyPreferences(
                from: editingSpace,
                to: number,
                fromDisplay: editingDisplay,
                toDisplay: selectedDisplayID,
                store: store
            )
        }
        tick += 1
    }

    /// Copies the edited entry's preferences onto every Space of every
    /// display. Meaningful with per-display icons; shared storage collapses
    /// the display dimension on write.
    func copyToAllDisplays() {
        guard confirmAction(
            Localization.confirmCopyToAllDisplays,
            Localization.detailCopyToAllDisplays,
            Localization.buttonCopy,
            false
        ) else {
            return
        }
        for display in displays {
            for number in 1 ... max(display.entries.count, Layout.maxSpacesPerDisplay)
                where number != editingSpace || display.displayID != selectedDisplayID
            {
                SpacePreferences.copyPreferences(
                    from: editingSpace,
                    to: number,
                    fromDisplay: editingDisplay,
                    toDisplay: display.displayID,
                    store: store
                )
            }
        }
        tick += 1
    }

    /// Clears the edited entry's preferences (or the saved template when
    /// the Default Style entry is selected, with its own wording - the
    /// template is not a Space).
    func resetToDefault() {
        if isEditingDefaultStyle {
            guard confirmAction(
                Localization.confirmResetDefault,
                Localization.detailResetDefault,
                Localization.buttonReset,
                true
            ) else {
                return
            }
            SpacePreferences.clearDefaultStyle(store: store)
        } else {
            resetSpace(editingSpace)
            return
        }
        tick += 1
    }

    /// Clears one Space's own preferences after confirming, so it follows
    /// the default style again. Selects the Space first: the confirmation
    /// names "the current Space", and the reveal shows what is resetting.
    func resetSpace(_ number: Int) {
        selection = .space(number)
        guard confirmAction(
            Localization.confirmResetSpace,
            Localization.detailResetSpace,
            Localization.buttonReset,
            true
        ) else {
            return
        }
        SpacePreferences.clearPreferences(forSpace: number, display: selectedDisplayID, store: store)
        tick += 1
    }

    /// Clears every Space's preferences on every display, including the
    /// saved template and per-space sounds. Icon sizing, separator, and the
    /// global default sound stay untouched.
    func resetAllSpacesToDefault() {
        guard confirmAction(
            Localization.confirmResetAllSpaces,
            Localization.detailResetAllSpaces,
            Localization.buttonResetAll,
            true
        ) else {
            return
        }
        SpacePreferences.clearAll(store: store)
        tick += 1
    }

    /// Saves the edited Space's preferences as the template for new Spaces.
    func saveAsDefaultStyle() {
        guard !isEditingDefaultStyle else {
            return
        }
        guard confirmAction(
            Localization.confirmSetDefaultStyle,
            Localization.detailSetDefaultStyle,
            Localization.buttonOK,
            false
        ) else {
            return
        }
        SpacePreferences.saveDefaultStyle(fromSpace: editingSpace, display: editingDisplay, store: store)
        tick += 1
    }

    // MARK: - External Change Observation

    /// Starts re-rendering the pane on defaults changes made outside this
    /// model. Called when the settings window opens; stopped on close so the
    /// stream does not outlive the window.
    func startObserving() {
        stopObserving()
        let keys = store.allKeys
        observationTask = Task { [weak self] in
            for await _ in Defaults.updates(keys, initial: false) {
                self?.tick += 1
            }
        }
    }

    func stopObserving() {
        observationTask?.cancel()
        observationTask = nil
    }
}
