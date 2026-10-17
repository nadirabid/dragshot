import Cocoa
import Combine

/// One observable source for the settings window. Changes still go through the
/// existing integration and macOS services, so the menu and composer stay in sync.
final class SettingsModel: ObservableObject {
    @Published var page: SettingsPage? = .general
    @Published private(set) var status = SetupStatus.current
    @Published private(set) var loginEnabled = LaunchAtLogin.enabled
    @Published private(set) var loginNeedsApproval = LaunchAtLogin.needsApproval
    @Published private(set) var loginDescription = LaunchAtLogin.description
    @Published private(set) var sending = DSHIntegration.shared.isEnabled
    @Published private(set) var activateAfterSend = DSHIntegration.shared.activateAfterSend
    @Published private(set) var destination = DSHIntegration.shared.target.kind
    @Published private(set) var destinationTitle = DSHIntegration.shared.target.title
    @Published private(set) var bridge = DSHIntegration.shared.bridgeStatusText
    @Published private(set) var captureState = CaptureTestState.idle
    @Published var showPermissionHelp = false
    @Published var errorMessage: String?
    weak var window: NSWindow?
    var onChange: (() -> Void)?
    var onRestart: (() -> Void)?
    private var captureTask: Task<Void, Never>?

    enum CaptureTestState: Equatable {
        case idle, running, verified, failed
        var message: String {
            switch self {
            case .idle: return "Confirm access with a test capture. No image is saved."
            case .running: return "Waiting for macOS. Choose Allow if prompted."
            case .verified: return "Screen capture verified."
            case .failed: return "Capture failed. Allow access, restart Lookit, and try again."
            }
        }
    }

    func refresh(_ status: SetupStatus) {
        if self.status != status { self.status = status }
        if !status.screen && captureState == .verified { captureState = .idle }
    }
    func refreshPreferences() {
        if loginEnabled != LaunchAtLogin.enabled { loginEnabled = LaunchAtLogin.enabled }
        if loginNeedsApproval != LaunchAtLogin.needsApproval { loginNeedsApproval = LaunchAtLogin.needsApproval }
        if loginDescription != LaunchAtLogin.description { loginDescription = LaunchAtLogin.description }
        let integration = DSHIntegration.shared
        if sending != integration.isEnabled { sending = integration.isEnabled }
        if activateAfterSend != integration.activateAfterSend { activateAfterSend = integration.activateAfterSend }
        if destination != integration.target.kind { destination = integration.target.kind }
        if destinationTitle != integration.target.title { destinationTitle = integration.target.title }
        if bridge != integration.bridgeStatusText { bridge = integration.bridgeStatusText }
    }
    private func changed() { refreshPreferences(); onChange?() }
    func toggleLogin() { LaunchAtLogin.toggle(); changed() }
    func setSending(_ value: Bool) { DSHIntegration.shared.isEnabled = value; changed() }
    func setActivation(_ value: Bool) { DSHIntegration.shared.activateAfterSend = value; changed() }
    func setDestination(_ value: String) {
        if value == "recent" { DSHIntegration.shared.target = .recent }
        if value == "new" { DSHIntegration.shared.target = .new }
        changed()
    }
    func openDSH() {
        if !DSHIntegration.shared.openDSH() { errorMessage = "DeepSeek Harness is not installed." }
        changed()
    }
    func openSettings(_ step: SetupStep) {
        if let window, let screen = window.screen {
            window.setFrameOrigin(NSPoint(x: screen.visibleFrame.minX + 12,
                                          y: max(screen.visibleFrame.minY, screen.visibleFrame.midY - window.frame.height / 2)))
        }
        switch step {
        case .screen: Permissions.requestScreenRecording()
        case .control: Permissions.requestAccessibility()
        case .input:
            if status.inputReady { Permissions.openSettingsPane("Privacy_ListenEvent") }
            else { Permissions.requestInputMonitoring() }
        case .gesture: Diagnostics.openTrackpadSettings()
        }
    }
    func testCapture() {
        guard captureTask == nil, let screen = window?.screen ?? NSScreen.main else { return }
        captureState = .running
        captureTask = ScreenCapture.capture(screen: screen,
            rect: NSRect(x: screen.frame.minX, y: screen.frame.minY, width: 2, height: 2),
            timeoutInterval: 60) { [weak self] result in
                guard let self else { return }
                self.captureTask = nil
                switch result {
                case .success: self.captureState = .verified
                case .failure: self.captureState = .failed
                }
                self.refresh(.current)
            }
    }
    func openCaptures() {
        do {
            try FileManager.default.createDirectory(atPath: Storage.directory, withIntermediateDirectories: true)
            NSWorkspace.shared.open(URL(fileURLWithPath: Storage.directory))
        } catch { errorMessage = error.localizedDescription }
    }
    func copyDiagnostics() { Diagnostics.write(); Diagnostics.copyToPasteboard(); Notice.show("Diagnostics copied.") }
    func revealDiagnostics() { Diagnostics.write(); reveal(Diagnostics.path) }
    func revealLog() { reveal(Log.path) }
    func revealApp() { NSWorkspace.shared.activateFileViewerSelecting([Bundle.main.bundleURL]) }
    private func reveal(_ path: String) {
        let url = URL(fileURLWithPath: path)
        if FileManager.default.fileExists(atPath: path) { NSWorkspace.shared.activateFileViewerSelecting([url]) }
        else { NSWorkspace.shared.open(url.deletingLastPathComponent()) }
    }
}
