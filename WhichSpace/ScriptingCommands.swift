import Cocoa

/// Command handler for AppleScript "move front window left" command.
/// Usage: `tell application "WhichSpace" to move front window left`
final class MoveWindowLeftCommand: NSScriptCommand {
    override func performDefaultImplementation() -> Any? {
        performMove { try await ScriptingHelpers.moveWindowRelative(goRight: false, follow: true) }
        return nil
    }
}

/// Command handler for AppleScript "move front window right" command.
/// Usage: `tell application "WhichSpace" to move front window right`
final class MoveWindowRightCommand: NSScriptCommand {
    override func performDefaultImplementation() -> Any? {
        performMove { try await ScriptingHelpers.moveWindowRelative(goRight: true, follow: true) }
        return nil
    }
}

/// Command handler for AppleScript "move front window to space number" command.
/// Usage: `tell application "WhichSpace" to move front window to space number 3`
final class MoveWindowToSpaceCommand: NSScriptCommand {
    override func performDefaultImplementation() -> Any? {
        guard let spaceNumber = spaceNumberParameter() else {
            return nil
        }
        performMove { try await ScriptingHelpers.moveWindow(toSpace: spaceNumber, follow: true) }
        return nil
    }
}

/// Command handler for AppleScript "send front window left" command.
/// Usage: `tell application "WhichSpace" to send front window left`
final class SendWindowLeftCommand: NSScriptCommand {
    override func performDefaultImplementation() -> Any? {
        performMove { try await ScriptingHelpers.moveWindowRelative(goRight: false, follow: false) }
        return nil
    }
}

/// Command handler for AppleScript "send front window right" command.
/// Usage: `tell application "WhichSpace" to send front window right`
final class SendWindowRightCommand: NSScriptCommand {
    override func performDefaultImplementation() -> Any? {
        performMove { try await ScriptingHelpers.moveWindowRelative(goRight: true, follow: false) }
        return nil
    }
}

/// Command handler for AppleScript "send front window to space number" command.
/// Usage: `tell application "WhichSpace" to send front window to space number 3`
final class SendWindowToSpaceCommand: NSScriptCommand {
    override func performDefaultImplementation() -> Any? {
        guard let spaceNumber = spaceNumberParameter() else {
            return nil
        }
        performMove { try await ScriptingHelpers.moveWindow(toSpace: spaceNumber, follow: false) }
        return nil
    }
}

extension NSScriptCommand {
    /// Reads the 1-based Space number, reporting a script error when it is
    /// missing or not an integer.
    fileprivate func spaceNumberParameter() -> Int? {
        guard let spaceNumber = directParameter as? Int else {
            scriptErrorNumber = errOSACantAssign
            scriptErrorString = Localization.errorScriptingExpectedSpaceNumber
            return nil
        }
        return spaceNumber
    }

    /// Runs an asynchronous move, suspending the script until the window has
    /// actually landed so callers can act on the result. Moves are confirmed
    /// against the window server, so they cannot report success early.
    fileprivate func performMove(_ work: @escaping @MainActor () async throws -> Void) {
        suspendExecution()
        // Apple Events are delivered on the main thread and the work below runs
        // on the main actor, so the command is never touched concurrently
        nonisolated(unsafe) let command = self
        Task { @MainActor in
            do {
                try await work()
            } catch {
                command.scriptErrorNumber = errOSACantAssign
                command.scriptErrorString = error.localizedDescription
            }
            command.resumeExecution(withResult: nil)
        }
    }
}

/// Command handler for AppleScript "reset all space badges" command.
/// Usage: `tell application "WhichSpace" to reset all space badges`
final class ResetAllSpaceBadgesCommand: NSScriptCommand {
    override func performDefaultImplementation() -> Any? {
        MainActor.assumeIsolated {
            SpacePreferences.clearAllBadges(store: AppEnvironment.shared.store)
        }
        return nil
    }
}

