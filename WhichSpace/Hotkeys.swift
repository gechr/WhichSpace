import AppKit
import KeyboardShortcuts

extension KeyboardShortcuts.Name {
    static let switchLeft = Self("switchLeft")
    static let switchRight = Self("switchRight")
    static let switchPrevious = Self("switchPrevious")
    static let sendLeft = Self("sendLeft")
    static let sendRight = Self("sendRight")
    static let moveLeft = Self("moveLeft")
    static let moveRight = Self("moveRight")

    /// One bindable name per numbered Desktop. Positions past the current
    /// Desktop count stay recorded but inert, so a binding survives the
    /// Desktop it targets being removed and re-added.
    static let jumpToSpace: [Self] = (1 ... HotkeyCenter.maxJumpTargets).map {
        Self("switchToSpace\($0)")
    }

    /// Numbered window hotkeys, one send and one move per Desktop, following
    /// the same inert-past-the-count rule as `jumpToSpace`.
    static let sendToSpace: [Self] = (1 ... HotkeyCenter.maxJumpTargets).map {
        Self("sendToSpace\($0)")
    }

    static let moveToSpace: [Self] = (1 ... HotkeyCenter.maxJumpTargets).map {
        Self("moveToSpace\($0)")
    }
}

/// Routes recorded global hotkeys through the shared switching backends.
/// Relative and locally numbered jumps match the scripting surfaces; globally
/// numbered jumps can additionally cross display boundaries.
@MainActor
final class HotkeyCenter {
    /// How many Desktops can carry a direct binding, matching macOS's numbered
    /// Mission Control shortcut range and the per-display Space limit.
    nonisolated static let maxJumpTargets = Layout.maxSpacesPerDisplay

    /// Keep WhichSpace's Carbon registrations out of the way long enough for
    /// a forwarded Mission Control key event to reach macOS instead of
    /// recursively invoking another WhichSpace binding.
    private static let forwardedHotKeySettleDelay: Duration = .milliseconds(20)

    /// Every bindable name, for whole-surface operations like a full reset.
    static var allNames: [KeyboardShortcuts.Name] {
        [.switchLeft, .switchRight, .switchPrevious, .sendLeft, .sendRight, .moveLeft, .moveRight]
            + KeyboardShortcuts.Name.jumpToSpace
            + KeyboardShortcuts.Name.sendToSpace
            + KeyboardShortcuts.Name.moveToSpace
    }

    /// Clears every recorded binding, returning the pane to its fresh state.
    static func resetBindings() {
        KeyboardShortcuts.reset(allNames)
    }

    /// The recorded bindings as name to encoded shortcut, for settings
    /// export. Only recorded names appear, so a fresh install exports none.
    static func exportBindings() -> [String: String] {
        var bindings = [String: String]()
        for name in allNames {
            guard let shortcut = KeyboardShortcuts.getShortcut(for: name),
                  let data = try? JSONEncoder().encode(shortcut),
                  let encoded = String(data: data, encoding: .utf8)
            else {
                continue
            }
            bindings[name.rawValue] = encoded
        }
        return bindings
    }

    /// Replaces every binding with the imported set: names absent from the
    /// backup are cleared, matching how the rest of an import overwrites
    /// current state. Unreadable entries clear their binding rather than
    /// keeping a value the backup meant to change.
    static func importBindings(_ bindings: [String: String]) {
        for name in allNames {
            if let encoded = bindings[name.rawValue],
               let shortcut = try? JSONDecoder().decode(
                   KeyboardShortcuts.Shortcut.self, from: Data(encoded.utf8)
               )
            {
                KeyboardShortcuts.setShortcut(shortcut, for: name)
            } else {
                KeyboardShortcuts.reset(name)
            }
        }
    }

    private let appState: AppState
    private let store: DefaultsStore

    init(appState: AppState, store: DefaultsStore) {
        self.appState = appState
        self.store = store
        // The library calls handlers outside any actor, so each hops to the
        // main actor before touching switching state
        KeyboardShortcuts.onKeyDown(for: .switchRight) { [weak self] in
            Task { @MainActor in
                self?.switchRelative(goRight: true)
            }
        }
        KeyboardShortcuts.onKeyDown(for: .switchLeft) { [weak self] in
            Task { @MainActor in
                self?.switchRelative(goRight: false)
            }
        }
        KeyboardShortcuts.onKeyDown(for: .switchPrevious) { [weak self] in
            Task { @MainActor in
                self?.switchToPrevious()
            }
        }
        // Send leaves you where you are, move follows the window, matching the
        // two verbs the scripting surface uses
        KeyboardShortcuts.onKeyDown(for: .sendLeft) { [weak self] in
            Task { @MainActor in
                self?.moveWindow(goRight: false, follow: false)
            }
        }
        KeyboardShortcuts.onKeyDown(for: .sendRight) { [weak self] in
            Task { @MainActor in
                self?.moveWindow(goRight: true, follow: false)
            }
        }
        KeyboardShortcuts.onKeyDown(for: .moveLeft) { [weak self] in
            Task { @MainActor in
                self?.moveWindow(goRight: false, follow: true)
            }
        }
        KeyboardShortcuts.onKeyDown(for: .moveRight) { [weak self] in
            Task { @MainActor in
                self?.moveWindow(goRight: true, follow: true)
            }
        }
        for (index, name) in KeyboardShortcuts.Name.jumpToSpace.enumerated() {
            KeyboardShortcuts.onKeyDown(for: name) { [weak self] in
                Task { @MainActor in
                    self?.switchTo(number: index + 1)
                }
            }
        }
        for (index, name) in KeyboardShortcuts.Name.sendToSpace.enumerated() {
            KeyboardShortcuts.onKeyDown(for: name) { [weak self] in
                Task { @MainActor in
                    self?.moveWindow(toNumber: index + 1, follow: false)
                }
            }
        }
        for (index, name) in KeyboardShortcuts.Name.moveToSpace.enumerated() {
            KeyboardShortcuts.onKeyDown(for: name) { [weak self] in
                Task { @MainActor in
                    self?.moveWindow(toNumber: index + 1, follow: true)
                }
            }
        }
    }

