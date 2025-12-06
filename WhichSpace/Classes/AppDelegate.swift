//
//  AppDelegate.swift
//  WhichSpace
//
//  Created by George on 27/10/2015.
//  Copyright © 2020 George Christou. All rights reserved.
//

import Cocoa
import LaunchAtLogin
import Sparkle

// swiftformat:disable wrapArguments
private enum Localization {
    static let applyColorToAll = NSLocalizedString(
        "apply_color_to_all",
        comment: "Menu item to apply color to all spaces"
    )
    static let applyColorToAllTip = NSLocalizedString(
        "apply_color_to_all_tip",
        comment: "Tooltip for apply color to all spaces"
    )
    static let applyStyleToAll = NSLocalizedString(
        "apply_style_to_all",
        comment: "Menu item to apply style to all spaces"
    )
    static let applyStyleToAllTip = NSLocalizedString(
        "apply_style_to_all_tip",
        comment: "Tooltip for apply style to all spaces"
    )
    static let applyToAll = NSLocalizedString("apply_to_all", comment: "Menu item to apply setting to all spaces")
    static let applyToAllTip = NSLocalizedString(
        "apply_to_all_tip",
        comment: "Tooltip for apply all settings to all spaces"
    )
    static let backgroundLabel = NSLocalizedString("background_label", comment: "Label for background color section")
    static let colorTitle = NSLocalizedString("color_menu_title", comment: "Title of the color menu")
    static let foregroundLabel = NSLocalizedString("foreground_label", comment: "Label for foreground color section")
    static let launchAtLogin = NSLocalizedString("launch_at_login", comment: "Menu item to launch at login")
    static let numberTitle = NSLocalizedString("number_menu_title", comment: "Title of the number style menu")
    static let resetColorToDefault = NSLocalizedString(
        "reset_color_to_default",
        comment: "Menu item to reset color to default"
    )
    static let resetColorToDefaultTip = NSLocalizedString(
        "reset_color_to_default_tip",
        comment: "Tooltip for reset color to default"
    )
    static let resetSpaceToDefault = NSLocalizedString(
        "reset_space_to_default",
        comment: "Menu item to reset space customization"
    )
    static let resetSpaceToDefaultTip = NSLocalizedString(
        "reset_space_to_default_tip",
        comment: "Tooltip for reset space to default"
    )
    static let resetStyleToDefault = NSLocalizedString(
        "reset_style_to_default",
        comment: "Menu item to reset style to default"
    )
    static let resetStyleToDefaultTip = NSLocalizedString(
        "reset_style_to_default_tip",
        comment: "Tooltip for reset style to default"
    )
    static let styleTitle = NSLocalizedString("style_menu_title", comment: "Title of the style menu")
    static let symbolTitle = NSLocalizedString("symbol_menu_title", comment: "Title of the symbol menu")
}

// swiftformat:enable wrapArguments

@main
@objc
final class AppDelegate: NSObject, NSApplicationDelegate {
    @IBOutlet var statusMenu: NSMenu!
    @IBOutlet var application: NSApplication!
    @IBOutlet var workspace: NSWorkspace!
    private var updaterController: SPUStandardUpdaterController!

    let mainDisplay = "Main"
    let spacesMonitorFile = "~/Library/Preferences/com.apple.spaces.plist"

    let statusBarItem = NSStatusBar.system.statusItem(withLength: 24)
    let conn = _CGSDefaultConnection()

    private var currentSpace: Int = 0
    private var currentSpaceLabel: String = "?"
    private var darkModeEnabled = false
    private var isPickingForeground = true
    private var lastUpdateTime: Date = .distantPast
    private var mouseEventMonitor: Any?
    private var spacesMonitor: DispatchSourceFileSystemObject?

    private func configureApplication() {
        application = NSApplication.shared
        // Specifying `.Accessory` both hides the Dock icon and allows
        // the update dialog to take focus
        application.setActivationPolicy(.accessory)
    }

