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
final class CurrentSpaceLabelCommand: NSScriptCommand {
    override func performDefaultImplementation() -> Any? {
        runScriptQueryOnMain {
            AppEnvironment.shared.appState.currentSpaceLabel
        }
    }
}

/// Extension to make the application scriptable for property access.
extension NSApplication {
    /// Returns the current space number (1-based index).
    /// Usage: `tell application "WhichSpace" to get current space number`
    @MainActor @objc var currentSpaceNumber: Int {
        AppEnvironment.shared.appState.currentSpace
    }

    /// Returns the current space label (e.g. "1", "2", "F" for fullscreen).
    /// Usage: `tell application "WhichSpace" to get current space label`
    @MainActor @objc var currentSpaceLabel: String {
        AppEnvironment.shared.appState.currentSpaceLabel
    }
}
