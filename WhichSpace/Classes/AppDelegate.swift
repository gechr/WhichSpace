//
//  AppDelegate.swift
//  WhichSpace
//
//  Created by George on 27/10/2015.
//  Copyright © 2015 George Christou. All rights reserved.
//

import Cocoa
import Sparkle

@NSApplicationMain
@objc
class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate, SUUpdaterDelegate {

    @IBOutlet weak var window: NSWindow!
    @IBOutlet weak var statusMenu: NSMenu!
    @IBOutlet weak var application: NSApplication!
    @IBOutlet weak var workspace: NSWorkspace!
    @IBOutlet weak var updater: SUUpdater!

    let spacesMonitorFile = "~/Library/Preferences/com.apple.spaces.plist"

    let statusBarItem = NSStatusBar.system().statusItem(withLength: 27)
    let conn = _CGSDefaultConnection()

    static var darkModeEnabled = false

    fileprivate func configureApplication() {
        application = NSApplication.shared()
        // Specifying `.Accessory` both hides the Dock icon and allows
        // the update dialog to take focus
        application.setActivationPolicy(.accessory)
    }

    fileprivate func configureObservers() {
        workspace = NSWorkspace.shared()
        workspace.notificationCenter.addObserver(
            self,
            selector: #selector(AppDelegate.updateActiveSpaceNumber),
            name: NSNotification.Name.NSWorkspaceActiveSpaceDidChange,
            object: workspace
        )
        DistributedNotificationCenter.default().addObserver(
            self,
            selector: #selector(updateDarkModeStatus(_:)),
            name: NSNotification.Name("AppleInterfaceThemeChangedNotification"),
            object: nil
        )
    }

    fileprivate func configureMenuBarIcon() {
        updateDarkModeStatus()
        statusBarItem.button?.cell = StatusItemCell()
        statusBarItem.image = NSImage(named: "default") // This icon appears when switching spaces when cell length is variable width.
        statusBarItem.menu = statusMenu
    }

    fileprivate func configureSparkle() {
        updater = SUUpdater.shared()
        updater.delegate = self
        // Silently check for updates on launch
        updater.checkForUpdatesInBackground()
    }

    fileprivate func configureSpaceMonitor() {
        let fullPath = (spacesMonitorFile as NSString).expandingTildeInPath
        let queue = DispatchQueue.global(priority: DispatchQueue.GlobalQueuePriority.default)
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

    func updateDarkModeStatus(_ sender: AnyObject?=nil) {
        let dictionary = UserDefaults.standard.persistentDomain(forName: UserDefaults.globalDomain);
        if let interfaceStyle = dictionary?["AppleInterfaceStyle"] as? NSString {
            AppDelegate.darkModeEnabled = interfaceStyle.localizedCaseInsensitiveContains("dark")
        } else {
            AppDelegate.darkModeEnabled = false
        }
    }

    func applicationWillFinishLaunching(_ notification: Notification) {
        configureApplication()
        configureObservers()
        configureMenuBarIcon()
        configureSparkle()
        configureSpaceMonitor()
        updateActiveSpaceNumber()
    }

    func updateActiveSpaceNumber() {
        let info = CGSCopyManagedDisplaySpaces(conn) as! [NSDictionary]
        let displayInfo = info[0]
        let activeSpaceID = (displayInfo["Current Space"]! as! NSDictionary)["ManagedSpaceID"] as! Int
        let spaces = displayInfo["Spaces"] as! NSArray
        for (index, space) in spaces.enumerated() {
            let spaceID = (space as! NSDictionary)["ManagedSpaceID"] as! Int
            let spaceNumber = index + 1
            if spaceID == activeSpaceID {
                statusBarItem.button?.title = String("\(spaceNumber)")
                return
            }
        }
    }

    func menuWillOpen(_ menu: NSMenu) {
        if let cell = statusBarItem.button?.cell as! StatusItemCell? {
            cell.isMenuVisible = true
        }
    }

    func menuDidClose(_ menu: NSMenu) {
        if let cell = statusBarItem.button?.cell as! StatusItemCell? {
            cell.isMenuVisible = false
        }
    }

    @IBAction func checkForUpdatesClicked(_ sender: NSMenuItem) {
        updater.checkForUpdates(sender)
    }

    @IBAction func quitClicked(_ sender: NSMenuItem) {
        NSApplication.shared().terminate(self)
    }
}
