import Cocoa
import os.log

/// Receives push notifications from the WindowServer when the active space
/// changes, via the private `SLSRegisterConnectionNotifyProc` API.
///
/// The WindowServer delivers these the instant the space transition starts -
/// lower latency than `NSWorkspace.activeSpaceDidChangeNotification` (which
/// is derived from the same events but delivered later through AppKit) and
/// much lower than the `com.apple.spaces.plist` file watch (which waits for
/// cfprefsd to rewrite the plist). The event ids were established
/// empirically and are stable across recent macOS releases.
@MainActor
enum SpaceChangeNotifier {
    /// WindowServer connection notification ids, established empirically:
    /// - 1329/1401 fire the instant the current/active space changes
    /// - 818/828/1322 fire on space creation and deletion
    /// - 1325-1328 fire when windows are added to / removed from a space
    /// Each group retains its meaning so window-only events can avoid a full
    /// Space snapshot rebuild.
    private nonisolated static let eventReasons: [UInt32: SpaceUpdateReason] = [
        818: .topology,
        828: .topology,
        1322: .topology,
        1325: .windowMembership,
        1326: .windowMembership,
        1327: .windowMembership,
        1328: .windowMembership,
        1329: .activeSpace,
        1401: .activeSpace,
    ]

    private nonisolated static let logger = Logger(
        subsystem: "io.gechr.WhichSpace", category: "SpaceChangeNotifier"
    )

    /// Set once from `start()` before registration, then only read (on the
    /// main queue) from the notify proc's hop - hence nonisolated(unsafe)
    private nonisolated(unsafe) static var onChange: (@MainActor (SpaceUpdateReason) -> Void)?

    private static var started = false

    /// Registers for WindowServer space-change events. The handler is
    /// invoked on the main actor for every space transition.
    static func start(onChange handler: @escaping @MainActor (SpaceUpdateReason) -> Void) {
        guard !started else {
            return
        }
        started = true
        onChange = handler
        let conn = _CGSDefaultConnection()
        for event in eventReasons.keys.sorted() {
            let error = SLSRegisterConnectionNotifyProc(conn, notifyProc, event, nil)
            if error != .success {
                logger.error("failed to register for WindowServer event \(event): \(error.rawValue)")
            }
        }
    }

    nonisolated static func reason(forEvent event: UInt32) -> SpaceUpdateReason? {
        eventReasons[event]
    }

    /// Non-capturing C callback. The WindowServer calls it on whichever
    /// thread receives the datagram, so extract nothing and hop to main.
    private nonisolated static let notifyProc: CGSConnectionNotifyProc = { event, _, _, _, _ in
        logger.debug("WindowServer space event \(event)")
        guard let reason = reason(forEvent: event) else {
            return
        }
        DispatchQueue.main.async {
            MainActor.assumeIsolated {
                onChange?(reason)
            }
        }
    }
}
