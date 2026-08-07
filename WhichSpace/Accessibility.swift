import AppKit
import Observation
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
/// - The trust flag freezes at its launch value when permission changes in
///   System Settings while the app runs, so revocation detection probes the
///   live capability instead: creating an event tap is validated by
///   WindowServer on every call. The probe result only ever drives display
///   state and pane routing - it must never gate `requestPermission`, whose
///   `tccutil reset` would wipe a real grant on a false negative.
@MainActor
enum Accessibility {
    private static let logger = Logger(subsystem: "io.gechr.WhichSpace", category: "Accessibility")

    /// Undocumented HIServices notification posted when any app's AX permission changes
    private nonisolated static let permissionsChangedNotification = "com.apple.accessibility.api"
    /// System Settings, whose deactivation triggers a re-probe: permission
    /// edits happen there, and removing the app's entry from the
    /// Accessibility list fires no distributed notification at all
    private nonisolated static let systemSettingsBundleID = "com.apple.systempreferences"
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
    /// Poll cadence for the revocation watch - the notification skips some
    /// System Settings actions, so the probe also runs on a timer: every
    /// slice while the settings window is open, every 30 slices otherwise
    private nonisolated static let capabilityPollSlice: Duration = .seconds(2)
    private nonisolated static let capabilityPollSliceCount = 30

    private static var grantWatchTask: Task<Void, Never>?
    private static var revocationWatchTask: Task<Void, Never>?

    /// Whether the settings window is showing, where a stale banner is
    /// visible to the user rather than merely internal
    static var isSettingsWindowOpen = false

    /// Live capability state for UI that must notice a mid-session revoke
    static let liveStatus = AccessibilityLiveStatus()

    static var isTrusted: Bool {
        AXIsProcessTrusted()
    }

    /// Whether permission was revoked in System Settings while the app runs:
    /// the launch-frozen trust flag still reads trusted but the live
    /// capability is gone
    static var isRevoked: Bool {
        isTrusted && !liveStatus.capabilityTrusted
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
            refreshCapability()
            onGranted()
        }
    }

    // MARK: - Revocation Detection

    /// Starts the lifetime watch that keeps `liveStatus` current: a probe on
    /// every permissions-changed notification plus a sparse backstop poll.
    static func startRevocationWatch() {
        guard revocationWatchTask == nil else {
            return
        }
        refreshCapability()
        revocationWatchTask = Task {
            await withTaskGroup(of: Void.self) { group in
                group.addTask { await watchNotificationsForCapabilityChanges() }
                group.addTask { await watchSystemSettingsForCapabilityChanges() }
                group.addTask { await pollCapabilityChanges() }
                await group.waitForAll()
            }
        }
    }

    /// Recovery path for the revoked state. The probe re-registers the app in
    /// the Accessibility list when its entry was removed outright: a failed
    /// tap creation raises the system prompt, which recreates the entry, so
    /// the pane the user lands on has a toggle to flip rather than nothing.
    /// Never resets: the frozen trust flag still reads trusted in this state,
    /// so the request flow's reset could wipe a real grant on a probe false
    /// negative.
    static func recoverFromRevocation() {
        _ = capabilityProbe()
        openSettingsPane()
    }

    /// Re-probes on demand from UI surfaces. A no-op until the watch has
    /// started, so tests never run a real probe against host TCC state.
    static func refreshCapabilityIfWatching() {
        guard revocationWatchTask != nil else {
            return
        }
        refreshCapability()
    }

    /// Re-probes the live capability and records transitions in `liveStatus`.
    ///
    /// Only the trusted state is probed: creating an event tap without a list
    /// entry raises the system prompt, so probing an untrusted process would
    /// pop a dialog nobody asked for at launch. Untrusted still records the
    /// capability as absent - that is the truth, and the observable flipping
    /// is what re-renders a visible banner. The trust flag's own reading is
    /// not reliably observable in-process, so panes must not depend on it
    /// changing.
    static func refreshCapability() {
        let trusted = isTrusted ? capabilityProbe() : false
        if liveStatus.capabilityTrusted != trusted {
            logger.info("live capability changed: \(trusted ? "granted" : "revoked", privacy: .public)")
        }
        liveStatus.capabilityTrusted = trusted
    }

    /// Whether the process can create an event tap right now. Tap creation is
    /// validated live by WindowServer on every call, unlike the trust flag,
    /// which freezes at its launch value on external permission changes. The
    /// tap must be an active one - listen-only scroll taps do not require the
    /// permission - and is torn down immediately, so no event is affected.
    nonisolated static func capabilityProbe() -> Bool {
        let mask = CGEventMask(1 << CGEventType.scrollWheel.rawValue)
        guard let tap = CGEvent.tapCreate(
            tap: .cghidEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: { _, _, event, _ in Unmanaged.passUnretained(event) },
            userInfo: nil
        ) else {
            return false
        }
        let enabled = CGEvent.tapIsEnabled(tap: tap)
        CFMachPortInvalidate(tap)
        return enabled
    }

    private nonisolated static func watchNotificationsForCapabilityChanges() async {
        for await _ in distributedNotifications(named: permissionsChangedNotification) {
            try? await Task.sleep(for: notificationSettleDelay)
            if Task.isCancelled {
                return
            }
            await refreshCapability()
        }
    }

    private nonisolated static func watchSystemSettingsForCapabilityChanges() async {
        for await _ in workspaceAppDepartures(bundleID: systemSettingsBundleID) {
            try? await Task.sleep(for: notificationSettleDelay)
            if Task.isCancelled {
                return
            }
            await refreshCapability()
        }
    }

    /// Polls on a slice, probing every slice while the settings window is
    /// open and every `capabilityPollSliceCount` slices otherwise. The
    /// notification does not fire for every System Settings action, so a
    /// visible banner needs a cadence the user reads as immediate, while a
    /// closed window only needs the sparse backstop.
    private nonisolated static func pollCapabilityChanges() async {
        var slicesSinceProbe = 0
        while !Task.isCancelled {
            try? await Task.sleep(for: capabilityPollSlice)
            if Task.isCancelled {
                return
            }
            slicesSinceProbe += 1
            let watchingClosely = await isSettingsWindowOpen
            if watchingClosely || slicesSinceProbe >= capabilityPollSliceCount {
                slicesSinceProbe = 0
                await refreshCapability()
            }
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

    /// Yields whenever the given app deactivates or terminates.
    private nonisolated static func workspaceAppDepartures(bundleID: String) -> AsyncStream<Void> {
        AsyncStream { continuation in
            let center = NSWorkspace.shared.notificationCenter
            let names: [Notification.Name] = [
                NSWorkspace.didDeactivateApplicationNotification,
                NSWorkspace.didTerminateApplicationNotification,
            ]
            nonisolated(unsafe) let observers = names.map { name in
                center.addObserver(forName: name, object: nil, queue: .main) { notification in
                    let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
                    if app?.bundleIdentifier == bundleID {
                        continuation.yield()
                    }
                }
            }
            continuation.onTermination = { @Sendable _ in
                for observer in observers {
                    NSWorkspace.shared.notificationCenter.removeObserver(observer)
                }
            }
        }
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

/// Observable holder for the live capability reading, so SwiftUI panes
/// re-render when a revoke or re-grant lands mid-session. Display state
/// only - never a gate for `requestPermission`.
@MainActor
@Observable
final class AccessibilityLiveStatus {
    /// Whether the app could create an event tap at the last probe. Starts
    /// true so nothing changes behaviour before the watch first probes.
    fileprivate(set) var capabilityTrusted = true
}
