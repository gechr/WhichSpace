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

    private var currentSpaceNumber: String = "?"
    private var isMenuVisible = false
    private var darkModeEnabled = false
    private var mouseEventMonitor: Any?
    private var lastUpdateTime: Date = .distantPast

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
        statusBarItem.menu = statusMenu
        updateStatusBarIcon()
    }

    private func updateStatusBarIcon() {
        let icon = SpaceIconGenerator.generateIcon(
            for: currentSpaceNumber,
            darkMode: darkModeEnabled,
            highlighted: isMenuVisible
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
                        self.currentSpaceNumber = String(localIndex)
                        self.lastUpdateTime = Date()
                        self.updateStatusBarIcon()
                    }
                    return
                }
            }
        }

        DispatchQueue.main.async {
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
