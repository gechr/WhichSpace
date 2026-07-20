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

    /// Attempts to set `clickToSwitchSpaces`.
    ///
    /// When enabling, returns `false` if accessibility permission is not granted
    /// (the caller is responsible for showing any UI prompt). Disabling always
    /// succeeds. The trust check is injectable so tests don't depend on the
    /// host process's actual TCC state.
    @discardableResult
    static func setClickToSwitchSpaces(
        _ value: Bool,
        store: DefaultsStore,
        isProcessTrusted: () -> Bool = { Accessibility.isTrusted }
    ) -> Bool {
        if value, !isProcessTrusted() {
            return false
        }
        store.clickToSwitchSpaces = value
        return true
    }

    /// Attempts to set a scroll-to-switch axis (`horizontalScrollEnabled` or
    /// `verticalScrollEnabled`). Same contract as `setClickToSwitchSpaces`:
    /// enabling requires accessibility permission, disabling always succeeds.
    @discardableResult
    static func setScrollSwitching(
        _ value: Bool,
        axis: ReferenceWritableKeyPath<DefaultsStore, Bool>,
        store: DefaultsStore,
        isProcessTrusted: () -> Bool = { Accessibility.isTrusted }
    ) -> Bool {
        if value, !isProcessTrusted() {
            return false
        }
        store[keyPath: axis] = value
        return true
    }
}
