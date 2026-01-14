import XCTest
@testable import WhichSpace

// MARK: - CodableColor Tests

final class CodableColorTests: XCTestCase {
    func testRoundTripConversion() {
        let original = NSColor.red
        let codable = CodableColor(from: original)
        let restored = codable.toNSColor()

        XCTAssertEqual(restored.redComponent, 1.0, accuracy: 0.001)
        XCTAssertEqual(restored.greenComponent, 0.0, accuracy: 0.001)
        XCTAssertEqual(restored.blueComponent, 0.0, accuracy: 0.001)
        XCTAssertEqual(restored.alphaComponent, 1.0, accuracy: 0.001)
    }

    func testPreservesAlpha() {
        let original = NSColor.blue.withAlphaComponent(0.5)
        let codable = CodableColor(from: original)
        let restored = codable.toNSColor()

        XCTAssertEqual(restored.alphaComponent, 0.5, accuracy: 0.001)
    }

    func testCustomColor() {
        let original = NSColor(red: 0.25, green: 0.5, blue: 0.75, alpha: 0.9)
        let codable = CodableColor(from: original)
        let restored = codable.toNSColor()

        XCTAssertEqual(restored.redComponent, 0.25, accuracy: 0.001)
        XCTAssertEqual(restored.greenComponent, 0.5, accuracy: 0.001)
        XCTAssertEqual(restored.blueComponent, 0.75, accuracy: 0.001)
        XCTAssertEqual(restored.alphaComponent, 0.9, accuracy: 0.001)
    }

    func testJSONEncodeDecode() throws {
        let original = CodableColor(from: NSColor.green)
        let encoder = JSONEncoder()
        let data = try encoder.encode(original)
        let decoder = JSONDecoder()
        let decoded = try decoder.decode(CodableColor.self, from: data)

        XCTAssertEqual(decoded.red, original.red, accuracy: 0.001)
        XCTAssertEqual(decoded.green, original.green, accuracy: 0.001)
        XCTAssertEqual(decoded.blue, original.blue, accuracy: 0.001)
        XCTAssertEqual(decoded.alpha, original.alpha, accuracy: 0.001)
    }
}

// MARK: - CodableSpaceColors Tests

final class CodableSpaceColorsTests: XCTestCase {
    func testRoundTripConversion() {
        let original = SpaceColors(foreground: .white, background: .black)
        let codable = CodableSpaceColors(from: original)
        let restored = codable.toSpaceColors()

        XCTAssertNotNil(restored)
        guard let restored else {
            return
        }
        // White foreground
        XCTAssertEqual(restored.foreground.redComponent, 1.0, accuracy: 0.001)
        XCTAssertEqual(restored.foreground.greenComponent, 1.0, accuracy: 0.001)
        XCTAssertEqual(restored.foreground.blueComponent, 1.0, accuracy: 0.001)
        // Black background
        XCTAssertEqual(restored.background.redComponent, 0.0, accuracy: 0.001)
        XCTAssertEqual(restored.background.greenComponent, 0.0, accuracy: 0.001)
        XCTAssertEqual(restored.background.blueComponent, 0.0, accuracy: 0.001)
    }

    func testJSONEncodeDecode() throws {
        let original = CodableSpaceColors(from: SpaceColors(foreground: .red, background: .blue))
        let encoder = JSONEncoder()
        let data = try encoder.encode(original)
        let decoder = JSONDecoder()
        let decoded = try decoder.decode(CodableSpaceColors.self, from: data)

        XCTAssertEqual(decoded.foreground.red, original.foreground.red, accuracy: 0.001)
        XCTAssertEqual(decoded.background.blue, original.background.blue, accuracy: 0.001)
    }
}

// MARK: - CodableSpaceFont Tests

final class CodableSpaceFontTests: XCTestCase {
    func testRoundTripConversion() {
        let originalFont = NSFont.systemFont(ofSize: 14)
        let original = SpaceFont(font: originalFont)
        let codable = CodableSpaceFont(from: original)
        let restored = codable.toSpaceFont()

        XCTAssertNotNil(restored)
        XCTAssertEqual(restored?.font.pointSize, 14)
    }

    func testPreservesFontName() {
        let originalFont = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        let original = SpaceFont(font: originalFont)
        let codable = CodableSpaceFont(from: original)

        XCTAssertEqual(codable.name, originalFont.fontName)
        XCTAssertEqual(codable.size, 12)
    }