/// Command handler for AppleScript "reset all space labels" command.
/// Usage: `tell application "WhichSpace" to reset all space labels`
final class ResetAllSpaceLabelsCommand: NSScriptCommand {
    override func performDefaultImplementation() -> Any? {
        MainActor.assumeIsolated {
            SpacePreferences.clearAllLabels(store: AppEnvironment.shared.store)
        }
        return nil
    }
}

/// Command handler for AppleScript "reset current space badge" command.
/// Usage: `tell application "WhichSpace" to reset current space badge`
final class ResetCurrentSpaceBadgeCommand: NSScriptCommand {
    override func performDefaultImplementation() -> Any? {
        MainActor.assumeIsolated {
            ScriptingHelpers.resetCurrentBadge(
                appState: AppEnvironment.shared.appState,
                store: AppEnvironment.shared.store
            )
        }
        return nil
    }
}

/// Command handler for AppleScript "reset current space label" command.
/// Usage: `tell application "WhichSpace" to reset current space label`
final class ResetCurrentSpaceLabelCommand: NSScriptCommand {
    override func performDefaultImplementation() -> Any? {
        MainActor.assumeIsolated {
            ScriptingHelpers.resetCurrentLabel(
                appState: AppEnvironment.shared.appState,
                store: AppEnvironment.shared.store
            )
        }
        return nil
    }
}

/// Command handler for AppleScript "switch left" command.
/// Usage: `tell application "WhichSpace" to switch left`
final class SwitchLeftCommand: NSScriptCommand {
    override func performDefaultImplementation() -> Any? {
        do {
            try MainActor.assumeIsolated {
                try ScriptingHelpers.switchRelative(goRight: false)
            }
        } catch {
            scriptErrorNumber = errOSACantAssign
            scriptErrorString = error.localizedDescription
        }
        return nil
    }
}

/// Command handler for AppleScript "switch right" command.
/// Usage: `tell application "WhichSpace" to switch right`
final class SwitchRightCommand: NSScriptCommand {
    override func performDefaultImplementation() -> Any? {
        do {
            try MainActor.assumeIsolated {
                try ScriptingHelpers.switchRelative(goRight: true)
            }
        } catch {
            scriptErrorNumber = errOSACantAssign
            scriptErrorString = error.localizedDescription
        }
        return nil
    }
}

/// Command handler for AppleScript "switch to previous space" command.
/// Usage: `tell application "WhichSpace" to switch to previous space`
final class SwitchToPreviousSpaceCommand: NSScriptCommand {
    override func performDefaultImplementation() -> Any? {
        do {
            try MainActor.assumeIsolated {
                try ScriptingHelpers.switchToPreviousSpace(appState: AppEnvironment.shared.appState)
            }
        } catch {
            scriptErrorNumber = errOSACantAssign
            scriptErrorString = error.localizedDescription
        }
        return nil
    }
}

/// Command handler for AppleScript "switch to space number" command.
/// Usage: `tell application "WhichSpace" to switch to space number 3`
/// Usage: `tell application "WhichSpace" to switch to space number 3 label "Work"`
/// Usage: `tell application "WhichSpace" to switch to space number 3 badge "A"`
final class SwitchToSpaceCommand: NSScriptCommand {
    override func performDefaultImplementation() -> Any? {
        guard let spaceNumber = directParameter as? Int else {
            scriptErrorNumber = errOSACantAssign
            scriptErrorString = Localization.errorScriptingExpectedSpaceNumber
            return nil
        }
        let label = evaluatedArguments?["label"] as? String
        let badge = evaluatedArguments?["badge"] as? String

        do {
            try MainActor.assumeIsolated {
                try ScriptingHelpers.switchToSpace(
                    number: spaceNumber,
                    appState: AppEnvironment.shared.appState
                )
                // Keyed by the target Space number, so these cannot race the
                // asynchronous switch animation
                if let label {
                    ScriptingHelpers.setLabel(
                        label,
                        forSpace: spaceNumber,
                        appState: AppEnvironment.shared.appState,
                        store: AppEnvironment.shared.store
                    )
                }
                if let badge {
                    try ScriptingHelpers.setBadge(
                        badge,
                        forSpace: spaceNumber,
                        appState: AppEnvironment.shared.appState,
                        store: AppEnvironment.shared.store
                    )
                }
            }
        } catch {
            scriptErrorNumber = errOSACantAssign
            scriptErrorString = error.localizedDescription
        }
        return nil
    }
}

