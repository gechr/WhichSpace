import Cocoa
import Defaults
import Testing
@testable import WhichSpace

@Suite("SpaceColors Bridge")
@MainActor
struct SpaceColorsBridgeTests {
    private let store: DefaultsStore
    private let testSuite: TestSuite
    private let bridge: SpaceColors.Bridge

    init() {
        testSuite = TestSuiteFactory.createSuite()
        store = DefaultsStore(suite: testSuite.suite)
        bridge = SpaceColors.Bridge()
    }

    // MARK: - Serialize Tests

    @Test("serialize nil returns nil")
    func serializeNilReturnsNil() {
        let result = bridge.serialize(nil)
        #expect(result == nil)
    }

    @Test("serialize returns expected keys")
    func serializeReturnsExpectedKeys() {
        let colors = SpaceColors(foreground: .red, background: .blue)
        let serialized = bridge.serialize(colors)

        #expect(serialized != nil)
        #expect(serialized?["foreground"] != nil)
        #expect(serialized?["background"] != nil)
        #expect(serialized?.count == 2)
    }

    // MARK: - Deserialize Tests

    @Test("deserialize nil returns nil")
    func deserializeNilReturnsNil() {
        let result = bridge.deserialize(nil)
        #expect(result == nil)
    }

    @Test("deserialize empty dictionary returns nil")
    func deserializeEmptyDictionaryReturnsNil() {
        let result = bridge.deserialize([:])
        #expect(result == nil)
    }

    @Test("deserialize missing foreground returns nil")
    func deserializeMissingForegroundReturnsNil() throws {
        let backgroundData = try NSKeyedArchiver.archivedData(
            withRootObject: NSColor.blue,
            requiringSecureCoding: true
        )
        let result = bridge.deserialize(["background": backgroundData])
        #expect(result == nil)
    }

    @Test("deserialize missing background returns nil")
    func deserializeMissingBackgroundReturnsNil() throws {
        let foregroundData = try NSKeyedArchiver.archivedData(
            withRootObject: NSColor.red,
            requiringSecureCoding: true
        )
        let result = bridge.deserialize(["foreground": foregroundData])
        #expect(result == nil)
    }

    @Test("deserialize invalid data returns nil")
    func deserializeInvalidDataReturnsNil() {
        let invalidData = Data([0x00, 0x01, 0x02])
        let result = bridge.deserialize([
            "foreground": invalidData,
            "background": invalidData,
        ])
        #expect(result == nil)
    }

    // MARK: - Round-Trip Tests

    @Test("round trip with basic colors")
    func roundTripWithBasicColors() {
        let original = SpaceColors(foreground: .red, background: .blue)
        let serialized = bridge.serialize(original)
        let deserialized = bridge.deserialize(serialized)

        #expect(deserialized != nil)
        #expect(deserialized?.foreground == original.foreground)
        #expect(deserialized?.background == original.background)
    }

    @Test("round trip with calibrated colors")
    func roundTripWithCalibratedColors() {
        let original = SpaceColors(
            foreground: NSColor(calibratedWhite: 0.3, alpha: 1.0),
            background: NSColor(calibratedWhite: 0.7, alpha: 1.0)
        )
        let serialized = bridge.serialize(original)
        let deserialized = bridge.deserialize(serialized)

        #expect(deserialized != nil)
        #expect(deserialized?.foreground == original.foreground)
        #expect(deserialized?.background == original.background)
    }

    @Test("round trip with RGB colors")
    func roundTripWithRGBColors() {
        let original = SpaceColors(
            foreground: NSColor(red: 0.2, green: 0.4, blue: 0.6, alpha: 1.0),
            background: NSColor(red: 0.8, green: 0.6, blue: 0.4, alpha: 0.5)
        )
        let serialized = bridge.serialize(original)
        let deserialized = bridge.deserialize(serialized)

        #expect(deserialized != nil)
        assertColorsApproximatelyEqual(deserialized?.foreground, original.foreground)
        assertColorsApproximatelyEqual(deserialized?.background, original.background)
    }

    @Test("round trip preserves distinct colors")
    func roundTripPreservesDistinctColors() {
        let colors1 = SpaceColors(foreground: .systemRed, background: .systemBlue)
        let colors2 = SpaceColors(foreground: .systemGreen, background: .systemYellow)

        let serialized1 = bridge.serialize(colors1)
        let serialized2 = bridge.serialize(colors2)

        let deserialized1 = bridge.deserialize(serialized1)
        let deserialized2 = bridge.deserialize(serialized2)

        #expect(deserialized1 != nil)
        #expect(deserialized2 != nil)
        #expect(deserialized1?.foreground != deserialized2?.foreground)
        #expect(deserialized1?.background != deserialized2?.background)
    }

    // MARK: - Persistence Integration Tests

    @Test("persists through defaults")
    func persistsThroughDefaults() {
        let original = SpaceColors(foreground: .orange, background: .purple)
        SpacePreferences.setColors(original, forSpace: 1, store: store)

        let retrieved = SpacePreferences.colors(forSpace: 1, store: store)
        #expect(retrieved != nil)
        #expect(retrieved?.foreground == original.foreground)
        #expect(retrieved?.background == original.background)
    }

    // MARK: - Helper

    private func assertColorsApproximatelyEqual(
        _ color1: NSColor?,
        _ color2: NSColor?,
        tolerance: Double = 0.01
    ) {
        guard let c1 = color1?.usingColorSpace(.genericRGB),
              let c2 = color2?.usingColorSpace(.genericRGB)
        else {
            Issue.record("Colors are nil or cannot be converted to RGB")
            return
        }

        #expect(abs(c1.redComponent - c2.redComponent) <= tolerance)
        #expect(abs(c1.greenComponent - c2.greenComponent) <= tolerance)
        #expect(abs(c1.blueComponent - c2.blueComponent) <= tolerance)
        #expect(abs(c1.alphaComponent - c2.alphaComponent) <= tolerance)
    }
}
