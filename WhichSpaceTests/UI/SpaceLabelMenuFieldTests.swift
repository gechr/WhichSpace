import AppKit
import Testing
@testable import WhichSpace

@MainActor
struct SpaceLabelMenuFieldTests {
    private let store: DefaultsStore
    private let testSuite: TestSuite
    private let stub: CGSStub

    init() {
        testSuite = TestSuiteFactory.createSuite()
        store = DefaultsStore(suite: testSuite.suite)
        stub = CGSStub()
    }

    private static let spaces: [(id: Int, isFullscreen: Bool)] = [
        (id: 100, isFullscreen: false),
        (id: 101, isFullscreen: false),
        (id: 102, isFullscreen: false),
    ]

    /// One display with Space 2 active, or two displays with the second
    /// one carrying its own Spaces
    private func makeAppState(displayCount: Int = 1, activeSpaceID: Int = 101) -> AppState {
        stub.activeDisplayIdentifier = "Main"
        stub.displays = [
            CGSStub.makeDisplay(displayID: "Main", spaces: Self.spaces, activeSpaceID: activeSpaceID),
        ]
        if displayCount > 1 {
            stub.displays.append(CGSStub.makeDisplay(
                displayID: "Second",
                spaces: [(id: 200, isFullscreen: false), (id: 201, isFullscreen: false)],
                activeSpaceID: 200
            ))
        }
        return AppState(displaySpaceProvider: stub, skipObservers: true, store: store)
    }

    private func makeDelegate(appState: AppState) -> AppDelegate {
        AppDelegate(
            appState: appState,
            confirmAction: { _, _, _, _ in true },
            launchAtLogin: StubLaunchAtLoginProvider()
        )
    }

    private func configure(
        _ field: SpaceLabelMenuField,
        currentLabel: String?,
        onChange: @escaping (String) -> Void = { _ in },
        onRevert: @escaping () -> Void = {}
    ) {
        field.configure(currentLabel: currentLabel, onChange: onChange, onRevert: onRevert)
    }

