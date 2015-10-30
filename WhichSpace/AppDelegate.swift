//
//  AppDelegate.swift
//  WhichSpace
//
//  Created by George on 27/10/2015.
//  Copyright © 2015 George Christou. All rights reserved.
//

import Cocoa

@NSApplicationMain
class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {

    @IBOutlet weak var window: NSWindow!
    @IBOutlet weak var statusMenu: NSMenu!

    var icons = [NSImage]()
    let statusBarItem = NSStatusBar.systemStatusBar().statusItemWithLength(27)
    let conn = _CGSDefaultConnection()

    func applicationWillFinishLaunching(notification: NSNotification) {
        NSApp.setActivationPolicy(.Prohibited)
        NSWorkspace.sharedWorkspace().notificationCenter.addObserver(
            self,
            selector: "activeSpaceDidChange",
            name: NSWorkspaceActiveSpaceDidChangeNotification,
            object: NSWorkspace.sharedWorkspace()
        )
        
        statusBarItem.button?.cell = StatusItemCell()
    }

    func applicationDidFinishLaunching(notification: NSNotification) {
        statusBarItem.image = NSImage(named: "Default")
        statusBarItem.menu = statusMenu
        
        // show the correct space on launch
        activeSpaceDidChange()
    }

    func activeSpaceDidChange() {
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
    
    @IBAction func quitClicked(sender: NSMenuItem) {
        NSApplication.sharedApplication().terminate(self)
    }
}
