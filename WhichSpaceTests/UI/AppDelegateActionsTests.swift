import AppKit
import XCTest
@testable import WhichSpace

// MARK: - Stub Alert for Testing

/// A stub alert that returns a predetermined result
struct StubConfirmationAlert: ConfirmationAlertProvider {
    let shouldConfirm: Bool

    func runModal() -> Bool {
        shouldConfirm
    }
}

/// A factory that creates stub alerts with configurable confirmation behavior
final class StubAlertFactory: ConfirmationAlertFactory {
    var shouldConfirm = true
    private(set) var alertsShown: [(message: String, detail: String, confirmTitle: String, isDestructive: Bool)] = []

    func makeAlert(
        message: String,
        detail: String,
        confirmTitle: String,
        isDestructive: Bool
    ) -> ConfirmationAlertProvider {
        alertsShown.append((message, detail, confirmTitle, isDestructive))
        return StubConfirmationAlert(shouldConfirm: shouldConfirm)
    }

    func reset() {
        alertsShown = []
    }
}

// MARK: - Stub LaunchAtLogin for Testing

/// A stub launch-at-login provider for testing
final class StubLaunchAtLoginProvider: LaunchAtLoginProvider {
    var isEnabled = false
}

// MARK: - AppDelegate Actions Tests

/// Tests for AppDelegate menu action methods.
/// Uses stubbed dependencies to test actions without showing UI.
@MainActor
final class AppDelegateActionsTests: XCTestCase {
    private var store: DefaultsStore!
    private var testSuite: TestSuite!
    private var stub: CGSStub!
    private var appState: AppState!
    private var alertFactory: StubAlertFactory!
    private var launchAtLoginStub: StubLaunchAtLoginProvider!
    private var sut: AppDelegate!

    override func setUp() {
        super.setUp()

        // Create per-test isolated store
        testSuite = TestSuiteFactory.createSuite()
        store = DefaultsStore(suite: testSuite.suite)

        stub = CGSStub()
        stub.activeDisplayIdentifier = "Main"
        stub.displays = [
            CGSStub.makeDisplay(
                displayID: "Main",
                spaces: [
                    (id: 100, isFullscreen: false),
                    (id: 101, isFullscreen: false),
                    (id: 102, isFullscreen: false),
                    (id: 103, isFullscreen: false),
                ],
                activeSpaceID: 101
            ),
        ]

        appState = AppState(displaySpaceProvider: stub, skipObservers: true, store: store)
        alertFactory = StubAlertFactory()
        launchAtLoginStub = StubLaunchAtLoginProvider()
        sut = AppDelegate(appState: appState, alertFactory: alertFactory, launchAtLogin: launchAtLoginStub)
    }

    override func tearDown() {
        sut.stopObservingAppState()
        sut = nil
        launchAtLoginStub = nil
        appState = nil
        alertFactory = nil
        stub = nil
        if let store, let testSuite {
            store.resetAll()
            TestSuiteFactory.destroySuite(testSuite)
        }
        store = nil
        testSuite = nil
        super.tearDown()
    }

    // MARK: - Helper Methods

    /// Creates an AsyncStream that receives notifications when updateStatusBarIcon() is called.
    /// Call this before triggering state changes that require observation.
    private func makeUpdateNotifier() -> (stream: AsyncStream<Void>, iterator: AsyncStream<Void>.AsyncIterator) {
        var continuation: AsyncStream<Void>.Continuation!
        let stream = AsyncStream<Void> { continuation = $0 }
        sut.statusBarIconUpdateNotifier = continuation
        return (stream, stream.makeAsyncIterator())
    }

    /// Waits for statusBarIconUpdateCount to change from the given value.
    /// Returns true if count changed, false if timeout was reached.
    private func waitForCountChange(
        from initialCount: Int,
        timeout: Duration = .milliseconds(100)
    ) async -> Bool {
        let deadline = ContinuousClock.now.advanced(by: timeout)
        while ContinuousClock.now < deadline {
            if sut.statusBarIconUpdateCount != initialCount {
                return true
            }
            try? await Task.sleep(for: .milliseconds(5))
        }
        return sut.statusBarIconUpdateCount != initialCount
    }

    private func setupSpaceWithPreferences(
        space: Int,
        style: IconStyle? = nil,
        colors: SpaceColors? = nil,
        symbol: String? = nil,
        font: NSFont? = nil
    ) {
        if let style {
            SpacePreferences.setIconStyle(style, forSpace: space, store: store)
        }
        if let colors {
            SpacePreferences.setColors(colors, forSpace: space, store: store)
        }
        if let symbol {
            SpacePreferences.setSymbol(symbol, forSpace: space, store: store)
        }
        if let font {
            SpacePreferences.setFont(SpaceFont(font: font), forSpace: space, store: store)
        }
    }

    // MARK: - toggleShowAllSpaces Tests

    func testToggleShowAllSpaces_togglesFromFalseToTrue() {
        store.showAllSpaces = false

        sut.toggleShowAllSpaces()

        XCTAssertTrue(store.showAllSpaces, "showAllSpaces should toggle to true")
    }

    func testToggleShowAllSpaces_togglesFromTrueToFalse() {
        store.showAllSpaces = true

        sut.toggleShowAllSpaces()

        XCTAssertFalse(store.showAllSpaces, "showAllSpaces should toggle to false")
    }

    func testToggleShowAllSpaces_multipleToggles() {
        store.showAllSpaces = false

        sut.toggleShowAllSpaces()
        XCTAssertTrue(store.showAllSpaces)

        sut.toggleShowAllSpaces()
        XCTAssertFalse(store.showAllSpaces)

        sut.toggleShowAllSpaces()
        XCTAssertTrue(store.showAllSpaces)
    }

    func testToggleShowAllSpaces_disablesShowAllDisplays_whenEnabled() {
        store.showAllDisplays = true
        store.showAllSpaces = false

        sut.toggleShowAllSpaces()

        XCTAssertTrue(store.showAllSpaces, "showAllSpaces should be enabled")
        XCTAssertFalse(store.showAllDisplays, "showAllDisplays should be disabled when showAllSpaces is enabled")
    }

    func testToggleShowAllSpaces_doesNotAffectShowAllDisplays_whenDisabled() {
        store.showAllDisplays = true
        store.showAllSpaces = true

        sut.toggleShowAllSpaces()

        XCTAssertFalse(store.showAllSpaces, "showAllSpaces should be disabled")
        XCTAssertTrue(store.showAllDisplays, "showAllDisplays should remain unchanged when showAllSpaces is disabled")
    }

    // MARK: - toggleShowAllDisplays Tests

    func testToggleShowAllDisplays_togglesFromFalseToTrue() {
        store.showAllDisplays = false

        sut.toggleShowAllDisplays()

        XCTAssertTrue(store.showAllDisplays, "showAllDisplays should toggle to true")
    }

    func testToggleShowAllDisplays_togglesFromTrueToFalse() {
        store.showAllDisplays = true

        sut.toggleShowAllDisplays()

        XCTAssertFalse(store.showAllDisplays, "showAllDisplays should toggle to false")
    }

    func testToggleShowAllDisplays_disablesShowAllSpaces_whenEnabled() {
        store.showAllSpaces = true
        store.showAllDisplays = false

        sut.toggleShowAllDisplays()

        XCTAssertTrue(store.showAllDisplays, "showAllDisplays should be enabled")
        XCTAssertFalse(store.showAllSpaces, "showAllSpaces should be disabled when showAllDisplays is enabled")
    }

    func testToggleShowAllDisplays_doesNotAffectShowAllSpaces_whenDisabled() {
        store.showAllSpaces = true
        store.showAllDisplays = true

        sut.toggleShowAllDisplays()

        XCTAssertFalse(store.showAllDisplays, "showAllDisplays should be disabled")
        XCTAssertTrue(store.showAllSpaces, "showAllSpaces should remain unchanged when showAllDisplays is disabled")
    }

    // MARK: - toggleDimInactiveSpaces Tests

    func testToggleDimInactiveSpaces_togglesFromTrueToFalse() {
        store.dimInactiveSpaces = true

        sut.toggleDimInactiveSpaces()

        XCTAssertFalse(store.dimInactiveSpaces, "dimInactiveSpaces should toggle to false")
    }

    func testToggleDimInactiveSpaces_togglesFromFalseToTrue() {
        store.dimInactiveSpaces = false

        sut.toggleDimInactiveSpaces()

        XCTAssertTrue(store.dimInactiveSpaces, "dimInactiveSpaces should toggle to true")
    }

    func testToggleDimInactiveSpaces_multipleToggles() {
        store.dimInactiveSpaces = true

        sut.toggleDimInactiveSpaces()
        XCTAssertFalse(store.dimInactiveSpaces)

        sut.toggleDimInactiveSpaces()
        XCTAssertTrue(store.dimInactiveSpaces)

        sut.toggleDimInactiveSpaces()
        XCTAssertFalse(store.dimInactiveSpaces)
    }

    // MARK: - toggleHideEmptySpaces Tests

    func testToggleHideEmptySpaces_togglesFromTrueToFalse() {
        store.hideEmptySpaces = true

        sut.toggleHideEmptySpaces()

        XCTAssertFalse(store.hideEmptySpaces, "hideEmptySpaces should toggle to false")
    }

    func testToggleHideEmptySpaces_togglesFromFalseToTrue() {
        store.hideEmptySpaces = false

        sut.toggleHideEmptySpaces()

        XCTAssertTrue(store.hideEmptySpaces, "hideEmptySpaces should toggle to true")
    }

