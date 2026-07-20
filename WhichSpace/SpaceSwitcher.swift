import AppKit

// MARK: - Space Switching via Synthetic Dock-Swipe Gestures

/// Switches spaces instantly by posting synthetic trackpad dock-swipe gesture events.
///
/// This avoids the sliding animation and works for any number of spaces without
/// external dependencies. The technique simulates what macOS does when a fast
/// three-finger swipe is detected on the trackpad.
enum SpaceSwitcher {
    // MARK: - Private CGEvent Field Constants

    /// Undocumented CGEventField values used by the macOS gesture subsystem.
    private enum Field {
        static let eventType = CGEventField(rawValue: 55)!
        static let gestureHIDType = CGEventField(rawValue: 110)!
        static let gestureSwipeMotion = CGEventField(rawValue: 123)!
        static let gestureSwipeProgress = CGEventField(rawValue: 124)!
        static let gestureSwipeVelocityX = CGEventField(rawValue: 129)!
        static let gestureSwipeVelocityY = CGEventField(rawValue: 130)!
        static let gesturePhase = CGEventField(rawValue: 132)!
    }

    /// CGS event type constants.
    private enum EventType {
        static let dockControl: Int64 = 30
    }

    /// IOHIDEventType for dock swipe gestures.
    private static let hidTypeDockSwipe: Int64 = 23

    /// Gesture phase constants.
    private enum Phase {
        static let began: Int64 = 1
        static let changed: Int64 = 2
        static let ended: Int64 = 4
    }

    /// Horizontal motion constant.
    private static let horizontalMotion: Int64 = 1

    /// Base swipe velocity, scaled by step count so multi-Space jumps stay instant.
    private static let swipeVelocity = 2000.0

    /// Smallest non-zero progress still commits the switch but leaves the
    /// animation nothing to animate, making it instant.
    private static let swipeProgress = Double(Float.leastNonzeroMagnitude)

    private actor SharedState {
        private var hasPromptedForAccessibility = false

        func claimAccessibilityPrompt() -> Bool {
            guard !hasPromptedForAccessibility else {
                return false
            }
            hasPromptedForAccessibility = true
            return true
        }
    }

    private static let sharedState = SharedState()

    /// Predicted space index per display for switches whose CGS state hasn't
    /// caught up yet. During rapid successive switches CGS still reports the
    /// pre-switch space, which would make step counts wrong.
    @MainActor private static var predictedIndex: [String: Int] = [:]

    /// Clears switch predictions once a real space snapshot lands.
    @MainActor static func resetPredictions() {
        predictedIndex.removeAll()
    }

    // MARK: - Public API

    /// Switches to the space with the given CGS space ID on the menu bar display.
    /// Posts synthetic dock-swipe gestures to move from the current space to the target.
    @MainActor static func switchToSpace(id targetSpaceID: Int) {
        let conn = _CGSDefaultConnection()

        guard let activeDisplayRef = CGSCopyActiveMenuBarDisplayIdentifier(conn) else {
            NSLog("SpaceSwitcher: failed to get active menu bar display")
            return
        }
        let activeDisplayID = activeDisplayRef.takeRetainedValue() as String

        let displays = managedDisplays(connection: conn)
        guard let display = displays.first(where: { $0.identifier == activeDisplayID }) ?? displays.first else {
            NSLog("SpaceSwitcher: no display found")
            return
        }

        guard let cgsCurrentIndex = display.spaces.firstIndex(where: { $0.id == display.currentSpaceID }),
              let targetIndex = display.spaces.firstIndex(where: { $0.id == targetSpaceID })
        else {
            NSLog(
                "SpaceSwitcher: could not find current (%d) or target (%d) space",
                display.currentSpaceID,
                targetSpaceID
            )
            return
        }

        let currentIndex = predictedIndex[display.identifier] ?? cgsCurrentIndex

        guard currentIndex != targetIndex else {
            return
        }

        let steps = abs(targetIndex - currentIndex)
        let goRight = targetIndex > currentIndex
        let velocity = swipeVelocity * Double(steps)

        for _ in 0 ..< steps {
            guard postSwipeGesture(goRight: goRight, velocity: velocity) else {
                return
            }
        }

        predictedIndex[display.identifier] = targetIndex
    }

