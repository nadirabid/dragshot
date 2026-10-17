import Cocoa

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    #if DRAGSHOT_TESTING
    var runE2EOnLaunch = false
    #endif

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        buildStatusItem()
        DragShot.shared.start()

        // Used once, on first run, to raise the two grants. Never automatic: launching the app
        // at login should not produce dialogs.
        if CommandLine.arguments.contains("--request-permissions") {
            if !Permissions.hasScreenRecording { Permissions.requestScreenRecording() }
            if !Permissions.hasAccessibility { Permissions.requestAccessibility() }
            scheduleMenuRefresh()
        }

        #if DRAGSHOT_TESTING
        if runE2EOnLaunch { E2E.run() }
        #endif
    }

    func applicationWillTerminate(_ notification: Notification) {
        DragShot.shared.cancel()
    }

    // MARK: - Menu bar

    private func buildStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.image = NSImage(
            systemSymbolName: "crop",
            accessibilityDescription: "DragShot"
        )
        item.button?.image?.isTemplate = true
        statusItem = item
        refreshMenu()
    }

    /// The menu states permission status plainly rather than nagging with dialogs at launch.
    func refreshMenu() {
        let menu = NSMenu()

        let header = NSMenuItem(title: "DragShot", action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)
        menu.addItem(.separator())

        let threeFinger = NSMenuItem(
            title: "Three-finger drag: draw a box to capture",
            action: nil, keyEquivalent: "")
        threeFinger.isEnabled = false
        menu.addItem(threeFinger)

        if DragShot.shared.hotkeyEnabled {
            let hotkey = NSMenuItem(title: "Debug trigger: ⌘⇧4", action: nil, keyEquivalent: "")
            hotkey.isEnabled = false
            menu.addItem(hotkey)
        }

        let multitouch = NSMenuItem(
            title: "Trackpad reader: \(Multitouch.isAvailable ? "running" : "unavailable")",
            action: nil, keyEquivalent: "")
        multitouch.isEnabled = false
        menu.addItem(multitouch)

        menu.addItem(.separator())

        if Permissions.hasScreenRecording {
            let ok = NSMenuItem(title: "✓ Screen Recording", action: nil, keyEquivalent: "")
            ok.isEnabled = false
            menu.addItem(ok)
        } else {
            menu.addItem(NSMenuItem(title: "Grant Screen Recording…",
                                    action: #selector(grantScreenRecording),
                                    keyEquivalent: ""))
        }

        if Permissions.hasAccessibility {
            let ok = NSMenuItem(title: "✓ Accessibility", action: nil, keyEquivalent: "")
            ok.isEnabled = false
            menu.addItem(ok)
        } else {
            menu.addItem(NSMenuItem(title: "Grant Accessibility…",
                                    action: #selector(grantAccessibility),
                                    keyEquivalent: ""))
        }

        if Permissions.allGranted && EventTap.isRunning && Multitouch.isAvailable {
            let ready = NSMenuItem(title: "✓ Ready", action: nil, keyEquivalent: "")
            ready.isEnabled = false
            menu.addItem(ready)
        }

        menu.addItem(.separator())
        addAgentItems(to: menu)

        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Open Captures Folder",
                                action: #selector(openFolder), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Reveal Log",
                                action: #selector(revealLog), keyEquivalent: ""))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit DragShot",
                                action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))

        wireMenuTargets(menu)
        // Quit keeps the standard target.
        menu.items.last?.target = NSApp

        statusItem?.menu = menu
    }

    /// The agent controls live beside the permission state, not in a second
    /// menu. A real settings window can grow from this without changing the
    /// defaults the capture path reads.
    private func addAgentItems(to menu: NSMenu) {
        let integration = DSHIntegration.shared

        let send = NSMenuItem(title: "Send captures to DSH",
                              action: #selector(toggleDSH), keyEquivalent: "")
        send.state = integration.isEnabled ? .on : .off
        menu.addItem(send)

        let targetItem = NSMenuItem(title: "DSH target", action: nil, keyEquivalent: "")
        let targetMenu = NSMenu(title: "DSH target")
        let recent = NSMenuItem(title: "Most recent session",
                                action: #selector(useRecentDSHTarget), keyEquivalent: "")
        recent.state = integration.target == .recent ? .on : .off
        let fresh = NSMenuItem(title: "New chat",
                               action: #selector(useNewDSHTarget), keyEquivalent: "")
        fresh.state = integration.target == .new ? .on : .off
        targetMenu.addItem(recent)
        targetMenu.addItem(fresh)
        if case .session(_, let title) = integration.target {
            let pinned = NSMenuItem(title: "Pinned: \(title)", action: nil, keyEquivalent: "")
            pinned.state = .on
            pinned.isEnabled = false
            targetMenu.addItem(.separator())
            targetMenu.addItem(pinned)
        }
        targetItem.submenu = targetMenu
        targetItem.isEnabled = integration.isEnabled
        menu.addItem(targetItem)

        let activate = NSMenuItem(title: "Open DSH after send",
                                  action: #selector(toggleDSHActivation), keyEquivalent: "")
        activate.state = integration.activateAfterSend ? .on : .off
        activate.isEnabled = integration.isEnabled
        menu.addItem(activate)

        let status = NSMenuItem(title: "DSH bridge: \(integration.bridgeStatusText)",
                                action: nil, keyEquivalent: "")
        status.isEnabled = false
        menu.addItem(status)

        menu.addItem(NSMenuItem(title: "Open DSH",
                                action: #selector(openDSH), keyEquivalent: ""))
    }

    /// Actions in submenus need the same target wiring as top-level items.
    private func wireMenuTargets(_ menu: NSMenu) {
        for item in menu.items {
            if let submenu = item.submenu { wireMenuTargets(submenu) }
            if item.action != nil && item.target == nil { item.target = self }
        }
    }

    @objc private func toggleDSH() {
        let integration = DSHIntegration.shared
        integration.isEnabled.toggle()
        if integration.isEnabled {
            switch integration.bridgeState {
            case .ready:
                break
            case .appNotRunning:
                Notice.show("DSH will open on the first capture.")
            case .bridgeMissing:
                Notice.show("DSH bridge is not loaded. Restart DSH once.")
            case .notInstalled:
                Notice.show("DeepSeek Harness is not installed.")
            }
        }
        refreshMenu()
    }

    @objc private func useRecentDSHTarget() {
        DSHIntegration.shared.target = .recent
        refreshMenu()
    }

    @objc private func useNewDSHTarget() {
        DSHIntegration.shared.target = .new
        refreshMenu()
    }

    @objc private func toggleDSHActivation() {
        DSHIntegration.shared.activateAfterSend.toggle()
        refreshMenu()
    }

    @objc private func openDSH() {
        if !DSHIntegration.shared.openDSH() {
            Notice.show("DeepSeek Harness is not installed.")
        }
        refreshMenu()
    }

    @objc private func grantScreenRecording() {
        Permissions.requestScreenRecording()
        scheduleMenuRefresh()
    }

    @objc private func grantAccessibility() {
        Permissions.requestAccessibility()
        scheduleMenuRefresh()
    }

    @objc private func openFolder() {
        try? FileManager.default.createDirectory(atPath: Storage.directory, withIntermediateDirectories: true)
        NSWorkspace.shared.open(URL(fileURLWithPath: Storage.directory))
    }

    @objc private func revealLog() {
        let url = URL(fileURLWithPath: Log.path)
        if FileManager.default.fileExists(atPath: Log.path) {
            NSWorkspace.shared.activateFileViewerSelecting([url])
        } else {
            NSWorkspace.shared.open(url.deletingLastPathComponent())
        }
    }

    /// Permissions are granted in System Settings, so poll briefly to catch the flip.
    private func scheduleMenuRefresh() {
        for delay in [1.0, 4.0, 10.0] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                self?.refreshMenu()
            }
        }
    }
}

// MARK: - Entry point

let app = NSApplication.shared
if CommandLine.arguments.contains("--status") {
    print("screen recording: \(Permissions.hasScreenRecording)")
    print("accessibility: \(Permissions.hasAccessibility)")
    exit(Permissions.allGranted ? 0 : 1)
}

#if DRAGSHOT_TESTING
// Clean README capture: the real AppKit glass UI, fake session data, and a
// caller-supplied macOS wallpaper. No personal desktop content is included.
if let index = CommandLine.arguments.firstIndex(of: "--readme-shot"),
   CommandLine.arguments.indices.contains(index + 1) {
    app.setActivationPolicy(.accessory)
    app.finishLaunching()
    ReadmeShot.run(backgroundPath: CommandLine.arguments[index + 1])
    app.run()
}

// Visual review path for the composer + picker. It uses the real DSH bridge
// when available and captures the views directly, without ScreenCaptureKit.
if CommandLine.arguments.contains("--picker-review") {
    app.setActivationPolicy(.accessory)
    app.finishLaunching()
    let screen = NSScreen.main!
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
    image.unlockFocus()
    guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
        exit(2)
    }
    DSHIntegration.shared.isEnabled = true
    let panel = PanelWindow()
    let rect = NSRect(x: screen.frame.minX + 180, y: screen.frame.minY + 200,
                      width: 400, height: 220)
    panel.present(near: rect, on: screen)
    panel.attach(cgImage)
    try? FileManager.default.createDirectory(at: SelfTest.output, withIntermediateDirectories: true)
    print("review: panel presented")
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
        print("review: opening picker")
        panel.presentSessionPicker()
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            print("review: snapshotting")
            let picker = NSApp.windows.compactMap { $0 as? SessionPickerWindow }.first
            print("review: picker window", picker != nil)
            func snapshot(_ view: NSView, name: String) {
                let bounds = view.bounds
                guard bounds.width > 0, bounds.height > 0,
                      let rep = view.bitmapImageRepForCachingDisplay(in: bounds) else {
                    print("review: no rep for", name); return
                }
                view.cacheDisplay(in: bounds, to: rep)
                if let png = rep.representation(using: .png, properties: [:]) {
                    do {
                        try png.write(to: SelfTest.output.appendingPathComponent(name))
                        print("review: wrote", name)
                    } catch { print("review: write error", error) }
                }
            }
            if let picker {
                snapshot(picker.contentView!, name: "picker-view.png")
            }
            snapshot(panel.contentView!, name: "panel-view.png")
            let union = panel.frame.union(picker?.frame ?? .zero).insetBy(dx: -28, dy: -28)
            Task { @MainActor in
                try? await E2E.screenshot(screen: screen, rect: union, name: "picker-live2.png")
                print("review: screen captured")
                exit(0)
            }
            // Fallback if ScreenCaptureKit is slow.
            DispatchQueue.main.asyncAfter(deadline: .now() + 8) {
                print("review: capture timeout")
                exit(0)
            }
        }
    }
    app.run()
}

