import Cocoa

/// Own the complete mouse sequence, including the mouse-up after Escape. All callbacks
/// run on the main run loop, so controller state and event routing cannot race.
enum EventTap {
    static var canBegin: () -> Bool = { false }
    static var onBegin: (NSPoint) -> Void = { _ in }
    static var onMove: (NSPoint) -> Void = { _ in }
    static var onEnd: (NSPoint) -> Void = { _ in }
    static var onCancel: () -> Bool = { false }
    static var onAim: (NSPoint) -> Void = { _ in }
    static var onOutsideInteraction: (NSPoint) -> Bool = { _ in false }
    static var onTogglePicker: () -> Bool = { false }
    static var hotkeyEnabled = false

    private static var tap: CFMachPort?
    private static var source: CFRunLoopSource?
    private static var dragging = false
    private static var cancelled = false
    private static var trackpadDrag = false
    private static var lastDragPoint = NSPoint.zero
    private static var aiming = false
    private static var swallowedKeys: Set<Int64> = []

    static var isRunning: Bool { tap != nil }

    static func start() {
        let types: [CGEventType] = [.leftMouseDown, .leftMouseDragged, .leftMouseUp,
                                   .rightMouseDown, .otherMouseDown, .scrollWheel,
                                   .mouseMoved, .keyDown, .keyUp]
        let mask = types.reduce(CGEventMask(0)) { $0 | (1 << $1.rawValue) }
        guard let port = CGEvent.tapCreate(
            tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
            eventsOfInterest: mask,
            callback: { _, type, event, _ in EventTap.handle(type: type, event: event) },
            userInfo: nil
        ) else {
            Log.write("event tap unavailable — Accessibility permission is required")
            return
        }
        tap = port
        source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, port, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: port, enable: true)
        Log.write("event tap installed")
    }

    static func endTrackpadDrag() {
        guard dragging, trackpadDrag, !cancelled else { return }
        // Keep owning the mouse sequence until its delayed up; never deliver it twice
        // or allow resumed motion to drag the editor or the app beneath it.
        cancelled = true
        onEnd(lastDragPoint)
    }

    static func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return Unmanaged.passUnretained(event)
        }

        // Cocoa uses the lower-left of the main display, including for displays above it.
        let point = event.unflippedLocation
        if type == .keyDown || type == .keyUp {
            let key = event.getIntegerValueField(.keyboardEventKeycode)
            if type == .keyUp {
                return swallowedKeys.remove(key) == nil ? Unmanaged.passUnretained(event) : nil
            }
            if swallowedKeys.contains(key) {
                // A missing key-up for a swallowed shortcut must not eat the
                // same key forever. A plain slash is always allowed through.
                if key == 44, !event.flags.contains(.maskCommand) {
                    swallowedKeys.remove(key)
                    return Unmanaged.passUnretained(event)
                }
                return nil
            }
            if key == 53, onCancel() {
                cancelled = dragging
                aiming = false
                swallowedKeys.insert(key)
                return nil
            }
            if key == 21, hotkeyEnabled, event.flags.contains([.maskCommand, .maskShift]),
               !dragging, !aiming, canBegin() {
                aiming = true
                swallowedKeys.insert(key)
                onAim(point)
                return nil
            }
            if key == 44, event.flags.contains(.maskCommand), !dragging, !aiming,
               onTogglePicker() {
                swallowedKeys.insert(key)
                return nil
            }
            return Unmanaged.passUnretained(event)
        }

        if !dragging || cancelled,
           type == .leftMouseDown || type == .rightMouseDown
                || type == .otherMouseDown || type == .scrollWheel,
           onOutsideInteraction(point) {
            // Dismiss without consuming the click or scroll that belongs to another app.
            return Unmanaged.passUnretained(event)
        }
        if type == .mouseMoved, aiming {
            onAim(point)
            return Unmanaged.passUnretained(event)
        }
        if type == .leftMouseDown {
            guard !dragging, aiming || (Multitouch.activeTouches == 3 && canBegin()) else {
                return Unmanaged.passUnretained(event)
            }
            dragging = true
            cancelled = false
            trackpadDrag = !aiming
            lastDragPoint = point
            aiming = false
            onBegin(point)
            return nil
        }
        guard dragging else { return Unmanaged.passUnretained(event) }
        if type == .leftMouseDragged {
            if !cancelled {
                lastDragPoint = point
                onMove(point)
            }
            return nil
        }
        if type == .leftMouseUp {
            dragging = false
            if !cancelled { onEnd(point) }
            cancelled = false
            return nil
        }
        return Unmanaged.passUnretained(event)
    }
}
