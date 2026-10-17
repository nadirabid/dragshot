import Foundation

// Probe: does MultitouchSupport still hand us raw trackpad contact frames on macOS 27?
// Private API, resolved at runtime from the dyld shared cache.

final class MTContact: NSObject {
    @objc dynamic var frame: Int32 = 0
    @objc dynamic var timestamp: Double = 0
    @objc dynamic var identifier: Int32 = 0
    @objc dynamic var state: Int32 = 0
    @objc dynamic var foo3: Int32 = 0
    @objc dynamic var foo4: Int32 = 0
    @objc dynamic var angle: Double = 0
    @objc dynamic var area: Double = 0
    @objc dynamic var foo7: Double = 0
    @objc dynamic var zTotal: Double = 0
    @objc dynamic var x: Double = 0
    @objc dynamic var y: Double = 0
    @objc dynamic var z: Double = 0
}

typealias MTDeviceRef = UnsafeMutableRawPointer
typealias MTContactCallback = @convention(c) (MTDeviceRef?, UnsafeMutableRawPointer?, Int32, Double, Int32) -> Int32
typealias MTDeviceCreateListFn = @convention(c) () -> Unmanaged<CFMutableArray>?
typealias MTRegisterCallbackFn = @convention(c) (MTDeviceRef?, MTContactCallback?) -> Void
typealias MTDeviceStartFn = @convention(c) (MTDeviceRef?, Int32) -> Void
typealias MTDeviceStopFn = @convention(c) (MTDeviceRef?) -> Void
typealias MTDeviceIsOpaqueFn = @convention(c) (MTDeviceRef?) -> Bool

let path = "/System/Library/PrivateFrameworks/MultitouchSupport.framework/MultitouchSupport"
guard let handle = dlopen(path, RTLD_NOW) else {
    let err = String(cString: dlerror() ?? UnsafeMutablePointer(mutating: ""))
    FileHandle.standardError.write("dlopen failed: \(err)\n".data(using: .utf8)!)
    exit(1)
}
print("dlopen ok")

func sym<T>(_ name: String, _ type: T.Type) -> T? {
    guard let p = dlsym(handle, name) else { return nil }
    return unsafeBitCast(p, to: T.self)
}

guard let createList = sym("MTDeviceCreateList", MTDeviceCreateListFn.self) else {
    FileHandle.standardError.write("MTDeviceCreateList missing\n".data(using: .utf8)!)
    exit(1)
}
guard let register = sym("MTRegisterContactFrameCallback", MTRegisterCallbackFn.self) else {
    FileHandle.standardError.write("MTRegisterContactFrameCallback missing\n".data(using: .utf8)!)
    exit(1)
}
guard let start = sym("MTDeviceStart", MTDeviceStartFn.self) else {
    FileHandle.standardError.write("MTDeviceStart missing\n".data(using: .utf8)!)
    exit(1)
}
let isOpaque = sym("MTDeviceIsOpaque", MTDeviceIsOpaqueFn.self)

guard let list = createList()?.takeRetainedValue() as? [MTDeviceRef] else {
    FileHandle.standardError.write("no devices\n".data(using: .utf8)!)
    exit(1)
}
print("devices: \(list.count)")

var frames = 0
let callback: MTContactCallback = { _, data, nFingers, timestamp, frame in
    frames += 1
    guard let data, nFingers > 0 else { return 0 }
    let contacts = data.assumingMemoryBound(to: MTContact.self)
    let fingers = (0..<Int(nFingers)).map { i -> String in
        let c = contacts[i]
        return String(format: "(%.2f,%.2f) z=%.2f", c.x, c.y, c.z)
    }
    print("frame \(frame) t=\(String(format: "%.3f", timestamp)) fingers=\(nFingers) \(fingers.joined(separator: " "))")
    return 0
}

for (i, device) in list.enumerated() {
    let opaque = isOpaque?(device) ?? false
    print("device \(i) opaque=\(opaque)")
    register(device, callback)
    start(device, 0)
}

print("listening 5s — touch the trackpad with 1, 2, 3 fingers")
Thread.sleep(forTimeInterval: 5)
print("frames received: \(frames)")
if frames == 0 {
    print("RESULT: no contact frames (blocked or API changed)")
} else {
    print("RESULT: raw multitouch available")
}
