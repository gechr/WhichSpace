import Foundation
@testable import WhichSpace

/// Stub implementation of DisplaySpaceProviding for testing
final class CGSStub: DisplaySpaceProviding {
    var displays: [NSDictionary] = []
    var activeDisplayIdentifier: String?
    var spacesWithWindowsSet: Set<Int> = []

    // swiftlint:disable:next discouraged_optional_collection
    func copyManagedDisplaySpaces() -> [NSDictionary]? {
        displays.isEmpty ? nil : displays
    }

    func copyActiveMenuBarDisplayIdentifier() -> String? {
        activeDisplayIdentifier
    }

    func spacesWithWindows(forSpaceIDs spaceIDs: [Int]) -> Set<Int> {
        spacesWithWindowsSet.intersection(spaceIDs)
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