    private func type(_ text: String, into field: SpaceLabelMenuField) {
        field.field.stringValue = text
        field.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification, object: field.field))
    }

    private func press(_ selector: Selector, on field: SpaceLabelMenuField) -> Bool {
        field.control(field.field, textView: NSTextView(), doCommandBy: selector)
    }

    private func pressEscape(on field: SpaceLabelMenuField) -> Bool {
        press(#selector(NSResponder.cancelOperation(_:)), on: field)
    }

    /// The clear button empties the field and fires its action
    private func clear(_ field: SpaceLabelMenuField) {
        field.field.stringValue = ""
        _ = field.field.sendAction(field.field.action, to: field.field.target)
    }

    @Test("status menu places a Label header and the field between the version header and Settings")
    func menuPlacesFieldUnderHeader() {
        let field = SpaceLabelMenuField()

        let menu = MenuBuilder.buildMenu(target: NSObject(), labelField: field)

        #expect(!menu.items[0].isEnabled)
        #expect(menu.items[1].isSeparatorItem)
        #expect(menu.items[2].title == Localization.menuLabel)
        #expect(!menu.items[2].isEnabled)
        #expect(menu.items[3].view === field)
        #expect(menu.items[4].isSeparatorItem)
        #expect(menu.items[5].title == Localization.menuSettingsWindow)
        #expect(field.field.placeholderString == Localization.menuLabel)
    }

    @Test("the field shows the label in effect with its template tokens intact")
    func configureShowsCurrentLabel() {
        let field = SpaceLabelMenuField()

        configure(field, currentLabel: "{#} Work")
        #expect(field.text == "{#} Work")

        configure(field, currentLabel: nil)
        #expect(field.text.isEmpty)
    }

    @Test("every edit is applied as typed and clamped to the label limit")
    func editsApplyLiveAndClamp() {
        let field = SpaceLabelMenuField()
        var applied: [String] = []
        configure(field, currentLabel: nil) { applied.append($0) }

        type("Wo", into: field)
        type(String(repeating: "a", count: LabelTemplate.maxContentLength + 5), into: field)

        #expect(applied == ["Wo", String(repeating: "a", count: LabelTemplate.maxContentLength)])
        #expect(field.text.count == LabelTemplate.maxContentLength)
    }

    @Test("Return closes without another edit")
    func returnCloses() {
        let field = SpaceLabelMenuField()
        var applied: [String] = []
        configure(field, currentLabel: "Work") { applied.append($0) }
        type("Play", into: field)

        #expect(press(#selector(NSResponder.insertNewline(_:)), on: field))
        #expect(applied == ["Play"])
    }

    @Test("Escape reverts only after an edit")
    func escapeRevertsOnlyAfterEdit() {
        let field = SpaceLabelMenuField()
        var applied: [String] = []
        var reverts = 0
        configure(field, currentLabel: "Work", onChange: { applied.append($0) }, onRevert: { reverts += 1 })

        #expect(pressEscape(on: field))
        #expect(reverts == 0)
        #expect(applied.isEmpty)

        type("Play", into: field)
        #expect(pressEscape(on: field))
        #expect(reverts == 1)

        // A fresh presentation starts unedited again
        configure(field, currentLabel: "Work", onChange: { applied.append($0) }, onRevert: { reverts += 1 })
        #expect(pressEscape(on: field))
        #expect(reverts == 1)
    }

    @Test("the clear button applies an empty label and counts as an edit")
    func clearButtonAppliesEmptyLabel() {
        let field = SpaceLabelMenuField()
        var applied: [String] = []
        var reverts = 0
        configure(field, currentLabel: "Work", onChange: { applied.append($0) }, onRevert: { reverts += 1 })

        clear(field)
        #expect(applied == [""])

        #expect(pressEscape(on: field))
        #expect(reverts == 1)
    }

    @Test("on a single display the field edits the shared label, as the settings editor does")
    func singleDisplayEditsSharedLabel() {
        let appState = makeAppState()
        store.spaceLabels = [2: "Old"]
        let delegate = makeDelegate(appState: appState)
        let field = delegate.statusMenuLabelField

        delegate.prepareStatusMenuLabelField()
        #expect(field.text == "Old")
        #expect(field.field.isEnabled)

        type("Work", into: field)
        #expect(store.spaceLabels[2] == "Work")
        #expect(store.displaySpaceLabels.isEmpty)
        #expect(ScriptingHelpers.resolveCurrentLabel(appState: appState, store: store) == "Work")

        type("", into: field)
        #expect(store.spaceLabels[2] == nil)
        #expect(ScriptingHelpers.resolveCurrentLabel(appState: appState, store: store) == "2")
    }

    @Test("on a single display an existing override is what the field shows and edits")
    func singleDisplayFollowsExistingOverride() {
        let appState = makeAppState()
        // What the scripting setter writes, even on one display
        SpacePreferences.setLabel("Old", forSpace: 2, display: "Main", store: store)
        let delegate = makeDelegate(appState: appState)
        let field = delegate.statusMenuLabelField

        delegate.prepareStatusMenuLabelField()
        #expect(field.text == "Old")

        type("Work", into: field)
        #expect(store.displaySpaceLabels["Main"]?[2] == "Work")
        #expect(store.spaceLabels.isEmpty)
        #expect(ScriptingHelpers.resolveCurrentLabel(appState: appState, store: store) == "Work")

        #expect(pressEscape(on: field))
        #expect(store.displaySpaceLabels["Main"]?[2] == "Old")
    }

    @Test("clearing an override reveals the shared label underneath")
    func clearingOverrideRevealsSharedLabel() {
        let appState = makeAppState()
        store.spaceLabels = [2: "Shared"]
        SpacePreferences.setLabel("Old", forSpace: 2, display: "Main", store: store)
        let delegate = makeDelegate(appState: appState)
        let field = delegate.statusMenuLabelField

        delegate.prepareStatusMenuLabelField()
        clear(field)

        #expect(store.displaySpaceLabels["Main"]?[2] == nil)
        #expect(store.spaceLabels[2] == "Shared")
        #expect(ScriptingHelpers.resolveCurrentLabel(appState: appState, store: store) == "Shared")
    }

    @Test("the current Space's number is the placeholder when the click hit no slot")
    func placeholderShowsCurrentSpaceNumber() {
        let delegate = makeDelegate(appState: makeAppState())

        delegate.prepareStatusMenuLabelField()

        #expect(delegate.statusMenuLabelField.field.placeholderString == "2")
        #expect(delegate.statusMenuLabelField.text.isEmpty)
    }

    @Test("a right-clicked slot targets its own Space, not the current one")
    func rightClickedSlotTargetsItsSpace() {
        let appState = makeAppState()
        store.spaceLabels = [3: "Old"]
        let delegate = makeDelegate(appState: appState)
        let field = delegate.statusMenuLabelField

        delegate.prepareStatusMenuLabelField(spaceID: 102)
        #expect(field.field.placeholderString == "3")
        #expect(field.text == "Old")

        type("Work", into: field)
        #expect(store.spaceLabels[3] == "Work")
        #expect(store.spaceLabels[2] == nil)
        #expect(appState.currentSpace == 2)
    }

    @Test("a slot on another display is keyed to that display and numbered per the numbering mode")
    func slotOnAnotherDisplay() {
        let appState = makeAppState(displayCount: 2)
        let delegate = makeDelegate(appState: appState)
        let field = delegate.statusMenuLabelField

        delegate.prepareStatusMenuLabelField(spaceID: 201)
        #expect(field.field.placeholderString == "5")
        type("Work", into: field)
        #expect(store.displaySpaceLabels["Second"]?[2] == "Work")
        #expect(store.displaySpaceLabels["Main"] == nil)

        store.localSpaceNumbers = true
        delegate.prepareStatusMenuLabelField(spaceID: 201)
        #expect(field.field.placeholderString == "2")
    }

    @Test("global numbering continues past the 16-Desktop cap on a second display")
    func globalNumberPastCap() {
        stub.activeDisplayIdentifier = "Main"
        stub.displays = [
            CGSStub.makeDisplay(
                displayID: "Main",
                spaces: (1 ... 16).map { (id: 100 + $0, isFullscreen: false) },
                activeSpaceID: 101
            ),
            CGSStub.makeDisplay(displayID: "Second", spaces: [(id: 200, isFullscreen: false)], activeSpaceID: 200),
        ]
        let appState = AppState(displaySpaceProvider: stub, skipObservers: true, store: store)
        let delegate = makeDelegate(appState: appState)

        delegate.prepareStatusMenuLabelField(spaceID: 200)

        #expect(delegate.statusMenuLabelField.field.placeholderString == "17")
    }

    @Test("a fullscreen Space before a Desktop shifts its position but not its number")
    func fullscreenBeforeDesktop() {
        stub.activeDisplayIdentifier = "Main"
        stub.displays = [
            CGSStub.makeDisplay(
                displayID: "Main",
                spaces: [(id: 100, isFullscreen: false), (id: 103, isFullscreen: true), (id: 101, isFullscreen: false)],
                activeSpaceID: 100
            ),
        ]
        let appState = AppState(displaySpaceProvider: stub, skipObservers: true, store: store)
        let delegate = makeDelegate(appState: appState)

        delegate.prepareStatusMenuLabelField(spaceID: 101)

        #expect(delegate.statusMenuLabelField.field.placeholderString == "2")
        type("Work", into: delegate.statusMenuLabelField)
        #expect(store.spaceLabels[3] == "Work")
    }

    @Test("a fullscreen slot shows the fullscreen marker as its placeholder")
    func fullscreenSlotPlaceholder() {
        stub.activeDisplayIdentifier = "Main"
        stub.displays = [
            CGSStub.makeDisplay(
                displayID: "Main",
                spaces: Self.spaces + [(id: 103, isFullscreen: true)],
                activeSpaceID: 101
            ),
        ]
        let appState = AppState(displaySpaceProvider: stub, skipObservers: true, store: store)
        let delegate = makeDelegate(appState: appState)

        delegate.prepareStatusMenuLabelField(spaceID: 103)

        #expect(delegate.statusMenuLabelField.field.placeholderString == Labels.fullscreen)
        type("Work", into: delegate.statusMenuLabelField)
        #expect(store.spaceLabels[4] == "Work")
    }

    @Test("an unknown Space ID disables the field")
    func unknownSpaceDisablesField() {
        let delegate = makeDelegate(appState: makeAppState())

        delegate.prepareStatusMenuLabelField(spaceID: 999)

        #expect(!delegate.statusMenuLabelField.field.isEnabled)
    }

    @Test("with several displays the field edits the current display's override")
    func multipleDisplaysEditCurrentDisplayOverride() {
        let appState = makeAppState(displayCount: 2)
        let delegate = makeDelegate(appState: appState)

        delegate.prepareStatusMenuLabelField()
        type("Work", into: delegate.statusMenuLabelField)

        #expect(store.displaySpaceLabels["Main"]?[2] == "Work")
        #expect(store.spaceLabels.isEmpty)
    }

    @Test("Escape leaves an inherited template label inherited")
    func escapeKeepsTemplateLabelInherited() {
        let appState = makeAppState()
        store.spaceLabels = [SpacePreferences.defaultStyleSpace: "Desk"]
        let delegate = makeDelegate(appState: appState)
        let field = delegate.statusMenuLabelField

        delegate.prepareStatusMenuLabelField()
        #expect(field.text == "Desk")

        type("Play", into: field)
        #expect(store.spaceLabels[2] == "Play")

        #expect(pressEscape(on: field))
        #expect(store.spaceLabels[2] == nil)
        #expect(SpacePreferences.label(forSpace: 2, store: store) == "Desk")

        // The template still reaches the Space afterwards
        store.spaceLabels[SpacePreferences.defaultStyleSpace] = "Home"
        #expect(SpacePreferences.label(forSpace: 2, store: store) == "Home")
    }

    @Test("Escape keeps the plain-number sentinel that hides a template label")
    func escapeKeepsPlainNumberSentinel() {
        let appState = makeAppState()
        store.spaceLabels = [SpacePreferences.defaultStyleSpace: "Desk", 2: ""]
        let delegate = makeDelegate(appState: appState)
        let field = delegate.statusMenuLabelField

        delegate.prepareStatusMenuLabelField()
        #expect(field.text.isEmpty)

        type("Play", into: field)
        #expect(pressEscape(on: field))

        #expect(store.spaceLabels[2]?.isEmpty == true)
        #expect(SpacePreferences.label(forSpace: 2, store: store) == nil)
        #expect(ScriptingHelpers.resolveCurrentLabel(appState: appState, store: store) == "2")
    }

    @Test("Escape without an edit writes nothing")
    func escapeWithoutEditWritesNothing() {
        let appState = makeAppState()
        store.spaceLabels = [SpacePreferences.defaultStyleSpace: "Desk"]
        let delegate = makeDelegate(appState: appState)
        let before = store.mutationCount

        delegate.prepareStatusMenuLabelField()
        #expect(pressEscape(on: delegate.statusMenuLabelField))

        #expect(store.mutationCount == before)
        #expect(store.spaceLabels == [SpacePreferences.defaultStyleSpace: "Desk"])
    }

    @Test("the field keeps its opening target when the current Space changes")
    func fieldTargetIsFixedAtOpen() {
        let appState = makeAppState()
        let delegate = makeDelegate(appState: appState)
        delegate.prepareStatusMenuLabelField()

        stub.displays = [
            CGSStub.makeDisplay(displayID: "Main", spaces: Self.spaces, activeSpaceID: 102),
        ]
        appState.forceSpaceUpdate()
        #expect(appState.currentSpace == 3)

        type("Work", into: delegate.statusMenuLabelField)

        #expect(store.spaceLabels[2] == "Work")
        #expect(store.spaceLabels[3] == nil)
    }

    @Test("before the first snapshot the field is disabled and writes nothing")
    func fieldIsDisabledWithoutACurrentSpace() {
        stub.activeDisplayIdentifier = "Main"
        stub.displays = []
        let appState = AppState(displaySpaceProvider: stub, skipObservers: true, store: store)
        store.spaceLabels = [SpacePreferences.defaultStyleSpace: "Desk"]
        let delegate = makeDelegate(appState: appState)
        let field = delegate.statusMenuLabelField

        delegate.prepareStatusMenuLabelField()
        #expect(appState.currentSpace == 0)
        #expect(!field.field.isEnabled)
        #expect(field.text.isEmpty)

        type("Work", into: field)
        #expect(store.spaceLabels == [SpacePreferences.defaultStyleSpace: "Desk"])
        #expect(store.displaySpaceLabels.isEmpty)
    }
}