    private func configureObservers() {
        workspace = NSWorkspace.shared
        workspace.notificationCenter.addObserver(
            self,
            selector: #selector(AppDelegate.updateActiveSpaceNumber),
            name: NSWorkspace.activeSpaceDidChangeNotification,
            object: workspace
        )
        DistributedNotificationCenter.default().addObserver(
            self,
            selector: #selector(updateDarkModeStatus(_:)),
            name: NSNotification.Name("AppleInterfaceThemeChangedNotification"),
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(AppDelegate.updateActiveSpaceNumber),
            name: NSApplication.didUpdateNotification,
            object: nil
        )

        // Monitor when a different application becomes active (e.g.,, clicking on another display)
        workspace.notificationCenter.addObserver(
            self,
            selector: #selector(AppDelegate.updateActiveSpaceNumber),
            name: NSWorkspace.didActivateApplicationNotification,
            object: workspace
        )

        // Fallback: monitor mouse clicks for cases where the same app's window is on another display
        mouseEventMonitor = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDown) { [weak self] _ in
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                guard let self else { return }
                // Skip if a notification-triggered update happened recently
                if Date().timeIntervalSince(self.lastUpdateTime) > 0.5 {
                    self.updateActiveSpaceNumber()
                }
            }
        }
    }

    private func configureMenuBarIcon() {
        updateDarkModeStatus()
        configureVersionHeader()
        configureColorMenuItem()
        configureStyleMenuItem()
        configureApplyAndResetMenuItems()
        configureLaunchAtLoginMenuItem()
        statusMenu.delegate = self
        statusBarItem.menu = statusMenu
        updateStatusBarIcon()
    }

    private func configureVersionHeader() {
        let name = Bundle.main.infoDictionary?["CFBundleName"] as? String ?? "WhichSpace"
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        let versionItem = NSMenuItem(title: "\(name) v\(version)", action: nil, keyEquivalent: "")
        versionItem.isEnabled = false
        statusMenu.insertItem(versionItem, at: 0)
        statusMenu.insertItem(NSMenuItem.separator(), at: 1)
    }

    private func configureColorMenuItem() {
        let colorsMenu = createColorMenu()
        let colorsMenuItem = NSMenuItem(title: Localization.colorTitle, action: nil, keyEquivalent: "")
        colorsMenuItem.submenu = colorsMenu
        statusMenu.insertItem(colorsMenuItem, at: 2)
    }

    private func configureStyleMenuItem() {
        let styleMenu = NSMenu(title: Localization.styleTitle)
        styleMenu.delegate = self

        // Add Number submenu (icon shapes)
        let iconMenu = createIconMenu()
        let iconMenuItem = NSMenuItem(title: Localization.numberTitle, action: nil, keyEquivalent: "")
        iconMenuItem.submenu = iconMenu
        styleMenu.addItem(iconMenuItem)

        // Add Symbol submenu
        let symbolMenu = createSymbolMenu()
        let symbolMenuItem = NSMenuItem(title: Localization.symbolTitle, action: nil, keyEquivalent: "")
        symbolMenuItem.submenu = symbolMenu
        styleMenu.addItem(symbolMenuItem)

        styleMenu.addItem(NSMenuItem.separator())

        let applyStyleItem = NSMenuItem(
            title: Localization.applyStyleToAll,
            action: #selector(applyStyleToAllSpaces),
            keyEquivalent: ""
        )
        applyStyleItem.target = self
        applyStyleItem.toolTip = Localization.applyStyleToAllTip
        styleMenu.addItem(applyStyleItem)

        let resetStyleItem = NSMenuItem(
            title: Localization.resetStyleToDefault,
            action: #selector(resetStyleToDefault),
            keyEquivalent: ""
        )
        resetStyleItem.target = self
        resetStyleItem.toolTip = Localization.resetStyleToDefaultTip
        styleMenu.addItem(resetStyleItem)

        let styleMenuItem = NSMenuItem(title: Localization.styleTitle, action: nil, keyEquivalent: "")
        styleMenuItem.submenu = styleMenu

        statusMenu.insertItem(styleMenuItem, at: 3)
        statusMenu.insertItem(NSMenuItem.separator(), at: 4)
    }

    private func configureApplyAndResetMenuItems() {
        let applyToAllItem = NSMenuItem(
            title: Localization.applyToAll,
            action: #selector(applyAllToAllSpaces),
            keyEquivalent: ""
        )
        applyToAllItem.target = self
        applyToAllItem.toolTip = Localization.applyToAllTip
        statusMenu.insertItem(applyToAllItem, at: 5)

        let resetItem = NSMenuItem(
            title: Localization.resetSpaceToDefault,
            action: #selector(resetSpaceToDefault),
            keyEquivalent: ""
        )
        resetItem.target = self
        resetItem.toolTip = Localization.resetSpaceToDefaultTip
        statusMenu.insertItem(resetItem, at: 6)

        statusMenu.insertItem(NSMenuItem.separator(), at: 7)
    }

    private func configureLaunchAtLoginMenuItem() {
        let launchAtLoginItem = NSMenuItem(
            title: Localization.launchAtLogin,
            action: #selector(toggleLaunchAtLogin),
            keyEquivalent: ""
        )
        launchAtLoginItem.target = self
        launchAtLoginItem.tag = 100
        statusMenu.insertItem(launchAtLoginItem, at: 8)
    }

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
        colorsMenu.addItem(NSMenuItem.separator())

        let applyToAllItem = NSMenuItem(
            title: Localization.applyColorToAll,
            action: #selector(applyColorsToAllSpaces),
            keyEquivalent: ""
        )
        applyToAllItem.target = self
        applyToAllItem.toolTip = Localization.applyColorToAllTip
        colorsMenu.addItem(applyToAllItem)

        let resetColorItem = NSMenuItem(
            title: Localization.resetColorToDefault,
            action: #selector(resetColorToDefault),
            keyEquivalent: ""
        )
        resetColorItem.target = self
        resetColorItem.toolTip = Localization.resetColorToDefaultTip
        colorsMenu.addItem(resetColorItem)

        return colorsMenu
    }

    private func createIconMenu() -> NSMenu {
        let iconMenu = NSMenu(title: Localization.numberTitle)
        iconMenu.delegate = self

        for style in IconStyle.allCases {
            let item = NSMenuItem()
            let rowView = IconStyleRowView(style: style)
            rowView.frame = NSRect(origin: .zero, size: rowView.intrinsicContentSize)
            rowView.isChecked = style == currentIconStyle()
            rowView.customColors = SpacePreferences.colors(forSpace: currentSpace)
            rowView.darkMode = darkModeEnabled
            rowView.previewNumber = currentSpaceLabel == "?" ? "1" : currentSpaceLabel
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
        let symbolPickerView = SFSymbolPickerView()
        symbolPickerView.frame = NSRect(origin: .zero, size: symbolPickerView.intrinsicContentSize)
        symbolPickerView.selectedSymbol = SpacePreferences.sfSymbol(forSpace: currentSpace)
        symbolPickerView.darkMode = darkModeEnabled
        symbolPickerView.onSymbolSelected = { [weak self] symbol in
            self?.setSymbol(symbol)
        }
        symbolPickerItem.view = symbolPickerView
        symbolMenu.addItem(symbolPickerItem)

        return symbolMenu
    }

    private func setSymbol(_ symbol: String?) {
        guard currentSpace > 0 else { return }
        SpacePreferences.setSFSymbol(symbol, forSpace: currentSpace)
        updateStatusBarIcon()
    }

    private func selectIconStyle(_ style: IconStyle, rowView: IconStyleRowView?) {
        guard currentSpace > 0 else { return }

        // Clear SF Symbol to switch to number mode
        SpacePreferences.clearSFSymbol(forSpace: currentSpace)
        SpacePreferences.setIconStyle(style, forSpace: currentSpace)

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

    private func currentIconStyle() -> IconStyle {
        SpacePreferences.iconStyle(forSpace: currentSpace) ?? .square
    }

    private func setForegroundColor(_ color: NSColor) {
        guard currentSpace > 0 else { return }
        let existingColors = SpacePreferences.colors(forSpace: currentSpace)
        let background = existingColors?.backgroundColor ?? .black
        let newColors = SpaceColors(foreground: color, background: background)
        SpacePreferences.setColors(newColors, forSpace: currentSpace)
        updateStatusBarIcon()
    }

    private func setBackgroundColor(_ color: NSColor) {
        guard currentSpace > 0 else { return }
        let existingColors = SpacePreferences.colors(forSpace: currentSpace)
        let foreground = existingColors?.foregroundColor ?? .white
        let newColors = SpaceColors(foreground: foreground, background: color)
        SpacePreferences.setColors(newColors, forSpace: currentSpace)
        updateStatusBarIcon()
    }

    private func showColorPanel() {
        // Activate the app so the color panel can be shown
        NSApp.activate(ignoringOtherApps: true)

        let colorPanel = NSColorPanel.shared
        colorPanel.setTarget(self)
        colorPanel.setAction(#selector(colorChanged(_:)))
        colorPanel.isContinuous = true

        // Set initial color based on current space preferences
        if let colors = SpacePreferences.colors(forSpace: currentSpace) {
            colorPanel.color = isPickingForeground ? colors.foregroundColor : colors.backgroundColor
        } else {
            colorPanel.color = isPickingForeground ? .white : .black
        }

        colorPanel.makeKeyAndOrderFront(nil)
    }

    @objc func colorChanged(_ sender: NSColorPanel) {
        guard currentSpace > 0 else { return }

        let existingColors = SpacePreferences.colors(forSpace: currentSpace)
        let foreground = isPickingForeground ? sender.color : (existingColors?.foregroundColor ?? .white)
        let background = isPickingForeground ? (existingColors?.backgroundColor ?? .black) : sender.color

        let newColors = SpaceColors(foreground: foreground, background: background)
        SpacePreferences.setColors(newColors, forSpace: currentSpace)
        updateStatusBarIcon()
    }

    /// Returns all space indices across all displays (excluding fullscreen spaces)
    private func getAllSpaceIndices() -> Set<Int> {
        var indices = Set<Int>()
        guard let displays = CGSCopyManagedDisplaySpaces(conn) as? [NSDictionary] else {
            return indices
        }

        for display in displays {
            guard let spaces = display["Spaces"] as? [[String: Any]] else {
                continue
            }

            var localIndex = 0
            for space in spaces {
                let isFullscreen = space["TileLayoutManager"] is [String: Any]
                if isFullscreen {
                    continue
                }
                localIndex += 1
                indices.insert(localIndex)
            }
        }

        return indices
    }

    @objc func applyColorsToAllSpaces() {
        guard currentSpace > 0,
              let colors = SpacePreferences.colors(forSpace: currentSpace)
        else { return }
        for space in getAllSpaceIndices() {
            SpacePreferences.setColors(colors, forSpace: space)
        }
    }

    @objc func applyStyleToAllSpaces() {
        guard currentSpace > 0 else { return }
        let style = currentIconStyle()
        let symbol = SpacePreferences.sfSymbol(forSpace: currentSpace)
        for space in getAllSpaceIndices() {
            SpacePreferences.setIconStyle(style, forSpace: space)
            SpacePreferences.setSFSymbol(symbol, forSpace: space)
        }
    }

    @objc func applyAllToAllSpaces() {
        guard currentSpace > 0 else { return }
        let style = currentIconStyle()
        let colors = SpacePreferences.colors(forSpace: currentSpace)
        let symbol = SpacePreferences.sfSymbol(forSpace: currentSpace)
        for space in getAllSpaceIndices() {
            SpacePreferences.setIconStyle(style, forSpace: space)
            SpacePreferences.setSFSymbol(symbol, forSpace: space)
            if let colors {
                SpacePreferences.setColors(colors, forSpace: space)
            }
        }
    }

    @objc func resetColorToDefault() {
        guard currentSpace > 0 else { return }
        SpacePreferences.clearColors(forSpace: currentSpace)
        updateStatusBarIcon()
    }

    @objc func resetStyleToDefault() {
        guard currentSpace > 0 else { return }
        SpacePreferences.clearIconStyle(forSpace: currentSpace)
        SpacePreferences.clearSFSymbol(forSpace: currentSpace)
        updateStatusBarIcon()
    }

    @objc func resetSpaceToDefault() {
        guard currentSpace > 0 else { return }
        SpacePreferences.clearColors(forSpace: currentSpace)
        SpacePreferences.clearIconStyle(forSpace: currentSpace)
        SpacePreferences.clearSFSymbol(forSpace: currentSpace)
        updateStatusBarIcon()
    }

    @objc func toggleLaunchAtLogin() {
        LaunchAtLogin.isEnabled.toggle()
    }

    private func updateStatusBarIcon() {
        let customColors = SpacePreferences.colors(forSpace: currentSpace)

        let icon: NSImage
        if let sfSymbol = SpacePreferences.sfSymbol(forSpace: currentSpace) {
            icon = SpaceIconGenerator.generateSFSymbolIcon(
                symbolName: sfSymbol,
                darkMode: darkModeEnabled,
                customColors: customColors
            )
        } else {
            icon = SpaceIconGenerator.generateIcon(
                for: currentSpaceLabel,
                darkMode: darkModeEnabled,
                customColors: customColors,
                style: currentIconStyle()
            )
        }
        statusBarItem.button?.image = icon
    }

    private func configureSparkle() {
        updaterController = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: self
        )
    }

    private func configureSpaceMonitor() {
        // Cancel existing monitor if any
        spacesMonitor?.cancel()
        spacesMonitor = nil

        let fullPath = (spacesMonitorFile as NSString).expandingTildeInPath
        let queue = DispatchQueue.global(qos: .default)
        let fildes = open(fullPath.cString(using: String.Encoding.utf8)!, O_EVTONLY)
        if fildes == -1 {
            NSLog("Failed to open file: \(spacesMonitorFile)")
            return
        }

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fildes,
            eventMask: DispatchSource.FileSystemEvent.delete,
            queue: queue
        )

        source.setEventHandler { [weak self] in
            guard let self else { return }
            let flags = source.data.rawValue
            if flags & DispatchSource.FileSystemEvent.delete.rawValue != 0 {
                self.updateActiveSpaceNumber()
                self.configureSpaceMonitor()
            }
        }

        source.setCancelHandler {
            close(fildes)
        }

        source.resume()
        spacesMonitor = source
    }

    @objc func updateDarkModeStatus(_: AnyObject? = nil) {
        let dictionary = UserDefaults.standard.persistentDomain(forName: UserDefaults.globalDomain)
        if let interfaceStyle = dictionary?["AppleInterfaceStyle"] as? NSString {
            darkModeEnabled = interfaceStyle.localizedCaseInsensitiveContains("dark")
        } else {
            darkModeEnabled = false
        }
        updateStatusBarIcon()
    }

    func applicationWillFinishLaunching(_: Notification) {
        PFMoveToApplicationsFolderIfNecessary()
        configureApplication()
        configureObservers()
        configureMenuBarIcon()
        configureSparkle()
        configureSpaceMonitor()
        updateActiveSpaceNumber()
    }

    @objc func updateActiveSpaceNumber() {
        guard let displays = CGSCopyManagedDisplaySpaces(conn) as? [NSDictionary],
              let activeDisplay = CGSCopyActiveMenuBarDisplayIdentifier(conn) as? String
        else {
            return
        }

        for display in displays {
            guard let current = display["Current Space"] as? [String: Any],
                  let spaces = display["Spaces"] as? [[String: Any]],
                  let displayID = display["Display Identifier"] as? String
            else {
                continue
            }

            // Only process the active display
            guard displayID == mainDisplay || displayID == activeDisplay else {
                continue
            }

            guard let activeSpaceID = current["ManagedSpaceID"] as? Int else {
                continue
            }

            // Find the position of the active space within this display's spaces
            var localIndex = 0
            for space in spaces {
                guard let spaceID = space["ManagedSpaceID"] as? Int else {
                    continue
                }

                let isFullscreen = space["TileLayoutManager"] is [String: Any]
                if isFullscreen {
                    // If the active space is a fullscreen space, preserve the last known space
                    if spaceID == activeSpaceID {
                        DispatchQueue.main.async {
                            self.lastUpdateTime = Date()
                            // Keep currentSpace and currentSpaceLabel unchanged
                        }
                        return
                    }
                    continue
                }

                localIndex += 1
                if spaceID == activeSpaceID {
                    DispatchQueue.main.async {
                        self.currentSpace = localIndex
                        self.currentSpaceLabel = String(localIndex)
                        self.lastUpdateTime = Date()
                        self.updateStatusBarIcon()
                    }
                    return
                }
            }
        }

        DispatchQueue.main.async {
            self.currentSpace = 0
            self.currentSpaceLabel = "?"
            self.updateStatusBarIcon()
        }
    }

    @IBAction func checkForUpdatesClicked(_ sender: NSMenuItem) {
        updaterController.checkForUpdates(sender)
    }

    @IBAction func quitClicked(_: NSMenuItem) {
        NSApplication.shared.terminate(self)
    }
}

// MARK: - SPUStandardUserDriverDelegate

extension AppDelegate: SPUStandardUserDriverDelegate {
    func supportsGentleScheduledUpdateReminders() -> Bool {
        true
    }

    func standardUserDriverWillShowModalAlert() {
        NSApp.activate(ignoringOtherApps: true)
    }

    func standardUserDriverDidReceiveUserAttention(forUpdate _: SUAppcastItem) {
        NSApp.activate(ignoringOtherApps: true)
    }
}

// MARK: - NSMenuDelegate

extension AppDelegate: NSMenuDelegate {
    func menuWillOpen(_ menu: NSMenu) {
        let currentStyle = currentIconStyle()
        let customColors = SpacePreferences.colors(forSpace: currentSpace)
        let previewNumber = currentSpaceLabel == "?" ? "1" : currentSpaceLabel
        let currentSymbol = SpacePreferences.sfSymbol(forSpace: currentSpace)
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
                view.darkMode = darkModeEnabled
                view.previewNumber = previewNumber
                view.needsDisplay = true
            }

            // Update symbol picker view
            if let view = item.view as? SFSymbolPickerView {
                view.selectedSymbol = currentSymbol
                view.darkMode = darkModeEnabled
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
    }
}