// MARK: - Scripting Helpers

/// Errors thrown by `ScriptingHelpers.setCurrentBadge`.
/// Surfaces to AppleScript callers via `NSScriptCommand.scriptErrorString`.
enum BadgeError: LocalizedError {
    case notASingleCharacter

    var errorDescription: String? {
        switch self {
        case .notASingleCharacter:
            Localization.errorScriptingBadgeSingleCharacter
        }
    }
}

/// Errors thrown by `ScriptingHelpers.switchToSpace`.
/// Surfaces to AppleScript callers via `NSScriptCommand.scriptErrorString`.
enum SwitchError: LocalizedError {
    case accessibilityNotTrusted
    case noSpacesAvailable
    case noPreviousSpace
    case spaceOutOfRange(requested: Int, max: Int)

    var errorDescription: String? {
        switch self {
        case .accessibilityNotTrusted:
            Localization.errorScriptingAccessibilityRequired
        case .noSpacesAvailable:
            Localization.errorScriptingNoSpaces
        case .noPreviousSpace:
            Localization.errorScriptingNoPreviousSpace
        case let .spaceOutOfRange(requested, max):
            String(format: Localization.errorScriptingSpaceOutOfRange, requested, max)
        }
    }
}

/// Errors thrown by `ScriptingHelpers.moveWindow`.
/// Surfaces to AppleScript callers via `NSScriptCommand.scriptErrorString`.
enum MoveError: LocalizedError {
    case accessibilityNotTrusted
    case noSpacesAvailable
    case spaceOutOfRange(requested: Int, max: Int)
    case spaceIsFullscreen(requested: Int)
    case noWindowToMove
    case windowIsFullscreen
    case unsupported
    case moveFailed(requested: Int)

    var errorDescription: String? {
        switch self {
        case .accessibilityNotTrusted:
            Localization.errorScriptingAccessibilityRequired
        case .noSpacesAvailable:
            Localization.errorScriptingNoSpaces
        case let .spaceOutOfRange(requested, max):
            String(format: Localization.errorScriptingSpaceOutOfRange, requested, max)
        case let .spaceIsFullscreen(requested):
            String(format: Localization.errorScriptingSpaceIsFullscreen, requested)
        case .noWindowToMove:
            Localization.errorScriptingNoWindowToMove
        case .windowIsFullscreen:
            Localization.errorScriptingWindowIsFullscreen
        case .unsupported:
            Localization.errorScriptingMoveUnsupported
        case let .moveFailed(requested):
            String(format: Localization.errorScriptingMoveFailed, requested)
        }
    }
}

@MainActor
enum ScriptingHelpers {
    /// Moves the frontmost window to the Space at the given 1-based number.
    /// `follow` switches to that Space afterwards, which is the difference
    /// between the `move` and `send` commands. Numbering follows the menu bar
    /// preference, the same way `switchToSpace(number:)` resolves it.
    static func moveWindow(
        toSpace number: Int,
        follow: Bool,
        appState: AppState = AppEnvironment.shared.appState,
        store: DefaultsStore = AppEnvironment.shared.store,
        mover: SpaceWindowMover = SpaceWindowMover()
    ) async throws(MoveError) {
        if store.localSpaceNumbers {
            try await mover.move(toSpaceNumber: number, follow: follow, appState: appState)
        } else {
            try await mover.move(toGlobalDesktop: number, follow: follow, appState: appState)
        }
    }

    /// Moves the frontmost window one Space left or right, skipping fullscreen
    /// Spaces. Without `wrap` either edge is an error rather than a silent
    /// no-op, which is what the scripting and URL surfaces want.
    static func moveWindowRelative(
        goRight: Bool,
        follow: Bool,
        wrap: Bool = false,
        appState: AppState = AppEnvironment.shared.appState,
        mover: SpaceWindowMover = SpaceWindowMover()
    ) async throws(MoveError) {
        try await mover.moveRelative(goRight: goRight, follow: follow, wrap: wrap, appState: appState)
    }

