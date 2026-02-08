import AppKit
import Testing
import XCTest
@testable import WhichSpace

// MARK: - CodableColor Tests

@Suite("CodableColor")
struct CodableColorTests {
    @Test("round-trip conversion preserves red")
    func roundTripConversion() {
        let original = NSColor.red
        let codable = CodableColor(from: original)
        let restored = codable.toNSColor()

        #expect(abs(restored.redComponent - 1.0) < 0.001)
        #expect(abs(restored.greenComponent - 0.0) < 0.001)
        #expect(abs(restored.blueComponent - 0.0) < 0.001)
        #expect(abs(restored.alphaComponent - 1.0) < 0.001)
    }

    @Test("preserves alpha component")
    func preservesAlpha() {
        let original = NSColor.blue.withAlphaComponent(0.5)
        let codable = CodableColor(from: original)
        let restored = codable.toNSColor()

        #expect(abs(restored.alphaComponent - 0.5) < 0.001)
    }

    @Test("custom color round-trip")
    func customColor() {
        let original = NSColor(red: 0.25, green: 0.5, blue: 0.75, alpha: 0.9)
        let codable = CodableColor(from: original)
        let restored = codable.toNSColor()

        #expect(abs(restored.redComponent - 0.25) < 0.001)
        #expect(abs(restored.greenComponent - 0.5) < 0.001)
        #expect(abs(restored.blueComponent - 0.75) < 0.001)
        #expect(abs(restored.alphaComponent - 0.9) < 0.001)
    }

    @Test("JSON encode/decode round-trip")
    func jsonEncodeDecode() throws {
        let original = CodableColor(from: NSColor.green)
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(CodableColor.self, from: data)

        #expect(abs(decoded.red - original.red) < 0.001)
        #expect(abs(decoded.green - original.green) < 0.001)
        #expect(abs(decoded.blue - original.blue) < 0.001)
        #expect(abs(decoded.alpha - original.alpha) < 0.001)
    }
}

// MARK: - CodableSpaceColors Tests

@Suite("CodableSpaceColors")
struct CodableSpaceColorsTests {
    @Test("round-trip conversion preserves white/black")
    func roundTripConversion() throws {
        let original = SpaceColors(foreground: .white, background: .black)
        let codable = CodableSpaceColors(from: original)
        let restored = try #require(codable.toSpaceColors())

        #expect(abs(restored.foreground.redComponent - 1.0) < 0.001)
        #expect(abs(restored.foreground.greenComponent - 1.0) < 0.001)
        #expect(abs(restored.foreground.blueComponent - 1.0) < 0.001)
        #expect(abs(restored.background.redComponent - 0.0) < 0.001)
        #expect(abs(restored.background.greenComponent - 0.0) < 0.001)
        #expect(abs(restored.background.blueComponent - 0.0) < 0.001)
    }

    @Test("JSON encode/decode round-trip")
    func jsonEncodeDecode() throws {
        let original = CodableSpaceColors(from: SpaceColors(foreground: .red, background: .blue))
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(CodableSpaceColors.self, from: data)

        #expect(abs(decoded.foreground.red - original.foreground.red) < 0.001)
        #expect(abs(decoded.background.blue - original.background.blue) < 0.001)
    }
}

// MARK: - CodableSpaceFont Tests

@Suite("CodableSpaceFont")
struct CodableSpaceFontTests {
    @Test("round-trip conversion preserves point size")
    func roundTripConversion() throws {
        let originalFont = NSFont.systemFont(ofSize: 14)
        let original = SpaceFont(font: originalFont)
        let codable = CodableSpaceFont(from: original)
        let restored = try #require(codable.toSpaceFont())

        #expect(restored.font.pointSize == 14)
    }

    @Test("preserves font name")
    func preservesFontName() {
        let originalFont = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        let original = SpaceFont(font: originalFont)
        let codable = CodableSpaceFont(from: original)

        #expect(codable.name == originalFont.fontName)
        #expect(codable.size == 12)
    }

