import Testing
@testable import WhichSpace

@Suite("Space Switcher")
@MainActor
struct SpaceSwitcherTests {
    private let mockProvider: MockHotKeyProvider
    private let switcher: SpaceSwitcher

    init() {
        mockProvider = MockHotKeyProvider()
        switcher = SpaceSwitcher(hotKeyProvider: mockProvider)
    }

    // MARK: - Range Validation

    @Test("space 0 returns nil event")
    func outOfRangeSpace_zero_returnsNilEvent() {
        let event = switcher.eventForSwitching(to: 0)
        #expect(event == nil, "Space 0 should not produce an event")
    }

    @Test("negative space returns nil event")
    func outOfRangeSpace_negative_returnsNilEvent() {
        let event = switcher.eventForSwitching(to: -1)
        #expect(event == nil, "Negative space should not produce an event")
    }

    @Test("space 17 returns nil event")
    func outOfRangeSpace_17_returnsNilEvent() {
        let event = switcher.eventForSwitching(to: 17)
        #expect(event == nil, "Space 17 should not produce an event")
    }

    @Test("space 100 returns nil event")
    func outOfRangeSpace_100_returnsNilEvent() {
        let event = switcher.eventForSwitching(to: 100)
        #expect(event == nil, "Space 100 should not produce an event")
    }

    // MARK: - Missing Hot Key Value

    @Test("missing hot key value returns nil event")
    func missingHotKeyValue_returnsNilEvent() {
        let event = switcher.eventForSwitching(to: 1)
        #expect(event == nil, "Missing hot key value should return nil event")
    }

    // MARK: - Valid Range

    @Test("space 1 produces valid event")
    func validRange_space1_accepted() {
        configureHotKey(for: 1, keyCode: 18)
        let event = switcher.eventForSwitching(to: 1)
        #expect(event != nil, "Space 1 should produce a valid event")
    }

    @Test("space 16 produces valid event")
    func validRange_space16_accepted() {
        configureHotKey(for: 16, keyCode: 33)
        let event = switcher.eventForSwitching(to: 16)
        #expect(event != nil, "Space 16 should produce a valid event")
    }

    // MARK: - Hot Key Index Mapping

    @Test("space 1 maps to hot key 118")
    func hotKeyMapping_space1_mapsToHotKey118() {
        let hotKey: CGSSymbolicHotKey = 118
        mockProvider.hotKeyValues[hotKey] = (keyChar: 0, keyCode: 18, flags: 0)
        mockProvider.enabledHotKeys.insert(hotKey)

        let event = switcher.eventForSwitching(to: 1)
        #expect(event != nil, "Space 1 should use hot key 118")
    }

    @Test("space 16 maps to hot key 133")
    func hotKeyMapping_space16_mapsToHotKey133() {
        let hotKey: CGSSymbolicHotKey = 133
        mockProvider.hotKeyValues[hotKey] = (keyChar: 0, keyCode: 33, flags: 0)
        mockProvider.enabledHotKeys.insert(hotKey)

        let event = switcher.eventForSwitching(to: 16)
        #expect(event != nil, "Space 16 should use hot key 133")
    }

    // MARK: - Disabled Hot Key Re-enabling

    @Test("disabled hot key is enabled before use")
    func disabledHotKey_isEnabledBeforeUse() {
        let hotKey: CGSSymbolicHotKey = 118
        mockProvider.hotKeyValues[hotKey] = (keyChar: 0, keyCode: 18, flags: 0)

        let event = switcher.eventForSwitching(to: 1)
        #expect(event != nil, "Should still produce event after enabling hot key")

        #expect(mockProvider.setEnabledCalls.count == 1)
        #expect(mockProvider.setEnabledCalls.first?.hotKey == hotKey)
        #expect(mockProvider.setEnabledCalls.first?.enabled == true)
    }

    @Test("already enabled hot key is not re-enabled")
    func alreadyEnabledHotKey_notReEnabled() {
        let hotKey: CGSSymbolicHotKey = 118
        mockProvider.hotKeyValues[hotKey] = (keyChar: 0, keyCode: 18, flags: 0)
        mockProvider.enabledHotKeys.insert(hotKey)

        _ = switcher.eventForSwitching(to: 1)

        #expect(mockProvider.setEnabledCalls.isEmpty)
    }

    // MARK: - Helpers

    private func configureHotKey(for space: Int, keyCode: CGKeyCode) {
        let hotKey = CGSSymbolicHotKey(118 + UInt16(space) - 1)
        mockProvider.hotKeyValues[hotKey] = (keyChar: 0, keyCode: keyCode, flags: 0)
        mockProvider.enabledHotKeys.insert(hotKey)
    }
}
