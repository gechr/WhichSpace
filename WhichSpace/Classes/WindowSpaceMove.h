//
//  WindowSpaceMove.h
//  WhichSpace
//

#ifndef WindowSpaceMove_h
#define WindowSpaceMove_h

#include <stdbool.h>
#include <stdint.h>

// Private window-move backends, in the order macOS has supported them.
//
// Every symbol is resolved lazily at first use and never at link time, so a
// symbol Apple removes disables this feature instead of preventing launch.
// Availability means the entry points resolved, not that the move will take
// effect: callers must confirm the result with SLSCopySpacesForWindows.

bool WSMoveBridgedIsAvailable(void);
bool WSMoveManagedSpaceIsAvailable(void);
bool WSMoveCompatIDIsAvailable(void);

// Each function reports whether the request was issued, not whether the window
// moved. The bridged operation is asynchronous and the others return void.

bool WSMoveBridged(uint32_t windowID, uint64_t spaceID);
bool WSMoveManagedSpace(int cid, uint32_t windowID, uint64_t spaceID);
bool WSMoveCompatID(int cid, uint32_t windowID, uint64_t spaceID);

#endif