    /// Whether a press has already triggered the permission flow this launch.
    private var promptedForAccessibility = false
    /// Whether a press has already deep-linked System Settings after a revoke.
    private var openedSettingsForRevocation = false

    /// Every hotkey needs the Accessibility permission to post its events, so
    /// the first press without it starts the grant flow instead of leaving
    /// the binding dead. Later presses stay silent until the grant lands
    /// rather than stacking system dialogs.
    private func ensureAccessibility() -> Bool {
        if AXIsProcessTrusted() {
            guard Accessibility.liveStatus.capabilityTrusted else {
                // Revoked mid-session: the frozen trust flag still reads
                // trusted, so the request flow's tccutil reset must stay
                // unreachable from this state; recover once
                if !openedSettingsForRevocation {
                    openedSettingsForRevocation = true
                    Accessibility.recoverFromRevocation()
                }
                return false
            }
            return true
        }
        if !promptedForAccessibility {
            promptedForAccessibility = true
            Accessibility.requestPermission {}
        }
        return false
    }

    /// Whether the next switch will post Mission Control key events: by
    /// preference, or because a held mouse button forces the classic
    /// fallback in SpaceSwitcher.
    private var switchForwardsKeyEvents: Bool {
        store.classicSpaceSwitching || NSEvent.pressedMouseButtons != 0
    }

    /// Runs a switch action. When the switch forwards Mission Control key
    /// events, the Carbon registrations step aside long enough for them to
    /// reach macOS instead of recursively invoking another binding.
    private func performSwitch(forwardsKeyEvents: Bool, _ action: () -> Void) {
        guard forwardsKeyEvents else {
            action()
            return
        }
        KeyboardShortcuts.disable(Self.allNames)
        action()
        Task { @MainActor in
            try? await Task.sleep(for: Self.forwardedHotKeySettleDelay)
            KeyboardShortcuts.enable(Self.allNames)
        }
    }

    /// Wrapping follows the same preference as scroll switching, so the two
    /// relative surfaces agree about what happens at the edges. Skipping
    /// empty Spaces is a hotkey-only preference: scroll and the scripting
    /// surfaces keep stepping one Space at a time.
    private func switchRelative(goRight: Bool) {
        guard ensureAccessibility() else {
            return
        }
        performSwitch(forwardsKeyEvents: switchForwardsKeyEvents) {
            let skipped = store.hotkeysSkipEmptySpaces ? appState.emptySpaceIDs() : []
            _ = SpaceSwitcher.switchRelative(
                goRight: goRight,
                wrap: store.scrollWrapAround,
                skippingSpaceIDs: skipped
            )
        }
    }

    /// Nothing to go back to before the first Space change of the session, so
    /// the binding is inert until then rather than picking a stand-in.
    private func switchToPrevious() {
        guard ensureAccessibility() else {
            return
        }
        performSwitch(forwardsKeyEvents: switchForwardsKeyEvents) {
            try? ScriptingHelpers.switchToPreviousSpace(appState: appState)
        }
    }

    /// Out-of-range failures stay silent: a hotkey has no caller to report
    /// to, and beeping on every press of a stale binding would punish
    /// leaving one recorded.
    private func switchTo(number: Int) {
        guard ensureAccessibility() else {
            return
        }
        // The global route may forward a numbered Mission Control key event
        // even outside the classic path, so it always steps aside.
        performSwitch(forwardsKeyEvents: !store.localSpaceNumbers || switchForwardsKeyEvents) {
            try? ScriptingHelpers.switchToSpace(number: number, appState: appState, store: store)
        }
    }

    /// Wrapping follows the same preference as the switch hotkeys, so both
    /// directions behave the same way at the edges. Failures stay silent for
    /// the same reason `switchTo` swallows its own. Skipping empty Spaces has
    /// a preference per verb, separate from the switch hotkeys': landing a
    /// window on an empty Space is a normal way to start a fresh Desktop.
    private func moveWindow(goRight: Bool, follow: Bool) {
        guard ensureAccessibility() else {
            return
        }
        Task { @MainActor in
            let skips = follow ? store.hotkeysMoveSkipEmptySpaces : store.hotkeysSendSkipEmptySpaces
            let skipped = skips ? appState.emptySpaceIDs() : []
            try? await ScriptingHelpers.moveWindowRelative(
                goRight: goRight,
                follow: follow,
                wrap: store.scrollWrapAround,
                skippingSpaceIDs: skipped,
                appState: appState
            )
        }
    }

    /// Skipping empty Spaces does not apply here: an absolute target has
    /// nothing to step over, matching how `switchTo` ignores the toggle.
    /// Numbering follows the menu bar preference, the same resolution the
    /// numbered switch hotkeys use.
    private func moveWindow(toNumber number: Int, follow: Bool) {
        guard ensureAccessibility() else {
            return
        }
        Task { @MainActor in
            try? await ScriptingHelpers.moveWindow(
                toSpace: number,
                follow: follow,
                appState: appState,
                store: store
            )
        }
    }
}
