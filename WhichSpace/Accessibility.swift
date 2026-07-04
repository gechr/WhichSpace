import AppKit
import os.log

/// Accessibility permission handling.
///
/// - `tccutil reset` before prompting clears stale TCC entries keyed to a
///   previous code signature, followed by a settle delay because tccd
///   processes the reset asynchronously and silently ignores a prompt
///   request that races it.
/// - The system prompt (`AXIsProcessTrustedWithOptions`) is the primary
///   affordance: it is the only mechanism that automatically registers the
///   app in the Accessibility list with the toggle off.
/// - The prompt can be silently suppressed by tccd, so if no grant lands
///   shortly, deep-link the Accessibility pane directly as a fallback - the
///   user is never left with no path forward.
/// - Grant detection listens for the undocumented
///   `com.apple.accessibility.api` distributed notification with a settle
///   delay because the readable AX state lags the notification, plus a
///   polling backstop because the notification's firing behaviour is not
///   reliably characterised.
@MainActor
enum Accessibility {
    private static let logger = Logger(subsystem: "io.gechr.WhichSpace", category: "Accessibility")

    /// Undocumented HIServices notification posted when any app's AX permission changes
    private nonisolated static let permissionsChangedNotification = "com.apple.accessibility.api"
    private static let settingsPaneURL =
        "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
    private static let trustedCheckOptionPrompt = "AXTrustedCheckOptionPrompt"

    /// Wait after `tccutil reset` before prompting - tccd ignores a prompt that races the reset
    private static let resetSettleDelay: Duration = .milliseconds(500)
    /// Wait after a permissions-changed notification before re-reading the (lagging) AX state
    private static let notificationSettleDelay: Duration = .milliseconds(250)
    /// How long to wait for the system prompt to produce a grant before opening the pane
    private static let suppressedPromptFallbackDelay: Duration = .seconds(3)
    /// Backstop poll cadence and bound (2 minutes total)
    private nonisolated static let pollInterval: Duration = .seconds(1)
    private nonisolated static let pollLimit = 120

    private static var grantWatchTask: Task<Void, Never>?

    static var isTrusted: Bool {
        AXIsProcessTrusted()
    }

    /// Requests accessibility permission and invokes `onGranted` once the user grants it.
    /// Safe to call repeatedly; a new request replaces any in-flight grant watch.
    static func requestPermission(onGranted: @escaping @MainActor () -> Void) {
        Task {
            if await resetAndPrompt() {
                logger.info("permission already granted after prompt")
                onGranted()
                return
            }
            watchForGrant(onGranted: onGranted)
            try? await Task.sleep(for: suppressedPromptFallbackDelay)
            if !AXIsProcessTrusted() {
                logger.info("no grant after prompt; opening Accessibility pane")
                openSettingsPane()
            }
        }
    }

    /// Resets stale TCC state, waits for tccd to settle, then requests the
    /// system prompt. Returns the resulting trusted state.
    static func resetAndPrompt() async -> Bool {
        await resetPermission()
        try? await Task.sleep(for: resetSettleDelay)
        let options = [trustedCheckOptionPrompt: true] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    static func openSettingsPane() {
        guard let url = URL(string: settingsPaneURL) else {
            return
        }
        NSWorkspace.shared.open(url)
    }

    /// Resets the app's Accessibility TCC entry to clear grants keyed to a
    /// previous code signature. Waits for `tccutil` without blocking.
    nonisolated static func resetPermission() async {
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
        await withCheckedContinuation { continuation in
            process.terminationHandler = { _ in
                continuation.resume()
            }
            do {
                try process.run()
            } catch {
                process.terminationHandler = nil
                NSLog("Accessibility: failed to reset permission: \(error)")
                continuation.resume()
            }
        }
    }

    // MARK: - Grant Detection

    private static func watchForGrant(onGranted: @escaping @MainActor () -> Void) {
        grantWatchTask?.cancel()
        grantWatchTask = Task {
            let granted = await withTaskGroup(of: Bool.self) { group in
                group.addTask { await watchNotificationsForGrant() }
                group.addTask { await pollForGrant() }
                // First child to finish decides: a grant (true) or the poll
                // backstop timing out (false)
                let result = await group.next() ?? false
                group.cancelAll()
                return result
            }
            guard granted, !Task.isCancelled else {
                return
            }
            logger.info("permission granted")
            onGranted()
        }
    }

    private nonisolated static func watchNotificationsForGrant() async -> Bool {
        for await _ in distributedNotifications(named: permissionsChangedNotification) {
            try? await Task.sleep(for: notificationSettleDelay)
            if Task.isCancelled {
                return false
            }
            if AXIsProcessTrusted() {
                return true
            }
        }
        return false
    }

    private nonisolated static func pollForGrant() async -> Bool {
        for _ in 0 ..< pollLimit {
            try? await Task.sleep(for: pollInterval)
            if Task.isCancelled {
                return false
            }
            if AXIsProcessTrusted() {
                return true
            }
        }
        return false
    }

    private nonisolated static func distributedNotifications(named name: String) -> AsyncStream<Void> {
        AsyncStream { continuation in
            nonisolated(unsafe) let observer = DistributedNotificationCenter.default().addObserver(
                forName: NSNotification.Name(name), object: nil, queue: .main
            ) { _ in
                continuation.yield()
            }
            continuation.onTermination = { @Sendable _ in
                DistributedNotificationCenter.default().removeObserver(observer)
            }
        }
    }
}
