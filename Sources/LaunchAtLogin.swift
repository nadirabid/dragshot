import Cocoa
import ServiceManagement

/// Both settings surfaces read macOS's actual login-item state.
enum LaunchAtLogin {
    static var status: SMAppService.Status { SMAppService.mainApp.status }
    static var enabled: Bool { status == .enabled }
    static var needsApproval: Bool { status == .requiresApproval }
    static var description: String {
        switch status {
        case .enabled: return "Lookit opens automatically when you log in to your Mac."
        case .requiresApproval: return "Allow Lookit in System Settings → Login Items to finish enabling."
        case .notFound: return AppLocation.isInstalled(Bundle.main.bundleURL)
            ? "Open Lookit manually, or enable launch at login."
            : "Install Lookit in Applications to enable launch at login."
        default: return "Open Lookit manually, or enable launch at login."
        }
    }
    static func toggle() {
        do {
            if enabled { try SMAppService.mainApp.unregister() }
            else if needsApproval { SMAppService.openSystemSettingsLoginItems() }
            else { try SMAppService.mainApp.register() }
        } catch {
            let alert = NSAlert(error: error)
            alert.messageText = "Couldn’t update launch at login"
            alert.runModal()
        }
    }
}

