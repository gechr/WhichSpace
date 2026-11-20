import AppKit
import KeyboardShortcuts
import Testing
@testable import WhichSpace

/// The lookup behind the recorder's "already used by" alert. Driven through
/// the bindings-taking overload so nothing here reads or writes the recorded
/// shortcuts, which live in the standard defaults domain rather than the
/// app's own suite.
@MainActor
struct HotkeyConflictTests {
    private let combination = KeyboardShortcuts.Shortcut(.one, modifiers: [.command])
    private let other = KeyboardShortcuts.Shortcut(.two, modifiers: [.command])

    @Test("fullscreen bindings round trip through backup names and participate in conflict detection")
    func fullscreenNames() throws {
        for uuid in [UUID().uuidString, nil] {
            let entry = SpaceEntry(id: 46, label: Labels.fullscreen, regularIndex: nil, uuid: uuid)
            let target = FullscreenShortcutTarget(entry: entry, displayID: "Second", displayNumber: 2, position: 3)
            let name = try #require(FullscreenShortcutTarget.storedName(target.id))
            #expect(name.rawValue == target.id)
            #expect(HotkeyCenter.owner(of: combination, excluding: .moveLeft, bindings: [name: combination]) == name)
            #expect(FullscreenShortcutTarget.storedName(target.id + ".unknown") == nil)
        }
        #expect(FullscreenShortcutTarget.storedName("switchLeft") == nil)
    }

    @Test("forwarded navigation keys tolerate implicit Fn and letter shortcuts retain explicit Fn")
    func forwardedChords() throws {
        func chords(
            _ key: KeyboardShortcuts.Key, modifiers: NSEvent.ModifierFlags = .control
        ) throws -> Set<KeyboardShortcuts.Shortcut> {
            let event = try #require(CGEvent(
                keyboardEventSource: nil,
                virtualKey: CGKeyCode(key.rawValue),
                keyDown: true
            ))
            event.flags = []
            return try HotkeyCenter.forwardedChords(
                for: #require(NSEvent(cgEvent: event)), flags: CGSModifierFlags(modifiers.rawValue)
            )
        }
        #expect(try chords(.leftArrow) == [
            .init(.leftArrow, modifiers: .control),
            .init(.leftArrow, modifiers: [.control, .function]),
        ])
        #expect(try chords(.a) == [.init(.a, modifiers: .control)])
        #expect(try chords(.a, modifiers: [.control, .function]) == [.init(.a, modifiers: [.control, .function])])
    }

    @Test("overlapping posts restore bindings together and failed posts roll back only their own binding")
    func restoreOverlappingHotKeys() async throws {
        var disabled = Set<KeyboardShortcuts.Name>()
        var systemRestores: [CGSSymbolicHotKey] = []
        var bindingRestores: [Set<KeyboardShortcuts.Name>] = []
        let forwarding = ForwardedHotKeys(
            delay: .zero,
            setSystemEnabled: { key, enabled in
                if !enabled {
                    systemRestores.append(key)
                }
                return key != 3
            }
        ) { names, enabled in
            if enabled {
                bindingRestores.append(Set(names))
                disabled.subtract(names)
            } else {
                disabled.formUnion(names)
            }
        }
        var posts = 0
        let first = forwarding.post(1, suspending: [.switchLeft], systemEnabled: false) { posts += 1 }
        let earlier = try #require(forwarding.pending)
        let second = forwarding.post(2, suspending: [.switchRight], systemEnabled: true) { posts += 1 }
        let failed = forwarding.post(3, suspending: [.switchPrevious], systemEnabled: false) { posts += 1 }
        #expect(first && second && !failed)
        #expect(posts == 2)
        #expect(earlier.isCancelled)
        #expect(disabled == [.switchLeft, .switchRight])
        #expect(bindingRestores == [[.switchPrevious]])
        await forwarding.pending?.value
        #expect(systemRestores == [1])
        #expect(bindingRestores == [[.switchPrevious], [.switchLeft, .switchRight]])
        #expect(disabled.isEmpty)
    }

    @Test("nothing recorded means nothing conflicts")
    func emptyBindingsHaveNoOwner() {
        let owner = HotkeyCenter.owner(of: combination, excluding: .switchLeft, bindings: [:])
        #expect(owner == nil)
    }

    /// Re-recording a binding onto the row that already holds it is the
    /// commonest way to hit the lookup, and it must stay silent.
    @Test("a name does not conflict with itself")
    func ownNameIsNotAConflict() {
        let owner = HotkeyCenter.owner(
            of: combination,
            excluding: .switchLeft,
            bindings: [.switchLeft: combination]
        )
        #expect(owner == nil)
    }

    @Test("another name holding the combination is the owner")
    func otherNameIsTheOwner() {
        let owner = HotkeyCenter.owner(
            of: combination,
            excluding: .sendRight,
            bindings: [.switchLeft: combination]
        )
        #expect(owner == .switchLeft)
    }

    @Test("a different combination on another name does not conflict")
    func differentCombinationIsNotAConflict() {
        let owner = HotkeyCenter.owner(
            of: combination,
            excluding: .sendRight,
            bindings: [.switchLeft: other]
        )
        #expect(owner == nil)
    }

    /// Numbered names past the current Desktop count stay recorded but inert,
    /// so one still owns its combination and must still be reported.
    @Test("an inert numbered name still owns its combination")
    func numberedNameBeyondTheDesktopCountOwnsIt() {
        let inert = KeyboardShortcuts.Name.moveToSpace[HotkeyCenter.maxJumpTargets - 1]
        let owner = HotkeyCenter.owner(
            of: combination,
            excluding: .switchLeft,
            bindings: [inert: combination]
        )
        #expect(owner == inert)
    }

    /// Every verb's numbered names are searched, not just the tab the picker
    /// happens to be showing.
    @Test("every verb's numbered names are searched")
    func everyVerbIsSearched() {
        let names = [
            KeyboardShortcuts.Name.jumpToSpace[0],
            KeyboardShortcuts.Name.sendToSpace[0],
            KeyboardShortcuts.Name.moveToSpace[0],
        ]
        for name in names {
            let owner = HotkeyCenter.owner(
                of: combination,
                excluding: .switchPrevious,
                bindings: [name: combination]
            )
            #expect(owner == name)
        }
    }
}
