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
        menu.addItem(NSMenuItem(title: "Open Captures Folder",
                                action: #selector(openFolder), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Reveal Log",
                                action: #selector(revealLog), keyEquivalent: ""))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit DragShot",
                                action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))

        for entry in menu.items where entry.action != nil && entry.target == nil {
            entry.target = self
        }
        // Quit keeps the standard target.
        menu.items.last?.target = NSApp

        statusItem?.menu = menu
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
#if DRAGSHOT_TESTING
if CommandLine.arguments.contains("--e2e") {
    delegate.runE2EOnLaunch = true
    DragShot.shared.hotkeyEnabled = true
}
#endif
app.run()
