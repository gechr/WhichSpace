import AppKit
import KeyboardShortcuts
import Observation

/// A binding identifies a Space independently of its display or position.
/// Without a UUID, a managed ID is only safe to reuse during this launch.
struct FullscreenShortcutTarget: Identifiable, Equatable {
    private static let session = UUID().uuidString
    static let prefix = "fullscreenSpace-"

    let entry: SpaceEntry
    let displayID: String
    let displayNumber: Int
    let position: Int

    var id: String {
        let identity = entry.uuid.flatMap(UUID.init(uuidString:))?.uuidString
            ?? "\(Self.session)-\(entry.id)"
        return Self.prefix + identity
    }

    static func storedName(_ raw: String) -> KeyboardShortcuts.Name? {
        guard raw.hasPrefix(prefix) else {
            return nil
        }
        let suffix = raw.dropFirst(prefix.count)
        let uuid = String(suffix.prefix(36))
        guard UUID(uuidString: uuid)?.uuidString == uuid else {
            return nil
        }
        let rest = suffix.dropFirst(36)
        guard rest.isEmpty || (rest.first == "-" && Int(rest.dropFirst()).map { $0 > 0 } == true) else {
            return nil
        }
        return .init(raw)
    }
}

/// Keep recorded bindings available for a disconnected display, but release
/// their global key registrations as soon as their targets disappear.
struct FullscreenShortcutHandlers {
    private(set) var names: [String: KeyboardShortcuts.Name] = [:]

    mutating func update(
        _ targets: [FullscreenShortcutTarget],
        remove: (KeyboardShortcuts.Name) -> Void,
        register: (KeyboardShortcuts.Name) -> Void
    ) {
        let live = Set(targets.map(\.id))
        for (id, name) in names where !live.contains(id) {
            remove(name)
            names.removeValue(forKey: id)
        }
        for id in live where names[id] == nil {
            let name = KeyboardShortcuts.Name(id)
            register(name)
            names[id] = name
        }
    }
}

extension AppState {
    var fullscreenShortcutTargets: [FullscreenShortcutTarget] {
        allDisplaysSpaceInfo.enumerated().flatMap { screen, display in
            display.entries.enumerated().compactMap { index, entry in
                guard entry.regularIndex == nil, !entry.hasOnlyExcludedTileOwners else {
                    return nil
                }
                return FullscreenShortcutTarget(
                    entry: entry, displayID: display.displayID, displayNumber: screen + 1, position: index + 1
                )
            }
        }
    }
}

/// Keeps overlapping posts registered until WindowServer has matched the last event.
@MainActor
final class ForwardedHotKeys {
    typealias Name = KeyboardShortcuts.Name

    private var forceEnabled: Set<CGSSymbolicHotKey> = []
    private var suspended: Set<Name> = []
    private(set) var pending: Task<Void, Never>?
    private let delay: Duration
    private let setSystemEnabled: (CGSSymbolicHotKey, Bool) -> Bool
    private let setBindingsEnabled: ([Name], Bool) -> Void

    init(
        delay: Duration = .milliseconds(250),
        setSystemEnabled: @escaping (CGSSymbolicHotKey, Bool) -> Bool = {
            CGSSetSymbolicHotKeyEnabled($0, $1) == .success
        },
        setBindingsEnabled: @escaping ([Name], Bool) -> Void = { names, enabled in
            if enabled {
                KeyboardShortcuts.enable(names)
            } else {
                KeyboardShortcuts.disable(names)
            }
        }
    ) {
        self.delay = delay
        self.setSystemEnabled = setSystemEnabled
        self.setBindingsEnabled = setBindingsEnabled
    }

    func post(
        _ hotKey: CGSSymbolicHotKey,
        suspending bindings: [Name],
        systemEnabled: @autoclosure () -> Bool,
        action: () -> Void
    ) -> Bool {
        setBindingsEnabled(bindings, false)
        if !systemEnabled() {
            guard setSystemEnabled(hotKey, true) else {
                setBindingsEnabled(bindings, true)
                NSLog("SpaceSwitcher: failed to enable hot key %d", Int(hotKey))
                return false
            }
            forceEnabled.insert(hotKey)
        }
        action()
        suspended.formUnion(bindings)
        if !forceEnabled.isEmpty || !suspended.isEmpty {
            scheduleRestore()
        }
        return true
    }

