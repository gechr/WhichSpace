import Foundation
@testable import WhichSpace

/// Stub implementation of DisplaySpaceProvider for testing
final class CGSStub: DisplaySpaceProvider, @unchecked Sendable {
    private let lock = NSLock()
    private var fullscreenOwnerPIDsCalls = 0
    private var fullscreenOwnerPIDsValue: [Int: pid_t] = [:]
    private var mainThreadSpacesWithWindowsCalls = 0
    private var spacesWithWindowsCalls = 0
    private var spacesWithWindowsSemaphore: DispatchSemaphore?
    private var spacesWithWindowsValue: Set<Int> = []
    private var windowOwnerPIDsCalls = 0
    private var windowOwnerPIDsValue: [Int: [pid_t]] = [:]

    var displays: [NSDictionary] = []
    var activeDisplayIdentifier: String?
    var displayBoundsMap: [String: CGRect] = [:]

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

    func displayBounds(forIdentifier identifier: String) -> CGRect? {
        displayBoundsMap[identifier]
    }

    var fullscreenOwnerPIDsMap: [Int: pid_t] {
        get { withLock { fullscreenOwnerPIDsValue } }
        set { withLock { fullscreenOwnerPIDsValue = newValue } }
    }

    var fullscreenOwnerPIDsCallCount: Int {
        withLock { fullscreenOwnerPIDsCalls }
    }

    func fullscreenOwnerPIDs(forSpaceIDs spaceIDs: [Int]) -> [Int: pid_t] {
        withLock {
            fullscreenOwnerPIDsCalls += 1
            return fullscreenOwnerPIDsValue.filter { spaceIDs.contains($0.key) }
        }
    }

    var windowOwnerPIDsMap: [Int: [pid_t]] {
        get { withLock { windowOwnerPIDsValue } }
        set { withLock { windowOwnerPIDsValue = newValue } }
    }

    var windowOwnerPIDsCallCount: Int {
        withLock { windowOwnerPIDsCalls }
    }

    func windowOwnerPIDs(forSpaceIDs spaceIDs: [Int]) -> [Int: [pid_t]] {
        withLock {
            windowOwnerPIDsCalls += 1
            return windowOwnerPIDsValue.filter { spaceIDs.contains($0.key) }
        }
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
        makeDisplay(
            displayID: displayID,
            uuidSpaces: spaces.map { (id: $0.id, uuid: nil, isFullscreen: $0.isFullscreen) },
            activeSpaceID: activeSpaceID
        )
    }

    /// Creates display data whose spaces carry CGS Space UUIDs, for tests
    /// exercising order tracking. A nil uuid omits the key, matching CGS
    /// data that lacks one. The distinct label keeps `spaces: []` calls
    /// unambiguous.
    static func makeDisplay(
        displayID: String,
        uuidSpaces: [(id: Int, uuid: String?, isFullscreen: Bool)],
        activeSpaceID: Int
    ) -> NSDictionary {
        let spaceDicts: [[String: Any]] = uuidSpaces.map { space in
            var dict: [String: Any] = ["ManagedSpaceID": space.id]
            if let uuid = space.uuid {
                dict["uuid"] = uuid
            }
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
