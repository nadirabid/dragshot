import Cocoa

/// A small, local status file for installers and bug reports. It contains no
/// captures, note text, session titles, or conversation data.
enum Diagnostics {
    static let directory = NSString(string: "~/Library/Application Support/Lookit").expandingTildeInPath
    static let path = (directory as NSString).appendingPathComponent("diagnostics.txt")

    /// The system setting is global: `TrackpadThreeFingerDrag` under either the
    /// built-in or Bluetooth trackpad preferences. The app itself does not own it.
    static var threeFingerDrag: String {
        let domains = [
            "com.apple.AppleMultitouchTrackpad",
            "com.apple.driver.AppleBluetoothMultitouch.trackpad",
        ]
        let values = domains.compactMap { domain -> Bool? in
            guard let value = CFPreferencesCopyValue(
                "TrackpadThreeFingerDrag" as CFString,
                domain as CFString,
                kCFPreferencesCurrentUser,
                kCFPreferencesAnyHost
            ) else { return nil }
            return (value as? NSNumber)?.boolValue
        }
        if values.contains(true) { return "enabled" }
        if !values.isEmpty { return "disabled" }
        return "unknown"
    }

    static var text: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        return """
        Lookit \(version)
        app: \(Bundle.main.bundlePath)
        bundle: \(Bundle.main.bundleIdentifier ?? "?")
        pid: \(ProcessInfo.processInfo.processIdentifier)
        updated: \(ISO8601DateFormatter().string(from: Date()))
        screen recording: \(Permissions.hasScreenRecording)
        accessibility: \(Permissions.hasAccessibility)
        input monitoring: \(Permissions.hasInputMonitoring)
        event control: \(Permissions.hasEventControl)
        event tap: \(EventTap.isRunning)
        multitouch: \(Multitouch.isAvailable)
        three-finger drag: \(threeFingerDrag)
        harness: \(HarnessIntegration.destination.rawValue)
        open after sending: \(DSHIntegration.shared.activateAfterSend)
        captures: \(Storage.directory)
        log: \(Log.path)
        """
    }

    static func write() {
        try? FileManager.default.createDirectory(
            atPath: directory, withIntermediateDirectories: true
        )
        try? text.write(toFile: path, atomically: true, encoding: .utf8)
        try? FileManager.default.setAttributes(
            [.posixPermissions: 0o600], ofItemAtPath: path
        )
    }

    static func copyToPasteboard() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    static func openTrackpadSettings() {
        NSWorkspace.shared.open(
            URL(string: "x-apple.systempreferences:com.apple.preference.universalaccess?Mouse")!
        )
    }
}
