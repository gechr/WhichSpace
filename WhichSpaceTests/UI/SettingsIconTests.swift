import AppKit
import Testing
@testable import WhichSpace

@MainActor
struct SettingsIconTests {
    private let store: DefaultsStore
    private let stub: CGSStub

    init() {
        let testSuite = TestSuiteFactory.createSuite()
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
                ],
                activeSpaceID: 100
            ),
        ]
    }

    /// AppState lives inside each test rather than on the suite: the suite
    /// value deallocates off the main actor, where AppState's deinit traps.
    private func makeAppState() -> AppState {
        AppState(displaySpaceProvider: stub, skipObservers: true, store: store)
    }

    private func pixels(_ image: NSImage) -> Data? {
        image.tiffRepresentation
    }

    @Test("honors per-Space preferences for a non-current Space")
    func honorsNonCurrentSpacePreferences() {
        let appState = makeAppState()
        let plain = appState.renderer.settingsIcon(forSpace: 3, display: "Main")
        SpacePreferences.setColors(
            SpaceColors(foreground: .red, background: .blue),
            forSpace: 3,
            display: "Main",
            store: store
        )
        let styled = appState.renderer.settingsIcon(forSpace: 3, display: "Main")
        #expect(pixels(styled) != pixels(plain))

        // Other Spaces stay unaffected
        let neighbor = appState.renderer.settingsIcon(forSpace: 2, display: "Main")
        let neighborAfter = appState.renderer.settingsIcon(forSpace: 2, display: "Main")
        #expect(pixels(neighbor) == pixels(neighborAfter))
    }

    @Test("resolves custom labels with the Space number")
    func resolvesLabels() {
        let appState = makeAppState()
        let plain = appState.renderer.settingsIcon(forSpace: 2, display: "Main")
        SpacePreferences.setLabel("S{#}", forSpace: 2, display: "Main", store: store)
        let labeled = appState.renderer.settingsIcon(forSpace: 2, display: "Main")
        #expect(pixels(labeled) != pixels(plain))
        // Labels widen the icon beyond the single-number canvas
        #expect(labeled.size.width > plain.size.width)
    }

    @Test("space 0 renders the default-style template from shared storage")
    func rendersTemplate() {
        let appState = makeAppState()
        let plain = appState.renderer.settingsIcon(forSpace: 0, display: nil)
        SpacePreferences.setColors(
            SpaceColors(foreground: .yellow, background: .purple),
            forSpace: SpacePreferences.defaultStyleSpace,
            display: nil,
            store: store
        )
        let styled = appState.renderer.settingsIcon(forSpace: 0, display: nil)
        #expect(pixels(styled) != pixels(plain))
    }

    @Test("shared labels show through on displays without an override")
    func sharedLabelShowsThroughOnDisplays() {
        let appState = makeAppState()
        let plain = appState.renderer.settingsIcon(forSpace: 2, display: "Main")
        SpacePreferences.setLabel("S{#}", forSpace: 2, display: nil, store: store)
        let labeled = appState.renderer.settingsIcon(forSpace: 2, display: "Main")
        #expect(labeled.size.width > plain.size.width)

        // An empty override is the "no label" sentinel and suppresses the
        // shared label on that display alone
        SpacePreferences.setLabel("", forSpace: 2, display: "Main", store: store)
        let suppressed = appState.renderer.settingsIcon(forSpace: 2, display: "Main")
        #expect(suppressed.size.width == plain.size.width)
    }

    @Test("the scale override multiplies the rendered size")
    func scaleOverride() {
        let appState = makeAppState()
        let base = appState.renderer.settingsIcon(forSpace: 1, display: "Main")
        let enlarged = appState.renderer.settingsIcon(forSpace: 1, display: "Main", sizeScale: 300)
        #expect(enlarged.size.width == base.size.width * 3)
        #expect(enlarged.size.height == base.size.height * 3)
    }
}