    /// Switches one Space left or right on the menu bar display, clamped at the
    /// edges unless `wrap` is true, in which case scrolling past either edge
    /// wraps around to the opposite end.
    /// Posts a single synthetic dock-swipe gesture, so fullscreen Spaces are
    /// traversed the same way a real three-finger swipe would.
    @MainActor static func switchRelative(goRight: Bool, wrap: Bool = false) {
        let conn = _CGSDefaultConnection()

        guard let activeDisplayRef = CGSCopyActiveMenuBarDisplayIdentifier(conn) else {
            NSLog("SpaceSwitcher: failed to get active menu bar display")
            return
        }
        let activeDisplayID = activeDisplayRef.takeRetainedValue() as String

        let displays = managedDisplays(connection: conn)
        guard let display = displays.first(where: { $0.identifier == activeDisplayID }) ?? displays.first else {
            NSLog("SpaceSwitcher: no display found")
            return
        }

        guard let cgsCurrentIndex = display.spaces.firstIndex(where: { $0.id == display.currentSpaceID }) else {
            NSLog("SpaceSwitcher: could not find current space (%d)", display.currentSpaceID)
            return
        }

        let currentIndex = predictedIndex[display.identifier] ?? cgsCurrentIndex
        let targetIndex = currentIndex + (goRight ? 1 : -1)
        guard display.spaces.indices.contains(targetIndex) else {
            if wrap {
                wrapAround(goRight: goRight, currentIndex: currentIndex, display: display)
            }
            return
        }

        guard postSwipeGesture(goRight: goRight, velocity: swipeVelocity) else {
            return
        }

        predictedIndex[display.identifier] = targetIndex
    }

    /// Jumps from one edge of the Space strip to the other by swiping back
    /// across every intermediate Space, mirroring how `switchToSpace(id:)`
    /// covers multi-Space distances.
    @MainActor private static func wrapAround(goRight: Bool, currentIndex: Int, display: ManagedDisplay) {
        let targetIndex = goRight ? 0 : display.spaces.count - 1
        let steps = abs(targetIndex - currentIndex)
        guard steps > 0 else {
            return
        }

        let velocity = swipeVelocity * Double(steps)
        for _ in 0 ..< steps {
            guard postSwipeGesture(goRight: !goRight, velocity: velocity) else {
                return
            }
        }

        predictedIndex[display.identifier] = targetIndex
    }

    // MARK: - CGS Dictionary Decoding

    /// Typed view of a single space returned by `CGSCopyManagedDisplaySpaces`.
    private struct ManagedSpace {
        let id: Int

        init?(dict: [String: Any]) {
            guard let id = dict["ManagedSpaceID"] as? Int else {
                return nil
            }
            self.id = id
        }
    }

    /// Typed view of a single display returned by `CGSCopyManagedDisplaySpaces`.
    private struct ManagedDisplay {
        let identifier: String
        let spaces: [ManagedSpace]
        let currentSpaceID: Int

        init?(dict: [String: Any]) {
            guard let identifier = dict["Display Identifier"] as? String,
                  let spacesRaw = dict["Spaces"] as? [[String: Any]],
                  let currentDict = dict["Current Space"] as? [String: Any],
                  let currentSpaceID = currentDict["ManagedSpaceID"] as? Int
            else {
                return nil
            }
            self.identifier = identifier
            spaces = spacesRaw.compactMap(ManagedSpace.init(dict:))
            self.currentSpaceID = currentSpaceID
        }
    }

    private static func managedDisplays(connection: Int32) -> [ManagedDisplay] {
        guard let rawRef = CGSCopyManagedDisplaySpaces(connection),
              let raw = rawRef.takeRetainedValue() as? [[String: Any]]
        else {
            NSLog("SpaceSwitcher: failed to get managed display spaces")
            return []
        }
        return raw.compactMap(ManagedDisplay.init(dict:))
    }

