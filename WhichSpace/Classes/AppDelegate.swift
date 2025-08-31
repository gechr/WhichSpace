//
//  AppDelegate.swift
//  WhichSpace
//
//  Created by George on 27/10/2015.
//  Copyright © 2020 George Christou. All rights reserved.
//

import Cocoa
import Sparkle

@NSApplicationMain
@objc
class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {

    @IBOutlet weak var window: NSWindow!
    @IBOutlet weak var statusMenu: NSMenu!
    @IBOutlet weak var application: NSApplication!
    @IBOutlet weak var workspace: NSWorkspace!
    private var updaterController: SPUStandardUpdaterController!

    let mainDisplay = "Main"
    let spacesMonitorFile = "~/Library/Preferences/com.apple.spaces.plist"

    let statusBarItem = NSStatusBar.system.statusItem(withLength: 24)
    let conn = _CGSDefaultConnection()

    private var currentSpaceNumber: String = "?"
    private var isMenuVisible = false
    private var darkModeEnabled = false

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
        updaterController = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)
    }

    fileprivate func configureSpaceMonitor() {
        let fullPath = (spacesMonitorFile as NSString).expandingTildeInPath
        let queue = DispatchQueue.global(qos: .default)
        let fildes = open(fullPath.cString(using: String.Encoding.utf8)!, O_EVTONLY)
        if fildes == -1 {
            NSLog("Failed to open file: \(spacesMonitorFile)")
            return
        }

        let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fildes, eventMask: DispatchSource.FileSystemEvent.delete, queue: queue)

        source.setEventHandler { () -> Void in
            let flags = source.data.rawValue
            if (flags & DispatchSource.FileSystemEvent.delete.rawValue != 0) {
                source.cancel()
                self.updateActiveSpaceNumber()
                self.configureSpaceMonitor()
            }
        }

        source.setCancelHandler { () -> Void in
            close(fildes)
        }

        source.resume()
    }

    @objc func updateDarkModeStatus(_ sender: AnyObject? = nil) {
        let dictionary = UserDefaults.standard.persistentDomain(forName: UserDefaults.globalDomain)
        if let interfaceStyle = dictionary?["AppleInterfaceStyle"] as? NSString {
            darkModeEnabled = interfaceStyle.localizedCaseInsensitiveContains("dark")
        } else {
            darkModeEnabled = false
        }
        updateStatusBarIcon()
    }

    func applicationWillFinishLaunching(_ notification: Notification) {
        PFMoveToApplicationsFolderIfNecessary()
        configureApplication()
        configureObservers()
        configureMenuBarIcon()
        configureSparkle()
        configureSpaceMonitor()
        updateActiveSpaceNumber()
    }

    @objc func updateActiveSpaceNumber() {
        let displays = CGSCopyManagedDisplaySpaces(conn) as! [NSDictionary]
        let activeDisplay = CGSCopyActiveMenuBarDisplayIdentifier(conn) as! String
        let allSpaces: NSMutableArray = []
        var activeSpaceID = -1

        for d in displays {
            guard
                let current = d["Current Space"] as? [String: Any],
                let spaces = d["Spaces"] as? [[String: Any]],
                let dispID = d["Display Identifier"] as? String
                else {
                    continue
            }

            switch dispID {
            case mainDisplay, activeDisplay:
                activeSpaceID = current["ManagedSpaceID"] as! Int
            default:
                break
            }

            for s in spaces {
                let isFullscreen = s["TileLayoutManager"] as? [String: Any] != nil
                if isFullscreen {
                    continue
                }
                allSpaces.add(s)
            }
        }

        if activeSpaceID == -1 {
            DispatchQueue.main.async {
                self.currentSpaceNumber = "?"
                self.updateStatusBarIcon()
            }
            return
        }

        for (index, space) in allSpaces.enumerated() {
            let spaceID = (space as! NSDictionary)["ManagedSpaceID"] as! Int
            let spaceNumber = index + 1
            if spaceID == activeSpaceID {
                DispatchQueue.main.async {
                    self.currentSpaceNumber = String(spaceNumber)
                    self.updateStatusBarIcon()
                }
                return
            }
        }
    }

    func menuWillOpen(_ menu: NSMenu) {
        isMenuVisible = true
        updateStatusBarIcon()
    }

    func menuDidClose(_ menu: NSMenu) {
        isMenuVisible = false
        updateStatusBarIcon()
    }

    @IBAction func checkForUpdatesClicked(_ sender: NSMenuItem) {
        updaterController.checkForUpdates(sender)
    }

    @IBAction func quitClicked(_ sender: NSMenuItem) {
        NSApplication.shared.terminate(self)
    }
}
