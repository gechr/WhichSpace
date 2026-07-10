import Foundation

/// Classifies system signals by the work needed to reflect them in the UI.
enum SpaceUpdateReason: Equatable, Sendable {
    case activeSpace
    case fallback
    case topology
    case windowMembership
}

/// Coalesces overlapping system signals without discarding their meaning.
@MainActor
final class SpaceUpdateCoordinator {
    private let debounceInterval: Duration
    private let onSnapshotUpdate: @MainActor () -> Void
    private let onWindowOccupancyUpdate: @MainActor () -> Void
    private var pendingSnapshotTask: Task<Void, Never>?

    init(
        debounceInterval: Duration = .milliseconds(50),
        onSnapshotUpdate: @escaping @MainActor () -> Void,
        onWindowOccupancyUpdate: @escaping @MainActor () -> Void
    ) {
        self.debounceInterval = debounceInterval
        self.onSnapshotUpdate = onSnapshotUpdate
        self.onWindowOccupancyUpdate = onWindowOccupancyUpdate
    }

    func handle(_ reason: SpaceUpdateReason) {
        switch reason {
        case .activeSpace, .fallback:
            scheduleSnapshotUpdate(applyLeadingEdge: true)
        case .topology:
            scheduleSnapshotUpdate(applyLeadingEdge: false)
        case .windowMembership:
            onWindowOccupancyUpdate()
        }
    }

    func cancel() {
        pendingSnapshotTask?.cancel()
        pendingSnapshotTask = nil
    }

    private func scheduleSnapshotUpdate(applyLeadingEdge: Bool) {
        if applyLeadingEdge, pendingSnapshotTask == nil {
            onSnapshotUpdate()
        }

        pendingSnapshotTask?.cancel()
        pendingSnapshotTask = Task { [weak self, debounceInterval] in
            try? await Task.sleep(for: debounceInterval)
            guard !Task.isCancelled, let self else {
                return
            }
            onSnapshotUpdate()
            pendingSnapshotTask = nil
        }
    }
}