    func testToggleHideEmptySpaces_multipleToggles() {
        store.hideEmptySpaces = false

        sut.toggleHideEmptySpaces()
        XCTAssertTrue(store.hideEmptySpaces)

        sut.toggleHideEmptySpaces()
        XCTAssertFalse(store.hideEmptySpaces)

        sut.toggleHideEmptySpaces()
        XCTAssertTrue(store.hideEmptySpaces)
    }

    // MARK: - toggleHideFullscreenApps Tests

    func testToggleHideFullscreenApps_togglesFromTrueToFalse() {
        store.hideFullscreenApps = true

        sut.toggleHideFullscreenApps()

        XCTAssertFalse(store.hideFullscreenApps, "hideFullscreenApps should toggle to false")
    }

    func testToggleHideFullscreenApps_togglesFromFalseToTrue() {
        store.hideFullscreenApps = false

        sut.toggleHideFullscreenApps()

        XCTAssertTrue(store.hideFullscreenApps, "hideFullscreenApps should toggle to true")
    }

    func testToggleHideFullscreenApps_multipleToggles() {
        store.hideFullscreenApps = false

        sut.toggleHideFullscreenApps()
        XCTAssertTrue(store.hideFullscreenApps)

        sut.toggleHideFullscreenApps()
        XCTAssertFalse(store.hideFullscreenApps)

        sut.toggleHideFullscreenApps()
        XCTAssertTrue(store.hideFullscreenApps)
    }

    // MARK: - toggleHideSingleSpace Tests

    func testToggleHideSingleSpace_togglesFromTrueToFalse() {
        store.hideSingleSpace = true

        sut.toggleHideSingleSpace()

        XCTAssertFalse(store.hideSingleSpace, "hideSingleSpace should toggle to false")
    }

    func testToggleHideSingleSpace_togglesFromFalseToTrue() {
        store.hideSingleSpace = false

        sut.toggleHideSingleSpace()

        XCTAssertTrue(store.hideSingleSpace, "hideSingleSpace should toggle to true")
    }

    func testToggleHideSingleSpace_multipleToggles() {
        store.hideSingleSpace = false

        sut.toggleHideSingleSpace()
        XCTAssertTrue(store.hideSingleSpace)

        sut.toggleHideSingleSpace()
        XCTAssertFalse(store.hideSingleSpace)

        sut.toggleHideSingleSpace()
        XCTAssertTrue(store.hideSingleSpace)
    }

    // MARK: - applyToAllSpaces. Tests

    func testApplyAllToAllSpaces_whenConfirmed_appliesStyleToAllSpaces() {
        let testStyle = IconStyle.circle
        setupSpaceWithPreferences(space: appState.currentSpace, style: testStyle)
        alertFactory.shouldConfirm = true
        let initialCount = sut.statusBarIconUpdateCount

        sut.applyToAllSpaces()

        for space in 1 ... 4 {
            XCTAssertEqual(
                SpacePreferences.iconStyle(forSpace: space, store: store),
                testStyle,
                "Space \(space) should have icon style \(testStyle.rawValue)"
            )
        }
        XCTAssertEqual(sut.statusBarIconUpdateCount, initialCount + 1, "updateStatusBarIcon should be called")
        XCTAssertEqual(alertFactory.alertsShown.count, 1, "One alert should be shown")
    }

    func testApplyAllToAllSpaces_whenConfirmed_appliesColorsToAllSpaces() {
        let testColors = SpaceColors(foreground: .systemRed, background: .systemBlue)
        setupSpaceWithPreferences(space: appState.currentSpace, colors: testColors)
        alertFactory.shouldConfirm = true

        sut.applyToAllSpaces()

        for space in 1 ... 4 {
            let colors = SpacePreferences.colors(forSpace: space, store: store)
            XCTAssertNotNil(colors, "Space \(space) should have colors")
            XCTAssertEqual(colors?.foreground, testColors.foreground)
            XCTAssertEqual(colors?.background, testColors.background)
        }
    }

    func testApplyAllToAllSpaces_whenConfirmed_appliesSymbolToAllSpaces() {
        let testSymbol = "star.fill"
        setupSpaceWithPreferences(space: appState.currentSpace, symbol: testSymbol)
        alertFactory.shouldConfirm = true

        sut.applyToAllSpaces()

        for space in 1 ... 4 {
            XCTAssertEqual(
                SpacePreferences.symbol(forSpace: space, store: store),
                testSymbol,
                "Space \(space) should have symbol \(testSymbol)"
            )
        }
    }

    func testApplyAllToAllSpaces_whenConfirmed_appliesFontToAllSpaces() {
        let testFont = NSFont.boldSystemFont(ofSize: 15)
        setupSpaceWithPreferences(space: appState.currentSpace, font: testFont)
        alertFactory.shouldConfirm = true

        sut.applyToAllSpaces()

        for space in 1 ... 4 {
            let font = SpacePreferences.font(forSpace: space, store: store)?.font
            XCTAssertEqual(font?.fontName, testFont.fontName, "Space \(space) should have font \(testFont.fontName)")
            XCTAssertEqual(Double(font?.pointSize ?? -1), Double(testFont.pointSize), accuracy: 0.001)
        }
    }

    func testApplyAllToAllSpaces_whenDeclined_doesNotApply() {
        let testStyle = IconStyle.hexagon
        setupSpaceWithPreferences(space: appState.currentSpace, style: testStyle)
        alertFactory.shouldConfirm = false
        let initialCount = sut.statusBarIconUpdateCount

        sut.applyToAllSpaces()

        // Other spaces should not have the style
        XCTAssertNil(SpacePreferences.iconStyle(forSpace: 1, store: store))
        XCTAssertNil(SpacePreferences.iconStyle(forSpace: 3, store: store))
        XCTAssertNil(SpacePreferences.iconStyle(forSpace: 4, store: store))
        XCTAssertEqual(sut.statusBarIconUpdateCount, initialCount, "updateStatusBarIcon should not be called")
    }

    func testApplyAllToAllSpaces_clearsSymbolWhenNil() {
        // Set symbols on other spaces
        for space in 1 ... 4 {
            SpacePreferences.setSymbol("star.fill", forSpace: space, store: store)
        }
        // Current space has no symbol (number mode)
        SpacePreferences.clearSymbol(forSpace: appState.currentSpace, store: store)
        alertFactory.shouldConfirm = true

        sut.applyToAllSpaces()

        for space in 1 ... 4 {
            XCTAssertNil(
                SpacePreferences.symbol(forSpace: space, store: store),
                "Space \(space) should have no symbol"
            )
        }
    }

    func testApplyAllToAllSpaces_clearsColorsWhenNil() {
        // Set colors on other spaces
        for space in 1 ... 4 {
            SpacePreferences.setColors(SpaceColors(foreground: .red, background: .blue), forSpace: space, store: store)
        }
        // Current space has no colors
        SpacePreferences.clearColors(forSpace: appState.currentSpace, store: store)
        alertFactory.shouldConfirm = true

        sut.applyToAllSpaces()

        for space in 1 ... 4 {
            XCTAssertNil(
                SpacePreferences.colors(forSpace: space, store: store),
                "Space \(space) should have no colors"
            )
        }
    }

    func testApplyAllToAllSpaces_clearsFontWhenNil() {
        // Set fonts on other spaces
        for space in 1 ... 4 {
            SpacePreferences.setFont(SpaceFont(font: NSFont.systemFont(ofSize: 13)), forSpace: space, store: store)
        }
        // Current space has no font
        SpacePreferences.clearFont(forSpace: appState.currentSpace, store: store)
        alertFactory.shouldConfirm = true

        sut.applyToAllSpaces()

        for space in 1 ... 4 {
            XCTAssertNil(
                SpacePreferences.font(forSpace: space, store: store),
                "Space \(space) should have no font"
            )
        }
    }

    // MARK: - resetSpaceToDefault Tests

    func testResetSpaceToDefault_whenConfirmed_clearsAllPreferences() {
        setupSpaceWithPreferences(
            space: appState.currentSpace,
            style: .hexagon,
            colors: SpaceColors(foreground: .red, background: .blue),
            symbol: "star.fill",
            font: NSFont.boldSystemFont(ofSize: 14)
        )
        alertFactory.shouldConfirm = true
        let initialCount = sut.statusBarIconUpdateCount

        sut.resetSpaceToDefault()

        XCTAssertNil(SpacePreferences.colors(forSpace: appState.currentSpace, store: store))
        XCTAssertNil(SpacePreferences.iconStyle(forSpace: appState.currentSpace, store: store))
        XCTAssertNil(SpacePreferences.symbol(forSpace: appState.currentSpace, store: store))
        XCTAssertNil(SpacePreferences.font(forSpace: appState.currentSpace, store: store))
        XCTAssertEqual(sut.statusBarIconUpdateCount, initialCount + 1, "updateStatusBarIcon should be called")
    }

    func testResetSpaceToDefault_whenDeclined_preservesPreferences() {
        let testColors = SpaceColors(foreground: .red, background: .blue)
        setupSpaceWithPreferences(space: appState.currentSpace, colors: testColors)
        alertFactory.shouldConfirm = false

        sut.resetSpaceToDefault()

        XCTAssertNotNil(
            SpacePreferences.colors(forSpace: appState.currentSpace, store: store),
            "Colors should be preserved"
        )
    }

