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
protocol LaunchAtLoginProviding {
    var isEnabled: Bool { get set }
}

/// Default implementation using the actual LaunchAtLogin library
struct DefaultLaunchAtLoginProvider: LaunchAtLoginProviding {
    var isEnabled: Bool {
        get { LaunchAtLogin.isEnabled }
        set { LaunchAtLogin.isEnabled = newValue }
    }
}

// MARK: - Confirmation Alert Protocol

/// Protocol for abstracting confirmation alerts for testability
protocol ConfirmationAlertProviding {
    func runModal() -> Bool
}

/// Default implementation using the actual ConfirmationAlert
extension ConfirmationAlert: ConfirmationAlertProviding {}

/// Factory for creating confirmation alerts
protocol ConfirmationAlertFactory {
    func makeAlert(message: String, detail: String, confirmTitle: String, isDestructive: Bool)
        -> ConfirmationAlertProviding
}

/// Default factory that creates real ConfirmationAlerts
struct DefaultConfirmationAlertFactory: ConfirmationAlertFactory {
    func makeAlert(
        message: String,
        detail: String,
        confirmTitle: String,
        isDestructive: Bool
    ) -> ConfirmationAlertProviding {
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
    private var launchAtLogin: LaunchAtLoginProviding

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
        launchAtLogin: LaunchAtLoginProviding = DefaultLaunchAtLoginProvider()
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
        statusBarItem.menu = statusMenu
        statusBarItem.button?.toolTip = appName
        updateStatusBarIcon()
    }

    private func configureVersionHeader() {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        let versionItem = NSMenuItem(title: "\(appName) v\(version)", action: nil, keyEquivalent: "")
        versionItem.isEnabled = false
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
        let colorsMenuItem = NSMenuItem(title: Localization.colorTitle, action: nil, keyEquivalent: "")
        colorsMenuItem.image = NSImage(systemSymbolName: "paintpalette", accessibilityDescription: nil)
        colorsMenuItem.submenu = colorsMenu
        statusMenu.addItem(colorsMenuItem)
    }

    private func configureStyleMenuItem() {
        let styleMenu = NSMenu(title: Localization.styleTitle)
        styleMenu.delegate = self

        // Number submenu (icon shapes)
        let iconMenu = createIconMenu()
        let iconMenuItem = NSMenuItem(title: Localization.numberTitle, action: nil, keyEquivalent: "")
        iconMenuItem.image = NSImage(systemSymbolName: "textformat.123", accessibilityDescription: nil)
        iconMenuItem.submenu = iconMenu
        styleMenu.addItem(iconMenuItem)

        // Symbol submenu
        let symbolMenu = createSymbolMenu()
        let symbolMenuItem = NSMenuItem(title: Localization.symbolTitle, action: nil, keyEquivalent: "")
        symbolMenuItem.image = NSImage(systemSymbolName: "burst.fill", accessibilityDescription: nil)
        symbolMenuItem.submenu = symbolMenu
        styleMenu.addItem(symbolMenuItem)

        styleMenu.addItem(.separator())

        let applyStyleItem = NSMenuItem(
            title: Localization.applyStyleToAll,
            action: #selector(applyStyleToAllSpaces),
            keyEquivalent: ""
        )
        applyStyleItem.target = self
        applyStyleItem.image = NSImage(systemSymbolName: "square.on.square", accessibilityDescription: nil)
        applyStyleItem.toolTip = Localization.applyStyleToAllTip
        styleMenu.addItem(applyStyleItem)

        let resetStyleItem = NSMenuItem(
            title: Localization.resetStyleToDefault,
            action: #selector(resetStyleToDefault),
            keyEquivalent: ""
        )
        resetStyleItem.target = self
        resetStyleItem.image = NSImage(systemSymbolName: "arrow.uturn.backward", accessibilityDescription: nil)
        resetStyleItem.toolTip = Localization.resetStyleToDefaultTip
        styleMenu.addItem(resetStyleItem)

        let styleMenuItem = NSMenuItem(title: Localization.styleTitle, action: nil, keyEquivalent: "")
        styleMenuItem.image = NSImage(systemSymbolName: "photo.artframe", accessibilityDescription: nil)
        styleMenuItem.submenu = styleMenu
        statusMenu.addItem(styleMenuItem)
    }

    private func configureSizeMenuItem() {
        let sizeMenu = NSMenu(title: Localization.sizeTitle)
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

        let sizeMenuItem = NSMenuItem(title: Localization.sizeTitle, action: nil, keyEquivalent: "")
        sizeMenuItem.image = NSImage(
            systemSymbolName: "arrow.up.left.and.down.right.and.arrow.up.right.and.down.left",
            accessibilityDescription: nil
        )
        sizeMenuItem.submenu = sizeMenu
        statusMenu.addItem(sizeMenuItem)
        statusMenu.addItem(.separator())
    }

