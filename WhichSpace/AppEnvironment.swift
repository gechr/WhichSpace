/// Composition root that centralises the creation and ownership of
/// the app's core dependencies.
@MainActor
struct AppEnvironment {
    let appState: AppState
    let store: DefaultsStore

    static let shared: AppEnvironment = {
        let store = DefaultsStore(suite: .standard)
        let appState = if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil {
            // Running as a test host — use a no-op provider to avoid blocking
            // on private CGS/SLS APIs that require a window server connection.
            AppState(
                displaySpaceProvider: NullDisplaySpaceProvider(),
                skipObservers: true,
                store: store
            )
        } else {
            AppState(store: store)
        }
        return Self(appState: appState, store: store)
    }()
}