    /// Switches to the Space at the given 1-based number. Numbering follows
    /// the menu bar preference: the current display's Spaces with local
    /// numbering, Desktops across every display otherwise, in which case the
    /// switch can cross a display boundary.
    static func switchToSpace(
        number: Int,
        appState: AppState,
        store: DefaultsStore = AppEnvironment.shared.store
    ) throws(SwitchError) {
        guard AXIsProcessTrusted() else {
            throw .accessibilityNotTrusted
        }
        guard store.localSpaceNumbers else {
            try switchToGlobalDesktop(number: number, appState: appState)
            return
        }
        let entries = appState.allSpaceEntries
        guard !entries.isEmpty else {
            throw .noSpacesAvailable
        }
        guard number >= 1, number <= entries.count else {
            throw .spaceOutOfRange(requested: number, max: entries.count)
        }
        guard number != appState.currentSpace else {
            return
        }
        let entry = entries[number - 1]
        if entry.regularIndex != nil {
            SpaceSwitcher.switchToSpace(id: entry.id)
        } else {
            _ = SpaceSwitcher.activateAppOnSpace(entry.id)
        }
    }

    /// Switches to a globally numbered Desktop, which may live on another
    /// display. Fullscreen Spaces carry no Desktop number, so global
    /// numbering cannot address them.
    private static func switchToGlobalDesktop(number: Int, appState: AppState) throws(SwitchError) {
        let desktops = appState.globalDesktopEntries
        guard !desktops.isEmpty else {
            throw .noSpacesAvailable
        }
        guard number >= 1, number <= desktops.count else {
            throw .spaceOutOfRange(requested: number, max: desktops.count)
        }
        SpaceSwitcher.switchToDesktop(number: number)
    }

    /// Switches back to the Space last visited on the current display. The
    /// switch records the Space being left, so issuing this repeatedly toggles
    /// between the two. Addressed by space ID rather than number, so the
    /// toggle is unaffected by the numbering preference.
    static func switchToPreviousSpace(appState: AppState) throws(SwitchError) {
        guard AXIsProcessTrusted() else {
            throw .accessibilityNotTrusted
        }
        guard let entry = appState.previousSpaceEntry else {
            throw .noPreviousSpace
        }
        if entry.regularIndex != nil {
            SpaceSwitcher.switchToSpace(id: entry.id)
        } else {
            _ = SpaceSwitcher.activateAppOnSpace(entry.id)
        }
    }

    /// Switches one Space left or right on the current display, clamped at the
    /// edges. Mirrors a single scroll or swipe step.
    static func switchRelative(goRight: Bool) throws(SwitchError) {
        guard AXIsProcessTrusted() else {
            throw .accessibilityNotTrusted
        }
        SpaceSwitcher.switchRelative(goRight: goRight)
    }

    /// Returns the number of Spaces addressable by `switch to space number`:
    /// the current display's Spaces with local numbering, numbered Desktops
    /// across every display otherwise.
    static func spaceCount(
        appState: AppState,
        store: DefaultsStore = AppEnvironment.shared.store
    ) -> Int {
        store.localSpaceNumbers
            ? appState.allSpaceEntries.count
            : appState.globalDesktopEntries.count
    }

    /// Returns the resolved label of every numbered Space, in the same order
    /// as `spaceCount`, so position N in the list is the Space that
    /// `switch to space number N` targets.
    static func resolveAllLabels(appState: AppState, store: DefaultsStore) -> [String] {
        guard store.localSpaceNumbers else {
            return appState.globalDesktopEntries.indices.map {
                resolveGlobalLabel(number: $0 + 1, appState: appState, store: store)
            }
        }
        return appState.allSpaceEntries.indices.map {
            resolveLabel(forSpace: $0 + 1, appState: appState, store: store)
        }
    }

