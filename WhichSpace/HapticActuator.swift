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

    private static var actuators: [CFTypeRef] = []
    private static var didOpenActuators = false

    /// Plays one haptic tap on every available Force Touch trackpad, opening
    /// their actuators on first use. Does nothing without a haptic trackpad.
    static func actuate(intensity: Int) {
        guard let api else {
            return
        }
        if !didOpenActuators {
            actuators = openActuators(api: api)
            didOpenActuators = true
        }
        guard !actuators.isEmpty else {
            return
        }
        let actuationID = Int32(intensity.clamped(to: Layout.scrollHapticIntensityRange))
        let results = actuators.map { api.actuate($0, actuationID, 0, 0, 0) }
        if results.contains(where: { $0 != 0 }) {
            // Actuators can go stale (e.g. across sleep/wake); drop them so
            // the next call enumerates and opens the current devices again.
            actuators.removeAll()
            didOpenActuators = false
        }
    }

    /// Returns every multitouch device whose actuator opens successfully.
    /// This covers Macs used with both a built-in and an external trackpad.
    private static func openActuators(api: API) -> [CFTypeRef] {
        guard let list = api.createList()?.takeRetainedValue() else {
            return []
        }
        var actuators: [CFTypeRef] = []
        for device in list as NSArray {
            var deviceID: UInt64 = 0
            guard api.getDeviceID(device as AnyObject, &deviceID) == 0,
                  let actuator = api.createActuator(deviceID)?.takeRetainedValue()
            else {
                continue
            }
            if api.open(actuator) == 0 {
                actuators.append(actuator)
            }
        }
        return actuators
    }
}
