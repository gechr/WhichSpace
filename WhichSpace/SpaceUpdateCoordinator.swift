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
    /// Whether the pending debounce already applied a leading snapshot. A
    /// topology event schedules a trailing task without applying, so the task
    /// alone can't tell an active Space event that its leading edge is due.
    private var pendingSnapshotAppliedLeadingEdge = false
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
        pendingSnapshotAppliedLeadingEdge = false
    }

    private func scheduleSnapshotUpdate(applyLeadingEdge: Bool) {
        if applyLeadingEdge, !pendingSnapshotAppliedLeadingEdge {
            onSnapshotUpdate()
            pendingSnapshotAppliedLeadingEdge = true
        }

        pendingSnapshotTask?.cancel()
        pendingSnapshotTask = Task { [weak self, debounceInterval] in
            try? await Task.sleep(for: debounceInterval)
            guard !Task.isCancelled, let self else {
                return
            }
            // Clear before applying so a re-entrant handle() schedules a fresh
            // debounce instead of having its task reference clobbered here
            pendingSnapshotTask = nil
            pendingSnapshotAppliedLeadingEdge = false
            onSnapshotUpdate()
        }
    }
}
