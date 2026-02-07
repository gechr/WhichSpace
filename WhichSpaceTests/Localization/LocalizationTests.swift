import Foundation
import Testing

@Suite("Localization")
struct LocalizationTests {
    /// All supported languages in Localizable.xcstrings
    private static let expectedLanguages: Set<String> = [
        "ar", "bg", "ca", "cs", "da", "de", "el", "en", "en-GB", "es",
        "fa", "fi", "fr", "he", "hi", "hu", "id", "it", "ja", "ko",
        "mk", "ms", "nb", "nl", "nn", "pa", "pl", "ps", "pt", "pt-BR",
        "ro", "ru", "sk", "sr", "sv", "th", "tr", "uk", "ur", "vi",
        "zh-Hans", "zh-Hant", "zh-HK",
    ]

    private static let catalogURL: URL = .init(fileURLWithPath: #filePath)
        .deletingLastPathComponent() // Remove LocalizationTests.swift
        .deletingLastPathComponent() // Remove Localization
        .deletingLastPathComponent() // Remove WhichSpaceTests
        .appendingPathComponent("WhichSpace")
        .appendingPathComponent("Localization")
        .appendingPathComponent("Localizable.xcstrings")

    // MARK: - Tests

    @Test("all expected languages exist")
    func allExpectedLanguagesExist() throws {
        let catalog = try loadCatalog()
        let actualLanguages = allLanguages(in: catalog)

        let missingLanguages = Self.expectedLanguages.subtracting(actualLanguages)
        let unexpectedLanguages = actualLanguages.subtracting(Self.expectedLanguages)

        #expect(
            missingLanguages.isEmpty,
            "Missing language entries: \(missingLanguages.sorted().joined(separator: ", "))"
        )
        #expect(
            unexpectedLanguages.isEmpty,
            "Unexpected language entries: \(unexpectedLanguages.sorted().joined(separator: ", "))"
        )
    }

    @Test("no missing translations")
    func noMissingTranslations() throws {
        let catalog = try loadCatalog()
        let keys = catalog.strings.keys.sorted()
        var failures: [String] = []

        for language in Self.expectedLanguages.sorted() {
            var missingKeys: [String] = []
            for key in keys {
                guard let localization = catalog.strings[key]?.localizations[language],
                      hasTranslation(localization)
                else {
                    missingKeys.append(key)
                    continue
                }
            }

            if !missingKeys.isEmpty {
                failures.append(
                    "\(language): missing \(missingKeys.count) key(s): " +
                        "\(missingKeys.joined(separator: ", "))"
                )
            }
        }

        #expect(
            failures.isEmpty,
            "Languages with missing translations:\n\(failures.joined(separator: "\n"))"
        )
    }

    @Test("no extra translations")
    func noExtraTranslations() throws {
        let catalog = try loadCatalog()
        var failures: [String] = []

        for (key, entry) in catalog.strings {
            let languages = Set(entry.localizations.keys)
            let unexpectedLanguages = languages.subtracting(Self.expectedLanguages)

            if !unexpectedLanguages.isEmpty {
                failures.append(
                    "\(key): unexpected language entries: " +
                        "\(unexpectedLanguages.sorted().joined(separator: ", "))"
                )
            }
        }

        #expect(
            failures.isEmpty,
            "Strings with unexpected language entries:\n\(failures.sorted().joined(separator: "\n"))"
        )
    }

    // MARK: - Helpers

    private func loadCatalog() throws -> StringCatalog {
        let data = try Data(contentsOf: Self.catalogURL)
        return try JSONDecoder().decode(StringCatalog.self, from: data)
    }

    private func allLanguages(in catalog: StringCatalog) -> Set<String> {
        var languages: Set<String> = [catalog.sourceLanguage]
        for entry in catalog.strings.values {
            languages.formUnion(entry.localizations.keys)
        }
        return languages
    }

    private func hasTranslation(_ localization: Localization) -> Bool {
        if let value = localization.stringUnit?.value, !value.isEmpty {
            return true
        }
        if let plural = localization.variations?.plural,
           plural.values.contains(where: { ($0.stringUnit?.value?.isEmpty == false) })
        {
            return true
        }
        if let device = localization.variations?.device,
           device.values.contains(where: { ($0.stringUnit?.value?.isEmpty == false) })
        {
            return true
        }
        return false
    }
}

private struct StringCatalog: Decodable {
    let sourceLanguage: String
    let strings: [String: StringEntry]
    let version: String?
}

private struct StringEntry: Decodable {
    let localizations: [String: Localization]

    private enum CodingKeys: String, CodingKey {
        case localizations
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        localizations = try container.decodeIfPresent([String: Localization].self, forKey: .localizations) ?? [:]
    }
}

private struct Localization: Decodable {
    let stringUnit: StringUnit?
    let variations: Variations?
}

private struct StringUnit: Decodable {
    let value: String?
}

private struct Variations: Decodable {
    let plural: [String: Variation]
    let device: [String: Variation]

    private enum CodingKeys: String, CodingKey {
        case plural
        case device
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        plural = try container.decodeIfPresent([String: Variation].self, forKey: .plural) ?? [:]
        device = try container.decodeIfPresent([String: Variation].self, forKey: .device) ?? [:]
    }
}

private struct Variation: Decodable {
    let stringUnit: StringUnit?
}