    /// Returns the badge of every numbered Space, in the same order as
    /// `resolveAllLabels`. Spaces without a badge yield "".
    static func resolveAllBadges(appState: AppState, store: DefaultsStore) -> [String] {
        guard store.localSpaceNumbers else {
            return appState.globalDesktopEntries.indices.map {
                resolveGlobalBadge(number: $0 + 1, appState: appState, store: store)
            }
        }
        return appState.allSpaceEntries.indices.map {
            resolveBadge(forSpace: $0 + 1, appState: appState, store: store)
        }
    }

    /// Returns the label shown for the globally numbered Desktop: its custom
    /// label with space tokens resolved against the global number, otherwise
    /// the number itself, matching the menu bar in global mode.
    private static func resolveGlobalLabel(number: Int, appState: AppState, store: DefaultsStore) -> String {
        let target = appState.globalDesktopEntries[number - 1]
        if let customLabel = SpacePreferences.label(
            forSpace: target.position,
            display: target.displayID,
            store: store
        ), !customLabel.isEmpty {
            return LabelTemplate.resolve(customLabel, space: number)
        }
        return String(number)
    }

    /// Returns the badge of the globally numbered Desktop, with the number
    /// token resolved against the global number. Unbadged Desktops yield "".
    private static func resolveGlobalBadge(number: Int, appState: AppState, store: DefaultsStore) -> String {
        let target = appState.globalDesktopEntries[number - 1]
        guard let badge = SpacePreferences.badge(
            forSpace: target.position,
            display: target.displayID,
            store: store
        ) else {
            return ""
        }
        guard badge.character == BadgeTemplate.spaceToken else {
            return badge.character
        }
        return String(number)
    }

    /// Returns the label shown for the given Space: its custom label when set,
    /// with space tokens resolved against the displayed number, otherwise the
    /// default label ("1", "2", "F" for fullscreen).
    static func resolveLabel(forSpace number: Int, appState: AppState, store: DefaultsStore) -> String {
        if let customLabel = SpacePreferences.label(
            forSpace: number,
            display: appState.currentDisplayID,
            store: store
        ), !customLabel.isEmpty {
            return LabelTemplate.resolve(customLabel, space: appState.displayNumber(forSpace: number))
        }
        let index = number - 1
        guard appState.allSpaceEntries.indices.contains(index) else {
            return ""
        }
        return appState.allSpaceEntries[index].label
    }

    static func resolveCurrentLabel(appState: AppState, store: DefaultsStore) -> String {
        // The current Space keeps the snapshot's own label as its fallback,
        // which stays correct even while entries are momentarily empty
        if let customLabel = SpacePreferences.label(
            forSpace: appState.currentSpace,
            display: appState.currentDisplayID,
            store: store
        ), !customLabel.isEmpty {
            return LabelTemplate.resolve(customLabel, space: appState.currentSpaceDisplayNumber)
        }
        return appState.currentSpaceLabel
    }

    /// Resolves a numbered Space to the display and 1-based entry position
    /// that key its stored preferences. With local numbering the number is
    /// already the current display's entry position, and positions past the
    /// current count stay writable so labels can be recorded ahead of time.
    /// With global numbering the number resolves to the owning display, so
    /// it must address an existing Desktop.
    private static func preferenceKey(
        forSpace number: Int,
        appState: AppState,
        store: DefaultsStore
    ) -> (position: Int, displayID: String?)? {
        if store.localSpaceNumbers {
            return number > 0 ? (number, appState.currentDisplayID) : nil
        }
        let desktops = appState.globalDesktopEntries
        guard desktops.indices.contains(number - 1) else {
            return nil
        }
        let target = desktops[number - 1]
        return (target.position, target.displayID)
    }

    /// Applies a custom label to the given numbered Space, mirroring the
    /// menu-driven path in `ActionHandler.setLabel`. Numbering follows the
    /// menu bar preference, so a global number can address another display.
    /// Leading/trailing whitespace is ignored, and an empty string resets
    /// the label. The status bar icon re-renders automatically via the
    /// `displaySpaceLabels` defaults observer.
    static func setLabel(_ label: String, forSpace number: Int, appState: AppState, store: DefaultsStore) {
        guard let key = preferenceKey(forSpace: number, appState: appState, store: store) else {
            return
        }
        setLabel(label, at: key, store: store)
    }