// A tiny diagnostic path for the DSH adapter: send one existing PNG through
// the real Unix-socket client without starting the gesture engine.
if let sendIndex = CommandLine.arguments.firstIndex(of: "--dsh-send"),
   sendIndex + 1 < CommandLine.arguments.count,
   let source = NSImage(contentsOfFile: CommandLine.arguments[sendIndex + 1]),
   let image = source.cgImage(forProposedRect: nil, context: nil, hints: nil) {
    let text = sendIndex + 2 < CommandLine.arguments.count
        ? CommandLine.arguments[sendIndex + 2]
        : ""
    app.setActivationPolicy(.accessory)
    app.finishLaunching()
    DSHIntegration.shared.isEnabled = true
    if let socketIndex = CommandLine.arguments.firstIndex(of: "--dsh-socket"),
       socketIndex + 1 < CommandLine.arguments.count {
        DSHIntegration.shared.socketPathOverride = CommandLine.arguments[socketIndex + 1]
    }
    var finished = false
    DSHIntegration.shared.send(image: image, text: text) { result in
        switch result {
        case .success(let sent):
            print("OK session=\(sent.sessionID) created=\(sent.created) target=\(sent.target) title=\(sent.title ?? "")")
        case .failure(let error):
            print("ERROR \(error.localizedDescription)")
        }
        finished = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { exit(0) }
    }
    while !finished {
        RunLoop.current.run(until: Date().addingTimeInterval(0.05))
    }
    exit(0)
}

if CommandLine.arguments.contains("--selftest") {
    app.setActivationPolicy(.accessory)
    app.finishLaunching()
    SelfTest.run()
    exit(0)
}
#endif

let delegate = AppDelegate()
app.delegate = delegate
DragShot.shared.hotkeyEnabled = CommandLine.arguments.contains("--hotkey")
if CommandLine.arguments.contains("--dsh-enable") {
    DSHIntegration.shared.isEnabled = true
}
if let socketIndex = CommandLine.arguments.firstIndex(of: "--dsh-socket"),
   socketIndex + 1 < CommandLine.arguments.count {
    DSHIntegration.shared.socketPathOverride = CommandLine.arguments[socketIndex + 1]
    DSHIntegration.shared.isEnabled = true
}
#if DRAGSHOT_TESTING
if CommandLine.arguments.contains("--e2e") {
    delegate.runE2EOnLaunch = true
    DragShot.shared.hotkeyEnabled = true
}
#endif
app.run()
