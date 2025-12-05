//
//  AppDelegate.swift
//  WhichSpace
//
//  Created by George on 27/10/2015.
//  Copyright © 2020 George Christou. All rights reserved.
//

import Cocoa
import Sparkle

@main
@objc
class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    @IBOutlet var window: NSWindow!
    @IBOutlet var statusMenu: NSMenu!
    @IBOutlet var application: NSApplication!
    @IBOutlet var workspace: NSWorkspace!
    private var updaterController: SPUStandardUpdaterController!

    let mainDisplay = "Main"
    let spacesMonitorFile = "~/Library/Preferences/com.apple.spaces.plist"

    let statusBarItem = NSStatusBar.system.statusItem(withLength: 24)
    let conn = _CGSDefaultConnection()

    private var currentSpaceInt: Int = 0
    private var currentSpaceNumber: String = "?"
    private var darkModeEnabled = false
    private var isMenuVisible = false
    private var isPickingForeground = true
    private var lastUpdateTime: Date = .distantPast
    private var mouseEventMonitor: Any?

    fileprivate func configureApplication() {
        application = NSApplication.shared
        // Specifying `.Accessory` both hides the Dock icon and allows
        // the update dialog to take focus
        application.setActivationPolicy(.accessory)
    }

    fileprivate func configureObservers() {
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

    fileprivate func configureMenuBarIcon() {
        updateDarkModeStatus()
        configureColorMenuItems()
        statusBarItem.menu = statusMenu
        updateStatusBarIcon()
    }

    fileprivate func configureColorMenuItems() {
        // Create Colors submenu
        let colorsMenu = NSMenu(title: "Colors")

        let foregroundItem = NSMenuItem(
            title: "Foreground...",
            action: #selector(setForegroundColorClicked),
            keyEquivalent: ""
        )
        foregroundItem.target = self

        let backgroundItem = NSMenuItem(
            title: "Background...",
            action: #selector(setBackgroundColorClicked),
            keyEquivalent: ""
        )
        backgroundItem.target = self

        let resetItem = NSMenuItem(
            title: "Reset to Default",
            action: #selector(resetColorsClicked),
            keyEquivalent: ""
        )
        resetItem.target = self

        colorsMenu.addItem(foregroundItem)
        colorsMenu.addItem(backgroundItem)
        colorsMenu.addItem(NSMenuItem.separator())
        colorsMenu.addItem(resetItem)

        let colorsMenuItem = NSMenuItem(title: "Colors", action: nil, keyEquivalent: "")
        colorsMenuItem.submenu = colorsMenu

        statusMenu.insertItem(colorsMenuItem, at: 0)
        statusMenu.insertItem(NSMenuItem.separator(), at: 1)
    }

    @objc func setForegroundColorClicked() {
        isPickingForeground = true
        showColorPanel()
    }

    @objc func setBackgroundColorClicked() {
        isPickingForeground = false
        showColorPanel()
    }

    private func showColorPanel() {
        // Activate the app so the color panel can be shown
        NSApp.activate(ignoringOtherApps: true)

        let colorPanel = NSColorPanel.shared
        colorPanel.setTarget(self)
        colorPanel.setAction(#selector(colorChanged(_:)))
        colorPanel.isContinuous = true

        // Set initial color based on current space preferences
        if let colors = SpacePreferences.colors(forSpace: currentSpaceInt) {
            colorPanel.color = isPickingForeground ? colors.foregroundColor : colors.backgroundColor
        } else {
            colorPanel.color = isPickingForeground ? .white : .black
        }

        colorPanel.makeKeyAndOrderFront(nil)
    }

    @objc func colorChanged(_ sender: NSColorPanel) {
        guard currentSpaceInt > 0 else { return }

        let existingColors = SpacePreferences.colors(forSpace: currentSpaceInt)
        let foreground = isPickingForeground ? sender.color : (existingColors?.foregroundColor ?? .white)
        let background = isPickingForeground ? (existingColors?.backgroundColor ?? .black) : sender.color

        let newColors = SpaceColors(foreground: foreground, background: background)
        SpacePreferences.setColors(newColors, forSpace: currentSpaceInt)
        updateStatusBarIcon()
    }

    @objc func resetColorsClicked() {
        guard currentSpaceInt > 0 else { return }
        SpacePreferences.clearColors(forSpace: currentSpaceInt)
        updateStatusBarIcon()
    }

    private func updateStatusBarIcon() {
        let customColors = SpacePreferences.colors(forSpace: currentSpaceInt)
        let icon = SpaceIconGenerator.generateIcon(
            for: currentSpaceNumber,
            darkMode: darkModeEnabled,
            highlighted: isMenuVisible,
            customColors: customColors
        )
        statusBarItem.button?.image = icon
    }

    fileprivate func configureSparkle() {
        updaterController = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
    }

    fileprivate func configureSpaceMonitor() {
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
        guard
            let displays = CGSCopyManagedDisplaySpaces(conn) as? [NSDictionary],
            let activeDisplay = CGSCopyActiveMenuBarDisplayIdentifier(conn) as? String
        else {
            return
        }

        for display in displays {
            guard
                let current = display["Current Space"] as? [String: Any],
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
                        self.currentSpaceInt = localIndex
                        self.currentSpaceNumber = String(localIndex)
                        self.lastUpdateTime = Date()
                        self.updateStatusBarIcon()
                    }
                    return
                }
            }
        }

        DispatchQueue.main.async {
            self.currentSpaceInt = 0
            self.currentSpaceNumber = "?"
            self.updateStatusBarIcon()
        }
    }

    func menuWillOpen(_: NSMenu) {
        isMenuVisible = true
        updateStatusBarIcon()
    }

    func menuDidClose(_: NSMenu) {
        isMenuVisible = false
        updateStatusBarIcon()
    }

    @IBAction func checkForUpdatesClicked(_ sender: NSMenuItem) {
        updaterController.checkForUpdates(sender)
    }

    @IBAction func quitClicked(_: NSMenuItem) {
        NSApplication.shared.terminate(self)
    }
}
