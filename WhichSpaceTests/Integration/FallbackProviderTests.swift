import Testing
@testable import WhichSpace

@Suite("Fallback Provider")
@MainActor
struct FallbackProviderTests {
    // MARK: - Nil Fallback Behavior

    @Test("copyManagedDisplaySpaces propagates nil when underlying returns nil")
    func copyManagedDisplaySpaces_nilPropagatesNil() {
        let stub = CGSStub()
        let fallback = FallbackDisplaySpaceProvider(wrapping: stub)

        let result = fallback.copyManagedDisplaySpaces()

        #expect(result == nil, "Should propagate nil from underlying provider")
    }

    @Test("copyActiveMenuBarDisplayIdentifier propagates nil when underlying returns nil")
    func copyActiveMenuBarDisplayIdentifier_nilPropagatesNil() {
        let stub = CGSStub()
        let fallback = FallbackDisplaySpaceProvider(wrapping: stub)

        let result = fallback.copyActiveMenuBarDisplayIdentifier()

        #expect(result == nil, "Should propagate nil from underlying provider")
    }

    // MARK: - Pass-through Behavior

    @Test("copyManagedDisplaySpaces passes through non-nil results")
    func copyManagedDisplaySpaces_passesThroughNonNilResults() {
        let stub = CGSStub()
        stub.displays = [
            CGSStub.makeDisplay(
                displayID: "Main",
                spaces: [(id: 100, isFullscreen: false)],
                activeSpaceID: 100
            ),
        ]
        let fallback = FallbackDisplaySpaceProvider(wrapping: stub)

        let result = fallback.copyManagedDisplaySpaces()

        #expect(result?.count == 1, "Should pass through non-nil results unchanged")
    }

    @Test("copyActiveMenuBarDisplayIdentifier passes through non-nil results")
    func copyActiveMenuBarDisplayIdentifier_passesThroughNonNilResults() {
        let stub = CGSStub()
        stub.activeDisplayIdentifier = "Main"
        let fallback = FallbackDisplaySpaceProvider(wrapping: stub)

        let result = fallback.copyActiveMenuBarDisplayIdentifier()

        #expect(result == "Main", "Should pass through non-nil results unchanged")
    }

    // MARK: - spacesWithWindows Delegation

    @Test("spacesWithWindows delegates correctly")
    func spacesWithWindows_delegatesCorrectly() {
        let stub = CGSStub()
        stub.spacesWithWindowsSet = [100, 101]
        let fallback = FallbackDisplaySpaceProvider(wrapping: stub)

        let result = fallback.spacesWithWindows(forSpaceIDs: [100, 102])

        #expect(result == [100], "Should delegate to wrapped provider and intersect")
    }

    @Test("spacesWithWindows with empty input returns empty")
    func spacesWithWindows_emptyInput_returnsEmpty() {
        let stub = CGSStub()
        stub.spacesWithWindowsSet = [100]
        let fallback = FallbackDisplaySpaceProvider(wrapping: stub)

        let result = fallback.spacesWithWindows(forSpaceIDs: [])

        #expect(result.isEmpty)
    }
}
