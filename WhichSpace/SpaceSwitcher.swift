import AppKit

// MARK: - Space Switching

enum SpaceSwitcher {
    private static let firstHotKey: UInt16 = 118
    private static let maxSupportedSpace = 16
    private static let yabaiExecutableName = "yabai"

    private static var binYabai: URL?
    private static var hasPromptedForAccessibility = false

    static func switchToSpace(_ space: Int) {
        guard ensureAccessibilityPermission() else {
            NSLog("SpaceSwitcher: accessibility permission not granted; cannot switch")
            return
        }

        guard let event = eventForSwitching(to: space) else {
            return
        }
        postSwitchEvents(with: event)
    }

    private static func ensureAccessibilityPermission() -> Bool {
        if AXIsProcessTrusted() {
            return true
        }

        // Request permission once so the user sees the System Settings prompt
        if !hasPromptedForAccessibility {
            let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
            _ = AXIsProcessTrustedWithOptions(options)
            hasPromptedForAccessibility = true
        }

        return false
    }

    private static func eventForSwitching(to space: Int) -> CGEvent? {
        guard (1 ... maxSupportedSpace).contains(space) else {
            return nil
        }

        let hotKey = CGSSymbolicHotKey(firstHotKey + UInt16(space) - 1)
        var keyCode: CGKeyCode = 0
        var flags: CGSModifierFlags = 0

        let error = CGSGetSymbolicHotKeyValue(hotKey, nil, &keyCode, &flags)
        guard error == .success else {
            return nil
        }

        if !CGSIsSymbolicHotKeyEnabled(hotKey) {
            _ = CGSSetSymbolicHotKeyEnabled(hotKey, true)
        }

        guard let keyDownEvent = CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: true) else {
            return nil
        }

        keyDownEvent.flags = CGEventFlags(rawValue: flags)
        return keyDownEvent
    }

    private static func postSwitchEvents(with keyDownEvent: CGEvent) {
        let keyCodeValue = CGKeyCode(keyDownEvent.getIntegerValueField(.keyboardEventKeycode))
        guard let keyUpEvent = CGEvent(keyboardEventSource: nil, virtualKey: keyCodeValue, keyDown: false) else {
            return
        }

        // Send the shortcut command to get Mission Control to switch spaces
        keyDownEvent.post(tap: .cghidEventTap)
        keyUpEvent.flags = []
        keyUpEvent.post(tap: .cghidEventTap)
    }

    /// Returns true if the yabai CLI is available and responding
    static func isYabaiAvailable() -> Bool {
        guard let yabaiURL = resolveYabaiExecutable() else {
            return false
        }

        let process = Process()
        process.executableURL = yabaiURL
        process.arguments = ["-m", "query", "--spaces"]

        let stderrPipe = Pipe()
        process.standardError = stderrPipe

        do {
            try process.run()

            guard let status = runWithTimeout(process) else {
                NSLog("SpaceSwitcher: yabai preflight timed out")
                return false
            }

            if status != 0 {
                let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
                if let stderr = String(data: stderrData, encoding: .utf8), !stderr.isEmpty {
                    NSLog("SpaceSwitcher: yabai preflight stderr: %@", stderr)
                }
                return false
            }
            return true
        } catch {
            NSLog("SpaceSwitcher: yabai preflight failed: \(error)")
            return false
        }
    }

    /// Switches to space using yabai CLI. Returns true on success.
    static func switchToSpaceViaYabai(_ space: Int) -> Bool {
        guard let yabaiURL = resolveYabaiExecutable() else {
            return false
        }

        let process = Process()
        process.executableURL = yabaiURL
        process.arguments = ["-m", "space", "--focus", "\(space)"]

        let stderrPipe = Pipe()
        process.standardError = stderrPipe

        do {
            try process.run()

            guard let status = runWithTimeout(process) else {
                NSLog("SpaceSwitcher: yabai command timed out")
                return false
            }

            if status != 0 {
                let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
                if let stderr = String(data: stderrData, encoding: .utf8), !stderr.isEmpty {
                    NSLog("SpaceSwitcher: yabai stderr: %@", stderr)
                }
                return false
            }
            return true
        } catch {
            NSLog("SpaceSwitcher: yabai command failed: \(error)")
            return false
        }
    }

    /// Runs a process with a timeout to avoid blocking the main thread indefinitely
    /// Returns the termination status, or nil if the process timed out
    private static func runWithTimeout(_ process: Process, timeout: TimeInterval = 3) -> Int32? {
        let semaphore = DispatchSemaphore(value: 0)
        DispatchQueue.global().async {
            process.waitUntilExit()
            semaphore.signal()
        }

        if semaphore.wait(timeout: .now() + timeout) == .timedOut {
            process.terminate()
            return nil
        }

        return process.terminationStatus
    }

    /// Resolve the absolute path to the yabai executable once to avoid PATH issues when launched from Finder/Login
    /// Items
    private static func resolveYabaiExecutable() -> URL? {
        if let binYabai {
            return binYabai
        }

        let pathEnv = ProcessInfo.processInfo.environment["PATH"] ?? ""
        var searchPaths = ["/opt/homebrew/bin", "/usr/local/bin"]
        searchPaths.append(contentsOf: pathEnv.split(separator: ":").map(String.init))

        var seen = Set<String>()
        for path in searchPaths where !path.isEmpty {
            if seen.contains(path) {
                continue
            }
            seen.insert(path)

            let candidate = URL(fileURLWithPath: path, isDirectory: true)
                .appendingPathComponent(yabaiExecutableName)
            if FileManager.default.isExecutableFile(atPath: candidate.path) {
                binYabai = candidate
                return candidate
            }
        }

        NSLog("SpaceSwitcher: yabai not found; searched PATH (\(pathEnv)) and common locations")
        return nil
    }
}