    func testResetSpaceToDefault_doesNotAffectOtherSpaces() {
        let otherSpace = 3
        let otherColors = SpaceColors(foreground: .green, background: .yellow)
        setupSpaceWithPreferences(
            space: appState.currentSpace,
            colors: SpaceColors(foreground: .red, background: .blue)
        )
        setupSpaceWithPreferences(space: otherSpace, colors: otherColors)
        alertFactory.shouldConfirm = true

        sut.resetSpaceToDefault()

        XCTAssertNotNil(
            SpacePreferences.colors(forSpace: otherSpace, store: store),
            "Other space colors should be preserved"
        )
        XCTAssertEqual(SpacePreferences.colors(forSpace: otherSpace, store: store)?.foreground, otherColors.foreground)
    }

    // MARK: - resetAllSpacesToDefault Tests

    func testResetAllSpacesToDefault_whenConfirmed_clearsAllSpacePreferences() {
        for space in 1 ... 4 {
            setupSpaceWithPreferences(
                space: space,
                style: .circle,
                colors: SpaceColors(foreground: .red, background: .blue),
                symbol: "star"
            )
        }
        store.sizeScale = 80.0
        alertFactory.shouldConfirm = true
        let initialCount = sut.statusBarIconUpdateCount

        sut.resetAllSpacesToDefault()

        for space in 1 ... 4 {
            XCTAssertNil(SpacePreferences.colors(forSpace: space, store: store))
            XCTAssertNil(SpacePreferences.iconStyle(forSpace: space, store: store))
            XCTAssertNil(SpacePreferences.symbol(forSpace: space, store: store))
        }
        XCTAssertEqual(store.sizeScale, Layout.defaultSizeScale, "Size scale should be reset to default")
        XCTAssertEqual(sut.statusBarIconUpdateCount, initialCount + 1, "updateStatusBarIcon should be called")
    }

    func testResetAllSpacesToDefault_whenDeclined_preservesPreferences() {
        let testColors = SpaceColors(foreground: .red, background: .blue)
        setupSpaceWithPreferences(space: 1, colors: testColors)
        store.sizeScale = 80.0
        alertFactory.shouldConfirm = false

        sut.resetAllSpacesToDefault()

        XCTAssertNotNil(SpacePreferences.colors(forSpace: 1, store: store), "Colors should be preserved")
        XCTAssertEqual(store.sizeScale, 80.0, "Size scale should be preserved")
    }

    func testResetAllSpacesToDefault_clearsPreferencesForClosedSpaces() {
        // Setup: Configure 10 spaces worth of preferences (more than the 4 active spaces)
        for space in 1 ... 10 {
            setupSpaceWithPreferences(
                space: space,
                style: .pentagon,
                colors: SpaceColors(foreground: .orange, background: .purple),
                symbol: "star"
            )
        }

        // Simulate closing spaces by reducing to only 2 active spaces
        stub.displays = [
            CGSStub.makeDisplay(
                displayID: "Main",
                spaces: [
                    (id: 100, isFullscreen: false),
                    (id: 101, isFullscreen: false),
                ],
                activeSpaceID: 101
            ),
        ]
        appState.forceSpaceUpdate()
        XCTAssertEqual(appState.getAllSpaceIndices().count, 2, "Should only have 2 active spaces")

        alertFactory.shouldConfirm = true

        // Reset all spaces
        sut.resetAllSpacesToDefault()

        // Verify ALL 10 spaces are cleared, not just the 2 active ones
        for space in 1 ... 10 {
            XCTAssertNil(
                SpacePreferences.colors(forSpace: space, store: store),
                "Space \(space) colors should be cleared"
            )
            XCTAssertNil(
                SpacePreferences.iconStyle(forSpace: space, store: store),
                "Space \(space) icon style should be cleared"
            )
            XCTAssertNil(
                SpacePreferences.symbol(forSpace: space, store: store),
                "Space \(space) SF symbol should be cleared"
            )
        }
    }

    // MARK: - invertColors Tests

    func testInvertColors_swapsForegroundAndBackground() {
        let originalForeground = NSColor.white
        let originalBackground = NSColor.black
        setupSpaceWithPreferences(
            space: appState.currentSpace,
            colors: SpaceColors(foreground: originalForeground, background: originalBackground)
        )
        let initialCount = sut.statusBarIconUpdateCount

        sut.invertColors()

        let colors = SpacePreferences.colors(forSpace: appState.currentSpace, store: store)
        XCTAssertEqual(colors?.foreground, originalBackground, "Foreground should become original background")
        XCTAssertEqual(colors?.background, originalForeground, "Background should become original foreground")
        XCTAssertEqual(sut.statusBarIconUpdateCount, initialCount + 1, "updateStatusBarIcon should be called")
    }

    func testInvertColors_withCustomColors() {
        let customForeground = NSColor.systemRed
        let customBackground = NSColor.systemBlue
        setupSpaceWithPreferences(
            space: appState.currentSpace,
            colors: SpaceColors(foreground: customForeground, background: customBackground)
        )

        sut.invertColors()

        let colors = SpacePreferences.colors(forSpace: appState.currentSpace, store: store)
        XCTAssertEqual(colors?.foreground, customBackground)
        XCTAssertEqual(colors?.background, customForeground)
    }

    func testInvertColors_doubleInvertRestoresOriginal() {
        let originalColors = SpaceColors(foreground: .systemGreen, background: .systemPurple)
        setupSpaceWithPreferences(space: appState.currentSpace, colors: originalColors)

        sut.invertColors()
        sut.invertColors()

        let colors = SpacePreferences.colors(forSpace: appState.currentSpace, store: store)
        XCTAssertEqual(colors?.foreground, originalColors.foreground)
        XCTAssertEqual(colors?.background, originalColors.background)
    }

    // MARK: - applyColorsToAllSpaces Tests

    func testApplyColorsToAllSpaces_whenConfirmed_appliesColors() {
        let testColors = SpaceColors(foreground: .systemOrange, background: .systemTeal)
        setupSpaceWithPreferences(space: appState.currentSpace, colors: testColors)
        alertFactory.shouldConfirm = true
        let initialCount = sut.statusBarIconUpdateCount

        sut.applyColorsToAllSpaces()

        for space in 1 ... 4 {
            let colors = SpacePreferences.colors(forSpace: space, store: store)
            XCTAssertEqual(colors?.foreground, testColors.foreground)
            XCTAssertEqual(colors?.background, testColors.background)
        }
        XCTAssertEqual(sut.statusBarIconUpdateCount, initialCount + 1, "updateStatusBarIcon should be called")
    }

    func testApplyColorsToAllSpaces_whenDeclined_doesNotApply() {
        let testColors = SpaceColors(foreground: .systemOrange, background: .systemTeal)
        setupSpaceWithPreferences(space: appState.currentSpace, colors: testColors)
        alertFactory.shouldConfirm = false

        sut.applyColorsToAllSpaces()

        for space in [1, 3, 4] {
            XCTAssertNil(SpacePreferences.colors(forSpace: space, store: store))
        }
    }

    func testApplyColorsToAllSpaces_clearsColorsWhenNil() {
        // Set colors on all spaces
        for space in 1 ... 4 {
            SpacePreferences.setColors(SpaceColors(foreground: .red, background: .blue), forSpace: space, store: store)
        }
        // Clear colors on current space
        SpacePreferences.clearColors(forSpace: appState.currentSpace, store: store)
        alertFactory.shouldConfirm = true

        sut.applyColorsToAllSpaces()

        for space in 1 ... 4 {
            XCTAssertNil(SpacePreferences.colors(forSpace: space, store: store))
        }
    }

    func testApplyColorsToAllSpaces_preservesStyleAndSymbol() {
        // Set up different styles and symbols for each space
        for space in 1 ... 4 {
            SpacePreferences.setIconStyle(.circle, forSpace: space, store: store)
            SpacePreferences.setSymbol("star.fill", forSpace: space, store: store)
        }

        // Apply colors to all spaces
        let testColors = SpaceColors(foreground: .systemOrange, background: .systemTeal)
        setupSpaceWithPreferences(space: appState.currentSpace, colors: testColors)
        alertFactory.shouldConfirm = true

        sut.applyColorsToAllSpaces()

        // Verify styles and symbols are preserved
        for space in 1 ... 4 {
            XCTAssertEqual(
                SpacePreferences.iconStyle(forSpace: space, store: store),
                .circle,
                "Space \(space) style should be preserved after applying colors"
            )
            XCTAssertEqual(
                SpacePreferences.symbol(forSpace: space, store: store),
                "star.fill",
                "Space \(space) symbol should be preserved after applying colors"
            )
        }
    }

    // MARK: - applyStyleToAllSpaces Tests

    func testApplyStyleToAllSpaces_whenConfirmed_appliesStyle() {
        let testStyle = IconStyle.triangle
        setupSpaceWithPreferences(space: appState.currentSpace, style: testStyle)
        alertFactory.shouldConfirm = true
        let initialCount = sut.statusBarIconUpdateCount

        sut.applyStyleToAllSpaces()

        for space in 1 ... 4 {
            XCTAssertEqual(SpacePreferences.iconStyle(forSpace: space, store: store), testStyle)
        }
        XCTAssertEqual(sut.statusBarIconUpdateCount, initialCount + 1, "updateStatusBarIcon should be called")
    }

    func testApplyStyleToAllSpaces_appliesSymbolToAllIndices() {
        let testSymbol = "heart.fill"
        setupSpaceWithPreferences(space: appState.currentSpace, symbol: testSymbol)
        alertFactory.shouldConfirm = true

        sut.applyStyleToAllSpaces()

        for space in 1 ... 4 {
            XCTAssertEqual(SpacePreferences.symbol(forSpace: space, store: store), testSymbol)
        }
    }

