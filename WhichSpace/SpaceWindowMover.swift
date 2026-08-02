import AppKit

// MARK: - Backends

/// Private mechanisms for moving a window to another Space, newest first.
enum WindowMoveBackend: CaseIterable {
    case bridged
    case managedSpace
    case compatID
}

/// Abstracts the private move APIs and the membership read used to confirm
/// them, so tests never touch the window server.
protocol WindowMoving: Sendable {
    func isAvailable(_ backend: WindowMoveBackend) -> Bool
    func perform(_ backend: WindowMoveBackend, windowID: CGWindowID, spaceID: Int) -> Bool
    func spaceIDs(forWindow windowID: CGWindowID) -> [Int]
}

struct SkyLightWindowMover: WindowMoving {
    func isAvailable(_ backend: WindowMoveBackend) -> Bool {
        switch backend {
        case .bridged:
            WSMoveBridgedIsAvailable()
        case .managedSpace:
            WSMoveManagedSpaceIsAvailable()
        case .compatID:
            WSMoveCompatIDIsAvailable()
        }
    }

    func perform(_ backend: WindowMoveBackend, windowID: CGWindowID, spaceID: Int) -> Bool {
        let space = UInt64(spaceID)
        switch backend {
        case .bridged:
            return WSMoveBridged(windowID, space)
        case .managedSpace:
            return WSMoveManagedSpace(_CGSDefaultConnection(), windowID, space)
        case .compatID:
            return WSMoveCompatID(_CGSDefaultConnection(), windowID, space)
        }
    }

    func spaceIDs(forWindow windowID: CGWindowID) -> [Int] {
        // Selector 0x7 = all spaces the window is on
        guard let result = SLSCopySpacesForWindows(_CGSDefaultConnection(), 0x7, [Int(windowID)] as CFArray) else {
            return []
        }
        return result.takeRetainedValue() as? [Int] ?? []
    }
}

// MARK: - Window Raising

/// Abstracts the Accessibility raise used after a move, so tests never message
/// another process's AX server.
protocol WindowRaising: Sendable {
    @discardableResult
    func raise(_ window: FrontWindow) -> Bool
}

/// Attempts to make a moved window frontmost on its new Space. The private
/// moves change Space membership but not z-order, so without a raise an
/// incumbent window on the target Space would keep focus over the arrival.
/// Cross-Space AX behavior is empirical rather than documented, hence the
/// attempt is best-effort.
struct AXWindowRaiser: WindowRaising {
    /// Cap on each AX round-trip. The calls message the owning process
    /// synchronously from the main actor, so a hung app must not stall
    /// WhichSpace for a nicety.
    private static let messagingTimeout: Float = 0.25

    @discardableResult
    func raise(_ window: FrontWindow) -> Bool {
        let application = AXUIElementCreateApplication(window.ownerPID)
        // The timeout binds to the exact element it is set on, not to elements
        // derived from it, so each element gets its own
        AXUIElementSetMessagingTimeout(application, Self.messagingTimeout)

        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(application, kAXWindowsAttribute as CFString, &value) == .success,
              let windows = value as? [AXUIElement]
        else {
            return false
        }

        for element in windows {
            var windowID = CGWindowID(0)
            guard _AXUIElementGetWindow(element, &windowID) == .success, windowID == window.id else {
                continue
            }
            AXUIElementSetMessagingTimeout(element, Self.messagingTimeout)
            // Main marks which window a later activation should focus; the
            // raise is what reorders, so only its result counts
            AXUIElementSetAttributeValue(element, kAXMainAttribute as CFString, kCFBooleanTrue)
            return AXUIElementPerformAction(element, kAXRaiseAction as CFString) == .success
        }
        return false
    }
}

// MARK: - Front Window

struct FrontWindow: Equatable {
    let id: CGWindowID
    let ownerPID: pid_t
}

protocol FrontWindowLocating: Sendable {
    func frontWindow() -> FrontWindow?
}

