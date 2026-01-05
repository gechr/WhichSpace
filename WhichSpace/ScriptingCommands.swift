import Cocoa

/// Command handler for AppleScript "current space number" command.
/// Usage: `tell application "WhichSpace" to get current space number`
@MainActor
final class CurrentSpaceNumberCommand: NSScriptCommand {
    override func performDefaultImplementation() -> Any? {
        AppState.shared.currentSpace
    }
}

/// Command handler for AppleScript "current space label" command.
/// Usage: `tell application "WhichSpace" to get current space label`
@MainActor
final class CurrentSpaceLabelCommand: NSScriptCommand {
    override func performDefaultImplementation() -> Any? {
        AppState.shared.currentSpaceLabel
    }
}

/// Extension to make the application scriptable for property access.
extension NSApplication {
    /// Returns the current space number (1-based index).
    /// Usage: `tell application "WhichSpace" to get current space number`
    @MainActor @objc var currentSpaceNumber: Int {
        AppState.shared.currentSpace
    }

    /// Returns the current space label (e.g. "1", "2", "F" for fullscreen).
    /// Usage: `tell application "WhichSpace" to get current space label`
    @MainActor @objc var currentSpaceLabel: String {
        AppState.shared.currentSpaceLabel
    }
}
