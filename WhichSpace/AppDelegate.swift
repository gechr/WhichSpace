import AppKit
import Defaults
import LaunchAtLogin
import Observation
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

// MARK: - App Delegate

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, SPUStandardUserDriverDelegate {
    // MARK: - Properties

    private let confirmAction: ConfirmAction
    private let appState: AppState
    private let missionControlNotificationSender: (CFString) -> Void
    private let spaceSwitcher: SpaceSwitcher
    private(set) var actionHandler: ActionHandler!
    private var menuBuilder: MenuBuilder!
    private var statusBarItem: NSStatusItem!

    private var isPickingForeground = true
    private var isPreviewingIcon = false
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
        spaceSwitcher = SpaceSwitcher()
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
        spaceSwitcher: SpaceSwitcher = SpaceSwitcher()
    ) {
        self.appState = appState
        self.confirmAction = confirmAction
        self.launchAtLogin = launchAtLogin
        self.missionControlNotificationSender = missionControlNotificationSender
        self.spaceSwitcher = spaceSwitcher
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
            startingUpdater: !AppInfo.isHomebrewInstall,
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

        // Disable click-to-switch if accessibility permission was revoked
        if store.clickToSwitchSpaces, !AXIsProcessTrusted() {
            SettingsConstraints.setClickToSwitchSpaces(false, store: store)
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
            store.keyShowAllSpaces,
            store.keyShowAllDisplays,
            store.keyDimInactiveSpaces,
            store.keyHideEmptySpaces,
            store.keyHideFullscreenApps,
            store.keyHideSingleSpace,
            store.keyUniqueIconsPerDisplay,
            store.keyLocalSpaceNumbers,
            store.keySizeScale,
            store.keySeparatorColor,
            store.keySpaceColors,
            store.keySpaceIconStyles,
            store.keySpaceSymbols,
            store.keySpaceFonts,
            store.keySpaceSkinTones,
            store.keyDisplaySpaceColors,
            store.keyDisplaySpaceIconStyles,
            store.keyDisplaySpaceSymbols,
            store.keyDisplaySpaceFonts,
            store.keyDisplaySpaceSkinTones,
        ]

        preferenceObservationTasks.append(Task { [weak self] in
            for await _ in Defaults.updates(iconKeys, initial: false) {
                // 16ms ≈ one frame at 60 FPS; coalesces rapid changes into a single update
                try? await Task.sleep(for: .milliseconds(16))
                guard !Task.isCancelled
                else { return }
                self?.updateStatusBarIcon()
            }
        })

        let localSpaceNumbersKey = store.keyLocalSpaceNumbers
        preferenceObservationTasks.append(Task { [weak self] in
            for await _ in Defaults.updates(localSpaceNumbersKey, initial: false) {
                guard !Task.isCancelled
                else { return }
                self?.appState.forceSpaceUpdate()
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
        NSEvent.addLocalMonitorForEvents(matching: .otherMouseUp) { [weak self] event in
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
        // Only handle clicks if the setting is enabled
        guard store.clickToSwitchSpaces else {
            return
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

        let targetSpace = slot.targetSpace!

        // For spaces > 16, need yabai (macOS only has hotkeys for 1-16)
        Task {
            if targetSpace > 16 {
                guard await SpaceSwitcher.isYabaiAvailable() else {
                    showYabaiRequiredAlert()
                    return
                }

                if await !SpaceSwitcher.switchToSpaceViaYabai(targetSpace) {
                    showYabaiRequiredAlert()
                }
            } else {
                await spaceSwitcher.switchToSpace(targetSpace)
            }
        }
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
        statusBarItem.length = icon.size.width
        statusBarItem.button?.image = icon
        updateStatusBarVisibility()
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

    private func showPreviewIcon(
        style: IconStyle? = nil,
        symbol: String? = nil,
        foreground: NSColor? = nil,
        background: NSColor? = nil,
        separatorColor: NSColor? = nil,
        clearSymbol: Bool = false,
        skinTone: SkinTone? = nil
    ) {
        guard let statusBarItem else {
            return
        }
        isPreviewingIcon = true
        let previewIcon = appState.generatePreviewIcon(
            overrideStyle: style,
            overrideSymbol: symbol,
            overrideForeground: foreground,
            overrideBackground: background,
            overrideSeparatorColor: separatorColor,
            clearSymbol: clearSymbol,
            skinTone: skinTone
        )
        statusBarItem.length = previewIcon.size.width
        statusBarItem.button?.image = previewIcon
    }

    private func restoreIcon() {
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

    // MARK: - Alert Helpers

    private func showYabaiRequiredAlert() {
        let alert = InfoAlert(
            message: Localization.yabaiRequiredTitle,
            detail: Localization.yabaiRequiredDetail,
            primaryButtonTitle: Localization.buttonLearnMore,
            icon: NSImage(named: "yabai")
        )

        if alert.runModal() {
            if let url = URL(string: "https://github.com/asmvik/yabai/wiki/Installing-yabai-(latest-release)") {
                NSWorkspace.shared.open(url)
            }
        }
    }
}

// MARK: - MenuActionDelegate

extension AppDelegate: MenuActionDelegate {
    func sizeChanged(to scale: Double) {
        store.sizeScale = scale
        updateStatusBarIcon()
        updateStylePickerSizeScales()
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
    }

    func iconStyleSelected(_ style: IconStyle, stylePicker: StylePicker?) {
        actionHandler.selectIconStyle(style, stylePicker: stylePicker)
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

        // Update status bar icon when menu opens
        updateStatusBarIcon()
    }

    func menuDidClose(_: NSMenu) {
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
