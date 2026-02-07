import Foundation

/// Builds immutable SpaceSnapshot values from system display/space data.
///
/// Extracted from AppState to separate snapshot building/parsing concerns from state management.
/// Pure function: takes a DisplaySpaceProvider + preferences, returns a SpaceSnapshot.
enum SpaceSnapshotService {
    private static let mainDisplay = "Main"

    /// Builds an immutable snapshot of the current space state from system data
    static func buildSnapshot(
        provider: DisplaySpaceProvider,
        localSpaceNumbers: Bool
    ) -> SpaceSnapshot {
        guard let displays = provider.copyManagedDisplaySpaces(),
              let activeDisplay = provider.copyActiveMenuBarDisplayIdentifier()
        else {
            return .empty
        }

        // Collect space info from ALL displays
        var allDisplays: [DisplaySpaceInfo] = []

        for display in displays {
            guard let spaces = display["Spaces"] as? [[String: Any]],
                  let displayID = display["Display Identifier"] as? String
            else {
                continue
            }

            var regularSpaceIndex = 0
            var spaceLabels: [String] = []
            var spaceIDs: [Int] = []

            for space in spaces {
                guard let spaceID = space["ManagedSpaceID"] as? Int else {
                    continue
                }

                let isFullscreen = space["TileLayoutManager"] is [String: Any]
                let label: String
                if isFullscreen {
                    label = Labels.fullscreen
                } else {
                    regularSpaceIndex += 1
                    label = String(regularSpaceIndex)
                }

                spaceLabels.append(label)
                spaceIDs.append(spaceID)
            }

            if !spaceLabels.isEmpty {
                allDisplays.append(DisplaySpaceInfo(
                    displayID: displayID,
                    labels: spaceLabels,
                    spaceIDs: spaceIDs,
                    regularSpaceCount: regularSpaceIndex
                ))
            }
        }

        // Calculate global start indices
        var globalIndex = 1
        for index in 0 ..< allDisplays.count {
            allDisplays[index].globalStartIndex = globalIndex
            globalIndex += allDisplays[index].regularSpaceCount
        }

        // Find the active display - prefer activeDisplay, fall back to mainDisplay
        let targetDisplayID = allDisplays.contains { $0.displayID == activeDisplay }
            ? activeDisplay
            : mainDisplay

        // Find current space info from the active display
        for display in displays {
            guard let current = display["Current Space"] as? [String: Any],
                  let spaces = display["Spaces"] as? [[String: Any]],
                  let displayID = display["Display Identifier"] as? String,
                  displayID == targetDisplayID,
                  let activeSpaceID = current["ManagedSpaceID"] as? Int
            else {
                continue
            }

            var regularSpaceIndex = 0
            var spaceLabels: [String] = []
            var spaceIDs: [Int] = []
            var snapshotCurrentSpace = 0
            var snapshotCurrentSpaceID = 0
            var snapshotCurrentSpaceLabel = "?"
            var snapshotGlobalSpaceIndex = 0

            for space in spaces {
                guard let spaceID = space["ManagedSpaceID"] as? Int else {
                    continue
                }

                let isFullscreen = space["TileLayoutManager"] is [String: Any]
                let label: String
                if isFullscreen {
                    label = Labels.fullscreen
                } else {
                    regularSpaceIndex += 1
                    label = String(regularSpaceIndex)
                }

                spaceLabels.append(label)
                spaceIDs.append(spaceID)

                if spaceID == activeSpaceID {
                    let activeIndex = spaceLabels.count
                    snapshotCurrentSpace = activeIndex
                    snapshotCurrentSpaceID = spaceID

                    // Calculate global space index
                    if let displayInfo = allDisplays.first(where: { $0.displayID == displayID }) {
                        let regularPosition = max(regularSpaceIndex, 1)
                        if isFullscreen {
                            snapshotGlobalSpaceIndex = displayInfo.globalStartIndex + max(regularPosition - 1, 0)
                        } else {
                            snapshotGlobalSpaceIndex = displayInfo.globalStartIndex + regularPosition - 1
                        }
                    } else {
                        snapshotGlobalSpaceIndex = activeIndex
                    }

                    // Use local or global numbering based on preference
                    if !isFullscreen, !localSpaceNumbers {
                        snapshotCurrentSpaceLabel = String(snapshotGlobalSpaceIndex)
                    } else {
                        snapshotCurrentSpaceLabel = label
                    }
                }
            }

            return SpaceSnapshot(
                allDisplaysSpaceInfo: allDisplays,
                allSpaceIDs: spaceIDs,
                allSpaceLabels: spaceLabels,
                currentDisplayID: displayID,
                currentGlobalSpaceIndex: snapshotGlobalSpaceIndex,
                currentSpace: snapshotCurrentSpace,
                currentSpaceID: snapshotCurrentSpaceID,
                currentSpaceLabel: snapshotCurrentSpaceLabel
            )
        }

        return .empty
    }
}
