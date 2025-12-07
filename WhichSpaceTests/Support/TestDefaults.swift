import Defaults
import XCTest
@testable import WhichSpace

// MARK: - TestSuite

/// A test UserDefaults suite with its associated name for cleanup.
struct TestSuite {
    let suite: UserDefaults
    let suiteName: String
}

// MARK: - TestSuiteFactory

/// Creates isolated UserDefaults suites for testing.
enum TestSuiteFactory {
    /// Creates a new UserDefaults suite with a unique name.
    ///
    /// Each call returns a fresh, empty suite suitable for test isolation.
    /// The suite name includes a UUID to prevent collisions.
    static func createSuite() -> TestSuite {
        let name = "WhichSpaceTests.\(UUID().uuidString)"
        return TestSuite(suite: UserDefaults(suiteName: name)!, suiteName: name)
    }

    /// Removes a test suite's persistent domain.
    ///
    /// Call this in teardown to clean up after tests.
    static func destroySuite(_ testSuite: TestSuite) {
        testSuite.suite.removePersistentDomain(forName: testSuite.suiteName)
        testSuite.suite.synchronize()
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
//
// ## Note for @MainActor Tests
// If your test class needs `@MainActor`, don't inherit from this class.
// Instead, create a `store` property directly and use `TestSuiteFactory` in setUp/tearDown:
// ```swift
// @MainActor
// final class MyTests: XCTestCase {
//     private var store: DefaultsStore!
//     private var testSuite: TestSuite!
//
//     override func setUp() {
//         super.setUp()
//         testSuite = TestSuiteFactory.createSuite()
//         store = DefaultsStore(suite: testSuite.suite)
//     }
//
//     override func tearDown() {
//         if let store, let testSuite {
//             store.resetAll()
//             TestSuiteFactory.destroySuite(testSuite)
//         }
//         store = nil
//         testSuite = nil
//         super.tearDown()
//     }
// }
// ```
// swiftformat:disable preferFinalClasses
// swiftlint:disable:next final_class final_test_case
class IsolatedDefaultsTestCase: XCTestCase {
    // swiftformat:enable preferFinalClasses

    // swiftlint:disable test_case_accessibility
    // The isolated store for this test, backed by a per-test suite.
    private(set) var store: DefaultsStore!

    /// The underlying UserDefaults suite (for direct access if needed).
    var suite: UserDefaults { store.suite }

    /// The test suite with its name for cleanup.
    private var testSuite: TestSuite!
    // swiftlint:enable test_case_accessibility

    override func setUp() {
        super.setUp()

        // Create per-test isolated suite
        testSuite = TestSuiteFactory.createSuite()
        store = DefaultsStore(suite: testSuite.suite)

        // Register cleanup that runs even if test crashes
        addTeardownBlock { [store, testSuite] in
            guard let store, let testSuite else {
                return
            }
            store.resetAll()
            TestSuiteFactory.destroySuite(testSuite)
        }
    }

    override func tearDown() {
        store = nil
        testSuite = nil
        super.tearDown()
    }
}

// MARK: - Defaults Isolation Guard Tests

/// Tests that verify the test isolation infrastructure itself works correctly.
final class DefaultsIsolationGuardTests: IsolatedDefaultsTestCase {
    /// Verifies that per-test suite isolation works.
    func testStoreHasIsolatedSuite() {
        // Each test should get its own suite, not .standard
        XCTAssertNotEqual(
            store.suite,
            UserDefaults.standard,
            "Test store should use an isolated suite, not .standard"
        )
    }

    /// Verifies store operations work correctly.
    func testStoreOperations() {
        // Default values
        XCTAssertFalse(store.showAllSpaces)
        XCTAssertEqual(store.sizeScale, Layout.defaultSizeScale)
        XCTAssertTrue(store.spaceColors.isEmpty)

        // Set values
        store.showAllSpaces = true
        store.sizeScale = 80.0
        store.spaceColors = [1: SpaceColors(foreground: .red, background: .blue)]

        // Verify values
        XCTAssertTrue(store.showAllSpaces)
        XCTAssertEqual(store.sizeScale, 80.0)
        XCTAssertEqual(store.spaceColors.count, 1)

        // Reset
        store.resetAll()
        XCTAssertFalse(store.showAllSpaces)
        XCTAssertEqual(store.sizeScale, Layout.defaultSizeScale)
    }

    /// Verifies that KeySpecs matches Defaults.Keys definitions.
    func testKeySpecsMatchDefaultsKeys() {
        let expectedKeyNames: Set<String> = [
            "showAllSpaces",
            "spaceColors",
            "spaceIconStyles",
            "spaceSFSymbols",
            "sizeScale",
        ]

        XCTAssertEqual(
            KeySpecs.allKeyNames,
            expectedKeyNames,
            "KeySpecs.allKeyNames must match all keys defined in Defaults.Keys"
        )
    }

    /// Verifies that two tests get different suites.
    func testSuiteIsolationFirstTest() {
        store.showAllSpaces = true
        // This value should not affect other tests
    }

    func testSuiteIsolationSecondTest() {
        // Should start with default value, not affected by other test
        XCTAssertFalse(store.showAllSpaces)
    }
}
