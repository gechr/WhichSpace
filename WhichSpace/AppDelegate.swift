//
//  AppDelegate.swift
//  WhichSpace
//
//  Created by George on 27/10/2015.
//  Copyright © 2015 George Christou. All rights reserved.
//

import Cocoa

@NSApplicationMain
class AppDelegate: NSObject, NSApplicationDelegate {

    @IBOutlet weak var window: NSWindow!
    @IBOutlet weak var statusMenu: NSMenu!

    var icons = [NSImage]()
    let statusBarItem = NSStatusBar.systemStatusBar().statusItemWithLength(-1)

    func applicationWillFinishLaunching(notification: NSNotification) {
        NSApp.setActivationPolicy(.Prohibited)
        NSWorkspace.sharedWorkspace().notificationCenter.addObserver(
            self,
            selector: "activeSpaceDidChange",
            name: NSWorkspaceActiveSpaceDidChangeNotification,
            object: NSWorkspace.sharedWorkspace()
        )
    }

    func applicationDidFinishLaunching(notification: NSNotification) {
        icons.append(NSImage(named: "Default")!)
        icons[0].template = true
        for i in 1...6 {
            let iconName = "space_" + String(i)
            icons.append(NSImage(named: iconName)!)
            icons[i].template = true
        }
        statusBarItem.image = icons.first
        statusBarItem.menu = statusMenu
    }

    func activeSpaceDidChange() {
        let conn = _CGSDefaultConnection()
        let info = CGSCopyManagedDisplaySpaces(conn)
        let displayInfo = info[0] as! NSDictionary
        let activeSpaceID = displayInfo["Current Space"]!["ManagedSpaceID"] as! Int
        let spaces = displayInfo["Spaces"] as! NSArray
        for (index, space) in spaces.enumerate() {
            let spaceID = space["ManagedSpaceID"] as! Int
            let iconIndex = index + 1
            if spaceID == activeSpaceID {
                if iconIndex >= icons.count {
                    break
                }
                statusBarItem.image = icons[iconIndex]
                return
            }
        }
        statusBarItem.image = icons.first
    }

    @IBAction func quitClicked(sender: NSMenuItem) {
        NSApplication.sharedApplication().terminate(self)
    }
}