    @Test("JSON encode/decode round-trip")
    func jsonEncodeDecode() throws {
        let original = CodableSpaceFont(from: SpaceFont(font: NSFont.systemFont(ofSize: 16)))
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(CodableSpaceFont.self, from: data)

        #expect(decoded.name == original.name)
        #expect(decoded.size == original.size)
    }

    @Test("invalid font name returns nil")
    func invalidFontReturnsNil() throws {
        let jsonString = """
        {"name": "NonExistentFontName12345", "size": 12.0}
        """
        let data = try #require(jsonString.data(using: .utf8))
        let decoded = try? JSONDecoder().decode(CodableSpaceFont.self, from: data)

        #expect(decoded != nil)
        #expect(decoded?.toSpaceFont() == nil)
    }
}

// MARK: - BackupSpacePreferences Tests

@Suite("BackupSpacePreferences")
// swiftlint:disable:next type_body_length
struct BackupSpacePreferencesTests {
    @Test("empty initialization has empty collections")
    func emptyInitialization() {
        let prefs = BackupSpacePreferences()

        #expect(prefs.colors.isEmpty)
        #expect(prefs.fonts.isEmpty)
        #expect(prefs.iconStyles.isEmpty)
        #expect(prefs.skinTones.isEmpty)
        #expect(prefs.symbols.isEmpty)
    }

    @Test("colors conversion round-trip")
    func colorsConversion() {
        let colors: [Int: SpaceColors] = [
            1: SpaceColors(foreground: .red, background: .blue),
            2: SpaceColors(foreground: .green, background: .yellow),
        ]
        let prefs = BackupSpacePreferences(colors: colors)

        #expect(prefs.colors.count == 2)
        #expect(prefs.colors["1"] != nil)
        #expect(prefs.colors["2"] != nil)

        let restored = prefs.toSpaceColors()
        #expect(restored.count == 2)
        #expect(restored[1] != nil)
        #expect(restored[2] != nil)
    }

    // swiftlint:disable:next function_body_length
    @Test("icon styles conversion round-trip")
    func iconStylesConversion() {
        let styles: [Int: IconStyle] = [
            1: .circle,
            2: .hexagon,
            3: .square,
        ]
        let prefs = BackupSpacePreferences(iconStyles: styles)

        #expect(prefs.iconStyles["1"] == "circle")
        #expect(prefs.iconStyles["2"] == "hexagon")
        #expect(prefs.iconStyles["3"] == "square")

        let restored = prefs.toIconStyles()
        #expect(restored[1] == .circle)
        #expect(restored[2] == .hexagon)
        #expect(restored[3] == .square)
    }

    @Test("skin tones conversion round-trip")
    func skinTonesConversion() {
        let tones: [Int: SkinTone] = [
            1: .light,
            2: .mediumLight,
            3: .medium,
        ]
        let prefs = BackupSpacePreferences(skinTones: tones)

        let restored = prefs.toSkinTones()
        #expect(restored[1] == .light)
        #expect(restored[2] == .mediumLight)
        #expect(restored[3] == .medium)
    }

    @Test("symbols conversion round-trip")
    func symbolsConversion() {
        let symbols: [Int: String] = [
            1: "star.fill",
            2: "heart.fill",
            3: "moon.fill",
        ]
        let prefs = BackupSpacePreferences(symbols: symbols)

        #expect(prefs.symbols["1"] == "star.fill")
        #expect(prefs.symbols["2"] == "heart.fill")
        #expect(prefs.symbols["3"] == "moon.fill")

        let restored = prefs.toSymbols()
        #expect(restored[1] == "star.fill")
        #expect(restored[2] == "heart.fill")
        #expect(restored[3] == "moon.fill")
    }

