#ifndef WhichSpace_Bridging_Header_h
#define WhichSpace_Bridging_Header_h

#import <Foundation/Foundation.h>
#import <ApplicationServices/ApplicationServices.h>

#import "WindowSpaceMove.h"

// Private CoreDock API for triggering Mission Control
int CoreDockSendNotification(CFStringRef notification);

// Private CGS/SLS APIs for getting space information (no public alternative exists)
int _CGSDefaultConnection();
CFArrayRef CGSCopyManagedDisplaySpaces(int conn);
CFStringRef CGSCopyActiveMenuBarDisplayIdentifier(int conn);
CFArrayRef SLSCopySpacesForWindows(int conn, int selector, CFArrayRef windowIDs);

// Private AX API for resolving the CGWindowID behind an AX window element
// (no public alternative exists)
AXError _AXUIElementGetWindow(AXUIElementRef element, CGWindowID *windowID);

// Private SLS API for push notifications from the WindowServer. The proc is
// invoked on whichever thread receives the datagram, so implementations must
// hop to their own queue before touching shared state.
typedef void (*CGSConnectionNotifyProc)(uint32_t event, void *data, size_t dataLength, void *context, int cid);
CGError SLSRegisterConnectionNotifyProc(int cid, CGSConnectionNotifyProc proc, uint32_t event, void *context);

// Private CGS symbolic hotkey APIs for classic Space switching. The hotkey
// and modifier types are 32-bit in the private ABI; wider types only work
// by accident of zero-initialization on little-endian machines.
typedef int CGSSymbolicHotKey;
typedef unsigned int CGSModifierFlags;

CGError CGSGetSymbolicHotKeyValue(CGSSymbolicHotKey hotKey, UniChar *outCharCode, CGKeyCode *keyCode, CGSModifierFlags *flags);
Boolean CGSIsSymbolicHotKeyEnabled(CGSSymbolicHotKey hotKey);
CGError CGSSetSymbolicHotKeyEnabled(CGSSymbolicHotKey hotKey, Boolean enabled);

#endif
