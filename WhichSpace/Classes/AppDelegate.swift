//
//  AppDelegate.swift
//  WhichSpace
//
//  Created by George on 27/10/2015.
//  Copyright © 2020 George Christou. All rights reserved.
//

import Cocoa
import Sparkle

private enum Localization {
    static let applyToAll = NSLocalizedString(
        "apply_to_all",
        comment: "Menu item to apply setting to all spaces"
    )
    static let applyColorToAll = NSLocalizedString(
        "apply_color_to_all",
        comment: "Menu item to apply color to all spaces"
    )
    static let applyIconToAll = NSLocalizedString(
        "apply_icon_to_all",
        comment: "Menu item to apply icon to all spaces"
    )
    static let backgroundLabel = NSLocalizedString("background_label", comment: "Label for background color section")
    static let colorTitle = NSLocalizedString("color_menu_title", comment: "Title of the color menu")
    static let foregroundLabel = NSLocalizedString("foreground_label", comment: "Label for foreground color section")
    static let iconTitle = NSLocalizedString("icon_menu_title", comment: "Title of the icon menu")
    static let resetToDefault = NSLocalizedString("reset_to_default", comment: "Menu item to reset customization")
}

@main
@objc
final class AppDelegate: NSObject, NSApplicationDelegate {
    @IBOutlet var window: NSWindow!
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

        // Monitor when a different application becomes active (e.g., clicking on another display)
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
        configureColorMenuItems()
        configureIconMenuItems()
        configureResetMenuItem()
        statusMenu.delegate = self
        statusBarItem.menu = statusMenu
        updateStatusBarIcon()
    }

    private func configureResetMenuItem() {
        statusMenu.insertItem(NSMenuItem.separator(), at: 3)

        let applyAllItem = NSMenuItem(
            title: Localization.applyToAll,
            action: #selector(applyAllToAllSpaces),
            keyEquivalent: ""
        )
        applyAllItem.target = self
        statusMenu.insertItem(applyAllItem, at: 4)

        let resetItem = NSMenuItem(
            title: Localization.resetToDefault,
            action: #selector(resetToDefaultClicked),
            keyEquivalent: ""
        )
        resetItem.target = self
        statusMenu.insertItem(resetItem, at: 5)

        statusMenu.insertItem(NSMenuItem.separator(), at: 6)
    }

    private func configureColorMenuItems() {
        // Create Color submenu
        let colorsMenu = NSMenu(title: Localization.colorTitle)

        // Foreground label
        let foregroundLabel = NSMenuItem(title: Localization.foregroundLabel, action: nil, keyEquivalent: "")
        foregroundLabel.isEnabled = false
        colorsMenu.addItem(foregroundLabel)

        // Foreground color swatches
        let foregroundSwatchItem = NSMenuItem()
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

        colorsMenu.addItem(NSMenuItem.separator())

        // Background label
        let backgroundLabel = NSMenuItem(title: Localization.backgroundLabel, action: nil, keyEquivalent: "")
        backgroundLabel.isEnabled = false
        colorsMenu.addItem(backgroundLabel)

        // Background color swatches
        let backgroundSwatchItem = NSMenuItem()
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

        colorsMenu.addItem(NSMenuItem.separator())

        let applyToAllItem = NSMenuItem(
            title: Localization.applyColorToAll,
            action: #selector(applyColorsToAllSpaces),
            keyEquivalent: ""
        )
        applyToAllItem.target = self
        colorsMenu.addItem(applyToAllItem)

        let colorsMenuItem = NSMenuItem(
            title: Localization.colorTitle,
            action: nil,
            keyEquivalent: ""
        )
        colorsMenuItem.submenu = colorsMenu

        statusMenu.insertItem(colorsMenuItem, at: 0)
    }

    private func configureIconMenuItems() {
        let iconMenu = NSMenu(title: Localization.iconTitle)
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

        iconMenu.addItem(NSMenuItem.separator())

        let applyToAllItem = NSMenuItem(
            title: Localization.applyIconToAll,
            action: #selector(applyIconToAll),
            keyEquivalent: ""
        )
        applyToAllItem.target = self
        iconMenu.addItem(applyToAllItem)

        let iconMenuItem = NSMenuItem(
            title: Localization.iconTitle,
            action: nil,
            keyEquivalent: ""
        )
        iconMenuItem.submenu = iconMenu

        statusMenu.insertItem(iconMenuItem, at: 1)
        statusMenu.insertItem(NSMenuItem.separator(), at: 2)
    }

    private func selectIconStyle(_ style: IconStyle, rowView: IconStyleRowView?) {
        guard currentSpace > 0 else { return }
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

    @objc func applyIconToAll() {
        let style = currentIconStyle()
        for space in 1 ... 16 {
            SpacePreferences.setIconStyle(style, forSpace: space)
        }
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

    @objc func applyColorsToAllSpaces() {
        guard let colors = SpacePreferences.colors(forSpace: currentSpace) else { return }
        for space in 1 ... 16 {
            SpacePreferences.setColors(colors, forSpace: space)
        }
    }

    @objc func applyAllToAllSpaces() {
        let style = currentIconStyle()
        let colors = SpacePreferences.colors(forSpace: currentSpace)
        for space in 1 ... 16 {
            SpacePreferences.setIconStyle(style, forSpace: space)
            if let colors {
                SpacePreferences.setColors(colors, forSpace: space)
            }
        }
    }

    @objc func resetToDefaultClicked() {
        guard currentSpace > 0 else { return }
        SpacePreferences.clearColors(forSpace: currentSpace)
        SpacePreferences.clearIconStyle(forSpace: currentSpace)
        updateStatusBarIcon()
    }

    private func updateStatusBarIcon() {
        let customColors = SpacePreferences.colors(forSpace: currentSpace)
        let icon = SpaceIconGenerator.generateIcon(
            for: currentSpaceLabel,
            darkMode: darkModeEnabled,
            customColors: customColors,
            style: currentIconStyle()
        )
        statusBarItem.button?.image = icon
    }

    private func configureSparkle() {
        updaterController = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
    }

    private func configureSpaceMonitor() {
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

        source.setEventHandler {
            let flags = source.data.rawValue
            if flags & DispatchSource.FileSystemEvent.delete.rawValue != 0 {
                source.cancel()
                self.updateActiveSpaceNumber()
                self.configureSpaceMonitor()
            }
        }

        source.setCancelHandler {
            close(fildes)
        }

        source.resume()
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
                let isFullscreen = space["TileLayoutManager"] is [String: Any]
                if isFullscreen {
                    continue
                }

                localIndex += 1
                guard let spaceID = space["ManagedSpaceID"] as? Int else {
                    continue
                }
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

// MARK: - NSMenuDelegate

extension AppDelegate: NSMenuDelegate {
    func menuWillOpen(_ menu: NSMenu) {
        // Update icon style views when menu opens
        let currentStyle = currentIconStyle()
        let customColors = SpacePreferences.colors(forSpace: currentSpace)
        let previewNumber = currentSpaceLabel == "?" ? "1" : currentSpaceLabel

        for item in menu.items {
            // Direct items (when Icons submenu opens)
            if let view = item.view as? IconStyleRowView {
                view.isChecked = item.representedObject as? IconStyle == currentStyle
                view.customColors = customColors
                view.darkMode = darkModeEnabled
                view.previewNumber = previewNumber
                view.needsDisplay = true
            }
        }
    }
}
