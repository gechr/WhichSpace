import XCTest

final class LocalizationTests: XCTestCase {
    /// All supported languages (directories under Locale/)
    private static let expectedLanguages: Set<String> = [
        "ar", "bg", "ca", "cs", "da", "de", "el", "en", "en-GB", "es",
        "fa", "fi", "fr", "he", "hi", "hu", "id", "it", "ja", "ko",
        "mk", "ms", "nb", "nl", "nn", "pa", "pl", "ps", "pt", "pt-BR",
        "ro", "ru", "sk", "sr", "sv", "th", "tr", "uk", "ur", "vi",
        "zh-Hans", "zh-Hant", "zh-HK",
    ]

    // Derive path at compile time from this source file's location
    // This file: WhichSpaceTests/Locale/LocalizationTests.swift
    // Target:    WhichSpace/Locale/
    private static let localeURL: URL = .init(fileURLWithPath: #file)
        .deletingLastPathComponent() // Remove LocalizationTests.swift
        .deletingLastPathComponent() // Remove Locale
        .deletingLastPathComponent() // Remove WhichSpaceTests
        .appendingPathComponent("WhichSpace")
        .appendingPathComponent("Locale")

    // MARK: - Tests

    func testAllExpectedLanguagesExist() throws {
        let actualLanguages = try findAllLanguages()

        let missingLanguages = Self.expectedLanguages.subtracting(actualLanguages)
        let unexpectedLanguages = actualLanguages.subtracting(Self.expectedLanguages)

        XCTAssertTrue(
            missingLanguages.isEmpty,
            "Missing language directories: \(missingLanguages.sorted().joined(separator: ", "))"
        )
        XCTAssertTrue(
            unexpectedLanguages.isEmpty,
            "Unexpected language directories (add to expectedLanguages if intentional): " +
                "\(unexpectedLanguages.sorted().joined(separator: ", "))"
        )
    }

    func testNoMissingTranslations() throws {
        let englishKeys = try loadKeys(for: "en")
        var failures: [String] = []

        for language in try findAllLanguages() where language != "en" {
            let languageKeys = try loadKeys(for: language)
            let missingKeys = englishKeys.subtracting(languageKeys)

            if !missingKeys.isEmpty {
                failures.append(
                    "\(language): missing \(missingKeys.count) key(s): " +
                        "\(missingKeys.sorted().joined(separator: ", "))"
                )
            }
        }

        XCTAssertTrue(
            failures.isEmpty,
            "Languages with missing translations:\n\(failures.joined(separator: "\n"))"
        )
    }

    func testNoExtraTranslations() throws {
        let englishKeys = try loadKeys(for: "en")
        var failures: [String] = []

        for language in try findAllLanguages() where language != "en" {
            let languageKeys = try loadKeys(for: language)
            let extraKeys = languageKeys.subtracting(englishKeys)

            if !extraKeys.isEmpty {
                failures.append(
                    "\(language): extra \(extraKeys.count) key(s): " +
                        "\(extraKeys.sorted().joined(separator: ", "))"
                )
            }
        }

        XCTAssertTrue(
            failures.isEmpty,
            "Languages with extra translations (not in English):\n\(failures.joined(separator: "\n"))"
        )
    }

    // MARK: - Helpers

    private func findAllLanguages() throws -> Set<String> {
        let contents = try FileManager.default.contentsOfDirectory(
            at: Self.localeURL,
            includingPropertiesForKeys: [.isDirectoryKey]
        )

        return Set(
            contents.compactMap { url -> String? in
                guard url.pathExtension == "lproj" else {
                    return nil
                }
                return url.deletingPathExtension().lastPathComponent
            }
        )
    }

    private func loadKeys(for language: String) throws -> Set<String> {
        let stringsFile = Self.localeURL
            .appendingPathComponent("\(language).lproj")
            .appendingPathComponent("Localizable.strings")

        let content = try String(contentsOf: stringsFile, encoding: .utf8)
        return parseKeys(from: content)
    }

    private func parseKeys(from content: String) -> Set<String> {
        // Parse .strings file format: "key" = "value";
        let pattern = #/^\s*"([^"]+)"\s*=\s*"/#

        var keys: Set<String> = []
        for line in content.split(separator: "\n", omittingEmptySubsequences: false) {
            if let match = String(line).firstMatch(of: pattern) {
                keys.insert(String(match.1))
            }
        }
        return keys
    }
}