    func testJSONEncodeDecode() throws {
        let original = CodableSpaceFont(from: SpaceFont(font: NSFont.systemFont(ofSize: 16)))
        let encoder = JSONEncoder()
        let data = try encoder.encode(original)
        let decoder = JSONDecoder()
        let decoded = try decoder.decode(CodableSpaceFont.self, from: data)

        XCTAssertEqual(decoded.name, original.name)
        XCTAssertEqual(decoded.size, original.size)
    }

    func testInvalidFontReturnsNil() {
        // Create a CodableSpaceFont with an invalid font name
        let jsonString = """
        {"name": "NonExistentFontName12345", "size": 12.0}
        """
        let data = jsonString.data(using: .utf8)!
        let decoded = try? JSONDecoder().decode(CodableSpaceFont.self, from: data)

        XCTAssertNotNil(decoded)
        XCTAssertNil(decoded?.toSpaceFont())
    }
}

// MARK: - BackupSpacePreferences Tests

final class BackupSpacePreferencesTests: XCTestCase {
    // swiftlint:disable line_length
    func testEmptyInitialization() {
        let prefs = BackupSpacePreferences()

        XCTAssertTrue(prefs.colors.isEmpty)
        XCTAssertTrue(prefs.fonts.isEmpty)
        XCTAssertTrue(prefs.iconStyles.isEmpty)
        XCTAssertTrue(prefs.skinTones.isEmpty)
        XCTAssertTrue(prefs.symbols.isEmpty)
    }

    func testColorsConversion() {
        let colors: [Int: SpaceColors] = [
            1: SpaceColors(foreground: .red, background: .blue),
            2: SpaceColors(foreground: .green, background: .yellow),
        ]
        let prefs = BackupSpacePreferences(colors: colors)

        XCTAssertEqual(prefs.colors.count, 2)
        XCTAssertNotNil(prefs.colors["1"])
        XCTAssertNotNil(prefs.colors["2"])

        let restored = prefs.toSpaceColors()
        XCTAssertEqual(restored.count, 2)
        XCTAssertNotNil(restored[1])
        XCTAssertNotNil(restored[2])
    }

    func testIconStylesConversion() {
        let styles: [Int: IconStyle] = [
            1: .circle,
            2: .hexagon,
            3: .square,
        ]
        let prefs = BackupSpacePreferences(iconStyles: styles)

        XCTAssertEqual(prefs.iconStyles["1"], "circle")
        XCTAssertEqual(prefs.iconStyles["2"], "hexagon")
        XCTAssertEqual(prefs.iconStyles["3"], "square")

        let restored = prefs.toIconStyles()
        XCTAssertEqual(restored[1], .circle)
        XCTAssertEqual(restored[2], .hexagon)
        XCTAssertEqual(restored[3], .square)
    }

    func testSkinTonesConversion() {
        let tones: [Int: SkinTone] = [
            1: .light,
            2: .mediumLight,
            3: .medium,
        ]
        let prefs = BackupSpacePreferences(skinTones: tones)

        let restored = prefs.toSkinTones()
        XCTAssertEqual(restored[1], .light)
        XCTAssertEqual(restored[2], .mediumLight)
        XCTAssertEqual(restored[3], .medium)
    }

    func testSymbolsConversion() {
        let symbols: [Int: String] = [
            1: "star.fill",
            2: "heart.fill",
            3: "moon.fill",
        ]
        let prefs = BackupSpacePreferences(symbols: symbols)

        XCTAssertEqual(prefs.symbols["1"], "star.fill")
        XCTAssertEqual(prefs.symbols["2"], "heart.fill")
        XCTAssertEqual(prefs.symbols["3"], "moon.fill")

        let restored = prefs.toSymbols()
        XCTAssertEqual(restored[1], "star.fill")
        XCTAssertEqual(restored[2], "heart.fill")
        XCTAssertEqual(restored[3], "moon.fill")
    }

    func testInvalidKeyIsIgnored() {
        // Create JSON with invalid non-numeric key
        let jsonString = """
        {
            "colors": {},
            "fonts": {},
            "iconStyles": {"invalid": "circle", "1": "square"},
            "skinTones": {},
            "symbols": {}
        }
        """
        let data = jsonString.data(using: .utf8)!
        let decoded = try? JSONDecoder().decode(BackupSpacePreferences.self, from: data)

        XCTAssertNotNil(decoded)
        let restored = decoded?.toIconStyles()
        // "invalid" key should be ignored, only "1" should be present
        XCTAssertEqual(restored?.count, 1)
        XCTAssertEqual(restored?[1], .square)
    }
    // swiftlint:enable line_length
}

