import Cocoa

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private var setupWindow: SettingsWindow?
    private var permissionTimer: Timer?
    private var lastSetupStatus: SetupStatus?
    private var lastLoginStatus: Int?
    #if LOOKIT_TESTING
    var runE2EOnLaunch = false
    #endif

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        guard AppLocation.prepareLaunch() else { return }
        buildStatusItem()
        Lookit.shared.start()
        DSHIntegration.shared.refreshHealth()
        // A standalone .app carries its bridge as well. Do not initialize DSH
        // itself or change the chosen harness; only repair a missing payload.
        let profile = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".dsh/profiles/desktop")
        if Bundle.main.bundleIdentifier == "local.lookit" && !DSHIntegration.shared.bridgeInstalled && FileManager.default.fileExists(atPath: profile.path) {
            DSHIntegration.shared.installBridge { error in
                if let error { Log.write("Bridge setup: \(error.localizedDescription)") }
            }
        }
        Diagnostics.write()
        Log.write("three-finger drag setting: \(Diagnostics.threeFingerDrag)")

        // Present guidance once when setup is incomplete, without raising system prompts.
        let explicitSetup = CommandLine.arguments.contains("--request-permissions")
            || CommandLine.arguments.contains("--setup")
        if explicitSetup || (!SetupStatus.current.ready
                             && !UserDefaults.standard.bool(forKey: "didShowSetup")) {
            showSetup()
        }
        permissionTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            self?.updatePermissionState()
        }

        #if LOOKIT_TESTING
        if runE2EOnLaunch { E2E.run() }
        #endif
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showSettings()
        return true
    }

    func applicationWillTerminate(_ notification: Notification) {
        permissionTimer?.invalidate()
        Lookit.shared.cancel()
    }

    // MARK: - Menu bar

    private func buildStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.image = NSImage(
            systemSymbolName: "crop",
            accessibilityDescription: "Lookit"
        )
        item.button?.image?.isTemplate = true
        statusItem = item
        refreshMenu()
    }

    func refreshMenu() {
        let menu = NSMenu()
        let settings = NSMenuItem(title: "Settings…", action: #selector(showSettings), keyEquivalent: ",")
        settings.target = self
        menu.addItem(settings)
        let permissions = NSMenuItem(title: "Configure Permissions…", action: #selector(showSetup), keyEquivalent: "")
        permissions.target = self
        menu.addItem(permissions)
        let login = NSMenuItem(title: "Launch at Login", action: #selector(toggleLogin), keyEquivalent: "")
        login.target = self
        login.state = LaunchAtLogin.enabled ? .on : LaunchAtLogin.needsApproval ? .mixed : .off
        menu.addItem(login)
        menu.addItem(.separator())
        let quit = NSMenuItem(title: "Quit Lookit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        quit.target = NSApp
        menu.addItem(quit)
        statusItem?.menu = menu
        Diagnostics.write()
    }

    @objc private func toggleLogin() {
        LaunchAtLogin.toggle()
        refreshMenu()
        setupWindow?.refreshPreferences()
    }

    @objc private func showSettings() { presentSettings(page: nil) }
    @objc private func showSetup() { presentSettings(page: .permissions) }

    private func presentSettings(page: SettingsPage?) {
        Lookit.shared.cancel()
        if setupWindow == nil {
            setupWindow = SettingsWindow()
            Lookit.shared.setupWindow = setupWindow?.window
            setupWindow?.onChange = { [weak self] in self?.refreshMenu() }
            setupWindow?.onRestart = { [weak self] in self?.restartApp() }
        }
        UserDefaults.standard.set(true, forKey: "didShowSetup")
        if let page { setupWindow?.selectPage(page) }
        setupWindow?.present()
    }

    private func restartApp() {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = true
        configuration.arguments = ["--setup"] + (Lookit.shared.hotkeyEnabled ? ["--hotkey"] : [])
        NSWorkspace.shared.openApplication(at: Bundle.main.bundleURL, configuration: configuration) {
            [weak self] application, error in
            DispatchQueue.main.async {
                if application != nil && error == nil { NSApp.terminate(nil) }
                else { self?.setupWindow?.showRestartError() }
            }
        }
    }

    private func updatePermissionState() {
        // Attach once after the user grants access; never rebuild the whole capture controller.
        let status = SetupStatus.current
        if status.accessibility && !status.listener && (lastSetupStatus?.accessibility != true || lastSetupStatus?.inputMonitoring != status.inputMonitoring) {
            EventTap.start()
        }
        DSHIntegration.shared.refreshHealth()
        setupWindow?.refreshPreferences()
        if lastLoginStatus != LaunchAtLogin.status.rawValue {
            lastLoginStatus = LaunchAtLogin.status.rawValue
            refreshMenu()
        }
        Diagnostics.write()
        let updated = SetupStatus.current
        if updated != lastSetupStatus {
            lastSetupStatus = updated
            refreshMenu()
            setupWindow?.refresh(updated)
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

#if LOOKIT_TESTING
// Clean README capture: the real AppKit glass UI and sample content over a
// caller-supplied macOS wallpaper. No personal desktop content is included.
if let index = CommandLine.arguments.firstIndex(of: "--readme-shot"),
   CommandLine.arguments.indices.contains(index + 1) {
    app.setActivationPolicy(.accessory)
    app.finishLaunching()
    ReadmeShot.run(backgroundPath: CommandLine.arguments[index + 1])
    app.run()
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
Lookit.shared.hotkeyEnabled = CommandLine.arguments.contains("--hotkey")
#if LOOKIT_TESTING
if CommandLine.arguments.contains("--e2e") {
    delegate.runE2EOnLaunch = true
    Lookit.shared.hotkeyEnabled = true
}
#endif
app.run()
