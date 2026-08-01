import AppKit
import Defaults
import LaunchAtLogin
import Observation
import os.log
import QuartzCore
import Settings
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

// MARK: - Click Permission

/// Whether a left click may switch Spaces, or has to ask for permission first.
enum ClickPermission {
    case granted
    case needsRequest
}

// MARK: - App Delegate

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, SPUStandardUserDriverDelegate {
    // MARK: - Properties

    private let confirmAction: ConfirmAction
    private let appState: AppState
    private let missionControlNotificationSender: (CFString) -> Void
    private(set) var actionHandler: ActionHandler!
    private var middleClickMonitor: Any?
    private var scrollMonitor: Any?
    private var statusBarItem: NSStatusItem!

    /// Switches one Space left or right; injectable so scroll tests don't move real Spaces
    private let relativeSpaceSwitchAction: (_ goRight: Bool, _ wrap: Bool) -> Bool
    /// Plays scroll haptics; injectable so gesture classification can be tested.
    private let scrollHapticAction: @MainActor (Int) -> Void
    /// Reports Accessibility trust; injectable so click tests don't depend on the host's TCC state
    private let isProcessTrusted: () -> Bool

    /// Records why a click produced no switch; the early returns below leave
    /// no other trace.
    private static let logger = Logger(subsystem: "io.gechr.WhichSpace", category: "Click")
    /// Accumulated precise scroll delta at 100% sensitivity; a switch fires on crossing
    private static let scrollSpaceBaseThreshold = 50.0
    /// Minimum interval between scroll-triggered switches, so a flick lands one Space over
    private static let scrollSwitchCooldown: TimeInterval = 0.3
    private var scrollAccumulator = 0.0
    private var lastScrollSwitchTimestamp: TimeInterval = -.infinity

    /// Reads whether anyone else's status items are still drawn
    private let menuBarVisibilityProbe: MenuBarVisibilityProbe
    private var evictionDetector = MenuBarEvictionDetector()
    private var pendingEvictionCheck: Task<Void, Never>?
    private var evictionObservationTasks: [Task<Void, Never>] = []
    /// The display the status item was last seen drawn on. `NSWindow.screen`
    /// can go nil once the window is hidden, which is exactly when the display
    /// needs naming, so the last good answer is kept.
    private var lastKnownStatusDisplay: CGRect?
    /// Whether the screen is showing the desktop rather than the lock screen,
    /// the screensaver, or a sleeping display.
    private var sessionIsActive = true

    private var launchAtLogin: LaunchAtLoginProvider
    private var preferenceObservationTasks: [Task<Void, Never>] = []
    private var settingsCoordinator: SettingsWindowCoordinator?
    private var updaterController: SPUStandardUpdaterController!

    private(set) var observationTask: Task<Void, Never>?
    private(set) var statusBarIconUpdateCount = 0
    private(set) var statusMenu: NSMenu!

    /// Convenience accessor for the store via appState
    private var store: DefaultsStore {
        appState.store
    }

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
        relativeSpaceSwitchAction = { goRight, wrap in
            guard AXIsProcessTrusted() else {
                return false
            }
            return SpaceSwitcher.switchRelative(goRight: goRight, wrap: wrap)
        }
        scrollHapticAction = HapticActuator.actuate
        isProcessTrusted = { AXIsProcessTrusted() }
        menuBarVisibilityProbe = CGMenuBarVisibilityProbe()
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
        },
        relativeSpaceSwitchAction: @escaping (_ goRight: Bool, _ wrap: Bool) -> Bool = { goRight, wrap in
            guard AXIsProcessTrusted() else {
                return false
            }
            return SpaceSwitcher.switchRelative(goRight: goRight, wrap: wrap)
        },
        scrollHapticAction: @escaping @MainActor (Int) -> Void = HapticActuator.actuate,
        isProcessTrusted: @escaping () -> Bool = { AXIsProcessTrusted() },
        menuBarVisibilityProbe: MenuBarVisibilityProbe = CGMenuBarVisibilityProbe()
    ) {
        self.appState = appState
        self.confirmAction = confirmAction
        self.launchAtLogin = launchAtLogin
        self.missionControlNotificationSender = missionControlNotificationSender
        self.relativeSpaceSwitchAction = relativeSpaceSwitchAction
        self.scrollHapticAction = scrollHapticAction
        self.isProcessTrusted = isProcessTrusted
        self.menuBarVisibilityProbe = menuBarVisibilityProbe
        super.init()
        configureActionHandler()
    }

    private func configureActionHandler() {
        actionHandler = ActionHandler(
            appState: appState,
            launchAtLogin: launchAtLogin,
            confirmAction: confirmAction,
            onStatusBarIconNeedsUpdate: { [weak self] in
                self?.updateStatusBarIcon()
            },
            onCheckForUpdates: { [weak self] in
                NSApp.activate(ignoringOtherApps: true)
                self?.updaterController.checkForUpdates(nil)
            },
            onOpenSettings: { [weak self] in
                self?.showSettingsWindow()
            }
        )
    }

    // MARK: - Settings Window

    /// Opens (creating on first use) the settings window, optionally on a
    /// named pane with one row scrolled into view.
    func showSettingsWindow(pane: SettingsPaneID? = nil, focus: SettingsFocus? = nil) {
        if settingsCoordinator == nil {
            let model = SettingsModel(store: store, launchAtLogin: launchAtLogin)
            let editorModel = SpaceEditorModel(appState: appState, confirmAction: confirmAction)
            let highlighter = SettingsHighlighter()
            let generalPane = Settings.PaneHostingController(pane: Settings.Pane(
                identifier: .general,
                title: Localization.paneGeneral,
                toolbarIcon: NSImage(systemSymbolName: "gearshape", accessibilityDescription: nil)!
            ) {
                GeneralPane(
                    model: model,
                    updater: updaterController?.updater,
                    onCheckForUpdates: { [weak self] in self?.actionHandler.checkForUpdates() },
                    onImportSettings: { [weak self] in self?.actionHandler.importSettings() },
                    onExportSettings: { [weak self] in self?.actionHandler.exportSettings() },
                    onResetAllSettings: { [weak self] in self?.actionHandler.resetAllSettings() }
                )
                .environment(highlighter)
            })
            let spacesPane = Settings.PaneHostingController(pane: Settings.Pane(
                identifier: .spaces,
                title: Localization.paneSpaces,
                toolbarIcon: NSImage(systemSymbolName: "square.grid.2x2", accessibilityDescription: nil)!
            ) {
                SpacesPane(model: editorModel) { [weak self] in
                    self?.actionHandler.openCustomSoundsFolder()
                }
                .environment(highlighter)
            })
            let menuBarPane = Settings.PaneHostingController(pane: Settings.Pane(
                identifier: .menuBar,
                title: Localization.paneMenuBar,
                toolbarIcon: NSImage(systemSymbolName: "menubar.rectangle", accessibilityDescription: nil)!
            ) {
                MenuBarPane(model: model)
                    .environment(highlighter)
            })
            let switchingPane = Settings.PaneHostingController(pane: Settings.Pane(
                identifier: .switching,
                title: Localization.paneSwitching,
                toolbarIcon: NSImage(systemSymbolName: "computermouse", accessibilityDescription: nil)!
            ) {
                SwitchingPane(model: model) { [weak self] intensity in
                    self?.scrollHapticAction(intensity)
                }
                .environment(highlighter)
            })
            settingsCoordinator = SettingsWindowCoordinator(
                models: [model, editorModel],
                panes: [generalPane, menuBarPane, spacesPane, switchingPane],
                highlighter: highlighter
            )
        }
        settingsCoordinator?.show(pane: pane, focus: focus)
    }

    // MARK: - NSApplicationDelegate

    func applicationDidFinishLaunching(_: Notification) {
        // Skip full app setup when running as a test host
        guard ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil else {
            return
        }

        // AppKit's tooltip manager reads this key
        // register() keeps it session-only and yields to a user-set value
        UserDefaults.standard.register(defaults: ["NSInitialToolTipDelay": 500])

        // Offer to move to /Applications when launched from elsewhere (e.g. Downloads)
        // - running translocated would break Sparkle updates.
        // A debug build lives in DerivedData, which is never an Applications
        // folder, so it would offer to replace the installed copy and trash
        // the build product out from under the running process.
        #if !DEBUG
            AppMover.moveIfNecessary(appName: AppInfo.appName)
        #endif

        // Menu bar only - no Dock icon or app-switcher entry
        NSApp.setActivationPolicy(.accessory)

        // Start Sparkle so scheduled update checks run
        updaterController = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: self
        )

        // Create the status item and keep its icon in sync with renderer state
        statusBarItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        configureMenuBarIcon()
        appState.renderer.onIconNeedsUpdate = { [weak self] in
            self?.updateStatusBarIcon()
        }
        // A Space change only earns another attempt at full size once the
        // crowding that caused the shrink has eased
        appState.onSnapshotDidChange = { [weak self] in
            self?.retryFullSizeIfRoomAppeared()
        }
        startObservingIconVisibility()

        // Begin observing app state, Space changes, and preference edits
        startObservingAppState()
        startObservingSpaceChanges()
        startObservingPreferences()

        // Disable switching gestures if accessibility permission was revoked
        if !isProcessTrusted() {
            let hadGestures = store.clickToSwitchSpaces || store.horizontalScrollEnabled || store.verticalScrollEnabled
            if store.clickToSwitchSpaces {
                SettingsConstraints.setClickToSwitchSpaces(false, store: store)
            }
            if store.horizontalScrollEnabled {
                SettingsConstraints.setScrollSwitching(false, axis: \.horizontalScrollEnabled, store: store)
            }
            if store.verticalScrollEnabled {
                SettingsConstraints.setScrollSwitching(false, axis: \.verticalScrollEnabled, store: store)
            }
            if hadGestures {
                Self.logger.info("not trusted at launch; switching gestures turned off")
            }
        }

        // Warm the symbol/emoji catalogs off-main so the first settings-window
        // open doesn't pay for instantiating ~600 NSImages on the main thread
        Task.detached(priority: .utility) {
            _ = ItemData.symbols.count
            _ = ItemData.emojis.count
        }
    }

    func applicationShouldHandleReopen(_: NSApplication, hasVisibleWindows _: Bool) -> Bool {
        // Prevent macOS/SwiftUI from opening any windows when the app is relaunched
        false
    }

    func application(_: NSApplication, open urls: [URL]) {
        for url in urls {
            guard let command = URLCommand.parse(url) else {
                NSLog("AppDelegate: ignoring unrecognized URL '%@'", url.absoluteString)
                continue
            }
            handleURLCommand(command)
        }
    }

    /// Routes a parsed `whichspace://` command through the same helpers as the
    /// AppleScript and Shortcuts surfaces, so validation and reset semantics match.
    private func handleURLCommand(_ command: URLCommand) {
        do {
            switch command {
            case let .switchToSpace(number, label, badge):
                try ScriptingHelpers.switchToSpace(number: number, appState: appState)
                // Keyed by the target Space number, so these cannot race the
                // asynchronous switch animation
                if let label {
                    ScriptingHelpers.setLabel(label, forSpace: number, appState: appState, store: store)
                }
                if let badge {
                    try ScriptingHelpers.setBadge(badge, forSpace: number, appState: appState, store: store)
                }
            case .switchToNext:
                try ScriptingHelpers.switchRelative(goRight: true)
            case .switchToPrevious:
                try ScriptingHelpers.switchRelative(goRight: false)
            case let .openSettings(pane, focus):
                showSettingsWindow(pane: pane, focus: focus)
            }
        } catch {
            NSLog("AppDelegate: URL command failed - %@", error.localizedDescription)
        }
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
        pendingEvictionCheck?.cancel()
        pendingEvictionCheck = nil
        for task in evictionObservationTasks {
            task.cancel()
        }
        evictionObservationTasks.removeAll()
        stopObservingPreferences()
    }

    func stopObservingPreferences() {
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
            name: .currentDisplaySpaceDidChange,
            object: appState
        )
    }

    @objc private func handleSpaceDidChange() {
        // Per-space override ("" = silent) falls back to the global default sound
        guard let soundName = SpacePreferences.resolvedSoundName(
            forSpace: appState.currentSpace,
            display: appState.currentDisplayID,
            store: store
        ) else {
            return
        }
        // Copy to allow overlapping sounds on rapid switches
        guard let sound = NSSound(named: NSSound.Name(soundName))?.copy() as? NSSound else {
            NSLog("AppDelegate: failed to load sound '%@'", soundName)
            return
        }
        sound.play()
    }

    /// Observes preference changes that affect the status bar icon using Defaults async streams.
    /// Internal so tests can drive the observation streams directly.
    func startObservingPreferences() {
        stopObservingPreferences()

        // Derived from the KeySpecs registry so newly added preferences are
        // observed automatically
        let iconKeys = store.iconAffectingKeys

        preferenceObservationTasks.append(Task { [weak self] in
            for await _ in Defaults.updates(iconKeys, initial: false) {
                // 16ms ≈ one frame at 60 FPS; coalesces rapid changes into a single update
                try? await Task.sleep(for: .milliseconds(16))
                guard !Task.isCancelled
                else { return }
                // Covers defaults changes that bypass DefaultsStore (and its mutation
                // counter), e.g. external `defaults write`
                // A setting that changes how wide the item draws earns another
                // attempt at full size. One that only changes how it looks -
                // a colour, a separator glyph - must not, or every cosmetic
                // edit would widen the item and reflow the whole menu bar.
                let previousWidth = self?.appState.statusBarIcon.size.width
                self?.store.invalidateCachedValues()
                self?.appState.renderer.invalidateIconCache()
                if self?.appState.statusBarIcon.size.width != previousWidth {
                    self?.resetShrinkLevel()
                }
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

        // Non-icon keys are read through the memo cache too (e.g. per scroll
        // event), so external defaults writes must still drop the cache even
        // though no icon rebuild is needed
        let nonIconKeys = store.nonIconKeys
        preferenceObservationTasks.append(Task { [weak self] in
            for await _ in Defaults.updates(nonIconKeys, initial: false) {
                // Same coalescing as above: a slider drag writes continuously,
                // and each invalidation drops every memoized value
                try? await Task.sleep(for: .milliseconds(16))
                guard !Task.isCancelled
                else { return }
                self?.store.invalidateCachedValues()
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
        statusMenu = MenuBuilder.buildMenu(target: actionHandler)
        statusBarItem?.button?.toolTip = AppInfo.appName
        statusBarItem?.button?.target = self
        statusBarItem?.button?.action = #selector(statusBarButtonClicked(_:))
        statusBarItem?.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
        // Remove any previous monitors: this is re-invoked by tests
        if let middleClickMonitor {
            NSEvent.removeMonitor(middleClickMonitor)
        }
        middleClickMonitor = NSEvent.addLocalMonitorForEvents(matching: .otherMouseUp) { [weak self] event in
            self?.handleMiddleClickEvent(event, in: self?.statusBarItem?.button) ?? event
        }
        if let scrollMonitor {
            NSEvent.removeMonitor(scrollMonitor)
        }
        scrollMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            self?.handleScrollEvent(event, in: self?.statusBarItem?.button) ?? event
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

    /// Handles scroll over the status bar item and switches at most one Space per
    /// event: scroll up goes to the next Space, scroll down to the previous.
    /// Horizontal scrolls follow the Mission Control swipe convention - fingers
    /// left = next, fingers right = previous - and the dominant enabled axis of
    /// each event wins. A cooldown between switches keeps flicks to a single hop.
    /// Returns nil when the event is consumed; otherwise returns the original event.
    func handleScrollEvent(_ event: NSEvent, in button: NSView?) -> NSEvent? {
        guard let button,
              button.isMousePoint(button.convert(event.locationInWindow, from: nil), in: button.bounds)
        else {
            return event
        }
        let verticalEnabled = store.verticalScrollEnabled
        let horizontalEnabled = store.horizontalScrollEnabled
        guard verticalEnabled || horizontalEnabled else {
            return event
        }
        // Ignore momentum-phase events so a trackpad flick doesn't skip several Spaces
        guard event.momentumPhase.isEmpty else {
            return nil
        }
        // Each gesture starts from a clean slate so leftovers don't carry over
        if event.phase == .began {
            scrollAccumulator = 0
        }
        // Swallow the tail of a gesture right after a switch
        guard event.timestamp - lastScrollSwitchTimestamp >= Self.scrollSwitchCooldown else {
            scrollAccumulator = 0
            return nil
        }

        // Normalize the dominant enabled axis into "positive = next Space":
        // scroll up = next, and a leftward scroll (negative deltaX) pushes the
        // Space strip left to reveal the next Space, matching the system swipe
        let precise = event.hasPreciseScrollingDeltas
        let rawVertical = (precise ? event.scrollingDeltaY : event.deltaY) * (verticalEnabled ? 1 : 0)
        let rawHorizontal = (precise ? event.scrollingDeltaX : event.deltaX) * (horizontalEnabled ? 1 : 0)
        var delta: Double
        if abs(rawHorizontal) > abs(rawVertical) {
            delta = -rawHorizontal
            if store.invertHorizontalScroll {
                delta.negate()
            }
        } else {
            delta = rawVertical
            if store.invertVerticalScroll {
                delta.negate()
            }
        }
        guard delta != 0 else {
            return nil
        }

        let shouldSwitch: Bool
        let goRight: Bool
        if precise {
            // Trackpads emit many small deltas per gesture; accumulate to a
            // threshold scaled by the sensitivity preference
            scrollAccumulator += delta
            let threshold = Self.scrollSpaceBaseThreshold * 100.0 / store.scrollSensitivity
            shouldSwitch = abs(scrollAccumulator) >= threshold
            goRight = scrollAccumulator > 0
            if shouldSwitch {
                scrollAccumulator = 0
            }
        } else {
            // Mouse wheels emit one event per notch; step directly
            shouldSwitch = true
            goRight = delta > 0
        }
        if shouldSwitch {
            lastScrollSwitchTimestamp = event.timestamp
            let switched = relativeSpaceSwitchAction(goRight, store.scrollWrapAround)
            // Gesture phases indicate direct touch interaction more reliably
            // than precise deltas, which smooth-scrolling mice can also emit.
            if switched, !event.phase.isEmpty, store.scrollHapticFeedback {
                scrollHapticAction(store.scrollHapticIntensity)
            }
        }
        return nil
    }

    @objc private func statusBarButtonClicked(_ button: NSStatusBarButton) {
        guard let event = NSApp.currentEvent else {
            Self.logger.info("click ignored: no current event")
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

    /// Resolves what a left click is allowed to do, enabling click-to-switch on
    /// the first click and turning it back off if the grant has gone away.
    ///
    /// Permission can disappear after the setting was enabled - a revoked
    /// grant, a TCC reset, or a rebuilt bundle the system no longer
    /// recognises - so both states end in a permission request rather than a
    /// click that does nothing and says nothing.
    func resolveClickPermission() -> ClickPermission {
        // Auto-enable click-to-switch on first left click
        guard store.clickToSwitchSpaces else {
            let enabled = SettingsConstraints.setClickToSwitchSpaces(
                true, store: store, isProcessTrusted: isProcessTrusted
            )
            if !enabled {
                Self.logger.info("click ignored: not trusted, so click-to-switch stays off")
            }
            return enabled ? .granted : .needsRequest
        }

        guard isProcessTrusted() else {
            Self.logger.info("click ignored: not trusted; turning click-to-switch off")
            SettingsConstraints.setClickToSwitchSpaces(false, store: store)
            return .needsRequest
        }

        return .granted
    }

    private func handleLeftClick(_ event: NSEvent, button: NSStatusBarButton) {
        guard resolveClickPermission() == .granted else {
            actionHandler.requestAccessibilityForClickToSwitch()
            return
        }

        // A collapsed icon reports no slots, so it lands on the picker here
        // alongside single-icon mode rather than expanding: growing the icon
        // back under a full menu bar would just have macOS drop it again
        let layout = appState.statusBarLayout()
        // Single-icon mode draws one icon per display rather than one per
        // Space, so a click has no Space of its own to land on even when the
        // display row gives the layout slots. Offer the picker in both cases,
        // and whenever the layout came back empty, so a left click can always
        // reach another Space.
        //
        // A shrunk icon that has given up its per-Space slots is the same
        // picture arrived at a different way, so it routes the same way. Keying
        // this off the preference alone would leave a click on the current
        // display's icon selecting the Space it is already on.
        let showsSpaces = store.showAllSpaces && appState.shrinkLevel.showsInactiveSpaces
        guard showsSpaces, !layout.slots.isEmpty else {
            let allSpaces = store.showAllSpaces
            let slotCount = layout.slots.count
            Self.logger.info("picker fallback: showAllSpaces \(allSpaces), slots \(slotCount)")
            showSpacePickerMenu(from: button)
            return
        }

        let location = button.convert(event.locationInWindow, from: nil)
        let clickX = Double(location.x)

        // Use StatusBarLayout hit testing
        guard let slot = layout.slot(at: clickX) else {
            let width = layout.totalWidth
            Self.logger.info("click ignored: no slot at x \(clickX) of width \(width)")
            return
        }

        // Fullscreen spaces don't have a targetSpace - activate the app instead
        if slot.targetSpace == nil {
            _ = SpaceSwitcher.activateAppOnSpace(slot.spaceID)
            return
        }

        SpaceSwitcher.switchToSpace(id: slot.spaceID)
    }

    // MARK: - Auto Shrink

    /// Schedules the reading that decides whether the menu bar dropped the
    /// status item for lack of room.
    ///
    /// Assigning an image relayouts the bar and the item reads as off screen
    /// while that happens, so the reading waits for it to settle. Each render
    /// replaces any pending reading, and the reading itself renders when it
    /// shrinks, so the levels cascade until one fits.
    private func scheduleEvictionCheck() {
        pendingEvictionCheck?.cancel()
        pendingEvictionCheck = nil
        // Nothing to schedule once the icon is as small as it goes
        guard store.shrinkIconToFit, appState.shrinkLevel.next != nil else {
            return
        }
        evictionDetector.beginSettling(now: Date())
        pendingEvictionCheck = Task { [weak self] in
            try? await Task.sleep(for: .seconds(MenuBarEvictionDetector.checkDelay))
            guard !Task.isCancelled else {
                return
            }
            self?.pendingEvictionCheck = nil
            self?.shrinkIfEvicted()
        }
    }

    /// Shrinks the icon a step when the menu bar has dropped it.
    ///
    /// The reading that matters is a relative one. Running out of room takes
    /// this app's item off screen and leaves its neighbours behind, so the
    /// menu bar going dark altogether - a fullscreen Space, auto-hide,
    /// Mission Control, the lock screen, display sleep - reads as no eviction
    /// at all and leaves the icon alone.
    ///
    /// The two halves come from different sources because neither can answer
    /// both. The WindowServer does not attribute a status item to the app that
    /// created it, so this app's own status window never appears in the window
    /// list and its absence there says nothing; occlusion answers for it
    /// instead, and is only observable for windows this process owns.
    private func shrinkIfEvicted() {
        guard store.shrinkIconToFit,
              let statusBarItem, statusBarItem.isVisible,
              let window = statusBarItem.button?.window
        else {
            return
        }
        let ownIsOnScreen = window.occlusionState.contains(.visible)
        if ownIsOnScreen, let bounds = window.screen.flatMap(Self.displayBounds) {
            lastKnownStatusDisplay = bounds
        }
        guard let bounds = lastKnownStatusDisplay ?? window.screen.flatMap(Self.displayBounds) else {
            return
        }

        let snapshot = StatusWindowSnapshot(
            ownWindowIsOnScreen: ownIsOnScreen,
            otherStatusWindowCount: menuBarVisibilityProbe.otherStatusWindowCount(onDisplay: bounds),
            sessionIsActive: sessionIsActive
        )
        guard let level = evictionDetector.apply(snapshot, now: Date()) else {
            return
        }
        Self.logger.info("menu bar dropped the icon, shrinking to level \(level.rawValue)")
        appState.shrinkLevel = level
    }

    /// The display a screen occupies, in the coordinate system the window list
    /// reports bounds in.
    private static func displayBounds(of screen: NSScreen) -> CGRect? {
        guard let number = screen.deviceDescription[
            NSDeviceDescriptionKey("NSScreenNumber")
        ] as? NSNumber else {
            return nil
        }
        return CGDisplayBounds(CGDirectDisplayID(number.uint32Value))
    }

    /// Returns the icon to full size so a layout with room again gets it back.
    private func resetShrinkLevel() {
        evictionDetector.reset()
        appState.shrinkLevel = .full
    }

    /// Grows the icon back only once a status item has gone away.
    ///
    /// Widening the item reflows every icon to its left, so the whole menu bar
    /// repaints. Doing that on every Space switch costs a visible flicker each
    /// time and almost always ends where it started, because switching Space
    /// does not change what the menu bar is holding. A neighbouring status item
    /// disappearing does change it, and is the case worth spending a repaint
    /// on.
    private func retryFullSizeIfRoomAppeared() {
        guard store.shrinkIconToFit, appState.shrinkLevel != .full else {
            return
        }
        guard let bounds = lastKnownStatusDisplay else {
            return
        }
        let count = menuBarVisibilityProbe.otherStatusWindowCount(onDisplay: bounds)
        guard evictionDetector.shouldRetryFullSize(otherStatusWindowCount: count) else {
            return
        }
        Self.logger.info("menu bar has room again, restoring the icon")
        resetShrinkLevel()
    }

    /// Watches for the icon being dropped by something other than this app.
    ///
    /// Eviction is usually somebody else's doing: another app adds a status
    /// item, or the frontmost app's menus grow wider. Neither changes anything
    /// WhichSpace draws, so neither produces a render, and a check scheduled
    /// only from `updateStatusBarIcon` would not run until the next Space
    /// switch. The status window posts an occlusion change in both cases.
    ///
    /// Screen parameter changes get their own reset: they alter the room
    /// available without necessarily changing the Space snapshot, which
    /// `AppState.applySnapshot` drops when equal.
    private func startObservingIconVisibility() {
        for task in evictionObservationTasks {
            task.cancel()
        }
        evictionObservationTasks.removeAll()

        if let window = statusBarItem?.button?.window {
            let occlusionChanges = Self.notifications(
                named: NSWindow.didChangeOcclusionStateNotification, object: window
            )
            evictionObservationTasks.append(Task { [weak self] in
                for await _ in occlusionChanges {
                    self?.scheduleEvictionCheck()
                }
            })
        }

        evictionObservationTasks.append(Task { [weak self] in
            for await _ in NotificationCenter.default.notifications(
                named: NSApplication.didChangeScreenParametersNotification
            ) {
                self?.lastKnownStatusDisplay = nil
                self?.resetShrinkLevel()
            }
        })

        // The lock screen, the screensaver and a sleeping display are the one
        // case the neighbour count cannot rule out: measured on a locked
        // screen the display keeps 4 to 20 status windows drawn while this
        // app's occlusion drops, which reads exactly like running out of room.
        for (name, active) in Self.sessionActivityNotifications {
            evictionObservationTasks.append(Task { [weak self] in
                for await _ in Self.distributedNotifications(named: name) {
                    self?.sessionIsActive = active
                }
            })
        }
        let workspaceCenter = NSWorkspace.shared.notificationCenter
        for (name, active) in [
            (NSWorkspace.screensDidSleepNotification, false),
            (NSWorkspace.screensDidWakeNotification, true),
        ] {
            evictionObservationTasks.append(Task { [weak self] in
                for await _ in workspaceCenter.notifications(named: name) {
                    self?.sessionIsActive = active
                }
            })
        }
    }

    /// Distributed notifications naming a session state the icon must not be
    /// judged in, paired with the state they announce.
    private static let sessionActivityNotifications: [(String, Bool)] = [
        ("com.apple.screenIsLocked", false),
        ("com.apple.screenIsUnlocked", true),
        ("com.apple.screensaver.didstart", false),
        ("com.apple.screensaver.didstop", true),
    ]

    /// Bridges a distributed notification into an async sequence; there is no
    /// native async API for that centre.
    private static func distributedNotifications(named name: String) -> AsyncStream<Void> {
        AsyncStream { continuation in
            nonisolated(unsafe) let observer = DistributedNotificationCenter.default().addObserver(
                forName: Notification.Name(name), object: nil, queue: .main
            ) { _ in
                continuation.yield()
            }
            continuation.onTermination = { @Sendable _ in
                DistributedNotificationCenter.default().removeObserver(observer)
            }
        }
    }

    /// Bridges a notification for a specific non-Sendable object into an async
    /// sequence, matching how `AppState` observes its distributed notifications.
    private static func notifications(named name: Notification.Name, object: NSWindow) -> AsyncStream<Void> {
        AsyncStream { continuation in
            nonisolated(unsafe) let observer = NotificationCenter.default.addObserver(
                forName: name, object: object, queue: .main
            ) { _ in
                continuation.yield()
            }
            continuation.onTermination = { @Sendable _ in
                NotificationCenter.default.removeObserver(observer)
            }
        }
    }

    /// Pops up a menu listing every Space on the current display, each item
    /// rendered exactly like its status bar icon, with the active Space checked.
    private func showSpacePickerMenu(from button: NSStatusBarButton) {
        let entries = appState.spacePickerEntries()
        // A single Space leaves nothing to switch to
        guard entries.count > 1 else {
            Self.logger.info("no picker: \(entries.count) Space(s) available")
            return
        }
        let menu = MenuBuilder.buildSpacePickerMenu(entries: entries, target: actionHandler)
        let position = NSPoint(x: 0, y: button.bounds.height + 5)
        menu.popUp(positioning: nil, at: position, in: button)
    }

    // MARK: - Status Bar

    /// The single funnel for base-icon refreshes, reached via three routes:
    /// the observation task (snapshot and dark-mode changes), the renderer's
    /// `onIconNeedsUpdate` callback (background occupancy scans), and the
    /// preference observers (settings-window writes and external defaults
    /// edits).
    func updateStatusBarIcon() {
        statusBarIconUpdateCount += 1
        guard let statusBarItem else {
            return
        }
        // Every refresh re-arms the reading, including the unchanged-icon path
        // below: the room around the item can change without the icon doing so
        scheduleEvictionCheck()
        // Ahead of the unchanged-icon check: the same icon can outlive a
        // change of Space, and the announced label has to follow the Space
        updateStatusBarAccessibilityLabel()
        let icon = appState.statusBarIcon
        // Skip the assignment and forced redraw when the cached icon is
        // already installed (e.g. every submenu open triggers an update)
        guard statusBarItem.button?.image !== icon else {
            updateStatusBarVisibility()
            return
        }
        statusBarItem.length = icon.size.width
        statusBarItem.button?.image = icon
        // Force immediate redraw - during event tracking (e.g. settings
        // slider drags) AppKit defers display for the status bar button's
        // window, delaying the new icon visibly.
        statusBarItem.button?.display()
        // Force the Core Animation commit - during rapid event streams the
        // run loop never idles, so the beforeWaiting commit observer is
        // starved and drawn frames reach the WindowServer late.
        CATransaction.flush()
        updateStatusBarVisibility()
    }

    /// Names the current Space for VoiceOver. The icon is a drawn bitmap, so
    /// without a label the item announces only the app name. The tooltip is
    /// left naming the app: an explicit accessibility label takes precedence
    /// over the one AppKit would otherwise derive from the tooltip, so the
    /// two can say different things. The text matches what AppleScript
    /// reports for `current space label`.
    func updateStatusBarAccessibilityLabel() {
        guard let button = statusBarItem?.button else {
            return
        }
        let label = ScriptingHelpers.resolveCurrentLabel(appState: appState, store: store)
        button.setAccessibilityLabel(
            String(format: Localization.accessibilityCurrentSpace, label)
        )
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
}
