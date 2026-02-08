import AppKit
import Defaults
import LaunchAtLogin
import Observation
@preconcurrency import Sparkle
import UniformTypeIdentifiers

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

// MARK: - Confirmation Alert Protocol

/// Protocol for abstracting confirmation alerts for testability
protocol ConfirmationAlertProvider {
    func runModal() -> Bool
}

/// Default implementation using the actual ConfirmationAlert
extension ConfirmationAlert: ConfirmationAlertProvider {}

/// Factory for creating confirmation alerts
protocol ConfirmationAlertFactory {
    func makeAlert(message: String, detail: String, confirmTitle: String, isDestructive: Bool)
        -> ConfirmationAlertProvider
}

/// Default factory that creates real ConfirmationAlerts
struct DefaultConfirmationAlertFactory: ConfirmationAlertFactory {
    func makeAlert(
        message: String,
        detail: String,
        confirmTitle: String,
        isDestructive: Bool
    ) -> ConfirmationAlertProvider {
        ConfirmationAlert(message: message, detail: detail, confirmTitle: confirmTitle, isDestructive: isDestructive)
    }
}

// MARK: - App Delegate

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, SPUStandardUserDriverDelegate {
    // MARK: - Properties

    private let alertFactory: ConfirmationAlertFactory
    private let appState: AppState
    private let spaceSwitcher: SpaceSwitcher
    private var actionHandler: ActionHandler!
    private var menuBuilder: MenuBuilder!
    private var statusBarItem: NSStatusItem!

    private var isPickingForeground = true
    private var isPreviewingIcon = false
    private var launchAtLogin: LaunchAtLoginProvider
    private var preferenceObservationTasks: [Task<Void, Never>] = []
    private var updaterController: SPUStandardUpdaterController!

    private var isHomebrewInstall: Bool {
        AppInfo.isHomebrewInstall
    }

    private(set) var observationTask: Task<Void, Never>?
    private(set) var statusBarIconUpdateCount = 0
    private(set) var statusMenu: NSMenu!

    /// Test hook: continuation that fires whenever updateStatusBarIcon() completes.
    /// Set this from tests to await icon updates deterministically.
    var statusBarIconUpdateNotifier: AsyncStream<Void>.Continuation?

    /// Convenience accessor for the store via appState
    private var store: DefaultsStore {
        appState.store
    }

    // MARK: - Initialization

    /// Default initializer for production use
    override init() {
        let env = AppEnvironment.shared
        appState = env.appState
        alertFactory = DefaultConfirmationAlertFactory()
        launchAtLogin = DefaultLaunchAtLoginProvider()
        spaceSwitcher = SpaceSwitcher()
        super.init()
        configureActionHandler()
    }

    /// Testable initializer with dependency injection
    init(
        appState: AppState,
        alertFactory: ConfirmationAlertFactory,
        launchAtLogin: LaunchAtLoginProvider = DefaultLaunchAtLoginProvider(),
        spaceSwitcher: SpaceSwitcher = SpaceSwitcher()
    ) {
        self.appState = appState
        self.alertFactory = alertFactory
        self.launchAtLogin = launchAtLogin
        self.spaceSwitcher = spaceSwitcher
        super.init()
        configureActionHandler()
    }

    private func configureActionHandler() {
        actionHandler = ActionHandler(
            appState: appState,
            alertFactory: alertFactory,
            launchAtLogin: launchAtLogin,
            onStatusBarIconNeedsUpdate: { [weak self] in
                self?.updateStatusBarIcon()
            },
            onStatusBarVisibilityNeedsUpdate: { [weak self] in
                self?.updateStatusBarVisibility()
            }
        )
    }

    // MARK: - Computed Properties

    private var appName: String {
        AppInfo.appName
    }

    // MARK: - NSApplicationDelegate

    func applicationDidFinishLaunching(_: Notification) {
        // Skip full app setup when running as a test host
        guard ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil else {
            return
        }
        AppMover.moveIfNecessary(appName: appName)
        NSApp.setActivationPolicy(.accessory)
        statusBarItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        updaterController = SPUStandardUpdaterController(
            startingUpdater: !isHomebrewInstall,
            updaterDelegate: nil,
            userDriverDelegate: self
        )
        configureMenuBarIcon()
        startObservingAppState()
        startObservingSpaceChanges()
        startObservingPreferences()

        // Disable click-to-switch if accessibility permission was revoked
        if store.clickToSwitchSpaces, !AXIsProcessTrusted() {
            SettingsInvariantEnforcer.setClickToSwitchSpaces(false, store: store)
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
        statusMenu = menuBuilder.buildMenu(target: self, menuDelegate: self, callbacks: makeMenuCallbacks())
        statusMenu.delegate = self
        statusBarItem?.button?.toolTip = appName
        statusBarItem?.button?.target = self
        statusBarItem?.button?.action = #selector(statusBarButtonClicked(_:))
        statusBarItem?.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
        updateStatusBarIcon()
    }

    private func makeMenuCallbacks() -> MenuBuilderCallbacks {
        var cb = MenuBuilderCallbacks()
        cb.onSizeChanged = { [weak self] scale in
            self?.store.sizeScale = scale
            self?.updateStatusBarIcon()
            self?.updateStylePickerSizeScales()
        }
        cb.onSkinToneSelected = { [weak self] tone in
            guard let self, appState.currentSpace > 0 else {
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
        cb.onSkinToneHoverStart = { [weak self] tone in
            guard let self, let symbol = appState.currentSymbol else {
                return
            }
            self.showPreviewIcon(symbol: symbol, skinTone: tone)
        }
        cb.onForegroundColorSelected = { [weak self] color in
            self?.setForegroundColor(color)
        }
        cb.onBackgroundColorSelected = { [weak self] color in
            self?.setBackgroundColor(color)
        }
        cb.onSeparatorColorSelected = { [weak self] color in
            self?.setSeparatorColor(color)
        }
        cb.onCustomForegroundColorRequested = { [weak self] in
            self?.isPickingForeground = true
            self?.showColorPanel()
        }
        cb.onCustomBackgroundColorRequested = { [weak self] in
            self?.isPickingForeground = false
            self?.showColorPanel()
        }
        cb.onCustomSeparatorColorRequested = { [weak self] in
            self?.showSeparatorColorPanel()
        }
        cb.onSymbolSelected = { [weak self] item in
            self?.setSymbol(item)
        }
        cb.onIconStyleSelected = { [weak self] style, stylePicker in
            self?.selectIconStyle(style, stylePicker: stylePicker)
        }
        cb.onColorHoverStart = { [weak self] index, isForeground in
            if isForeground {
                self?.showPreviewIcon(foreground: ColorSwatch.presetColors[index])
            } else {
                self?.showPreviewIcon(background: ColorSwatch.presetColors[index])
            }
        }
        cb.onBackgroundColorHoverStart = { [weak self] index in
            self?.showPreviewIcon(background: ColorSwatch.presetColors[index])
        }
        cb.onSeparatorColorHoverStart = { [weak self] index in
            self?.showPreviewIcon(separatorColor: ColorSwatch.presetColors[index])
        }
        cb.onSymbolHoverStart = { [weak self] item, foreground, background, skinTone in
            self?.showPreviewIcon(symbol: item, foreground: foreground, background: background, skinTone: skinTone)
        }
        cb.onStyleHoverStart = { [weak self] style in
            self?.showPreviewIcon(style: style, clearSymbol: true)
        }
        cb.onHoverEnd = { [weak self] in
            self?.restoreIcon()
        }
        return cb
    }

    @objc private func statusBarButtonClicked(_ button: NSStatusBarButton) {
        guard let event = NSApp.currentEvent else {
            return
        }

        if event.type == .rightMouseUp {
            guard let button = statusBarItem?.button else {
                return
            }
            let position = NSPoint(x: 0, y: button.bounds.height + 5)
            statusMenu.popUp(positioning: nil, at: position, in: button)
        } else if event.type == .leftMouseUp {
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
            SettingsInvariantEnforcer.setClickToSwitchSpaces(false, store: store)
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
        statusBarIconUpdateNotifier?.yield()
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
        let foreground = appState.currentColors?.foregroundColor ?? defaults.foreground
        let background = appState.currentColors?.backgroundColor ?? defaults.background
        showPreviewIcon(foreground: background, background: foreground)
    }

    // MARK: - Action Forwarding Stubs

    //
    // These @objc methods forward to ActionHandler, which contains the real implementations.
    // They exist so that #selector(AppDelegate.methodName) references in MenuBuilder and
    // existing tests continue to work without modification.

    @objc func toggleDimInactiveSpaces() {
        actionHandler.toggleDimInactiveSpaces()
    }

    @objc func toggleHideEmptySpaces() {
        actionHandler.toggleHideEmptySpaces()
    }

    @objc func toggleHideFullscreenApps() {
        actionHandler.toggleHideFullscreenApps()
    }

    @objc func toggleHideSingleSpace() {
        actionHandler.toggleHideSingleSpace()
    }

    @objc func toggleLaunchAtLogin() {
        actionHandler.toggleLaunchAtLogin()
    }

    @objc func toggleShowAllDisplays() {
        actionHandler.toggleShowAllDisplays()
    }

    @objc func toggleShowAllSpaces() {
        actionHandler.toggleShowAllSpaces()
    }

    @objc func toggleClickToSwitchSpaces() {
        actionHandler.toggleClickToSwitchSpaces()
    }

    @objc func toggleLocalSpaceNumbers() {
        actionHandler.toggleLocalSpaceNumbers()
    }

    @objc func toggleUniqueIconsPerDisplay() {
        actionHandler.toggleUniqueIconsPerDisplay()
    }

    @objc func checkForUpdates() {
        NSApp.activate(ignoringOtherApps: true)
        updaterController.checkForUpdates(nil)
    }

    @objc func selectSound(_ sender: NSMenuItem) {
        actionHandler.selectSound(sender)
    }

    @objc func invertColors() {
        actionHandler.invertColors()
    }

    @objc func applyColorsToAllSpaces() {
        actionHandler.applyColorsToAllSpaces()
    }

    @objc func resetColorToDefault() {
        actionHandler.resetColorToDefault()
    }

    @objc func applyStyleToAllSpaces() {
        actionHandler.applyStyleToAllSpaces()
    }

    @objc func resetStyleToDefault() {
        actionHandler.resetStyleToDefault()
    }

    @objc func applyToAllSpaces() {
        actionHandler.applyToAllSpaces()
    }

    @objc func resetSpaceToDefault() {
        actionHandler.resetSpaceToDefault()
    }

    @objc func resetAllSpacesToDefault() {
        actionHandler.resetAllSpacesToDefault()
    }

    @objc func importSettings() {
        actionHandler.importSettings()
    }

    @objc func exportSettings() {
        actionHandler.exportSettings()
    }

    func setForegroundColor(_ color: NSColor) {
        actionHandler.setForegroundColor(color)
    }

    func setBackgroundColor(_ color: NSColor) {
        actionHandler.setBackgroundColor(color)
    }

    private func setSeparatorColor(_ color: NSColor) {
        store.separatorColor = color
        updateStatusBarIcon()
    }

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
        store.separatorColor = sender.color
        updateStatusBarIcon()
    }

    private func showColorPanel() {
        NSApp.activate(ignoringOtherApps: true)

        let colorPanel = NSColorPanel.shared
        colorPanel.setTarget(self)
        colorPanel.setAction(#selector(colorChanged(_:)))
        colorPanel.isContinuous = true

        if let colors = appState.currentColors {
            colorPanel.color = isPickingForeground ? colors.foregroundColor : colors.backgroundColor
        } else {
            colorPanel.color = isPickingForeground ? .white : .black
        }

        colorPanel.makeKeyAndOrderFront(nil)
    }

    @objc private func colorChanged(_ sender: NSColorPanel) {
        guard appState.currentSpace > 0 else {
            return
        }

        let existingColors = appState.currentColors
        let defaults = IconColors.filledColors(darkMode: appState.darkModeEnabled)
        let foreground = isPickingForeground ? sender.color : (existingColors?.foregroundColor ?? defaults.foreground)
        let background = isPickingForeground ? (existingColors?.backgroundColor ?? defaults.background) : sender.color

        SpacePreferences.setColors(
            SpaceColors(foreground: foreground, background: background),
            forSpace: appState.currentSpace,
            display: appState.currentDisplayID,
            store: store
        )
        updateStatusBarIcon()
    }

    private func selectIconStyle(_ style: IconStyle, stylePicker: StylePicker?) {
        guard appState.currentSpace > 0 else {
            return
        }

        // Clear SF Symbol to switch to number mode
        SpacePreferences.clearSymbol(
            forSpace: appState.currentSpace,
            display: appState.currentDisplayID,
            store: store
        )
        SpacePreferences.setIconStyle(
            style,
            forSpace: appState.currentSpace,
            display: appState.currentDisplayID,
            store: store
        )

        // Update checkmarks in all row views
        if let menu = stylePicker?.enclosingMenuItem?.menu {
            for item in menu.items {
                if let view = item.view as? StylePicker {
                    view.isChecked = item.representedObject as? IconStyle == style
                }
            }
        }

        updateStatusBarIcon()
    }

    private func setSymbol(_ symbol: String?) {
        guard appState.currentSpace > 0 else {
            return
        }
        SpacePreferences.setSymbol(
            symbol,
            forSpace: appState.currentSpace,
            display: appState.currentDisplayID,
            store: store
        )
        // When setting an emoji, also set the per-space skin tone to match the current global picker tone
        if let symbol, symbol.containsEmoji {
            SpacePreferences.setSkinTone(
                Defaults[.emojiPickerSkinTone],
                forSpace: appState.currentSpace,
                display: appState.currentDisplayID,
                store: store
            )
        }
        updateStatusBarIcon()
    }

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

    @objc func resetFontToDefault() {
        actionHandler.resetFontToDefault()
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
