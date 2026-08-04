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

    /// CGS symbolic hotkey IDs used for classic switching.
    private enum HotKey {
        /// "Switch to Desktop 1"; Desktops 2-16 follow consecutively.
        static let firstDesktop: CGSSymbolicHotKey = 118
        /// Desktops beyond this have no "Switch to Desktop N" hotkey.
        static let maxDesktops = 16
        /// "Move left a space" (Ctrl+Left by default).
        static let moveLeft: CGSSymbolicHotKey = 79
        /// "Move right a space" (Ctrl+Right by default).
        static let moveRight: CGSSymbolicHotKey = 81
    }

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
    @discardableResult
    @MainActor static func switchToSpace(id targetSpaceID: Int) -> Bool {
        let conn = _CGSDefaultConnection()

        guard let activeDisplayRef = CGSCopyActiveMenuBarDisplayIdentifier(conn) else {
            NSLog("SpaceSwitcher: failed to get active menu bar display")
            return false
        }
        let activeDisplayID = activeDisplayRef.takeRetainedValue() as String

        let displays = managedDisplays(connection: conn)
        guard let display = displays.first(where: { $0.identifier == activeDisplayID }) ?? displays.first else {
            NSLog("SpaceSwitcher: no display found")
            return false
        }

        guard let cgsCurrentIndex = display.spaces.firstIndex(where: { $0.id == display.currentSpaceID }),
              let targetIndex = display.spaces.firstIndex(where: { $0.id == targetSpaceID })
        else {
            NSLog(
                "SpaceSwitcher: could not find current (%d) or target (%d) space",
                display.currentSpaceID,
                targetSpaceID
            )
            return false
        }

        let currentIndex = predictedIndex[display.identifier] ?? cgsCurrentIndex

        guard currentIndex != targetIndex else {
            return true
        }

        let steps = abs(targetIndex - currentIndex)
        let goRight = targetIndex > currentIndex

        if usesClassicSwitching {
            guard classicSwitch(toSpaceID: targetSpaceID, goRight: goRight, steps: steps, connection: conn) else {
                return false
            }
        } else {
            let velocity = swipeVelocity * Double(steps)
            for _ in 0 ..< steps {
                guard postSwipeGesture(goRight: goRight, velocity: velocity) else {
                    return false
                }
            }
        }

        predictedIndex[display.identifier] = targetIndex
        return true
    }

    /// Switches to a globally numbered regular Desktop. A target on the
    /// active display keeps the configured instant/classic behavior; a target
    /// on another display uses macOS's numbered Mission Control shortcut,
    /// which addresses Desktops globally rather than relative to focus.
    @discardableResult
    @MainActor static func switchToDesktop(number: Int) -> Bool {
        let conn = _CGSDefaultConnection()
        guard let activeDisplayRef = CGSCopyActiveMenuBarDisplayIdentifier(conn) else {
            NSLog("SpaceSwitcher: failed to get active menu bar display")
            return false
        }
        let activeDisplayID = activeDisplayRef.takeRetainedValue() as String

        let displays = managedDisplays(connection: conn)
        guard let activeDisplay = displays.first(
            where: { $0.identifier == activeDisplayID }
        ) ?? displays.first else {
            NSLog("SpaceSwitcher: no display found")
            return false
        }
        guard let route = desktopSwitchRoute(
            number: number,
            activeDisplayID: activeDisplay.identifier,
            displays: displays
        ) else {
            return false
        }

        switch route {
        case let .activeDisplay(spaceID):
            return switchToSpace(id: spaceID)
        case let .otherDisplay(hotKey):
            return postHotKey(hotKey)
        }
    }

    /// Switches one Space left or right on the menu bar display, clamped at the
    /// edges unless `wrap` is true, in which case scrolling past either edge
    /// wraps around to the opposite end.
    /// Posts a single synthetic dock-swipe gesture, so fullscreen Spaces are
    /// traversed the same way a real three-finger swipe would.
    /// Returns whether a switch was actually performed, so callers can skip
    /// feedback (e.g. haptics) when the gesture was a no-op.
    @discardableResult
    @MainActor static func switchRelative(goRight: Bool, wrap: Bool = false) -> Bool {
        let conn = _CGSDefaultConnection()

        guard let activeDisplayRef = CGSCopyActiveMenuBarDisplayIdentifier(conn) else {
            NSLog("SpaceSwitcher: failed to get active menu bar display")
            return false
        }
        let activeDisplayID = activeDisplayRef.takeRetainedValue() as String

        let displays = managedDisplays(connection: conn)
        guard let display = displays.first(where: { $0.identifier == activeDisplayID }) ?? displays.first else {
            NSLog("SpaceSwitcher: no display found")
            return false
        }

        guard let cgsCurrentIndex = display.spaces.firstIndex(where: { $0.id == display.currentSpaceID }) else {
            NSLog("SpaceSwitcher: could not find current space (%d)", display.currentSpaceID)
            return false
        }

        let currentIndex = predictedIndex[display.identifier] ?? cgsCurrentIndex
        let targetIndex = currentIndex + (goRight ? 1 : -1)
        guard display.spaces.indices.contains(targetIndex) else {
            if wrap {
                return wrapAround(goRight: goRight, currentIndex: currentIndex, display: display)
            }
            return false
        }

        guard postStep(goRight: goRight, velocity: swipeVelocity) else {
            return false
        }

        predictedIndex[display.identifier] = targetIndex
        return true
    }

    /// Jumps from one edge of the Space strip to the other by swiping back
    /// across every intermediate Space, mirroring how `switchToSpace(id:)`
    /// covers multi-Space distances.
    @MainActor private static func wrapAround(goRight: Bool, currentIndex: Int, display: ManagedDisplay) -> Bool {
        let targetIndex = goRight ? 0 : display.spaces.count - 1
        let steps = abs(targetIndex - currentIndex)
        guard steps > 0 else {
            return false
        }

        if usesClassicSwitching {
            let target = display.spaces[targetIndex].id
            guard classicSwitch(toSpaceID: target, goRight: !goRight, steps: steps, connection: _CGSDefaultConnection())
            else {
                return false
            }
        } else {
            let velocity = swipeVelocity * Double(steps)
            for _ in 0 ..< steps {
                guard postSwipeGesture(goRight: !goRight, velocity: velocity) else {
                    return false
                }
            }
        }

        predictedIndex[display.identifier] = targetIndex
        return true
    }

    // MARK: - CGS Dictionary Decoding

    /// Typed view of a single space returned by `CGSCopyManagedDisplaySpaces`.
    struct ManagedSpace {
        let id: Int
        let isFullscreen: Bool

        init?(dict: [String: Any]) {
            guard let id = dict["ManagedSpaceID"] as? Int else {
                return nil
            }
            self.id = id
            isFullscreen = dict["TileLayoutManager"] is [String: Any]
        }
    }

    /// Typed view of a single display returned by `CGSCopyManagedDisplaySpaces`.
    struct ManagedDisplay {
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

    /// A pure routing decision kept separate from event posting so
    /// multi-display numbering can be covered without changing the test
    /// runner's active Space.
    enum DesktopSwitchRoute: Equatable {
        case activeDisplay(spaceID: Int)
        case otherDisplay(hotKey: CGSSymbolicHotKey)
    }

    static func desktopSwitchRoute(
        number: Int,
        activeDisplayID: String,
        displays: [ManagedDisplay]
    ) -> DesktopSwitchRoute? {
        guard number >= 1, number <= HotKey.maxDesktops else {
            return nil
        }

        var desktopNumber = 0
        for display in displays {
            for space in display.spaces where !space.isFullscreen {
                desktopNumber += 1
                guard desktopNumber == number else {
                    continue
                }
                if display.identifier == activeDisplayID {
                    return .activeDisplay(spaceID: space.id)
                }
                return .otherDisplay(
                    hotKey: HotKey.firstDesktop + CGSSymbolicHotKey(number - 1)
                )
            }
        }
        return nil
    }

    // MARK: - Classic Switching

    /// Whether the user prefers classic hotkey switching over instant gestures.
    /// Classic switching simulates the Mission Control keyboard shortcuts, so
    /// it keeps the slide animation and works while a mouse button is held
    /// down, which swallows synthetic swipe gestures.
    @MainActor private static var usesClassicSwitching: Bool {
        AppEnvironment.shared.store.classicSpaceSwitching
    }

    /// Posts one switch step left or right using the active mechanism.
    @MainActor private static func postStep(goRight: Bool, velocity: Double) -> Bool {
        if usesClassicSwitching {
            return postHotKey(goRight ? HotKey.moveRight : HotKey.moveLeft)
        }
        return postSwipeGesture(goRight: goRight, velocity: velocity)
    }

    /// Switches via the "Switch to Desktop N" shortcut when the target has
    /// one, stepping with the arrow shortcuts otherwise (fullscreen Spaces
    /// and Desktops beyond 16 have no numbered shortcut).
    private static func classicSwitch(
        toSpaceID targetSpaceID: Int,
        goRight: Bool,
        steps: Int,
        connection: Int32
    ) -> Bool {
        if let number = desktopNumber(forSpaceID: targetSpaceID, connection: connection),
           number <= HotKey.maxDesktops
        {
            return postHotKey(HotKey.firstDesktop + CGSSymbolicHotKey(number - 1))
        }
        for _ in 0 ..< steps {
            guard postHotKey(goRight ? HotKey.moveRight : HotKey.moveLeft) else {
                return false
            }
        }
        return true
    }

    /// The 1-based Mission Control Desktop number for a space ID, counting
    /// regular Spaces across every display, or nil for fullscreen Spaces.
    private static func desktopNumber(forSpaceID spaceID: Int, connection: Int32) -> Int? {
        var number = 0
        for display in managedDisplays(connection: connection) {
            for space in display.spaces {
                if space.isFullscreen {
                    if space.id == spaceID {
                        return nil
                    }
                    continue
                }
                number += 1
                if space.id == spaceID {
                    return number
                }
            }
        }
        return nil
    }

    /// Posts the key event pair for a symbolic hotkey, enabling the hotkey
    /// first if the user has it switched off in System Settings.
    private static func postHotKey(_ hotKey: CGSSymbolicHotKey) -> Bool {
        var keyCode: CGKeyCode = 0
        var flags: CGSModifierFlags = 0
        guard CGSGetSymbolicHotKeyValue(hotKey, nil, &keyCode, &flags) == .success else {
            NSLog("SpaceSwitcher: failed to get hot key value for %d", Int(hotKey))
            return false
        }

        if !CGSIsSymbolicHotKeyEnabled(hotKey) {
            guard CGSSetSymbolicHotKeyEnabled(hotKey, true) == .success else {
                NSLog("SpaceSwitcher: failed to enable hot key %d", Int(hotKey))
                return false
            }
        }

        guard let keyDown = CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: false)
        else {
            NSLog("SpaceSwitcher: failed to create key events for hot key %d", Int(hotKey))
            return false
        }

        keyDown.flags = CGEventFlags(rawValue: UInt64(flags))
        keyDown.post(tap: .cghidEventTap)
        keyUp.flags = []
        keyUp.post(tap: .cghidEventTap)
        return true
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