/// Identifies the window to move from the window list rather than through
/// Accessibility, so moving a window needs no permission of its own.
struct SystemFrontWindowLocator: FrontWindowLocating {
    func frontWindow() -> FrontWindow? {
        // On-screen only, so candidates are limited to the current Space
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        let windowList = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] ?? []
        return Self.resolve(
            windowList: windowList,
            frontmostPID: NSWorkspace.shared.frontmostApplication?.processIdentifier,
            excluding: ProcessInfo.processInfo.processIdentifier
        )
    }

    /// Picks the frontmost app's first regular window, falling back to the
    /// front-to-back window order. Kept pure so tests cover it directly.
    static func resolve(
        windowList: [[String: Any]],
        frontmostPID: pid_t?,
        excluding ownPID: pid_t
    ) -> FrontWindow? {
        var candidates: [FrontWindow] = []

        for window in windowList {
            guard let layer = window[kCGWindowLayer as String] as? Int, layer == 0,
                  let ownerPID = window[kCGWindowOwnerPID as String] as? pid_t, ownerPID != ownPID,
                  let windowNumber = window[kCGWindowNumber as String] as? Int
            else {
                continue
            }
            // Skip windows that are too small (likely utility/overlay windows)
            guard let bounds = window[kCGWindowBounds as String] as? [String: Any],
                  let width = bounds["Width"] as? Double,
                  let height = bounds["Height"] as? Double,
                  width > 5, height > 5
            else {
                continue
            }
            if let alpha = window[kCGWindowAlpha as String] as? Double, alpha <= 0 {
                continue
            }
            candidates.append(FrontWindow(id: CGWindowID(windowNumber), ownerPID: ownerPID))
        }

        if let frontmostPID, let owned = candidates.first(where: { $0.ownerPID == frontmostPID }) {
            return owned
        }
        return candidates.first
    }
}

// MARK: - Space Window Mover

/// Moves the front window to another Space, confirming the result before
/// reporting success. The bridged backend is asynchronous and the others return
/// nothing, so membership is the only trustworthy signal.
@MainActor
struct SpaceWindowMover {
    private let activateApp: @MainActor (pid_t) -> Void
    private let arrivalInterval: Duration
    private let arrivalTimeout: Duration
    private let confirmationInterval: Duration
    private let confirmationTimeout: Duration
    private let followAction: @MainActor (Int, pid_t) -> Void
    private let isProcessTrusted: () -> Bool
    private let locator: any FrontWindowLocating
    private let mover: any WindowMoving
    private let permitted: [WindowMoveBackend]
    private let raiser: any WindowRaising

    init(
        mover: any WindowMoving = SkyLightWindowMover(),
        locator: any FrontWindowLocating = SystemFrontWindowLocator(),
        raiser: any WindowRaising = AXWindowRaiser(),
        isProcessTrusted: @escaping () -> Bool = { AXIsProcessTrusted() },
        followAction: @escaping @MainActor (Int, pid_t) -> Void = { spaceID, ownerPID in
            SpaceSwitcher.switchToSpace(id: spaceID)
            NSRunningApplication(processIdentifier: ownerPID)?.activate()
        },
        activateApp: @escaping @MainActor (pid_t) -> Void = { ownerPID in
            NSRunningApplication(processIdentifier: ownerPID)?.activate()
        },
        // Injected so the ladder is testable: which backends a host permits
        // depends on its macOS version, so tests could not otherwise reach the
        // fall-through path
        permitted: [WindowMoveBackend] = Self.permittedBackends,
        confirmationTimeout: Duration = .milliseconds(400),
        confirmationInterval: Duration = .milliseconds(10),
        // Generous enough for a multi-Space swipe plus the snapshot debounce
        // that feeds the current-Space reading
        arrivalTimeout: Duration = .seconds(2),
        arrivalInterval: Duration = .milliseconds(50)
    ) {
        self.mover = mover
        self.locator = locator
        self.raiser = raiser
        self.isProcessTrusted = isProcessTrusted
        self.followAction = followAction
        self.activateApp = activateApp
        self.permitted = permitted
        self.confirmationTimeout = confirmationTimeout
        self.confirmationInterval = confirmationInterval
        self.arrivalTimeout = arrivalTimeout
        self.arrivalInterval = arrivalInterval
    }

    /// Moves the front window to the Space at the given 1-based number, which
    /// indexes the same array `switchToSpace` uses.
    func move(toSpaceNumber number: Int, follow: Bool, appState: AppState) async throws(MoveError) {
        let entries = appState.allSpaceEntries
        guard !entries.isEmpty else {
            throw .noSpacesAvailable
        }
        guard number >= 1, number <= entries.count else {
            throw .spaceOutOfRange(requested: number, max: entries.count)
        }
        let entry = entries[number - 1]
        guard entry.regularIndex != nil else {
            throw .spaceIsFullscreen(requested: number)
        }
        try await move(toSpaceID: entry.id, requested: number, follow: follow, entries: entries, appState: appState)
    }

    /// Moves the front window one Space left or right, skipping fullscreen
    /// Spaces. Either edge is an error rather than a silent no-op, so a script
    /// can tell a refusal from a move.
    func moveRelative(goRight: Bool, follow: Bool, appState: AppState) async throws(MoveError) {
        let entries = appState.allSpaceEntries
        guard !entries.isEmpty else {
            throw .noSpacesAvailable
        }
        let step = goRight ? 1 : -1
        var index = appState.currentSpace + step
        while entries.indices.contains(index - 1), entries[index - 1].regularIndex == nil {
            index += step
        }
        guard entries.indices.contains(index - 1) else {
            throw .spaceOutOfRange(requested: index, max: entries.count)
        }
        try await move(
            toSpaceID: entries[index - 1].id,
            requested: index,
            follow: follow,
            entries: entries,
            appState: appState
        )
    }

