//
//  StatusItemView.swift
//  WhichSpace
//
//  Created by Stephen Sykes on 30/10/15.
//  Copyright © 2017 George Christou. All rights reserved.
//

import Cocoa

class StatusItemCell: NSStatusBarButtonCell {
    
    var isMenuVisible = false
    
    override func drawImage(_ image: NSImage, withFrame frame: NSRect, in controlView: NSView) {

        var darkColor: NSColor
        var whiteColor: NSColor
        if AppDelegate.darkModeEnabled {
            darkColor = NSColor(calibratedWhite: 0.7, alpha: 1)
            whiteColor = NSColor(calibratedWhite: 0, alpha: 1)
        } else {
            darkColor = NSColor(calibratedWhite: 0.3, alpha: 1)
            whiteColor = NSColor(calibratedWhite: 1, alpha: 1)
        }

        let blueColor = NSColor(calibratedRed: 0, green: 0.41, blue: 0.85, alpha: 1)
        let foregroundColor = isMenuVisible ? darkColor : whiteColor
        let backgroundColor = isMenuVisible ? whiteColor : darkColor
        
        if isMenuVisible {
            let rectPath = NSBezierPath(rect: frame)
            blueColor.setFill()
            rectPath.fill()
        }
        
        let roundedRectanglePath = NSBezierPath(roundedRect: NSRect(x: 5, y: 3, width: 16, height: 16), xRadius: 2, yRadius: 2)
        backgroundColor.setFill()
        roundedRectanglePath.fill()
        
        let titleRect = NSRect(x: frame.origin.x, y: frame.origin.y + 3, width: frame.size.width, height: frame.size.height)
        
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = NSTextAlignment.center
        
        let font = NSFont.boldSystemFont(ofSize: 11)
        let attributes = [NSFontAttributeName: font, NSParagraphStyleAttributeName: paragraphStyle, NSForegroundColorAttributeName: foregroundColor]
        title.draw(in: titleRect, withAttributes:attributes)
    }
}
