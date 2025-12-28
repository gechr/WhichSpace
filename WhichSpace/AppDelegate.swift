import AppKit
import Combine
import Defaults
import LaunchAtLogin
import Observation
@preconcurrency import Sparkle

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
    private var statusBarItem: NSStatusItem!

    private var isPickingForeground = true
    private var isPreviewingIcon = false
    private var launchAtLogin: LaunchAtLoginProvider
    private var preferenceCancellables = Set<AnyCancellable>()
    private var updaterController: SPUStandardUpdaterController!

    private(set) var observationTask: Task<Void, Never>?
    private(set) var statusBarIconUpdateCount = 0
    private(set) var statusMenu: NSMenu!

    /// Test hook: continuation that fires whenever updateStatusBarIcon() completes.
    /// Set this from tests to await icon updates deterministically.
    var statusBarIconUpdateNotifier: AsyncStream<Void>.Continuation?

    /// Convenience accessor for the store via appState
    private var store: DefaultsStore { appState.store }

    // MARK: - Initialization

    /// Default initializer for production use
    override init() {
        appState = AppState.shared
        alertFactory = DefaultConfirmationAlertFactory()
        launchAtLogin = DefaultLaunchAtLoginProvider()
        super.init()
    }

    /// Testable initializer with dependency injection
    init(
        appState: AppState,
        alertFactory: ConfirmationAlertFactory,
        launchAtLogin: LaunchAtLoginProvider = DefaultLaunchAtLoginProvider()
    ) {
        self.appState = appState
        self.alertFactory = alertFactory
        self.launchAtLogin = launchAtLogin
        super.init()
    }

    // MARK: - Computed Properties

    private var appName: String {
        Bundle.main.infoDictionary?["CFBundleName"] as? String ?? "WhichSpace"
    }

    // MARK: - NSApplicationDelegate

    func applicationDidFinishLaunching(_: Notification) {
        Relocator.moveIfNecessary(appName: appName)
        NSApp.setActivationPolicy(.accessory)
        statusBarItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        updaterController = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: self
        )
        configureMenuBarIcon()
        startObservingAppState()
        startObservingSpaceChanges()
        startObservingPreferences()

        // Disable click-to-switch if accessibility permission was revoked
        if store.clickToSwitchSpaces, !AXIsProcessTrusted() {
            store.clickToSwitchSpaces = false
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
        let sound = NSSound(named: NSSound.Name(soundName))?.copy() as? NSSound
        sound?.play()
    }

    /// Observes preference changes that affect the status bar icon using Combine publishers
    private func startObservingPreferences() {
        func voidPublisher(_ key: Defaults.Key<some Any>) -> AnyPublisher<Void, Never> {
            Defaults.publisher(key)
                .map { _ in () }
                .eraseToAnyPublisher()
        }

        let localSpaceNumbersPublisher = voidPublisher(store.keyLocalSpaceNumbers)

        let displayModePublishers: [AnyPublisher<Void, Never>] = [
            voidPublisher(store.keyShowAllSpaces),
            voidPublisher(store.keyShowAllDisplays),
            voidPublisher(store.keyDimInactiveSpaces),
            voidPublisher(store.keyHideEmptySpaces),
            voidPublisher(store.keyHideFullscreenApps),
            voidPublisher(store.keyUniqueIconsPerDisplay),
            localSpaceNumbersPublisher,
        ]

        let appearancePublishers: [AnyPublisher<Void, Never>] = [
            voidPublisher(store.keySizeScale),
            voidPublisher(store.keySeparatorColor),
            voidPublisher(store.keySpaceColors),
            voidPublisher(store.keySpaceIconStyles),
            voidPublisher(store.keySpaceSymbols),
            voidPublisher(store.keySpaceFonts),
            voidPublisher(store.keySpaceSkinTones),
        ]

        let perDisplayPublishers: [AnyPublisher<Void, Never>] = [
            voidPublisher(store.keyDisplaySpaceColors),
            voidPublisher(store.keyDisplaySpaceIconStyles),
            voidPublisher(store.keyDisplaySpaceSymbols),
            voidPublisher(store.keyDisplaySpaceFonts),
            voidPublisher(store.keyDisplaySpaceSkinTones),
        ]

        let allPublishers = displayModePublishers + appearancePublishers + perDisplayPublishers

        Publishers.MergeMany(allPublishers)
            // 16ms ≈ one frame at 60 FPS; coalesces rapid changes into a single update
            .debounce(for: .milliseconds(16), scheduler: DispatchQueue.main)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in
                self?.updateStatusBarIcon()
            }
            .store(in: &preferenceCancellables)

        localSpaceNumbersPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in
                // Refresh the cached labels so numbering changes apply immediately
                self?.appState.forceSpaceUpdate()
            }
            .store(in: &preferenceCancellables)
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
        statusMenu = NSMenu()
        configureVersionHeader()
        configureColorMenuItem()
        configureStyleMenuItem()
        configureSoundMenuItem()
        configureSizeMenuItem()
        configureOptionsMenuItems()
        configureLaunchAtLoginMenuItem()
        configureUpdateAndQuitMenuItems()
        statusMenu.delegate = self
        statusBarItem?.button?.toolTip = appName
        statusBarItem?.button?.target = self
        statusBarItem?.button?.action = #selector(statusBarButtonClicked(_:))
        statusBarItem?.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
        updateStatusBarIcon()
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
            store.clickToSwitchSpaces = false
            return
        }

        let layout = appState.statusBarLayout()
        guard !layout.slots.isEmpty else {
            return
        }

        let location = button.convert(event.locationInWindow, from: nil)
        let clickX = Double(location.x)

        // Use StatusBarLayout hit testing
        guard let targetSpace = layout.targetSpace(at: clickX) else {
            return
        }

        // For spaces > 16, need yabai (macOS only has hotkeys for 1-16)
        if targetSpace > 16 {
            guard SpaceSwitcher.isYabaiAvailable() else {
                showYabaiRequiredAlert()
                return
            }

            if !SpaceSwitcher.switchToSpaceViaYabai(targetSpace) {
                showYabaiRequiredAlert()
            }
        } else {
            SpaceSwitcher.switchToSpace(targetSpace)
        }
    }

    private func configureVersionHeader() {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        let versionItem = NSMenuItem(title: "\(appName) v\(version)", action: nil, keyEquivalent: "")
        versionItem.isEnabled = false
        versionItem.toolTip = "https://github.com/gechr/WhichSpace"
        if let icon = NSApp.applicationIconImage {
            let resized = NSImage(size: NSSize(width: 16, height: 16))
            resized.lockFocus()
            icon.draw(in: NSRect(x: 0, y: 0, width: 16, height: 16))
            resized.unlockFocus()
            versionItem.image = resized
        }
        statusMenu.addItem(versionItem)
        statusMenu.addItem(.separator())
    }

    private func configureColorMenuItem() {
        let colorsMenu = createColorMenu()
        let colorsMenuItem = NSMenuItem(title: Localization.menuColor, action: nil, keyEquivalent: "")
        colorsMenuItem.tag = MenuTag.colorMenuItem.rawValue
        colorsMenuItem.image = NSImage(systemSymbolName: "paintpalette", accessibilityDescription: nil)
        colorsMenuItem.submenu = colorsMenu
        statusMenu.addItem(colorsMenuItem)
    }

    private func configureStyleMenuItem() {
        let styleMenu = NSMenu(title: Localization.menuStyle)
        styleMenu.delegate = self

        // Number submenu (icon shapes)
        let iconMenu = createIconMenu()
        let iconMenuItem = NSMenuItem(title: Localization.menuNumber, action: nil, keyEquivalent: "")
        iconMenuItem.image = NSImage(systemSymbolName: "textformat.123", accessibilityDescription: nil)
        iconMenuItem.submenu = iconMenu
        styleMenu.addItem(iconMenuItem)

        // Symbol submenu
        let symbolMenu = createItemMenu(type: .symbols)
        let symbolMenuItem = NSMenuItem(title: Localization.menuSymbol, action: nil, keyEquivalent: "")
        symbolMenuItem.image = NSImage(systemSymbolName: "burst.fill", accessibilityDescription: nil)
        symbolMenuItem.submenu = symbolMenu
        styleMenu.addItem(symbolMenuItem)

        // Emoji submenu
        let emojiMenu = createItemMenu(type: .emojis)
        let emojiMenuItem = NSMenuItem(title: Localization.menuEmoji, action: nil, keyEquivalent: "")
        emojiMenuItem.image = NSImage(systemSymbolName: "face.smiling", accessibilityDescription: nil)
        emojiMenuItem.submenu = emojiMenu
        styleMenu.addItem(emojiMenuItem)

        styleMenu.addItem(.separator())

        let applyStyleItem = NSMenuItem(
            title: Localization.actionApplyStyleToAll,
            action: #selector(applyStyleToAllSpaces),
            keyEquivalent: ""
        )
        applyStyleItem.target = self
        applyStyleItem.image = NSImage(systemSymbolName: "square.on.square", accessibilityDescription: nil)
        applyStyleItem.toolTip = Localization.tipApplyStyleToAll
        styleMenu.addItem(applyStyleItem)

        let resetStyleItem = NSMenuItem(
            title: Localization.actionResetStyleToDefault,
            action: #selector(resetStyleToDefault),
            keyEquivalent: ""
        )
        resetStyleItem.target = self
        resetStyleItem.image = NSImage(systemSymbolName: "arrow.uturn.backward", accessibilityDescription: nil)
        resetStyleItem.toolTip = Localization.tipResetStyleToDefault
        styleMenu.addItem(resetStyleItem)

        let styleMenuItem = NSMenuItem(title: Localization.menuStyle, action: nil, keyEquivalent: "")
        styleMenuItem.image = NSImage(systemSymbolName: "photo.artframe", accessibilityDescription: nil)
        styleMenuItem.submenu = styleMenu
        statusMenu.addItem(styleMenuItem)
    }

    private func configureSizeMenuItem() {
        let sizeMenu = NSMenu(title: Localization.menuSize)
        sizeMenu.delegate = self

        // Size scale row (percentage)
        let sizeItem = NSMenuItem()
        sizeItem.tag = MenuTag.sizeRow.rawValue
        let sizeSlider = SizeSlider(
            initialSize: store.sizeScale,
            range: Layout.sizeScaleRange
        )
        sizeSlider.frame = NSRect(origin: .zero, size: sizeSlider.intrinsicContentSize)
        sizeSlider.onSizeChanged = { [weak self] scale in
            self?.store.sizeScale = scale
            self?.updateStatusBarIcon()
            self?.updateStylePickerSizeScales()
        }
        sizeItem.view = sizeSlider
        sizeMenu.addItem(sizeItem)

        let sizeMenuItem = NSMenuItem(title: Localization.menuSize, action: nil, keyEquivalent: "")
        sizeMenuItem.image = NSImage(
            systemSymbolName: "arrow.up.left.and.down.right.and.arrow.up.right.and.down.left",
            accessibilityDescription: nil
        )
        sizeMenuItem.submenu = sizeMenu
        statusMenu.addItem(sizeMenuItem)
        statusMenu.addItem(.separator())
    }

    private func configureSoundMenuItem() {
        let soundMenu = createSoundMenu()
        let soundMenuItem = NSMenuItem(title: Localization.menuSound, action: nil, keyEquivalent: "")
        soundMenuItem.image = NSImage(systemSymbolName: "speaker.wave.2", accessibilityDescription: nil)
        soundMenuItem.submenu = soundMenu
        statusMenu.addItem(soundMenuItem)
    }

    // MARK: Sound Menu

    /// Available sounds from a directory (discovered once at startup)
    private static func discoverSounds(in directory: URL) -> [String] {
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.contentTypeKey]
        ) else {
            return []
        }
        var sounds = Set<String>()
        for url in contents {
            guard let type = try? url.resourceValues(forKeys: [.contentTypeKey]).contentType,
                  type.conforms(to: .audio)
            else {
                continue
            }
            sounds.insert(url.deletingPathExtension().lastPathComponent)
        }
        return sounds.sorted()
    }

    private static let systemSounds = discoverSounds(in: URL(fileURLWithPath: "/System/Library/Sounds"))
    private static let userSounds = discoverSounds(
        in: FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Sounds")
    )

    private func createSoundMenu() -> NSMenu {
        let soundMenu = NSMenu(title: Localization.menuSound)
        soundMenu.delegate = self

        // "None" option at top (disables sound)
        let noneItem = NSMenuItem(
            title: Localization.soundNone,
            action: #selector(selectSound(_:)),
            keyEquivalent: ""
        )
        noneItem.target = self
        noneItem.representedObject = "" // Empty string = no sound
        noneItem.state = store.soundName.isEmpty ? .on : .off
        soundMenu.addItem(noneItem)

        soundMenu.addItem(.separator())

        let hasUserSounds = !Self.userSounds.isEmpty

        // User sounds (only if they exist)
        if hasUserSounds {
            let header = NSMenuItem(title: Localization.soundUser, action: nil, keyEquivalent: "")
            header.isEnabled = false
            soundMenu.addItem(header)

            for soundName in Self.userSounds {
                let item = NSMenuItem(
                    title: soundName,
                    action: #selector(selectSound(_:)),
                    keyEquivalent: ""
                )
                item.target = self
                item.representedObject = soundName
                item.state = store.soundName == soundName ? .on : .off
                soundMenu.addItem(item)
            }

            soundMenu.addItem(.separator())
            let systemHeader = NSMenuItem(title: Localization.soundSystem, action: nil, keyEquivalent: "")
            systemHeader.isEnabled = false
            soundMenu.addItem(systemHeader)
        }

        // System sounds
        for soundName in Self.systemSounds {
            let item = NSMenuItem(
                title: soundName,
                action: #selector(selectSound(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.representedObject = soundName
            item.state = store.soundName == soundName ? .on : .off
            soundMenu.addItem(item)
        }

        return soundMenu
    }

    @objc private func selectSound(_ sender: NSMenuItem) {
        guard let soundName = sender.representedObject as? String else {
            return
        }

        store.soundName = soundName
    }

    private func configureOptionsMenuItems() {
        let localSpaceNumbersItem = NSMenuItem(
            title: Localization.toggleLocalSpaceNumbers,
            action: #selector(toggleLocalSpaceNumbers),
            keyEquivalent: ""
        )
        localSpaceNumbersItem.target = self
        localSpaceNumbersItem.tag = MenuTag.localSpaceNumbers.rawValue
        let localSpaceNumbersConfig = NSImage.SymbolConfiguration(pointSize: 18, weight: .medium)
        localSpaceNumbersItem.image = NSImage(
            systemSymbolName: "1.square",
            accessibilityDescription: nil
        )?.withSymbolConfiguration(localSpaceNumbersConfig)
        localSpaceNumbersItem.toolTip = Localization.tipLocalSpaceNumbers
        statusMenu.addItem(localSpaceNumbersItem)

        let uniqueIconsPerDisplayItem = NSMenuItem(
            title: Localization.toggleUniqueIconsPerDisplay,
            action: #selector(toggleUniqueIconsPerDisplay),
            keyEquivalent: ""
        )
        uniqueIconsPerDisplayItem.target = self
        uniqueIconsPerDisplayItem.tag = MenuTag.uniqueIconsPerDisplay.rawValue
        uniqueIconsPerDisplayItem.image = NSImage(
            systemSymbolName: "theatermasks",
            accessibilityDescription: nil
        )
        uniqueIconsPerDisplayItem.toolTip = Localization.tipUniqueIconsPerDisplay
        statusMenu.addItem(uniqueIconsPerDisplayItem)

        let dimInactiveSpacesItem = NSMenuItem(
            title: Localization.toggleDimInactiveSpaces,
            action: #selector(toggleDimInactiveSpaces),
            keyEquivalent: ""
        )
        dimInactiveSpacesItem.target = self
        dimInactiveSpacesItem.tag = MenuTag.dimInactiveSpaces.rawValue
        dimInactiveSpacesItem.image = NSImage(
            systemSymbolName: "aqi.low",
            accessibilityDescription: nil
        )
        dimInactiveSpacesItem.toolTip = Localization.tipDimInactiveSpaces
        statusMenu.addItem(dimInactiveSpacesItem)

        statusMenu.addItem(NSMenuItem.separator())

        let showAllDisplaysItem = NSMenuItem(
            title: Localization.toggleShowAllDisplays,
            action: #selector(toggleShowAllDisplays),
            keyEquivalent: ""
        )
        showAllDisplaysItem.target = self
        showAllDisplaysItem.tag = MenuTag.showAllDisplays.rawValue
        showAllDisplaysItem.image = NSImage(
            systemSymbolName: "display.2",
            accessibilityDescription: nil
        )
        showAllDisplaysItem.toolTip = Localization.tipShowAllDisplays
        statusMenu.addItem(showAllDisplaysItem)

        let showAllSpacesItem = NSMenuItem(
            title: Localization.toggleShowAllSpaces,
            action: #selector(toggleShowAllSpaces),
            keyEquivalent: ""
        )
        showAllSpacesItem.target = self
        showAllSpacesItem.tag = MenuTag.showAllSpaces.rawValue
        showAllSpacesItem.image = NSImage(
            systemSymbolName: "square.grid.3x1.below.line.grid.1x2",
            accessibilityDescription: nil
        )
        showAllSpacesItem.toolTip = Localization.tipShowAllSpaces
        statusMenu.addItem(showAllSpacesItem)

        let clickToSwitchItem = NSMenuItem(
            title: Localization.toggleClickToSwitchSpaces,
            action: #selector(toggleClickToSwitchSpaces),
            keyEquivalent: ""
        )
        clickToSwitchItem.target = self
        clickToSwitchItem.tag = MenuTag.clickToSwitchSpaces.rawValue
        clickToSwitchItem.image = NSImage(
            systemSymbolName: "hand.tap.fill",
            accessibilityDescription: nil
        )
        clickToSwitchItem.toolTip = Localization.tipClickToSwitchSpaces
        statusMenu.addItem(clickToSwitchItem)

        statusMenu.addItem(NSMenuItem.separator())

        let hideEmptySpacesItem = NSMenuItem(
            title: Localization.toggleHideEmptySpaces,
            action: #selector(toggleHideEmptySpaces),
            keyEquivalent: ""
        )
        hideEmptySpacesItem.target = self
        hideEmptySpacesItem.tag = MenuTag.hideEmptySpaces.rawValue
        hideEmptySpacesItem.image = NSImage(
            systemSymbolName: "eye.slash",
            accessibilityDescription: nil
        )
        hideEmptySpacesItem.toolTip = Localization.tipHideEmptySpaces
        statusMenu.addItem(hideEmptySpacesItem)

        let hideFullscreenAppsItem = NSMenuItem(
            title: Localization.toggleHideFullscreenApps,
            action: #selector(toggleHideFullscreenApps),
            keyEquivalent: ""
        )
        hideFullscreenAppsItem.target = self
        hideFullscreenAppsItem.tag = MenuTag.hideFullscreenApps.rawValue
        hideFullscreenAppsItem.image = NSImage(
            systemSymbolName: "eye.slash.fill",
            accessibilityDescription: nil
        )
        hideFullscreenAppsItem.toolTip = Localization.tipHideFullscreenApps
        statusMenu.addItem(hideFullscreenAppsItem)
        statusMenu.addItem(.separator())

        let applyToAllItem = NSMenuItem(
            title: Localization.actionApplyToAll,
            action: #selector(applyToAllSpaces),
            keyEquivalent: ""
        )
        applyToAllItem.target = self
        applyToAllItem.image = NSImage(systemSymbolName: "square.on.square", accessibilityDescription: nil)
        applyToAllItem.toolTip = Localization.tipApplyToAll
        statusMenu.addItem(applyToAllItem)

        let resetItem = NSMenuItem(
            title: Localization.actionResetSpaceToDefault,
            action: #selector(resetSpaceToDefault),
            keyEquivalent: ""
        )
        resetItem.target = self
        resetItem.image = NSImage(systemSymbolName: "arrow.uturn.backward", accessibilityDescription: nil)
        resetItem.toolTip = Localization.tipResetSpaceToDefault
        statusMenu.addItem(resetItem)

        let resetAllItem = NSMenuItem(
            title: Localization.actionResetAllSpacesToDefault,
            action: #selector(resetAllSpacesToDefault),
            keyEquivalent: ""
        )
        resetAllItem.target = self
        resetAllItem.image = NSImage(systemSymbolName: "arrow.triangle.2.circlepath", accessibilityDescription: nil)
        resetAllItem.toolTip = Localization.tipResetAllSpacesToDefault
        statusMenu.addItem(resetAllItem)
        statusMenu.addItem(.separator())
    }

    private func configureLaunchAtLoginMenuItem() {
        let launchAtLoginItem = NSMenuItem(
            title: Localization.toggleLaunchAtLogin,
            action: #selector(toggleLaunchAtLogin),
            keyEquivalent: ""
        )
        launchAtLoginItem.target = self
        launchAtLoginItem.tag = MenuTag.launchAtLogin.rawValue
        launchAtLoginItem.image = NSImage(systemSymbolName: "sunrise", accessibilityDescription: nil)
        launchAtLoginItem.toolTip = String(format: Localization.tipLaunchAtLogin, appName)
        statusMenu.addItem(launchAtLoginItem)
    }

    private func configureUpdateAndQuitMenuItems() {
        let updateItem = NSMenuItem(
            title: Localization.actionCheckForUpdates,
            action: #selector(checkForUpdates),
            keyEquivalent: ""
        )
        updateItem.target = self
        updateItem.image = NSImage(systemSymbolName: "square.and.arrow.down", accessibilityDescription: nil)
        updateItem.toolTip = String(format: Localization.tipCheckForUpdates, appName)
        statusMenu.addItem(updateItem)
        statusMenu.addItem(.separator())

        let quitItem = NSMenuItem(
            title: Localization.actionQuit,
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: ""
        )
        quitItem.image = NSImage(systemSymbolName: "xmark.rectangle", accessibilityDescription: nil)
        quitItem.toolTip = String(format: Localization.tipQuit, appName)
        statusMenu.addItem(quitItem)

        // NSMenu clips bottom padding when containing custom view-backed items, so add
        // an invisible spacer to compensate.
        let spacer = NSMenuItem()
        spacer.isEnabled = false
        spacer.view = NSView(frame: NSRect(x: 0, y: 0, width: 1, height: 5))
        statusMenu.addItem(spacer)
    }

    // MARK: Color Menu

    private func createColorMenu() -> NSMenu {
        let colorsMenu = NSMenu(title: Localization.menuColor)
        colorsMenu.delegate = self

        // Skin tone label (shown only when emoji active)
        let skinToneLabelItem = NSMenuItem(title: Localization.labelSkinTone, action: nil, keyEquivalent: "")
        skinToneLabelItem.isEnabled = false
        skinToneLabelItem.tag = MenuTag.skinToneLabel.rawValue
        skinToneLabelItem.isHidden = true
        colorsMenu.addItem(skinToneLabelItem)

        // Skin tone swatch (shown only when emoji active)
        let skinToneSwatchItem = NSMenuItem()
        skinToneSwatchItem.tag = MenuTag.skinToneSwatch.rawValue
        skinToneSwatchItem.isHidden = true
        let skinToneSwatch = SkinToneSwatch()
        skinToneSwatch.frame = NSRect(origin: .zero, size: skinToneSwatch.intrinsicContentSize)
        skinToneSwatch.onToneSelected = { [weak self] tone in
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
            skinToneSwatch.currentTone = tone
        }
        skinToneSwatch.onToneHoverStart = { [weak self] tone in
            guard let self, let symbol = appState.currentSymbol else {
                return
            }
            self.showPreviewIcon(symbol: symbol, skinTone: tone)
        }
        skinToneSwatch.onHoverEnd = { [weak self] in
            self?.restoreIcon()
        }
        skinToneSwatchItem.view = skinToneSwatch
        colorsMenu.addItem(skinToneSwatchItem)

        // Symbol label (shown only when symbol active)
        let symbolLabelItem = NSMenuItem(title: Localization.labelSymbol, action: nil, keyEquivalent: "")
        symbolLabelItem.isEnabled = false
        symbolLabelItem.tag = MenuTag.symbolLabel.rawValue
        symbolLabelItem.isHidden = true
        colorsMenu.addItem(symbolLabelItem)

        // Symbol color swatch (shown only when symbol active)
        let symbolSwatchItem = NSMenuItem()
        symbolSwatchItem.tag = MenuTag.symbolColorSwatch.rawValue
        symbolSwatchItem.isHidden = true
        let symbolSwatch = ColorSwatch()
        symbolSwatch.frame = NSRect(origin: .zero, size: symbolSwatch.intrinsicContentSize)
        symbolSwatch.onColorSelected = { [weak self] color in
            self?.setForegroundColor(color)
        }
        symbolSwatch.onCustomColorRequested = { [weak self] in
            self?.isPickingForeground = true
            self?.showColorPanel()
        }
        symbolSwatch.onHoverStart = { [weak self] index in
            guard index < ColorSwatch.presetColors.count else {
                return
            }
            self?.showPreviewIcon(foreground: ColorSwatch.presetColors[index])
        }
        symbolSwatch.onHoverEnd = { [weak self] in
            self?.restoreIcon()
        }
        symbolSwatchItem.view = symbolSwatch
        colorsMenu.addItem(symbolSwatchItem)

        // Foreground label (hidden when symbol active)
        let foregroundLabel = NSMenuItem(title: Localization.labelNumberForeground, action: nil, keyEquivalent: "")
        foregroundLabel.isEnabled = false
        foregroundLabel.tag = MenuTag.foregroundLabel.rawValue
        colorsMenu.addItem(foregroundLabel)

        // Foreground color swatches (hidden when symbol active)
        let foregroundSwatchItem = NSMenuItem()
        foregroundSwatchItem.tag = MenuTag.foregroundSwatch.rawValue
        let foregroundSwatch = ColorSwatch()
        foregroundSwatch.frame = NSRect(origin: .zero, size: foregroundSwatch.intrinsicContentSize)
        foregroundSwatch.onColorSelected = { [weak self] color in
            self?.setForegroundColor(color)
        }
        foregroundSwatch.onCustomColorRequested = { [weak self] in
            self?.isPickingForeground = true
            self?.showColorPanel()
        }
        foregroundSwatch.onHoverStart = { [weak self] index in
            guard index < ColorSwatch.presetColors.count else {
                return
            }
            self?.showPreviewIcon(foreground: ColorSwatch.presetColors[index])
        }
        foregroundSwatch.onHoverEnd = { [weak self] in
            self?.restoreIcon()
        }
        foregroundSwatchItem.view = foregroundSwatch
        colorsMenu.addItem(foregroundSwatchItem)

        // Separator (hidden when symbol active)
        let separator = NSMenuItem.separator()
        separator.tag = MenuTag.colorSeparator.rawValue
        colorsMenu.addItem(separator)

        // Background label (hidden when symbol active)
        let backgroundLabel = NSMenuItem(title: Localization.labelNumberBackground, action: nil, keyEquivalent: "")
        backgroundLabel.isEnabled = false
        backgroundLabel.tag = MenuTag.backgroundLabel.rawValue
        colorsMenu.addItem(backgroundLabel)

        // Background color swatches (hidden when symbol active)
        let backgroundSwatchItem = NSMenuItem()
        backgroundSwatchItem.tag = MenuTag.backgroundSwatch.rawValue
        let backgroundSwatch = ColorSwatch()
        backgroundSwatch.frame = NSRect(origin: .zero, size: backgroundSwatch.intrinsicContentSize)
        backgroundSwatch.onColorSelected = { [weak self] color in
            self?.setBackgroundColor(color)
        }
        backgroundSwatch.onCustomColorRequested = { [weak self] in
            self?.isPickingForeground = false
            self?.showColorPanel()
        }
        backgroundSwatch.onHoverStart = { [weak self] index in
            guard index < ColorSwatch.presetColors.count else {
                return
            }
            self?.showPreviewIcon(background: ColorSwatch.presetColors[index])
        }
        backgroundSwatch.onHoverEnd = { [weak self] in
            self?.restoreIcon()
        }
        backgroundSwatchItem.view = backgroundSwatch
        colorsMenu.addItem(backgroundSwatchItem)

        // Separator color section (shown only when Show all Displays is enabled)
        let separatorColorDivider = NSMenuItem.separator()
        separatorColorDivider.tag = MenuTag.separatorColorDivider.rawValue
        separatorColorDivider.isHidden = true
        colorsMenu.addItem(separatorColorDivider)

        let separatorLabelItem = NSMenuItem(title: Localization.labelSeparator, action: nil, keyEquivalent: "")
        separatorLabelItem.isEnabled = false
        separatorLabelItem.tag = MenuTag.separatorLabel.rawValue
        separatorLabelItem.isHidden = true
        colorsMenu.addItem(separatorLabelItem)

        let separatorSwatchItem = NSMenuItem()
        separatorSwatchItem.tag = MenuTag.separatorSwatch.rawValue
        separatorSwatchItem.isHidden = true
        let separatorSwatch = ColorSwatch()
        separatorSwatch.frame = NSRect(origin: .zero, size: separatorSwatch.intrinsicContentSize)
        separatorSwatch.onColorSelected = { [weak self] color in
            self?.setSeparatorColor(color)
        }
        separatorSwatch.onCustomColorRequested = { [weak self] in
            self?.showSeparatorColorPanel()
        }
        separatorSwatch.onHoverStart = { [weak self] index in
            guard index < ColorSwatch.presetColors.count else {
                return
            }
            self?.showPreviewIcon(separatorColor: ColorSwatch.presetColors[index])
        }
        separatorSwatch.onHoverEnd = { [weak self] in
            self?.restoreIcon()
        }
        separatorSwatchItem.view = separatorSwatch
        colorsMenu.addItem(separatorSwatchItem)

        // Separator before actions
        colorsMenu.addItem(.separator())

        let invertColorsItem = NSMenuItem(
            title: Localization.actionInvertColors,
            action: #selector(invertColors),
            keyEquivalent: ""
        )
        invertColorsItem.tag = MenuTag.invertColors.rawValue
        invertColorsItem.target = self
        invertColorsItem.image = NSImage(systemSymbolName: "arrow.left.arrow.right", accessibilityDescription: nil)
        invertColorsItem.toolTip = Localization.tipInvertColors
        colorsMenu.addItem(invertColorsItem)
        colorsMenu.addItem(.separator())

        let applyToAllItem = NSMenuItem(
            title: Localization.actionApplyColorToAll,
            action: #selector(applyColorsToAllSpaces),
            keyEquivalent: ""
        )
        applyToAllItem.target = self
        applyToAllItem.image = NSImage(systemSymbolName: "square.on.square", accessibilityDescription: nil)
        applyToAllItem.toolTip = Localization.tipApplyColorToAll
        colorsMenu.addItem(applyToAllItem)

        let resetColorItem = NSMenuItem(
            title: Localization.actionResetColorToDefault,
            action: #selector(resetColorToDefault),
            keyEquivalent: ""
        )
        resetColorItem.target = self
        resetColorItem.image = NSImage(systemSymbolName: "arrow.uturn.backward", accessibilityDescription: nil)
        resetColorItem.toolTip = Localization.tipResetColorToDefault
        colorsMenu.addItem(resetColorItem)

        return colorsMenu
    }

    // MARK: Style Menus

    private func createIconMenu() -> NSMenu {
        let iconMenu = NSMenu(title: Localization.menuNumber)
        iconMenu.delegate = self

        for style in IconStyle.allCases {
            let item = NSMenuItem()
            let stylePicker = StylePicker(style: style)
            stylePicker.frame = NSRect(origin: .zero, size: stylePicker.intrinsicContentSize)
            stylePicker.isChecked = style == appState.currentIconStyle
            stylePicker.customColors = appState.currentColors
            stylePicker.darkMode = appState.darkModeEnabled
            stylePicker.previewNumber = appState.currentSpaceLabel == "?" ? "1" : appState.currentSpaceLabel
            stylePicker.sizeScale = appState.store.sizeScale
            stylePicker.onSelected = { [weak self, weak stylePicker] in
                self?.selectIconStyle(style, stylePicker: stylePicker)
            }
            stylePicker.onHoverStart = { [weak self] hoveredStyle in
                self?.showPreviewIcon(style: hoveredStyle, clearSymbol: true)
            }
            stylePicker.onHoverEnd = { [weak self] in
                self?.restoreIcon()
            }
            item.view = stylePicker
            item.representedObject = style
            iconMenu.addItem(item)
        }

        iconMenu.addItem(.separator())

        let fontItem = NSMenuItem(
            title: Localization.actionFont,
            action: #selector(showFontPanel),
            keyEquivalent: ""
        )
        fontItem.target = self
        fontItem.image = NSImage(systemSymbolName: "textformat", accessibilityDescription: nil)
        fontItem.toolTip = Localization.tipFont
        iconMenu.addItem(fontItem)

        let resetFontItem = NSMenuItem(
            title: Localization.actionResetFontToDefault,
            action: #selector(resetFontToDefault),
            keyEquivalent: ""
        )
        resetFontItem.target = self
        resetFontItem.image = NSImage(systemSymbolName: "arrow.uturn.backward", accessibilityDescription: nil)
        resetFontItem.toolTip = Localization.tipResetFontToDefault
        iconMenu.addItem(resetFontItem)

        return iconMenu
    }

    private func createItemMenu(type: ItemPicker.ItemType) -> NSMenu {
        let title = type == .symbols ? Localization.menuSymbol : Localization.menuEmoji
        let menu = NSMenu(title: title)
        menu.delegate = self

        let pickerItem = NSMenuItem()
        let picker = ItemPicker(type: type)
        picker.frame = NSRect(origin: .zero, size: picker.intrinsicContentSize)
        picker.selectedItem = appState.currentSymbol
        picker.darkMode = appState.darkModeEnabled
        picker.onItemSelected = { [weak self] item in
            self?.setSymbol(item)
        }
        picker.onItemHoverStart = { [weak self] item in
            // For emojis, use the global emoji picker skin tone for preview
            let skinTone = item.containsEmoji ? Defaults[.emojiPickerSkinTone] : nil
            let foreground = self?.appState.currentColors?.foreground
            let background = self?.appState.currentColors?.background
            self?.showPreviewIcon(symbol: item, foreground: foreground, background: background, skinTone: skinTone)
        }
        picker.onItemHoverEnd = { [weak self] in
            self?.restoreIcon()
        }
        pickerItem.view = picker
        menu.addItem(pickerItem)

        return menu
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

    // MARK: - Toggle Actions

    @objc func toggleDimInactiveSpaces() {
        store.dimInactiveSpaces.toggle()
    }

    @objc func toggleHideEmptySpaces() {
        store.hideEmptySpaces.toggle()
    }

    @objc func toggleHideFullscreenApps() {
        store.hideFullscreenApps.toggle()
    }

    @objc func toggleLaunchAtLogin() {
        launchAtLogin.isEnabled.toggle()
    }

    @objc func toggleShowAllDisplays() {
        store.showAllDisplays.toggle()
        // Turn off showAllSpaces when enabling showAllDisplays (they are mutually exclusive in behavior)
        if store.showAllDisplays {
            store.showAllSpaces = false
        }
    }

    @objc func toggleShowAllSpaces() {
        store.showAllSpaces.toggle()
        // Turn off showAllDisplays when enabling showAllSpaces (they are mutually exclusive in behavior)
        if store.showAllSpaces {
            store.showAllDisplays = false
        }
    }

    @objc func toggleClickToSwitchSpaces() {
        if !store.clickToSwitchSpaces, !AXIsProcessTrusted() {
            showAccessibilityPermissionAlert()
            return
        }
        store.clickToSwitchSpaces.toggle()
    }

    @objc func toggleLocalSpaceNumbers() {
        store.localSpaceNumbers.toggle()
    }

    @objc func toggleUniqueIconsPerDisplay() {
        store.uniqueIconsPerDisplay.toggle()
    }

    @objc private func checkForUpdates() {
        NSApp.activate(ignoringOtherApps: true)
        updaterController.checkForUpdates(nil)
    }

    // MARK: - Apply Actions

    @objc func applyToAllSpaces() {
        guard appState.currentSpace > 0 else {
            return
        }

        let confirmed = alertFactory.makeAlert(
            message: Localization.confirmApplyToAll,
            detail: Localization.detailApplyToAll,
            confirmTitle: Localization.buttonOK,
            isDestructive: false
        )
        .runModal()

        guard confirmed else {
            return
        }

        let style = appState.currentIconStyle
        let colors = appState.currentColors
        let symbol = appState.currentSymbol
        let font = appState.currentFont
        let skinTone = SpacePreferences.skinTone(
            forSpace: appState.currentSpace,
            display: appState.currentDisplayID,
            store: store
        )
        let display = appState.currentDisplayID
        for space in appState.getAllSpaceIndices() {
            SpacePreferences.setIconStyle(style, forSpace: space, display: display, store: store)
            if let symbol {
                SpacePreferences.setSymbol(symbol, forSpace: space, display: display, store: store)
            } else {
                SpacePreferences.clearSymbol(forSpace: space, display: display, store: store)
            }
            if let colors {
                SpacePreferences.setColors(colors, forSpace: space, display: display, store: store)
            } else {
                SpacePreferences.clearColors(forSpace: space, display: display, store: store)
            }
            if let font {
                SpacePreferences.setFont(SpaceFont(font: font), forSpace: space, display: display, store: store)
            } else {
                SpacePreferences.clearFont(forSpace: space, display: display, store: store)
            }
            if let skinTone {
                SpacePreferences.setSkinTone(skinTone, forSpace: space, display: display, store: store)
            } else {
                SpacePreferences.clearSkinTone(forSpace: space, display: display, store: store)
            }
        }
        updateStatusBarIcon()
    }

    // MARK: - Reset Actions

    @objc func resetSpaceToDefault() {
        guard appState.currentSpace > 0 else {
            return
        }

        let confirmed = alertFactory.makeAlert(
            message: Localization.confirmResetSpace,
            detail: Localization.detailResetSpace,
            confirmTitle: Localization.buttonReset,
            isDestructive: true
        )
        .runModal()

        guard confirmed else {
            return
        }

        SpacePreferences.clearColors(forSpace: appState.currentSpace, display: appState.currentDisplayID, store: store)
        SpacePreferences.clearIconStyle(
            forSpace: appState.currentSpace,
            display: appState.currentDisplayID,
            store: store
        )
        SpacePreferences.clearFont(
            forSpace: appState.currentSpace,
            display: appState.currentDisplayID,
            store: store
        )
        SpacePreferences.clearSymbol(
            forSpace: appState.currentSpace,
            display: appState.currentDisplayID,
            store: store
        )
        SpacePreferences.clearSkinTone(
            forSpace: appState.currentSpace,
            display: appState.currentDisplayID,
            store: store
        )
        updateStatusBarIcon()
    }

    @objc func resetAllSpacesToDefault() {
        let confirmed = alertFactory.makeAlert(
            message: Localization.confirmResetAllSpaces,
            detail: Localization.detailResetAllSpaces,
            confirmTitle: Localization.buttonResetAll,
            isDestructive: true
        )
        .runModal()

        guard confirmed else {
            return
        }

        // Always clear both shared and per-display settings
        SpacePreferences.clearAll(store: store)
        store.sizeScale = Layout.defaultSizeScale
        store.soundName = ""
        store.separatorColor = nil
        updateStatusBarIcon()
    }

    @objc func resetColorToDefault() {
        let confirmed = alertFactory.makeAlert(
            message: Localization.confirmResetColor,
            detail: Localization.detailResetColor,
            confirmTitle: Localization.buttonReset,
            isDestructive: true
        )
        .runModal()

        guard confirmed else {
            return
        }

        SpacePreferences.clearColors(forSpace: appState.currentSpace, display: appState.currentDisplayID, store: store)
        SpacePreferences.clearSkinTone(
            forSpace: appState.currentSpace,
            display: appState.currentDisplayID,
            store: store
        )
        store.separatorColor = nil
        updateStatusBarIcon()
    }

    @objc func resetStyleToDefault() {
        guard appState.currentSpace > 0 else {
            return
        }

        let confirmed = alertFactory.makeAlert(
            message: Localization.confirmResetStyle,
            detail: Localization.detailResetStyle,
            confirmTitle: Localization.buttonReset,
            isDestructive: true
        )
        .runModal()

        guard confirmed else {
            return
        }

        SpacePreferences.clearIconStyle(
            forSpace: appState.currentSpace,
            display: appState.currentDisplayID,
            store: store
        )
        SpacePreferences.clearSymbol(
            forSpace: appState.currentSpace,
            display: appState.currentDisplayID,
            store: store
        )
        updateStatusBarIcon()
    }

    @objc func invertColors() {
        guard appState.currentSpace > 0 else {
            return
        }
        let defaults = IconColors.filledColors(darkMode: appState.darkModeEnabled)
        let foreground = appState.currentColors?.foregroundColor ?? defaults.foreground
        let background = appState.currentColors?.backgroundColor ?? defaults.background
        SpacePreferences.setColors(
            SpaceColors(foreground: background, background: foreground),
            forSpace: appState.currentSpace,
            display: appState.currentDisplayID,
            store: store
        )
        updateStatusBarIcon()
    }

    @objc func applyColorsToAllSpaces() {
        guard appState.currentSpace > 0 else {
            return
        }

        let confirmed = alertFactory.makeAlert(
            message: Localization.confirmApplyColorToAll,
            detail: Localization.detailApplyColorToAll,
            confirmTitle: Localization.buttonOK,
            isDestructive: false
        )
        .runModal()

        guard confirmed else {
            return
        }

        let colors = appState.currentColors
        let skinTone = SpacePreferences.skinTone(
            forSpace: appState.currentSpace,
            display: appState.currentDisplayID,
            store: store
        )
        let display = appState.currentDisplayID
        for space in appState.getAllSpaceIndices() {
            if let colors {
                SpacePreferences.setColors(colors, forSpace: space, display: display, store: store)
            } else {
                SpacePreferences.clearColors(forSpace: space, display: display, store: store)
            }
            if let skinTone {
                SpacePreferences.setSkinTone(skinTone, forSpace: space, display: display, store: store)
            } else {
                SpacePreferences.clearSkinTone(forSpace: space, display: display, store: store)
            }
        }
        updateStatusBarIcon()
    }

    @objc func applyStyleToAllSpaces() {
        guard appState.currentSpace > 0 else {
            return
        }

        let confirmed = alertFactory.makeAlert(
            message: Localization.confirmApplyStyleToAll,
            detail: Localization.detailApplyStyleToAll,
            confirmTitle: Localization.buttonOK,
            isDestructive: false
        )
        .runModal()

        guard confirmed else {
            return
        }

        let style = appState.currentIconStyle
        let symbol = appState.currentSymbol
        let display = appState.currentDisplayID
        for space in appState.getAllSpaceIndices() {
            SpacePreferences.setIconStyle(style, forSpace: space, display: display, store: store)
            if let symbol {
                SpacePreferences.setSymbol(symbol, forSpace: space, display: display, store: store)
            } else {
                SpacePreferences.clearSymbol(forSpace: space, display: display, store: store)
            }
        }
        updateStatusBarIcon()
    }

    // MARK: - Color Helpers

    func setForegroundColor(_ color: NSColor) {
        guard appState.currentSpace > 0 else {
            return
        }
        let defaults = IconColors.filledColors(darkMode: appState.darkModeEnabled)
        let background = appState.currentColors?.backgroundColor ?? defaults.background
        SpacePreferences.setColors(
            SpaceColors(foreground: color, background: background),
            forSpace: appState.currentSpace,
            display: appState.currentDisplayID,
            store: store
        )
        updateStatusBarIcon()
    }

    func setBackgroundColor(_ color: NSColor) {
        guard appState.currentSpace > 0 else {
            return
        }
        let defaults = IconColors.filledColors(darkMode: appState.darkModeEnabled)
        let foreground = appState.currentColors?.foregroundColor ?? defaults.foreground
        SpacePreferences.setColors(
            SpaceColors(foreground: foreground, background: color),
            forSpace: appState.currentSpace,
            display: appState.currentDisplayID,
            store: store
        )
        updateStatusBarIcon()
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

    // MARK: - Font Helpers

    @objc func showFontPanel() {
        NSApp.activate(ignoringOtherApps: true)

        let fontManager = NSFontManager.shared
        fontManager.target = self
        fontManager.action = #selector(changeFont(_:))

        let fontPanel = NSFontPanel.shared
        // Set the current font if one exists, otherwise use a sensible default
        if let currentFont = appState.currentFont {
            fontPanel.setPanelFont(currentFont, isMultiple: false)
        } else {
            let defaultFont = NSFont.boldSystemFont(ofSize: Layout.baseFontSize)
            fontPanel.setPanelFont(defaultFont, isMultiple: false)
        }

        // Center the font panel on screen
        if let screen = NSScreen.main {
            let screenFrame = screen.visibleFrame
            let panelFrame = fontPanel.frame
            let centerX = screenFrame.midX - panelFrame.width / 2
            let centerY = screenFrame.midY - panelFrame.height / 2
            fontPanel.setFrameOrigin(NSPoint(x: centerX, y: centerY))
        }

        fontPanel.makeKeyAndOrderFront(nil)
    }

    @objc func changeFont(_ sender: Any?) {
        guard appState.currentSpace > 0 else {
            return
        }

        guard let fontManager = sender as? NSFontManager else {
            return
        }

        // Get the converted font from the font manager
        let currentFont = appState.currentFont ?? NSFont.boldSystemFont(ofSize: Layout.baseFontSize)
        let newFont = fontManager.convert(currentFont)

        SpacePreferences.setFont(
            SpaceFont(font: newFont),
            forSpace: appState.currentSpace,
            display: appState.currentDisplayID,
            store: store
        )
        updateStatusBarIcon()
    }

    @objc func resetFontToDefault() {
        guard appState.currentSpace > 0 else {
            return
        }

        let confirmed = alertFactory.makeAlert(
            message: Localization.confirmResetFont,
            detail: Localization.detailResetFont,
            confirmTitle: Localization.buttonReset,
            isDestructive: true
        )
        .runModal()

        guard confirmed else {
            return
        }

        SpacePreferences.clearFont(
            forSpace: appState.currentSpace,
            display: appState.currentDisplayID,
            store: store
        )
        updateStatusBarIcon()
    }

    // MARK: - Alert Helpers

    private func showAccessibilityPermissionAlert() {
        let alert = NSAlert()
        alert.messageText = "Permission Required"
        // swiftformat:disable all
        alert.informativeText = """
        This feature requires Accessibility permission to simulate keyboard shortcuts.

        After clicking Continue, macOS will prompt you for permission. Click "Open System Settings", then find \(appName) in the list and enable it.
        """
        // swiftformat:enable all
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Continue")
        alert.addButton(withTitle: "Cancel")

        NSApp.activate(ignoringOtherApps: true)
        let response = alert.runModal()

        if response == .alertFirstButtonReturn {
            // Request permission - this triggers the system prompt
            let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
            _ = AXIsProcessTrustedWithOptions(options)
            // Enable the setting - it will check permission again when actually switching
            store.clickToSwitchSpaces = true
        }
    }

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
        let currentStyle = appState.currentIconStyle
        let customColors = appState.currentColors
        let previewNumber = appState.currentSpaceLabel == "?" ? "1" : appState.currentSpaceLabel
        let currentSymbol = appState.currentSymbol
        let symbolIsActive = currentSymbol != nil

        // Update Launch at Login checkmark
        if let launchAtLoginItem = menu.item(withTag: MenuTag.launchAtLogin.rawValue) {
            launchAtLoginItem.state = launchAtLogin.isEnabled ? .on : .off
        }

        if let localSpaceNumbersItem = menu.item(withTag: MenuTag.localSpaceNumbers.rawValue) {
            localSpaceNumbersItem.state = store.localSpaceNumbers ? .on : .off
        }

        // Update Unique Icons Per Display checkmark
        if let uniqueIconsItem = menu.item(withTag: MenuTag.uniqueIconsPerDisplay.rawValue) {
            uniqueIconsItem.state = store.uniqueIconsPerDisplay ? .on : .off
        }

        // Update Show All Spaces checkmark
        if let showAllSpacesItem = menu.item(withTag: MenuTag.showAllSpaces.rawValue) {
            showAllSpacesItem.state = store.showAllSpaces ? .on : .off
        }

        // Update Show All Displays checkmark
        if let showAllDisplaysItem = menu.item(withTag: MenuTag.showAllDisplays.rawValue) {
            showAllDisplaysItem.state = store.showAllDisplays ? .on : .off
        }

        // Dim/Hide options are visible when either showAllSpaces or showAllDisplays is enabled
        let showMultiSpaceOptions = store.showAllSpaces || store.showAllDisplays

        // Update Click to Switch Spaces checkmark and visibility (only shown when multi-space is enabled)
        // Deselect if permission has been revoked
        if store.clickToSwitchSpaces, !AXIsProcessTrusted() {
            store.clickToSwitchSpaces = false
        }
        if let clickToSwitchItem = menu.item(withTag: MenuTag.clickToSwitchSpaces.rawValue) {
            clickToSwitchItem.state = store.clickToSwitchSpaces ? .on : .off
            clickToSwitchItem.isHidden = !showMultiSpaceOptions
        }

        // Update Dim inactive Spaces checkmark and visibility
        if let dimInactiveItem = menu.item(withTag: MenuTag.dimInactiveSpaces.rawValue) {
            dimInactiveItem.state = store.dimInactiveSpaces ? .on : .off
            dimInactiveItem.isHidden = !showMultiSpaceOptions
        }

        // Update Hide empty Spaces checkmark and visibility
        if let hideEmptyItem = menu.item(withTag: MenuTag.hideEmptySpaces.rawValue) {
            hideEmptyItem.state = store.hideEmptySpaces ? .on : .off
            hideEmptyItem.isHidden = !showMultiSpaceOptions
        }

        // Update Hide full-screen applications checkmark and visibility
        if let hideFullscreenItem = menu.item(withTag: MenuTag.hideFullscreenApps.rawValue) {
            hideFullscreenItem.state = store.hideFullscreenApps ? .on : .off
            hideFullscreenItem.isHidden = !showMultiSpaceOptions
        }

        // Determine if current symbol is an emoji vs SF Symbol
        let currentSymbolIsEmoji = currentSymbol?.containsEmoji ?? false
        let currentSymbolIsSFSymbol = symbolIsActive && !currentSymbolIsEmoji

        for item in menu.items {
            // Update icon style views - only show checkmark when not in symbol mode
            if let view = item.view as? StylePicker {
                view.isChecked = !symbolIsActive && item.representedObject as? IconStyle == currentStyle
                view.customColors = customColors
                view.darkMode = appState.darkModeEnabled
                view.previewNumber = previewNumber
                view.needsDisplay = true
            }

            // Update symbol picker view
            if let view = item.view as? SymbolPicker {
                view.selectedSymbol = currentSymbol
                view.darkMode = appState.darkModeEnabled
                view.needsDisplay = true
            }

            // Show skin tone items only when emoji is active
            if item.tag == MenuTag.skinToneLabel.rawValue || item.tag == MenuTag.skinToneSwatch.rawValue {
                item.isHidden = !currentSymbolIsEmoji
            }

            // Update skin tone swatch to reflect current space's skin tone (with global fallback)
            if item.tag == MenuTag.skinToneSwatch.rawValue, let swatch = item.view as? SkinToneSwatch {
                let spaceTone = SpacePreferences.skinTone(
                    forSpace: appState.currentSpace,
                    display: appState.currentDisplayID,
                    store: store
                )
                swatch.currentTone = spaceTone ?? .default
            }

            // Show symbol label and color swatch only when SF Symbol is active (not emoji)
            if item.tag == MenuTag.symbolLabel.rawValue || item.tag == MenuTag.symbolColorSwatch.rawValue {
                item.isHidden = !currentSymbolIsSFSymbol
            }

            // Show separator divider, label, and swatch only when Show all Displays is enabled
            // AND there are multiple displays (separator only appears between displays)
            if item.tag == MenuTag.separatorColorDivider.rawValue || item.tag == MenuTag.separatorLabel.rawValue
                || item.tag == MenuTag.separatorSwatch.rawValue
            {
                let hasMultipleDisplays = appState.allDisplaysSpaceInfo.count > 1
                item.isHidden = !store.showAllDisplays || !hasMultipleDisplays
            }

            // Hide foreground/background labels and swatches when any symbol is active (SF Symbol or emoji)
            // Also hide background items when style is transparent (no background to color)
            let foregroundTags = [MenuTag.foregroundLabel.rawValue, MenuTag.foregroundSwatch.rawValue]
            let backgroundTags = [
                MenuTag.colorSeparator.rawValue,
                MenuTag.backgroundLabel.rawValue,
                MenuTag.backgroundSwatch.rawValue,
            ]
            if foregroundTags.contains(item.tag) {
                item.isHidden = symbolIsActive
            }
            if backgroundTags.contains(item.tag) {
                item.isHidden = symbolIsActive || currentStyle == .transparent
            }

            // Hide "Invert color" when any symbol is active (no fg/bg to swap)
            if item.tag == MenuTag.invertColors.rawValue {
                item.isHidden = symbolIsActive
            }
            // Update foreground label text: "Number" for transparent, "Number (Foreground)" otherwise
            if item.tag == MenuTag.foregroundLabel.rawValue {
                item.title = currentStyle == .transparent
                    ? Localization.labelNumber
                    : Localization.labelNumberForeground
            }

            // Update size row view (tag 310)
            if item.tag == MenuTag.sizeRow.rawValue, let view = item.view as? SizeSlider {
                view.currentSize = store.sizeScale
            }

            // Update sound menu checkmarks
            if item.representedObject is String {
                let soundName = item.representedObject as? String ?? ""
                item.state = soundName == store.soundName ? .on : .off
            }
        }

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
