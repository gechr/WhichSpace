import AppKit

// MARK: - HotKeyProvider

/// Abstracts CGS symbolic hot key APIs for testability.
protocol HotKeyProvider: Sendable {
    func getHotKeyValue(for hotKey: CGSSymbolicHotKey) -> (keyChar: UniChar, keyCode: CGKeyCode, flags: UInt64)?
    func isHotKeyEnabled(_ hotKey: CGSSymbolicHotKey) -> Bool
    func setHotKeyEnabled(_ hotKey: CGSSymbolicHotKey, enabled: Bool)
}

// MARK: - CGSHotKeyProvider

/// Default implementation that calls the private CGS APIs.
struct CGSHotKeyProvider: HotKeyProvider {
    /// Returns true if the CGS symbolic hot key APIs are available at runtime.
    static var isAvailable: Bool {
        guard let handle = dlopen(nil, RTLD_LAZY) else {
            return false
        }
        defer { dlclose(handle) }
        return dlsym(handle, "CGSGetSymbolicHotKeyValue") != nil
    }

    func getHotKeyValue(for hotKey: CGSSymbolicHotKey) -> (keyChar: UniChar, keyCode: CGKeyCode, flags: UInt64)? {
        var keyCode: CGKeyCode = 0
        var flags: CGSModifierFlags = 0

        let error = CGSGetSymbolicHotKeyValue(hotKey, nil, &keyCode, &flags)
        guard error == .success else {
            return nil
        }
        return (0, keyCode, flags)
    }

    func isHotKeyEnabled(_ hotKey: CGSSymbolicHotKey) -> Bool {
        CGSIsSymbolicHotKeyEnabled(hotKey)
    }

    func setHotKeyEnabled(_ hotKey: CGSSymbolicHotKey, enabled: Bool) {
        _ = CGSSetSymbolicHotKeyEnabled(hotKey, enabled)
    }
}

// MARK: - Space Switching

struct SpaceSwitcher: @unchecked Sendable {
    private static let firstHotKey: UInt16 = 118
    private static let maxSupportedSpace = 16
    private static let yabaiExecutableName = "yabai"
    private static let accessibilityPromptOptionKey = "AXTrustedCheckOptionPrompt"

    private actor SharedState {
        private var binYabai: URL?
        private var hasPromptedForAccessibility = false

        func claimAccessibilityPrompt() -> Bool {
            guard !hasPromptedForAccessibility else {
                return false
            }
            hasPromptedForAccessibility = true
            return true
        }

        func cachedYabaiURL() -> URL? {
            binYabai
        }

        func cacheYabaiURL(_ url: URL) {
            binYabai = url
        }
    }

    private static let sharedState = SharedState()

    let hotKeyProvider: any HotKeyProvider

    init(hotKeyProvider: any HotKeyProvider = CGSHotKeyProvider()) {
        self.hotKeyProvider = hotKeyProvider
    }

