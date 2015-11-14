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
class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate, SUUpdaterDelegate {

    @IBOutlet weak var window: NSWindow!
    @IBOutlet weak var statusMenu: NSMenu!
    @IBOutlet weak var application: NSApplication!
    @IBOutlet weak var workspace: NSWorkspace!
    @IBOutlet weak var updater: SUUpdater!

    // Frequency to check active space (in seconds)
    let UpdateInterval: Double = 1

    var icons = [NSImage]()
    let statusBarItem = NSStatusBar.systemStatusBar().statusItemWithLength(27)
    let conn = _CGSDefaultConnection()

    func configureSparkle() {
        updater = SUUpdater.sharedUpdater()
        updater.delegate = self
        // Silently check for updates on launch
        updater.checkForUpdatesInBackground()
    }

    func applicationWillFinishLaunching(notification: NSNotification) {
        application = NSApplication.sharedApplication()
        // Specifying `.Accessory` both hides the Dock icon and allows
        // the update dialog to take focus
        application.setActivationPolicy(.Accessory)

        workspace = NSWorkspace.sharedWorkspace()
        workspace.notificationCenter.addObserver(
            self,
            selector: "updateActiveSpaceNumber",
            name: NSWorkspaceActiveSpaceDidChangeNotification,
            object: workspace
        )

        // TODO: Figure out a suitable notification and add an observer
        //       rather than checking every `UpdateInterval` seconds
        NSTimer.scheduledTimerWithTimeInterval(
            UpdateInterval,
            target: self,
            selector: "updateActiveSpaceNumber",
            userInfo: nil,
            repeats: true
        )

        statusBarItem.button?.cell = StatusItemCell()

        configureSparkle()
    }

    func applicationDidFinishLaunching(notification: NSNotification) {
        statusBarItem.image = NSImage(named: "default")
        statusBarItem.menu = statusMenu

        // Show the correct space on launch
        updateActiveSpaceNumber()
    }

    func updateActiveSpaceNumber() {
        let info = CGSCopyManagedDisplaySpaces(conn)
        let displayInfo = info[0] as! NSDictionary
        let activeSpaceID = displayInfo["Current Space"]!["ManagedSpaceID"] as! Int
        let spaces = displayInfo["Spaces"] as! NSArray
        for (index, space) in spaces.enumerate() {
            let spaceID = space["ManagedSpaceID"] as! Int
            let spaceNumber = index + 1
            if spaceID == activeSpaceID {
                statusBarItem.button?.title = String(spaceNumber)
                return
            }
        }
    }

    func menuWillOpen(menu: NSMenu) {
        if let cell = statusBarItem.button?.cell as! StatusItemCell? {
            cell.isMenuVisible = true
        }
    }

    func menuDidClose(menu: NSMenu) {
        if let cell = statusBarItem.button?.cell as! StatusItemCell? {
            cell.isMenuVisible = false
        }
    }

    @IBAction func checkForUpdatesClicked(sender: NSMenuItem) {
        updater.checkForUpdates(sender)
    }

    @IBAction func quitClicked(sender: NSMenuItem) {
        NSApplication.sharedApplication().terminate(self)
    }
}
