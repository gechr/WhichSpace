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
#import <ApplicationServices/ApplicationServices.h>

// Private CoreDock API for triggering Mission Control
int CoreDockSendNotification(CFStringRef notification);

// Private CGS/SLS APIs for getting space information (no public alternative exists)
int _CGSDefaultConnection();
CFArrayRef CGSCopyManagedDisplaySpaces(int conn);
CFStringRef CGSCopyActiveMenuBarDisplayIdentifier(int conn);
CFArrayRef SLSCopySpacesForWindows(int conn, int selector, CFArrayRef windowIDs);

// Private SLS API for push notifications from the WindowServer. The proc is
// invoked on whichever thread receives the datagram, so implementations must
// hop to their own queue before touching shared state.
typedef void (*CGSConnectionNotifyProc)(uint32_t event, void *data, size_t dataLength, void *context, int cid);
CGError SLSRegisterConnectionNotifyProc(int cid, CGSConnectionNotifyProc proc, uint32_t event, void *context);

#endif
