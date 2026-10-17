import Cocoa

enum UITests {
    @MainActor
    static func run(screen: NSScreen) async throws {
        let start = NSPoint(x: screen.frame.minX + 200, y: screen.frame.maxY - 240)
        let end = NSPoint(x: start.x + 360, y: start.y - 200)
        // Exercise the contact-frame handoff while deliberately withholding mouse-up.
        Multitouch.updateContacts(3)
        _ = EventTap.handle(type: .leftMouseDown, event: SelfTest.mouse(.leftMouseDown, quartz(start)))
        _ = EventTap.handle(type: .leftMouseDragged, event: SelfTest.mouse(.leftMouseDragged, quartz(end)))
        Multitouch.updateContacts(0)
        await withCheckedContinuation { continuation in
            DispatchQueue.main.async { continuation.resume() }
        }
        SelfTest.require(NSApp.keyWindow is PanelWindow && NSApp.keyWindow?.firstResponder is NSTextView,
                         "last finger lift must open and focus input before mouse-up arrives")
        Lookit.shared.cancel()
        SelfTest.require(EventTap.handle(type: .leftMouseUp,
                                        event: SelfTest.mouse(.leftMouseUp, quartz(end))) == nil,
                         "delayed mouse-up must be consumed after input dismissal")
        SelfTest.require(!selectionVisible && !(NSApp.keyWindow is PanelWindow),
                         "delayed mouse-up must not reopen cancelled input")

        for type: CGEventType in [.leftMouseDown, .rightMouseDown, .otherMouseDown, .scrollWheel] {
            let panel = try await compose(from: start, to: end)
            let inside = CGEvent(source: nil)!
            inside.type = type
            inside.location = quartz(NSPoint(x: panel.frame.midX, y: panel.frame.midY))
            SelfTest.require(EventTap.handle(type: type, event: inside) != nil,
                             "interaction inside the input must pass through")
            SelfTest.require(panel.isVisible, "interaction inside the input must keep it open")
            let outside = CGEvent(source: nil)!
            outside.type = type
            outside.location = quartz(NSPoint(x: panel.frame.maxX + 20, y: panel.frame.midY))
            SelfTest.require(EventTap.handle(type: type, event: outside) != nil,
                             "dismissal must pass the original interaction through")
            SelfTest.require(!panel.isVisible && !selectionVisible,
                             "outside click or scroll must dismiss both surfaces")
        }

        let focused = try await compose(from: start, to: end)
        let other = PanelWindow()
        other.present(near: NSRect(origin: start, size: NSSize(width: 100, height: 50)), on: screen)
        SelfTest.require(!focused.isVisible && !selectionVisible,
                         "losing keyboard focus must dismiss the old input and selection")
        other.orderOut(nil)

        for name in [NSWorkspace.didActivateApplicationNotification,
                     NSWorkspace.activeSpaceDidChangeNotification] {
            let panel = try await compose(from: start, to: end)
            NSWorkspace.shared.notificationCenter.post(name: name, object: NSWorkspace.shared)
            SelfTest.require(!panel.isVisible && !selectionVisible,
                             "switching app or Space must dismiss both surfaces")
        }

        // Clicking away while the screenshot is in flight must prevent late presentation.
        Lookit.shared.begin(at: start)
        Lookit.shared.move(to: end)
        Lookit.shared.end(at: end)
        let click = CGEvent(source: nil)!
        click.type = .leftMouseDown
        click.location = quartz(start)
        SelfTest.require(EventTap.handle(type: .leftMouseDown, event: click) != nil,
                         "click during capture must pass through")
        try await Task.sleep(nanoseconds: 300_000_000)
        SelfTest.require(!selectionVisible && !(NSApp.keyWindow is PanelWindow),
                         "capture must not reopen after clicking away")
        // Thin, tall, and edge selections must keep the entire composer on screen.
        for size in [NSSize(width: 900, height: 8), NSSize(width: 8, height: 900)] {
            let panel = PanelWindow()
            let edge = NSRect(x: screen.visibleFrame.maxX - size.width,
                              y: screen.visibleFrame.minY, width: size.width, height: size.height)
            panel.present(near: edge, on: screen)
            let editor = panel.firstResponder as! NSTextView
            editor.string = "Keep this message while the image arrives"
            editor.didChangeText()
            let before = panel.frame
            panel.attach(attachmentFixture())
            SelfTest.require(panel.frame == before && screen.visibleFrame.contains(panel.frame),
                             "edge attachment must fit the display without moving on arrival")
            SelfTest.require(editor.string == "Keep this message while the image arrives"
                             && panel.firstResponder === editor,
                             "attachment must preserve typing already in progress")
            panel.orderOut(nil)
        }
        try await composerDragging(screen: screen)
        try await appearance(screen: screen)
    }

