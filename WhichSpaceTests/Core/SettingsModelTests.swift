import SwiftUI
import Testing
@testable import WhichSpace

@MainActor
struct SettingsModelTests {
    private let store: DefaultsStore
    private let launchAtLogin: StubLaunchAtLoginProvider
    private let model: SettingsModel

    init() {
        let testSuite = TestSuiteFactory.createSuite()
        store = DefaultsStore(suite: testSuite.suite)
        launchAtLogin = StubLaunchAtLoginProvider()
        model = SettingsModel(store: store, launchAtLogin: launchAtLogin)
    }

    private func makeModel(trusted: Bool) -> SettingsModel {
        SettingsModel(store: store, launchAtLogin: launchAtLogin) { trusted }
    }

    @Test("binding round-trips through the memoizing subscript")
    func bindingRoundTrip() {
        let binding = model.binding(\.showAllSpaces)
        #expect(!binding.wrappedValue)

        let before = store.mutationCount
        binding.wrappedValue = true

        #expect(store.showAllSpaces)
        #expect(binding.wrappedValue)
        // The renderer's icon cache key derives from mutationCount, so writes
        // that bypass it would serve stale icons
        #expect(store.mutationCount > before)
    }

    @Test("binding set bumps tick")
    func bindingBumpsTick() {
        let before = model.tick
        model.binding(\.sizeScale).wrappedValue = 80.0
        #expect(model.tick == before + 1)
    }

    @Test("launch at login binding reads and writes the provider")
    func launchAtLoginBinding() {
        launchAtLogin.isEnabled = true
        #expect(model.launchAtLoginBinding.wrappedValue)

        model.launchAtLoginBinding.wrappedValue = false
        #expect(!launchAtLogin.isEnabled)
    }

    @Test("value registers a tick dependency and reads the store")
    func valueReadsStore() {
        store.showAllDisplays = true
        #expect(model.value(\.showAllDisplays))
    }

    @Test("accessibilityGranted reflects the injected trust check")
    func accessibilityGranted() {
        #expect(makeModel(trusted: true).accessibilityGranted)
        #expect(!makeModel(trusted: false).accessibilityGranted)
    }

    @Test("click binding persists when trusted")
    func clickBindingTrusted() {
        let trusted = makeModel(trusted: true)
        trusted.clickToSwitchSpacesBinding.wrappedValue = true
        #expect(store.clickToSwitchSpaces)
    }

    @Test("click binding persists when untrusted")
    func clickBindingUntrusted() {
        let untrusted = makeModel(trusted: false)
        let before = untrusted.tick
        untrusted.clickToSwitchSpacesBinding.wrappedValue = true

        // The pref records intent even without permission
        #expect(store.clickToSwitchSpaces)
        #expect(untrusted.clickToSwitchSpacesBinding.wrappedValue)
        #expect(untrusted.tick > before)
    }

    @Test("scroll binding persists when trusted")
    func scrollBindingTrusted() {
        let trusted = makeModel(trusted: true)
        trusted.scrollSwitchingBinding(axis: \.verticalScrollEnabled).wrappedValue = true
        #expect(store.verticalScrollEnabled)
    }

    @Test("scroll binding persists when untrusted")
    func scrollBindingUntrusted() {
        let untrusted = makeModel(trusted: false)
        let before = untrusted.tick
        let binding = untrusted.scrollSwitchingBinding(axis: \.horizontalScrollEnabled)
        binding.wrappedValue = true

        #expect(store.horizontalScrollEnabled)
        #expect(binding.wrappedValue)
        #expect(untrusted.tick > before)
    }

    @Test("disabling a switching setting never requires permission")
    func gatedDisableUntrusted() {
        store.clickToSwitchSpaces = true
        store.verticalScrollEnabled = true

        let untrusted = makeModel(trusted: false)
        untrusted.clickToSwitchSpacesBinding.wrappedValue = false
        untrusted.scrollSwitchingBinding(axis: \.verticalScrollEnabled).wrappedValue = false

        #expect(!store.clickToSwitchSpaces)
        #expect(!store.verticalScrollEnabled)
    }

    @Test("haptic binding maps 0 to disabled and preserves intensity")
    func hapticBinding() {
        let binding = model.scrollHapticIntensityBinding
        #expect(binding.wrappedValue == 0)

        binding.wrappedValue = 3
        #expect(store.scrollHapticFeedback)
        #expect(store.scrollHapticIntensity == 3)

        binding.wrappedValue = 0
        #expect(!store.scrollHapticFeedback)
        // The last strength survives so re-enabling restores it
        #expect(store.scrollHapticIntensity == 3)
        #expect(binding.wrappedValue == 0)

        binding.wrappedValue = 3
        #expect(store.scrollHapticFeedback)
        #expect(binding.wrappedValue == 3)
    }

    @Test("showAll bindings write through the constraints setters")
    func showAllBindings() {
        model.showAllSpacesBinding.wrappedValue = true
        model.showAllDisplaysBinding.wrappedValue = true
        #expect(store.showAllSpaces)
        #expect(store.showAllDisplays)

        model.showAllSpacesBinding.wrappedValue = false
        #expect(!store.showAllSpaces)
        #expect(store.showAllDisplays)
    }
}

struct SliderValueParsingTests {
    @Test("the formatted value round trips back to a number")
    func parsesFormattedValue() {
        #expect(SettingsSliderRow.parseNumber("125%") == 125)
        #expect(SettingsSliderRow.parseNumber("125") == 125)
        #expect(SettingsSliderRow.parseNumber("100 %") == 100)
    }

    @Test("either decimal separator reads as a number")
    func parsesBothDecimalSeparators() {
        #expect(SettingsSliderRow.parseNumber("12.5%") == 12.5)
        #expect(SettingsSliderRow.parseNumber("12,5%") == 12.5)
    }

    @Test("input with no number in it is rejected")
    func rejectsNonNumericInput() {
        #expect(SettingsSliderRow.parseNumber("") == nil)
        #expect(SettingsSliderRow.parseNumber("%") == nil)
        // The haptic detent names are why this row opts out of typing
        #expect(SettingsSliderRow.parseNumber("Light") == nil)
    }
}
