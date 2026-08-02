import AppKit
import KeyboardShortcuts

extension KeyboardShortcuts.Name {
    static let switchLeft = Self("switchLeft")
    static let switchRight = Self("switchRight")

    /// One bindable name per Space position on the current display. Positions
    /// past the current Space count stay recorded but inert, so a binding
    /// survives the Space it targets being removed and re-added.
    static let jumpToSpace: [Self] = (1 ... HotkeyCenter.maxJumpTargets).map {
        Self("switchToSpace\($0)")
    }
}

/// Routes recorded global hotkeys into the same switching helpers the
/// scripting, URL, and Shortcuts surfaces use, so range validation and
/// fullscreen handling stay identical across entry points.
@MainActor
final class HotkeyCenter {
    /// How many Spaces can carry a direct binding: the most Spaces a display
    /// can hold, so the pane's recorder list and the Spaces sidebar agree.
    nonisolated static let maxJumpTargets = Layout.maxSpacesPerDisplay

    /// Every bindable name, for whole-surface operations like a full reset.
    static var allNames: [KeyboardShortcuts.Name] {
        [.switchLeft, .switchRight] + KeyboardShortcuts.Name.jumpToSpace
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
        for (index, name) in KeyboardShortcuts.Name.jumpToSpace.enumerated() {
            KeyboardShortcuts.onKeyDown(for: name) { [weak self] in
                Task { @MainActor in
                    self?.switchTo(number: index + 1)
                }
            }
        }
    }

    /// Wrapping follows the same preference as scroll switching, so the two
    /// relative surfaces agree about what happens at the edges.
    private func switchRelative(goRight: Bool) {
        guard AXIsProcessTrusted() else {
            return
        }
        _ = SpaceSwitcher.switchRelative(goRight: goRight, wrap: store.scrollWrapAround)
    }

    /// Out-of-range and permission failures stay silent: a hotkey has no
    /// caller to report to, and beeping on every press of a stale binding
    /// would punish leaving one recorded.
    private func switchTo(number: Int) {
        try? ScriptingHelpers.switchToSpace(number: number, appState: appState)
    }
}
