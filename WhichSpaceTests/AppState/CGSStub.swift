import Foundation
@testable import WhichSpace

/// Stub implementation of DisplaySpaceProvider for testing
final class CGSStub: DisplaySpaceProvider, @unchecked Sendable {
    private let lock = NSLock()
    private var mainThreadSpacesWithWindowsCalls = 0
    private var spacesWithWindowsCalls = 0
    private var spacesWithWindowsSemaphore: DispatchSemaphore?
    private var spacesWithWindowsValue: Set<Int> = []

    var displays: [NSDictionary] = []
    var activeDisplayIdentifier: String?

    var spacesWithWindowsSet: Set<Int> {
        get { withLock { spacesWithWindowsValue } }
        set { withLock { spacesWithWindowsValue = newValue } }
    }

    var spacesWithWindowsCallCount: Int {
        withLock { spacesWithWindowsCalls }
    }

    var spacesWithWindowsBlocker: DispatchSemaphore? {
        get { withLock { spacesWithWindowsSemaphore } }
        set { withLock { spacesWithWindowsSemaphore = newValue } }
    }

    var mainThreadSpacesWithWindowsCallCount: Int {
        withLock { mainThreadSpacesWithWindowsCalls }
    }

    // swiftlint:disable:next discouraged_optional_collection
    func copyManagedDisplaySpaces() -> [NSDictionary]? {
        displays.isEmpty ? nil : displays
    }

    func copyActiveMenuBarDisplayIdentifier() -> String? {
        activeDisplayIdentifier
    }

    func spacesWithWindows(forSpaceIDs spaceIDs: [Int]) -> Set<Int> {
        let (spaces, blocker) = withLock {
            spacesWithWindowsCalls += 1
            if Thread.isMainThread {
                mainThreadSpacesWithWindowsCalls += 1
            }
            return (spacesWithWindowsValue.intersection(spaceIDs), spacesWithWindowsSemaphore)
        }
        blocker?.wait()
        return spaces
    }

    private func withLock<Result>(_ operation: () -> Result) -> Result {
        lock.lock()
        defer { lock.unlock() }
        return operation()
    }

    // MARK: - Builder Helpers

    /// Creates display data with the specified spaces
    /// - Parameters:
    ///   - displayID: The display identifier
    ///   - spaces: Array of space configs (id, isFullscreen)
    ///   - activeSpaceID: The ID of the currently active space
    /// - Returns: An NSDictionary matching CGS format
    static func makeDisplay(
        displayID: String,
        spaces: [(id: Int, isFullscreen: Bool)],
        activeSpaceID: Int
    ) -> NSDictionary {
        let spaceDicts: [[String: Any]] = spaces.map { space in
            var dict: [String: Any] = ["ManagedSpaceID": space.id]
            if space.isFullscreen {
                dict["TileLayoutManager"] = ["SomeKey": "SomeValue"]
            }
            return dict
        }

        let currentSpace: [String: Any] = ["ManagedSpaceID": activeSpaceID]

        return [
            "Display Identifier": displayID,
            "Spaces": spaceDicts,
            "Current Space": currentSpace,
        ] as NSDictionary
    }
}
