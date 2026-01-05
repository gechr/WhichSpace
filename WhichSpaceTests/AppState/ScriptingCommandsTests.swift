import XCTest
@testable import WhichSpace

@MainActor
final class ScriptingCommandsTests: XCTestCase {
    private var stub: CGSStub!
    private var appState: AppState!
    private var store: DefaultsStore!
    private var testSuite: TestSuite!

    override func setUp() {
        super.setUp()
        testSuite = TestSuiteFactory.createSuite()
        store = DefaultsStore(suite: testSuite.suite)
        stub = CGSStub()
    }

    override func tearDown() {
        appState = nil
        stub = nil
        if let store, let testSuite {
            store.resetAll()
            TestSuiteFactory.destroySuite(testSuite)
        }
        store = nil
        testSuite = nil
        super.tearDown()
    }

    // MARK: - currentSpaceNumber Tests

    func testCurrentSpaceNumber_returnsCorrectNumberFromAppState() {
        // Given: Single display with 3 spaces, space 2 active
        stub.activeDisplayIdentifier = "Main"
        stub.displays = [
            CGSStub.makeDisplay(
                displayID: "Main",
                spaces: [
                    (id: 100, isFullscreen: false),
                    (id: 101, isFullscreen: false),
                    (id: 102, isFullscreen: false),
                ],
                activeSpaceID: 101
            ),
        ]
        appState = AppState(displaySpaceProvider: stub, skipObservers: true, store: store)

        // When
        let number = appState.currentSpace

        // Then
        XCTAssertEqual(number, 2, "currentSpaceNumber should return 2 for the second space")
    }

    func testCurrentSpaceNumber_space1Active() {
        // Given: 3 spaces, space 1 active
        stub.activeDisplayIdentifier = "Main"
        stub.displays = [
            CGSStub.makeDisplay(
                displayID: "Main",
                spaces: [
                    (id: 100, isFullscreen: false),
                    (id: 101, isFullscreen: false),
                    (id: 102, isFullscreen: false),
                ],
                activeSpaceID: 100
            ),
        ]
        appState = AppState(displaySpaceProvider: stub, skipObservers: true, store: store)

        // When
        let number = appState.currentSpace

        // Then
        XCTAssertEqual(number, 1, "currentSpaceNumber should return 1 for the first space")
    }

    func testCurrentSpaceNumber_space3Active() {
        // Given: 3 spaces, space 3 active
        stub.activeDisplayIdentifier = "Main"
        stub.displays = [
            CGSStub.makeDisplay(
                displayID: "Main",
                spaces: [
                    (id: 100, isFullscreen: false),
                    (id: 101, isFullscreen: false),
                    (id: 102, isFullscreen: false),
                ],
                activeSpaceID: 102
            ),
        ]
        appState = AppState(displaySpaceProvider: stub, skipObservers: true, store: store)

        // When
        let number = appState.currentSpace

        // Then
        XCTAssertEqual(number, 3, "currentSpaceNumber should return 3 for the third space")
    }

    // MARK: - currentSpaceLabel Tests

    func testCurrentSpaceLabel_returnsCorrectLabelFromAppState() {
        // Given: Single display with 3 spaces, space 2 active
        stub.activeDisplayIdentifier = "Main"
        stub.displays = [
            CGSStub.makeDisplay(
                displayID: "Main",
                spaces: [
                    (id: 100, isFullscreen: false),
                    (id: 101, isFullscreen: false),
                    (id: 102, isFullscreen: false),
                ],
                activeSpaceID: 101
            ),
        ]
        appState = AppState(displaySpaceProvider: stub, skipObservers: true, store: store)

        // When
        let label = appState.currentSpaceLabel

        // Then
        XCTAssertEqual(label, "2", "currentSpaceLabel should return '2' for the second space")
    }

    func testCurrentSpaceLabel_withFullscreenSpace() {
        // Given: Display with regular, fullscreen, regular spaces - fullscreen active
        stub.activeDisplayIdentifier = "Main"
        stub.displays = [
            CGSStub.makeDisplay(
                displayID: "Main",
                spaces: [
                    (id: 100, isFullscreen: false),
                    (id: 101, isFullscreen: true),
                    (id: 102, isFullscreen: false),
                ],
                activeSpaceID: 101
            ),
        ]
        appState = AppState(displaySpaceProvider: stub, skipObservers: true, store: store)

        // When
        let label = appState.currentSpaceLabel

        // Then: Fullscreen space should return "F"
        XCTAssertEqual(label, Labels.fullscreen, "currentSpaceLabel should return 'F' for fullscreen space")
    }

    func testCurrentSpaceLabel_multipleDisplays_returnsActiveDisplayLabel() {
        // Given: Two displays, active display has space 2 active
        stub.activeDisplayIdentifier = "DisplayA"
        stub.displays = [
            CGSStub.makeDisplay(
                displayID: "DisplayA",
                spaces: [
                    (id: 100, isFullscreen: false),
                    (id: 101, isFullscreen: false),
                ],
                activeSpaceID: 101
            ),
            CGSStub.makeDisplay(
                displayID: "DisplayB",
                spaces: [
                    (id: 200, isFullscreen: false),
                    (id: 201, isFullscreen: false),
                    (id: 202, isFullscreen: false),
                ],
                activeSpaceID: 200
            ),
        ]
        appState = AppState(displaySpaceProvider: stub, skipObservers: true, store: store)

        // When
        let label = appState.currentSpaceLabel

        // Then: Should return label from active display
        XCTAssertEqual(label, "2", "currentSpaceLabel should return label from active display")
    }

    // MARK: - Number vs Label Difference

    func testCurrentSpaceNumberAndLabel_fullscreen_numberIsIndexLabelIsF() {
        // Given: Fullscreen space is active
        stub.activeDisplayIdentifier = "Main"
        stub.displays = [
            CGSStub.makeDisplay(
                displayID: "Main",
                spaces: [
                    (id: 100, isFullscreen: false),
                    (id: 101, isFullscreen: true),
                    (id: 102, isFullscreen: false),
                ],
                activeSpaceID: 101
            ),
        ]
        appState = AppState(displaySpaceProvider: stub, skipObservers: true, store: store)

        // When
        let number = appState.currentSpace
        let label = appState.currentSpaceLabel

        // Then: Number is the index (2), label is "F"
        XCTAssertEqual(number, 2, "currentSpaceNumber should return index 2")
        XCTAssertEqual(label, Labels.fullscreen, "currentSpaceLabel should return 'F'")
    }
}
