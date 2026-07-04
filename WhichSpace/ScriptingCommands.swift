import Cocoa

/// Command handler for AppleScript "current space number" command.
/// Usage: `tell application "WhichSpace" to get current space number`
final class CurrentSpaceNumberCommand: NSScriptCommand {
    override func performDefaultImplementation() -> Any? {
        MainActor.assumeIsolated {
            AppEnvironment.shared.appState.currentSpace
        }
    }
}

/// Command handler for AppleScript "current space label" command.
/// Usage: `tell application "WhichSpace" to get current space label`
/// Returns the custom label if one is set, otherwise the default space label.
final class CurrentSpaceLabelCommand: NSScriptCommand {
    override func performDefaultImplementation() -> Any? {
        MainActor.assumeIsolated {
            ScriptingHelpers.resolveCurrentLabel(
                appState: AppEnvironment.shared.appState,
                store: AppEnvironment.shared.store
            )
        }
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
}

/// Extension to make the application scriptable for property access.
extension NSApplication {
    /// Returns the current space number (1-based index).
    /// Usage: `tell application "WhichSpace" to get current space number`
    @MainActor @objc var currentSpaceNumber: Int {
        AppEnvironment.shared.appState.currentSpace
    }

    /// Returns the current space label (custom label if set, otherwise "1", "2", "F" for fullscreen).
    /// Usage: `tell application "WhichSpace" to get current space label`
    @MainActor @objc var currentSpaceLabel: String {
        ScriptingHelpers.resolveCurrentLabel(
            appState: AppEnvironment.shared.appState,
            store: AppEnvironment.shared.store
        )
    }
}
