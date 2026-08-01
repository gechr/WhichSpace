import AppKit
import Testing
@testable import WhichSpace

@MainActor
struct SpaceEditorModelTests {
    private let store: DefaultsStore
    private let stub: CGSStub

    init() {
        let testSuite = TestSuiteFactory.createSuite()
        store = DefaultsStore(suite: testSuite.suite)
        stub = CGSStub()
        stub.activeDisplayIdentifier = "Main"
        stub.displays = [
            CGSStub.makeDisplay(
                displayID: "Main",
                spaces: [
                    (id: 100, isFullscreen: false),
                    (id: 101, isFullscreen: false),
                    (id: 102, isFullscreen: false),
                ],
                activeSpaceID: 100
            ),
        ]
    }

    /// AppState lives inside each test rather than on the suite: the suite
    /// value deallocates off the main actor, where AppState's deinit traps.
    private func makeAppState() -> AppState {
        AppState(displaySpaceProvider: stub, skipObservers: true, store: store)
    }

    private func makeModel(confirmed: Bool = true) -> SpaceEditorModel {
        SpaceEditorModel(appState: makeAppState()) { _, _, _, _ in confirmed }
    }

    // MARK: - Selection

    @Test("initial selection is the current Space on the current display")
    func initialSelection() {
        let model = makeModel()
        #expect(model.selection == .space(1))
        #expect(model.selectedDisplayID == "Main")
        #expect(model.editingSpace == 1)
        #expect(model.editingDisplay == "Main")
    }

    @Test("the Default Style entry edits space 0 with no display")
    func defaultStyleCoordinates() {
        let model = makeModel()
        model.selection = .defaultStyle
        #expect(model.editingSpace == SpacePreferences.defaultStyleSpace)
        #expect(model.editingDisplay == nil)
    }

    @Test("normalizeSelection keeps a placeholder Space selected")
    func normalizeSelectionKeepsPlaceholder() {
        let model = makeModel()
        model.selection = .space(9)
        model.normalizeSelection()
        #expect(model.selection == .space(9))
    }

    @Test("normalizeSelection recovers from a Space beyond the limit")
    func normalizeSelection() {
        let model = makeModel()
        model.selection = .space(Layout.maxSpacesPerDisplay + 1)
        model.normalizeSelection()
        #expect(model.selection == .space(1))
    }

    // MARK: - Space List

    @Test("the Space list pads placeholders up to the per-display limit")
    func spaceEntriesPadding() {
        let model = makeModel()
        let entries = model.spaceEntries
        #expect(entries.count == Layout.maxSpacesPerDisplay)
        #expect(entries.prefix(3).allSatisfy { $0.entry != nil })
        #expect(entries.dropFirst(3).allSatisfy { $0.entry == nil })
        #expect(entries.map(\.number) == Array(1 ... Layout.maxSpacesPerDisplay))
        #expect(model.existingSpaceCount == 3)
    }