    func testApplyStyleToAllSpaces_whenDeclined_doesNotApply() {
        let testStyle = IconStyle.pentagon
        setupSpaceWithPreferences(space: appState.currentSpace, style: testStyle)
        alertFactory.shouldConfirm = false

        sut.applyStyleToAllSpaces()

        for space in [1, 3, 4] {
            XCTAssertNil(SpacePreferences.iconStyle(forSpace: space, store: store))
        }
    }

    func testApplyStyleToAllSpaces_clearsSymbolWhenNil() {
        // First set symbols for all spaces
        for space in 1 ... 4 {
            SpacePreferences.setSymbol("moon.fill", forSpace: space, store: store)
        }

        // Current space has no symbol (number mode)
        SpacePreferences.clearSymbol(forSpace: appState.currentSpace, store: store)
        setupSpaceWithPreferences(space: appState.currentSpace, style: .hexagon)
        alertFactory.shouldConfirm = true

        sut.applyStyleToAllSpaces()

        for space in 1 ... 4 {
            XCTAssertNil(
                SpacePreferences.symbol(forSpace: space, store: store),
                "Space \(space) should have no symbol"
            )
            XCTAssertEqual(
                SpacePreferences.iconStyle(forSpace: space, store: store),
                .hexagon,
                "Space \(space) should have the new style"
            )
        }
    }

    func testApplyStyleToAllSpaces_preservesColors() {
        // Set up colors for each space
        let testColors = SpaceColors(foreground: .systemRed, background: .systemBlue)
        for space in 1 ... 4 {
            SpacePreferences.setColors(testColors, forSpace: space, store: store)
        }

        // Apply style to all spaces
        let testStyle = IconStyle.pentagon
        setupSpaceWithPreferences(space: appState.currentSpace, style: testStyle)
        alertFactory.shouldConfirm = true

        sut.applyStyleToAllSpaces()

        // Verify colors are preserved
        for space in 1 ... 4 {
            let colors = SpacePreferences.colors(forSpace: space, store: store)
            XCTAssertEqual(
                colors?.foreground,
                testColors.foreground,
                "Space \(space) foreground color should be preserved after applying style"
            )
            XCTAssertEqual(
                colors?.background,
                testColors.background,
                "Space \(space) background color should be preserved after applying style"
            )
        }
    }

    // MARK: - resetStyleToDefault Tests

    func testResetStyleToDefault_whenConfirmed_clearsStyleAndSymbol() {
        setupSpaceWithPreferences(
            space: appState.currentSpace,
            style: .pentagon,
            symbol: "bolt.fill"
        )
        alertFactory.shouldConfirm = true
        let initialCount = sut.statusBarIconUpdateCount

        sut.resetStyleToDefault()

        XCTAssertNil(SpacePreferences.iconStyle(forSpace: appState.currentSpace, store: store))
        XCTAssertNil(SpacePreferences.symbol(forSpace: appState.currentSpace, store: store))
        XCTAssertEqual(sut.statusBarIconUpdateCount, initialCount + 1, "updateStatusBarIcon should be called")
    }

    func testResetStyleToDefault_whenDeclined_preservesPreferences() {
        setupSpaceWithPreferences(space: appState.currentSpace, style: .pentagon)
        alertFactory.shouldConfirm = false

        sut.resetStyleToDefault()

        XCTAssertEqual(SpacePreferences.iconStyle(forSpace: appState.currentSpace, store: store), .pentagon)
    }

    func testResetStyleToDefault_preservesColors() {
        let testColors = SpaceColors(foreground: .systemGreen, background: .systemPurple)
        setupSpaceWithPreferences(
            space: appState.currentSpace,
            style: .hexagon,
            colors: testColors,
            symbol: "star.fill"
        )
        alertFactory.shouldConfirm = true

        sut.resetStyleToDefault()

        // Verify colors are preserved
        let colors = SpacePreferences.colors(forSpace: appState.currentSpace, store: store)
        XCTAssertNotNil(colors, "Colors should be preserved after resetting style")
        XCTAssertEqual(colors?.foreground, testColors.foreground)
        XCTAssertEqual(colors?.background, testColors.background)
    }

    // MARK: - resetColorToDefault Tests

    func testResetColorToDefault_whenConfirmed_clearsColors() {
        setupSpaceWithPreferences(
            space: appState.currentSpace,
            colors: SpaceColors(foreground: .cyan, background: .magenta)
        )
        alertFactory.shouldConfirm = true
        let initialCount = sut.statusBarIconUpdateCount

        sut.resetColorToDefault()

        XCTAssertNil(SpacePreferences.colors(forSpace: appState.currentSpace, store: store))
        XCTAssertEqual(sut.statusBarIconUpdateCount, initialCount + 1, "updateStatusBarIcon should be called")
    }

    func testResetColorToDefault_whenDeclined_preservesColors() {
        let testColors = SpaceColors(foreground: .cyan, background: .magenta)
        setupSpaceWithPreferences(space: appState.currentSpace, colors: testColors)
        alertFactory.shouldConfirm = false

        sut.resetColorToDefault()

        XCTAssertNotNil(SpacePreferences.colors(forSpace: appState.currentSpace, store: store))
    }

    func testResetColorToDefault_preservesStyleAndSymbol() {
        let testStyle = IconStyle.triangle
        let testSymbol = "heart.fill"
        setupSpaceWithPreferences(
            space: appState.currentSpace,
            style: testStyle,
            colors: SpaceColors(foreground: .cyan, background: .magenta),
            symbol: testSymbol
        )
        alertFactory.shouldConfirm = true

        sut.resetColorToDefault()

        // Verify style and symbol are preserved
        XCTAssertEqual(
            SpacePreferences.iconStyle(forSpace: appState.currentSpace, store: store),
            testStyle,
            "Style should be preserved after resetting color"
        )
        XCTAssertEqual(
            SpacePreferences.symbol(forSpace: appState.currentSpace, store: store),
            testSymbol,
            "Symbol should be preserved after resetting color"
        )
    }

    // MARK: - Edge Cases: currentSpace == 0 (No-ops)

    func testApplyAllToAllSpaces_whenCurrentSpaceIsZero_noOp() {
        // Setup with no active space
        stub.displays = []
        appState = AppState(displaySpaceProvider: stub, skipObservers: true)
        sut = AppDelegate(appState: appState, alertFactory: alertFactory)
        XCTAssertEqual(appState.currentSpace, 0)

        sut.applyToAllSpaces()

        XCTAssertEqual(alertFactory.alertsShown.count, 0, "No alert should be shown when currentSpace is 0")
    }

    func testResetSpaceToDefault_whenCurrentSpaceIsZero_noOp() {
        stub.displays = []
        appState = AppState(displaySpaceProvider: stub, skipObservers: true)
        sut = AppDelegate(appState: appState, alertFactory: alertFactory)

        sut.resetSpaceToDefault()

        XCTAssertEqual(alertFactory.alertsShown.count, 0, "No alert should be shown when currentSpace is 0")
    }

    func testInvertColors_whenCurrentSpaceIsZero_noOp() {
        stub.displays = []
        appState = AppState(displaySpaceProvider: stub, skipObservers: true)
        sut = AppDelegate(appState: appState, alertFactory: alertFactory)
        let initialCount = sut.statusBarIconUpdateCount

        sut.invertColors()

        XCTAssertEqual(sut.statusBarIconUpdateCount, initialCount, "updateStatusBarIcon should not be called")
    }

    func testApplyColorsToAllSpaces_whenCurrentSpaceIsZero_noOp() {
        stub.displays = []
        appState = AppState(displaySpaceProvider: stub, skipObservers: true)
        sut = AppDelegate(appState: appState, alertFactory: alertFactory)

        sut.applyColorsToAllSpaces()

        XCTAssertEqual(alertFactory.alertsShown.count, 0, "No alert should be shown when currentSpace is 0")
    }

    func testApplyStyleToAllSpaces_whenCurrentSpaceIsZero_noOp() {
        stub.displays = []
        appState = AppState(displaySpaceProvider: stub, skipObservers: true)
        sut = AppDelegate(appState: appState, alertFactory: alertFactory)

        sut.applyStyleToAllSpaces()

        XCTAssertEqual(alertFactory.alertsShown.count, 0, "No alert should be shown when currentSpace is 0")
    }

    func testResetStyleToDefault_whenCurrentSpaceIsZero_noOp() {
        stub.displays = []
        appState = AppState(displaySpaceProvider: stub, skipObservers: true)
        sut = AppDelegate(appState: appState, alertFactory: alertFactory)

        sut.resetStyleToDefault()

        XCTAssertEqual(alertFactory.alertsShown.count, 0, "No alert should be shown when currentSpace is 0")
    }

    // MARK: - Edge Cases: Symbol vs Number Mode

    func testApplyAllToAllSpaces_inSymbolMode_appliesSymbolToAll() {
        let testSymbol = "star.fill"
        setupSpaceWithPreferences(space: appState.currentSpace, style: .circle, symbol: testSymbol)
        alertFactory.shouldConfirm = true

        sut.applyToAllSpaces()

        for space in 1 ... 4 {
            XCTAssertEqual(
                SpacePreferences.symbol(forSpace: space, store: store),
                testSymbol,
                "Symbol should be applied"
            )
            XCTAssertEqual(
                SpacePreferences.iconStyle(forSpace: space, store: store),
                .circle,
                "Style should also be applied"
            )
        }
    }

