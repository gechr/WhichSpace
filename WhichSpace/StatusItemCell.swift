//
//  StatusItemView.swift
//  WhichSpace
//
//  Created by Stephen Sykes on 30/10/15.
//  Copyright © 2015 George Christou. All rights reserved.
//

import Cocoa

class StatusItemCell : NSStatusBarButtonCell {
    
    var isMenuVisible = false
    
    override func drawImage(image: NSImage, withFrame frame: NSRect, inView controlView: NSView) {
        let darkColor = NSColor(calibratedWhite: 0.3, alpha: 1)
        let whiteColor = NSColor(calibratedWhite: 1, alpha: 1)
        let blueColor = NSColor(calibratedRed: 0, green: 0.41, blue: 0.85, alpha: 1)

        let backgroundColor = isMenuVisible ? whiteColor : darkColor
        let foregroundColor = isMenuVisible ? darkColor : whiteColor
        
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
        paragraphStyle.alignment = NSTextAlignment.Center
        
        let font = NSFont.boldSystemFontOfSize(11)
        let attributes = [NSFontAttributeName: font, NSParagraphStyleAttributeName: paragraphStyle, NSForegroundColorAttributeName: foregroundColor]
        title.drawInRect(titleRect, withAttributes:attributes)
    }
}
