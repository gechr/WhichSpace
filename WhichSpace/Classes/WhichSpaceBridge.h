//
//  WhichSpaceBridge.h
//  WhichSpace
//
//  Created by George on 29/10/2015.
//  Copyright © 2020 George Christou. All rights reserved.
//

#ifndef WhichSpaceBridge_h
#define WhichSpaceBridge_h

#import <Foundation/Foundation.h>

#import "NSStatusBarButtonCell.h"
#import "PFMoveApplication.h"

int _CGSDefaultConnection();
id CGSCopyManagedDisplaySpaces(int conn);
id CGSCopyActiveMenuBarDisplayIdentifier(int conn);
id CGSCast(int conn);
#endif