    private func configureCopyAndResetMenuItems() {
        let showAllSpacesItem = NSMenuItem(
            title: Localization.showAllSpaces,
            action: #selector(toggleShowAllSpaces),
            keyEquivalent: ""
        )
        showAllSpacesItem.target = self
        showAllSpacesItem.tag = MenuTag.showAllSpaces
        showAllSpacesItem.image = NSImage(
            systemSymbolName: "square.grid.3x1.below.line.grid.1x2",
            accessibilityDescription: nil
        )
        showAllSpacesItem.toolTip = Localization.showAllSpacesTip
        statusMenu.addItem(showAllSpacesItem)
        statusMenu.addItem(.separator())

        let applyToAllItem = NSMenuItem(
            title: Localization.applyToAll,
            action: #selector(applyAllToAllSpaces),
            keyEquivalent: ""
        )
        applyToAllItem.target = self
        applyToAllItem.image = NSImage(systemSymbolName: "square.on.square", accessibilityDescription: nil)
        applyToAllItem.toolTip = Localization.applyToAllTip
        statusMenu.addItem(applyToAllItem)

        let resetItem = NSMenuItem(
            title: Localization.resetSpaceToDefault,
            action: #selector(resetSpaceToDefault),
            keyEquivalent: ""
        )
        resetItem.target = self
        resetItem.image = NSImage(systemSymbolName: "arrow.uturn.backward", accessibilityDescription: nil)
        resetItem.toolTip = Localization.resetSpaceToDefaultTip
        statusMenu.addItem(resetItem)

        let resetAllItem = NSMenuItem(
            title: Localization.resetAllSpacesToDefault,
            action: #selector(resetAllSpacesToDefault),
            keyEquivalent: ""
        )
        resetAllItem.target = self
        resetAllItem.image = NSImage(systemSymbolName: "arrow.triangle.2.circlepath", accessibilityDescription: nil)
        resetAllItem.toolTip = Localization.resetAllSpacesToDefaultTip
        statusMenu.addItem(resetAllItem)
        statusMenu.addItem(.separator())
    }

    private func configureLaunchAtLoginMenuItem() {
        let launchAtLoginItem = NSMenuItem(
            title: Localization.launchAtLogin,
            action: #selector(toggleLaunchAtLogin),
            keyEquivalent: ""
        )
        launchAtLoginItem.target = self
        launchAtLoginItem.tag = MenuTag.launchAtLogin
        launchAtLoginItem.image = NSImage(systemSymbolName: "sunrise", accessibilityDescription: nil)
        launchAtLoginItem.toolTip = String(format: Localization.launchAtLoginTip, appName)
        statusMenu.addItem(launchAtLoginItem)
    }

    private func configureUpdateAndQuitMenuItems() {
        let updateItem = NSMenuItem(
            title: Localization.checkForUpdates,
            action: #selector(checkForUpdates),
            keyEquivalent: ""
        )
        updateItem.target = self
        updateItem.image = NSImage(systemSymbolName: "square.and.arrow.down", accessibilityDescription: nil)
        updateItem.toolTip = String(format: Localization.checkForUpdatesTip, appName)
        statusMenu.addItem(updateItem)
        statusMenu.addItem(.separator())

        let quitItem = NSMenuItem(
            title: Localization.quit,
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )
        quitItem.image = NSImage(systemSymbolName: "xmark.rectangle", accessibilityDescription: nil)
        quitItem.toolTip = String(format: Localization.quitTip, appName)
        statusMenu.addItem(quitItem)
    }

    // MARK: Color Menu