    private func scheduleRestore() {
        pending?.cancel()
        pending = Task {
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else {
                return
            }
            for key in forceEnabled {
                _ = setSystemEnabled(key, false)
            }
            forceEnabled.removeAll()
            setBindingsEnabled(Array(suspended), true)
            suspended.removeAll()
            pending = nil
        }
    }
}

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

    private static var fixedNames: [KeyboardShortcuts.Name] {
        [.switchLeft, .switchRight, .switchPrevious, .sendLeft, .sendRight, .moveLeft, .moveRight]
            + KeyboardShortcuts.Name.jumpToSpace
            + KeyboardShortcuts.Name.sendToSpace
            + KeyboardShortcuts.Name.moveToSpace
    }

    static var allNames: [KeyboardShortcuts.Name] {
        fixedNames + storedFullscreenNames
    }

    static var storedFullscreenNames: [KeyboardShortcuts.Name] {
        KeyboardShortcuts.storedNames.filter { $0.rawValue.hasPrefix(FullscreenShortcutTarget.prefix) }
            .sorted { $0.rawValue < $1.rawValue }
    }

    static func enabledBindings(for unmodified: NSEvent, flags: CGSModifierFlags) -> [KeyboardShortcuts.Name] {
        let chords = forwardedChords(for: unmodified, flags: flags)
        return KeyboardShortcuts.storedNames.filter { name in
            guard let shortcut = KeyboardShortcuts.getShortcut(for: name), chords.contains(shortcut) else {
                return false
            }
            return KeyboardShortcuts.isEnabled(for: name)
        }
    }

    static func forwardedChords(for unmodified: NSEvent, flags: CGSModifierFlags) -> Set<KeyboardShortcuts.Shortcut> {
        let key = KeyboardShortcuts.Key(rawValue: Int(unmodified.keyCode))
        let modifiers = NSEvent.ModifierFlags(rawValue: UInt(flags))
        guard unmodified.modifierFlags.contains(.function) else {
            return [.init(key, modifiers: modifiers)]
        }
        return [
            .init(key, modifiers: modifiers.union(.function)),
            .init(key, modifiers: modifiers.subtracting(.function)),
        ]
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

    /// The recorded bindings as name to the chord the user presses, for the diagnostics report.
    /// The rendering is glyphs and the layout's own character, so it does not vary by language.
    static func describeBindings() -> [String: String] {
        var bindings = [String: String]()
        var fullscreenIndex = 0
        for name in allNames {
            guard let shortcut = KeyboardShortcuts.getShortcut(for: name) else {
                continue
            }
            if name.rawValue.hasPrefix(FullscreenShortcutTarget.prefix) {
                fullscreenIndex += 1
                bindings["fullscreenSpace\(fullscreenIndex)"] = shortcut.description
            } else {
                bindings[name.rawValue] = shortcut.description
            }
        }
        return bindings
    }

    /// Replaces every binding with the imported set: names absent from the
    /// backup are cleared, matching how the rest of an import overwrites
    /// current state. Unreadable entries clear their binding rather than
    /// keeping a value the backup meant to change.
    static func importBindings(_ bindings: [String: String]) {
        let imported = bindings.keys.compactMap(FullscreenShortcutTarget.storedName)
        for name in Set(allNames).union(imported) {
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

    /// The recorded name holding `shortcut`, ignoring `name` so re-recording a
    /// binding onto itself is not a conflict. One combination must map to one
    /// name: the library invokes every handler whose name resolves to a
    /// shortcut, so a duplicate fires both actions on a single press.
    static func owner(
        of shortcut: KeyboardShortcuts.Shortcut,
        excluding name: KeyboardShortcuts.Name
    ) -> KeyboardShortcuts.Name? {
        var bindings = [KeyboardShortcuts.Name: KeyboardShortcuts.Shortcut]()
        for candidate in allNames {
            bindings[candidate] = KeyboardShortcuts.getShortcut(for: candidate)
        }
        return owner(of: shortcut, excluding: name, bindings: bindings)
    }

    /// The lookup itself, taking the bindings rather than reading them, so it
    /// resolves without the recorded state the live overload reaches for.
    /// Numbered names past the current Desktop count are searched too: a
    /// binding on an inert row still owns its combination.
    static func owner(
        of shortcut: KeyboardShortcuts.Shortcut,
        excluding name: KeyboardShortcuts.Name,
        bindings: [KeyboardShortcuts.Name: KeyboardShortcuts.Shortcut]
    ) -> KeyboardShortcuts.Name? {
        bindings.first { $0.key != name && $0.value == shortcut }?.key
    }

    private let appState: AppState
    private let store: DefaultsStore
    private var fullscreenHandlers = FullscreenShortcutHandlers()

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
        observeFullscreenTargets()
    }

    private func observeFullscreenTargets() {
        let targets = withObservationTracking {
            appState.fullscreenShortcutTargets
        } onChange: { [weak self] in
            Task { @MainActor in self?.observeFullscreenTargets() }
        }
        fullscreenHandlers.update(targets, remove: KeyboardShortcuts.removeHandler(for:)) { name in
            KeyboardShortcuts.onKeyDown(for: name) { [weak self] in
                Task { @MainActor in self?.switchToFullscreen(name) }
            }
        }
    }

    private func switchToFullscreen(_ name: KeyboardShortcuts.Name) {
        guard let target = appState.fullscreenShortcutTargets.first(where: { $0.id == name.rawValue }),
              ensureAccessibility()
        else {
            return
        }
        SpaceSwitcher.selectFullscreenSpace(target.entry.id)
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

    /// Wrapping follows the same preference as scroll switching, so the two
    /// relative surfaces agree about what happens at the edges. Skipping
    /// empty Spaces is a hotkey-only preference: scroll and the scripting
    /// surfaces keep stepping one Space at a time.
    private func switchRelative(goRight: Bool) {
        guard ensureAccessibility() else {
            return
        }
        let skipped = store.hotkeysSkipEmptySpaces ? appState.emptySpaceIDs() : []
        _ = SpaceSwitcher.switchRelative(
            goRight: goRight,
            wrap: store.scrollWrapAround,
            skippingSpaceIDs: skipped
        )
    }

    /// Nothing to go back to before the first Space change of the session, so
    /// the binding is inert until then rather than picking a stand-in.
    private func switchToPrevious() {
        guard ensureAccessibility() else {
            return
        }
        try? ScriptingHelpers.switchToPreviousSpace(appState: appState)
    }

    /// Out-of-range failures stay silent: a hotkey has no caller to report
    /// to, and beeping on every press of a stale binding would punish
    /// leaving one recorded.
    private func switchTo(number: Int) {
        guard ensureAccessibility() else {
            return
        }
        SpaceSwitcher.switchToDesktop(number: number, local: store.localSpaceNumbers)
    }

    /// Wrapping follows the same preference as the switch hotkeys, so both
    /// directions behave the same way at the edges. Failures stay silent for
    /// the same reason `switchTo` swallows its own. Skipping empty Spaces has
    /// a preference per verb, separate from the switch hotkeys': landing a
    /// window on an empty Space is a normal way to start a fresh Desktop.
    /// Occupancy is sampled by the provider once the command executes, so a
    /// press queued behind another move sees that move's result.
    private func moveWindow(goRight: Bool, follow: Bool) {
        guard ensureAccessibility() else {
            return
        }
        Task { @MainActor in
            try? await ScriptingHelpers.moveWindowRelative(
                goRight: goRight,
                follow: follow,
                wrap: store.scrollWrapAround,
                skippingSpaceIDs: { [store, appState] in
                    let skips = follow ? store.hotkeysMoveSkipEmptySpaces : store.hotkeysSendSkipEmptySpaces
                    return skips ? appState.emptySpaceIDs() : []
                },
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
