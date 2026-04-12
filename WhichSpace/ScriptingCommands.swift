import Cocoa

/// Runs a synchronous script query on the main thread.
/// AppleScript command handlers are synchronous, so we bridge explicitly.
private func runScriptQueryOnMain<T: Sendable>(_ query: @MainActor () -> T) -> T {
    if Thread.isMainThread {
        return MainActor.assumeIsolated(query)
    }

    return DispatchQueue.main.sync {
        MainActor.assumeIsolated(query)
    }
}

/// Command handler for AppleScript "current space number" command.
/// Usage: `tell application "WhichSpace" to get current space number`
final class CurrentSpaceNumberCommand: NSScriptCommand {
    override func performDefaultImplementation() -> Any? {
        runScriptQueryOnMain {
            AppEnvironment.shared.appState.currentSpace
        }
    }
}

/// Command handler for AppleScript "current space label" command.
/// Usage: `tell application "WhichSpace" to get current space label`
/// Returns the custom label if one is set, otherwise the default space label.
final class CurrentSpaceLabelCommand: NSScriptCommand {
    override func performDefaultImplementation() -> Any? {
        runScriptQueryOnMain {
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

        let result = runScriptQueryOnMain {
            ScriptingHelpers.switchToSpace(
                number: spaceNumber,
                appState: AppEnvironment.shared.appState
            )
        }

        switch result {
        case .success:
            return nil
        case let .failure(message):
            scriptErrorNumber = errOSACantAssign
            scriptErrorString = message
            return nil
        }
    }
}

// MARK: - Scripting Helpers

@MainActor
enum ScriptingHelpers {
    enum SwitchResult {
        case success
        case failure(String)
    }

    static func switchToSpace(number: Int, appState: AppState) -> SwitchResult {
        guard AXIsProcessTrusted() else {
            return .failure(
                "Accessibility permission required. Grant it in System Settings → Privacy & Security → Accessibility."
            )
        }
        let entries = appState.allSpaceEntries
        guard !entries.isEmpty else {
            return .failure("No spaces available.")
        }
        guard number >= 1, number <= entries.count else {
            return .failure("Space \(number) does not exist (1-\(entries.count)).")
        }
        guard number != appState.currentSpace else {
            return .success
        }
        let entry = entries[number - 1]
        if entry.regularIndex != nil {
            SpaceSwitcher.switchToSpace(id: entry.id)
        } else {
            _ = SpaceSwitcher.activateAppOnSpace(entry.id)
        }
        return .success
    }

    static func resolveCurrentLabel(appState: AppState, store: DefaultsStore) -> String {
        if let customLabel = SpacePreferences.label(
            forSpace: appState.currentSpace,
            display: appState.currentDisplayID,
            store: store
        ), !customLabel.isEmpty {
            return LabelTemplate.resolve(customLabel, space: appState.currentSpace)
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
