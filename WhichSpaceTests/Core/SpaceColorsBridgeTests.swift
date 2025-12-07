import Defaults
import XCTest
@testable import WhichSpace

final class SpaceColorsBridgeTests: IsolatedDefaultsTestCase {
    private var bridge: SpaceColors.Bridge!

    override func setUp() {
        super.setUp()
        bridge = SpaceColors.Bridge()
    }

    override func tearDown() {
        bridge = nil
        super.tearDown()
    }

    // MARK: - Serialize Tests

    func testSerializeNilReturnsNil() {
        let result = bridge.serialize(nil)
        XCTAssertNil(result)
    }

    func testSerializeReturnsExpectedKeys() {
        let colors = SpaceColors(foreground: .red, background: .blue)
        let serialized = bridge.serialize(colors)

        XCTAssertNotNil(serialized)
        XCTAssertNotNil(serialized?["foreground"])
        XCTAssertNotNil(serialized?["background"])
        XCTAssertEqual(serialized?.count, 2)
    }

    // MARK: - Deserialize Tests

    func testDeserializeNilReturnsNil() {
        let result = bridge.deserialize(nil)
        XCTAssertNil(result)
    }

    func testDeserializeEmptyDictionaryReturnsNil() {
        let result = bridge.deserialize([:])
        XCTAssertNil(result)
    }

    func testDeserializeMissingForegroundReturnsNil() {
        let backgroundData = try! NSKeyedArchiver.archivedData(
            withRootObject: NSColor.blue,
            requiringSecureCoding: true
        )
        let result = bridge.deserialize(["background": backgroundData])
        XCTAssertNil(result)
    }

    func testDeserializeMissingBackgroundReturnsNil() {
        let foregroundData = try! NSKeyedArchiver.archivedData(
            withRootObject: NSColor.red,
            requiringSecureCoding: true
        )
        let result = bridge.deserialize(["foreground": foregroundData])
        XCTAssertNil(result)
    }

    func testDeserializeInvalidDataReturnsNil() {
        let invalidData = Data([0x00, 0x01, 0x02])
        let result = bridge.deserialize([
            "foreground": invalidData,
            "background": invalidData,
        ])
        XCTAssertNil(result)
    }

    // MARK: - Round-Trip Tests

    func testRoundTripWithBasicColors() {
        let original = SpaceColors(foreground: .red, background: .blue)
        let serialized = bridge.serialize(original)
        let deserialized = bridge.deserialize(serialized)

        XCTAssertNotNil(deserialized)
        XCTAssertEqual(deserialized?.foreground, original.foreground)
        XCTAssertEqual(deserialized?.background, original.background)
    }

    func testRoundTripWithCalibratedColors() {
        let original = SpaceColors(
            foreground: NSColor(calibratedWhite: 0.3, alpha: 1.0),
            background: NSColor(calibratedWhite: 0.7, alpha: 1.0)
        )
        let serialized = bridge.serialize(original)
        let deserialized = bridge.deserialize(serialized)

        XCTAssertNotNil(deserialized)
        XCTAssertEqual(deserialized?.foreground, original.foreground)
        XCTAssertEqual(deserialized?.background, original.background)
    }

    func testRoundTripWithRGBColors() {
        let original = SpaceColors(
            foreground: NSColor(red: 0.2, green: 0.4, blue: 0.6, alpha: 1.0),
            background: NSColor(red: 0.8, green: 0.6, blue: 0.4, alpha: 0.5)
        )
        let serialized = bridge.serialize(original)
        let deserialized = bridge.deserialize(serialized)

        XCTAssertNotNil(deserialized)

        // Compare RGB components with tolerance for color space conversion
        assertColorsApproximatelyEqual(deserialized?.foreground, original.foreground)
        assertColorsApproximatelyEqual(deserialized?.background, original.background)
    }

    func testRoundTripPreservesDistinctColors() {
        let colors1 = SpaceColors(foreground: .systemRed, background: .systemBlue)
        let colors2 = SpaceColors(foreground: .systemGreen, background: .systemYellow)

        let serialized1 = bridge.serialize(colors1)
        let serialized2 = bridge.serialize(colors2)

        let deserialized1 = bridge.deserialize(serialized1)
        let deserialized2 = bridge.deserialize(serialized2)

        XCTAssertNotNil(deserialized1)
        XCTAssertNotNil(deserialized2)

        // Ensure they remain distinct
        XCTAssertNotEqual(deserialized1?.foreground, deserialized2?.foreground)
        XCTAssertNotEqual(deserialized1?.background, deserialized2?.background)
    }

    // MARK: - Persistence Integration Tests

    func testPersistsThroughDefaults() {
        let original = SpaceColors(foreground: .orange, background: .purple)
        SpacePreferences.setColors(original, forSpace: 1, store: store)

        let retrieved = SpacePreferences.colors(forSpace: 1, store: store)
        XCTAssertNotNil(retrieved)
        XCTAssertEqual(retrieved?.foreground, original.foreground)
        XCTAssertEqual(retrieved?.background, original.background)
    }

    // MARK: - Helper

    private func assertColorsApproximatelyEqual(
        _ color1: NSColor?,
        _ color2: NSColor?,
        tolerance: Double = 0.01,
        file: StaticString = #file,
        line: UInt = #line
    ) {
        guard let c1 = color1?.usingColorSpace(.genericRGB),
              let c2 = color2?.usingColorSpace(.genericRGB)
        else {
            XCTFail("Colors are nil or cannot be converted to RGB", file: file, line: line)
            return
        }

        XCTAssertEqual(c1.redComponent, c2.redComponent, accuracy: tolerance, file: file, line: line)
        XCTAssertEqual(c1.greenComponent, c2.greenComponent, accuracy: tolerance, file: file, line: line)
        XCTAssertEqual(c1.blueComponent, c2.blueComponent, accuracy: tolerance, file: file, line: line)
        XCTAssertEqual(c1.alphaComponent, c2.alphaComponent, accuracy: tolerance, file: file, line: line)
    }
}
