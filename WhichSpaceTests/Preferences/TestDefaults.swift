import Defaults
import Foundation
import Testing
import XCTest
@testable import WhichSpace

/// UserDefaults is thread-safe but not marked Sendable in the SDK.
extension UserDefaults: @unchecked @retroactive Sendable {}

// MARK: - TestSuite

/// A test UserDefaults suite with its associated name.
struct TestSuite {
    let suite: UserDefaults
    let suiteName: String
}

// MARK: - TestSuiteFactory

/// Creates isolated UserDefaults suites for testing.
///
/// Uses real UserDefaults with unique suite names for test isolation.
/// Orphaned plist files from previous test runs are cleaned up automatically
/// at the start of each test run (cfprefsd prevents reliable cleanup of
/// current run's files).
enum TestSuiteFactory {
    private static let testSuitePrefix = "WhichSpaceTests"
    private static let plistSuffix = ".plist"
    private static let cleanupOnce: Void = {
        cleanupOrphanedTestFiles()
    }()

    /// Creates a new UserDefaults suite with a unique name.
    ///
    /// Each call returns a fresh, empty suite suitable for test isolation.
    /// The suite name includes a UUID to prevent collisions.
    static func createSuite() -> TestSuite {
        _ = cleanupOnce
        let name = "\(testSuitePrefix).\(UUID().uuidString)"
        return TestSuite(suite: UserDefaults(suiteName: name)!, suiteName: name)
    }

    /// Removes a test suite's persistent domain.
    ///
    /// Note: The plist file may remain on disk due to cfprefsd caching.
    /// These orphaned files are cleaned up at the start of the next test run.
    static func destroySuite(_ testSuite: TestSuite) {
        testSuite.suite.removePersistentDomain(forName: testSuite.suiteName)
    }

    /// Cleans up orphaned test plist files from previous test runs.
    ///
    /// Called once per test run. Files from previous runs are safe to delete
    /// because cfprefsd has long since forgotten about them.
    private static func cleanupOrphanedTestFiles() {
        let prefsURL = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first!
            .appendingPathComponent("Preferences")

        guard let files = try? FileManager.default.contentsOfDirectory(
            at: prefsURL,
            includingPropertiesForKeys: nil
        ) else { return }

        for file in files where isTestSuitePlist(filename: file.lastPathComponent) {
            try? FileManager.default.removeItem(at: file)
        }
    }

    /// Matches test suite plist filenames: "WhichSpaceTests.UUID.plist"
    private static func isTestSuitePlist(filename: String) -> Bool {
        let prefix = "\(testSuitePrefix)."
        guard filename.hasPrefix(prefix), filename.hasSuffix(plistSuffix) else {
            return false
        }

        let uuidStart = filename.index(filename.startIndex, offsetBy: prefix.count)
        let uuidEnd = filename.index(filename.endIndex, offsetBy: -plistSuffix.count)
        guard uuidStart < uuidEnd else {
            return false
        }

        let uuidString = String(filename[uuidStart ..< uuidEnd])
        return UUID(uuidString: uuidString) != nil
    }
}

// MARK: - IsolatedDefaultsTestCase

// Base class for test cases that need isolated Defaults.
//
// Each test gets its own `DefaultsStore` backed by a unique UserDefaults suite,
// providing complete isolation between tests.
//
// ## Parallel Test Safety
// Because each test uses its own suite, tests can safely run in parallel.
//
// ## Usage
// ```swift
// final class MyTests: IsolatedDefaultsTestCase {
//     func testSomething() {
//         // Use self.store for isolated Defaults access
//         store.showAllSpaces = true
//         XCTAssertTrue(store.showAllSpaces)
//     }
// }
// ```
// swiftformat:disable preferFinalClasses
@MainActor
// swiftlint:disable:next final_class final_test_case
class IsolatedDefaultsTestCase: XCTestCase {
    // swiftformat:enable preferFinalClasses

    // swiftlint:disable test_case_accessibility
    // The isolated store for this test, backed by a per-test suite.
    private(set) var store: DefaultsStore!

    /// The underlying UserDefaults suite (for direct access if needed).
    var suite: UserDefaults {
        store.suite
    }

    /// The test suite with its name.
    private var testSuite: TestSuite!
    // swiftlint:enable test_case_accessibility

    override func setUp() async throws {
        try await super.setUp()

        testSuite = TestSuiteFactory.createSuite()
        store = DefaultsStore(suite: testSuite.suite)
    }

    override func tearDown() async throws {
        if let store, let testSuite {
            store.resetAll()
            TestSuiteFactory.destroySuite(testSuite)
        }
        store = nil
        testSuite = nil
        try await super.tearDown()
    }
}

// MARK: - Defaults Isolation Guard Tests

/// Tests that verify the test isolation infrastructure itself works correctly.
@MainActor
struct DefaultsIsolationGuardTests {
    private let store: DefaultsStore
    private let testSuite: TestSuite

    init() {
        testSuite = TestSuiteFactory.createSuite()
        store = DefaultsStore(suite: testSuite.suite)
    }

    /// Verifies that per-test suite isolation works.
    @Test("store uses an isolated suite, not the standard one")
    func storeHasIsolatedSuite() {
        #expect(store.suite != UserDefaults.standard)
    }

    /// Verifies store operations work correctly.
    @Test("store operations round-trip")
    func storeOperations() {
        #expect(!store.showAllSpaces)
        #expect(store.sizeScale == Layout.defaultSizeScale)
        #expect(store.spaceColors.isEmpty)

        store.showAllSpaces = true
        store.sizeScale = 80.0
        store.spaceColors = [1: SpaceColors(foreground: .red, background: .blue)]

        #expect(store.showAllSpaces)
        #expect(store.sizeScale == 80.0)
        #expect(store.spaceColors.count == 1)

        store.resetAll()
        #expect(!store.showAllSpaces)
        #expect(store.sizeScale == Layout.defaultSizeScale)
    }

    /// Verifies that KeySpecs matches Defaults.Keys definitions.
    @Test("KeySpecs.allKeyNames matches Defaults.Keys")
    func keySpecsMatchDefaultsKeys() {
        let expectedKeyNames: Set = [
            "clickToSwitchSpaces",
            "dimInactiveSpaces",
            "displaySpaceBadges",
            "displaySpaceColors",
            "displaySpaceFonts",
            "displaySpaceIconStyles",
            "displaySpaceLabels",
            "displaySpaceLabelStyles",
            "displaySpaceSkinTones",
            "displaySpaceSymbols",
            "hideEmptySpaces",
            "hideFullscreenApps",
            "hideSingleSpace",
            "localSpaceNumbers",
            "paddingScale",
            "separatorColor",
            "showAllDisplays",
            "showAllSpaces",
            "sizeScale",
            "soundName",
            "spaceBadges",
            "spaceColors",
            "spaceFonts",
            "spaceIconStyles",
            "spaceLabels",
            "spaceLabelStyles",
            "spaceSkinTones",
            "spaceSymbols",
            "suppressHiddenIconWarning",
            "uniqueIconsPerDisplay",
        ]

        #expect(KeySpecs.allKeyNames == expectedKeyNames)
    }

    /// Verifies that two tests get different suites.
    @Test("suite isolation A: setting a value should not affect other tests")
    func suiteIsolationFirstTest() {
        store.showAllSpaces = true
    }

    @Test("suite isolation B: starts with default value")
    func suiteIsolationSecondTest() {
        #expect(!store.showAllSpaces)
    }
}
