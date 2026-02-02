import Cocoa
import Defaults
import XCTest
@testable import WhichSpace

// MARK: - Error Recovery Tests

final class ErrorRecoveryTests: IsolatedDefaultsTestCase {
    private var bridge: SpaceColors.Bridge!
    private var fontBridge: SpaceFont.Bridge!

    override func setUp() {
        super.setUp()
        bridge = SpaceColors.Bridge()
        fontBridge = SpaceFont.Bridge()
    }

    override func tearDown() {
        bridge = nil
        fontBridge = nil
        super.tearDown()
    }

    // MARK: - Corrupted Preference Data Tests

    func testDeserializeWithCorruptedForegroundData() throws {
        let validBackground = try NSKeyedArchiver.archivedData(
            withRootObject: NSColor.blue,
            requiringSecureCoding: true
        )
        let corruptedData = Data([0xDE, 0xAD, 0xBE, 0xEF])

        let result = bridge.deserialize([
            "foreground": corruptedData,
            "background": validBackground,
        ])

        XCTAssertNil(result, "Should return nil for corrupted foreground data")
    }

    func testDeserializeWithCorruptedBackgroundData() throws {
        let validForeground = try NSKeyedArchiver.archivedData(
            withRootObject: NSColor.red,
            requiringSecureCoding: true
        )
        let corruptedData = Data([0xCA, 0xFE, 0xBA, 0xBE])

        let result = bridge.deserialize([
            "foreground": validForeground,
            "background": corruptedData,
        ])

        XCTAssertNil(result, "Should return nil for corrupted background data")
    }

    func testDeserializeWithBothCorruptedData() {
        let corruptedData = Data([0x00, 0x01, 0x02, 0x03])

        let result = bridge.deserialize([
            "foreground": corruptedData,
            "background": corruptedData,
        ])

        XCTAssertNil(result, "Should return nil when both colors are corrupted")
    }

    func testDeserializeWithEmptyData() {
        let emptyData = Data()

        let result = bridge.deserialize([
            "foreground": emptyData,
            "background": emptyData,
        ])

        XCTAssertNil(result, "Should return nil for empty data")
    }

    func testDeserializeWithWrongObjectType() throws {
        // Archive a string instead of NSColor
        let wrongTypeData = try NSKeyedArchiver.archivedData(
            withRootObject: "not a color" as NSString,
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

        XCTAssertNil(result, "Should return nil when archived object is wrong type")
    }

    func testDeserializeWithPartiallyValidData() throws {
        let validForeground = try NSKeyedArchiver.archivedData(
            withRootObject: NSColor.red,
            requiringSecureCoding: true
        )

        // Missing background entirely
        let result = bridge.deserialize(["foreground": validForeground])
        XCTAssertNil(result, "Should return nil when background is missing")
    }

    func testDeserializeWithExtraKeys() throws {
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

        XCTAssertNotNil(result, "Should successfully deserialize even with extra keys")
        XCTAssertEqual(result?.foreground, .red)
        XCTAssertEqual(result?.background, .blue)
    }

    // MARK: - Font Bridge Tests

    func testFontBridgeDeserializeWithCorruptedData() {
        let corruptedData = Data([0xDE, 0xAD, 0xBE, 0xEF])
        let result = fontBridge.deserialize(corruptedData)
        XCTAssertNil(result, "Should return nil for corrupted font data")
    }

    func testFontBridgeDeserializeWithEmptyData() {
        let result = fontBridge.deserialize(Data())
        XCTAssertNil(result, "Should return nil for empty font data")
    }

    func testFontBridgeDeserializeWithNil() {
        let result = fontBridge.deserialize(nil)
        XCTAssertNil(result, "Should return nil for nil font data")
    }

    func testFontBridgeRoundTrip() {
        let originalFont = NSFont.boldSystemFont(ofSize: 14)
        let spaceFont = SpaceFont(font: originalFont)

        let serialized = fontBridge.serialize(spaceFont)
        XCTAssertNotNil(serialized)

        let deserialized = fontBridge.deserialize(serialized)
        XCTAssertNotNil(deserialized)
        XCTAssertEqual(deserialized?.font.pointSize, originalFont.pointSize)
    }

    // MARK: - Recovery from Bad State Tests

    func testPreferencesRecoverFromCorruptedStorage() {
        // Set valid preferences
        let validColors = SpaceColors(foreground: .red, background: .blue)
        SpacePreferences.setColors(validColors, forSpace: 1, store: store)

        // Verify retrieval works
        let retrieved = SpacePreferences.colors(forSpace: 1, store: store)
        XCTAssertNotNil(retrieved)

        // Clear and verify clean state
        SpacePreferences.clearColors(forSpace: 1, store: store)
        XCTAssertNil(SpacePreferences.colors(forSpace: 1, store: store))

        // Should be able to set again after clearing
        let newColors = SpaceColors(foreground: .green, background: .yellow)
        SpacePreferences.setColors(newColors, forSpace: 1, store: store)
        let newRetrieved = SpacePreferences.colors(forSpace: 1, store: store)
        XCTAssertEqual(newRetrieved?.foreground, .green)
    }
}
