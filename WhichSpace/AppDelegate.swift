import AppKit
import Defaults
import LaunchAtLogin
import Observation
import QuartzCore
@preconcurrency import Sparkle

// MARK: - NSEvent Right-Click Detection

extension NSEvent {
    var isRightClick: Bool {
        type == .rightMouseUp || modifierFlags.contains(.control)
    }
}

// MARK: - Launch at Login Protocol

/// Protocol for abstracting LaunchAtLogin for testability
protocol LaunchAtLoginProvider {
    var isEnabled: Bool { get set }
}

/// Default implementation using the actual LaunchAtLogin library
struct DefaultLaunchAtLoginProvider: LaunchAtLoginProvider {
    var isEnabled: Bool {
        get { LaunchAtLogin.isEnabled }
        set { LaunchAtLogin.isEnabled = newValue }
    }
}

// MARK: - Confirmation Alert

/// Closure that shows a confirmation alert and returns whether the user confirmed.
typealias ConfirmAction = (
    _ message: String, _ detail: String, _ confirmTitle: String, _ isDestructive: Bool
) -> Bool

// MARK: - Hidden Icon Warning State

struct HiddenIconWarningState {
    private var hiddenSince: Date?
    private var warnedForCurrentHide = false

    mutating func shouldWarn(
        hiddenNow: Bool,
        suppressed: Bool,
        now: Date,
        warningDelay: TimeInterval
    ) -> Bool {
        guard hiddenNow else {
            hiddenSince = nil
            warnedForCurrentHide = false
            return false
        }

        if hiddenSince == nil {
            hiddenSince = now
        }
        guard !warnedForCurrentHide, !suppressed, let hiddenSince else {
            return false
        }
        guard now.timeIntervalSince(hiddenSince) >= warningDelay else {
            return false
        }

        warnedForCurrentHide = true
        return true
    }
}

