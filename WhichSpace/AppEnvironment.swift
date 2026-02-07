/// Composition root that centralises the creation and ownership of
/// the app's core dependencies.
///
/// Today it simply wraps the existing singletons so that call-sites
/// can be migrated incrementally.  Once every consumer receives its
/// dependencies via `AppEnvironment`, the `shared` singletons on
/// `AppState` and `DefaultsStore` can be removed.
@MainActor
struct AppEnvironment {
    let appState: AppState
    let store: DefaultsStore

    static let shared = Self(
        appState: .shared,
        store: .shared
    )
}
