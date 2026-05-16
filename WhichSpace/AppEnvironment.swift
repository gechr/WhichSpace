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
        return Self(appState: AppState(store: store), store: store)
    }()
}
