import Foundation

/// Plays haptic feedback through the built-in Force Touch trackpad using the
/// private MultitouchSupport actuator API.
///
/// `NSHapticFeedbackManager` is a silent no-op for menu bar accessory apps
/// (the system only honors it for the active app), so the trackpad actuator
/// is driven directly instead. Symbols are resolved at runtime so a future
/// macOS removing them degrades to a no-op rather than a crash.
@MainActor
enum HapticActuator {
    private typealias MTDeviceCreateListFn = @convention(c) () -> Unmanaged<CFArray>?
    private typealias MTDeviceGetDeviceIDFn = @convention(c) (
        AnyObject, UnsafeMutablePointer<UInt64>
    ) -> Int32
    private typealias MTActuatorCreateFromDeviceIDFn = @convention(c) (UInt64) -> Unmanaged<CFTypeRef>?
    private typealias MTActuatorOpenFn = @convention(c) (CFTypeRef) -> Int32
    private typealias MTActuatorActuateFn = @convention(c) (CFTypeRef, Int32, UInt32, Float, Float) -> Int32

    private struct API {
        let createList: MTDeviceCreateListFn
        let getDeviceID: MTDeviceGetDeviceIDFn
        let createActuator: MTActuatorCreateFromDeviceIDFn
        let open: MTActuatorOpenFn
        let actuate: MTActuatorActuateFn
    }

    /// A subtle single tap (6 is the strong Force Touch detent weight)
    private static let actuationID: Int32 = 3

    private static let api: API? = {
        guard let handle = dlopen(
            "/System/Library/PrivateFrameworks/MultitouchSupport.framework/MultitouchSupport",
            RTLD_NOW
        ),
            let createList = dlsym(handle, "MTDeviceCreateList"),
            let getDeviceID = dlsym(handle, "MTDeviceGetDeviceID"),
            let createActuator = dlsym(handle, "MTActuatorCreateFromDeviceID"),
            let open = dlsym(handle, "MTActuatorOpen"),
            let actuate = dlsym(handle, "MTActuatorActuate")
        else {
            return nil
        }
        return API(
            createList: unsafeBitCast(createList, to: MTDeviceCreateListFn.self),
            getDeviceID: unsafeBitCast(getDeviceID, to: MTDeviceGetDeviceIDFn.self),
            createActuator: unsafeBitCast(createActuator, to: MTActuatorCreateFromDeviceIDFn.self),
            open: unsafeBitCast(open, to: MTActuatorOpenFn.self),
            actuate: unsafeBitCast(actuate, to: MTActuatorActuateFn.self)
        )
    }()

    private static var actuator: CFTypeRef?

    /// Plays one haptic tap, opening the actuator on first use. Does nothing
    /// on hardware without a haptic trackpad.
    static func actuate() {
        guard let api else {
            return
        }
        if actuator == nil {
            actuator = openActuator(api: api)
        }
        guard let actuator else {
            return
        }
        if api.actuate(actuator, actuationID, 0, 0, 0) != 0 {
            // The actuator can go stale (e.g. across sleep/wake); drop it so
            // the next call reopens a fresh one
            Self.actuator = nil
        }
    }

    /// Returns the first multitouch device whose actuator opens successfully.
    /// Device IDs vary by hardware generation, so enumeration is required.
    private static func openActuator(api: API) -> CFTypeRef? {
        guard let list = api.createList()?.takeRetainedValue() else {
            return nil
        }
        for device in list as NSArray {
            var deviceID: UInt64 = 0
            guard api.getDeviceID(device as AnyObject, &deviceID) == 0,
                  let actuator = api.createActuator(deviceID)?.takeRetainedValue()
            else {
                continue
            }
            if api.open(actuator) == 0 {
                return actuator
            }
        }
        return nil
    }
}
