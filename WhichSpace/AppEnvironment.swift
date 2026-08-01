import Foundation

/// Composition root that centralises the creation and ownership of
/// the app's core dependencies.
///
/// Production code accesses dependencies via `AppEnvironment.shared`. Tests
/// never touch `.shared`; they construct `AppState` / `AppDelegate` directly
/// with stub providers and per-test `DefaultsStore` suites, so production
/// bootstrap remains free of test-detection branches.
@MainActor
struct AppEnvironment {
    let appState: AppState
    let store: DefaultsStore

    static let shared: AppEnvironment = {
        let store = DefaultsStore(suite: .standard)
        // Runs before AppState builds its first snapshot, so no icon is ever
        // rendered from unmigrated preferences. The snapshot is written at
        // most once even when both migrations run.
        var snapshotTaken = false
        let snapshot = {
            guard !snapshotTaken else {
                return
            }
            snapshotTaken = true
            Self.writePreMigrationBackup(store: store)
        }
        SpacePreferences.migrateStampedTemplateCopies(store: store, snapshot: snapshot)
        SpacePreferences.migrateDisplayScopeOverrides(store: store, snapshot: snapshot)
        return Self(appState: AppState(store: store), store: store)
    }()

    /// Best-effort safety net: the migration only removes per-space values
    /// proven identical to the default style template, but keep a snapshot
    /// in Application Support in case a report proves that wrong.
    private static func writePreMigrationBackup(store: DefaultsStore) {
        guard let json = try? BackupManager.encode(store: store),
              let support = FileManager.default.urls(
                  for: .applicationSupportDirectory, in: .userDomainMask
              ).first
        else {
            return
        }
        let directory = support.appendingPathComponent("WhichSpace", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try? json.write(
            to: directory.appendingPathComponent("PreMigrationBackup.json"),
            atomically: true,
            encoding: .utf8
        )
    }
}