    @Test("invalid non-numeric key is ignored")
    func invalidKeyIsIgnored() throws {
        let jsonString = """
        {
            "colors": {},
            "fonts": {},
            "iconStyles": {"invalid": "circle", "1": "square"},
            "skinTones": {},
            "symbols": {}
        }
        """
        let data = try #require(jsonString.data(using: .utf8))
        let decoded = try? JSONDecoder().decode(BackupSpacePreferences.self, from: data)

        #expect(decoded != nil)
        let restored = decoded?.toIconStyles()
        #expect(restored?.count == 1)
        #expect(restored?[1] == .square)
    }
}

// MARK: - BackupManager Tests

final class BackupManagerTests: IsolatedDefaultsTestCase {
    // swiftlint:disable line_length
    // MARK: - Encode/Decode Tests

    func testDecodeValidJSON() throws {
        let json = """
        {
            "bundleId": "com.test.app",
            "version": "1.0.0",
            "settings": {
                "clickToSwitchSpaces": true,
                "dimInactiveSpaces": false,
                "hideEmptySpaces": true,
                "hideFullscreenApps": false,
                "hideSingleSpace": true,
                "launchAtLogin": false,
                "localSpaceNumbers": false,
                "showAllDisplays": true,
                "showAllSpaces": false,
                "sizeScale": 80.0,
                "soundName": "Pop",
                "uniqueIconsPerDisplay": true
            },
            "spacePreferences": {
                "colors": {},
                "fonts": {},
                "iconStyles": {},
                "skinTones": {},
                "symbols": {}
            },
            "displaySpacePreferences": {}
        }
        """

        let backup = try BackupManager.decode(jsonString: json)

        XCTAssertEqual(backup.bundleId, "com.test.app")
        XCTAssertEqual(backup.version, "1.0.0")
        XCTAssertTrue(backup.settings.clickToSwitchSpaces)
        XCTAssertFalse(backup.settings.dimInactiveSpaces)
        XCTAssertEqual(backup.settings.sizeScale, 80.0)
        XCTAssertEqual(backup.settings.soundName, "Pop")
    }

    func testDecodeInvalidJSONThrows() {
        let invalidJSON = "{ invalid json }"
        XCTAssertThrowsError(try BackupManager.decode(jsonString: invalidJSON)) { error in
            XCTAssertTrue(error is BackupError)
        }
    }

    func testDecodeEmptyStringThrows() {
        XCTAssertThrowsError(try BackupManager.decode(jsonString: "")) { error in
            XCTAssertTrue(error is BackupError)
        }
    }

    // MARK: - Apply Tests

    func testApplyUpdatesGlobalSettings() throws {
        let json = """
        {
            "bundleId": "com.test.app",
            "version": "1.0.0",
            "settings": {
                "clickToSwitchSpaces": true,
                "dimInactiveSpaces": true,
                "hideEmptySpaces": true,
                "hideFullscreenApps": true,
                "hideSingleSpace": true,
                "launchAtLogin": true,
                "localSpaceNumbers": true,
                "showAllDisplays": true,
                "showAllSpaces": true,
                "sizeScale": 75.0,
                "soundName": "Blow",
                "uniqueIconsPerDisplay": true
            },
            "spacePreferences": {
                "colors": {},
                "fonts": {},
                "iconStyles": {},
                "skinTones": {},
                "symbols": {}
            },
            "displaySpacePreferences": {}
        }
        """

        let backup = try BackupManager.decode(jsonString: json)
        BackupManager.apply(backup, to: store)

        XCTAssertTrue(store.clickToSwitchSpaces)
        XCTAssertTrue(store.dimInactiveSpaces)
        XCTAssertTrue(store.hideEmptySpaces)
        XCTAssertTrue(store.hideFullscreenApps)
        XCTAssertTrue(store.hideSingleSpace)
        XCTAssertTrue(store.localSpaceNumbers)
        XCTAssertTrue(store.showAllDisplays)
        XCTAssertTrue(store.showAllSpaces)
        XCTAssertEqual(store.sizeScale, 75.0)
        XCTAssertEqual(store.soundName, "Blow")
        XCTAssertTrue(store.uniqueIconsPerDisplay)
    }

