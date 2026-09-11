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

    /// Sets `showInDock`. Turning the Dock tile off also restores the status
    /// item, so the app is never left without a visible surface.
    static func setShowInDock(_ value: Bool, store: DefaultsStore) {
        store.showInDock = value
        if !value {
            store.hideMenuBarIcon = false
        }
    }

    /// Sets `hideMenuBarIcon`, which only takes effect while the Dock tile
    /// is shown; without it the status item is the only way to reach the app.
    static func setHideMenuBarIcon(_ value: Bool, store: DefaultsStore) {
        store.hideMenuBarIcon = value && store.showInDock
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