    /// Resets WhichSpace Accessibility permission to clear stale TCC entries.
    static func resetAccessibilityPermission() {
        let tccutil = "/usr/bin/tccutil"
        guard FileManager.default.fileExists(atPath: tccutil),
              let bundleID = Bundle.main.bundleIdentifier
        else {
            return
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: tccutil)
        process.arguments = ["reset", "Accessibility", bundleID]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            NSLog("SpaceSwitcher: failed to reset accessibility permission: \(error)")
        }
    }

    func switchToSpace(_ space: Int) async {
        guard CGSHotKeyProvider.isAvailable else {
            NSLog("SpaceSwitcher: CGS hot key APIs unavailable; cannot switch spaces via keyboard shortcut")
            return
        }

        guard await Self.ensureAccessibilityPermission() else {
            NSLog("SpaceSwitcher: accessibility permission not granted; cannot switch")
            return
        }

        guard let event = eventForSwitching(to: space) else {
            NSLog("SpaceSwitcher: no event produced for space %d; aborting switch", space)
            return
        }
        Self.postSwitchEvents(with: event)
    }

    private static func ensureAccessibilityPermission() async -> Bool {
        if AXIsProcessTrusted() {
            return true
        }

        // Request permission once so the user sees the System Settings prompt
        if await sharedState.claimAccessibilityPrompt() {
            resetAccessibilityPermission()
            let options = [accessibilityPromptOptionKey: true] as CFDictionary
            _ = AXIsProcessTrustedWithOptions(options)
        }

        return false
    }

    func eventForSwitching(to space: Int) -> CGEvent? {
        guard (1 ... Self.maxSupportedSpace).contains(space) else {
            NSLog("SpaceSwitcher: space %d out of range (1-%d)", space, Self.maxSupportedSpace)
            return nil
        }

        let hotKey = CGSSymbolicHotKey(Self.firstHotKey + UInt16(space) - 1)

        guard let value = hotKeyProvider.getHotKeyValue(for: hotKey) else {
            NSLog("SpaceSwitcher: failed to get hot key value for space %d", space)
            return nil
        }

        if !hotKeyProvider.isHotKeyEnabled(hotKey) {
            hotKeyProvider.setHotKeyEnabled(hotKey, enabled: true)
        }

        guard let keyDownEvent = CGEvent(keyboardEventSource: nil, virtualKey: value.keyCode, keyDown: true) else {
            NSLog("SpaceSwitcher: failed to create CGEvent for space %d", space)
            return nil
        }

        keyDownEvent.flags = CGEventFlags(rawValue: value.flags)
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
    static func isYabaiAvailable() async -> Bool {
        await runYabai(arguments: ["-m", "query", "--spaces"], logPrefix: "yabai preflight")
    }

    /// Switches to space using yabai CLI. Returns true on success.
    static func switchToSpaceViaYabai(_ space: Int) async -> Bool {
        await runYabai(arguments: ["-m", "space", "--focus", "\(space)"], logPrefix: "yabai command")
    }

    /// Runs the yabai CLI with the given arguments. Returns true on success.
    private static func runYabai(arguments: [String], logPrefix: String) async -> Bool {
        guard let yabaiURL = await resolveYabaiExecutable() else {
            return false
        }

        let process = Process()
        process.executableURL = yabaiURL
        process.arguments = arguments

        let stderrPipe = Pipe()
        process.standardError = stderrPipe

        do {
            try process.run()

            guard let status = await runWithTimeout(process) else {
                NSLog("SpaceSwitcher: %@ timed out", logPrefix)
                return false
            }

            if status != 0 {
                let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
                if let stderr = String(data: stderrData, encoding: .utf8), !stderr.isEmpty {
                    NSLog("SpaceSwitcher: %@ stderr: %@", logPrefix, stderr)
                }
                return false
            }
            return true
        } catch {
            NSLog("SpaceSwitcher: %@ failed: \(error)", logPrefix)
            return false
        }
    }

    /// Runs a process with a timeout to avoid blocking the main thread indefinitely.
    /// Returns the termination status, or nil if the process timed out.
    private static func runWithTimeout(_ process: Process, timeout: Duration = .seconds(3)) async -> Int32? {
        await withTaskGroup(of: Int32?.self) { group in
            group.addTask {
                await withCheckedContinuation { continuation in
                    DispatchQueue.global(qos: .utility).async {
                        process.waitUntilExit()
                        continuation.resume(returning: process.terminationStatus)
                    }
                }
            }

            group.addTask {
                try? await Task.sleep(for: timeout)
                return nil
            }

            let result = await group.next()!
            group.cancelAll()

            if result == nil {
                process.terminate()
            }

            return result
        }
    }

    /// Resolve the absolute path to the yabai executable once to avoid PATH issues when launched from Finder/Login
    /// Items
    private static func resolveYabaiExecutable() async -> URL? {
        if let cached = await sharedState.cachedYabaiURL() {
            return cached
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
                await sharedState.cacheYabaiURL(candidate)
                return candidate
            }
        }

        NSLog("SpaceSwitcher: yabai not found; searched PATH (\(pathEnv)) and common locations")
        return nil
    }

    /// Activates an app that has a window on the given space ID (used for fullscreen spaces).
    /// macOS will automatically switch to the fullscreen space when the app is activated.
    /// Returns true if an app was found and activated.
    static func activateAppOnSpace(_ spaceID: Int) -> Bool {
        let conn = _CGSDefaultConnection()

        // Get all windows
        let options: CGWindowListOption = [.optionAll, .excludeDesktopElements]
        guard let windowList = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
            NSLog("SpaceSwitcher: failed to get window list")
            return false
        }

        // Find windows on the target space
        for window in windowList {
            // Filter to regular windows (layer 0)
            guard let layer = window[kCGWindowLayer as String] as? Int, layer == 0,
                  let windowNumber = window[kCGWindowNumber as String] as? Int,
                  let ownerPID = window[kCGWindowOwnerPID as String] as? Int32
            else {
                continue
            }

            // Check if this window is on the target space
            guard let spacesRef = SLSCopySpacesForWindows(conn, 0x7, [windowNumber] as CFArray) else {
                continue
            }
            let spaces = spacesRef.takeRetainedValue() as? [Int] ?? []

            if spaces.contains(spaceID) {
                // Found a window on the target space - activate its app
                if let app = NSRunningApplication(processIdentifier: ownerPID) {
                    let activated = app.activate(options: [])
                    if activated {
                        NSLog("SpaceSwitcher: activated \(app.localizedName ?? "app") for fullscreen space \(spaceID)")
                        return true
                    }
                }
            }
        }

        NSLog("SpaceSwitcher: no app found on space \(spaceID)")
        return false
    }
}