    func testApplyUpdatesSpacePreferences() throws {
        let json = """
        {
            "bundleId": "com.test.app",
            "version": "1.0.0",
            "settings": {
                "clickToSwitchSpaces": false,
                "dimInactiveSpaces": false,
                "hideEmptySpaces": false,
                "hideFullscreenApps": false,
                "hideSingleSpace": false,
                "launchAtLogin": false,
                "localSpaceNumbers": false,
                "showAllDisplays": false,
                "showAllSpaces": false,
                "sizeScale": 100.0,
                "soundName": "",
                "uniqueIconsPerDisplay": false
            },
            "spacePreferences": {
                "colors": {
                    "1": {
                        "foreground": {"red": 1.0, "green": 0.0, "blue": 0.0, "alpha": 1.0},
                        "background": {"red": 0.0, "green": 0.0, "blue": 1.0, "alpha": 1.0}
                    }
                },
                "fonts": {},
                "iconStyles": {"1": "circle", "2": "hexagon"},
                "skinTones": {"1": 1},
                "symbols": {"1": "star.fill"}
            },
            "displaySpacePreferences": {}
        }
        """

        let backup = try BackupManager.decode(jsonString: json)
        BackupManager.apply(backup, to: store)

        XCTAssertEqual(store.spaceColors.count, 1)
        XCTAssertNotNil(store.spaceColors[1])
        XCTAssertEqual(store.spaceIconStyles[1], .circle)
        XCTAssertEqual(store.spaceIconStyles[2], .hexagon)
        XCTAssertEqual(store.spaceSkinTones[1], .light)
        XCTAssertEqual(store.spaceSymbols[1], "star.fill")
    }

    func testApplyUpdatesDisplaySpacePreferences() throws {
        let json = """
        {
            "bundleId": "com.test.app",
            "version": "1.0.0",
            "settings": {
                "clickToSwitchSpaces": false,
                "dimInactiveSpaces": false,
                "hideEmptySpaces": false,
                "hideFullscreenApps": false,
                "hideSingleSpace": false,
                "launchAtLogin": false,
                "localSpaceNumbers": false,
                "showAllDisplays": false,
                "showAllSpaces": false,
                "sizeScale": 100.0,
                "soundName": "",
                "uniqueIconsPerDisplay": true
            },
            "spacePreferences": {
                "colors": {},
                "fonts": {},
                "iconStyles": {},
                "skinTones": {},
                "symbols": {}
            },
            "displaySpacePreferences": {
                "Display1": {
                    "colors": {},
                    "fonts": {},
                    "iconStyles": {"1": "triangle"},
                    "skinTones": {},
                    "symbols": {"1": "moon.fill"}
                },
                "Display2": {
                    "colors": {},
                    "fonts": {},
                    "iconStyles": {"1": "square"},
                    "skinTones": {},
                    "symbols": {}
                }
            }
        }
        """

        let backup = try BackupManager.decode(jsonString: json)
        BackupManager.apply(backup, to: store)

        XCTAssertEqual(store.displaySpaceIconStyles["Display1"]?[1], .triangle)
        XCTAssertEqual(store.displaySpaceSymbols["Display1"]?[1], "moon.fill")
        XCTAssertEqual(store.displaySpaceIconStyles["Display2"]?[1], .square)
    }

    func testApplyPostsNotification() throws {
        let json = """
        {
            "bundleId": "com.test.app",
            "version": "1.0.0",
            "settings": {
                "clickToSwitchSpaces": false,
                "dimInactiveSpaces": false,
                "hideEmptySpaces": false,
                "hideFullscreenApps": false,
                "hideSingleSpace": false,
                "launchAtLogin": false,
                "localSpaceNumbers": false,
                "showAllDisplays": false,
                "showAllSpaces": false,
                "sizeScale": 100.0,
                "soundName": "",
                "uniqueIconsPerDisplay": false
            },
            "spacePreferences": {
                "colors": {},
                "fonts": {},
                "iconStyles": {},
                "skinTones": {},
                "symbols": {}
            },
            "displaySpacePreferences": {}
        }
        """

        let backup = try BackupManager.decode(jsonString: json)

        let expectation = expectation(forNotification: .backupImported, object: nil)
        BackupManager.apply(backup, to: store)

        wait(for: [expectation], timeout: 1.0)
    }

