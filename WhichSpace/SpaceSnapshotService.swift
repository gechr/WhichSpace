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
            NSLog("SpaceSnapshotService: CGS display/space data unavailable; returning empty snapshot")
            return .empty
        }

        // Collect space info from ALL displays
        var parsedDisplays: [(displayID: String, entries: [SpaceEntry], regularSpaceCount: Int)] = []

        for display in displays {
            guard let spaces = display["Spaces"] as? [[String: Any]],
                  let displayID = display["Display Identifier"] as? String
            else {
                NSLog("SpaceSnapshotService: display entry missing 'Spaces' or 'Display Identifier'; skipping")
                continue
            }

            var regularSpaceIndex = 0
            var entries: [SpaceEntry] = []

            for space in spaces {
                guard let spaceID = space["ManagedSpaceID"] as? Int else {
                    NSLog("SpaceSnapshotService: space entry missing 'ManagedSpaceID'; skipping")
                    continue
                }

                let isFullscreen = space["TileLayoutManager"] is [String: Any]
                let label: String
                let regularIndex: Int?
                if isFullscreen {
                    label = Labels.fullscreen
                    regularIndex = nil
                } else {
                    regularSpaceIndex += 1
                    label = String(regularSpaceIndex)
                    regularIndex = regularSpaceIndex
                }

                entries.append(SpaceEntry(id: spaceID, label: label, regularIndex: regularIndex))
            }

            if !entries.isEmpty {
                parsedDisplays.append((displayID: displayID, entries: entries, regularSpaceCount: regularSpaceIndex))
            }
        }

        // Build DisplaySpaceInfo with computed globalStartIndex
        var allDisplays: [DisplaySpaceInfo] = []
        var globalIndex = 1
        for parsed in parsedDisplays {
            allDisplays.append(DisplaySpaceInfo(
                displayID: parsed.displayID,
                entries: parsed.entries,
                globalStartIndex: globalIndex,
                regularSpaceCount: parsed.regularSpaceCount
            ))
            globalIndex += parsed.regularSpaceCount
        }

        // Find the active display - prefer activeDisplay, fall back to mainDisplay
        let targetDisplayID = allDisplays.contains { $0.displayID == activeDisplay }
            ? activeDisplay
            : mainDisplay

        // Find current space info from the active display
        guard let activeDisplayInfo = allDisplays.first(where: { $0.displayID == targetDisplayID }) else {
            return .empty
        }

        for display in displays {
            guard let current = display["Current Space"] as? [String: Any],
                  let displayID = display["Display Identifier"] as? String,
                  displayID == targetDisplayID,
                  let activeSpaceID = current["ManagedSpaceID"] as? Int
            else {
                // Only log when display data is structurally invalid (not just wrong displayID)
                if display["Current Space"] == nil || display["Display Identifier"] == nil {
                    NSLog("SpaceSnapshotService: active display entry missing required keys; skipping")
                }
                continue
            }

            var snapshotCurrentSpace = 0
            var snapshotCurrentSpaceID = 0
            var snapshotCurrentSpaceLabel = "?"
            var snapshotGlobalSpaceIndex = 0

            for (arrayIndex, entry) in activeDisplayInfo.entries.enumerated() where entry.id == activeSpaceID {
                let activeIndex = arrayIndex + 1
                snapshotCurrentSpace = activeIndex
                snapshotCurrentSpaceID = entry.id

                // Calculate global space index
                let regularPosition = max(entry.regularIndex ?? 0, 1)
                if entry.regularIndex == nil {
                    snapshotGlobalSpaceIndex = activeDisplayInfo.globalStartIndex + max(regularPosition - 1, 0)
                } else {
                    snapshotGlobalSpaceIndex = activeDisplayInfo.globalStartIndex + regularPosition - 1
                }

                // Use local or global numbering based on preference
                if entry.regularIndex != nil, !localSpaceNumbers {
                    snapshotCurrentSpaceLabel = String(snapshotGlobalSpaceIndex)
                } else {
                    snapshotCurrentSpaceLabel = entry.label
                }
            }

            return SpaceSnapshot(
                allDisplaysSpaceInfo: allDisplays,
                allSpaceEntries: activeDisplayInfo.entries,
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
