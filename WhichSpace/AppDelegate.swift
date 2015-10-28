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
        for i in 0...5 {
            let iconName = "ic_looks_" + String(i + 1)
            icons.append(NSImage(named: iconName)!)
            icons[i].template = true
        }
        statusBarItem.image = icons[0]
        statusBarItem.menu = statusMenu
    }

    func activeSpaceDidChange() {
        // TODO: Figure out how to determine the *actual* space number
        let spaceNumber = Int(arc4random_uniform(UInt32(icons.count)))
        statusBarItem.image = icons[spaceNumber]
    }

    @IBAction func quitClicked(sender: NSMenuItem) {
        NSApplication.sharedApplication().terminate(self)
    }
}