    func testApplyAllToAllSpaces_inNumberMode_clearsSymbolsOnAllSpaces() {
        // Set symbols on all spaces first
        for space in 1 ... 4 {
            SpacePreferences.setSymbol("heart.fill", forSpace: space, store: store)
        }
        // Current space is in number mode (no symbol)
        SpacePreferences.clearSymbol(forSpace: appState.currentSpace, store: store)
        setupSpaceWithPreferences(space: appState.currentSpace, style: .triangle)
        alertFactory.shouldConfirm = true

        sut.applyToAllSpaces()

        for space in 1 ... 4 {
            XCTAssertNil(SpacePreferences.symbol(forSpace: space, store: store), "Symbol should be cleared")
            XCTAssertEqual(
                SpacePreferences.iconStyle(forSpace: space, store: store),
                .triangle,
                "Style should be applied"
            )
        }
    }

    func testApplyStyleToAllSpaces_inSymbolMode_preservesSymbol() {
        let testSymbol = "bolt.fill"
        setupSpaceWithPreferences(space: appState.currentSpace, style: .hexagon, symbol: testSymbol)
        alertFactory.shouldConfirm = true

        sut.applyStyleToAllSpaces()

        for space in 1 ... 4 {
            XCTAssertEqual(SpacePreferences.symbol(forSpace: space, store: store), testSymbol)
            XCTAssertEqual(SpacePreferences.iconStyle(forSpace: space, store: store), .hexagon)
        }
    }

    // MARK: - setForegroundColor Tests

    func testSetForegroundColor_withNoExistingColors_usesDefaultBackground() {
        // Ensure no custom colors exist
        SpacePreferences.clearColors(forSpace: appState.currentSpace, store: store)
        XCTAssertNil(appState.currentColors, "Should have no custom colors initially")

        // Set only foreground color
        sut.setForegroundColor(.systemRed)

        // Verify the background uses the default (not black)
        let colors = SpacePreferences.colors(forSpace: appState.currentSpace, store: store)
        XCTAssertNotNil(colors, "Colors should be set")
        XCTAssertEqual(colors?.foreground, .systemRed, "Foreground should be the selected color")

        let defaults = IconColors.filledColors(darkMode: appState.darkModeEnabled)
        XCTAssertEqual(colors?.background, defaults.background, "Background should use the default, not black")
    }

    func testSetForegroundColor_withExistingColors_preservesBackground() {
        // Set up existing colors
        let existingBackground = NSColor.systemBlue
        SpacePreferences.setColors(
            SpaceColors(foreground: .white, background: existingBackground),
            forSpace: appState.currentSpace,
            store: store
        )

        // Set foreground color
        sut.setForegroundColor(.systemGreen)

        // Verify background is preserved
        let colors = SpacePreferences.colors(forSpace: appState.currentSpace, store: store)
        XCTAssertEqual(colors?.foreground, .systemGreen, "Foreground should be updated")
        XCTAssertEqual(colors?.background, existingBackground, "Background should be preserved")
    }

    // MARK: - setBackgroundColor Tests

    func testSetBackgroundColor_withNoExistingColors_usesDefaultForeground() {
        // Ensure no custom colors exist
        SpacePreferences.clearColors(forSpace: appState.currentSpace, store: store)
        XCTAssertNil(appState.currentColors, "Should have no custom colors initially")

        // Set only background color
        sut.setBackgroundColor(.systemBlue)

        // Verify the foreground uses the default (not white)
        let colors = SpacePreferences.colors(forSpace: appState.currentSpace, store: store)
        XCTAssertNotNil(colors, "Colors should be set")
        XCTAssertEqual(colors?.background, .systemBlue, "Background should be the selected color")

        let defaults = IconColors.filledColors(darkMode: appState.darkModeEnabled)
        XCTAssertEqual(colors?.foreground, defaults.foreground, "Foreground should use the default, not white")
    }

    func testSetBackgroundColor_withExistingColors_preservesForeground() {
        // Set up existing colors
        let existingForeground = NSColor.systemRed
        SpacePreferences.setColors(
            SpaceColors(foreground: existingForeground, background: .black),
            forSpace: appState.currentSpace,
            store: store
        )

        // Set background color
        sut.setBackgroundColor(.systemYellow)

        // Verify foreground is preserved
        let colors = SpacePreferences.colors(forSpace: appState.currentSpace, store: store)
        XCTAssertEqual(colors?.foreground, existingForeground, "Foreground should be preserved")
        XCTAssertEqual(colors?.background, .systemYellow, "Background should be updated")
    }

    // MARK: - Edge Cases: Dark Mode Defaults When Colors Absent

    func testInvertColors_withNoCustomColors_usesDarkModeDefaults() {
        // No custom colors set - should use dark mode defaults
        let previousAppearance = NSApp.appearance
        NSApp.appearance = NSAppearance(named: .darkAqua)
        appState.updateDarkModeStatus()

        sut.invertColors()

        let colors = SpacePreferences.colors(forSpace: appState.currentSpace, store: store)
        XCTAssertNotNil(colors, "Colors should be set after invert")

        // Dark mode filled defaults: foreground=black, background=gray (0.7)
        // After invert: foreground=gray (0.7), background=black
        let defaults = IconColors.filledColors(darkMode: true)
        XCTAssertEqual(colors?.foreground, defaults.background, "Foreground should be original background")
        XCTAssertEqual(colors?.background, defaults.foreground, "Background should be original foreground")

        // Cleanup
        NSApp.appearance = previousAppearance
    }

    func testInvertColors_withNoCustomColors_usesLightModeDefaults() {
        let previousAppearance = NSApp.appearance
        NSApp.appearance = NSAppearance(named: .aqua)
        appState.updateDarkModeStatus()

        sut.invertColors()

        let colors = SpacePreferences.colors(forSpace: appState.currentSpace, store: store)
        XCTAssertNotNil(colors, "Colors should be set after invert")

        // Light mode filled defaults: foreground=white, background=gray (0.3)
        // After invert: foreground=gray (0.3), background=white
        let defaults = IconColors.filledColors(darkMode: false)
        XCTAssertEqual(colors?.foreground, defaults.background, "Foreground should be original background")
        XCTAssertEqual(colors?.background, defaults.foreground, "Background should be original foreground")

        // Cleanup
        NSApp.appearance = previousAppearance
    }

    // MARK: - Alert Verification Tests

    func testApplyAllToAllSpaces_showsCorrectAlert() {
        alertFactory.shouldConfirm = true

        sut.applyToAllSpaces()

        XCTAssertEqual(alertFactory.alertsShown.count, 1)
        let alert = alertFactory.alertsShown.first
        XCTAssertEqual(alert?.message, Localization.confirmApplyToAll)
        XCTAssertEqual(alert?.isDestructive, false)
    }

    func testResetSpaceToDefault_showsDestructiveAlert() {
        alertFactory.shouldConfirm = true

        sut.resetSpaceToDefault()

        XCTAssertEqual(alertFactory.alertsShown.count, 1)
        let alert = alertFactory.alertsShown.first
        XCTAssertEqual(alert?.message, Localization.confirmResetSpace)
        XCTAssertEqual(alert?.isDestructive, true)
    }

    func testResetAllSpacesToDefault_showsDestructiveAlert() {
        alertFactory.shouldConfirm = true

        sut.resetAllSpacesToDefault()

        XCTAssertEqual(alertFactory.alertsShown.count, 1)
        let alert = alertFactory.alertsShown.first
        XCTAssertEqual(alert?.message, Localization.confirmResetAllSpaces)
        XCTAssertEqual(alert?.isDestructive, true)
    }

    func testApplyColorsToAllSpaces_showsNonDestructiveAlert() {
        alertFactory.shouldConfirm = true

        sut.applyColorsToAllSpaces()

        XCTAssertEqual(alertFactory.alertsShown.count, 1)
        let alert = alertFactory.alertsShown.first
        XCTAssertEqual(alert?.message, Localization.confirmApplyColorToAll)
        XCTAssertEqual(alert?.isDestructive, false)
    }

    func testApplyStyleToAllSpaces_showsNonDestructiveAlert() {
        alertFactory.shouldConfirm = true

        sut.applyStyleToAllSpaces()

        XCTAssertEqual(alertFactory.alertsShown.count, 1)
        let alert = alertFactory.alertsShown.first
        XCTAssertEqual(alert?.message, Localization.confirmApplyStyleToAll)
        XCTAssertEqual(alert?.isDestructive, false)
    }

    func testResetStyleToDefault_showsDestructiveAlert() {
        alertFactory.shouldConfirm = true

        sut.resetStyleToDefault()

        XCTAssertEqual(alertFactory.alertsShown.count, 1)
        let alert = alertFactory.alertsShown.first
        XCTAssertEqual(alert?.message, Localization.confirmResetStyle)
        XCTAssertEqual(alert?.isDestructive, true)
    }

    func testResetColorToDefault_showsDestructiveAlert() {
        alertFactory.shouldConfirm = true

        sut.resetColorToDefault()

        XCTAssertEqual(alertFactory.alertsShown.count, 1)
        let alert = alertFactory.alertsShown.first
        XCTAssertEqual(alert?.message, Localization.confirmResetColor)
        XCTAssertEqual(alert?.isDestructive, true)
    }

    // MARK: - Size Scale Tests

