import AppKit

/// Applies settings that require shared validation or side effects.
@MainActor
enum SettingsConstraints {
    /// Sets `showAllSpaces` independently of `showAllDisplays`.
    static func setShowAllSpaces(_ value: Bool, store: DefaultsStore) {
        store.showAllSpaces = value
    }

    /// Sets `showAllDisplays` independently of `showAllSpaces`.
    static func setShowAllDisplays(_ value: Bool, store: DefaultsStore) {
        store.showAllDisplays = value
    }

    /// Sets `clickToSwitchSpaces` - switching paths gate on permission at use
    /// time.
    static func setClickToSwitchSpaces(_ value: Bool, store: DefaultsStore) {
        store.clickToSwitchSpaces = value
    }

    /// Sets a scroll-to-switch axis (`horizontalScrollEnabled` or
    /// `verticalScrollEnabled`). Same contract as `setClickToSwitchSpaces`.
    static func setScrollSwitching(
        _ value: Bool,
        axis: ReferenceWritableKeyPath<DefaultsStore, Bool>,
        store: DefaultsStore
    ) {
        store[keyPath: axis] = value
    }
}
