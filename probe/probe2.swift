import Foundation

// Probe 2: corrected ownership + diagnostics.
// MTDeviceCreateList returns a CFMutableArray we do NOT own -> takeUnretainedValue.

typealias MTDeviceRef = UnsafeMutableRawPointer
typealias MTContactCallback = @convention(c) (MTDeviceRef?, UnsafeMutableRawPointer?, Int32, Double, Int32) -> Int32
typealias MTDeviceCreateListFn = @convention(c) () -> Unmanaged<CFMutableArray>?
typealias MTRegisterCallbackFn = @convention(c) (MTDeviceRef?, MTContactCallback?) -> Void
typealias MTDeviceStartFn = @convention(c) (MTDeviceRef?, Int32) -> Void

let path = "/System/Library/PrivateFrameworks/MultitouchSupport.framework/MultitouchSupport"
guard let handle = dlopen(path, RTLD_NOW) else {
    print("dlopen failed")
    exit(1)
}

func sym<T>(_ name: String, _ type: T.Type) -> T? {
    guard let p = dlsym(handle, name) else { return nil }
    return unsafeBitCast(p, to: T.self)
}

// Enumerate what the framework actually exposes.
var count: UInt32 = 0
let img = _dyld_image_count()
for i in 0..<img {
    if let name = _dyld_get_image_name(i).map({ String(cString: $0) }), name.contains("MultitouchSupport") {
        print("loaded image: \(name)")
    }
}
_ = count

let names = ["MTDeviceCreateList", "MTDeviceCreateDefault", "MTRegisterContactFrameCallback",
             "MTUnregisterContactFrameCallback", "MTDeviceStart", "MTDeviceStop",
             "MTDeviceIsOpaque", "MTDeviceIsBuiltIn", "MTDeviceGetDeviceID"]
for n in names {
    print("symbol \(n): \(dlsym(handle, n) != nil ? "present" : "MISSING")")
}

guard let createList = sym("MTDeviceCreateList", MTDeviceCreateListFn.self) else {
    print("no MTDeviceCreateList")
    exit(1)
}

if let arr = createList()?.takeUnretainedValue() {
    print("array type: \(CFGetTypeID(arr)) CFArray=\(CFArrayGetTypeID())")
    print("count: \(CFArrayGetCount(arr))")
    for i in 0..<CFArrayGetCount(arr) {
        let raw = CFArrayGetValueAtIndex(arr, i)
        print("  device \(i): \(String(describing: raw))")
    }
} else {
    print("createList returned nil")
}

// Try the default-device entry point too.
if let createDefaultPtr = dlsym(handle, "MTDeviceCreateDefault") {
    typealias Fn = @convention(c) () -> MTDeviceRef?
    let fn = unsafeBitCast(createDefaultPtr, to: Fn.self)
    print("default device: \(String(describing: fn()))")
}
