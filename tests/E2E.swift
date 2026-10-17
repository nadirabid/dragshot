import Cocoa
import ScreenCaptureKit

enum E2E {
    static func run() {
        Task { @MainActor in
            do {
                try FileManager.default.createDirectory(at: SelfTest.output, withIntermediateDirectories: true)
                guard Permissions.allGranted, EventTap.isRunning, let screen = NSScreen.main else {
                    throw NSError(domain: "DragShotTests", code: 1,
                                  userInfo: [NSLocalizedDescriptionKey: "App permissions or event tap missing"])
                }
                if CommandLine.arguments.contains("--ui-review") {
                    try await UITests.appearance(screen: screen)
                    print("UI review screenshots written to \(SelfTest.output.path)")
                    exit(0)
                }
                try "RUNNING".write(to: SelfTest.output.appendingPathComponent("e2e-result.txt"),
                                    atomically: true, encoding: .utf8)
                let before = Set((try? FileManager.default.contentsOfDirectory(atPath: Storage.directory)) ?? [])
                let start = CGPoint(x: screen.frame.minX + 180, y: screen.frame.minY + 200)
                let end = CGPoint(x: start.x + 400, y: start.y + 220)
                let trigger = CGEvent(keyboardEventSource: nil, virtualKey: 21, keyDown: true)!
                trigger.location = start
                trigger.flags = [.maskCommand, .maskShift]
                trigger.post(tap: .cgSessionEventTap)
                let triggerUp = CGEvent(keyboardEventSource: nil, virtualKey: 21, keyDown: false)!
                triggerUp.flags = [.maskCommand, .maskShift]
                triggerUp.post(tap: .cgSessionEventTap)
                try await Task.sleep(nanoseconds: 100_000_000)
                SelfTest.mouse(.leftMouseDown, start).post(tap: .cgSessionEventTap)
                try await Task.sleep(nanoseconds: 50_000_000)
                for i in 1...30 {
                    let t = CGFloat(i) / 30
                    let point = CGPoint(x: start.x + (end.x - start.x) * t,
                                        y: start.y + (end.y - start.y) * t)
                    SelfTest.mouse(.leftMouseDragged, point).post(tap: .cgSessionEventTap)
                    try await Task.sleep(nanoseconds: 16_666_667)
                }
                try await screenshot(screen: screen, rect: screen.frame, name: "selection-live.png")
                let released = Date()
                SelfTest.mouse(.leftMouseUp, end).post(tap: .cgSessionEventTap)
                var panel: PanelWindow?
                for _ in 0..<100 {
                    if let key = NSApp.keyWindow as? PanelWindow { panel = key; break }
                    try await Task.sleep(nanoseconds: 50_000_000)
                }
                SelfTest.require(panel != nil, "capture must produce a focused note panel")
                SelfTest.require(NSApp.keyWindow?.firstResponder is NSTextView, "note field must own typing focus")
                SelfTest.require(!NSApp.windows.contains { $0 is OverlayWindow && $0.isVisible },
                                 "selection outline must disappear as the composer opens")
                let elapsed = Date().timeIntervalSince(released)
                try await Task.sleep(nanoseconds: 250_000_000)
                Log.write("panel visible \(panel!.isVisible), on space \(panel!.isOnActiveSpace), frame \(panel!.frame)")
                try await screenshot(screen: screen, rect: panel!.frame.insetBy(dx: -12, dy: -12),
                                     name: "panel-live.png")
                guard panel!.isVisible, let editor = panel!.firstResponder as? NSTextView else {
                    throw NSError(domain: "DragShotTests", code: 3,
                                  userInfo: [NSLocalizedDescriptionKey:
                                    "Input dismissed during UI test; outside interaction interrupted the run"])
                }
                SelfTest.require(UITests.attachmentImage(in: panel!.contentView!) != nil,
                                 "real screen capture must appear as the message attachment")
                let text = "DragShot capture test \(UUID().uuidString)"
                editor.string = text
                editor.didChangeText()
                _ = panel!.textView(editor, doCommandBy: #selector(NSResponder.insertNewline(_:)))
                SelfTest.require(!NSApp.windows.contains {
                    ($0 is PanelWindow || $0 is OverlayWindow) && $0.isVisible
                }, "Return must dismiss the note panel and selection together before returning")
                let nextStart = CGPoint(x: 200, y: screen.frame.maxY - 240)
                let nextEnd = CGPoint(x: 620, y: screen.frame.maxY - 480)
                DragShot.shared.begin(at: nextStart)
                DragShot.shared.move(to: nextEnd)
                SelfTest.require(NSApp.windows.contains { $0 is OverlayWindow && $0.isVisible },
                                 "a new selection can begin immediately after saving")
                DragShot.shared.cancel()
                let after = Set(try FileManager.default.contentsOfDirectory(atPath: Storage.directory))
                let added = after.subtracting(before)
                let shots = added.filter { $0.hasSuffix(".png") }
                SelfTest.require(shots.count == 1, "this run must create exactly one new screenshot")
                let png = URL(fileURLWithPath: Storage.directory).appendingPathComponent(shots.first!)
                let note = png.deletingPathExtension().appendingPathExtension("txt")
                let savedText = try String(contentsOf: note, encoding: .utf8)
                SelfTest.require(savedText == text, "this run must save its exact note")
                let image = NSBitmapImageRep(data: try Data(contentsOf: png))!
                SelfTest.require(image.pixelsWide == Int(400 * screen.backingScaleFactor)
                                 && image.pixelsHigh == Int(220 * screen.backingScaleFactor),
                                 "captured pixels must match selection size")
                SelfTest.require(NSPasteboard.general.data(forType: .png) != nil, "image must reach clipboard")
                SelfTest.require(!NSApp.windows.contains { $0 is OverlayWindow && $0.isVisible },
                                 "cancellation must remove the next selection")
                try Data(contentsOf: png).write(to: SelfTest.output.appendingPathComponent("capture.png"),
                                                options: .atomic)
                try FileManager.default.removeItem(at: png)
                try FileManager.default.removeItem(at: note)
                // Submit in the same main-actor turn as release, before capture can run.
                DragShot.shared.begin(at: nextStart)
                DragShot.shared.move(to: nextEnd)
                DragShot.shared.end(at: nextEnd)
                let immediate = NSApp.keyWindow as? PanelWindow
                SelfTest.require(immediate?.isVisible == true && immediate?.alphaValue == 1,
                                 "release must show input synchronously at full opacity")
                let earlyEditor = immediate!.firstResponder as! NSTextView
                let earlyText = "Immediate Return \(UUID().uuidString)"
                earlyEditor.string = earlyText
                @MainActor func findSendButton(_ view: NSView) -> NSButton? {
                    if let button = view as? NSButton { return button }
                    for child in view.subviews {
                        if let button = findSendButton(child) { return button }
                    }
                    return nil
                }
                guard let sendButton = findSendButton(immediate!.contentView!) else {
                    throw NSError(domain: "DragShotTests", code: 4,
                                  userInfo: [NSLocalizedDescriptionKey: "Composer has no send button"])
                }
                sendButton.performClick(nil)
                SelfTest.require(!NSApp.windows.contains {
                    ($0 is PanelWindow || $0 is OverlayWindow) && $0.isVisible
                }, "Return before capture completes must dismiss both surfaces immediately")
                SelfTest.require(!DragShot.shared.cancel(), "submitted capture must survive subsequent Escape")
                var earlyShots: Set<String> = []
                for _ in 0..<100 {
                    let files = Set(try FileManager.default.contentsOfDirectory(atPath: Storage.directory))
                    earlyShots = Set(files.subtracting(before).filter { $0.hasSuffix(".png") })
                    if !earlyShots.isEmpty { break }
                    try await Task.sleep(nanoseconds: 50_000_000)
                }
                SelfTest.require(earlyShots.count == 1, "early Return must eventually save exactly one image")
                let earlyPNG = URL(fileURLWithPath: Storage.directory).appendingPathComponent(earlyShots.first!)
                let earlyNote = earlyPNG.deletingPathExtension().appendingPathExtension("txt")
                let earlySavedText = try String(contentsOf: earlyNote, encoding: .utf8)
                SelfTest.require(earlySavedText == earlyText, "early Return must preserve the exact note")
                try FileManager.default.removeItem(at: earlyPNG)
                try FileManager.default.removeItem(at: earlyNote)
                // A release followed immediately by Escape must not reopen a late panel,
                // even when a new selection has already started.
                let cocoaStart = CGPoint(x: 180, y: screen.frame.maxY - 200)
                let cocoaEnd = CGPoint(x: 580, y: screen.frame.maxY - 420)
                DragShot.shared.begin(at: cocoaStart)
                DragShot.shared.move(to: cocoaEnd)
                DragShot.shared.end(at: cocoaEnd)
                DragShot.shared.cancel()
                DragShot.shared.begin(at: cocoaStart)
                try await Task.sleep(nanoseconds: 500_000_000)
                SelfTest.require(!NSApp.windows.contains { $0 is PanelWindow && $0.isVisible },
                                 "cancelled capture must not reopen the note panel")
                DragShot.shared.end(at: cocoaStart)
                SelfTest.require(!NSApp.windows.contains { $0 is OverlayWindow && $0.isVisible },
                                 "a tap must not leave an overlay")
                try await UITests.run(screen: screen)
                let result = "PASS: native composer dragging, attachment composer, synchronous input, early send, outside dismissal, focus loss, app/Space switch, glass appearance, multiline input, system event tap, selection, capture, focus, note, clipboard, cancellation, cleanup; release to panel \(Int(elapsed * 1000))ms"
                try result.write(to: SelfTest.output.appendingPathComponent("e2e-result.txt"),
                                 atomically: true, encoding: .utf8)
                Log.write(result)
                exit(0)
            } catch {
                let result = "FAIL: \(error.localizedDescription)"
                try? result.write(to: SelfTest.output.appendingPathComponent("e2e-result.txt"),
                                  atomically: true, encoding: .utf8)
                Log.write(result)
                exit(1)
            }
        }
    }
    @MainActor
    static func screenshot(screen: NSScreen, rect: NSRect, name: String) async throws {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        let id = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as! CGDirectDisplayID
        let display = content.displays.first { $0.displayID == id }!
        let filter = SCContentFilter(display: display, excludingWindows: [])
        let config = SCStreamConfiguration()
        config.sourceRect = CGRect(x: rect.minX - screen.frame.minX, y: screen.frame.maxY - rect.maxY,
                                   width: rect.width, height: rect.height)
        config.width = Int(rect.width * screen.backingScaleFactor)
        config.height = Int(rect.height * screen.backingScaleFactor)
        config.showsCursor = false
        let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
        SelfTest.write(image, name: name)
    }

}