    /// Applies a custom label to the current Space; see `setLabel(_:forSpace:)`.
    static func setCurrentLabel(_ label: String, appState: AppState, store: DefaultsStore) {
        guard appState.currentSpace > 0 else {
            return
        }
        setLabel(label, at: (appState.currentSpace, appState.currentDisplayID), store: store)
    }

    private static func setLabel(
        _ label: String,
        at key: (position: Int, displayID: String?),
        store: DefaultsStore
    ) {
        let label = label.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !label.isEmpty else {
            SpacePreferences.clearLabel(
                forSpace: key.position,
                display: key.displayID,
                store: store
            )
            return
        }
        // Enforce the same content-length limit as the menu input field.
        // Over-long labels are truncated with an ellipsis so the marker is
        // visible in the menu bar.
        SpacePreferences.setLabel(
            LabelTemplate.truncate(label, ellipsis: true),
            forSpace: key.position,
            display: key.displayID,
            store: store
        )
    }

    /// Removes the custom label from the current Space so it reverts to its
    /// default (the Space number, or "F" for fullscreen).
    static func resetCurrentLabel(appState: AppState, store: DefaultsStore) {
        guard appState.currentSpace > 0 else {
            return
        }
        SpacePreferences.clearLabel(
            forSpace: appState.currentSpace,
            display: appState.currentDisplayID,
            store: store
        )
    }

    /// Returns the current Space badge character, or "" when no badge is set.
    /// The special `#` character resolves to the displayed Space number,
    /// matching the menu bar rendering.
    static func resolveCurrentBadge(appState: AppState, store: DefaultsStore) -> String {
        resolveBadge(forSpace: appState.currentSpace, appState: appState, store: store)
    }

    /// Returns the badge character for the given Space, or "" when no badge is
    /// set. The special `#` character resolves to that Space's displayed
    /// number, matching the menu bar rendering.
    static func resolveBadge(forSpace number: Int, appState: AppState, store: DefaultsStore) -> String {
        guard let badge = SpacePreferences.badge(
            forSpace: number,
            display: appState.currentDisplayID,
            store: store
        ) else {
            return ""
        }
        guard badge.character == BadgeTemplate.spaceToken else {
            return badge.character
        }
        return String(appState.displayNumber(forSpace: number))
    }

    /// Applies a badge character to the given numbered Space, mirroring the
    /// menu-driven path in `ActionHandler.setBadgeCharacter`. Numbering
    /// follows the menu bar preference, so a global number can address
    /// another display. Leading/trailing whitespace is ignored, and an empty
    /// string resets the badge.
    static func setBadge(
        _ character: String,
        forSpace number: Int,
        appState: AppState,
        store: DefaultsStore
    ) throws(BadgeError) {
        guard let key = preferenceKey(forSpace: number, appState: appState, store: store) else {
            return
        }
        try setBadge(character, at: key, store: store)
    }

    /// Applies a badge character to the current Space; see `setBadge(_:forSpace:)`.
    static func setCurrentBadge(_ character: String, appState: AppState, store: DefaultsStore) throws(BadgeError) {
        guard appState.currentSpace > 0 else {
            return
        }
        try setBadge(character, at: (appState.currentSpace, appState.currentDisplayID), store: store)
    }

    private static func setBadge(
        _ character: String,
        at key: (position: Int, displayID: String?),
        store: DefaultsStore
    ) throws(BadgeError) {
        let character = character.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !character.isEmpty else {
            SpacePreferences.clearBadge(
                forSpace: key.position,
                display: key.displayID,
                store: store
            )
            return
        }
        // A badge is a single character (including multi-scalar emoji),
        // matching the menu input field.
        guard character.count == 1 else {
            throw .notASingleCharacter
        }
        let currentBadge = SpacePreferences.badge(
            forSpace: key.position,
            display: key.displayID,
            store: store
        )
        // Preserve the existing position, matching the menu input field.
        SpacePreferences.setBadge(
            SpaceBadge(character: character, position: currentBadge?.position ?? .topLeft),
            forSpace: key.position,
            display: key.displayID,
            store: store
        )
    }

