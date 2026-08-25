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
