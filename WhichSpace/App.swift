import LaunchAtLogin
import Sparkle
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

// MARK: - App Delegate

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let statusBarItem = NSStatusBar.system.statusItem(withLength: Layout.statusItemWidth)
    private let appState = AppState.shared
    private let updaterController = SPUStandardUpdaterController(
        startingUpdater: true,
        updaterDelegate: nil,
        userDriverDelegate: nil
    )

    private var statusMenu: NSMenu!
    private var isPickingForeground = true
    private var appName: String {
        Bundle.main.infoDictionary?["CFBundleName"] as? String ?? "WhichSpace"
    }

    func applicationDidFinishLaunching(_: Notification) {
        PFMoveToApplicationsFolderIfNecessary()
        NSApp.setActivationPolicy(.accessory)
        configureMenuBarIcon()
    }

    private func configureMenuBarIcon() {
        statusMenu = NSMenu()
        configureVersionHeader()
        configureColorMenuItem()
        configureStyleMenuItem()
        configureApplyAndResetMenuItems()
        configureLaunchAtLoginMenuItem()
        configureUpdateAndQuitMenuItems()
        statusMenu.delegate = self
        statusBarItem.menu = statusMenu
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
        symbolMenuItem.image = NSImage(systemSymbolName: "star", accessibilityDescription: nil)
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
        statusMenu.addItem(.separator())
    }

    private func configureApplyAndResetMenuItems() {
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
        statusMenu.addItem(.separator())
    }

    private func configureLaunchAtLoginMenuItem() {
        let launchAtLoginItem = NSMenuItem(
            title: Localization.launchAtLogin,
            action: #selector(toggleLaunchAtLogin),
            keyEquivalent: ""
        )
        launchAtLoginItem.target = self
        launchAtLoginItem.tag = 100
        launchAtLoginItem.image = NSImage(systemSymbolName: "sunrise", accessibilityDescription: nil)
        launchAtLoginItem.toolTip = "Automatically start \(appName) when you log in"
        statusMenu.addItem(launchAtLoginItem)
    }

    private func configureUpdateAndQuitMenuItems() {
        let updateItem = NSMenuItem(
            title: "Check for Updates...",
            action: #selector(checkForUpdates),
            keyEquivalent: ""
        )
        updateItem.target = self
        updateItem.image = NSImage(systemSymbolName: "arrow.triangle.2.circlepath", accessibilityDescription: nil)
        updateItem.toolTip = "Check for new versions of \(appName)"
        statusMenu.addItem(updateItem)

        let quitItem = NSMenuItem(
            title: "Quit",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )
        quitItem.image = NSImage(systemSymbolName: "xmark.circle", accessibilityDescription: nil)
        quitItem.toolTip = "Quit \(appName)"
        statusMenu.addItem(quitItem)
    }

    // MARK: - Color Menu

    private func createColorMenu() -> NSMenu {
        let colorsMenu = NSMenu(title: Localization.colorTitle)
        colorsMenu.delegate = self

        // Grid color swatch for symbol mode (shown only when symbol active)
        let gridSwatchItem = NSMenuItem()
        gridSwatchItem.tag = 210
        gridSwatchItem.isHidden = true
        let gridSwatchView = ColorSwatchView()
        gridSwatchView.gridMode = true
        gridSwatchView.frame = NSRect(origin: .zero, size: gridSwatchView.intrinsicContentSize)
        gridSwatchView.onColorSelected = { [weak self] color in
            self?.setForegroundColor(color)
        }
        gridSwatchItem.view = gridSwatchView
        colorsMenu.addItem(gridSwatchItem)

        // Foreground label (hidden when symbol active)
        let foregroundLabel = NSMenuItem(title: Localization.foregroundLabel, action: nil, keyEquivalent: "")
        foregroundLabel.isEnabled = false
        foregroundLabel.tag = 200
        colorsMenu.addItem(foregroundLabel)

        // Foreground color swatches (hidden when symbol active)
        let foregroundSwatchItem = NSMenuItem()
        foregroundSwatchItem.tag = 201
        let foregroundSwatchView = ColorSwatchView()
        foregroundSwatchView.frame = NSRect(origin: .zero, size: foregroundSwatchView.intrinsicContentSize)
        foregroundSwatchView.onColorSelected = { [weak self] color in
            self?.setForegroundColor(color)
        }
        foregroundSwatchView.onCustomColorRequested = { [weak self] in
            self?.isPickingForeground = true
            self?.showColorPanel()
        }
        foregroundSwatchItem.view = foregroundSwatchView
        colorsMenu.addItem(foregroundSwatchItem)

        // Separator (hidden when symbol active)
        let separator = NSMenuItem.separator()
        separator.tag = 202
        colorsMenu.addItem(separator)

        // Background label (hidden when symbol active)
        let backgroundLabel = NSMenuItem(title: Localization.backgroundLabel, action: nil, keyEquivalent: "")
        backgroundLabel.isEnabled = false
        backgroundLabel.tag = 203
        colorsMenu.addItem(backgroundLabel)

        // Background color swatches (hidden when symbol active)
        let backgroundSwatchItem = NSMenuItem()
        backgroundSwatchItem.tag = 204
        let backgroundSwatchView = ColorSwatchView()
        backgroundSwatchView.frame = NSRect(origin: .zero, size: backgroundSwatchView.intrinsicContentSize)
        backgroundSwatchView.onColorSelected = { [weak self] color in
            self?.setBackgroundColor(color)
        }
        backgroundSwatchView.onCustomColorRequested = { [weak self] in
            self?.isPickingForeground = false
            self?.showColorPanel()
        }
        backgroundSwatchItem.view = backgroundSwatchView
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

    // MARK: - Style Menus

    private func createIconMenu() -> NSMenu {
        let iconMenu = NSMenu(title: Localization.numberTitle)
        iconMenu.delegate = self

        for style in IconStyle.allCases {
            let item = NSMenuItem()
            let rowView = IconStyleRowView(style: style)
            rowView.frame = NSRect(origin: .zero, size: rowView.intrinsicContentSize)
            rowView.isChecked = style == appState.currentIconStyle
            rowView.customColors = appState.currentColors
            rowView.darkMode = appState.darkModeEnabled
            rowView.previewNumber = appState.currentSpaceLabel == "?" ? "1" : appState.currentSpaceLabel
            rowView.onSelected = { [weak self, weak rowView] in
                self?.selectIconStyle(style, rowView: rowView)
            }
            item.view = rowView
            item.representedObject = style
            iconMenu.addItem(item)
        }

        return iconMenu
    }

    private func createSymbolMenu() -> NSMenu {
        let symbolMenu = NSMenu(title: Localization.symbolTitle)
        symbolMenu.delegate = self

        let symbolPickerItem = NSMenuItem()
        let symbolPickerView = SymbolPickerView()
        symbolPickerView.frame = NSRect(origin: .zero, size: symbolPickerView.intrinsicContentSize)
        symbolPickerView.selectedSymbol = appState.currentSymbol
        symbolPickerView.darkMode = appState.darkModeEnabled
        symbolPickerView.onSymbolSelected = { [weak self] symbol in
            self?.setSymbol(symbol)
        }
        symbolPickerItem.view = symbolPickerView
        symbolMenu.addItem(symbolPickerItem)

        return symbolMenu
    }

    // MARK: - Actions

    @objc private func toggleLaunchAtLogin() {
        LaunchAtLogin.isEnabled.toggle()
    }

    @objc private func checkForUpdates() {
        NSApp.activate(ignoringOtherApps: true)
        updaterController.checkForUpdates(nil)
    }

    @objc private func applyAllToAllSpaces() {
        guard appState.currentSpace > 0 else {
            return
        }
        let style = appState.currentIconStyle
        let colors = appState.currentColors
        let symbol = appState.currentSymbol
        for space in appState.getAllSpaceIndices() {
            SpacePreferences.setIconStyle(style, forSpace: space)
            SpacePreferences.setSFSymbol(symbol, forSpace: space)
            if let colors {
                SpacePreferences.setColors(colors, forSpace: space)
            }
        }
        updateStatusBarIcon()
    }

    @objc private func resetSpaceToDefault() {
        guard appState.currentSpace > 0 else {
            return
        }
        SpacePreferences.clearColors(forSpace: appState.currentSpace)
        SpacePreferences.clearIconStyle(forSpace: appState.currentSpace)
        SpacePreferences.clearSFSymbol(forSpace: appState.currentSpace)
        updateStatusBarIcon()
    }

    @objc private func invertColors() {
        guard appState.currentSpace > 0 else {
            return
        }
        let defaults = IconColors.filledColors(darkMode: appState.darkModeEnabled)
        let foreground = appState.currentColors?.foregroundColor ?? defaults.foreground
        let background = appState.currentColors?.backgroundColor ?? defaults.background
        SpacePreferences.setColors(
            SpaceColors(foreground: background, background: foreground),
            forSpace: appState.currentSpace
        )
        updateStatusBarIcon()
    }

    @objc private func applyColorsToAllSpaces() {
        guard appState.currentSpace > 0, let colors = appState.currentColors else {
            return
        }
        for space in appState.getAllSpaceIndices() {
            SpacePreferences.setColors(colors, forSpace: space)
        }
    }

    @objc private func resetColorToDefault() {
        SpacePreferences.clearColors(forSpace: appState.currentSpace)
        updateStatusBarIcon()
    }

    @objc private func applyStyleToAllSpaces() {
        guard appState.currentSpace > 0 else {
            return
        }
        let style = appState.currentIconStyle
        let symbol = appState.currentSymbol
        for space in appState.getAllSpaceIndices() {
            SpacePreferences.setIconStyle(style, forSpace: space)
            SpacePreferences.setSFSymbol(symbol, forSpace: space)
        }
    }

    @objc private func resetStyleToDefault() {
        guard appState.currentSpace > 0 else {
            return
        }
        SpacePreferences.clearIconStyle(forSpace: appState.currentSpace)
        SpacePreferences.clearSFSymbol(forSpace: appState.currentSpace)
        updateStatusBarIcon()
    }

    // MARK: - Color Helpers

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

    // MARK: - Style Helpers

    private func selectIconStyle(_ style: IconStyle, rowView: IconStyleRowView?) {
        guard appState.currentSpace > 0 else {
            return
        }

        // Clear SF Symbol to switch to number mode
        SpacePreferences.clearSFSymbol(forSpace: appState.currentSpace)
        SpacePreferences.setIconStyle(style, forSpace: appState.currentSpace)

        // Update checkmarks in all row views
        if let menu = rowView?.enclosingMenuItem?.menu {
            for item in menu.items {
                if let view = item.view as? IconStyleRowView {
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
        SpacePreferences.setSFSymbol(symbol, forSpace: appState.currentSpace)
        updateStatusBarIcon()
    }

    // MARK: - Icon Update

    private func updateStatusBarIcon() {
        statusBarItem.button?.image = appState.statusBarIcon
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

        // Update Launch at Login checkmark (tag 100)
        if let launchAtLoginItem = menu.item(withTag: 100) {
            launchAtLoginItem.state = LaunchAtLogin.isEnabled ? .on : .off
        }

        for item in menu.items {
            // Update icon style views - only show checkmark when not in symbol mode
            if let view = item.view as? IconStyleRowView {
                view.isChecked = !symbolIsActive && item.representedObject as? IconStyle == currentStyle
                view.customColors = customColors
                view.darkMode = appState.darkModeEnabled
                view.previewNumber = previewNumber
                view.needsDisplay = true
            }

            // Update symbol picker view
            if let view = item.view as? SymbolPickerView {
                view.selectedSymbol = currentSymbol
                view.darkMode = appState.darkModeEnabled
                view.needsDisplay = true
            }

            // Show grid swatch when symbol is active (tag 210)
            if item.tag == 210 {
                item.isHidden = !symbolIsActive
            }

            // Hide foreground/background labels and swatches when symbol is active
            // Tags 200-204: foreground label, foreground swatch, separator, background label, background swatch
            if item.tag >= 200, item.tag <= 204 {
                item.isHidden = symbolIsActive
            }
        }

        // Update status bar icon when menu opens
        updateStatusBarIcon()
    }
}
