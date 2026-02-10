import AppKit

/// Enforces mutual-exclusion invariants between settings.
///
/// Both `ActionHandler` (menu toggles) and `SettingsView` (SwiftUI bindings)
/// route through these methods so the invariants are enforced in one place.
@MainActor
enum SettingsConstraints {
    /// Sets `showAllSpaces`, disabling `showAllDisplays` when enabling.
    static func setShowAllSpaces(_ value: Bool, store: DefaultsStore) {
        store.showAllSpaces = value
        if value {
            store.showAllDisplays = false
        }
    }

    /// Sets `showAllDisplays`, disabling `showAllSpaces` when enabling.
    static func setShowAllDisplays(_ value: Bool, store: DefaultsStore) {
        store.showAllDisplays = value
        if value {
            store.showAllSpaces = false
        }
    }

    /// Attempts to set `clickToSwitchSpaces`.
    ///
    /// When enabling, returns `false` if accessibility permission is not granted
    /// (the caller is responsible for showing any UI prompt). Disabling always succeeds.
    @discardableResult
    static func setClickToSwitchSpaces(_ value: Bool, store: DefaultsStore) -> Bool {
        if value, !AXIsProcessTrusted() {
            return false
        }
        store.clickToSwitchSpaces = value
        return true
    }
}