    private func move(
        toSpaceID spaceID: Int,
        requested: Int,
        follow: Bool,
        entries: [SpaceEntry],
        appState: AppState
    ) async throws(MoveError) {
        // Checked before any move is issued, so a permission failure never
        // leaves the window relocated
        if follow, !isProcessTrusted() {
            throw .accessibilityNotTrusted
        }

        guard let window = locator.frontWindow() else {
            throw .noWindowToMove
        }

        let source = Set(mover.spaceIDs(forWindow: window.id))

        // A sticky window is already everywhere, so treat it as moved
        if source.contains(spaceID) {
            raiseIfTrusted(window)
            await switchIfFollowing(follow, toSpaceID: spaceID, window: window, appState: appState)
            return
        }

        // The numbered target belongs to the menu bar display, but the window
        // list is global, so a window on another display would be moved across
        // displays without the caller asking for it
        guard source.contains(where: { id in entries.contains { $0.id == id } }) else {
            throw .noWindowToMove
        }
        // A window on a fullscreen Space is not a free-floating window, and the
        // private move leaves it in an unpredictable state
        guard !source.contains(where: { id in entries.contains { $0.id == id && $0.regularIndex == nil } }) else {
            throw .windowIsFullscreen
        }

        let backends = permitted.filter { mover.isAvailable($0) }
        guard !backends.isEmpty else {
            throw .unsupported
        }

        for backend in backends {
            guard mover.perform(backend, windowID: window.id, spaceID: spaceID) else {
                continue
            }
            if await confirm(window: window, spaceID: spaceID, leaving: source) {
                raiseIfTrusted(window)
                await switchIfFollowing(follow, toSpaceID: spaceID, window: window, appState: appState)
                return
            }
        }

        throw .moveFailed(requested: requested)
    }

    /// Raised before any follow switch, so the window is already frontmost on
    /// the target Space when the switch arrives. Sending needs no permission of
    /// its own, so without Accessibility the raise is skipped silently, and a
    /// failed raise never fails the move.
    private func raiseIfTrusted(_ window: FrontWindow) {
        guard isProcessTrusted() else {
            return
        }
        raiser.raise(window)
    }

    /// Follows the window, then re-asserts its focus once the switch lands.
    /// The pre-switch raise targets a window on an inactive Space, which AX
    /// honours only empirically, so the raise and activation are repeated on
    /// arrival where both are ordinary same-Space operations.
    private func switchIfFollowing(
        _ follow: Bool,
        toSpaceID spaceID: Int,
        window: FrontWindow,
        appState: AppState
    ) async {
        guard follow else {
            return
        }
        followAction(spaceID, window.ownerPID)
        guard await arrived(atSpaceID: spaceID, appState: appState) else {
            return
        }
        raiser.raise(window)
        activateApp(window.ownerPID)
    }

    /// Waits for the switch to land on the target Space. The swipe gestures
    /// complete asynchronously, so arrival is polled the same way membership
    /// is confirmed.
    private func arrived(atSpaceID spaceID: Int, appState: AppState) async -> Bool {
        var waited = Duration.zero
        while appState.currentSpaceID != spaceID {
            guard waited < arrivalTimeout else {
                return false
            }
            try? await Task.sleep(for: arrivalInterval)
            waited += arrivalInterval
        }
        return true
    }

    /// A move is only confirmed once the window is on the target *and* has left
    /// every Space it came from. Arriving without leaving is a copy, not a move,
    /// and reporting that as success would be a lie the caller cannot detect.
    private func confirm(window: FrontWindow, spaceID: Int, leaving source: Set<Int>) async -> Bool {
        var waited = Duration.zero
        while true {
            let current = Set(mover.spaceIDs(forWindow: window.id))
            if current.contains(spaceID), current.isDisjoint(with: source) {
                return true
            }
            guard waited < confirmationTimeout else {
                return false
            }
            try? await Task.sleep(for: confirmationInterval)
            waited += confirmationInterval
        }
    }

    /// Backends this macOS release is known to honour. The legacy calls remain
    /// callable where Apple has neutered them, so availability alone would not
    /// rule them out: `SLSMoveWindowsToManagedSpace` gained validation in 14.5,
    /// and the compat-ID pair does nothing from 15.0 onwards.
    static var permittedBackends: [WindowMoveBackend] {
        let version = ProcessInfo.processInfo.operatingSystemVersion
        // The bridged operation is capability-detected on every release
        var backends: [WindowMoveBackend] = [.bridged]
        guard version.majorVersion == 14 else {
            return backends
        }
        backends.append(version.minorVersion < 5 ? .managedSpace : .compatID)
        return backends
    }
}
