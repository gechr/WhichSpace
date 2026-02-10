import Testing
@testable import WhichSpace

@Suite("Settings Constraints")
@MainActor
struct SettingsConstraintsTests {
    private let store: DefaultsStore
    private let testSuite: TestSuite

    init() {
        testSuite = TestSuiteFactory.createSuite()
        store = DefaultsStore(suite: testSuite.suite)
    }

    // MARK: - showAllSpaces / showAllDisplays Mutual Exclusion

    @Test("enabling showAllSpaces disables showAllDisplays")
    func enablingShowAllSpaces_disablesShowAllDisplays() {
        store.showAllDisplays = true

        SettingsConstraints.setShowAllSpaces(true, store: store)

        #expect(store.showAllSpaces)
        #expect(!store.showAllDisplays, "showAllDisplays should be disabled when showAllSpaces is enabled")
    }

    @Test("enabling showAllDisplays disables showAllSpaces")
    func enablingShowAllDisplays_disablesShowAllSpaces() {
        store.showAllSpaces = true

        SettingsConstraints.setShowAllDisplays(true, store: store)

        #expect(store.showAllDisplays)
        #expect(!store.showAllSpaces, "showAllSpaces should be disabled when showAllDisplays is enabled")
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

    // MARK: - clickToSwitchSpaces Accessibility Guard

    @Test("clickToSwitchSpaces fails without accessibility")
    func clickToSwitchSpaces_failsWithoutAccessibility() {
        // AXIsProcessTrusted() returns false in test/CI environments
        let result = SettingsConstraints.setClickToSwitchSpaces(true, store: store)

        #expect(!result, "Should fail when accessibility is not granted")
        #expect(!store.clickToSwitchSpaces, "Setting should remain false")
    }

    @Test("clickToSwitchSpaces can always be disabled")
    func clickToSwitchSpaces_canAlwaysBeDisabled() {
        store.clickToSwitchSpaces = true

        let result = SettingsConstraints.setClickToSwitchSpaces(false, store: store)

        #expect(result, "Disabling should always succeed")
        #expect(!store.clickToSwitchSpaces)
    }

    @Test("clickToSwitchSpaces disabling from default succeeds")
    func clickToSwitchSpaces_disablingFromDefault_succeeds() {
        let result = SettingsConstraints.setClickToSwitchSpaces(false, store: store)

        #expect(result)
        #expect(!store.clickToSwitchSpaces)
    }

    // MARK: - Accessibility Alert Flow (SettingsView binding logic)

    @Test("accessibility alert triggered when enabling without permission")
    func accessibilityAlert_triggeredWhenEnablingWithoutPermission() {
        // Reproduces the binding setter logic from SettingsView.clickToSwitchSpacesBinding
        var showingAccessibilityAlert = false

        let result = SettingsConstraints.setClickToSwitchSpaces(true, store: store)
        if !result {
            showingAccessibilityAlert = true
        }

        #expect(showingAccessibilityAlert, "Alert should be triggered when enforcer denies the change")
        #expect(!store.clickToSwitchSpaces, "Setting should remain false")
    }

    @Test("no accessibility alert when disabling")
    func accessibilityAlert_notTriggeredWhenDisabling() {
        store.clickToSwitchSpaces = true
        var showingAccessibilityAlert = false

        let result = SettingsConstraints.setClickToSwitchSpaces(false, store: store)
        if !result {
            showingAccessibilityAlert = true
        }

        #expect(!showingAccessibilityAlert, "No alert when disabling")
        #expect(!store.clickToSwitchSpaces)
    }

    @Test("no accessibility alert when already disabled")
    func accessibilityAlert_notTriggeredWhenAlreadyDisabled() {
        var showingAccessibilityAlert = false

        let result = SettingsConstraints.setClickToSwitchSpaces(false, store: store)
        if !result {
            showingAccessibilityAlert = true
        }

        #expect(!showingAccessibilityAlert, "No alert when value is already false")
    }
}
