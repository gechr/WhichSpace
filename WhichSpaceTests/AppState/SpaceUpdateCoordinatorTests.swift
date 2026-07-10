import Testing
@testable import WhichSpace

@MainActor
struct SpaceUpdateCoordinatorTests {
    @Test("active Space bursts apply leading and trailing snapshots")
    func activeSpaceBurst_appliesLeadingAndTrailingSnapshots() async {
        var snapshotUpdates = 0
        let coordinator = SpaceUpdateCoordinator(
            debounceInterval: .milliseconds(20),
            onSnapshotUpdate: { snapshotUpdates += 1 },
            onWindowOccupancyUpdate: {}
        )
        defer { coordinator.cancel() }

        coordinator.handle(.activeSpace)
        coordinator.handle(.activeSpace)
        coordinator.handle(.activeSpace)

        #expect(snapshotUpdates == 1)
        try? await Task.sleep(for: .milliseconds(60))
        #expect(snapshotUpdates == 2)
    }

    @Test("topology bursts wait for one settled snapshot")
    func topologyBurst_appliesOneTrailingSnapshot() async {
        var snapshotUpdates = 0
        let coordinator = SpaceUpdateCoordinator(
            debounceInterval: .milliseconds(20),
            onSnapshotUpdate: { snapshotUpdates += 1 },
            onWindowOccupancyUpdate: {}
        )
        defer { coordinator.cancel() }

        coordinator.handle(.topology)
        coordinator.handle(.topology)

        #expect(snapshotUpdates == 0)
        try? await Task.sleep(for: .milliseconds(60))
        #expect(snapshotUpdates == 1)
    }

    @Test("window membership bypasses snapshot rebuilding")
    func windowMembership_refreshesOnlyOccupancy() async {
        var occupancyUpdates = 0
        var snapshotUpdates = 0
        let coordinator = SpaceUpdateCoordinator(
            debounceInterval: .milliseconds(20),
            onSnapshotUpdate: { snapshotUpdates += 1 },
            onWindowOccupancyUpdate: { occupancyUpdates += 1 }
        )
        defer { coordinator.cancel() }

        coordinator.handle(.windowMembership)

        #expect(occupancyUpdates == 1)
        try? await Task.sleep(for: .milliseconds(40))
        #expect(snapshotUpdates == 0)
    }

    @Test("WindowServer events map to focused update reasons")
    func windowServerEvents_mapToUpdateReasons() {
        for event in [UInt32(1329), 1401] {
            #expect(SpaceChangeNotifier.reason(forEvent: event) == .activeSpace)
        }
        for event in [UInt32(818), 828, 1322] {
            #expect(SpaceChangeNotifier.reason(forEvent: event) == .topology)
        }
        for event in [UInt32(1325), 1326, 1327, 1328] {
            #expect(SpaceChangeNotifier.reason(forEvent: event) == .windowMembership)
        }
        #expect(SpaceChangeNotifier.reason(forEvent: 0) == nil)
    }
}
