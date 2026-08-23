import AppKit
import Darwin

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
        static let gestureSwipeMask = CGEventField(rawValue: 115)!
        static let gestureSwipeMotion = CGEventField(rawValue: 123)!
        static let gestureSwipeProgress = CGEventField(rawValue: 124)!
        static let gestureSwipePositionX = CGEventField(rawValue: 125)!
        static let gestureSwipePositionY = CGEventField(rawValue: 126)!
        static let gestureSwipeVelocityX = CGEventField(rawValue: 129)!
        static let gestureSwipeVelocityY = CGEventField(rawValue: 130)!
        static let gesturePhase = CGEventField(rawValue: 132)!
        static let gesturePhase2 = CGEventField(rawValue: 134)!
        static let gestureFlavor = CGEventField(rawValue: 138)!
        static let eventTimestamp = CGEventField(rawValue: 169)!
        static let iohidPayload: UInt16 = 4205
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
    @MainActor private static var predictions: [String: (index: Int, madeAt: Date)] = [:]

    /// How long a prediction stays trusted. Rapid successive switches land
    /// within milliseconds, so an older prediction that CGS still contradicts
    /// means the posted events never took effect and trusting it would route
    /// later switches from a space the user never reached.
    private static let predictionLifetime: TimeInterval = 1

    /// The trusted predicted index for a display, or nil once expired.
    @MainActor private static func prediction(for display: String) -> Int? {
        guard let prediction = predictions[display],
              Date().timeIntervalSince(prediction.madeAt) < predictionLifetime
        else {
            return nil
        }
        return prediction.index
    }

    @MainActor private static func recordPrediction(_ index: Int, for display: String) {
        predictions[display] = (index, Date())
    }

    /// Clears switch predictions once a real space snapshot lands.
    @MainActor static func resetPredictions() {
        predictions.removeAll()
        restoreParkedWindowIfReady()
    }

    // MARK: - Public API

    /// Switches to the space with the given CGS space ID on the menu bar display.
    /// Posts synthetic dock-swipe gestures to move from the current space to the target.
    @discardableResult
    @MainActor static func switchToSpace(id targetSpaceID: Int, fromStatusItemClick: Bool = false) -> Bool {
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

        let currentIndex = prediction(for: display.identifier) ?? cgsCurrentIndex

        guard currentIndex != targetIndex else {
            return true
        }

        let steps = abs(targetIndex - currentIndex)
        let goRight = targetIndex > currentIndex

        if requiresClassicPath(fromStatusItemClick: fromStatusItemClick) {
            guard classicSwitch(toSpaceID: targetSpaceID, goRight: goRight, steps: steps, connection: conn) else {
                return false
            }
        } else {
            parkKeyWindowIfNeeded(
                currentSpaceID: display.currentSpaceID,
                targetSpaceID: targetSpaceID
            )
            let velocity = swipeVelocity * Double(steps)
            for _ in 0 ..< steps {
                guard postSwipeGesture(goRight: goRight, velocity: velocity) else {
                    return false
                }
            }
        }

        recordPrediction(targetIndex, for: display.identifier)
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
            displays: presentationOrdered(displays),
            cgsDisplays: displays
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
    /// wraps around to the opposite end. Spaces whose IDs appear in
    /// `skippingSpaceIDs` are jumped over, landing on the nearest remaining
    /// Space in the direction of travel.
    /// Returns whether a switch was actually performed, so callers can skip
    /// feedback (e.g. haptics) when the gesture was a no-op.
    @discardableResult
    @MainActor static func switchRelative(
        goRight: Bool,
        wrap: Bool = false,
        skippingSpaceIDs: Set<Int> = []
    ) -> Bool {
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

        let currentIndex = prediction(for: display.identifier) ?? cgsCurrentIndex
        guard let targetIndex = relativeTargetIndex(
            from: currentIndex,
            goRight: goRight,
            wrap: wrap,
            spaceIDs: display.spaces.map(\.id),
            skipping: skippingSpaceIDs
        ) else {
            return false
        }

        // A wrap reaches its target by stepping back across the intermediate
        // Spaces, so the posted direction follows the index delta rather than
        // the requested one.
        let steps = abs(targetIndex - currentIndex)
        let stepsRight = targetIndex > currentIndex
        let target = display.spaces[targetIndex].id
        // The single-step route decides classic vs gesture inside postStep
        // with the same predicate, so this mirrors the route actually taken
        let classicRoute = requiresClassicPath()
        if !classicRoute {
            parkKeyWindowIfNeeded(
                currentSpaceID: display.currentSpaceID,
                targetSpaceID: target
            )
        }
        if steps == 1 {
            guard postStep(goRight: stepsRight, velocity: swipeVelocity) else {
                return false
            }
        } else if classicRoute {
            guard classicSwitch(toSpaceID: target, goRight: stepsRight, steps: steps, connection: conn) else {
                return false
            }
        } else {
            let velocity = swipeVelocity * Double(steps)
            for _ in 0 ..< steps {
                guard postSwipeGesture(goRight: stepsRight, velocity: velocity) else {
                    return false
                }
            }
        }

        recordPrediction(targetIndex, for: display.identifier)
        return true
    }

    /// The index a relative switch lands on: the nearest index in the
    /// direction of travel whose Space ID is not skipped. When the scan runs
    /// off the edge and `wrap` is true, it resumes from the opposite end and
    /// stops before reaching the current index again. Nil when no Space
    /// qualifies. A pure routing decision kept separate from event posting so
    /// skip and wrap behavior can be covered without changing the test
    /// runner's active Space.
    static func relativeTargetIndex(
        from currentIndex: Int,
        goRight: Bool,
        wrap: Bool,
        spaceIDs: [Int],
        skipping: Set<Int> = []
    ) -> Int? {
        let direction = goRight ? 1 : -1
        var index = currentIndex + direction
        while spaceIDs.indices.contains(index) {
            if !skipping.contains(spaceIDs[index]) {
                return index
            }
            index += direction
        }
        guard wrap else {
            return nil
        }
        index = goRight ? 0 : spaceIDs.count - 1
        while spaceIDs.indices.contains(index), index != currentIndex {
            if !skipping.contains(spaceIDs[index]) {
                return index
            }
            index += direction
        }
        return nil
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

    /// The displays in the order the menu bar numbers their Desktops. A
    /// physical presentation reorder only affects numbering when the menu bar
    /// shows every display and the user has not chosen to preserve the
    /// numbers assigned by macOS, matching the snapshot's gating.
    @MainActor private static func presentationOrdered(_ displays: [ManagedDisplay]) -> [ManagedDisplay] {
        let store = AppEnvironment.shared.store
        guard store.showAllDisplays, store.displayOrder == .physical, !store.preserveSystemSpaceNumbers else {
            return displays
        }
        return DisplayArrangement.sorted(
            displays,
            identifier: \.identifier,
            bounds: DisplayGeometry.bounds(forDisplayIdentifier:)
        )
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

    /// `displays` is in the order the menu bar numbers Desktops, which the
    /// display order preference can reorder. `cgsDisplays` stays in raw CGS
    /// order for the cross-display route, whose symbolic hotkey addresses
    /// macOS's own numbering; empty means the two orders are the same.
    static func desktopSwitchRoute(
        number: Int,
        activeDisplayID: String,
        displays: [ManagedDisplay],
        cgsDisplays: [ManagedDisplay] = []
    ) -> DesktopSwitchRoute? {
        guard number >= 1, number <= HotKey.maxDesktops else {
            return nil
        }

        var counted = 0
        for display in displays {
            for space in display.spaces where !space.isFullscreen {
                counted += 1
                guard counted == number else {
                    continue
                }
                if display.identifier == activeDisplayID {
                    return .activeDisplay(spaceID: space.id)
                }
                // A reordered number can point at a Desktop macOS numbers
                // beyond its last numbered shortcut, which has no route
                guard let cgsNumber = desktopNumber(
                    forSpaceID: space.id,
                    displays: cgsDisplays.isEmpty ? displays : cgsDisplays
                ), cgsNumber <= HotKey.maxDesktops else {
                    return nil
                }
                return .otherDisplay(
                    hotKey: HotKey.firstDesktop + CGSSymbolicHotKey(cgsNumber - 1)
                )
            }
        }
        return nil
    }

    // MARK: - Classic Switching

    /// Whether the user prefers classic hotkey switching over instant gestures.
    /// Classic switching simulates the Mission Control keyboard shortcuts, so
    /// it keeps the slide animation.
    @MainActor private static var usesClassicSwitching: Bool {
        AppEnvironment.shared.store.classicSpaceSwitching
    }

    /// macOS 27 validates synthetic dock swipes against an IOHID payload.
    /// Earlier releases must keep posting the original plain events.
    private nonisolated static let requiresIOHIDPayload =
        ProcessInfo.processInfo.operatingSystemVersion.majorVersion >= 27

    /// The extra system gesture requirement is part of the macOS 27 event
    /// path only. Older releases retain their established switching behavior.
    nonisolated static var requiresSpaceSwipeGestureSetting: Bool {
        requiresIOHIDPayload
    }

    /// Whether macOS has either horizontal three- or four-finger Space swipe
    /// configured for a built-in/Bluetooth trackpad. Direct defaults writes
    /// are insufficient because they do not update Dock's live HID state.
    static var spaceSwipeGestureSettingEnabled: Bool {
        guard requiresSpaceSwipeGestureSetting else {
            return true
        }

        let domains = [
            "com.apple.AppleMultitouchTrackpad",
            "com.apple.driver.AppleBluetoothMultitouch.trackpad",
        ]
        let deviceKeys = [
            "TrackpadThreeFingerHorizSwipeGesture",
            "TrackpadFourFingerHorizSwipeGesture",
        ]
        var values: [Int?] = domains.flatMap { domain in
            deviceKeys.map { key in
                preferenceInt(key: key, applicationID: domain as CFString, host: kCFPreferencesAnyHost)
            }
        }
        values.append(preferenceInt(
            key: "com.apple.trackpad.threeFingerHorizSwipeGesture",
            applicationID: kCFPreferencesAnyApplication,
            host: kCFPreferencesCurrentHost
        ))
        values.append(preferenceInt(
            key: "com.apple.trackpad.fourFingerHorizSwipeGesture",
            applicationID: kCFPreferencesAnyApplication,
            host: kCFPreferencesCurrentHost
        ))
        return hasEnabledSpaceSwipeGesture(values)
    }

    static func hasEnabledSpaceSwipeGesture(_ values: [Int?]) -> Bool {
        values.contains { ($0 ?? 0) != 0 }
    }

    /// Uses the same private preference backend as Trackpad settings to make
    /// the macOS 27 gesture recognizer live immediately. A direct defaults
    /// write changes the plist but does not update Dock or the HID service.
    @MainActor static func enableSpaceSwipeGestureSetting() -> Bool {
        guard requiresSpaceSwipeGestureSetting else {
            return true
        }

        let path = "/System/Library/PrivateFrameworks/PreferencePanesSupport.framework/PreferencePanesSupport"
        guard dlopen(path, RTLD_NOW | RTLD_LOCAL) != nil,
              let backendClass = NSClassFromString("MTTGestureBackEnd") as? NSObject.Type
        else {
            return false
        }

        let sharedSelector = NSSelectorFromString("sharedInstance")
        guard backendClass.responds(to: sharedSelector),
              let backend = backendClass.perform(sharedSelector)?.takeUnretainedValue() as? NSObject
        else {
            return false
        }

        let cloudSelector = NSSelectorFromString("setShouldSyncChangesToCloud:")
        if backend.responds(to: cloudSelector) {
            typealias BoolSetter = @convention(c) (AnyObject, Selector, Bool) -> Void
            let setter = unsafeBitCast(backend.method(for: cloudSelector), to: BoolSetter.self)
            setter(backend, cloudSelector, false)
        }

        let swipeSelector = NSSelectorFromString("setFourFingerHorizSwipe:")
        guard backend.responds(to: swipeSelector) else {
            return false
        }
        typealias IntegerSetter = @convention(c) (AnyObject, Selector, Int) -> Void
        let setter = unsafeBitCast(backend.method(for: swipeSelector), to: IntegerSetter.self)
        setter(backend, swipeSelector, 2)
        return spaceSwipeGestureSettingEnabled
    }

    private static func preferenceInt(key: String, applicationID: CFString, host: CFString) -> Int? {
        let value = CFPreferencesCopyValue(
            key as CFString,
            applicationID,
            kCFPreferencesCurrentUser,
            host
        )
        return (value as? NSNumber)?.intValue
    }

    /// Whether the next switch must take the classic hotkey route. A held
    /// mouse button means the WindowServer is tracking a drag, which swallows
    /// synthetic swipe gestures without any failure signal, so instant
    /// switching falls back to the Mission Control shortcuts until the
    /// button is released. Key events still get delivered during a drag,
    /// and the switch carries the held window to the target Space.
    @MainActor private static func requiresClassicPath(fromStatusItemClick: Bool = false) -> Bool {
        let heldButtonIsDrag = heldButtonRequiresClassicPath(
            buttonIsPressed: NSEvent.pressedMouseButtons != 0,
            fromStatusItemClick: fromStatusItemClick,
            requiresIOHIDPayload: requiresIOHIDPayload
        )
        return usesClassicSwitching || heldButtonIsDrag
    }

    /// On macOS 27 the status item's mouse-up action can run before AppKit's
    /// global pressed-button state clears. Earlier releases retain the exact
    /// historical behavior, and every non-status-item switch still treats a
    /// held button as a window drag.
    static func heldButtonRequiresClassicPath(
        buttonIsPressed: Bool,
        fromStatusItemClick: Bool,
        requiresIOHIDPayload: Bool
    ) -> Bool {
        buttonIsPressed && !(requiresIOHIDPayload && fromStatusItemClick)
    }

    /// Posts one switch step left or right using the active mechanism.
    @MainActor private static func postStep(goRight: Bool, velocity: Double) -> Bool {
        if requiresClassicPath() {
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
        // On macOS 27 the numbered shortcut's posted key events do not switch
        // the active display, so every target is reached by stepping instead.
        if !requiresIOHIDPayload,
           let number = desktopNumber(forSpaceID: targetSpaceID, connection: connection),
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

    private static func desktopNumber(forSpaceID spaceID: Int, connection: Int32) -> Int? {
        desktopNumber(forSpaceID: spaceID, displays: managedDisplays(connection: connection))
    }

    /// The 1-based Mission Control Desktop number for a space ID, counting
    /// regular Spaces across every display, or nil for fullscreen Spaces.
    /// Callers pass displays in raw CGS order: this number addresses macOS's
    /// own numbering rather than the menu bar's.
    static func desktopNumber(forSpaceID spaceID: Int, displays: [ManagedDisplay]) -> Int? {
        var number = 0
        for display in displays {
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
        guard requiresIOHIDPayload else {
            return postDockSwipe(phase: Phase.began, goRight: goRight, velocity: velocity)
                && postDockSwipe(phase: Phase.changed, goRight: goRight, velocity: velocity)
                && postDockSwipe(phase: Phase.ended, goRight: goRight, velocity: velocity)
        }
        return postAugmentedDockSwipe(phase: Phase.began, goRight: goRight, velocity: velocity)
            && postAugmentedDockSwipe(phase: Phase.changed, goRight: goRight, velocity: velocity)
            && postAugmentedDockSwipe(phase: Phase.ended, goRight: goRight, velocity: velocity)
    }

    // MARK: - Window Parking

    /// The foreground window remembered when a synthetic switch leaves its
    /// Space, and whether it has been ordered out for a return switch.
    @MainActor private static var trackedWindow: (window: NSWindow, spaceID: Int, parked: Bool)?

    /// macOS 27 strands the menu bar when a synthetic switch arrives on a
    /// Space whose frontmost window belongs to this accessory app. Removing
    /// that window from the ordering before the switch prevents the bad
    /// WindowServer state; lowering or deactivating it does not.
    @MainActor private static func parkKeyWindowIfNeeded(
        currentSpaceID: Int,
        targetSpaceID: Int
    ) {
        guard requiresIOHIDPayload, trackedWindow?.parked != true else {
            return
        }
        if NSApp.isActive, let window = NSApp.keyWindow, window.isVisible {
            trackedWindow = (window, currentSpaceID, false)
        } else if trackedWindow?.spaceID == currentSpaceID {
            // Another app replaced WhichSpace before this Space was left, so
            // the remembered window is no longer the arrival front window.
            trackedWindow = nil
        }
        guard let tracked = trackedWindow,
              tracked.spaceID == targetSpaceID,
              tracked.window.isVisible
        else {
            return
        }
        tracked.window.orderOut(nil)
        trackedWindow = (tracked.window, tracked.spaceID, true)
    }

    /// Restores only after AppState has applied a real snapshot for the
    /// window's owning Space. Later switches cannot cancel this ownership,
    /// and a failed event post safely leaves an already off-Space window
    /// parked until that Space is eventually visited.
    @MainActor private static func restoreParkedWindowIfReady() {
        guard let tracked = trackedWindow, tracked.parked else {
            return
        }
        let ownerIsCurrent = managedDisplays(connection: _CGSDefaultConnection())
            .contains { $0.currentSpaceID == tracked.spaceID }
        guard ownerIsCurrent else {
            return
        }
        trackedWindow = nil
        tracked.window.orderFront(nil)
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

    // MARK: - macOS 27 IOHID Payload

    // Binary IOHID event layouts appended to the serialized CGEvent. These
    // are used only by the macOS 27 branch in `postSwipeGesture` above.

    private enum IOHID {
        static let eventTypeVelocity: UInt32 = 9
        static let eventTypeFluidTouchGesture: UInt32 = 23
        static let flavorDockPrimary: UInt16 = 3
    }

    private struct IOHIDEventBase {
        var size: UInt32
        var type: UInt32
        var options: UInt32
        var depth: UInt8
        var reserved: (UInt8, UInt8, UInt8)
    }

    private struct IOHIDFluidTouchGestureData {
        var base: IOHIDEventBase
        var positionX: Int32
        var positionY: Int32
        var positionZ: Int32
        var swipeMask: UInt32
        var gestureMotion: UInt16
        var gestureFlavor: UInt16
        var swipeProgress: Int32
    }

    private struct IOHIDVelocityEventData {
        var base: IOHIDEventBase
        var velocityX: Int32
        var velocityY: Int32
        var velocityZ: Int32
    }

    private struct IOHIDSystemQueueElementHeader {
        var timestamp: UInt64
        var senderID: UInt64
        var options: UInt32
        var attributeLength: UInt32
        var eventCount: UInt32
    }

    private static func postAugmentedDockSwipe(phase: Int64, goRight: Bool, velocity: Double) -> Bool {
        guard let event = CGEvent(source: nil) else {
            return false
        }

        let progress = goRight ? 1.0 : -1.0
        let signedVelocity = goRight ? velocity : -velocity

        event.setIntegerValueField(Field.eventType, value: EventType.dockControl)
        event.setIntegerValueField(Field.gestureHIDType, value: hidTypeDockSwipe)
        event.setIntegerValueField(Field.gesturePhase, value: phase)
        event.setDoubleValueField(Field.gestureSwipeProgress, value: progress)
        event.setIntegerValueField(Field.gestureSwipeMotion, value: horizontalMotion)
        event.setDoubleValueField(Field.gestureSwipeVelocityX, value: signedVelocity)
        event.setDoubleValueField(Field.gestureSwipeVelocityY, value: 0)
        event.setIntegerValueField(Field.gesturePhase2, value: phase)
        event.setDoubleValueField(Field.gestureFlavor, value: Double(IOHID.flavorDockPrimary))
        event.setDoubleValueField(Field.eventTimestamp, value: Double(mach_absolute_time()))
        event.setDoubleValueField(Field.gestureSwipePositionX, value: 0.1)

        guard let augmented = withIOHIDPayload(event, phase: phase, velocity: signedVelocity) else {
            return false
        }
        augmented.post(tap: .cgSessionEventTap)
        return true
    }

    private static func withIOHIDPayload(_ event: CGEvent, phase: Int64, velocity: Double) -> CGEvent? {
        guard let serialized = event.data else {
            return nil
        }

        var bytes = serialized as Data
        guard bytes.starts(with: [0, 0, 0, 2]) else {
            return nil
        }
        let payload = iohidPayload(event: event, phase: phase, velocity: velocity)
        let size = UInt16(payload.count)
        bytes.append(UInt8(size >> 8))
        bytes.append(UInt8(size & 0xFF))
        bytes.append(UInt8(Field.iohidPayload >> 8))
        bytes.append(UInt8(Field.iohidPayload & 0xFF))
        bytes.append(payload)

        return CGEvent(withDataAllocator: kCFAllocatorDefault, data: bytes as CFData)
    }

    private static func iohidPayload(event: CGEvent, phase: Int64, velocity: Double) -> Data {
        let timestamp = event.timestamp != 0 ? event.timestamp : mach_absolute_time()
        let progress = event.getDoubleValueField(Field.gestureSwipeProgress)
        let positionX = event.getDoubleValueField(Field.gestureSwipePositionX)
        let positionY = event.getDoubleValueField(Field.gestureSwipePositionY)
        var data = Data()

        var header = IOHIDSystemQueueElementHeader(
            timestamp: timestamp,
            senderID: 0,
            options: 0,
            attributeLength: 0,
            eventCount: 2
        )
        withUnsafeBytes(of: &header) { data.append(contentsOf: $0) }

        var gesture = IOHIDFluidTouchGestureData(
            base: IOHIDEventBase(
                size: UInt32(MemoryLayout<IOHIDFluidTouchGestureData>.size),
                type: IOHID.eventTypeFluidTouchGesture,
                options: UInt32((phase & 0xFF) << 24),
                depth: 0,
                reserved: (0, 0, 0)
            ),
            positionX: fixedPoint(positionX),
            positionY: fixedPoint(positionY),
            positionZ: 0,
            swipeMask: 0,
            gestureMotion: UInt16(horizontalMotion),
            gestureFlavor: IOHID.flavorDockPrimary,
            swipeProgress: fixedPoint(-progress)
        )
        withUnsafeBytes(of: &gesture) { data.append(contentsOf: $0) }

        var velocityEvent = IOHIDVelocityEventData(
            base: IOHIDEventBase(
                size: UInt32(MemoryLayout<IOHIDVelocityEventData>.size),
                type: IOHID.eventTypeVelocity,
                options: 0,
                depth: 1,
                reserved: (0, 0, 0)
            ),
            velocityX: fixedPoint(-velocity),
            velocityY: 0,
            velocityZ: 0
        )
        withUnsafeBytes(of: &velocityEvent) { data.append(contentsOf: $0) }
        return data
    }

    private static func fixedPoint(_ value: Double) -> Int32 {
        let scaled = value * 65_536.0
        if scaled >= Double(Int32.max) {
            return Int32.max
        }
        if scaled <= Double(Int32.min) {
            return Int32.min
        }
        let fixed = Int32(scaled)
        if fixed == 0, value != 0 {
            return value > 0 ? 1 : -1
        }
        return fixed
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