    @MainActor
    private static func composerDragging(screen: NSScreen) async throws {
        let panel = PanelWindow()
        defer { panel.orderOut(nil) }
        let selection = NSRect(x: screen.visibleFrame.midX - 180,
                               y: screen.visibleFrame.midY + 120, width: 360, height: 200)
        panel.present(near: selection, on: screen)
        panel.attach(attachmentFixture())
        try await Task.sleep(nanoseconds: 150_000_000)
        let editor = panel.firstResponder as! NSTextView
        for (point, delta) in [(NSPoint(x: 390, y: -60), NSPoint(x: 60, y: 40)),
                               (NSPoint(x: 70, y: -60), NSPoint(x: -30, y: 25))] {
            let before = panel.frame
            let start = NSPoint(x: before.minX + point.x, y: before.maxY + point.y)
            try await drag(from: start, to: NSPoint(x: start.x + delta.x, y: start.y + delta.y))
            Log.write("drag check: before=\(before), after=\(panel.frame), delta=\(delta)")
            SelfTest.require(abs(panel.frame.minX - before.minX - delta.x) < 3
                             && abs(panel.frame.minY - before.minY - delta.y) < 3,
                             "background and attachment must move the composer with native mouse dragging")
            SelfTest.require(panel.isVisible && panel.firstResponder === editor,
                             "moving composer must preserve typing focus")
        }
        let moved = panel.frame
        editor.string = "A message after moving the composer.\nAnother line.\nOne more line."
        editor.didChangeText()
        SelfTest.require(abs(panel.frame.minX - moved.minX) < 1
                         && abs(panel.frame.maxY - moved.maxY) < 1,
                         "growing input must preserve the moved top edge and horizontal position")
        let beforeSelection = panel.frame
        let textPoint = panel.convertPoint(toScreen: editor.convert(NSPoint(x: 3, y: 10), to: nil))
        try await drag(from: textPoint, to: NSPoint(x: textPoint.x + 100, y: textPoint.y))
        SelfTest.require(panel.frame == beforeSelection && editor.selectedRange().length > 0,
                         "dragging text must select text instead of moving the composer")
    }

    @MainActor
    private static func drag(from start: NSPoint, to end: NSPoint) async throws {
        let from = quartz(start)
        let to = quartz(end)
        // Native window tracking runs a nested loop; feed its events independently.
        await withCheckedContinuation { continuation in
            DispatchQueue.global().async {
                SelfTest.mouse(.mouseMoved, from).post(tap: .cgSessionEventTap)
                Thread.sleep(forTimeInterval: 0.05)
                SelfTest.mouse(.leftMouseDown, from).post(tap: .cgSessionEventTap)
                Thread.sleep(forTimeInterval: 0.05)
                for step in 1...12 {
                    let fraction = CGFloat(step) / 12
                    let point = CGPoint(x: from.x + (to.x - from.x) * fraction,
                                        y: from.y + (to.y - from.y) * fraction)
                    SelfTest.mouse(.leftMouseDragged, point).post(tap: .cgSessionEventTap)
                    Thread.sleep(forTimeInterval: 0.016)
                }
                SelfTest.mouse(.leftMouseUp, to).post(tap: .cgSessionEventTap)
                DispatchQueue.main.async { continuation.resume() }
            }
        }
        // WindowServer processes native dragging outside the app's event queue.
        try await Task.sleep(nanoseconds: 150_000_000)
    }

    private static var selectionVisible: Bool {
        NSApp.windows.contains { $0 is OverlayWindow && $0.isVisible }
    }

    private static func quartz(_ point: NSPoint) -> CGPoint {
        CGPoint(x: point.x, y: CGDisplayBounds(CGMainDisplayID()).height - point.y)
    }

    @MainActor
    private static func compose(from start: NSPoint, to end: NSPoint) async throws -> PanelWindow {
        Lookit.shared.begin(at: start)
        Lookit.shared.move(to: end)
        Lookit.shared.end(at: end)
        guard let panel = NSApp.keyWindow as? PanelWindow else {
            throw NSError(domain: "LookitTests", code: 2,
                          userInfo: [NSLocalizedDescriptionKey: "Release did not immediately focus input"])
        }
        SelfTest.require(panel.firstResponder is NSTextView && panel.isVisible && panel.alphaValue == 1,
                         "input must be visible and focused before asynchronous capture starts")
        SelfTest.require(!selectionVisible, "release must remove the selection outline immediately")
        return panel
    }