    func testSizeScale_defaultValue() {
        XCTAssertEqual(Layout.defaultSizeScale, 100.0, "Default size scale should be 100")
    }

    func testSizeScale_range() {
        XCTAssertEqual(Layout.sizeScaleRange.lowerBound, 60.0, "Size scale lower bound should be 60")
        XCTAssertEqual(Layout.sizeScaleRange.upperBound, 120.0, "Size scale upper bound should be 120")
    }

    func testSizeScale_canBeModified() {
        store.sizeScale = 85.0
        XCTAssertEqual(store.sizeScale, 85.0)

        store.sizeScale = 115.0
        XCTAssertEqual(store.sizeScale, 115.0)
    }

    // MARK: - Space Preferences Edge Cases

    func testSpacePreferences_handleSpaceZero() {
        // Space 0 typically means "unknown space"
        SpacePreferences.setColors(SpaceColors(foreground: .red, background: .blue), forSpace: 0, store: store)

        // Should still work (storage allows it)
        let colors = SpacePreferences.colors(forSpace: 0, store: store)
        XCTAssertNotNil(colors)
    }

    func testSpacePreferences_handleLargeSpaceNumbers() {
        let largeSpace = 100

        SpacePreferences.setIconStyle(.hexagonOutline, forSpace: largeSpace, store: store)

        XCTAssertEqual(SpacePreferences.iconStyle(forSpace: largeSpace, store: store), .hexagonOutline)
    }

    func testSpacePreferences_handleNegativeSpaceNumbers() {
        let negativeSpace = -1

        SpacePreferences.setIconStyle(.circle, forSpace: negativeSpace, store: store)

        XCTAssertEqual(SpacePreferences.iconStyle(forSpace: negativeSpace, store: store), .circle)
    }

    // MARK: - menuWillOpen Tests

    func testMenuWillOpen_setsLaunchAtLoginCheckmark_whenEnabled() {
        sut.configureMenuBarIcon()
        launchAtLoginStub.isEnabled = true

        sut.menuWillOpen(sut.statusMenu)

        let launchAtLoginItem = sut.statusMenu.item(withTag: MenuTag.launchAtLogin.rawValue)
        XCTAssertEqual(launchAtLoginItem?.state, .on, "Launch at Login should be checked when enabled")
    }

    func testMenuWillOpen_setsLaunchAtLoginCheckmark_whenDisabled() {
        sut.configureMenuBarIcon()
        launchAtLoginStub.isEnabled = false

        sut.menuWillOpen(sut.statusMenu)

        let launchAtLoginItem = sut.statusMenu.item(withTag: MenuTag.launchAtLogin.rawValue)
        XCTAssertEqual(launchAtLoginItem?.state, .off, "Launch at Login should be unchecked when disabled")
    }

    func testMenuWillOpen_setsShowAllSpacesCheckmark_whenEnabled() {
        sut.configureMenuBarIcon()
        store.showAllSpaces = true

        sut.menuWillOpen(sut.statusMenu)

        let showAllSpacesItem = sut.statusMenu.item(withTag: MenuTag.showAllSpaces.rawValue)
        XCTAssertEqual(showAllSpacesItem?.state, .on, "Show All Spaces should be checked when enabled")
    }

    func testMenuWillOpen_setsShowAllSpacesCheckmark_whenDisabled() {
        sut.configureMenuBarIcon()
        store.showAllSpaces = false

        sut.menuWillOpen(sut.statusMenu)

        let showAllSpacesItem = sut.statusMenu.item(withTag: MenuTag.showAllSpaces.rawValue)
        XCTAssertEqual(showAllSpacesItem?.state, .off, "Show All Spaces should be unchecked when disabled")
    }

    func testMenuWillOpen_setsDimInactiveSpacesCheckmark_whenEnabled() {
        sut.configureMenuBarIcon()
        store.dimInactiveSpaces = true

        sut.menuWillOpen(sut.statusMenu)

        let dimInactiveItem = sut.statusMenu.item(withTag: MenuTag.dimInactiveSpaces.rawValue)
        XCTAssertEqual(dimInactiveItem?.state, .on, "Dim inactive Spaces should be checked when enabled")
    }

    func testMenuWillOpen_setsDimInactiveSpacesCheckmark_whenDisabled() {
        sut.configureMenuBarIcon()
        store.dimInactiveSpaces = false

        sut.menuWillOpen(sut.statusMenu)

        let dimInactiveItem = sut.statusMenu.item(withTag: MenuTag.dimInactiveSpaces.rawValue)
        XCTAssertEqual(dimInactiveItem?.state, .off, "Dim inactive Spaces should be unchecked when disabled")
    }

    func testMenuWillOpen_showsDimInactiveSpaces_whenShowAllSpacesEnabled() {
        sut.configureMenuBarIcon()
        store.showAllSpaces = true

        sut.menuWillOpen(sut.statusMenu)

        let dimInactiveItem = sut.statusMenu.item(withTag: MenuTag.dimInactiveSpaces.rawValue)
        XCTAssertFalse(
            dimInactiveItem?.isHidden ?? true,
            "Dim inactive Spaces should be visible when Show All Spaces is on"
        )
    }

    func testMenuWillOpen_hidesDimInactiveSpaces_whenShowAllSpacesDisabled() {
        sut.configureMenuBarIcon()
        store.showAllSpaces = false

        sut.menuWillOpen(sut.statusMenu)

        let dimInactiveItem = sut.statusMenu.item(withTag: MenuTag.dimInactiveSpaces.rawValue)
        XCTAssertTrue(
            dimInactiveItem?.isHidden ?? false,
            "Dim inactive Spaces should be hidden when Show All Spaces is off"
        )
    }

    func testMenuWillOpen_setsHideEmptySpacesCheckmark_whenEnabled() {
        sut.configureMenuBarIcon()
        store.hideEmptySpaces = true

        sut.menuWillOpen(sut.statusMenu)

        let hideEmptyItem = sut.statusMenu.item(withTag: MenuTag.hideEmptySpaces.rawValue)
        XCTAssertEqual(hideEmptyItem?.state, .on, "Hide empty Spaces should be checked when enabled")
    }

    func testMenuWillOpen_setsHideEmptySpacesCheckmark_whenDisabled() {
        sut.configureMenuBarIcon()
        store.hideEmptySpaces = false

        sut.menuWillOpen(sut.statusMenu)

        let hideEmptyItem = sut.statusMenu.item(withTag: MenuTag.hideEmptySpaces.rawValue)
        XCTAssertEqual(hideEmptyItem?.state, .off, "Hide empty Spaces should be unchecked when disabled")
    }

    func testMenuWillOpen_showsHideEmptySpaces_whenShowAllSpacesEnabled() {
        sut.configureMenuBarIcon()
        store.showAllSpaces = true

        sut.menuWillOpen(sut.statusMenu)

        let hideEmptyItem = sut.statusMenu.item(withTag: MenuTag.hideEmptySpaces.rawValue)
        XCTAssertFalse(
            hideEmptyItem?.isHidden ?? true,
            "Hide empty Spaces should be visible when Show All Spaces is on"
        )
    }

    func testMenuWillOpen_hidesHideEmptySpaces_whenShowAllSpacesDisabled() {
        sut.configureMenuBarIcon()
        store.showAllSpaces = false

        sut.menuWillOpen(sut.statusMenu)

        let hideEmptyItem = sut.statusMenu.item(withTag: MenuTag.hideEmptySpaces.rawValue)
        XCTAssertTrue(
            hideEmptyItem?.isHidden ?? false,
            "Hide empty Spaces should be hidden when Show All Spaces is off"
        )
    }

    func testMenuWillOpen_setsHideFullscreenAppsCheckmark_whenEnabled() {
        sut.configureMenuBarIcon()
        store.hideFullscreenApps = true

        sut.menuWillOpen(sut.statusMenu)

        let hideFullscreenItem = sut.statusMenu.item(withTag: MenuTag.hideFullscreenApps.rawValue)
        XCTAssertEqual(hideFullscreenItem?.state, .on, "Hide full-screen apps should be checked when enabled")
    }

    func testMenuWillOpen_setsHideFullscreenAppsCheckmark_whenDisabled() {
        sut.configureMenuBarIcon()
        store.hideFullscreenApps = false

        sut.menuWillOpen(sut.statusMenu)

        let hideFullscreenItem = sut.statusMenu.item(withTag: MenuTag.hideFullscreenApps.rawValue)
        XCTAssertEqual(hideFullscreenItem?.state, .off, "Hide full-screen apps should be unchecked when disabled")
    }

    func testMenuWillOpen_showsHideFullscreenApps_whenShowAllSpacesEnabled() {
        sut.configureMenuBarIcon()
        store.showAllSpaces = true

        sut.menuWillOpen(sut.statusMenu)

        let hideFullscreenItem = sut.statusMenu.item(withTag: MenuTag.hideFullscreenApps.rawValue)
        XCTAssertFalse(
            hideFullscreenItem?.isHidden ?? true,
            "Hide full-screen apps should be visible when Show All Spaces is on"
        )
    }

    func testMenuWillOpen_hidesHideFullscreenApps_whenShowAllSpacesDisabled() {
        sut.configureMenuBarIcon()
        store.showAllSpaces = false

        sut.menuWillOpen(sut.statusMenu)

        let hideFullscreenItem = sut.statusMenu.item(withTag: MenuTag.hideFullscreenApps.rawValue)
        XCTAssertTrue(
            hideFullscreenItem?.isHidden ?? false,
            "Hide full-screen apps should be hidden when Show All Spaces is off"
        )
    }

