import XCTest
@testable import WhichSpace

/// Performance benchmarks for icon generation and rendering.
@MainActor
final class PerformanceTests: IsolatedDefaultsTestCase {
    private var stub: CGSStub!

    override func setUp() {
        super.setUp()
        stub = CGSStub()
    }

    override func tearDown() {
        stub = nil
        super.tearDown()
    }

    // MARK: - SpaceIconGenerator Benchmarks

    func testPerformance_generateIcon_allStyles() {
        measure {
            for style in IconStyle.allCases {
                _ = SpaceIconGenerator.generateIcon(
                    for: "1",
                    darkMode: false,
                    style: style
                )
            }
        }
    }

    func testPerformance_generateIcon_squareStyle() {
        measure {
            for _ in 0 ..< 100 {
                _ = SpaceIconGenerator.generateIcon(
                    for: "1",
                    darkMode: false,
                    style: .square
                )
            }
        }
    }

    func testPerformance_generateIcon_withCustomColors() {
        let colors = SpaceColors(foreground: .red, background: .blue)
        measure {
            for _ in 0 ..< 100 {
                _ = SpaceIconGenerator.generateIcon(
                    for: "1",
                    darkMode: false,
                    customColors: colors,
                    style: .square
                )
            }
        }
    }

    func testPerformance_generateIcon_multiDigitLabels() {
        let labels = ["1", "5", "10", "99"]
        measure {
            for label in labels {
                for style in IconStyle.allCases {
                    _ = SpaceIconGenerator.generateIcon(
                        for: label,
                        darkMode: false,
                        style: style
                    )
                }
            }
        }
    }

    func testPerformance_generateSymbolIcon_sfSymbol() {
        measure {
            for _ in 0 ..< 100 {
                _ = SpaceIconGenerator.generateSymbolIcon(
                    symbolName: "star.fill",
                    darkMode: false
                )
            }
        }
    }

    func testPerformance_generateSymbolIcon_emoji() {
        measure {
            for _ in 0 ..< 100 {
                _ = SpaceIconGenerator.generateSymbolIcon(
                    symbolName: "\u{1F680}",
                    darkMode: false
                )
            }
        }
    }

    // MARK: - StatusBarRenderer Benchmarks

    func testPerformance_statusBarIcon_singleSpace() {
        stub.activeDisplayIdentifier = "Main"
        stub.displays = [
            CGSStub.makeDisplay(
                displayID: "Main",
                spaces: [(id: 100, isFullscreen: false)],
                activeSpaceID: 100
            ),
        ]
        let appState = AppState(displaySpaceProvider: stub, skipObservers: true, store: store)

        measure {
            for _ in 0 ..< 50 {
                _ = appState.statusBarIcon
            }
        }
    }

    func testPerformance_statusBarIcon_multipleSpaces() {
        stub.activeDisplayIdentifier = "Main"
        stub.displays = [
            CGSStub.makeDisplay(
                displayID: "Main",
                spaces: [
                    (id: 100, isFullscreen: false),
                    (id: 101, isFullscreen: false),
                    (id: 102, isFullscreen: false),
                    (id: 103, isFullscreen: false),
                    (id: 104, isFullscreen: false),
                ],
                activeSpaceID: 102
            ),
        ]
        store.showAllSpaces = true
        let appState = AppState(displaySpaceProvider: stub, skipObservers: true, store: store)

        measure {
            for _ in 0 ..< 20 {
                _ = appState.statusBarIcon
            }
        }
    }

    func testPerformance_statusBarIcon_crossDisplay() {
        stub.activeDisplayIdentifier = "DisplayA"
        stub.displays = [
            CGSStub.makeDisplay(
                displayID: "DisplayA",
                spaces: [
                    (id: 100, isFullscreen: false),
                    (id: 101, isFullscreen: false),
                    (id: 102, isFullscreen: false),
                ],
                activeSpaceID: 100
            ),
            CGSStub.makeDisplay(
                displayID: "DisplayB",
                spaces: [
                    (id: 200, isFullscreen: false),
                    (id: 201, isFullscreen: false),
                ],
                activeSpaceID: 200
            ),
        ]
        store.showAllDisplays = true
        let appState = AppState(displaySpaceProvider: stub, skipObservers: true, store: store)

        measure {
            for _ in 0 ..< 20 {
                _ = appState.statusBarIcon
            }
        }
    }

    func testPerformance_statusBarLayout() {
        stub.activeDisplayIdentifier = "Main"
        stub.displays = [
            CGSStub.makeDisplay(
                displayID: "Main",
                spaces: [
                    (id: 100, isFullscreen: false),
                    (id: 101, isFullscreen: false),
                    (id: 102, isFullscreen: false),
                    (id: 103, isFullscreen: false),
                    (id: 104, isFullscreen: false),
                ],
                activeSpaceID: 102
            ),
        ]
        store.showAllSpaces = true
        let appState = AppState(displaySpaceProvider: stub, skipObservers: true, store: store)

        measure {
            for _ in 0 ..< 100 {
                _ = appState.statusBarLayout()
            }
        }
    }

    func testPerformance_forceSpaceUpdate() {
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
        let appState = AppState(displaySpaceProvider: stub, skipObservers: true, store: store)

        measure {
            for _ in 0 ..< 100 {
                appState.forceSpaceUpdate()
            }
        }
    }
}
