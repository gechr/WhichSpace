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
        static let gestureScrollY = CGEventField(rawValue: 119)!
        static let gestureSwipeMotion = CGEventField(rawValue: 123)!
        static let gestureSwipeProgress = CGEventField(rawValue: 124)!
        static let gestureSwipeVelocityX = CGEventField(rawValue: 129)!
        static let gestureSwipeVelocityY = CGEventField(rawValue: 130)!
        static let gesturePhase = CGEventField(rawValue: 132)!
        static let scrollGestureFlagBits = CGEventField(rawValue: 135)!
        static let gestureZoomDeltaX = CGEventField(rawValue: 139)!
    }

    /// CGS event type constants.
    private enum EventType {
        static let gesture: Int64 = 29
        static let dockControl: Int64 = 30
    }

    /// IOHIDEventType for dock swipe gestures.
    private static let hidTypeDockSwipe: Int64 = 23

    /// Gesture phase constants.
    private enum Phase {
        static let began: Int64 = 1
        static let ended: Int64 = 4
    }

    /// Horizontal motion constant.
    private static let horizontalMotion: Int64 = 1

    /// Swipe velocity - high enough for instant switching.
    private static let swipeVelocity = 400.0

    /// Swipe progress - distance value for a complete space switch.
    private static let swipeProgress = 2.0

    private static let accessibilityPromptOptionKey = "AXTrustedCheckOptionPrompt"

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

    // MARK: - Public API

    /// Switches to the space with the given CGS space ID on the menu bar display.
    /// Posts synthetic dock-swipe gestures to move from the current space to the target.
    static func switchToSpace(id targetSpaceID: Int) {
        let conn = _CGSDefaultConnection()

        guard let activeDisplayID = CGSCopyActiveMenuBarDisplayIdentifier(conn) as? String else {
            NSLog("SpaceSwitcher: failed to get active menu bar display")
            return
        }

        let displays = managedDisplays(connection: conn)
        guard let display = displays.first(where: { $0.identifier == activeDisplayID }) ?? displays.first else {
            NSLog("SpaceSwitcher: no display found")
            return
        }

        guard let currentIndex = display.spaces.firstIndex(where: { $0.id == display.currentSpaceID }),
              let targetIndex = display.spaces.firstIndex(where: { $0.id == targetSpaceID })
        else {
            NSLog(
                "SpaceSwitcher: could not find current (%d) or target (%d) space",
                display.currentSpaceID,
                targetSpaceID
            )
            return
        }

        guard currentIndex != targetIndex else {
            return
        }

        let steps = abs(targetIndex - currentIndex)
        let goRight = targetIndex > currentIndex

        for _ in 0 ..< steps {
            postSwipeGesture(goRight: goRight)
        }
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
            self.spaces = spacesRaw.compactMap(ManagedSpace.init(dict:))
            self.currentSpaceID = currentSpaceID
        }
    }

    private static func managedDisplays(connection: Int32) -> [ManagedDisplay] {
        guard let raw = CGSCopyManagedDisplaySpaces(connection) as? [[String: Any]] else {
            NSLog("SpaceSwitcher: failed to get managed display spaces")
            return []
        }
        return raw.compactMap(ManagedDisplay.init(dict:))
    }

    // MARK: - Gesture Posting

    /// Posts a single synthetic dock-swipe gesture that moves one space left or right.
    private static func postSwipeGesture(goRight: Bool) {
        let flagDirection: Int64 = goRight ? 1 : 0
        let progress = goRight ? swipeProgress : -swipeProgress
        let velocity = goRight ? swipeVelocity : -swipeVelocity

        // Begin gesture
        guard let gestureA = CGEvent(source: nil),
              let controlA = CGEvent(source: nil)
        else { return }

        gestureA.setIntegerValueField(Field.eventType, value: EventType.gesture)

        controlA.setIntegerValueField(Field.eventType, value: EventType.dockControl)
        controlA.setIntegerValueField(Field.gestureHIDType, value: hidTypeDockSwipe)
        controlA.setIntegerValueField(Field.gesturePhase, value: Phase.began)
        controlA.setIntegerValueField(Field.scrollGestureFlagBits, value: flagDirection)
        controlA.setIntegerValueField(Field.gestureSwipeMotion, value: horizontalMotion)
        controlA.setDoubleValueField(Field.gestureScrollY, value: 0)
        controlA.setDoubleValueField(Field.gestureZoomDeltaX, value: Double(Float.leastNonzeroMagnitude))

        controlA.post(tap: .cgSessionEventTap)
        gestureA.post(tap: .cgSessionEventTap)

        // End gesture
        guard let gestureB = CGEvent(source: nil),
              let controlB = CGEvent(source: nil)
        else { return }

        gestureB.setIntegerValueField(Field.eventType, value: EventType.gesture)

        controlB.setIntegerValueField(Field.eventType, value: EventType.dockControl)
        controlB.setIntegerValueField(Field.gestureHIDType, value: hidTypeDockSwipe)
        controlB.setIntegerValueField(Field.gesturePhase, value: Phase.ended)
        controlB.setDoubleValueField(Field.gestureSwipeProgress, value: progress)
        controlB.setIntegerValueField(Field.scrollGestureFlagBits, value: flagDirection)
        controlB.setIntegerValueField(Field.gestureSwipeMotion, value: horizontalMotion)
        controlB.setDoubleValueField(Field.gestureScrollY, value: 0)
        controlB.setDoubleValueField(Field.gestureSwipeVelocityX, value: velocity)
        controlB.setDoubleValueField(Field.gestureSwipeVelocityY, value: 0)
        controlB.setDoubleValueField(Field.gestureZoomDeltaX, value: Double(Float.leastNonzeroMagnitude))

        controlB.post(tap: .cgSessionEventTap)
        gestureB.post(tap: .cgSessionEventTap)
    }

    // MARK: - Accessibility

    /// Resets WhichSpace Accessibility permission to clear stale TCC entries.
    static func resetAccessibilityPermission() {
        let tccutil = "/usr/bin/tccutil"
        guard FileManager.default.fileExists(atPath: tccutil),
              let bundleID = Bundle.main.bundleIdentifier
        else {
            return
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: tccutil)
        process.arguments = ["reset", "Accessibility", bundleID]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            NSLog("SpaceSwitcher: failed to reset accessibility permission: \(error)")
        }
    }

    static func ensureAccessibilityPermission() async -> Bool {
        if AXIsProcessTrusted() {
            return true
        }

        // Request permission once so the user sees the System Settings prompt
        if await sharedState.claimAccessibilityPrompt() {
            resetAccessibilityPermission()
            let options = [accessibilityPromptOptionKey: true] as CFDictionary
            _ = AXIsProcessTrustedWithOptions(options)
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

        // Find windows on the target space
        for window in windowList {
            // Filter to regular windows (layer 0)
            guard let layer = window[kCGWindowLayer as String] as? Int, layer == 0,
                  let windowNumber = window[kCGWindowNumber as String] as? Int,
                  let ownerPID = window[kCGWindowOwnerPID as String] as? Int32
            else {
                continue
            }

            // Check if this window is on the target space
            guard let spacesRef = SLSCopySpacesForWindows(conn, 0x7, [windowNumber] as CFArray) else {
                continue
            }
            let spaces = spacesRef.takeRetainedValue() as? [Int] ?? []

            if spaces.contains(spaceID) {
                // Found a window on the target space - activate its app
                if let app = NSRunningApplication(processIdentifier: ownerPID) {
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