    private func createColorMenu() -> NSMenu {
        let colorsMenu = NSMenu(title: Localization.colorTitle)
        colorsMenu.delegate = self

        // Foreground label (hidden when symbol active)
        let foregroundLabel = NSMenuItem(title: Localization.foregroundLabel, action: nil, keyEquivalent: "")
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
        let backgroundLabel = NSMenuItem(title: Localization.backgroundLabel, action: nil, keyEquivalent: "")
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

        // Separator before actions
        colorsMenu.addItem(.separator())

        let invertColorsItem = NSMenuItem(
            title: Localization.invertColors,
            action: #selector(invertColors),
            keyEquivalent: ""
        )
        invertColorsItem.target = self
        invertColorsItem.image = NSImage(systemSymbolName: "arrow.left.arrow.right", accessibilityDescription: nil)
        invertColorsItem.toolTip = Localization.invertColorsTip
        colorsMenu.addItem(invertColorsItem)
        colorsMenu.addItem(.separator())

        let applyToAllItem = NSMenuItem(
            title: Localization.applyColorToAll,
            action: #selector(applyColorsToAllSpaces),
            keyEquivalent: ""
        )
        applyToAllItem.target = self
        applyToAllItem.image = NSImage(systemSymbolName: "square.on.square", accessibilityDescription: nil)
        applyToAllItem.toolTip = Localization.applyColorToAllTip
        colorsMenu.addItem(applyToAllItem)

        let resetColorItem = NSMenuItem(
            title: Localization.resetColorToDefault,
            action: #selector(resetColorToDefault),
            keyEquivalent: ""
        )
        resetColorItem.target = self
        resetColorItem.image = NSImage(systemSymbolName: "arrow.uturn.backward", accessibilityDescription: nil)
        resetColorItem.toolTip = Localization.resetColorToDefaultTip
        colorsMenu.addItem(resetColorItem)

        return colorsMenu
    }

    // MARK: Style Menus

    private func createIconMenu() -> NSMenu {
        let iconMenu = NSMenu(title: Localization.numberTitle)
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

        return iconMenu
    }

    private func createSymbolMenu() -> NSMenu {
        let symbolMenu = NSMenu(title: Localization.symbolTitle)
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

    // MARK: - Actions

    @objc func toggleLaunchAtLogin() {
        launchAtLogin.isEnabled.toggle()
        updateStatusBarIcon()
    }

    @objc func toggleShowAllSpaces() {
        store.showAllSpaces.toggle()
        updateStatusBarIcon()
    }

    @objc private func checkForUpdates() {
        NSApp.activate(ignoringOtherApps: true)
        updaterController.checkForUpdates(nil)
    }

    @objc func applyAllToAllSpaces() {
        guard appState.currentSpace > 0 else {
            return
        }

        let confirmed = alertFactory.makeAlert(
            message: Localization.applyToAllConfirm,
            detail: Localization.applyToAllDetail,
            confirmTitle: Localization.okButton,
            isDestructive: false
        )
        .runModal()

        guard confirmed else {
            return
        }

        let style = appState.currentIconStyle
        let colors = appState.currentColors
        let symbol = appState.currentSymbol
        for space in appState.getAllSpaceIndices() {
            SpacePreferences.setIconStyle(style, forSpace: space, store: store)
            if let symbol {
                SpacePreferences.setSFSymbol(symbol, forSpace: space, store: store)
            } else {
                SpacePreferences.clearSFSymbol(forSpace: space, store: store)
            }
            if let colors {
                SpacePreferences.setColors(colors, forSpace: space, store: store)
            } else {
                SpacePreferences.clearColors(forSpace: space, store: store)
            }
        }
        updateStatusBarIcon()
    }

    @objc func resetSpaceToDefault() {
        guard appState.currentSpace > 0 else {
            return
        }

        let confirmed = alertFactory.makeAlert(
            message: Localization.resetSpaceConfirm,
            detail: Localization.resetSpaceDetail,
            confirmTitle: Localization.resetButton,
            isDestructive: true
        )
        .runModal()

        guard confirmed else {
            return
        }

        SpacePreferences.clearColors(forSpace: appState.currentSpace, store: store)
        SpacePreferences.clearIconStyle(forSpace: appState.currentSpace, store: store)
        SpacePreferences.clearSFSymbol(forSpace: appState.currentSpace, store: store)
        updateStatusBarIcon()
    }

    @objc func resetAllSpacesToDefault() {
        let confirmed = alertFactory.makeAlert(
            message: Localization.resetAllSpacesConfirm,
            detail: Localization.resetAllSpacesDetail,
            confirmTitle: Localization.resetAllButton,
            isDestructive: true
        )
        .runModal()

        guard confirmed else {
            return
        }

        SpacePreferences.clearAll(store: store)
        store.sizeScale = Layout.defaultSizeScale
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
            store: store
        )
        updateStatusBarIcon()
    }

    @objc func applyColorsToAllSpaces() {
        guard appState.currentSpace > 0 else {
            return
        }

        let confirmed = alertFactory.makeAlert(
            message: Localization.applyColorToAllConfirm,
            detail: Localization.applyColorToAllDetail,
            confirmTitle: Localization.okButton,
            isDestructive: false
        )
        .runModal()

        guard confirmed else {
            return
        }

        let colors = appState.currentColors
        for space in appState.getAllSpaceIndices() {
            if let colors {
                SpacePreferences.setColors(colors, forSpace: space, store: store)
            } else {
                SpacePreferences.clearColors(forSpace: space, store: store)
            }
        }
        updateStatusBarIcon()
    }

