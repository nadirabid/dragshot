import Cocoa
import ApplicationServices

/// Permissions are never requested as a side effect of launching. On start we only
/// *preflight* (which is silent), and surface whatever is missing in the menu bar. The
/// system prompt is triggered only when you click the item, so the app never ambushes you
/// with a dialog at login.
enum Permissions {

    static var hasScreenRecording: Bool {
        CGPreflightScreenCaptureAccess()
    }

    static var hasAccessibility: Bool {
        AXIsProcessTrusted()
    }

    static var allGranted: Bool {
        hasScreenRecording && hasAccessibility
    }

    static func requestScreenRecording() {
        // Shows the system prompt and adds the app to the Screen Recording list, unchecked
        // until the user flips it in System Settings.
        CGRequestScreenCaptureAccess()
        openSettingsPane("Privacy_ScreenCapture")
    }

    static func requestAccessibility() {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        let options = [key: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
        openSettingsPane("Privacy_Accessibility")
    }

    static func openSettingsPane(_ anchor: String) {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(anchor)") else { return }
        NSWorkspace.shared.open(url)
    }
}
