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
    @ObservationIgnored private let isProcessTrusted: () -> Bool
    @ObservationIgnored private let isCapabilityTrusted: () -> Bool
    @ObservationIgnored private let onClassicSwitchingDisabled: () -> Void
    @ObservationIgnored private var observationTask: Task<Void, Never>?

    init(
        store: DefaultsStore,
        launchAtLogin: LaunchAtLoginProvider,
        isProcessTrusted: @escaping () -> Bool = { Accessibility.isTrusted },
        isCapabilityTrusted: @escaping () -> Bool = { Accessibility.liveStatus.capabilityTrusted },
        onClassicSwitchingDisabled: @escaping () -> Void = {}
    ) {
        self.store = store
        self.launchAtLogin = launchAtLogin
        self.isProcessTrusted = isProcessTrusted
        self.isCapabilityTrusted = isCapabilityTrusted
        self.onClassicSwitchingDisabled = onClassicSwitchingDisabled
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

    /// A tick-registered read for pane code that derives row enablement from
    /// other settings.
    func value<V>(_ keyPath: KeyPath<DefaultsStore, V>) -> V {
        _ = tick
        return store[keyPath: keyPath]
    }

    /// `showAllSpaces` and `showAllDisplays` route through their
    /// `SettingsConstraints` setters so any future coupling between the two
    /// keys applies to writes from the panes.
    var showAllSpacesBinding: Binding<Bool> {
        Binding(
            get: { [self] in
                _ = tick
                return store.showAllSpaces
            },
            set: { [self] in
                SettingsConstraints.setShowAllSpaces($0, store: store)
                tick += 1
            }
        )
    }

    var showAllDisplaysBinding: Binding<Bool> {
        Binding(
            get: { [self] in
                _ = tick
                return store.showAllDisplays
            },
            set: { [self] in
                SettingsConstraints.setShowAllDisplays($0, store: store)
                tick += 1
            }
        )
    }

    /// Presents the two-case display-order preference as a switch: enabled
    /// uses the physical left-to-right arrangement; disabled follows macOS.
    var physicalDisplayOrderBinding: Binding<Bool> {
        Binding(
            get: { [self] in
                _ = tick
                return store.displayOrder == .physical
            },
            set: { [self] in
                store.displayOrder = $0 ? .physical : .system
                tick += 1
            }
        )
    }

    /// Whether accessibility permission is currently granted. Reading `tick`
    /// first lets `requestAccessibility` refresh dependent UI on a grant.
    /// The trust flag freezes at its launch value on external changes, so the
    /// live capability reading is folded in to notice a mid-session revoke.
    var accessibilityGranted: Bool {
        _ = tick
        // Both reads must happen unconditionally: the capability closure
        // reads an observable, and short-circuiting past it would leave the
        // pane with no observation dependency, stranding a visible banner
        // when a re-grant lands
        let trusted = isProcessTrusted()
        let capability = isCapabilityTrusted()
        return trusted && capability
    }

    /// Whether permission was revoked while the app runs: the launch-frozen
    /// trust flag still reads trusted but the live capability is gone. The
    /// banner then deep-links System Settings; the reset-and-prompt flow is
    /// reserved for the never-granted state, so a probe false negative can
    /// never trigger a reset that wipes a real grant.
    var accessibilityRevoked: Bool {
        _ = tick
        // Unconditional reads for the same observation-dependency reason as
        // accessibilityGranted
        let trusted = isProcessTrusted()
        let capability = isCapabilityTrusted()
        return trusted && !capability
    }

    /// A binding for `clickToSwitchSpaces` - the write persists even without
    /// accessibility permission.
    var clickToSwitchSpacesBinding: Binding<Bool> {
        Binding(
            get: { [self] in
                _ = tick
                return store.clickToSwitchSpaces
            },
            set: { [self] in
                SettingsConstraints.setClickToSwitchSpaces($0, store: store)
                tick += 1
            }
        )
    }

    /// Rechecks the macOS 27 instant-switching prerequisite as soon as the
    /// user leaves Classic Switching. The injected action is a no-op on
    /// earlier macOS releases.
    var classicSpaceSwitchingBinding: Binding<Bool> {
        Binding(
            get: { [self] in
                _ = tick
                return store.classicSpaceSwitching
            },
            set: { [self] in
                store.classicSpaceSwitching = $0
                tick += 1
                if !$0 {
                    onClassicSwitchingDisabled()
                }
            }
        )
    }

    /// A binding for a scroll-switching axis; same contract as
    /// `clickToSwitchSpacesBinding`.
    func scrollSwitchingBinding(axis: ReferenceWritableKeyPath<DefaultsStore, Bool>) -> Binding<Bool> {
        Binding(
            get: { [self] in
                _ = tick
                return store[keyPath: axis]
            },
            set: { [self] in
                SettingsConstraints.setScrollSwitching($0, axis: axis, store: store)
                tick += 1
            }
        )
    }

    /// The haptic slider position: 0 when feedback is off, else the stored
    /// intensity. Writing 0 disables feedback but preserves the last
    /// intensity, so re-enabling restores the previous strength.
    var scrollHapticIntensityBinding: Binding<Double> {
        Binding(
            get: { [self] in
                _ = tick
                return store.scrollHapticFeedback ? Double(store.scrollHapticIntensity) : 0
            },
            set: { [self] in
                let intensity = Int($0)
                store.scrollHapticFeedback = intensity > 0
                if intensity > 0 {
                    store.scrollHapticIntensity = intensity
                }
                tick += 1
            }
        )
    }

    /// Prompts for accessibility permission; the tick bump on grant clears
    /// the permission banner and re-enables gated toggles live.
    func requestAccessibility() {
        Accessibility.requestPermission { [weak self] in
            self?.tick += 1
        }
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
        // Changes can land while the window is closed and observation is
        // stopped, so reads start from the suite rather than the memo
        store.invalidateCachedValues()
        // A revoke can also land while the window is closed, between the
        // watch's sparse backstop polls, so the banner probes on open and
        // the watch polls closely while the window shows it
        Accessibility.isSettingsWindowOpen = true
        Accessibility.refreshCapabilityIfWatching()
        tick += 1
        let keys = store.allKeys
        observationTask = Task { [weak self] in
            for await _ in Defaults.updates(keys, initial: false) {
                // Drop the memo cache so the re-render reads the new values
                self?.store.invalidateCachedValues()
                self?.tick += 1
            }
        }
    }

    func stopObserving() {
        observationTask?.cancel()
        observationTask = nil
        Accessibility.isSettingsWindowOpen = false
    }
}
