import SwiftUI

// System layout, typography, spacing and controls; only the quiet success tint is custom.
enum SettingsPage: Int, CaseIterable, Identifiable {
    case general, permissions, integration
    var id: Int { rawValue }
    var title: String {
        switch self {
        case .general: return "General"
        case .permissions: return "Permissions"
        case .integration: return "DeepSeek Harness"
        }
    }
    var symbol: String {
        switch self {
        case .general: return "gearshape"
        case .permissions: return "hand.raised"
        case .integration: return "bubble.left.and.bubble.right"
        }
    }
}

struct LookitSettingsView: View {
    @ObservedObject var model: SettingsModel
    var body: some View {
        NavigationSplitView {
            List(SettingsPage.allCases, selection: $model.page) { page in
                Label(page.title, systemImage: page.symbol).tag(page)
            }
            .navigationTitle("Lookit")
            .navigationSplitViewColumnWidth(min: 180, ideal: 200, max: 240)
        } detail: {
            Group {
                switch model.page ?? .general {
                case .general: GeneralSettings(model: model)
                case .permissions: PermissionSettings(model: model)
                case .integration: IntegrationSettings(model: model)
                }
            }
            .navigationTitle((model.page ?? .general).title)
        }
        .alert("Lookit", isPresented: Binding(get: { model.errorMessage != nil }, set: { if !$0 { model.errorMessage = nil } })) {
            Button("OK", role: .cancel) { model.errorMessage = nil }
        } message: { Text(model.errorMessage ?? "") }
    }
}

private struct GeneralSettings: View {
    @ObservedObject var model: SettingsModel
    var body: some View {
        Form {
            Section {
                Toggle("Launch at login", isOn: Binding(get: { model.loginEnabled }, set: { _ in model.toggleLogin() }))
                if model.loginNeedsApproval {
                    Button("Open Login Items Settings…", action: model.toggleLogin)
                }
            } header: { Text("Startup") } footer: { Text(model.loginDescription) }
            Section {
                LabeledContent("Gesture", value: "Three-finger drag")
                LabeledContent("Save location") {
                    Button("Open Captures Folder", action: model.openCaptures)
                }
                Button("Configure Permissions…") { model.page = .permissions }
            } header: { Text("Capture") } footer: {
                Text("Draw a region with three fingers. Return saves your image and note and copies the image to the clipboard.")
            }
            Section("Diagnostics") {
                LabeledContent("Gesture listener", value: model.status.listener ? "Running" : "Unavailable")
                LabeledContent("Trackpad", value: model.status.trackpad ? "Connected" : "Unavailable")
                if Lookit.shared.hotkeyEnabled { LabeledContent("Debug shortcut", value: "⌘⇧4") }
                HStack {
                    Button("Copy Diagnostics", action: model.copyDiagnostics)
                    Button("Reveal Diagnostics", action: model.revealDiagnostics)
                    Button("Reveal Log", action: model.revealLog)
                }
            }
            Section {
                HStack {
                    Button("Restart Lookit") { model.onRestart?() }
                    Spacer()
                    Button("Quit Lookit") { NSApp.terminate(nil) }
                }
            }
        }
        .formStyle(.grouped)
    }
}

private struct IntegrationSettings: View {
    @ObservedObject var model: SettingsModel
    var body: some View {
        Form {
            Section {
                Toggle("Send captures to DeepSeek Harness", isOn: Binding(get: { model.sending }, set: model.setSending))
            } footer: { Text("Your captures and notes are also saved locally. Images are always copied to the clipboard.") }
            Section {
                Picker("Default destination", selection: Binding(get: { model.destination }, set: model.setDestination)) {
                    Text("Most recent chat").tag("recent")
                    Text("New chat").tag("new")
                    if model.destination == "session" { Text("Pinned: \(model.destinationTitle)").tag("session") }
                }
                Toggle("Open DeepSeek Harness after sending", isOn: Binding(get: { model.activateAfterSend }, set: model.setActivation))
            } header: { Text("Sending") } footer: {
                Text("To pin a specific chat, choose it in the destination picker while composing a capture.")
            }
            .disabled(!model.sending)
            Section("Connection") {
                LabeledContent("Status", value: model.bridge)
                Button("Open DeepSeek Harness", action: model.openDSH)
            }
        }
        .formStyle(.grouped)
    }
}

private struct PermissionSettings: View {
    @ObservedObject var model: SettingsModel
    var body: some View {
        Form {
            Section {
                ForEach([SetupStep.screen, .control, .input], id: \.self) { step in
                    HStack(alignment: .center) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(step.title)
                            Text(step == .input && model.status.listener
                                 ? "Your gesture listener has access." : step.reason)
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 12)
                        StatusBadge(ready: model.status.enabled(step))
                        Button("Settings…") { model.openSettings(step) }
                            .accessibilityLabel("Open \(step.title) Settings")
                    }
                }
            } header: { Text("Privacy") } footer: { Text(model.status.summary) }
            Section {
                AppFileDrag().frame(height: 80)
            } header: { Text("Add Lookit to System Settings") }
            Section {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Screen capture")
                        Text(model.captureState.message).font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    if model.captureState == .running { ProgressView().controlSize(.small) }
                    if model.captureState == .verified { StatusBadge(ready: true) }
                    Button("Test Capture", action: model.testCapture).disabled(model.captureState == .running)
                }
            } footer: { Text("macOS may ask you to Allow screen and system audio access. Lookit captures images only; it does not record audio.") }
            Section {
                LabeledContent("Three-finger drag") {
                    StatusBadge(ready: model.status.enabled(.gesture))
                    Button("Trackpad Settings…") { model.openSettings(.gesture) }
                }
            } header: { Text("Trackpad") } footer: {
                Text("In Pointer Control → Trackpad Options, turn on dragging and choose Three Finger Drag.")
            }
            Section {
                HStack {
                    Button("Already enabled?") { model.showPermissionHelp = true }
                    Spacer()
                    Button("Restart Lookit") { model.onRestart?() }
                }
            }
        }
        .formStyle(.grouped)
        .alert("Settings says on, but Lookit can’t use it?", isPresented: $model.showPermissionHelp) {
            Button("Reveal App", action: model.revealApp)
            Button("OK", role: .cancel) { }
        } message: {
            Text("Restart Lookit first. If access is still missing, remove the old Lookit entry with −, then drag this installed app into the list and enable it again.")
        }
    }
}

private struct StatusBadge: View {
    let ready: Bool
    @Environment(\.colorScheme) private var colorScheme
    private var tint: Color {
        colorScheme == .dark ? Color(red: 0.53, green: 0.67, blue: 0.60) : Color(red: 0.31, green: 0.47, blue: 0.39)
    }
    var body: some View {
        Label {
            Text(ready ? "Ready" : "Needed").foregroundStyle(.secondary)
        } icon: {
            Image(systemName: ready ? "checkmark.circle" : "circle").foregroundStyle(ready ? tint : .secondary)
        }
        .font(.callout)
        .fixedSize()
        .accessibilityElement(children: .combine)
    }
}

/// Preserve native file-URL dragging and first-click drags from an inactive window.
private struct AppFileDrag: NSViewRepresentable {
    func makeNSView(context: Context) -> AppDragView { AppDragView() }
    func updateNSView(_ nsView: AppDragView, context: Context) { }
}