    @objc func resetColorToDefault() {
        let confirmed = alertFactory.makeAlert(
            message: Localization.resetColorConfirm,
            detail: Localization.resetColorDetail,
            confirmTitle: Localization.resetButton,
            isDestructive: true
        )
        .runModal()

        guard confirmed else {
            return
        }

        SpacePreferences.clearColors(forSpace: appState.currentSpace, store: store)
        updateStatusBarIcon()
    }

    @objc func applyStyleToAllSpaces() {
        guard appState.currentSpace > 0 else {
            return
        }

        let confirmed = alertFactory.makeAlert(
            message: Localization.applyStyleToAllConfirm,
            detail: Localization.applyStyleToAllDetail,
            confirmTitle: Localization.okButton,
            isDestructive: false
        )
        .runModal()

        guard confirmed else {
            return
        }

        let style = appState.currentIconStyle
        let symbol = appState.currentSymbol
        for space in appState.getAllSpaceIndices() {
            SpacePreferences.setIconStyle(style, forSpace: space, store: store)
            if let symbol {
                SpacePreferences.setSFSymbol(symbol, forSpace: space, store: store)
            } else {
                SpacePreferences.clearSFSymbol(forSpace: space, store: store)
            }
        }
        updateStatusBarIcon()
    }

    @objc func resetStyleToDefault() {
        guard appState.currentSpace > 0 else {
            return
        }

        let confirmed = alertFactory.makeAlert(
            message: Localization.resetStyleConfirm,
            detail: Localization.resetStyleDetail,
            confirmTitle: Localization.resetButton,
            isDestructive: true
        )
        .runModal()

        guard confirmed else {
            return
        }

        SpacePreferences.clearIconStyle(forSpace: appState.currentSpace, store: store)
        SpacePreferences.clearSFSymbol(forSpace: appState.currentSpace, store: store)
        updateStatusBarIcon()
    }

    // MARK: - Private Helpers

    private func setForegroundColor(_ color: NSColor) {
        guard appState.currentSpace > 0 else {
            return
        }
        let background = appState.currentColors?.backgroundColor ?? .black
        SpacePreferences.setColors(
            SpaceColors(foreground: color, background: background),
            forSpace: appState.currentSpace
        )
        updateStatusBarIcon()
    }

    private func setBackgroundColor(_ color: NSColor) {
        guard appState.currentSpace > 0 else {
            return
        }
        let foreground = appState.currentColors?.foregroundColor ?? .white
        SpacePreferences.setColors(
            SpaceColors(foreground: foreground, background: color),
            forSpace: appState.currentSpace
        )
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
        let foreground = isPickingForeground ? sender.color : (existingColors?.foregroundColor ?? .white)
        let background = isPickingForeground ? (existingColors?.backgroundColor ?? .black) : sender.color

        SpacePreferences.setColors(
            SpaceColors(foreground: foreground, background: background),
            forSpace: appState.currentSpace
        )
        updateStatusBarIcon()
    }

    private func selectIconStyle(_ style: IconStyle, stylePicker: StylePicker?) {
        guard appState.currentSpace > 0 else {
            return
        }

        // Clear SF Symbol to switch to number mode
        SpacePreferences.clearSFSymbol(forSpace: appState.currentSpace, store: store)
        SpacePreferences.setIconStyle(style, forSpace: appState.currentSpace, store: store)

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
        SpacePreferences.setSFSymbol(symbol, forSpace: appState.currentSpace, store: store)
        updateStatusBarIcon()
    }

    func updateStatusBarIcon() {
        statusBarIconUpdateCount += 1
        statusBarItem.button?.image = appState.statusBarIcon
        statusBarIconUpdateNotifier?.yield()
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

        // Update Launch at Login checkmark (tag 1)
        if let launchAtLoginItem = menu.item(withTag: MenuTag.launchAtLogin) {
            launchAtLoginItem.state = launchAtLogin.isEnabled ? .on : .off
        }

        // Update Show All Spaces checkmark (tag 101)
        if let showAllSpacesItem = menu.item(withTag: MenuTag.showAllSpaces) {
            showAllSpacesItem.state = store.showAllSpaces ? .on : .off
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

            // Hide foreground/background labels and swatches when symbol is active
            let colorTags = [
                MenuTag.foregroundLabel, MenuTag.foregroundSwatch,
                MenuTag.colorSeparator, MenuTag.backgroundLabel, MenuTag.backgroundSwatch,
            ]
            if colorTags.contains(item.tag) {
                item.isHidden = symbolIsActive
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
