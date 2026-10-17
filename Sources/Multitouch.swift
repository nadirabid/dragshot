import Foundation

// File-scope state. The framework's contact callback has to be a plain C function pointer,
// so it cannot capture anything — these are reachable without a context.

private let touchLock = NSLock()
private var touchCount: Int32 = 0

private typealias DeviceRef = UnsafeMutableRawPointer
private typealias ContactCallback = @convention(c) (DeviceRef?, UnsafeMutableRawPointer?, Int32, Double, Int32) -> Int32

/// The callback itself. A top-level function with no captures, which is the only shape
/// Swift will convert to a C function pointer.
private func contactFrameCallback(_ device: DeviceRef?,
                                  _ data: UnsafeMutableRawPointer?,
                                  _ fingers: Int32,
                                  _ timestamp: Double,
                                  _ frame: Int32) -> Int32 {
    Multitouch.updateContacts(fingers)
    return 0
}

/// Raw trackpad contact frames via the private MultitouchSupport framework.
///
/// Three contacts distinguish this gesture from ordinary drags; the final finger lift
/// ends selection without waiting for the system's drag-release grace period.
/// Cursor positions come from the system's own mouse events, so there is no
/// coordinate mapping here and the selection tracks the real pointer with Apple's own
/// acceleration curve.
enum Multitouch {
    private typealias CreateListFn = @convention(c) () -> Unmanaged<CFMutableArray>?
    private typealias RegisterFn = @convention(c) (DeviceRef?, ContactCallback?) -> Void
    private typealias StartFn = @convention(c) (DeviceRef?, Int32) -> Void
    private typealias StopFn = @convention(c) (DeviceRef?) -> Void

    private static var handle: UnsafeMutableRawPointer?
    private static var devices: [DeviceRef] = []

    static var isAvailable: Bool { handle != nil && !devices.isEmpty }

    /// Number of fingers currently resting on the pad.
    static var activeTouches: Int {
        touchLock.lock(); defer { touchLock.unlock() }
        return Int(touchCount)
    }

    static func updateContacts(_ fingers: Int32) {
        touchLock.lock()
        let lifted = touchCount > 0 && fingers == 0
        touchCount = fingers
        touchLock.unlock()
        if lifted {
            DispatchQueue.main.async { EventTap.endTrackpadDrag() }
        }
    }

    static func start() {
        let path = "/System/Library/PrivateFrameworks/MultitouchSupport.framework/MultitouchSupport"
        guard let h = dlopen(path, RTLD_NOW) else {
            Log.write("multitouch: dlopen failed — three-finger fingerprint unavailable")
            return
        }
        handle = h

        func sym<T>(_ name: String, _ type: T.Type) -> T? {
            guard let p = dlsym(h, name) else { return nil }
            return unsafeBitCast(p, to: T.self)
        }

        guard let createList = sym("MTDeviceCreateList", CreateListFn.self),
              let register = sym("MTRegisterContactFrameCallback", RegisterFn.self),
              let startDevice = sym("MTDeviceStart", StartFn.self) else {
            Log.write("multitouch: required symbols missing")
            return
        }

        // MTDeviceCreateList returns an array we do not own.
        guard let array = createList()?.takeUnretainedValue() else {
            Log.write("multitouch: no device list")
            return
        }
        let count = CFArrayGetCount(array)
        guard count > 0 else {
            Log.write("multitouch: device list empty")
            return
        }

        for i in 0..<count {
            guard let raw = CFArrayGetValueAtIndex(array, i) else { continue }
            let device = UnsafeMutableRawPointer(mutating: raw)
            devices.append(device)
            register(device, contactFrameCallback)
            startDevice(device, 0)
        }
        Log.write("multitouch: listening on \(devices.count) device(s)")
    }

}