    func testMenuWillOpen_setsHideSingleSpaceCheckmark_whenEnabled() {
        sut.configureMenuBarIcon()
        store.hideSingleSpace = true

        sut.menuWillOpen(sut.statusMenu)

        let hideSingleSpaceItem = sut.statusMenu.item(withTag: MenuTag.hideSingleSpace.rawValue)
        XCTAssertEqual(hideSingleSpaceItem?.state, .on, "Hide single Space should be checked when enabled")
    }

    func testMenuWillOpen_setsHideSingleSpaceCheckmark_whenDisabled() {
        sut.configureMenuBarIcon()
        store.hideSingleSpace = false

        sut.menuWillOpen(sut.statusMenu)

        let hideSingleSpaceItem = sut.statusMenu.item(withTag: MenuTag.hideSingleSpace.rawValue)
        XCTAssertEqual(hideSingleSpaceItem?.state, .off, "Hide single Space should be unchecked when disabled")
    }

    func testMenuWillOpen_hidesColorSwatches_whenSymbolActive() {
        sut.configureMenuBarIcon()
        SpacePreferences.setSymbol("star.fill", forSpace: appState.currentSpace, store: store)

        // Find the Colors submenu
        let colorsMenuItem = sut.statusMenu.items.first { $0.title == Localization.menuColor }
        guard let colorsMenu = colorsMenuItem?.submenu else {
            XCTFail("Colors submenu not found")
            return
        }

        sut.menuWillOpen(colorsMenu)

        // Verify color swatch items are hidden
        let foregroundLabel = colorsMenu.item(withTag: MenuTag.foregroundLabel.rawValue)
        let foregroundSwatch = colorsMenu.item(withTag: MenuTag.foregroundSwatch.rawValue)
        let colorSeparator = colorsMenu.item(withTag: MenuTag.colorSeparator.rawValue)
        let backgroundLabel = colorsMenu.item(withTag: MenuTag.backgroundLabel.rawValue)
        let backgroundSwatch = colorsMenu.item(withTag: MenuTag.backgroundSwatch.rawValue)

        XCTAssertTrue(foregroundLabel?.isHidden ?? false, "Foreground label should be hidden when symbol is active")
        XCTAssertTrue(foregroundSwatch?.isHidden ?? false, "Foreground swatch should be hidden when symbol is active")
        XCTAssertTrue(colorSeparator?.isHidden ?? false, "Color separator should be hidden when symbol is active")
        XCTAssertTrue(backgroundLabel?.isHidden ?? false, "Background label should be hidden when symbol is active")
        XCTAssertTrue(backgroundSwatch?.isHidden ?? false, "Background swatch should be hidden when symbol is active")
    }

    func testMenuWillOpen_showsSymbolColorSwatch_whenSymbolActive() {
        sut.configureMenuBarIcon()
        SpacePreferences.setSymbol("star.fill", forSpace: appState.currentSpace, store: store)

        // Find the Colors submenu
        let colorsMenuItem = sut.statusMenu.items.first { $0.title == Localization.menuColor }
        guard let colorsMenu = colorsMenuItem?.submenu else {
            XCTFail("Colors submenu not found")
            return
        }

        sut.menuWillOpen(colorsMenu)

        // Verify symbol color swatch is shown
        let symbolColorSwatch = colorsMenu.item(withTag: MenuTag.symbolColorSwatch.rawValue)
        XCTAssertFalse(
            symbolColorSwatch?.isHidden ?? true,
            "Symbol color swatch should be visible when symbol is active"
        )
    }

    func testMenuWillOpen_hidesSymbolColorSwatch_whenSymbolNotActive() {
        sut.configureMenuBarIcon()
        SpacePreferences.clearSymbol(forSpace: appState.currentSpace, store: store)

        // Find the Colors submenu
        let colorsMenuItem = sut.statusMenu.items.first { $0.title == Localization.menuColor }
        guard let colorsMenu = colorsMenuItem?.submenu else {
            XCTFail("Colors submenu not found")
            return
        }

        sut.menuWillOpen(colorsMenu)

        // Verify symbol color swatch is hidden
        let symbolColorSwatch = colorsMenu.item(withTag: MenuTag.symbolColorSwatch.rawValue)
        XCTAssertTrue(symbolColorSwatch?.isHidden ?? false, "Symbol color swatch should be hidden when no symbol")
    }

    func testMenuWillOpen_showsColorSwatches_whenSymbolNotActive() {
        sut.configureMenuBarIcon()
        SpacePreferences.clearSymbol(forSpace: appState.currentSpace, store: store)

        // Find the Colors submenu
        let colorsMenuItem = sut.statusMenu.items.first { $0.title == Localization.menuColor }
        guard let colorsMenu = colorsMenuItem?.submenu else {
            XCTFail("Colors submenu not found")
            return
        }

        sut.menuWillOpen(colorsMenu)

        // Verify color swatch items are visible
        let foregroundLabel = colorsMenu.item(withTag: MenuTag.foregroundLabel.rawValue)
        let foregroundSwatch = colorsMenu.item(withTag: MenuTag.foregroundSwatch.rawValue)
        let colorSeparator = colorsMenu.item(withTag: MenuTag.colorSeparator.rawValue)
        let backgroundLabel = colorsMenu.item(withTag: MenuTag.backgroundLabel.rawValue)
        let backgroundSwatch = colorsMenu.item(withTag: MenuTag.backgroundSwatch.rawValue)

        XCTAssertFalse(foregroundLabel?.isHidden ?? true, "Foreground label should be visible when no symbol")
        XCTAssertFalse(foregroundSwatch?.isHidden ?? true, "Foreground swatch should be visible when no symbol")
        XCTAssertFalse(colorSeparator?.isHidden ?? true, "Color separator should be visible when no symbol")
        XCTAssertFalse(backgroundLabel?.isHidden ?? true, "Background label should be visible when no symbol")
        XCTAssertFalse(backgroundSwatch?.isHidden ?? true, "Background swatch should be visible when no symbol")
    }

    func testMenuWillOpen_hidesBackgroundColorOptions_whenTransparentStyleActive() {
        sut.configureMenuBarIcon()
        SpacePreferences.setIconStyle(.transparent, forSpace: appState.currentSpace, store: store)

        // Find the Colors submenu
        let colorsMenuItem = sut.statusMenu.items.first { $0.title == Localization.menuColor }
        guard let colorsMenu = colorsMenuItem?.submenu else {
            XCTFail("Colors submenu not found")
            return
        }

        sut.menuWillOpen(colorsMenu)

        // Background options should be hidden for transparent style
        let colorSeparator = colorsMenu.item(withTag: MenuTag.colorSeparator.rawValue)
        let backgroundLabel = colorsMenu.item(withTag: MenuTag.backgroundLabel.rawValue)
        let backgroundSwatch = colorsMenu.item(withTag: MenuTag.backgroundSwatch.rawValue)

        XCTAssertTrue(colorSeparator?.isHidden ?? false, "Color separator should be hidden for transparent style")
        XCTAssertTrue(backgroundLabel?.isHidden ?? false, "Background label should be hidden for transparent style")
        XCTAssertTrue(backgroundSwatch?.isHidden ?? false, "Background swatch should be hidden for transparent style")

        // Foreground options should still be visible
        let foregroundLabel = colorsMenu.item(withTag: MenuTag.foregroundLabel.rawValue)
        let foregroundSwatch = colorsMenu.item(withTag: MenuTag.foregroundSwatch.rawValue)

        XCTAssertFalse(foregroundLabel?.isHidden ?? true, "Foreground label should be visible for transparent style")
        XCTAssertFalse(foregroundSwatch?.isHidden ?? true, "Foreground swatch should be visible for transparent style")
    }

    func testMenuWillOpen_updatesStatusBarIcon() {
        sut.configureMenuBarIcon()
        let initialCount = sut.statusBarIconUpdateCount

        sut.menuWillOpen(sut.statusMenu)

        XCTAssertEqual(
            sut.statusBarIconUpdateCount,
            initialCount + 1,
            "updateStatusBarIcon should be called when menu opens"
        )
    }

    func testMenuWillOpen_showsSeparatorItems_whenShowAllDisplaysEnabledAndMultipleDisplays() {
        // Set up multiple displays (required for separator to be visible)
        stub.displays = [
            CGSStub.makeDisplay(
                displayID: "Main",
                spaces: [(id: 100, isFullscreen: false), (id: 101, isFullscreen: false)],
                activeSpaceID: 101
            ),
            CGSStub.makeDisplay(
                displayID: "External",
                spaces: [(id: 200, isFullscreen: false), (id: 201, isFullscreen: false)],
                activeSpaceID: 200
            ),
        ]
        appState.forceSpaceUpdate()

        sut.configureMenuBarIcon()
        store.showAllDisplays = true

        // Find the Colors submenu
        let colorsMenuItem = sut.statusMenu.items.first { $0.title == Localization.menuColor }
        guard let colorsMenu = colorsMenuItem?.submenu else {
            XCTFail("Colors submenu not found")
            return
        }

        sut.menuWillOpen(colorsMenu)

        let separatorLabel = colorsMenu.item(withTag: MenuTag.separatorLabel.rawValue)
        let separatorSwatch = colorsMenu.item(withTag: MenuTag.separatorSwatch.rawValue)
        XCTAssertFalse(
            separatorLabel?.isHidden ?? true,
            "Separator label should be visible when Show All Displays is on with multiple displays"
        )
        XCTAssertFalse(
            separatorSwatch?.isHidden ?? true,
            "Separator swatch should be visible when Show All Displays is on with multiple displays"
        )
    }