    /// Removes the badge from the current Space.
    static func resetCurrentBadge(appState: AppState, store: DefaultsStore) {
        guard appState.currentSpace > 0 else {
            return
        }
        SpacePreferences.clearBadge(
            forSpace: appState.currentSpace,
            display: appState.currentDisplayID,
            store: store
        )
    }
}

/// Extension to make the application scriptable for property access.
extension NSApplication {
    /// Returns the current space number, following the local or global
    /// numbering preference. Fullscreen Spaces have no displayed number, so
    /// they yield their position among the current display's Spaces.
    /// Usage: `tell application "WhichSpace" to get current space number`
    @MainActor @objc var currentSpaceNumber: Int {
        AppEnvironment.shared.appState.currentSpaceDisplayNumber
    }

    /// Returns the number of Spaces addressable by `switch to space number`.
    /// Usage: `tell application "WhichSpace" to get space count`
    @MainActor @objc var spaceCount: Int {
        ScriptingHelpers.spaceCount(appState: AppEnvironment.shared.appState)
    }

    /// Returns the label of every numbered Space, in order, so item N of the
    /// list is the Space that `switch to space number N` targets.
    /// Usage: `tell application "WhichSpace" to get space labels`
    @MainActor @objc var spaceLabels: [String] {
        ScriptingHelpers.resolveAllLabels(
            appState: AppEnvironment.shared.appState,
            store: AppEnvironment.shared.store
        )
    }

    /// Returns the badge of every numbered Space, in the same order as
    /// `spaceLabels`. Spaces without a badge yield "".
    /// Usage: `tell application "WhichSpace" to get space badges`
    @MainActor @objc var spaceBadges: [String] {
        ScriptingHelpers.resolveAllBadges(
            appState: AppEnvironment.shared.appState,
            store: AppEnvironment.shared.store
        )
    }

    /// Gets or sets the current space label.
    /// Reading returns the custom label if set, otherwise "1", "2", "F" for fullscreen.
    /// Assigning a non-empty string applies a custom label; assigning "" resets it,
    /// as a synonym for the `reset current space label` command.
    /// Over-long labels are truncated with a trailing ellipsis.
    /// Usage: `tell application "WhichSpace" to get current space label`
    /// Usage: `tell application "WhichSpace" to set current space label to "Label"`
    @MainActor @objc var currentSpaceLabel: String {
        get {
            ScriptingHelpers.resolveCurrentLabel(
                appState: AppEnvironment.shared.appState,
                store: AppEnvironment.shared.store
            )
        }
        set {
            ScriptingHelpers.setCurrentLabel(
                newValue,
                appState: AppEnvironment.shared.appState,
                store: AppEnvironment.shared.store
            )
        }
    }

    /// Gets or sets the current space badge character.
    /// Reading returns the badge character ("#" resolved to the Space number), or "" when unset.
    /// Assigning a single character applies the badge; more than one character is an error and
    /// "" resets it, as a synonym for the `reset current space badge` command.
    /// Usage: `tell application "WhichSpace" to get current space badge`
    /// Usage: `tell application "WhichSpace" to set current space badge to "A"`
    @MainActor @objc var currentSpaceBadge: String {
        get {
            ScriptingHelpers.resolveCurrentBadge(
                appState: AppEnvironment.shared.appState,
                store: AppEnvironment.shared.store
            )
        }
        set {
            do {
                try ScriptingHelpers.setCurrentBadge(
                    newValue,
                    appState: AppEnvironment.shared.appState,
                    store: AppEnvironment.shared.store
                )
            } catch {
                // KVC setters can't throw; report through the in-flight command
                let command = NSScriptCommand.current()
                command?.scriptErrorNumber = errOSACantAssign
                command?.scriptErrorString = error.localizedDescription
            }
        }
    }
}
