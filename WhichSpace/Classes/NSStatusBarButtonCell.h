//
//  NSStatusBarButtonCell.h
//  WhichSpace
//
//  Created by Stephen Sykes on 30/10/15.
//  Copyright © 2015 George Christou. All rights reserved.
//

#ifndef NSStatusBarButtonCell_h
#define NSStatusBarButtonCell_h

#import <AppKit/NSButtonCell.h>

@class NSMenu, NSStatusBar;

@interface NSStatusBarButtonCell : NSButtonCell
{
    NSStatusBar *_fStatusBar;
    NSMenu *_fStatusMenu;
    BOOL _fHighlightMode;
    BOOL _fDoubleClick;
    SEL _fDoubleAction;
}

+ (void)popupStatusBarMenu:(id)arg1 inRect:(struct CGRect)arg2 ofView:(id)arg3 withEvent:(id)arg4;
- (BOOL)_sendActionFrom:(id)arg1;
- (void)dismiss;
- (void)performClick:(id)arg1;
- (BOOL)trackMouse:(id)arg1 inRect:(struct CGRect)arg2 ofView:(id)arg3 untilMouseUp:(BOOL)arg4;
- (void)_fillBackground:(struct CGRect)arg1 withAlternateColor:(BOOL)arg2;
- (void)drawWithFrame:(struct CGRect)arg1 inView:(id)arg2;
- (long long)_stateForDrawing;
- (BOOL)_isExitFullScreenButton;
- (struct CGRect)drawTitle:(id)arg1 withFrame:(struct CGRect)arg2 inView:(id)arg3;
- (long long)interiorBackgroundStyle;
- (BOOL)acceptsFirstResponder;
- (void)setDoubleAction:(SEL)arg1;
- (SEL)doubleAction;
- (void)setHighlightMode:(BOOL)arg1;
- (BOOL)highlightMode;
- (void)setStatusMenu:(id)arg1;
- (id)statusMenu;
- (id)statusBar;
- (void)setStatusBar:(id)arg1;
- (void)dealloc;
- (id)init;

@end

#endif /* NSStatusBarButtonCell_h */
