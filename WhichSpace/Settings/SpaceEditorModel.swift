import AppKit
import Defaults

/// Binding layer between the Spaces pane and `SpacePreferences`.
///
/// Holds the edited (space, display) selection so any Space on any display
/// can be styled without switching to it; every read and write routes
/// through the existing `forSpace:display:` accessors. A nil
/// `selectedDisplayID` is the "All" scope: edits land in the shared maps
/// and apply everywhere a display holds no override. The pinned "Default
/// Style" entry edits the space-0 template with `display: nil`, matching
/// how `saveDefaultStyle` stores it.
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
    /// it to register a SwiftUI observation dependency. Every bump also
    /// drops the hover preview: the committed state just changed, so a
    /// preview built against the old state is stale, and after a click on
    /// the hovered value the clear is visually a no-op anyway.
    private(set) var tick = 0 {
        didSet {
            clearPreview()
        }
    }

    /// The display whose overrides are edited; nil selects the "All"
    /// segment, editing the shared styles every display inherits.
    var selectedDisplayID: String? {
        didSet {
            clearPreview()
        }
    }

    var selection: Selection {
        didSet {
            clearPreview()
        }
    }

    /// Overrides applied to the pinned preview card while a candidate value
    /// is hovered; nil while no hover preview is active
    private(set) var hoverPreview: IconPreviewOverrides?

    /// A preview change waiting out the debounce: apply new overrides or
    /// restore the committed icon.
    private enum PendingPreview: Equatable {
        case apply(IconPreviewOverrides)
        case remove
    }

    /// The change waiting out the debounce; the latest hover event wins
    @ObservationIgnored private var pendingPreview: PendingPreview?
    @ObservationIgnored private(set) var previewApplyTask: Task<Void, Never>?
    @ObservationIgnored private let previewApplyDelay: Duration

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
        previewApplyDelay: Duration = .milliseconds(50),
        customNamesURL: URL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Containers/com.alexbeals.spacesrenamer/com.alexbeals.spacesrenamer.plist")
    ) {
        self.appState = appState
        store = appState.store
        self.confirmAction = confirmAction
        self.previewApplyDelay = previewApplyDelay
        self.customNamesURL = customNamesURL
        selectedDisplayID = appState.currentDisplayID
        selection = .space(max(appState.currentSpace, 1))
        normalizeSelection()
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

    /// The display the edited entry belongs to. The template is
    /// display-less so it always stays in the shared maps.
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

    /// The display whose Spaces the list shows: the selected one, or the
    /// primary display while "All" is selected, so the rows reflect one
    /// real arrangement rather than a cross-display concatenation.
    private var selectedDisplayInfo: DisplaySpaceInfo? {
        guard let selectedDisplayID else {
            return displays.first
        }
        return displays.first { $0.displayID == selectedDisplayID }
    }

    /// Entries of the shown display, as (1-based position, entry) pairs,
    /// padded with nil entries up to the per-display Space limit so Spaces
    /// can be styled before they are created.
    var spaceEntries: [(number: Int, entry: SpaceEntry?)] {
        let entries = selectedDisplayInfo?.entries ?? appState.allSpaceEntries
        let real = entries.enumerated().map { (number: $0.offset + 1, entry: SpaceEntry?($0.element)) }
        guard entries.count < Layout.maxSpacesPerDisplay else {
            return real
        }
        let placeholders = ((entries.count + 1) ... Layout.maxSpacesPerDisplay)
            .map { (number: $0, entry: SpaceEntry?.none) }
        return real + placeholders
    }

    /// The number of Spaces that exist right now on the shown display;
    /// list entries beyond it are placeholders for future Spaces.
    var existingSpaceCount: Int {
        (selectedDisplayInfo?.entries ?? appState.allSpaceEntries).count
    }

    /// Whether a list entry is the Space the user is on right now. Matched by
    /// CGS Space ID, which is unique across displays, so the marker follows
    /// the Space rather than a position and reads false throughout while
    /// another display is selected.
    func isCurrentSpace(_ candidate: (number: Int, entry: SpaceEntry?)) -> Bool {
        _ = tick
        return candidate.entry?.id == appState.currentSpaceID
    }

    /// The system name of a display, for example "Built-in Retina Display".
    /// Nil when no attached screen claims the UUID, leaving the picker's
    /// numbers to stand on their own.
    func displayName(for displayID: String?) -> String? {
        DisplayNameResolver.localizedName(for: displayID)
    }

    /// Keeps the selection valid when the display changes or Spaces close.
    /// A single display always edits the shared "All" scope - the picker is
    /// hidden, so a display-scoped override could never be told apart.
    func normalizeSelection() {
        if displays.count <= 1 {
            selectedDisplayID = nil
        } else if let selectedDisplayID,
                  !displays.contains(where: { $0.displayID == selectedDisplayID })
        {
            self.selectedDisplayID = appState.currentDisplayID
        }
        if case let .space(number) = selection, !spaceEntries.contains(where: { $0.number == number }) {
            selection = .space(1)
        }
    }

    /// Re-points the pane at the Space the user is on, so an opening window
    /// starts where they are rather than where they last edited.
    func prepareForShow() {
        selectedDisplayID = appState.currentDisplayID
        selection = .space(max(appState.currentSpace, 1))
        normalizeSelection()
    }

    /// The user-visible number of the edited Space, used by style previews.
    var editingDisplayNumber: Int {
        guard case let .space(number) = selection else {
            return 1
        }
        guard let info = selectedDisplayInfo else {
            return number
        }
        guard info.entries.indices.contains(number - 1) else {
            return StatusBarRenderer.placeholderNumber(
                atPosition: number,
                on: info,
                localNumbers: store.localSpaceNumbers
            )
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
            let entries = selectedDisplayInfo?.entries ?? appState.allSpaceEntries
            let regularCount = entries.compactMap(\.regularIndex).max() ?? 0
            let number = regularCount + candidate.number - entries.count
            return String(format: Localization.labelDesktopNumber, number)
        }
        if let custom = customSpaceName(for: entry) {
            return custom
        }
        guard let regularIndex = entry.regularIndex else {
            return nil
        }
        return String(format: Localization.labelDesktopNumber, regularIndex)
    }

    /// The Keyboard pane's globally numbered Desktop title. Regular Spaces
    /// are flattened across displays in the same order Mission Control uses;
    /// fullscreen Spaces do not consume a Desktop number.
    func globalDesktopName(for number: Int) -> String {
        _ = tick
        let entries = appState.allDisplaysSpaceInfo
            .flatMap(\.entries)
            .filter { $0.regularIndex != nil }
        if entries.indices.contains(number - 1),
           let custom = customSpaceName(for: entries[number - 1])
        {
            return custom
        }
        return String(format: Localization.labelDesktopNumber, number)
    }

    private func customSpaceName(for entry: SpaceEntry) -> String? {
        guard let uuid = entry.uuid, let custom = customNames()[uuid] else {
            return nil
        }
        let trimmed = custom.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else {
            return nil
        }
        return Self.truncatedName(trimmed)
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

    /// The edited entry's icon, rendered exactly as the status bar would,
    /// with any active hover preview applied. Only this render sees the
    /// preview; list icons keep showing committed state.
    func icon(sizeScale: Double = 100) -> NSImage {
        _ = tick
        return appState.renderer.settingsIcon(
            forSpace: editingSpace,
            display: editingDisplay,
            sizeScale: sizeScale,
            overrides: hoverPreview
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

    // MARK: - Hover Preview

    /// Applies or removes the hover preview for one candidate value. Each
    /// control passes its overrides with `hovering` from its hover events.
    /// Both directions go through the same debounce: a sweep across a grid,
    /// or content scrolling under a resting pointer, fires an enter/exit
    /// pair per cell crossed, and each event cancels the previous pending
    /// change. Only the cell the pointer settles on renders; every icon
    /// render in between would be a full uncached settings render.
    ///
    /// Every hover source shares the one pending slot, which assumes hover
    /// regions never overlap: at most one control is hovered at a time, so
    /// an exit always belongs to the current or a superseded hover. A
    /// nested or overlapping hover source would break that assumption -
    /// leaving and re-entering an inner region could remove the outer
    /// region's still-hovered preview.
    private func setPreview(_ overrides: IconPreviewOverrides, hovering: Bool) {
        if hovering {
            schedulePreview(.apply(overrides))
        } else {
            removePreview(overrides)
        }
    }

    /// Debounces a preview change; the latest hover event replaces a
    /// pending one and only the survivor mutates `hoverPreview`.
    private func schedulePreview(_ change: PendingPreview) {
        pendingPreview = change
        previewApplyTask?.cancel()
        let delay = previewApplyDelay
        previewApplyTask = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled, let self, let pending = pendingPreview else {
                return
            }
            pendingPreview = nil
            switch pending {
            case let .apply(overrides):
                hoverPreview = overrides
            case .remove:
                hoverPreview = nil
            }
            previewApplyTask = nil
        }
    }

    /// Handles a hover exit. A stale exit from a superseded cell is
    /// ignored: SwiftUI does not guarantee exit/enter ordering between
    /// neighboring cells. A removal is debounced like an apply, so an
    /// enter that follows within the delay supersedes it and the committed
    /// icon never flashes between two cells.
    private func removePreview(_ overrides: IconPreviewOverrides) {
        switch pendingPreview {
        case let .apply(pending) where pending == overrides:
            // The pointer left before the debounce fired; nothing applied
            // for this hover, so there is nothing to restore unless an
            // earlier preview is still showing
            cancelPendingPreview()
            if hoverPreview != nil {
                schedulePreview(.remove)
            }
        case .apply, .remove:
            // A newer hover or removal owns the pending slot
            break
        case nil:
            if hoverPreview == overrides {
                schedulePreview(.remove)
            }
        }
    }

    /// Drops any active or pending hover preview, restoring the committed
    /// icon.
    func clearPreview() {
        cancelPendingPreview()
        if hoverPreview != nil {
            hoverPreview = nil
        }
    }

    private func cancelPendingPreview() {
        previewApplyTask?.cancel()
        previewApplyTask = nil
        pendingPreview = nil
    }

    func previewIconStyle(_ style: IconStyle, hovering: Bool) {
        setPreview(IconPreviewOverrides(style: style), hovering: hovering)
    }

    func previewLabelStyle(_ style: IconStyle, hovering: Bool) {
        setPreview(IconPreviewOverrides(labelStyle: style), hovering: hovering)
    }

    /// Previews an emoji with the picker skin tone, as `setSymbol` records it.
    func previewSymbol(_ symbol: String, hovering: Bool) {
        setPreview(
            IconPreviewOverrides(
                skinTone: symbol.containsEmoji ? store.emojiPickerSkinTone : nil,
                symbol: symbol
            ),
            hovering: hovering
        )
    }

    func previewSkinTone(_ tone: SkinTone, hovering: Bool) {
        setPreview(IconPreviewOverrides(skinTone: tone), hovering: hovering)
    }

    /// Previews removing the symbol, which clicking the selected symbol
    /// cell commits.
    func previewSymbolClear(hovering: Bool) {
        setPreview(IconPreviewOverrides(clearSymbol: true), hovering: hovering)
    }

    /// Position previews apply only while a badge character exists,
    /// matching `setBadgePosition`.
    func previewBadgePosition(_ position: BadgePosition, hovering: Bool) {
        guard !(badge?.character ?? "").isEmpty else {
            return
        }
        setPreview(IconPreviewOverrides(badgePosition: position), hovering: hovering)
    }

    func previewSymbolPosition(_ position: SymbolPosition, hovering: Bool) {
        setPreview(IconPreviewOverrides(symbolPosition: position), hovering: hovering)
    }

    func previewSymbolWrap(_ wrap: SymbolWrap, hovering: Bool) {
        setPreview(IconPreviewOverrides(symbolWrap: wrap), hovering: hovering)
    }

    func previewForegroundColor(_ color: NSColor, hovering: Bool) {
        setPreview(IconPreviewOverrides(foreground: color), hovering: hovering)
    }

    func previewBackgroundColor(_ color: NSColor, hovering: Bool) {
        setPreview(IconPreviewOverrides(background: color), hovering: hovering)
    }

    func previewSymbolColor(_ color: NSColor, hovering: Bool) {
        setPreview(IconPreviewOverrides(symbolColor: color), hovering: hovering)
    }

    func previewSymbolBackgroundColor(_ color: NSColor, hovering: Bool) {
        setPreview(IconPreviewOverrides(symbolBackground: color), hovering: hovering)
    }

    func previewSymbolBackgroundClear(hovering: Bool) {
        setPreview(IconPreviewOverrides(clearSymbolBackground: true), hovering: hovering)
    }

    /// Previews the swap the invert button would commit.
    func previewInvertedColors(hovering: Bool) {
        let current = colors ?? SpaceColors(
            foreground: defaultColors.foreground, background: defaultColors.background
        )
        setPreview(
            IconPreviewOverrides(colors: current.inverted(for: combinedSymbolLayout)),
            hovering: hovering
        )
    }

    func previewFont(_ font: NSFont, hovering: Bool) {
        setPreview(IconPreviewOverrides(font: font), hovering: hovering)
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

    /// Whether a Space list entry carries any style at the edited scope -
    /// shared values under "All", that display's overrides otherwise.
    /// Drives the list's indicator dot and its revert button, which clears
    /// exactly this scope.
    func hasOwnStyle(for selection: Selection) -> Bool {
        _ = tick
        guard case let .space(number) = selection else {
            return false
        }
        return SpacePreferences.hasAnyScopedPreference(
            forSpace: number, context: selectedDisplayID, store: store
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

    /// Toggling the selected symbol off returns the entry to its label or
    /// number. The empty string is the explicit "none" sentinel, as
    /// `setIconStyle` writes: a plain clear would let a default-style
    /// template symbol bleed back through.
    func removeSymbol() {
        SpacePreferences.setSymbol("", forSpace: editingSpace, display: editingDisplay, store: store)
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

    /// The reach the confirmation describes, matching the menu item that
    /// asked for it: a lone display has none to name, the shared "All" scope
    /// reaches every display, and a selected display reaches only itself.
    private var bulkCopyWording: (confirm: String, detail: String) {
        if displays.count <= 1 {
            (Localization.confirmCopyToAllSpaces, Localization.detailCopyToAllSpaces)
        } else if selectedDisplayID == nil {
            (Localization.confirmCopyToAllDisplays, Localization.detailCopyToAllDisplays)
        } else {
            (Localization.confirmCopyToThisDisplay, Localization.detailCopyToThisDisplay)
        }
    }

    /// Copying is only destructive when it replaces preferences already
    /// stored at the destination's exact scope. Inherited styling remains
    /// untouched, so it does not warrant a confirmation.
    private func confirmCopyIfNeeded(
        targetHasModifications: Bool,
        message: String,
        detail: String
    ) -> Bool {
        guard targetHasModifications else {
            return true
        }
        return confirmAction(message, detail, Localization.buttonCopy, false)
    }

    func copyToAllSpaces() {
        let wording = bulkCopyWording
        let targetHasModifications = spaceEntries.contains { number, _ in
            number != editingSpace && SpacePreferences.hasAnyScopedPreference(
                forSpace: number,
                context: selectedDisplayID,
                store: store
            ) && SpacePreferences.copyWouldChangeConfiguration(
                from: editingSpace,
                to: number,
                fromDisplay: editingDisplay,
                toDisplay: selectedDisplayID,
                store: store
            )
        }
        guard confirmCopyIfNeeded(
            targetHasModifications: targetHasModifications,
            message: wording.confirm,
            detail: wording.detail
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
    /// display as per-display overrides. Offered only while a display is
    /// selected - shared "All" edits already apply everywhere.
    func copyToAllDisplays() {
        let targetHasModifications = displays.contains { display in
            (1 ... max(display.entries.count, Layout.maxSpacesPerDisplay)).contains { number in
                (number != editingSpace || display.displayID != selectedDisplayID)
                    && SpacePreferences.hasAnyScopedPreference(
                        forSpace: number,
                        context: display.displayID,
                        store: store
                    )
                    && SpacePreferences.copyWouldChangeConfiguration(
                        from: editingSpace,
                        to: number,
                        fromDisplay: editingDisplay,
                        toDisplay: display.displayID,
                        store: store
                    )
            }
        }
        guard confirmCopyIfNeeded(
            targetHasModifications: targetHasModifications,
            message: Localization.confirmCopyToAllDisplays,
            detail: Localization.detailCopyToAllDisplays
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

    /// Copies the edited entry's preferences onto one other Space at the
    /// edited scope, replacing that Space's own style after confirming.
    func copyToSpace(_ number: Int) {
        guard number != editingSpace else {
            return
        }
        guard confirmCopyIfNeeded(
            targetHasModifications: SpacePreferences.hasAnyScopedPreference(
                forSpace: number,
                context: selectedDisplayID,
                store: store
            ) && SpacePreferences.copyWouldChangeConfiguration(
                from: editingSpace,
                to: number,
                fromDisplay: editingDisplay,
                toDisplay: selectedDisplayID,
                store: store
            ),
            message: Localization.confirmCopyToSpace,
            detail: Localization.detailCopyToSpace
        ) else {
            return
        }
        SpacePreferences.copyPreferences(
            from: editingSpace,
            to: number,
            fromDisplay: editingDisplay,
            toDisplay: selectedDisplayID,
            store: store
        )
        tick += 1
    }

    /// Replaces the edited entry's preferences with another Space's, read at
    /// the shown display's scope and written at the edited one. The entry's
    /// own preferences are cleared first, so it ends up matching the source
    /// rather than blending with it: a copy alone carries only the keys the
    /// source holds, leaving the rest of the edited entry standing.
    func copyFromSpace(_ number: Int) {
        guard number != editingSpace else {
            return
        }
        guard confirmCopyIfNeeded(
            targetHasModifications: SpacePreferences.hasAnyScopedPreference(
                forSpace: editingSpace,
                context: editingDisplay,
                store: store
            ) && !SpacePreferences.configurationsMatch(
                editingSpace,
                display: editingDisplay,
                number,
                display: selectedDisplayID,
                includeSound: !isEditingDefaultStyle,
                store: store
            ),
            message: Localization.confirmCopyFromSpace,
            detail: Localization.detailCopyFromSpace
        ) else {
            return
        }
        SpacePreferences.clearPreferences(forSpace: editingSpace, display: editingDisplay, store: store)
        SpacePreferences.copyPreferences(
            from: number,
            to: editingSpace,
            fromDisplay: selectedDisplayID,
            toDisplay: editingDisplay,
            // The template holds no sound; the Default Style row edits the
            // global default instead, as saveDefaultStyle assumes
            includeSound: !isEditingDefaultStyle,
            store: store
        )
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

    /// Clears every Space's own preferences on every display so all Spaces
    /// inherit the saved template. The template itself stays untouched.
    func resetAllSpacesToDefault() {
        guard confirmAction(
            Localization.confirmResetAllSpaces,
            Localization.detailResetAllSpacesToDefault,
            Localization.buttonResetAll,
            true
        ) else {
            return
        }
        SpacePreferences.clearAllSpaceOverrides(store: store)
        tick += 1
    }

    /// Clears every Space's preferences on every display, including the
    /// saved template and per-space sounds. Icon sizing, separator, and the
    /// global default sound stay untouched.
    func resetAllSpaces() {
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
        clearPreview()
    }
}