    static func attachmentImage(in view: NSView) -> NSImage? {
        if let image = (view as? NSImageView)?.image { return image }
        for child in view.subviews {
            if let image = attachmentImage(in: child) { return image }
        }
        return nil
    }

    private static func attachmentFixture() -> CGImage {
        let image = NSImage(size: NSSize(width: 720, height: 420))
        image.lockFocus()
        NSColor(srgbRed: 0.96, green: 0.97, blue: 0.99, alpha: 1).setFill()
        NSRect(x: 0, y: 0, width: 720, height: 420).fill()
        ("Weekly overview" as NSString).draw(at: NSPoint(x: 40, y: 348), withAttributes: [
            .font: NSFont.systemFont(ofSize: 30, weight: .semibold), .foregroundColor: NSColor.black,
        ])
        ("Activity over the last seven days" as NSString).draw(at: NSPoint(x: 40, y: 310), withAttributes: [
            .font: NSFont.systemFont(ofSize: 18), .foregroundColor: NSColor.gray,
        ])
        for (index, height) in [90, 135, 110, 180, 160, 220, 195].enumerated() {
            NSColor(srgbRed: 0.25, green: 0.48, blue: 0.91, alpha: 1).setFill()
            NSBezierPath(roundedRect: NSRect(x: 40 + index * 92, y: 40, width: 56, height: height),
                         xRadius: 8, yRadius: 8).fill()
        }
        image.unlockFocus()
        return image.cgImage(forProposedRect: nil, context: nil, hints: nil)!
    }

    @MainActor
    static func appearance(screen: NSScreen) async throws {
        let frame = NSRect(x: screen.visibleFrame.midX - 340,
                           y: screen.visibleFrame.midY - 260, width: 680, height: 520)
        let backdrop = NSWindow(contentRect: frame, styleMask: .borderless,
                                backing: .buffered, defer: false)
        backdrop.level = NSWindow.Level(rawValue: Int(CGShieldingWindowLevel()) - 1)
        backdrop.isReleasedWhenClosed = false
        backdrop.hasShadow = false
        backdrop.ignoresMouseEvents = true
        defer { backdrop.orderOut(nil) }
        let styles: [(String, NSColor, NSAppearance.Name)] = [
            ("light", NSColor(srgbRed: 0.92, green: 0.94, blue: 0.96, alpha: 1), .aqua),
            ("dark", NSColor(srgbRed: 0.08, green: 0.10, blue: 0.13, alpha: 1), .darkAqua),
            ("color", NSColor(srgbRed: 0.20, green: 0.42, blue: 0.78, alpha: 1), .aqua),
        ]
        let selection = NSRect(x: frame.midX - 180, y: frame.midY + 60, width: 360, height: 210)
        let fixture = attachmentFixture()
        for (name, background, appearance) in styles {
            let panel = PanelWindow()
            backdrop.backgroundColor = background
            backdrop.orderFrontRegardless()
            panel.appearance = NSAppearance(named: appearance)
            panel.present(near: selection, on: screen)
            let editor = panel.firstResponder as! NSTextView
            SelfTest.require(editor.string.isEmpty, "new editor starts blank")
            let initialFrame = panel.frame
            panel.attach(fixture)
            SelfTest.require(panel.frame == initialFrame && panel.firstResponder === editor,
                             "attachment arrival must not move the composer or steal typing focus")
            try await Task.sleep(nanoseconds: 300_000_000)
            try await E2E.screenshot(screen: screen, rect: panel.frame.insetBy(dx: -24, dy: -24),
                                     name: "input-\(name).png")
            editor.string = "Help me understand this"
            editor.didChangeText()
            try await Task.sleep(nanoseconds: 160_000_000)
            try await E2E.screenshot(screen: screen, rect: panel.frame.insetBy(dx: -24, dy: -24),
                                     name: "input-\(name)-text.png")
            panel.orderOut(nil)
        }

        let panel = PanelWindow()
        defer { panel.orderOut(nil) }
        panel.appearance = NSAppearance(named: .darkAqua)
        panel.present(near: selection, on: screen)
        panel.attach(fixture)
        let editor = panel.firstResponder as! NSTextView
        editor.string = Array(repeating: "A longer instruction that should wrap naturally.", count: 12)
            .joined(separator: "\n")
        editor.didChangeText()
        try await Task.sleep(nanoseconds: 200_000_000)
        SelfTest.require(panel.frame.height <= 322 && screen.visibleFrame.contains(panel.frame),
                         "long input must scroll within a bounded panel on screen")
        SelfTest.require(panel.firstResponder === editor, "growing input must retain typing focus")
        try await E2E.screenshot(screen: screen, rect: panel.frame.insetBy(dx: -24, dy: -24),
                                 name: "input-multiline.png")
    }
}
