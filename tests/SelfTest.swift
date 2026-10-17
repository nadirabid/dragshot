import Cocoa

enum SelfTest {
    static let output = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("dragshot-ux-tests", isDirectory: true)

    static func require(_ condition: @autoclosure () -> Bool, _ message: String) {
        guard condition() else {
            let failure = "FAIL: \(message)"
            try? failure.write(to: output.appendingPathComponent("e2e-result.txt"),
                               atomically: true, encoding: .utf8)
            fputs(failure + "\n", stderr)
            exit(1)
        }
    }

    static func write(_ image: CGImage, name: String) {
        let rep = NSBitmapImageRep(cgImage: image)
        do {
            try rep.representation(using: .png, properties: [:])!.write(
                to: output.appendingPathComponent(name), options: .atomic)
        } catch {
            fatalError("Could not write test evidence: \(error)")
        }
    }

    static func run() {
        do { try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true) }
        catch { fatalError("Could not create test evidence directory: \(error)") }
        eventRouting()
        for scale: CGFloat in [1, 2] { rendering(scale: scale) }
        liveViewRendering()
        panelRendering()
        pickerRendering()
        pickerTrigger()
        print("PASS: coordinates, event suppression, Escape, transparent rendering at 1x/2x, live view, panel, picker, slash trigger")
        print("Visual evidence: \(output.path)")
    }

    static func mouse(_ type: CGEventType, _ point: CGPoint) -> CGEvent {
        CGEvent(mouseEventSource: nil, mouseType: type, mouseCursorPosition: point,
                mouseButton: .left)!
    }

    static func hotkey(at point: CGPoint) {
        let event = CGEvent(keyboardEventSource: nil, virtualKey: 21, keyDown: true)!
        event.location = point
        event.flags = [.maskCommand, .maskShift]
        require(EventTap.handle(type: .keyDown, event: event) == nil, "hotkey must be consumed")
        event.type = .keyUp
        require(EventTap.handle(type: .keyUp, event: event) == nil, "hotkey release must be consumed")
    }

    private static func eventRouting() {
        EventTap.hotkeyEnabled = true
        EventTap.canBegin = { true }
        var pickerToggled = false
        EventTap.onTogglePicker = { pickerToggled = true; return true }
        let slash = CGEvent(keyboardEventSource: nil, virtualKey: 44, keyDown: true)!
        slash.flags = [.maskCommand]
        require(EventTap.handle(type: .keyDown, event: slash) == nil,
                "Cmd+/ must be consumed")
        require(pickerToggled, "Cmd+/ must invoke the picker toggle")
        slash.type = .keyUp
        require(EventTap.handle(type: .keyUp, event: slash) == nil,
                "Cmd+/ release must be consumed")
        EventTap.onTogglePicker = { false }
        var began = CGPoint.zero
        var ended = CGPoint.zero
        var moves = 0
        var endings = 0
        var aims = 0
        EventTap.onBegin = { began = $0 }
        EventTap.onMove = { _ in moves += 1 }
        EventTap.onEnd = { ended = $0; endings += 1 }
        EventTap.onAim = { _ in aims += 1 }
        EventTap.onCancel = { true }
        let start = CGPoint(x: 120, y: 180)
        let end = CGPoint(x: 520, y: 380)
        let height = CGDisplayBounds(CGMainDisplayID()).height

        require(EventTap.handle(type: .leftMouseDown, event: mouse(.leftMouseDown, start)) != nil,
                "ordinary mouse-down must pass through")
        hotkey(at: start)
        require(aims == 1, "hotkey arms selection")
        require(EventTap.handle(type: .leftMouseDown, event: mouse(.leftMouseDown, start)) == nil,
                "selection mouse-down must be consumed")
        require(began == CGPoint(x: start.x, y: height - start.y), "event must use Cocoa coordinates")
        require(EventTap.handle(type: .leftMouseDragged, event: mouse(.leftMouseDragged, end)) == nil,
                "selection drag must be consumed")
        EventTap.endTrackpadDrag()
        require(endings == 0, "finger lift must not end a hotkey/mouse selection")
        let released = CGPoint(x: end.x + 4, y: end.y + 7)
        require(EventTap.handle(type: .leftMouseUp, event: mouse(.leftMouseUp, released)) == nil,
                "selection mouse-up must be consumed")
        require(ended == CGPoint(x: released.x, y: height - released.y),
                "release uses its own position, not the previous drag position")
        require(endings == 1 && moves == 1, "one delivery per selection event")

        hotkey(at: start)
        _ = EventTap.handle(type: .leftMouseDown, event: mouse(.leftMouseDown, start))
        let escape = CGEvent(keyboardEventSource: nil, virtualKey: 53, keyDown: true)!
        require(EventTap.handle(type: .keyDown, event: escape) == nil, "Escape must be consumed")
        require(EventTap.handle(type: .leftMouseDragged, event: mouse(.leftMouseDragged, end)) == nil,
                "cancelled drag must not leak into the underlying app")
        require(EventTap.handle(type: .leftMouseUp, event: mouse(.leftMouseUp, end)) == nil,
                "cancelled mouse-up must not leak into the underlying app")
        require(endings == 1 && moves == 1, "cancelled drag must not capture")
        EventTap.onCancel = { false }
        escape.type = .keyUp
        _ = EventTap.handle(type: .keyUp, event: escape)
        require(EventTap.handle(type: .keyDown, event: escape) != nil, "idle Escape passes through")

        Multitouch.updateContacts(3)
        _ = EventTap.handle(type: .leftMouseDown, event: mouse(.leftMouseDown, start))
        _ = EventTap.handle(type: .leftMouseDragged, event: mouse(.leftMouseDragged, end))
        EventTap.endTrackpadDrag()
        require(endings == 2 && ended == CGPoint(x: end.x, y: height - end.y),
                "finger lift ends trackpad selection at the last pointer position before mouse-up")
        EventTap.endTrackpadDrag()
        require(EventTap.handle(type: .leftMouseDragged, event: mouse(.leftMouseDragged, released)) == nil,
                "motion after finger lift must remain consumed")
        var outsideInteractions = 0
        EventTap.onOutsideInteraction = { _ in outsideInteractions += 1; return true }
        let scroll = CGEvent(source: nil)!
        scroll.type = .scrollWheel
        require(EventTap.handle(type: .scrollWheel, event: scroll) != nil && outsideInteractions == 1,
                "outside interactions must dismiss input before the delayed mouse-up")
        require(EventTap.handle(type: .leftMouseUp, event: mouse(.leftMouseUp, released)) == nil,
                "delayed mouse-up after finger lift must remain consumed")
        require(endings == 2 && moves == 2, "finger lift and delayed mouse-up cannot finish twice")
        EventTap.onOutsideInteraction = { _ in false }
        Multitouch.updateContacts(0)
    }

    private static func context(size: CGSize, scale: CGFloat) -> CGContext {
        CGContext(data: nil, width: Int(size.width * scale), height: Int(size.height * scale),
                  bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    }

    private static func alpha(_ image: CGImage, at point: CGPoint, scale: CGFloat) -> CGFloat {
        let rep = NSBitmapImageRep(cgImage: image)
        return rep.colorAt(x: Int(point.x * scale),
                           y: image.height - 1 - Int(point.y * scale))!.alphaComponent
    }

    private static func rendering(scale: CGFloat) {
        let size = CGSize(width: 900, height: 600)
        let rect = CGRect(x: 150, y: 180, width: 400, height: 250)
        let ctx = context(size: size, scale: scale)
        ctx.scaleBy(x: scale, y: scale)
        OverlayRenderer.draw(into: ctx, selection: rect, pointer: CGPoint(x: 550, y: 180),
                             bounds: CGRect(origin: .zero, size: size), scale: scale)
        let image = ctx.makeImage()!
        require(alpha(image, at: CGPoint(x: 30, y: 30), scale: scale) == 0,
                "desktop outside selection stays transparent at \(scale)x")
        require(alpha(image, at: CGPoint(x: 300, y: 300), scale: scale) == 0,
                "selection interior stays transparent at \(scale)x")
        require(alpha(image, at: CGPoint(x: 150, y: 300), scale: scale) > 0,
                "border stays at the requested coordinates at \(scale)x")
        write(image, name: "overlay-\(Int(scale))x.png")

        let desktop = context(size: size, scale: scale)
        desktop.scaleBy(x: scale, y: scale)
        desktop.setFillColor(CGColor(gray: 0.94, alpha: 1))
        desktop.fill(CGRect(origin: .zero, size: size))
        desktop.setFillColor(CGColor(srgbRed: 0.12, green: 0.16, blue: 0.22, alpha: 1))
        desktop.fill(CGRect(x: 450, y: 0, width: 450, height: 600))
        desktop.setStrokeColor(CGColor(gray: 0.5, alpha: 0.3))
        desktop.setLineWidth(0.5)
        for x in stride(from: 0, to: 900, by: 40) {
            desktop.move(to: CGPoint(x: x, y: 0))
            desktop.addLine(to: CGPoint(x: x, y: 600))
        }
        for y in stride(from: 0, to: 600, by: 40) {
            desktop.move(to: CGPoint(x: 0, y: y))
            desktop.addLine(to: CGPoint(x: 900, y: y))
        }
        desktop.strokePath()
        desktop.draw(image, in: CGRect(origin: .zero, size: size))
        write(desktop.makeImage()!, name: "preview-\(Int(scale))x.png")

        OverlayRenderer.draw(into: ctx, selection: .zero, pointer: nil,
                             bounds: CGRect(origin: .zero, size: size), scale: scale)
        require(alpha(ctx.makeImage()!, at: CGPoint(x: 150, y: 300), scale: scale) == 0,
                "old selection is cleared")
    }

    private static func liveViewRendering() {
        let screen = NSScreen.main!
        let window = OverlayWindow(screen: screen)
        window.selection = NSRect(x: 120, y: 160, width: 320, height: 240)
        let view = window.contentView!
        let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds)!
        view.cacheDisplay(in: view.bounds, to: rep)
        let image = rep.cgImage!
        let scale = CGFloat(image.width) / view.bounds.width
        require(alpha(image, at: CGPoint(x: 120, y: 300), scale: scale) > 0,
                "live AppKit view does not double-scale the selection")
        require(alpha(image, at: CGPoint(x: 260, y: 300), scale: scale) == 0,
                "live AppKit view does not paint desktop pixels")
        write(image, name: "live-view.png")
    }

    private static func panelRendering() {
        let panel = PanelWindow()
        panel.present(near: NSRect(x: 200, y: 400, width: 400, height: 200), on: NSScreen.main!)
        let view = panel.contentView!
        view.layoutSubtreeIfNeeded()
        let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds)!
        view.cacheDisplay(in: view.bounds, to: rep)
        write(rep.cgImage!, name: "panel.png")
        panel.orderOut(nil)
    }

    private static func pickerTrigger() {
        let previous = DSHIntegration.shared.isEnabled
        DSHIntegration.shared.isEnabled = true
        defer { DSHIntegration.shared.isEnabled = previous }
        let panel = PanelWindow()
        panel.present(near: NSRect(x: 200, y: 400, width: 400, height: 200), on: NSScreen.main!)
        panel.testTypeSlashAsKeyEvent()
        require(panel.testPickerVisible, "a leading slash key event opens the session picker")
        panel.dismissSessionPicker()
        require(panel.testEditorFocused, "closing the picker returns focus to the message field")
        panel.orderOut(nil)
    }

    private static func pickerRendering() {
        let sessions = [
            DSHSession(id: "a", title: "First session", cwd: "/tmp/ProjectA",
                       updatedAt: Date().timeIntervalSince1970 - 120,
                       lastPromptAt: Date().timeIntervalSince1970 - 120,
                       running: true, blank: false),
            DSHSession(id: "b", title: "Second session", cwd: "/tmp/ProjectB",
                       updatedAt: Date().timeIntervalSince1970 - 7200,
                       lastPromptAt: Date().timeIntervalSince1970 - 7200,
                       running: false, blank: false),
        ]
        let picker = SessionPickerWindow()
        picker.injectSessions(sessions, target: .recent)
        require(picker.testSummary.contains("visible=2"), "picker shows the injected sessions")
        require(picker.testSummary.contains("selected=1"), "recent target selects the newest session")
        picker.injectSessions(sessions, target: .new)
        require(picker.testSummary.contains("selected=0"), "new target selects the New session row")
        let view = picker.contentView!
        view.layoutSubtreeIfNeeded()
        let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds)!
        view.cacheDisplay(in: view.bounds, to: rep)
        write(rep.cgImage!, name: "picker.png")
        picker.orderOut(nil)
    }
}
