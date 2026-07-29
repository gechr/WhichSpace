import AppKit
import Defaults
import SwiftUI

/// Binding layer between the SwiftUI settings panes and `DefaultsStore`.
///
/// Writes go through the store's memoizing subscript, so `mutationCount`
/// bumps and the renderer's icon cache key stays correct; the status bar then
/// refreshes via the existing `Defaults.updates` observers in AppDelegate.
/// Reads register a SwiftUI dependency on `tick`, the sole observable stored
/// property, so panes re-render on any store change - including external ones
/// (AppleScript, `defaults write`, the status menu) while the window is open.
@MainActor
@Observable
final class SettingsModel {
    /// Bumped on every write and on observed external changes; binding
    /// getters read it to register a SwiftUI observation dependency
    private(set) var tick = 0

    @ObservationIgnored private let store: DefaultsStore
    @ObservationIgnored private var launchAtLogin: LaunchAtLoginProvider
    @ObservationIgnored private var observationTask: Task<Void, Never>?

    init(store: DefaultsStore, launchAtLogin: LaunchAtLoginProvider) {
        self.store = store
        self.launchAtLogin = launchAtLogin
    }

    // MARK: - Bindings

    /// A binding for any store property, routed through the memoizing subscript.
    func binding<V>(_ keyPath: ReferenceWritableKeyPath<DefaultsStore, V>) -> Binding<V> {
        Binding(
            get: { [self] in
                _ = tick
                return store[keyPath: keyPath]
            },
            set: { [self] in
                store[keyPath: keyPath] = $0
                tick += 1
            }
        )
    }

    /// Launch at Login is not a store key: it reads SMAppService state live
    /// through the provider, which can change externally in System Settings.
    var launchAtLoginBinding: Binding<Bool> {
        Binding(
            get: { [self] in
                _ = tick
                return launchAtLogin.isEnabled
            },
            set: { [self] in
                launchAtLogin.isEnabled = $0
                tick += 1
            }
        )
    }

    // MARK: - External Change Observation

    /// Starts re-rendering panes on defaults changes made outside this model.
    /// Called when the settings window opens; stopped on close so the stream
    /// does not outlive the window.
    func startObserving() {
        stopObserving()
        let keys = store.allKeys
        observationTask = Task { [weak self] in
            for await _ in Defaults.updates(keys, initial: false) {
                self?.tick += 1
            }
        }
    }

    func stopObserving() {
        observationTask?.cancel()
        observationTask = nil
    }
}
