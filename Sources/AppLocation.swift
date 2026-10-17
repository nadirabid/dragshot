import Cocoa

/// Permission requests must come from the installed app, never an accidentally opened build.
enum AppLocation {
    static let systemURL = URL(fileURLWithPath: "/Applications/Lookit.app")
    static let userURL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Applications/Lookit.app")

    static func isInstalled(_ url: URL) -> Bool {
        let path = url.resolvingSymlinksInPath().standardizedFileURL.path
        return [systemURL, userURL].contains { $0.standardizedFileURL.path == path }
            || UserDefaults.standard.string(forKey: "installedAppPath") == path
    }

    static func prepareLaunch() -> Bool {
        #if LOOKIT_TESTING
        return true
        #else
        let current = Bundle.main.bundleURL
        guard !isInstalled(current), !CommandLine.arguments.contains("--development") else { return true }
        let fm = FileManager.default
        let configured = UserDefaults.standard.string(forKey: "installedAppPath").map { URL(fileURLWithPath: $0) }
        let installed = ([configured].compactMap { $0 } + [systemURL, userURL]).first {
            Bundle(url: $0)?.bundleIdentifier == "local.lookit"
        }
        if let installed {
            openInstalled(installed)
            return false
        }
        let alert = NSAlert()
        alert.messageText = "Install Lookit in Applications"
        alert.informativeText = "Keep Lookit in one place so macOS permissions apply to the right app. Setup will open after installation."
        alert.addButton(withTitle: "Install Lookit")
        alert.addButton(withTitle: "Quit")
        NSApp.activate(ignoringOtherApps: true)
        guard alert.runModal() == .alertFirstButtonReturn else { NSApp.terminate(nil); return false }
        let destination = fm.isWritableFile(atPath: "/Applications") ? systemURL : userURL
        do {
            try fm.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
            try fm.copyItem(at: current, to: destination)
            openInstalled(destination)
        } catch {
            let failure = NSAlert(error: error)
            failure.runModal()
            NSApp.terminate(nil)
        }
        return false
        #endif
    }

    private static func openInstalled(_ url: URL) {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.arguments = ["--setup"]
        NSWorkspace.shared.openApplication(at: url, configuration: configuration) { app, error in
            DispatchQueue.main.async {
                if let error { NSAlert(error: error).runModal() }
                NSApp.terminate(nil)
            }
        }
    }
}
