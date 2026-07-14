import Cocoa

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

/// Command handler for AppleScript "switch to space number" command.
/// Usage: `tell application "WhichSpace" to switch to space number 3`
final class SwitchToSpaceCommand: NSScriptCommand {
    override func performDefaultImplementation() -> Any? {
        guard let spaceNumber = directParameter as? Int else {
            scriptErrorNumber = errOSACantAssign
            scriptErrorString = "Expected a space number."
            return nil
        }

        do {
            try MainActor.assumeIsolated {
                try ScriptingHelpers.switchToSpace(
                    number: spaceNumber,
                    appState: AppEnvironment.shared.appState
                )
            }
        } catch {
            scriptErrorNumber = errOSACantAssign
            scriptErrorString = error.localizedDescription
        }
        return nil
    }
}

// MARK: - Scripting Helpers

/// Errors thrown by `ScriptingHelpers.switchToSpace`.
/// Surfaces to AppleScript callers via `NSScriptCommand.scriptErrorString`.
enum SwitchError: LocalizedError {
    case accessibilityNotTrusted
    case noSpacesAvailable
    case spaceOutOfRange(requested: Int, max: Int)

    var errorDescription: String? {
        switch self {
        case .accessibilityNotTrusted:
            "Accessibility permission required. Grant it in System Settings → Privacy & Security → Accessibility."
        case .noSpacesAvailable:
            "No spaces available."
        case let .spaceOutOfRange(requested, max):
            "Space \(requested) does not exist (1-\(max))."
        }
    }
}

@MainActor
enum ScriptingHelpers {
    static func switchToSpace(number: Int, appState: AppState) throws(SwitchError) {
        guard AXIsProcessTrusted() else {
            throw .accessibilityNotTrusted
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

    static func resolveCurrentLabel(appState: AppState, store: DefaultsStore) -> String {
        if let customLabel = SpacePreferences.label(
            forSpace: appState.currentSpace,
            display: appState.currentDisplayID,
            store: store
        ), !customLabel.isEmpty {
            return LabelTemplate.resolve(customLabel, space: appState.currentSpaceDisplayNumber)
        }
        return appState.currentSpaceLabel
    }

    /// Applies a custom label to the current Space, mirroring the menu-driven
    /// path in `ActionHandler.setLabel`. Empty strings are ignored; use
    /// `resetCurrentLabel` to remove a custom label. The status bar icon
    /// re-renders automatically via the `displaySpaceLabels` defaults observer.
    static func setCurrentLabel(_ label: String, appState: AppState, store: DefaultsStore) {
        guard appState.currentSpace > 0, !label.isEmpty else {
            return
        }
        // Enforce the same content-length limit as the menu input field.
        // Over-long labels are truncated with an ellipsis so the marker is
        // visible in the menu bar.
        SpacePreferences.setLabel(
            LabelTemplate.truncate(label, ellipsis: true),
            forSpace: appState.currentSpace,
            display: appState.currentDisplayID,
            store: store
        )
        // Clear the symbol so the label takes effect immediately, matching the menu path.
        SpacePreferences.clearSymbol(
            forSpace: appState.currentSpace,
            display: appState.currentDisplayID,
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
}

/// Extension to make the application scriptable for property access.
extension NSApplication {
    /// Returns the current space number (1-based index).
    /// Usage: `tell application "WhichSpace" to get current space number`
    @MainActor @objc var currentSpaceNumber: Int {
        AppEnvironment.shared.appState.currentSpace
    }

    /// Gets or sets the current space label.
    /// Reading returns the custom label if set, otherwise "1", "2", "F" for fullscreen.
    /// Assigning a non-empty string applies a custom label; assigning "" is a no-op
    /// (use the `reset current space label` command to clear deliberately).
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
}
