//
//  WhichSpace-Bridging-Header.h
//  WhichSpace
//
//  Created by George on 29/10/2015.
//  Copyright © 2020 George Christou. All rights reserved.
//

#ifndef WhichSpace_Bridging_Header_h
#define WhichSpace_Bridging_Header_h

#import <Foundation/Foundation.h>

#import "PFMoveApplication.h"

// Private CGS/SLS APIs for getting space information (no public alternative exists)
int _CGSDefaultConnection();
id CGSCopyManagedDisplaySpaces(int conn);
id CGSCopyActiveMenuBarDisplayIdentifier(int conn);
CFArrayRef SLSCopySpacesForWindows(int conn, int selector, CFArrayRef windowIDs);

#endif