    func testMenuWillOpen_hidesSeparatorItems_whenShowAllDisplaysEnabledButSingleDisplay() {
        // Single display setup (default from setUp)
        sut.configureMenuBarIcon()
        store.showAllDisplays = true

        // Find the Colors submenu
        let colorsMenuItem = sut.statusMenu.items.first { $0.title == Localization.menuColor }
        guard let colorsMenu = colorsMenuItem?.submenu else {
            XCTFail("Colors submenu not found")
            return
        }

        sut.menuWillOpen(colorsMenu)

        let separatorLabel = colorsMenu.item(withTag: MenuTag.separatorLabel.rawValue)
        let separatorSwatch = colorsMenu.item(withTag: MenuTag.separatorSwatch.rawValue)
        XCTAssertTrue(
            separatorLabel?.isHidden ?? false,
            "Separator label should be hidden with single display even when Show All Displays is on"
        )
        XCTAssertTrue(
            separatorSwatch?.isHidden ?? false,
            "Separator swatch should be hidden with single display even when Show All Displays is on"
        )
    }

    func testMenuWillOpen_hidesSeparatorItems_whenShowAllDisplaysDisabled() {
        sut.configureMenuBarIcon()
        store.showAllDisplays = false

        // Find the Colors submenu
        let colorsMenuItem = sut.statusMenu.items.first { $0.title == Localization.menuColor }
        guard let colorsMenu = colorsMenuItem?.submenu else {
            XCTFail("Colors submenu not found")
            return
        }

        sut.menuWillOpen(colorsMenu)

        let separatorLabel = colorsMenu.item(withTag: MenuTag.separatorLabel.rawValue)
        let separatorSwatch = colorsMenu.item(withTag: MenuTag.separatorSwatch.rawValue)
        XCTAssertTrue(
            separatorLabel?.isHidden ?? false,
            "Separator label should be hidden when Show All Displays is off"
        )
        XCTAssertTrue(
            separatorSwatch?.isHidden ?? false,
            "Separator swatch should be hidden when Show All Displays is off"
        )
    }

    func testResetColorToDefault_clearsSeparatorColor() {
        store.separatorColor = .systemRed
        alertFactory.shouldConfirm = true

        sut.resetColorToDefault()

        XCTAssertNil(store.separatorColor, "Separator color should be cleared on reset")
    }

    func testResetAllSpacesToDefault_clearsSeparatorColor() {
        store.separatorColor = .systemBlue
        alertFactory.shouldConfirm = true

        sut.resetAllSpacesToDefault()

        XCTAssertNil(store.separatorColor, "Separator color should be cleared on reset all")
    }

    // MARK: - toggleLaunchAtLogin Tests

    func testToggleLaunchAtLogin_togglesFromFalseToTrue() {
        launchAtLoginStub.isEnabled = false

        sut.toggleLaunchAtLogin()

        XCTAssertTrue(launchAtLoginStub.isEnabled, "LaunchAtLogin should toggle to true")
    }

    func testToggleLaunchAtLogin_togglesFromTrueToFalse() {
        launchAtLoginStub.isEnabled = true

        sut.toggleLaunchAtLogin()

        XCTAssertFalse(launchAtLoginStub.isEnabled, "LaunchAtLogin should toggle to false")
    }

    func testToggleLaunchAtLogin_multipleToggles() {
        launchAtLoginStub.isEnabled = false

        sut.toggleLaunchAtLogin()
        XCTAssertTrue(launchAtLoginStub.isEnabled)

        sut.toggleLaunchAtLogin()
        XCTAssertFalse(launchAtLoginStub.isEnabled)

        sut.toggleLaunchAtLogin()
        XCTAssertTrue(launchAtLoginStub.isEnabled)
    }

    func testToggleLaunchAtLogin_menuCheckmarkUpdatesAfterMenuWillOpen() {
        sut.configureMenuBarIcon()
        launchAtLoginStub.isEnabled = false

        // Toggle launch at login
        sut.toggleLaunchAtLogin()
        XCTAssertTrue(launchAtLoginStub.isEnabled, "LaunchAtLogin should be enabled after toggle")

        // Refresh menu state via menuWillOpen
        sut.menuWillOpen(sut.statusMenu)

        // Verify the menu checkmark reflects the new state
        let launchAtLoginItem = sut.statusMenu.item(withTag: MenuTag.launchAtLogin.rawValue)
        XCTAssertEqual(
            launchAtLoginItem?.state,
            .on,
            "Launch at Login menu item should be checked after toggling to enabled and calling menuWillOpen"
        )

        // Toggle again to disabled
        sut.toggleLaunchAtLogin()
        XCTAssertFalse(launchAtLoginStub.isEnabled, "LaunchAtLogin should be disabled after second toggle")

        // Refresh menu state again
        sut.menuWillOpen(sut.statusMenu)

        // Verify the checkmark is now off
        XCTAssertEqual(
            launchAtLoginItem?.state,
            .off,
            "Launch at Login menu item should be unchecked after toggling to disabled and calling menuWillOpen"
        )
    }

    // MARK: - Observer/Task Lifecycle Tests

    func testStartObservingAppState_createsObservationTask() {
        XCTAssertNil(sut.observationTask, "Task should not exist before starting observation")

        sut.startObservingAppState()

        XCTAssertNotNil(sut.observationTask, "Task should exist after starting observation")
    }

    func testStopObservingAppState_cancelsTask() {
        sut.startObservingAppState()
        XCTAssertNotNil(sut.observationTask)

        sut.stopObservingAppState()

        XCTAssertNil(sut.observationTask, "Task should be nil after stopping observation")
    }

    func testObservationTask_isCancelledOnStop() {
        sut.startObservingAppState()
        let task = sut.observationTask
        XCTAssertNotNil(task)

        sut.stopObservingAppState()

        // Task.cancel() is synchronous, so the task is immediately marked cancelled
        XCTAssertTrue(task?.isCancelled ?? false, "Task should be cancelled after stopping observation")
    }

    func testObservation_updatesStatusBarIconOnAppStateChange() async {
        // Set up notifier before starting observation
        var (_, iterator) = makeUpdateNotifier()

        sut.startObservingAppState()
        let initialCount = sut.statusBarIconUpdateCount

        // Brief yield to let observation loop register its first tracking
        await Task.yield()

        // Trigger an app state change
        appState.setSpaceState(labels: ["1", "2", "3"], currentSpace: 3, currentLabel: "3")

        // Wait for the onChange callback to fire (deterministic, no sleep needed)
        _ = await iterator.next()

        // The observation task should have triggered updateStatusBarIcon
        XCTAssertGreaterThan(
            sut.statusBarIconUpdateCount,
            initialCount,
            "updateStatusBarIcon should be called when appState changes"
        )
    }

    func testStopObservingAppState_stopsObservationLoop() async {
        sut.startObservingAppState()
        XCTAssertNotNil(sut.observationTask, "Task should exist after starting")

        // Brief yield to let observation loop register its first tracking
        await Task.yield()

        // Stop observation
        sut.stopObservingAppState()
        XCTAssertNil(sut.observationTask, "Task should be nil after stopping")

        // Trigger a change - the previously-registered onChange callback may still fire
        let countBeforeFirstChange = sut.statusBarIconUpdateCount
        appState.setSpaceState(labels: ["1", "2"], currentSpace: 1, currentLabel: "1")

        // Wait for any pending callback (poll until count changes or timeout)
        _ = await waitForCountChange(from: countBeforeFirstChange)

        // Record count (may or may not have incremented from pending callback)
        let countAfterFirstChange = sut.statusBarIconUpdateCount

        // Trigger another change - this should NOT trigger any callback
        // because the loop is stopped and no new observation was registered
        appState.setSpaceState(labels: ["1", "2", "3"], currentSpace: 2, currentLabel: "2")

        // Poll to verify count does NOT change (should timeout with count unchanged)
        let countChanged = await waitForCountChange(from: countAfterFirstChange)

        // Count should be stable - no new callbacks registered after loop stopped
        XCTAssertFalse(
            countChanged,
            "Count should stabilize after observation loop stops (first change may fire pending callback, second should not)"
        )
        XCTAssertEqual(
            sut.statusBarIconUpdateCount,
            countAfterFirstChange,
            "statusBarIconUpdateCount should remain unchanged after second state change"
        )

        // Task should still be nil
        XCTAssertNil(sut.observationTask, "Task should remain nil after changes")
    }

    func testTearDown_cancelsObservationTask_preventingLeaks() {
        // Create a new delegate and start observation
        let localStub = CGSStub()
        localStub.activeDisplayIdentifier = "Main"
        localStub.displays = [
            CGSStub.makeDisplay(displayID: "Main", spaces: [(id: 100, isFullscreen: false)], activeSpaceID: 100),
        ]
        let localAppState = AppState(displaySpaceProvider: localStub, skipObservers: true)
        let localDelegate = AppDelegate(
            appState: localAppState,
            alertFactory: StubAlertFactory(),
            launchAtLogin: StubLaunchAtLoginProvider()
        )

        localDelegate.startObservingAppState()
        XCTAssertNotNil(localDelegate.observationTask, "Task should be running")

        // Simulate tearDown
        localDelegate.stopObservingAppState()

        XCTAssertNil(localDelegate.observationTask, "Task should be nil after cleanup")
    }
}