    func testApplySeparatorColor() throws {
        let json = """
        {
            "bundleId": "com.test.app",
            "version": "1.0.0",
            "settings": {
                "clickToSwitchSpaces": false,
                "dimInactiveSpaces": false,
                "hideEmptySpaces": false,
                "hideFullscreenApps": false,
                "hideSingleSpace": false,
                "launchAtLogin": false,
                "localSpaceNumbers": false,
                "separatorColor": {"red": 0.5, "green": 0.5, "blue": 0.5, "alpha": 1.0},
                "showAllDisplays": false,
                "showAllSpaces": false,
                "sizeScale": 100.0,
                "soundName": "",
                "uniqueIconsPerDisplay": false
            },
            "spacePreferences": {
                "colors": {},
                "fonts": {},
                "iconStyles": {},
                "skinTones": {},
                "symbols": {}
            },
            "displaySpacePreferences": {}
        }
        """

        let backup = try BackupManager.decode(jsonString: json)
        BackupManager.apply(backup, to: store)

        XCTAssertNotNil(store.separatorColor)
        XCTAssertEqual(Double(store.separatorColor?.redComponent ?? 0), 0.5, accuracy: 0.001)
    }

    // MARK: - File Operations Tests

    func testExportAndLoadRoundTrip() throws {
        // Set up some settings
        store.showAllSpaces = true
        store.sizeScale = 85.0
        store.soundName = "TestSound"
        store.spaceColors = [1: SpaceColors(foreground: .red, background: .blue)]
        store.spaceIconStyles = [1: .circle, 2: .hexagon]
        store.spaceSymbols = [1: "star.fill"]

        // Export to temp file
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("test_backup.json")

        // Clean up any existing file
        try? FileManager.default.removeItem(at: tempURL)

        try BackupManager.export(to: tempURL, store: store)

        // Verify file exists
        XCTAssertTrue(FileManager.default.fileExists(atPath: tempURL.path))

        // Reset store
        store.resetAll()
        XCTAssertFalse(store.showAllSpaces)
        XCTAssertEqual(store.sizeScale, Layout.defaultSizeScale)

        // Load from file
        try BackupManager.load(from: tempURL, store: store)

        // Verify settings restored
        XCTAssertTrue(store.showAllSpaces)
        XCTAssertEqual(store.sizeScale, 85.0)
        XCTAssertEqual(store.soundName, "TestSound")
        XCTAssertEqual(store.spaceIconStyles[1], .circle)
        XCTAssertEqual(store.spaceIconStyles[2], .hexagon)
        XCTAssertEqual(store.spaceSymbols[1], "star.fill")

        // Clean up
        try? FileManager.default.removeItem(at: tempURL)
    }

    func testLoadFromNonexistentFileThrows() {
        let fakeURL = URL(fileURLWithPath: "/nonexistent/path/settings.json")
        XCTAssertThrowsError(try BackupManager.load(from: fakeURL, store: store)) { error in
            guard case BackupError.fileReadFailed = error else {
                XCTFail("Expected fileReadFailed, got \(error)")
                return
            }
        }
    }

    func testLoadFromInvalidJSONThrows() throws {
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("invalid_backup.json")

        try "{ invalid json }".write(to: tempURL, atomically: true, encoding: .utf8)

        XCTAssertThrowsError(try BackupManager.load(from: tempURL, store: store)) { error in
            XCTAssertTrue(error is BackupError)
        }

        try? FileManager.default.removeItem(at: tempURL)
    }

    // MARK: - Default Filename Test

    func testDefaultFilename() {
        XCTAssertEqual(BackupManager.defaultFilename, "WhichSpaceSettings.json")
    }
    // swiftlint:enable line_length
}