    @Test("placeholder entries extrapolate their desktop name")
    func placeholderSpaceName() {
        let model = makeModel()
        let placeholder = model.spaceEntries[3]
        #expect(placeholder.entry == nil)
        #expect(model.spaceName(for: placeholder)
            == String(format: Localization.labelDesktopNumber, 4))
    }

    // MARK: - Key Routing

    @Test("writes use shared storage while uniqueIconsPerDisplay is off")
    func sharedRouting() {
        let model = makeModel()
        model.selection = .space(2)
        model.setSymbol("star.fill")
        #expect(store.spaceSymbols[2] == "star.fill")
        #expect(store.displaySpaceSymbols.isEmpty)
    }

    @Test("writes use per-display storage while uniqueIconsPerDisplay is on")
    func perDisplayRouting() {
        store.uniqueIconsPerDisplay = true
        let model = makeModel()
        model.selection = .space(2)
        model.setSymbol("star.fill")
        #expect(store.displaySpaceSymbols["Main"]?[2] == "star.fill")
        #expect(store.spaceSymbols.isEmpty)
    }

    @Test("the template stays in shared storage even per-display")
    func templateRoutingPerDisplay() {
        store.uniqueIconsPerDisplay = true
        let model = makeModel()
        model.selection = .defaultStyle
        model.setLabel("New")
        #expect(store.spaceLabels[0] == "New")
        #expect(store.displaySpaceLabels.isEmpty)
    }

    // MARK: - Write Semantics

    @Test("writes bump the store mutation count and the tick")
    func writesBumpCaches() {
        let model = makeModel()
        let mutationsBefore = store.mutationCount
        let tickBefore = model.tick
        model.setLabel("Work")
        #expect(store.mutationCount > mutationsBefore)
        #expect(model.tick > tickBefore)
    }

    @Test("labels are trimmed, cleared by whitespace, and truncated")
    func labelNormalization() {
        let model = makeModel()
        model.setLabel("  Work  ")
        #expect(model.label == "Work")

        model.setLabel("   ")
        #expect(model.label == nil)

        model.setLabel(String(repeating: "x", count: LabelTemplate.maxContentLength + 5))
        #expect(model.label?.count == LabelTemplate.maxContentLength)
    }

    @Test("selecting a number style clears the symbol and label")
    func iconStyleClearsSymbolMode() {
        let model = makeModel()
        model.setSymbol("star.fill")
        model.setLabel("Work")
        model.setIconStyle(.circle)
        #expect(model.iconStyle == .circle)
        #expect(model.symbol == nil)
        #expect(model.label == nil)
    }

    @Test("setting an emoji records the picker skin tone")
    func emojiRecordsSkinTone() {
        store.emojiPickerSkinTone = .dark
        let model = makeModel()
        model.setSymbol("👍")
        #expect(model.skinTone == .dark)
    }

    @Test("badge input keeps one character and survives clearing")
    func badgeCharacter() {
        let model = makeModel()
        model.setBadgeCharacter("AB")
        #expect(model.badge?.character == "A")

        model.setBadgePosition(.bottomRight)
        #expect(model.badge?.position == .bottomRight)

        // An empty character keeps the record so the position survives
        model.setBadgeCharacter(nil)
        #expect(model.badge?.character.isEmpty == true)
        #expect(model.badge?.position == .bottomRight)
    }

    @Test("badge position is ignored without a character")
    func badgePositionRequiresCharacter() {
        let model = makeModel()
        model.setBadgePosition(.topRight)
        #expect(model.badge == nil)
    }

    @Test("space sound writes route shared or per-display")
    func spaceSoundRouting() {
        let model = makeModel()
        model.selection = .space(2)
        model.setSpaceSound("Pop")
        #expect(store.spaceSounds[2] == "Pop")
        #expect(store.displaySpaceSounds.isEmpty)

        model.setSpaceSound(nil)
        #expect(model.spaceSound == nil)

        store.uniqueIconsPerDisplay = true
        model.setSpaceSound("Blow")
        #expect(store.displaySpaceSounds["Main"]?[2] == "Blow")
        #expect(store.spaceSounds.isEmpty)
    }

    @Test("global sound writes the store default and bumps caches")
    func globalSoundWrite() {
        let model = makeModel()
        let mutationsBefore = store.mutationCount
        let tickBefore = model.tick
        model.setGlobalSoundName("Glass")
        #expect(store.soundName == "Glass")
        #expect(model.globalSoundName == "Glass")
        #expect(store.mutationCount > mutationsBefore)
        #expect(model.tick > tickBefore)
    }

    @Test("color writes preserve the other components")
    func colorComponents() {
        let model = makeModel()
        model.setForegroundColor(.red)
        model.setSymbolBackgroundColor(.blue)
        #expect(model.colors?.foreground == .red)
        #expect(model.colors?.symbolBackground == .blue)

        model.clearSymbolBackgroundColor()
        #expect(model.colors?.foreground == .red)
        #expect(model.colors?.symbolBackground == nil)
    }

    @Test("invert swaps foreground and background")
    func invertColors() {
        let model = makeModel()
        model.setForegroundColor(.red)
        model.setBackgroundColor(.blue)
        model.invertColors()
        #expect(model.colors?.foreground == .blue)
        #expect(model.colors?.background == .red)
    }

    // MARK: - Actions

    @Test("copy to all covers every other Space once confirmed")
    func copyToAll() {
        let model = makeModel()
        model.setLabel("Work")
        model.setSpaceSound("Pop")
        model.copyToAllSpaces()
        #expect(SpacePreferences.label(forSpace: 2, display: "Main", store: store) == "Work")
        #expect(SpacePreferences.label(forSpace: 3, display: "Main", store: store) == "Work")
        #expect(SpacePreferences.sound(forSpace: 2, display: "Main", store: store) == "Pop")
        #expect(SpacePreferences.label(
            forSpace: Layout.maxSpacesPerDisplay, display: "Main", store: store
        ) == "Work")
    }

    @Test("copy to all displays covers every display's Spaces")
    func copyToAllDisplays() {
        store.uniqueIconsPerDisplay = true
        stub.displays = [
            CGSStub.makeDisplay(
                displayID: "Main",
                spaces: [(id: 100, isFullscreen: false), (id: 101, isFullscreen: false)],
                activeSpaceID: 100
            ),
            CGSStub.makeDisplay(
                displayID: "Side",
                spaces: [(id: 200, isFullscreen: false), (id: 201, isFullscreen: false)],
                activeSpaceID: 200
            ),
        ]

        let model = makeModel()
        model.setLabel("Work")
        model.copyToAllDisplays()
        #expect(store.displaySpaceLabels["Main"]?[2] == "Work")
        #expect(store.displaySpaceLabels["Side"]?[1] == "Work")
        #expect(store.displaySpaceLabels["Side"]?[2] == "Work")
        #expect(store.displaySpaceLabels["Main"]?[Layout.maxSpacesPerDisplay] == "Work")
        #expect(store.displaySpaceLabels["Side"]?[Layout.maxSpacesPerDisplay] == "Work")
    }

    @Test("a declined confirmation leaves the store unchanged")
    func declinedConfirmation() {
        let model = makeModel(confirmed: false)
        model.setLabel("Work")
        model.copyToAllSpaces()
        #expect(SpacePreferences.label(forSpace: 2, display: "Main", store: store) == nil)

        model.resetToDefault()
        #expect(model.label == "Work")
    }

    @Test("reset clears the edited Space's preferences")
    func resetSpace() {
        let model = makeModel()
        model.setLabel("Work")
        model.setSymbol("star.fill")
        model.setSpaceSound("Pop")
        model.resetToDefault()
        #expect(model.label == nil)
        #expect(model.symbol == nil)
        #expect(model.spaceSound == nil)
    }

    @Test("reset all Spaces clears every preference map")
    func resetAllSpaces() {
        let model = makeModel()
        model.setLabel("Work")
        model.selection = .space(2)
        model.setSymbol("star.fill")
        model.resetAllSpacesToDefault()
        #expect(store.spaceLabels.isEmpty)
        #expect(store.spaceSymbols.isEmpty)
    }

    @Test("reset on the Default Style entry clears the template")
    func resetTemplate() {
        let model = makeModel()
        model.setLabel("Work")
        model.saveAsDefaultStyle()
        #expect(SpacePreferences.hasDefaultStyle(store: store))

        model.selection = .defaultStyle
        model.resetToDefault()
        #expect(!SpacePreferences.hasDefaultStyle(store: store))
    }

    @Test("save as default stores the template at space 0")
    func saveAsDefault() {
        let model = makeModel()
        model.selection = .space(2)
        model.setLabel("Mail")
        model.saveAsDefaultStyle()
        #expect(SpacePreferences.label(forSpace: 0, display: nil, store: store) == "Mail")
    }

    @Test("save as default is a no-op for the template itself")
    func saveAsDefaultOnTemplate() {
        let model = makeModel()
        model.selection = .defaultStyle
        model.setLabel("Tmpl")
        model.saveAsDefaultStyle()
        #expect(SpacePreferences.label(forSpace: 0, display: nil, store: store) == "Tmpl")
    }

    // MARK: - Current Space Marker

    @Test("the current Space is marked by Space ID, not by position")
    func currentSpaceMarker() {
        let model = makeModel()
        let marked = model.spaceEntries.filter { model.isCurrentSpace($0) }
        #expect(marked.count == 1)
        #expect(marked.first?.entry?.id == 100)
    }

    @Test("placeholder rows are never the current Space")
    func placeholdersAreNotCurrent() {
        let model = makeModel()
        let placeholders = model.spaceEntries.filter { $0.entry == nil }
        #expect(!placeholders.isEmpty)
        #expect(placeholders.allSatisfy { !model.isCurrentSpace($0) })
    }

    @Test("a display CGS never names has no system name to show")
    func unknownDisplayHasNoName() {
        let model = makeModel()
        #expect(model.displayName(for: nil) == nil)
        #expect(model.displayName(for: "not-a-display-uuid") == nil)
    }
}
