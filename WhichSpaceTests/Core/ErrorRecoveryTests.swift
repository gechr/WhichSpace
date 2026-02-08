import Cocoa
import Defaults
import Testing
@testable import WhichSpace

@Suite("Error Recovery")
@MainActor
struct ErrorRecoveryTests {
    private let store: DefaultsStore
    private let testSuite: TestSuite
    private let bridge: SpaceColors.Bridge
    private let fontBridge: SpaceFont.Bridge

    init() {
        testSuite = TestSuiteFactory.createSuite()
        store = DefaultsStore(suite: testSuite.suite)
        bridge = SpaceColors.Bridge()
        fontBridge = SpaceFont.Bridge()
    }

    // MARK: - Corrupted Preference Data Tests

    @Test("deserialize with corrupted foreground data returns nil")
    func deserializeWithCorruptedForegroundData() throws {
        let validBackground = try NSKeyedArchiver.archivedData(
            withRootObject: NSColor.blue,
            requiringSecureCoding: true
        )
        let corruptedData = Data([0xDE, 0xAD, 0xBE, 0xEF])

        let result = bridge.deserialize([
            "foreground": corruptedData,
            "background": validBackground,
        ])

        #expect(result == nil, "Should return nil for corrupted foreground data")
    }

    @Test("deserialize with corrupted background data returns nil")
    func deserializeWithCorruptedBackgroundData() throws {
        let validForeground = try NSKeyedArchiver.archivedData(
            withRootObject: NSColor.red,
            requiringSecureCoding: true
        )
        let corruptedData = Data([0xCA, 0xFE, 0xBA, 0xBE])

        let result = bridge.deserialize([
            "foreground": validForeground,
            "background": corruptedData,
        ])

        #expect(result == nil, "Should return nil for corrupted background data")
    }

    @Test("deserialize with both corrupted data returns nil")
    func deserializeWithBothCorruptedData() {
        let corruptedData = Data([0x00, 0x01, 0x02, 0x03])

        let result = bridge.deserialize([
            "foreground": corruptedData,
            "background": corruptedData,
        ])

        #expect(result == nil, "Should return nil when both colors are corrupted")
    }

    @Test("deserialize with empty data returns nil")
    func deserializeWithEmptyData() {
        let emptyData = Data()

        let result = bridge.deserialize([
            "foreground": emptyData,
            "background": emptyData,
        ])

        #expect(result == nil, "Should return nil for empty data")
    }

    @Test("deserialize with wrong object type returns nil")
    func deserializeWithWrongObjectType() throws {
        let wrongTypeData = try NSKeyedArchiver.archivedData(
            withRootObject: NSFont.systemFont(ofSize: 12),
            requiringSecureCoding: true
        )
        let validBackground = try NSKeyedArchiver.archivedData(
            withRootObject: NSColor.blue,
            requiringSecureCoding: true
        )

        let result = bridge.deserialize([
            "foreground": wrongTypeData,
            "background": validBackground,
        ])

        #expect(result == nil, "Should return nil when archived object is wrong type")
    }

    @Test("deserialize with partially valid data returns nil")
    func deserializeWithPartiallyValidData() throws {
        let validForeground = try NSKeyedArchiver.archivedData(
            withRootObject: NSColor.red,
            requiringSecureCoding: true
        )

        let result = bridge.deserialize(["foreground": validForeground])
        #expect(result == nil, "Should return nil when background is missing")
    }

    @Test("deserialize with extra keys succeeds")
    func deserializeWithExtraKeys() throws {
        let validForeground = try NSKeyedArchiver.archivedData(
            withRootObject: NSColor.red,
            requiringSecureCoding: true
        )
        let validBackground = try NSKeyedArchiver.archivedData(
            withRootObject: NSColor.blue,
            requiringSecureCoding: true
        )

        let result = bridge.deserialize([
            "foreground": validForeground,
            "background": validBackground,
            "extraKey": Data([0x00]),
        ])

        #expect(result != nil, "Should successfully deserialize even with extra keys")
        #expect(result?.foreground == .red)
        #expect(result?.background == .blue)
    }

    // MARK: - Font Bridge Tests

    @Test("font bridge deserialize with corrupted data returns nil")
    func fontBridgeDeserializeWithCorruptedData() {
        let corruptedData = Data([0xDE, 0xAD, 0xBE, 0xEF])
        let result = fontBridge.deserialize(corruptedData)
        #expect(result == nil, "Should return nil for corrupted font data")
    }

    @Test("font bridge deserialize with empty data returns nil")
    func fontBridgeDeserializeWithEmptyData() {
        let result = fontBridge.deserialize(Data())
        #expect(result == nil, "Should return nil for empty font data")
    }

    @Test("font bridge deserialize with nil returns nil")
    func fontBridgeDeserializeWithNil() {
        let result = fontBridge.deserialize(nil)
        #expect(result == nil, "Should return nil for nil font data")
    }

    @Test("font bridge round trip")
    func fontBridgeRoundTrip() {
        let originalFont = NSFont.boldSystemFont(ofSize: 14)
        let spaceFont = SpaceFont(font: originalFont)

        let serialized = fontBridge.serialize(spaceFont)
        #expect(serialized != nil)

        let deserialized = fontBridge.deserialize(serialized)
        #expect(deserialized != nil)
        #expect(deserialized?.font.pointSize == originalFont.pointSize)
    }

    // MARK: - Recovery from Bad State Tests

    @Test("preferences recover from corrupted storage")
    func preferencesRecoverFromCorruptedStorage() {
        let validColors = SpaceColors(foreground: .red, background: .blue)
        SpacePreferences.setColors(validColors, forSpace: 1, store: store)

        let retrieved = SpacePreferences.colors(forSpace: 1, store: store)
        #expect(retrieved != nil)

        SpacePreferences.clearColors(forSpace: 1, store: store)
        #expect(SpacePreferences.colors(forSpace: 1, store: store) == nil)

        let newColors = SpaceColors(foreground: .green, background: .yellow)
        SpacePreferences.setColors(newColors, forSpace: 1, store: store)
        let newRetrieved = SpacePreferences.colors(forSpace: 1, store: store)
        #expect(newRetrieved?.foreground == .green)
    }
}