// MARK: - BackupManager Tests

final class BackupManagerTests: IsolatedDefaultsTestCase {
    // swiftlint:disable line_length
    // MARK: - Encode/Decode Tests

    func testDecodeValidJSON() {
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

        let backup = BackupManager.decode(jsonString: json)

        XCTAssertNotNil(backup)
        XCTAssertEqual(backup?.bundleId, "com.test.app")
        XCTAssertEqual(backup?.version, "1.0.0")
        XCTAssertTrue(backup?.settings.clickToSwitchSpaces ?? false)
        XCTAssertFalse(backup?.settings.dimInactiveSpaces ?? true)
        XCTAssertEqual(backup?.settings.sizeScale, 80.0)
        XCTAssertEqual(backup?.settings.soundName, "Pop")
    }

    func testDecodeInvalidJSONReturnsNil() {
        let invalidJSON = "{ invalid json }"
        let backup = BackupManager.decode(jsonString: invalidJSON)
        XCTAssertNil(backup)
    }

    func testDecodeEmptyStringReturnsNil() {
        let backup = BackupManager.decode(jsonString: "")
        XCTAssertNil(backup)
    }

    // MARK: - Apply Tests

    func testApplyUpdatesGlobalSettings() {
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

        let backup = BackupManager.decode(jsonString: json)!
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

    func testApplyUpdatesSpacePreferences() {
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

        let backup = BackupManager.decode(jsonString: json)!
        BackupManager.apply(backup, to: store)

        XCTAssertEqual(store.spaceColors.count, 1)
        XCTAssertNotNil(store.spaceColors[1])
        XCTAssertEqual(store.spaceIconStyles[1], .circle)
        XCTAssertEqual(store.spaceIconStyles[2], .hexagon)
        XCTAssertEqual(store.spaceSkinTones[1], .light)
        XCTAssertEqual(store.spaceSymbols[1], "star.fill")
    }

    func testApplyUpdatesDisplaySpacePreferences() {
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

        let backup = BackupManager.decode(jsonString: json)!
        BackupManager.apply(backup, to: store)

        XCTAssertEqual(store.displaySpaceIconStyles["Display1"]?[1], .triangle)
        XCTAssertEqual(store.displaySpaceSymbols["Display1"]?[1], "moon.fill")
        XCTAssertEqual(store.displaySpaceIconStyles["Display2"]?[1], .square)
    }

    func testApplyPostsNotification() {
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

        let backup = BackupManager.decode(jsonString: json)!

        let expectation = expectation(forNotification: .backupImported, object: nil)
        BackupManager.apply(backup, to: store)

        wait(for: [expectation], timeout: 1.0)
    }

    func testApplySeparatorColor() {
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

        let backup = BackupManager.decode(jsonString: json)!
        BackupManager.apply(backup, to: store)

        XCTAssertNotNil(store.separatorColor)
        XCTAssertEqual(Double(store.separatorColor?.redComponent ?? 0), 0.5, accuracy: 0.001)
    }

    // MARK: - File Operations Tests

    func testExportAndLoadRoundTrip() {
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

        let exportResult = BackupManager.export(to: tempURL, store: store)
        XCTAssertTrue(exportResult)

        // Verify file exists
        XCTAssertTrue(FileManager.default.fileExists(atPath: tempURL.path))

        // Reset store
        store.resetAll()
        XCTAssertFalse(store.showAllSpaces)
        XCTAssertEqual(store.sizeScale, Layout.defaultSizeScale)

        // Load from file
        let loadResult = BackupManager.load(from: tempURL, store: store)
        XCTAssertTrue(loadResult)

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

    func testLoadFromNonexistentFileReturnsFalse() {
        let fakeURL = URL(fileURLWithPath: "/nonexistent/path/settings.json")
        let result = BackupManager.load(from: fakeURL, store: store)
        XCTAssertFalse(result)
    }

    func testLoadFromInvalidJSONReturnsFalse() throws {
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("invalid_backup.json")

        try "{ invalid json }".write(to: tempURL, atomically: true, encoding: .utf8)

        let result = BackupManager.load(from: tempURL, store: store)
        XCTAssertFalse(result)

        try? FileManager.default.removeItem(at: tempURL)
    }

    // MARK: - Default Filename Test

    func testDefaultFilename() {
        XCTAssertEqual(BackupManager.defaultFilename, "WhichSpaceSettings.json")
    }
    // swiftlint:enable line_length
}
