import Testing
@testable import WhichSpace

@MainActor
struct SettingsConstraintsTests {
    private let store: DefaultsStore
    private let testSuite: TestSuite

    init() {
        testSuite = TestSuiteFactory.createSuite()
        store = DefaultsStore(suite: testSuite.suite)
    }

    // MARK: - showAllSpaces / showAllDisplays Independence

    @Test("enabling showAllSpaces preserves showAllDisplays")
    func enablingShowAllSpaces_preservesShowAllDisplays() {
        store.showAllDisplays = true

        SettingsConstraints.setShowAllSpaces(true, store: store)

        #expect(store.showAllSpaces)
        #expect(store.showAllDisplays)
    }

    @Test("enabling showAllDisplays preserves showAllSpaces")
    func enablingShowAllDisplays_preservesShowAllSpaces() {
        store.showAllSpaces = true

        SettingsConstraints.setShowAllDisplays(true, store: store)

        #expect(store.showAllDisplays)
        #expect(store.showAllSpaces)
    }

    @Test("disabling showAllSpaces does not affect showAllDisplays")
    func disablingShowAllSpaces_doesNotAffectShowAllDisplays() {
        store.showAllSpaces = true
        store.showAllDisplays = false

        SettingsConstraints.setShowAllSpaces(false, store: store)

        #expect(!store.showAllSpaces)
        #expect(!store.showAllDisplays)
    }

    @Test("disabling showAllDisplays does not affect showAllSpaces")
    func disablingShowAllDisplays_doesNotAffectShowAllSpaces() {
        store.showAllDisplays = true
        store.showAllSpaces = false

        SettingsConstraints.setShowAllDisplays(false, store: store)

        #expect(!store.showAllDisplays)
        #expect(!store.showAllSpaces)
    }

    @Test("both disabled, enabling one does not toggle other")
    func bothDisabled_enablingOneDoesNotToggleOther() {
        #expect(!store.showAllSpaces)
        #expect(!store.showAllDisplays)

        SettingsConstraints.setShowAllSpaces(true, store: store)

        #expect(store.showAllSpaces)
        #expect(!store.showAllDisplays)
    }

    // MARK: - Switching Preferences Record Intent

    @Test("scroll switching defaults to disabled")
    func scrollSwitching_defaultsToDisabled() {
        #expect(!store.horizontalScrollEnabled)
        #expect(!store.verticalScrollEnabled)
    }

    @Test("clickToSwitchSpaces persists in both directions")
    func clickToSwitchSpaces_persists() {
        SettingsConstraints.setClickToSwitchSpaces(true, store: store)
        #expect(store.clickToSwitchSpaces)

        SettingsConstraints.setClickToSwitchSpaces(false, store: store)
        #expect(!store.clickToSwitchSpaces)
    }

    @Test("scroll switching persists in both directions")
    func scrollSwitching_persists() {
        SettingsConstraints.setScrollSwitching(true, axis: \.verticalScrollEnabled, store: store)
        #expect(store.verticalScrollEnabled)

        SettingsConstraints.setScrollSwitching(false, axis: \.verticalScrollEnabled, store: store)
        #expect(!store.verticalScrollEnabled)
    }

    @Test("scroll axes write independently")
    func scrollAxes_writeIndependently() {
        SettingsConstraints.setScrollSwitching(true, axis: \.horizontalScrollEnabled, store: store)

        #expect(store.horizontalScrollEnabled)
        #expect(!store.verticalScrollEnabled)
    }
}
