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
    /// WindowServer connection notification ids for space transitions
    private enum Event: UInt32, CaseIterable {
        case currentSpaceChanged = 1329
        case activeSpaceChanged = 1401
    }

    private nonisolated static let logger = Logger(
        subsystem: "io.gechr.WhichSpace", category: "SpaceChangeNotifier"
    )

    /// Set once from `start()` before registration, then only read (on the
    /// main queue) from the notify proc's hop - hence nonisolated(unsafe)
    private nonisolated(unsafe) static var onChange: (@MainActor () -> Void)?

    private static var started = false

    /// Registers for WindowServer space-change events. The handler is
    /// invoked on the main actor for every space transition.
    static func start(onChange handler: @escaping @MainActor () -> Void) {
        guard !started else {
            return
        }
        started = true
        onChange = handler
        let conn = _CGSDefaultConnection()
        for event in Event.allCases {
            let error = SLSRegisterConnectionNotifyProc(conn, notifyProc, event.rawValue, nil)
            if error != .success {
                logger.error("failed to register for WindowServer event \(event.rawValue): \(error.rawValue)")
            }
        }
    }

    /// Non-capturing C callback. The WindowServer calls it on whichever
    /// thread receives the datagram, so extract nothing and hop to main.
    private nonisolated static let notifyProc: CGSConnectionNotifyProc = { event, _, _, _, _ in
        logger.debug("WindowServer space event \(event)")
        DispatchQueue.main.async {
            MainActor.assumeIsolated {
                onChange?()
            }
        }
    }
}