// MARK: - App Delegate

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, SPUStandardUserDriverDelegate {
    // MARK: - Properties

    private let confirmAction: ConfirmAction
    private let appState: AppState
    private let missionControlNotificationSender: (CFString) -> Void
    private(set) var actionHandler: ActionHandler!
    private var menuBuilder: MenuBuilder!
    private var middleClickMonitor: Any?
    private var statusBarItem: NSStatusItem!

    /// Observers/state for detecting when our menu bar icon is active but not
    /// actually on screen (truncated when the menu bar is full, or hidden by
    /// the notch). See `startObservingIconOcclusion()`.
    private var occlusionPollTimer: Timer?
    private var occlusionObserver: NSObjectProtocol?
    private weak var observedOcclusionWindow: NSWindow?
    private var screenParamsObserver: NSObjectProtocol?
    private var hiddenIconWarningState = HiddenIconWarningState()

    private var isPickingForeground = true
    private var isPreviewingIcon = false
    /// Defers hover-end restores so sweeping across preview rows doesn't
    /// commit a base-icon frame between consecutive previews (the restore
    /// would win the vsync and the intermediate previews would never show)
    private var restoreTimer: Timer?
    /// Latest preview request waiting for the next throttle slot
    private var pendingPreviewApply: (() -> Void)?
    /// Non-nil while inside a one-frame preview coalescing window
    private var previewThrottleTimer: Timer?
    private var launchAtLogin: LaunchAtLoginProvider
    private var preferenceObservationTasks: [Task<Void, Never>] = []
    private var updaterController: SPUStandardUpdaterController!

    private(set) var observationTask: Task<Void, Never>?
    private(set) var statusBarIconUpdateCount = 0
    private(set) var statusMenu: NSMenu!

    /// Convenience accessor for the store via appState
    private var store: DefaultsStore {
        appState.store
    }

    private static let hiddenIconPollInterval: TimeInterval = 3.0
    private static let hiddenIconWarningDelay: TimeInterval = 2.0

    // MARK: - Initialization

    /// Default initializer for production use
    override init() {
        let env = AppEnvironment.shared
        appState = env.appState
        confirmAction = {
            ConfirmationAlert(message: $0, detail: $1, confirmTitle: $2, isDestructive: $3).runModal()
        }
        launchAtLogin = DefaultLaunchAtLoginProvider()
        missionControlNotificationSender = { notification in
            _ = CoreDockSendNotification(notification)
        }
        super.init()
        configureActionHandler()
    }

    /// Testable initializer with dependency injection
    init(
        appState: AppState,
        confirmAction: @escaping ConfirmAction,
        launchAtLogin: LaunchAtLoginProvider = DefaultLaunchAtLoginProvider(),
        missionControlNotificationSender: @escaping (CFString) -> Void = { notification in
            _ = CoreDockSendNotification(notification)
        }
    ) {
        self.appState = appState
        self.confirmAction = confirmAction
        self.launchAtLogin = launchAtLogin
        self.missionControlNotificationSender = missionControlNotificationSender
        super.init()
        configureActionHandler()
    }

    private func configureActionHandler() {
        actionHandler = ActionHandler(
            appState: appState,
            confirmAction: confirmAction,
            launchAtLogin: launchAtLogin,
            onStatusBarIconNeedsUpdate: { [weak self] in
                self?.updateStatusBarIcon()
            },
            onStatusBarVisibilityNeedsUpdate: { [weak self] in
                self?.updateStatusBarVisibility()
            },
            onCheckForUpdates: { [weak self] in
                NSApp.activate(ignoringOtherApps: true)
                self?.updaterController.checkForUpdates(nil)
            }
        )
    }

    // MARK: - NSApplicationDelegate

    func applicationDidFinishLaunching(_: Notification) {
        // Skip full app setup when running as a test host
        guard ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil else {
            return
        }
        AppMover.moveIfNecessary(appName: AppInfo.appName)
        NSApp.setActivationPolicy(.accessory)
        statusBarItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        updaterController = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: self
        )
        configureMenuBarIcon()
        appState.renderer.onIconNeedsUpdate = { [weak self] in
            self?.updateStatusBarIcon()
        }
        startObservingAppState()
        startObservingSpaceChanges()
        startObservingPreferences()
        updateIconOcclusionMonitoring()

        // Disable click-to-switch if accessibility permission was revoked
        if store.clickToSwitchSpaces, !AXIsProcessTrusted() {
            SettingsConstraints.setClickToSwitchSpaces(false, store: store)
        }

        // Warm the symbol/emoji catalogs off-main so the first menu open doesn't
        // pay for instantiating ~600 NSImages on the main thread
        Task.detached(priority: .utility) {
            _ = ItemData.symbols.count
            _ = ItemData.emojis.count
        }
    }

    func applicationShouldHandleReopen(_: NSApplication, hasVisibleWindows _: Bool) -> Bool {
        // Prevent macOS/SwiftUI from opening any windows when the app is relaunched
        false
    }

    // MARK: - Observation

    /// Test hook to start the observation task. In production, this is called from applicationDidFinishLaunching.
    ///
    /// Uses `withCheckedContinuation` to suspend until `statusBarIcon` changes, avoiding
    /// wasteful polling. The `withObservationTracking` closure fires `onChange` once per
    /// change, so we loop to re-register after each update.
    func startObservingAppState() {
        observationTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else {
                    return
                }
                await withCheckedContinuation { continuation in
                    _ = withObservationTracking {
                        self.appState.statusBarIcon
                    } onChange: {
                        continuation.resume()
                    }
                }
                await MainActor.run {
                    self.updateStatusBarIcon()
                }
            }
        }
    }

    /// Cancels the observation task. Call this in test teardown to prevent leaks.
    func stopObservingAppState() {
        observationTask?.cancel()
        observationTask = nil
        stopObservingPreferences()
    }

    private func stopObservingPreferences() {
        for task in preferenceObservationTasks {
            task.cancel()
        }
        preferenceObservationTasks.removeAll()
    }

    /// Starts observing space change notifications to play sound
    private func startObservingSpaceChanges() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleSpaceDidChange),
            name: .spaceDidChange,
            object: nil
        )
    }

    @objc private func handleSpaceDidChange() {
        // Play sound if enabled (copy to allow overlapping sounds)
        let soundName = store.soundName
        guard !soundName.isEmpty else {
            return
        }
        guard let sound = NSSound(named: NSSound.Name(soundName))?.copy() as? NSSound else {
            NSLog("AppDelegate: failed to load sound '%@'", soundName)
            return
        }
        sound.play()
    }

    /// Observes preference changes that affect the status bar icon using Defaults async streams
    private func startObservingPreferences() {
        stopObservingPreferences()

        let iconKeys: [Defaults._AnyKey] = [
            store.keyFor(KeySpecs.showAllSpaces),
            store.keyFor(KeySpecs.showAllDisplays),
            store.keyFor(KeySpecs.dimInactiveSpaces),
            store.keyFor(KeySpecs.hideEmptySpaces),
            store.keyFor(KeySpecs.hideFullscreenApps),
            store.keyFor(KeySpecs.hideSingleSpace),
            store.keyFor(KeySpecs.uniqueIconsPerDisplay),
            store.keyFor(KeySpecs.localSpaceNumbers),
            store.keyFor(KeySpecs.sizeScale),
            store.keyFor(KeySpecs.paddingScale),
            store.keyFor(KeySpecs.separatorColor),
            store.keyFor(KeySpecs.spaceBadges),
            store.keyFor(KeySpecs.spaceColors),
            store.keyFor(KeySpecs.spaceIconStyles),
            store.keyFor(KeySpecs.spaceSymbols),
            store.keyFor(KeySpecs.spaceFonts),
            store.keyFor(KeySpecs.spaceLabels),
            store.keyFor(KeySpecs.spaceLabelStyles),
            store.keyFor(KeySpecs.spaceSkinTones),
            store.keyFor(KeySpecs.displaySpaceBadges),
            store.keyFor(KeySpecs.displaySpaceColors),
            store.keyFor(KeySpecs.displaySpaceIconStyles),
            store.keyFor(KeySpecs.displaySpaceSymbols),
            store.keyFor(KeySpecs.displaySpaceFonts),
            store.keyFor(KeySpecs.displaySpaceLabels),
            store.keyFor(KeySpecs.displaySpaceLabelStyles),
            store.keyFor(KeySpecs.displaySpaceSkinTones),
        ]

        preferenceObservationTasks.append(Task { [weak self] in
            for await _ in Defaults.updates(iconKeys, initial: false) {
                // 16ms ≈ one frame at 60 FPS; coalesces rapid changes into a single update
                try? await Task.sleep(for: .milliseconds(16))
                guard !Task.isCancelled
                else { return }
                // Covers defaults changes that bypass DefaultsStore (and its mutation
                // counter), e.g. external `defaults write`
                self?.store.invalidateCachedValues()
                self?.appState.renderer.invalidateIconCache()
                self?.updateStatusBarIcon()
            }
        })

        let localSpaceNumbersKey = store.keyFor(KeySpecs.localSpaceNumbers)
        preferenceObservationTasks.append(Task { [weak self] in
            for await _ in Defaults.updates(localSpaceNumbersKey, initial: false) {
                guard !Task.isCancelled
                else { return }
                self?.appState.forceSpaceUpdate()
            }
        })

        // Start/stop occlusion monitoring when the opt-out preference changes
        // (e.g. a settings reset re-enables it) without needing a relaunch.
        let suppressHiddenIconKey = store.keyFor(KeySpecs.suppressHiddenIconWarning)
        preferenceObservationTasks.append(Task { [weak self] in
            for await _ in Defaults.updates(suppressHiddenIconKey, initial: false) {
                guard !Task.isCancelled
                else { return }
                self?.store.invalidateCachedValues()
                self?.updateIconOcclusionMonitoring()
            }
        })
    }

    // MARK: - SPUStandardUserDriverDelegate

    nonisolated var supportsGentleScheduledUpdateReminders: Bool {
        true
    }

    nonisolated func standardUserDriverWillHandleShowingUpdate(
        _: Bool,
        forUpdate _: SUAppcastItem,
        state _: SPUUserUpdateState
    ) {
        DispatchQueue.main.async {
            NSApp.setActivationPolicy(.regular)
        }
    }

    nonisolated func standardUserDriverWillFinishUpdateSession() {
        DispatchQueue.main.async {
            NSApp.setActivationPolicy(.accessory)
        }
    }

    // MARK: - Menu Configuration

    /// Test hook to configure the menu bar icon. In production, this is called from applicationDidFinishLaunching.
    func configureMenuBarIcon() {
        menuBuilder = MenuBuilder(appState: appState, store: store)
        statusMenu = menuBuilder.buildMenu(target: actionHandler, menuDelegate: self, actionDelegate: self)
        statusMenu.delegate = self
        statusBarItem?.button?.toolTip = AppInfo.appName
        statusBarItem?.button?.target = self
        statusBarItem?.button?.action = #selector(statusBarButtonClicked(_:))
        statusBarItem?.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
        // Remove any previous monitor: this is re-invoked by tests
        if let middleClickMonitor {
            NSEvent.removeMonitor(middleClickMonitor)
        }
        middleClickMonitor = NSEvent.addLocalMonitorForEvents(matching: .otherMouseUp) { [weak self] event in
            self?.handleMiddleClickEvent(event, in: self?.statusBarItem?.button) ?? event
        }
        updateStatusBarIcon()
    }

    /// Handles middle-click on the status bar item and triggers Mission Control.
    /// Returns nil when the event is consumed; otherwise returns the original event.
    func handleMiddleClickEvent(_ event: NSEvent, in button: NSView?) -> NSEvent? {
        guard event.buttonNumber == 2,
              let button,
              button.isMousePoint(button.convert(event.locationInWindow, from: nil), in: button.bounds)
        else {
            return event
        }
        missionControlNotificationSender("com.apple.expose.awake" as CFString)
        return nil
    }

    @objc private func statusBarButtonClicked(_ button: NSStatusBarButton) {
        guard let event = NSApp.currentEvent else {
            return
        }

        if event.isRightClick {
            guard let button = statusBarItem?.button else {
                return
            }
            let position = NSPoint(x: 0, y: button.bounds.height + 5)
            statusMenu.popUp(positioning: nil, at: position, in: button)
        } else {
            handleLeftClick(event, button: button)
        }
    }

    private func handleLeftClick(_ event: NSEvent, button: NSStatusBarButton) {
        // Auto-enable click-to-switch on first left click
        if !store.clickToSwitchSpaces {
            if !SettingsConstraints.setClickToSwitchSpaces(true, store: store) {
                // Accessibility permission not granted - trigger the permission flow
                actionHandler.requestAccessibilityForClickToSwitch()
                return
            }
        }

        // If user denied accessibility permission, disable the setting
        guard AXIsProcessTrusted() else {
            SettingsConstraints.setClickToSwitchSpaces(false, store: store)
            return
        }

        let layout = appState.statusBarLayout()
        guard !layout.slots.isEmpty else {
            return
        }

        let location = button.convert(event.locationInWindow, from: nil)
        let clickX = Double(location.x)

        // Use StatusBarLayout hit testing
        guard let slot = layout.slot(at: clickX) else {
            return
        }

        // Fullscreen spaces don't have a targetSpace - activate the app instead
        if slot.targetSpace == nil {
            _ = SpaceSwitcher.activateAppOnSpace(slot.spaceID)
            return
        }

        SpaceSwitcher.switchToSpace(id: slot.spaceID)
    }

    // MARK: - Status Bar

    func updateStatusBarIcon() {
        guard !isPreviewingIcon else {
            return
        }
        statusBarIconUpdateCount += 1
        guard let statusBarItem else {
            return
        }
        let icon = appState.statusBarIcon
        // Skip the assignment and forced redraw when the cached icon is
        // already installed (e.g. every submenu open triggers an update)
        guard statusBarItem.button?.image !== icon else {
            updateStatusBarVisibility()
            return
        }
        statusBarItem.length = icon.size.width
        statusBarItem.button?.image = icon
        // Force immediate redraw - during menu tracking AppKit defers display
        // for the status bar button's window, causing visible preview lag.
        statusBarItem.button?.display()
        // Force the Core Animation commit (see showPreviewIcon)
        CATransaction.flush()
        updateStatusBarVisibility()
    }

    private func updateBadgeMenuVisibility() {
        let symbolIsActive = appState.currentSymbol != nil
        statusMenu.item(withTag: MenuTag.badgeMenuItem.rawValue)?.isHidden = symbolIsActive
    }

    private func updateStatusBarVisibility() {
        guard let statusBarItem else {
            return
        }
        guard store.hideSingleSpace else {
            statusBarItem.isVisible = true
            return
        }
        // Hide if there's only one regular (non-fullscreen) space across all displays
        statusBarItem.isVisible = appState.regularSpaceCount > 1
    }

    // MARK: - Hidden Icon Detection

    /// Detects when our status item is active but not actually visible on screen
    /// (macOS truncates icons when the menu bar is full, and the notch can swallow
    /// them) and warns the user, who otherwise assumes the app failed to launch.
    ///
    /// `NSStatusItem.isVisible` reflects intent, not reality, so it can't answer
    /// this. Instead the status button lives in its own window whose
    /// `occlusionState` drops `.visible` when the item is clipped or notch-hidden.
    /// This is the same signal Tailscale and VirtualBuddy use. Occlusion events
    /// are used as hints, with polling as the source of truth because the visible
    /// direction is not consistently delivered.
    /// Starts or stops occlusion monitoring based on the opt-out preference.
    /// When the user has ticked "Don't show this again" there is nothing left to
    /// warn about, so we tear the poll and observers down entirely - WhichSpace is
    /// meant to be near-zero when idle. Idempotent; safe to call on any change.
    private func updateIconOcclusionMonitoring() {
        if store.suppressHiddenIconWarning {
            stopObservingIconOcclusion()
        } else {
            startObservingIconOcclusion()
        }
    }

    private func startObservingIconOcclusion() {
        guard occlusionPollTimer == nil else {
            return
        }
        let timer = Timer(timeInterval: Self.hiddenIconPollInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.checkIconOcclusion()
            }
        }
        // A generous tolerance lets macOS coalesce this low-frequency wakeup with
        // other timers rather than scheduling a dedicated one - a large energy win
        // for a poll that only needs to be roughly periodic.
        timer.tolerance = Self.hiddenIconPollInterval * 0.5
        // .common so it keeps firing during menu tracking / event loops.
        RunLoop.main.add(timer, forMode: .common)
        occlusionPollTimer = timer
        screenParamsObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.checkIconOcclusion()
            }
        }
        // Catch launch-into-hidden without waiting for the first timer tick.
        checkIconOcclusion()
    }

    private func stopObservingIconOcclusion() {
        occlusionPollTimer?.invalidate()
        occlusionPollTimer = nil
        if let screenParamsObserver {
            NotificationCenter.default.removeObserver(screenParamsObserver)
            self.screenParamsObserver = nil
        }
        if let occlusionObserver {
            NotificationCenter.default.removeObserver(occlusionObserver)
            self.occlusionObserver = nil
        }
        observedOcclusionWindow = nil
        // Reset so a later re-enable starts from a clean visible->hidden edge.
        hiddenIconWarningState = HiddenIconWarningState()
    }

    private func checkIconOcclusion(now: Date = Date()) {
        guard let statusBarItem, let button = statusBarItem.button, let window = button.window else {
            return
        }
        observeOcclusionChanges(for: window)

        // Hidden = we intend to show the icon (`isVisible`, which WhichSpace turns
        // off deliberately on a single Space) but its window is fully occluded.
        // `.contains(.visible)` is the documented bitfield check.
        let hiddenByOcclusion = !window.occlusionState.contains(.visible)
        let hiddenByNotch = statusButtonIntersectsNotchGap(button, in: window)
        let hiddenNow = statusBarItem.isVisible && (hiddenByOcclusion || hiddenByNotch)

        guard hiddenIconWarningState.shouldWarn(
            hiddenNow: hiddenNow,
            suppressed: store.suppressHiddenIconWarning,
            now: now,
            warningDelay: Self.hiddenIconWarningDelay
        ) else {
            return
        }
        showHiddenIconWarning()
    }

    private func observeOcclusionChanges(for window: NSWindow) {
        guard observedOcclusionWindow !== window else {
            return
        }
        if let occlusionObserver {
            NotificationCenter.default.removeObserver(occlusionObserver)
        }
        observedOcclusionWindow = window
        occlusionObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didChangeOcclusionStateNotification,
            object: window,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.checkIconOcclusion()
            }
        }
    }

    private func statusButtonIntersectsNotchGap(_ button: NSStatusBarButton, in window: NSWindow) -> Bool {
        guard let screen = window.screen,
              screen.safeAreaInsets.top > 0,
              let topLeftArea = screen.auxiliaryTopLeftArea,
              let topRightArea = screen.auxiliaryTopRightArea,
              topLeftArea.maxX < topRightArea.minX
        else {
            return false
        }

        let buttonFrame = window.convertToScreen(button.convert(button.bounds, to: nil))
        let notchGap = NSRect(
            x: topLeftArea.maxX,
            y: min(topLeftArea.minY, topRightArea.minY),
            width: topRightArea.minX - topLeftArea.maxX,
            height: max(topLeftArea.maxY, topRightArea.maxY) - min(topLeftArea.minY, topRightArea.minY)
        )
        return buttonFrame.intersects(notchGap)
    }

    private func showHiddenIconWarning() {
        NSApp.activate(ignoringOtherApps: true)

        let alert = NSAlert()
        alert.messageText = Localization.alertHiddenIcon
        alert.informativeText = Localization.alertHiddenIconDetail
        alert.alertStyle = .informational
        alert.useSmallAppIcon()
        alert.addButton(withTitle: Localization.buttonLearnMore)
        alert.addButton(withTitle: Localization.buttonOK)
        alert.showsSuppressionButton = true
        alert.suppressionButton?.title = Localization.buttonDontShowAgain

        let response = alert.runModal()
        if alert.suppressionButton?.state == .on {
            store.suppressHiddenIconWarning = true
            // Opted out permanently: stop polling entirely (nothing left to warn about).
            stopObservingIconOcclusion()
        }
        if response == .alertFirstButtonReturn {
            NSWorkspace.shared.open(AppInfo.menuBarHelpURL)
        }
    }

    /// Updates the sizeScale on all StylePicker views in the icon menu
    private func updateStylePickerSizeScales() {
        let scale = store.sizeScale
        for item in statusMenu.items {
            guard let submenu = item.submenu else {
                continue
            }
            for subItem in submenu.items {
                guard let iconSubmenu = subItem.submenu else {
                    continue
                }
                for iconItem in iconSubmenu.items {
                    if let stylePicker = iconItem.view as? StylePicker {
                        stylePicker.sizeScale = scale
                        stylePicker.needsDisplay = true
                    }
                }
            }
        }
    }

    // MARK: - Preview

    /// Records a preview request; applies immediately when idle, otherwise
    /// coalesces to ~60Hz with latest-wins semantics.
    ///
    /// Rendering synchronously in every tracking-event handler makes the
    /// handler slower than the mouse-event arrival rate, so the main thread
    /// falls behind the sweep and previews replay late in a burst. Keeping
    /// the handler near-zero cost and applying at most one preview per
    /// display frame keeps the preview locked to the cursor.
    private func showPreviewIcon(
        style: IconStyle? = nil,
        labelStyle: IconStyle? = nil,
        symbol: String? = nil,
        foreground: NSColor? = nil,
        background: NSColor? = nil,
        separatorColor: NSColor? = nil,
        clearSymbol: Bool = false,
        skinTone: SkinTone? = nil,
        badgePosition: BadgePosition? = nil
    ) {
        guard statusBarItem != nil else {
            return
        }
        // A new hover arrived - cancel any pending restore from the row we
        // just left so the base icon never flashes between two previews
        restoreTimer?.invalidate()
        restoreTimer = nil
        pendingPreviewApply = { [weak self] in
            self?.applyPreviewIcon(
                style: style,
                labelStyle: labelStyle,
                symbol: symbol,
                foreground: foreground,
                background: background,
                separatorColor: separatorColor,
                clearSymbol: clearSymbol,
                skinTone: skinTone,
                badgePosition: badgePosition
            )
        }
        // Idle: apply on the spot so the first hover feels instant, then
        // open a one-frame coalescing window for any follow-up hovers
        if previewThrottleTimer == nil {
            flushPendingPreview()
            armPreviewThrottle()
        }
    }

    private func flushPendingPreview() {
        let apply = pendingPreviewApply
        pendingPreviewApply = nil
        apply?()
    }

    private func armPreviewThrottle() {
        // Fixed 60Hz regardless of display refresh rate: each apply costs
        // several ms (icon render + forced display + CATransaction.flush),
        // which fits a 16ms slot comfortably but could saturate the main
        // thread at 120Hz - and a status bar preview gains nothing visible
        // beyond 60 updates/sec
        let timer = Timer(timeInterval: 1.0 / 60.0, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else {
                    return
                }
                self.previewThrottleTimer = nil
                if self.pendingPreviewApply != nil {
                    self.flushPendingPreview()
                    self.armPreviewThrottle()
                }
            }
        }
        // .common includes the menu-tracking mode; a default-mode timer
        // would not fire until the menu closes
        RunLoop.main.add(timer, forMode: .common)
        previewThrottleTimer = timer
    }

    private func applyPreviewIcon(
        style: IconStyle?,
        labelStyle: IconStyle?,
        symbol: String?,
        foreground: NSColor?,
        background: NSColor?,
        separatorColor: NSColor?,
        clearSymbol: Bool,
        skinTone: SkinTone?,
        badgePosition: BadgePosition?
    ) {
        guard let statusBarItem else {
            return
        }
        isPreviewingIcon = true
        let previewIcon = appState.generatePreviewIcon(
            overrideStyle: style,
            overrideLabelStyle: labelStyle,
            overrideSymbol: symbol,
            overrideForeground: foreground,
            overrideBackground: background,
            overrideSeparatorColor: separatorColor,
            clearSymbol: clearSymbol,
            skinTone: skinTone,
            overrideBadgePosition: badgePosition
        )
        statusBarItem.length = previewIcon.size.width
        statusBarItem.button?.image = previewIcon
        // Force immediate redraw - during menu tracking AppKit defers display
        // for the status bar button's window, causing visible preview lag.
        statusBarItem.button?.display()
        // Force the Core Animation commit - during rapid event streams the
        // run loop never idles, so the beforeWaiting commit observer is
        // starved and drawn frames reach the WindowServer late.
        CATransaction.flush()
    }

    private func restoreIcon() {
        guard isPreviewingIcon else {
            return
        }
        // The pointer has left preview content - a preview still waiting for
        // a throttle slot is stale and must not apply after this point
        pendingPreviewApply = nil
        // Already scheduled: don't push the restore out again, or sweeping
        // across plain menu items (willHighlight calls this for each one)
        // would defer the restore indefinitely
        guard restoreTimer == nil else {
            return
        }
        // Defer the restore: mouseExited fires before the next row's
        // mouseEntered, and an immediate restore would commit a base-icon
        // frame between consecutive previews. The timer is cancelled by
        // showPreviewIcon when hovering continues to another preview row.
        let timer = Timer(timeInterval: 0.08, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.performRestore()
            }
        }
        // .common includes the menu-tracking mode; a default-mode timer
        // would not fire until the menu closes
        RunLoop.main.add(timer, forMode: .common)
        restoreTimer = timer
    }

    /// Cancels all in-flight preview work: a scheduled restore, a preview
    /// waiting for a throttle slot, and the throttle window itself. Must run
    /// when preview mode ends, otherwise a stale preview can apply after the
    /// menu has closed and stick until the next icon update.
    private func cancelPendingPreviewWork() {
        restoreTimer?.invalidate()
        restoreTimer = nil
        pendingPreviewApply = nil
        previewThrottleTimer?.invalidate()
        previewThrottleTimer = nil
    }

    private func performRestore() {
        cancelPendingPreviewWork()
        guard isPreviewingIcon else {
            return
        }
        isPreviewingIcon = false
        updateStatusBarIcon()
    }

    private func showInvertedColorPreview() {
        let defaults = IconColors.filledColors(darkMode: appState.darkModeEnabled)
        let foreground = appState.currentColors?.foreground ?? defaults.foreground
        let background = appState.currentColors?.background ?? defaults.background
        showPreviewIcon(foreground: background, background: foreground)
    }

    // MARK: - Color Panel

    private func showSeparatorColorPanel() {
        NSApp.activate(ignoringOtherApps: true)

        let colorPanel = NSColorPanel.shared
        colorPanel.setTarget(self)
        colorPanel.setAction(#selector(separatorColorChanged(_:)))
        colorPanel.isContinuous = true
        colorPanel.color = store.separatorColor ?? .gray
        colorPanel.makeKeyAndOrderFront(nil)
    }

    @objc private func separatorColorChanged(_ sender: NSColorPanel) {
        actionHandler.setSeparatorColor(sender.color)
    }

    private func showColorPanel() {
        NSApp.activate(ignoringOtherApps: true)

        let colorPanel = NSColorPanel.shared
        colorPanel.setTarget(self)
        colorPanel.setAction(#selector(colorChanged(_:)))
        colorPanel.isContinuous = true

        if let colors = appState.currentColors {
            colorPanel.color = isPickingForeground ? colors.foreground : colors.background
        } else {
            colorPanel.color = isPickingForeground ? .white : .black
        }

        colorPanel.makeKeyAndOrderFront(nil)
    }

    @objc private func colorChanged(_ sender: NSColorPanel) {
        actionHandler.setColor(sender.color, isForeground: isPickingForeground)
    }

    // MARK: - Font Panel

    @objc func showFontPanel() {
        // Set responder-chain target/action before delegating presentation
        let fontManager = NSFontManager.shared
        fontManager.target = self
        fontManager.action = #selector(changeFont(_:))
        actionHandler.showFontPanel()
    }

    @objc func changeFont(_ sender: Any?) {
        actionHandler.changeFont(sender)
    }
}

// MARK: - MenuActionDelegate

extension AppDelegate: MenuActionDelegate {
    func sizeChanged(to scale: Double) {
        store.sizeScale = scale
        updateStatusBarIcon()
        updateStylePickerSizeScales()
    }

    func paddingChanged(to scale: Double) {
        store.paddingScale = scale
        updateStatusBarIcon()
    }

    func skinToneSelected(_ tone: SkinTone) {
        guard appState.currentSpace > 0 else {
            return
        }
        SpacePreferences.setSkinTone(
            tone,
            forSpace: appState.currentSpace,
            display: appState.currentDisplayID,
            store: store
        )
        updateStatusBarIcon()
    }

    func foregroundColorSelected(_ color: NSColor) {
        actionHandler.setColor(color, isForeground: true)
    }

    func backgroundColorSelected(_ color: NSColor) {
        actionHandler.setColor(color, isForeground: false)
    }

    func separatorColorSelected(_ color: NSColor) {
        actionHandler.setSeparatorColor(color)
    }

    func customForegroundColorRequested() {
        isPickingForeground = true
        showColorPanel()
    }

    func customBackgroundColorRequested() {
        isPickingForeground = false
        showColorPanel()
    }

    func customSeparatorColorRequested() {
        showSeparatorColorPanel()
    }

    func symbolSelected(_ symbol: String?) {
        actionHandler.setSymbol(symbol)
        updateBadgeMenuVisibility()
    }

    func iconStyleSelected(_ style: IconStyle, stylePicker: StylePicker?) {
        actionHandler.selectIconStyle(style, stylePicker: stylePicker)
        updateBadgeMenuVisibility()
    }

    func badgeCharacterChanged(_ character: String?) {
        actionHandler.setBadgeCharacter(character)
    }

    func labelChanged(_ label: String?) {
        // End preview mode fully - a preview left queued here would reapply
        // after the label update and mask the new icon
        cancelPendingPreviewWork()
        isPreviewingIcon = false
        actionHandler.setLabel(label)
        updateLabelMenuVisibility(hasLabel: label != nil && !label!.isEmpty)
    }

    private func updateLabelMenuVisibility(hasLabel: Bool) {
        guard let labelMenu = MenuBuilder.findMenuItem(withTag: MenuTag.labelMenuItem.rawValue, in: statusMenu)?.submenu
        else {
            return
        }
        var pastInput = false
        for item in labelMenu.items {
            if item.tag == MenuTag.labelInput.rawValue {
                pastInput = true
                continue
            }
            // Only hide separators, disabled headers, and style pickers - not copy/reset actions
            if pastInput, item.tag != MenuTag.fontMenuItem.rawValue,
               item.isSeparatorItem || item.view is StylePicker || !item.isEnabled
            {
                item.isHidden = !hasLabel
            }
        }
    }

    func labelStyleSelected(_ style: IconStyle, stylePicker: StylePicker?) {
        actionHandler.selectLabelStyle(style, stylePicker: stylePicker)
    }

    func labelStyleHoverStarted(_ style: IconStyle) {
        showPreviewIcon(labelStyle: style)
    }

    func badgePositionSelected(_ position: BadgePosition) {
        guard appState.currentSpace > 0 else {
            return
        }
        let currentBadge = SpacePreferences.badge(
            forSpace: appState.currentSpace,
            display: appState.currentDisplayID,
            store: store
        )
        let character = currentBadge?.character ?? ""
        guard !character.isEmpty else {
            return
        }
        SpacePreferences.setBadge(
            SpaceBadge(character: character, position: position),
            forSpace: appState.currentSpace,
            display: appState.currentDisplayID,
            store: store
        )
        updateStatusBarIcon()
    }

    func skinToneHoverStarted(_ tone: SkinTone) {
        guard let symbol = appState.currentSymbol else {
            return
        }
        showPreviewIcon(symbol: symbol, skinTone: tone)
    }

    func colorHoverStarted(index: Int, isForeground _: Bool) {
        showPreviewIcon(foreground: ColorSwatch.presetColors[index])
    }

    func backgroundColorHoverStarted(index: Int) {
        showPreviewIcon(background: ColorSwatch.presetColors[index])
    }

    func separatorColorHoverStarted(index: Int) {
        showPreviewIcon(separatorColor: ColorSwatch.presetColors[index])
    }

    func symbolHoverStarted(_ symbol: String, foreground: NSColor?, background: NSColor?, skinTone: SkinTone?) {
        showPreviewIcon(symbol: symbol, foreground: foreground, background: background, skinTone: skinTone)
    }

    func styleHoverStarted(_ style: IconStyle) {
        showPreviewIcon(style: style, clearSymbol: true)
    }

    func hoverEnded() {
        restoreIcon()
    }
}

// MARK: - NSMenuDelegate

extension AppDelegate: NSMenuDelegate {
    func menuWillOpen(_ menu: NSMenu) {
        menuBuilder.updateMenuState(menu: menu, launchAtLoginEnabled: launchAtLogin.isEnabled)

        if menu == statusMenu {
            menuBuilder.refreshUserSounds()
        }

        // Update status bar icon when menu opens
        updateStatusBarIcon()
    }

    func menuDidClose(_: NSMenu) {
        cancelPendingPreviewWork()
        // Reset preview state in case menu closed while hovering (onHoverEnd may not fire)
        if isPreviewingIcon {
            isPreviewingIcon = false
            updateStatusBarIcon()
        }
    }

    func menu(_: NSMenu, willHighlight item: NSMenuItem?) {
        guard let item else {
            restoreIcon()
            return
        }

        let badgePositionTags: [Int: BadgePosition] = [
            MenuTag.badgePositionTopLeft.rawValue: .topLeft,
            MenuTag.badgePositionTopRight.rawValue: .topRight,
            MenuTag.badgePositionBottomLeft.rawValue: .bottomLeft,
            MenuTag.badgePositionBottomRight.rawValue: .bottomRight,
        ]

        if let position = badgePositionTags[item.tag] {
            showPreviewIcon(badgePosition: position)
            return
        }

        switch item.tag {
        case MenuTag.invertColors.rawValue:
            showInvertedColorPreview()
        default:
            // Play sound preview on hover (sound items store name in representedObject)
            if let soundName = item.representedObject as? String, !soundName.isEmpty {
                let sound = NSSound(named: NSSound.Name(soundName))?.copy() as? NSSound
                sound?.play()
            }
            restoreIcon()
        }
    }
}