    // MARK: - Gesture Posting

    /// Posts a single synthetic dock-swipe gesture that moves one space left or right.
    /// All three phases (began, changed, ended) are required - with only two,
    /// switching does not work while Mission Control is open.
    private static func postSwipeGesture(goRight: Bool, velocity: Double) -> Bool {
        postDockSwipe(phase: Phase.began, goRight: goRight, velocity: velocity)
            && postDockSwipe(phase: Phase.changed, goRight: goRight, velocity: velocity)
            && postDockSwipe(phase: Phase.ended, goRight: goRight, velocity: velocity)
    }

    private static func postDockSwipe(phase: Int64, goRight: Bool, velocity: Double) -> Bool {
        guard let event = CGEvent(source: nil) else {
            return false
        }

        let progress = goRight ? swipeProgress : -swipeProgress
        let signedVelocity = goRight ? velocity : -velocity

        event.setIntegerValueField(Field.eventType, value: EventType.dockControl)
        event.setIntegerValueField(Field.gestureHIDType, value: hidTypeDockSwipe)
        event.setIntegerValueField(Field.gesturePhase, value: phase)
        event.setDoubleValueField(Field.gestureSwipeProgress, value: progress)
        event.setIntegerValueField(Field.gestureSwipeMotion, value: horizontalMotion)
        event.setDoubleValueField(Field.gestureSwipeVelocityX, value: signedVelocity)
        event.setDoubleValueField(Field.gestureSwipeVelocityY, value: signedVelocity)

        event.post(tap: .cgSessionEventTap)
        return true
    }

    // MARK: - Accessibility

    static func ensureAccessibilityPermission() async -> Bool {
        if AXIsProcessTrusted() {
            return true
        }

        // Request permission once so the user sees the System Settings prompt
        if await sharedState.claimAccessibilityPrompt() {
            _ = await Accessibility.resetAndPrompt()
        }

        return false
    }

    // MARK: - Fullscreen Space Switching

    /// Activates an app that has a window on the given space ID (used for fullscreen spaces).
    /// macOS will automatically switch to the fullscreen space when the app is activated.
    /// Returns true if an app was found and activated.
    static func activateAppOnSpace(_ spaceID: Int) -> Bool {
        let conn = _CGSDefaultConnection()

        // Get all windows
        let options: CGWindowListOption = [.optionAll, .excludeDesktopElements]
        guard let windowList = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
            NSLog("SpaceSwitcher: failed to get window list")
            return false
        }

        // Group regular windows (layer 0) by owning app so each app needs one batched space query
        var windowsByPID: [Int32: [Int]] = [:]
        var orderedPIDs: [Int32] = []
        for window in windowList {
            guard let layer = window[kCGWindowLayer as String] as? Int, layer == 0,
                  let windowNumber = window[kCGWindowNumber as String] as? Int,
                  let ownerPID = window[kCGWindowOwnerPID as String] as? Int32
            else {
                continue
            }
            if windowsByPID[ownerPID] == nil {
                orderedPIDs.append(ownerPID)
            }
            windowsByPID[ownerPID, default: []].append(windowNumber)
        }

        // Check each app's windows (front-to-back order) against the target space
        for pid in orderedPIDs {
            guard let windowNumbers = windowsByPID[pid],
                  let spacesRef = SLSCopySpacesForWindows(conn, 0x7, windowNumbers as CFArray)
            else {
                continue
            }
            let spaces = spacesRef.takeRetainedValue() as? [Int] ?? []

            if spaces.contains(spaceID) {
                // Found an app with a window on the target space - activate it
                if let app = NSRunningApplication(processIdentifier: pid) {
                    let activated = app.activate(options: [])
                    if activated {
                        NSLog("SpaceSwitcher: activated \(app.localizedName ?? "app") for fullscreen space \(spaceID)")
                        return true
                    }
                }
            }
        }

        NSLog("SpaceSwitcher: no app found on space \(spaceID)")
        return false
    }
}
