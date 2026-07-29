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
}
