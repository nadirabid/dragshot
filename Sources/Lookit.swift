import Cocoa

/// Selection stays in Cocoa points. Only the finished region is captured, on release.
final class Lookit {
    static let shared = Lookit()

    private enum State { case idle, aiming, armed, selecting, composing, submitting }
    private var state: State = .idle
    private var anchor = NSPoint.zero
    private var current = NSPoint.zero
    private var activeScreen: NSScreen?
    private var overlay: OverlayWindow?
    private var panel: PanelWindow?
    private var cursorHidden = false
    private var pendingImage: CGImage?
    private var pendingSubmission: String?
    private var captureTask: Task<Void, Never>?
    private var generation = 0
    private var workspaceObservers: [NSObjectProtocol] = []
    var hotkeyEnabled = false

    private init() {}

    func start() {
        Multitouch.start()
        EventTap.hotkeyEnabled = hotkeyEnabled
        EventTap.canBegin = { [weak self] in
            guard let self else { return false }
            return self.state == .idle && Permissions.hasScreenRecording
        }
        EventTap.onBegin = { [weak self] in self?.begin(at: $0) }
        EventTap.onMove = { [weak self] in self?.move(to: $0) }
        EventTap.onEnd = { [weak self] in self?.end(at: $0) }
        EventTap.onAim = { [weak self] in self?.aim(at: $0) }
        EventTap.onCancel = { [weak self] in
            guard let self else { return false }
            if self.state == .composing, let panel = self.panel, panel.isSessionPickerVisible {
                panel.dismissSessionPicker()
                return true
            }
            if self.state == .composing,
               let editor = self.panel?.firstResponder as? NSTextView, editor.hasMarkedText() {
                return false
            }
            return self.cancel()
        }
        EventTap.onOutsideInteraction = { [weak self] point in
            guard let self, self.state == .composing, let panel = self.panel else { return false }
            if panel.isSessionPickerVisible {
                return panel.handleOutsideInteraction(at: point)
            }
            guard !panel.frame.contains(point) else { return false }
            Log.write("input dismissed: outside interaction")
            return self.cancel()
        }
        EventTap.onTogglePicker = { [weak self] in
            guard let self, self.state == .composing, let panel = self.panel,
                  DSHIntegration.shared.isEnabled else { return false }
            if panel.isSessionPickerVisible {
                panel.dismissSessionPicker()
            } else {
                panel.presentSessionPicker()
            }
            return true
        }
        let workspace = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didActivateApplicationNotification,
                     NSWorkspace.activeSpaceDidChangeNotification] {
            workspaceObservers.append(workspace.addObserver(
                forName: name, object: nil, queue: .main
            ) { [weak self] _ in
                guard let self, self.state == .composing else { return }
                Log.write("input dismissed: \(name.rawValue)")
                self.cancel()
            })
        }
        EventTap.start()
        Log.write("ready — screen recording \(Permissions.hasScreenRecording), "
                  + "accessibility \(Permissions.hasAccessibility), event tap \(EventTap.isRunning)")
    }

    func aim(at point: NSPoint) {
        guard state == .idle || state == .aiming else { return }
        state = .aiming
        current = point
        guard let screen = NSScreen.screens.first(where: { NSMouseInRect(point, $0.frame, false) }) else {
            return
        }
        if activeScreen !== screen {
            overlay?.orderOut(nil)
            activeScreen = screen
            overlay = OverlayWindow(screen: screen)
        }
        showOverlay()
        render()
    }

    func begin(at point: NSPoint) {
        guard state == .idle || state == .aiming else { return }
        guard Permissions.hasScreenRecording,
              let screen = NSScreen.screens.first(where: { NSMouseInRect(point, $0.frame, false) }) else {
            reset()
            Notice.show("Lookit needs Screen Recording — grant it from the menu bar")
            return
        }
        generation += 1
        state = .armed
        activeScreen = screen
        anchor = point
        current = point
        if overlay?.screenRef !== screen {
            overlay?.orderOut(nil)
            overlay = OverlayWindow(screen: screen)
        }
        Log.write("selection began at \(Int(point.x)),\(Int(point.y))")
    }

    func move(to point: NSPoint) {
        guard state == .armed || state == .selecting, let screen = activeScreen else { return }
        // Keep the visible rectangle and captured pixels on the same display.
        current = NSPoint(x: min(max(point.x, screen.frame.minX), screen.frame.maxX),
                          y: min(max(point.y, screen.frame.minY), screen.frame.maxY))
        if state == .armed {
            guard hypot(current.x - anchor.x, current.y - anchor.y) >= 3 else { return }
            state = .selecting
            showOverlay()
        }
        render()
    }

    func end(at point: NSPoint) {
        guard state == .armed || state == .selecting else { return }
        move(to: point)
        let rect = selectionRect
        guard state == .selecting, rect.width >= 6, rect.height >= 6,
              let screen = activeScreen else {
            reset()
            return
        }

        state = .composing
        restoreCursor()
        overlay?.orderOut(nil)
        overlay = nil
        let requestGeneration = generation
        // Present synchronously: screenshot latency must never delay typing.
        showPanel(near: rect, on: screen)
        captureTask = ScreenCapture.capture(screen: screen, rect: rect) { [weak self] result in
            guard let self, self.generation == requestGeneration else { return }
            self.captureTask = nil
            switch result {
            case .success(let image):
                self.pendingImage = image
                self.panel?.attach(image)
                if let text = self.pendingSubmission {
                    self.finishSubmission(text: text, image: image)
                }
            case .failure(let error):
                Log.write("capture failed: \(error.localizedDescription)")
                self.reset()
                Notice.show("Couldn’t capture this region. \(error.localizedDescription)")
            }
        }
    }

    @discardableResult
    func cancel() -> Bool {
        guard state != .idle, state != .submitting else { return false }
        reset()
        Log.write("selection cancelled")
        return true
    }

    private var selectionRect: NSRect {
        NSRect(x: min(anchor.x, current.x), y: min(anchor.y, current.y),
               width: abs(current.x - anchor.x), height: abs(current.y - anchor.y))
    }

    private func showOverlay() {
        guard let overlay else { return }
        if !cursorHidden {
            CGDisplayHideCursor(CGMainDisplayID())
            cursorHidden = true
        }
        render()
        overlay.orderFrontRegardless()
    }

    private func render() {
        guard let overlay, let screen = activeScreen else { return }
        let origin = screen.frame.origin
        let rect = selectionRect
        overlay.selection = state == .aiming ? .zero : rect.offsetBy(dx: -origin.x, dy: -origin.y)
        overlay.pointer = NSPoint(x: current.x - origin.x, y: current.y - origin.y)
    }

    private func showPanel(near rect: NSRect, on screen: NSScreen) {
        let panel = PanelWindow()
        self.panel = panel
        panel.onSubmit = { [weak self] in self?.commit(text: $0) }
        panel.onCancel = { [weak self] in
            guard let self, self.state == .composing else { return }
            self.cancel()
        }
        // A nonactivating panel can take keyboard focus without switching the front app.
        panel.present(near: rect, on: screen)
    }

    private func commit(text: String) {
        guard state == .composing else { return }
        state = .submitting
        pendingSubmission = text
        panel?.orderOut(nil)
        overlay?.orderOut(nil)
        // Return dismisses immediately, even before the capture has completed.
        if let image = pendingImage {
            finishSubmission(text: text, image: image)
        }
    }

    private func finishSubmission(text: String, image: CGImage) {
        do {
            let saved = try Storage.save(image: image, text: text)
            try Storage.copyToPasteboard(image: image)
            Log.write("saved \(saved.name) (\(image.width)x\(image.height))")
            if DSHIntegration.shared.isEnabled {
                DSHIntegration.shared.send(image: image, text: text) { result in
                    switch result {
                    case .success(let sent):
                        let suffix = sent.title.flatMap { $0.isEmpty ? nil : " · \($0)" } ?? ""
                        Notice.show(sent.created
                            ? "Sent to new DSH session"
                            : "Sent to DSH\(suffix)")
                    case .failure(let error):
                        Notice.show("Saved locally — \(error.localizedDescription)")
                    }
                }
            }
        } catch {
            Log.write("save failed: \(error.localizedDescription)")
            state = .composing
            pendingSubmission = nil
            panel?.makeKeyAndOrderFront(nil)
            Notice.show("Couldn’t finish saving. \(error.localizedDescription)")
            return
        }
        // The agent send is asynchronous. Dismiss immediately, as the local
        // save path always has; a failure still leaves the PNG, note, and
        // clipboard contents behind and reports through the notice.
        reset()
    }

    private func reset() {
        generation += 1
        state = .idle
        captureTask?.cancel()
        captureTask = nil
        panel?.closeSessionPicker()
        panel?.orderOut(nil)
        panel = nil
        pendingImage = nil
        pendingSubmission = nil
        overlay?.orderOut(nil)
        overlay = nil
        activeScreen = nil
        restoreCursor()
    }

    private func restoreCursor() {
        guard cursorHidden else { return }
        CGDisplayShowCursor(CGMainDisplayID())
        cursorHidden = false
    }
}
