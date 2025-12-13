import AppKit
import Defaults
import LaunchAtLogin
import Observation
@preconcurrency import Sparkle
import SwiftUI

@main
struct AppMain: App {
    // swiftformat:disable:next unusedPrivateDeclarations
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings {
            EmptyView()
        }
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

// MARK: - Space Switching

enum SpaceSwitcher {
    private static let maxSupportedSpace = 16
    private static let firstHotKey: UInt16 = 118
    private static var hasPromptedForAccessibility = false
    private static var binYabai: URL?
    private static let yabaiExecutableName = "yabai"

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

    private let statusBarItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let appState: AppState
    private let alertFactory: ConfirmationAlertFactory
    private var launchAtLogin: LaunchAtLoginProvider

    private var updaterController: SPUStandardUpdaterController!
    private(set) var statusMenu: NSMenu!
    private(set) var observationTask: Task<Void, Never>?
    private var isPickingForeground = true
    private(set) var statusBarIconUpdateCount = 0

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
        PFMoveToApplicationsFolderIfNecessary()
        NSApp.setActivationPolicy(.accessory)
        updaterController = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: self
        )
        configureMenuBarIcon()
        startObservingAppState()

        // Disable click-to-switch if accessibility permission was revoked
        if store.clickToSwitchSpaces, !AXIsProcessTrusted() {
            store.clickToSwitchSpaces = false
        }
    }

    // MARK: - Observation

    /// Test hook to start the observation task. In production, this is called from applicationDidFinishLaunching.
    func startObservingAppState() {
        observationTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else {
                    return
                }
                // Access properties to register them for observation tracking
                let icon = withObservationTracking {
                    self.appState.statusBarIcon
                } onChange: {
                    Task { @MainActor [weak self] in
                        self?.updateStatusBarIcon()
                    }
                }
                statusBarItem.button?.image = icon
                try? await Task.sleep(for: .milliseconds(100))
            }
        }
    }

    /// Cancels the observation task. Call this in test teardown to prevent leaks.
    func stopObservingAppState() {
        observationTask?.cancel()
        observationTask = nil
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
        configureSizeMenuItem()
        configureCopyAndResetMenuItems()
        configureLaunchAtLoginMenuItem()
        configureUpdateAndQuitMenuItems()
        statusMenu.delegate = self
        statusBarItem.button?.toolTip = appName
        statusBarItem.button?.target = self
        statusBarItem.button?.action = #selector(statusBarButtonClicked(_:))
        statusBarItem.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
        updateStatusBarIcon()
    }

    @objc private func statusBarButtonClicked(_ button: NSStatusBarButton) {
        guard let event = NSApp.currentEvent else {
            return
        }

        if event.type == .rightMouseUp {
            statusBarItem.popUpMenu(statusMenu)
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

        let slots = appState.visibleIconSlots()
        guard !slots.isEmpty else {
            return
        }

        let location = button.convert(event.locationInWindow, from: nil)
        let clickX = Double(location.x)

        for slot in slots {
            let endX = slot.startX + slot.width
            guard clickX >= slot.startX, clickX <= endX else {
                continue
            }

            // Ignore non-switchable slots (e.g., fullscreen apps)
            guard let targetSpace = slot.targetSpace else {
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
            return
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
        let symbolMenu = createSymbolMenu()
        let symbolMenuItem = NSMenuItem(title: Localization.menuSymbol, action: nil, keyEquivalent: "")
        symbolMenuItem.image = NSImage(systemSymbolName: "burst.fill", accessibilityDescription: nil)
        symbolMenuItem.submenu = symbolMenu
        styleMenu.addItem(symbolMenuItem)

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
        sizeItem.tag = MenuTag.sizeRow
        let sizeSlider = SizeSlider(
            initialSize: store.sizeScale,
            range: Layout.sizeScaleRange
        )
        sizeSlider.frame = NSRect(origin: .zero, size: sizeSlider.intrinsicContentSize)
        sizeSlider.onSizeChanged = { [weak self] scale in
            self?.store.sizeScale = scale
            self?.updateStatusBarIcon()
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

    private func configureCopyAndResetMenuItems() {
        let uniqueIconsPerDisplayItem = NSMenuItem(
            title: Localization.toggleUniqueIconsPerDisplay,
            action: #selector(toggleUniqueIconsPerDisplay),
            keyEquivalent: ""
        )
        uniqueIconsPerDisplayItem.target = self
        uniqueIconsPerDisplayItem.tag = MenuTag.uniqueIconsPerDisplay
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
        dimInactiveSpacesItem.tag = MenuTag.dimInactiveSpaces
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
        showAllDisplaysItem.tag = MenuTag.showAllDisplays
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
        showAllSpacesItem.tag = MenuTag.showAllSpaces
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
        clickToSwitchItem.tag = MenuTag.clickToSwitchSpaces
        clickToSwitchItem.image = NSImage(
            systemSymbolName: "cursorarrow.click",
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
        hideEmptySpacesItem.tag = MenuTag.hideEmptySpaces
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
        hideFullscreenAppsItem.tag = MenuTag.hideFullscreenApps
        hideFullscreenAppsItem.image = NSImage(
            systemSymbolName: "eye.slash.fill",
            accessibilityDescription: nil
        )
        hideFullscreenAppsItem.toolTip = Localization.tipHideFullscreenApps
        statusMenu.addItem(hideFullscreenAppsItem)
        statusMenu.addItem(.separator())

        let applyToAllItem = NSMenuItem(
            title: Localization.actionApplyToAll,
            action: #selector(applyAllToAllSpaces),
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
        launchAtLoginItem.tag = MenuTag.launchAtLogin
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
    }

    // MARK: Color Menu

    private func createColorMenu() -> NSMenu {
        let colorsMenu = NSMenu(title: Localization.menuColor)
        colorsMenu.delegate = self

        // Symbol label (shown only when symbol active)
        let symbolLabelItem = NSMenuItem(title: Localization.labelSymbol, action: nil, keyEquivalent: "")
        symbolLabelItem.isEnabled = false
        symbolLabelItem.tag = MenuTag.symbolLabel
        symbolLabelItem.isHidden = true
        colorsMenu.addItem(symbolLabelItem)

        // Symbol color swatch (shown only when symbol active)
        let symbolSwatchItem = NSMenuItem()
        symbolSwatchItem.tag = MenuTag.symbolColorSwatch
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
        symbolSwatchItem.view = symbolSwatch
        colorsMenu.addItem(symbolSwatchItem)

        // Foreground label (hidden when symbol active)
        let foregroundLabel = NSMenuItem(title: Localization.labelNumberForeground, action: nil, keyEquivalent: "")
        foregroundLabel.isEnabled = false
        foregroundLabel.tag = MenuTag.foregroundLabel
        colorsMenu.addItem(foregroundLabel)

        // Foreground color swatches (hidden when symbol active)
        let foregroundSwatchItem = NSMenuItem()
        foregroundSwatchItem.tag = MenuTag.foregroundSwatch
        let foregroundSwatch = ColorSwatch()
        foregroundSwatch.frame = NSRect(origin: .zero, size: foregroundSwatch.intrinsicContentSize)
        foregroundSwatch.onColorSelected = { [weak self] color in
            self?.setForegroundColor(color)
        }
        foregroundSwatch.onCustomColorRequested = { [weak self] in
            self?.isPickingForeground = true
            self?.showColorPanel()
        }
        foregroundSwatchItem.view = foregroundSwatch
        colorsMenu.addItem(foregroundSwatchItem)

        // Separator (hidden when symbol active)
        let separator = NSMenuItem.separator()
        separator.tag = MenuTag.colorSeparator
        colorsMenu.addItem(separator)

        // Background label (hidden when symbol active)
        let backgroundLabel = NSMenuItem(title: Localization.labelNumberBackground, action: nil, keyEquivalent: "")
        backgroundLabel.isEnabled = false
        backgroundLabel.tag = MenuTag.backgroundLabel
        colorsMenu.addItem(backgroundLabel)

        // Background color swatches (hidden when symbol active)
        let backgroundSwatchItem = NSMenuItem()
        backgroundSwatchItem.tag = MenuTag.backgroundSwatch
        let backgroundSwatch = ColorSwatch()
        backgroundSwatch.frame = NSRect(origin: .zero, size: backgroundSwatch.intrinsicContentSize)
        backgroundSwatch.onColorSelected = { [weak self] color in
            self?.setBackgroundColor(color)
        }
        backgroundSwatch.onCustomColorRequested = { [weak self] in
            self?.isPickingForeground = false
            self?.showColorPanel()
        }
        backgroundSwatchItem.view = backgroundSwatch
        colorsMenu.addItem(backgroundSwatchItem)

        // Separator color section (shown only when Show all Displays is enabled)
        let separatorColorDivider = NSMenuItem.separator()
        separatorColorDivider.tag = MenuTag.separatorColorDivider
        separatorColorDivider.isHidden = true
        colorsMenu.addItem(separatorColorDivider)

        let separatorLabelItem = NSMenuItem(title: Localization.labelSeparator, action: nil, keyEquivalent: "")
        separatorLabelItem.isEnabled = false
        separatorLabelItem.tag = MenuTag.separatorLabel
        separatorLabelItem.isHidden = true
        colorsMenu.addItem(separatorLabelItem)

        let separatorSwatchItem = NSMenuItem()
        separatorSwatchItem.tag = MenuTag.separatorSwatch
        separatorSwatchItem.isHidden = true
        let separatorSwatch = ColorSwatch()
        separatorSwatch.frame = NSRect(origin: .zero, size: separatorSwatch.intrinsicContentSize)
        separatorSwatch.onColorSelected = { [weak self] color in
            self?.setSeparatorColor(color)
        }
        separatorSwatch.onCustomColorRequested = { [weak self] in
            self?.showSeparatorColorPanel()
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
            stylePicker.onSelected = { [weak self, weak stylePicker] in
                self?.selectIconStyle(style, stylePicker: stylePicker)
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

    private func createSymbolMenu() -> NSMenu {
        let symbolMenu = NSMenu(title: Localization.menuSymbol)
        symbolMenu.delegate = self

        let symbolPickerItem = NSMenuItem()
        let symbolPicker = SymbolPicker()
        symbolPicker.frame = NSRect(origin: .zero, size: symbolPicker.intrinsicContentSize)
        symbolPicker.selectedSymbol = appState.currentSymbol
        symbolPicker.darkMode = appState.darkModeEnabled
        symbolPicker.onSymbolSelected = { [weak self] symbol in
            self?.setSymbol(symbol)
        }
        symbolPickerItem.view = symbolPicker
        symbolMenu.addItem(symbolPickerItem)

        return symbolMenu
    }

    // MARK: - Status Bar

    func updateStatusBarIcon() {
        statusBarIconUpdateCount += 1
        let icon = appState.statusBarIcon
        statusBarItem.length = icon.size.width
        statusBarItem.button?.image = icon
        statusBarIconUpdateNotifier?.yield()
    }

    // MARK: - Toggle Actions

    @objc func toggleDimInactiveSpaces() {
        store.dimInactiveSpaces.toggle()
        updateStatusBarIcon()
    }

    @objc func toggleHideEmptySpaces() {
        store.hideEmptySpaces.toggle()
        updateStatusBarIcon()
    }

    @objc func toggleHideFullscreenApps() {
        store.hideFullscreenApps.toggle()
        updateStatusBarIcon()
    }

    @objc func toggleLaunchAtLogin() {
        launchAtLogin.isEnabled.toggle()
        updateStatusBarIcon()
    }

    @objc func toggleShowAllDisplays() {
        store.showAllDisplays.toggle()
        // Turn off showAllSpaces when enabling showAllDisplays (they are mutually exclusive in behavior)
        if store.showAllDisplays {
            store.showAllSpaces = false
        }
        updateStatusBarIcon()
    }

    @objc func toggleShowAllSpaces() {
        store.showAllSpaces.toggle()
        // Turn off showAllDisplays when enabling showAllSpaces (they are mutually exclusive in behavior)
        if store.showAllSpaces {
            store.showAllDisplays = false
        }
        updateStatusBarIcon()
    }

    @objc func toggleClickToSwitchSpaces() {
        // If enabling and no accessibility permission, show alert first
        if !store.clickToSwitchSpaces, !AXIsProcessTrusted() {
            showAccessibilityPermissionAlert()
            return
        }
        store.clickToSwitchSpaces.toggle()
    }

    @objc func toggleUniqueIconsPerDisplay() {
        store.uniqueIconsPerDisplay.toggle()
        updateStatusBarIcon()
    }

    @objc private func checkForUpdates() {
        NSApp.activate(ignoringOtherApps: true)
        updaterController.checkForUpdates(nil)
    }

    // MARK: - Apply Actions

    @objc func applyAllToAllSpaces() {
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
        let display = appState.currentDisplayID
        for space in appState.getAllSpaceIndices() {
            SpacePreferences.setIconStyle(style, forSpace: space, display: display, store: store)
            if let symbol {
                SpacePreferences.setSFSymbol(symbol, forSpace: space, display: display, store: store)
            } else {
                SpacePreferences.clearSFSymbol(forSpace: space, display: display, store: store)
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
        SpacePreferences.clearSFSymbol(
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
        SpacePreferences.clearSFSymbol(
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
        let display = appState.currentDisplayID
        for space in appState.getAllSpaceIndices() {
            if let colors {
                SpacePreferences.setColors(colors, forSpace: space, display: display, store: store)
            } else {
                SpacePreferences.clearColors(forSpace: space, display: display, store: store)
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
                SpacePreferences.setSFSymbol(symbol, forSpace: space, display: display, store: store)
            } else {
                SpacePreferences.clearSFSymbol(forSpace: space, display: display, store: store)
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
        SpacePreferences.clearSFSymbol(
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
        SpacePreferences.setSFSymbol(
            symbol,
            forSpace: appState.currentSpace,
            display: appState.currentDisplayID,
            store: store
        )
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
        if let launchAtLoginItem = menu.item(withTag: MenuTag.launchAtLogin) {
            launchAtLoginItem.state = launchAtLogin.isEnabled ? .on : .off
        }

        // Update Unique Icons Per Display checkmark
        if let uniqueIconsItem = menu.item(withTag: MenuTag.uniqueIconsPerDisplay) {
            uniqueIconsItem.state = store.uniqueIconsPerDisplay ? .on : .off
        }

        // Update Show All Spaces checkmark
        if let showAllSpacesItem = menu.item(withTag: MenuTag.showAllSpaces) {
            showAllSpacesItem.state = store.showAllSpaces ? .on : .off
        }

        // Update Show All Displays checkmark
        if let showAllDisplaysItem = menu.item(withTag: MenuTag.showAllDisplays) {
            showAllDisplaysItem.state = store.showAllDisplays ? .on : .off
        }

        // Dim/Hide options are visible when either showAllSpaces or showAllDisplays is enabled
        let showMultiSpaceOptions = store.showAllSpaces || store.showAllDisplays

        // Update Click to Switch Spaces checkmark and visibility (only shown when multi-space is enabled)
        if let clickToSwitchItem = menu.item(withTag: MenuTag.clickToSwitchSpaces) {
            clickToSwitchItem.state = store.clickToSwitchSpaces ? .on : .off
            clickToSwitchItem.isHidden = !showMultiSpaceOptions
        }

        // Update Dim inactive Spaces checkmark and visibility
        if let dimInactiveItem = menu.item(withTag: MenuTag.dimInactiveSpaces) {
            dimInactiveItem.state = store.dimInactiveSpaces ? .on : .off
            dimInactiveItem.isHidden = !showMultiSpaceOptions
        }

        // Update Hide empty Spaces checkmark and visibility
        if let hideEmptyItem = menu.item(withTag: MenuTag.hideEmptySpaces) {
            hideEmptyItem.state = store.hideEmptySpaces ? .on : .off
            hideEmptyItem.isHidden = !showMultiSpaceOptions
        }

        // Update Hide full-screen applications checkmark and visibility
        if let hideFullscreenItem = menu.item(withTag: MenuTag.hideFullscreenApps) {
            hideFullscreenItem.state = store.hideFullscreenApps ? .on : .off
            hideFullscreenItem.isHidden = !showMultiSpaceOptions
        }

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

            // Show symbol label and color swatch only when symbol is active
            if item.tag == MenuTag.symbolLabel || item.tag == MenuTag.symbolColorSwatch {
                item.isHidden = !symbolIsActive
            }

            // Show separator divider, label, and swatch only when Show all Displays is enabled
            // AND there are multiple displays (separator only appears between displays)
            if item.tag == MenuTag.separatorColorDivider || item.tag == MenuTag.separatorLabel
                || item.tag == MenuTag.separatorSwatch
            {
                let hasMultipleDisplays = appState.allDisplaysSpaceInfo.count > 1
                item.isHidden = !store.showAllDisplays || !hasMultipleDisplays
            }

            // Hide foreground/background labels and swatches when symbol is active
            // Also hide background items when style is transparent (no background to color)
            let foregroundTags = [MenuTag.foregroundLabel, MenuTag.foregroundSwatch]
            let backgroundTags = [MenuTag.colorSeparator, MenuTag.backgroundLabel, MenuTag.backgroundSwatch]
            if foregroundTags.contains(item.tag) {
                item.isHidden = symbolIsActive
            }
            if backgroundTags.contains(item.tag) {
                item.isHidden = symbolIsActive || currentStyle == .transparent
            }
            // Update foreground label text: "Number" for transparent, "Number (Foreground)" otherwise
            if item.tag == MenuTag.foregroundLabel {
                item.title = currentStyle == .transparent
                    ? Localization.labelNumber
                    : Localization.labelNumberForeground
            }

            // Update size row view (tag 310)
            if item.tag == MenuTag.sizeRow, let view = item.view as? SizeSlider {
                view.currentSize = store.sizeScale
            }
        }

        // Update status bar icon when menu opens
        updateStatusBarIcon()
    }
}
