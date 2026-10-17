import Cocoa
import SwiftUI

/// AppKit owns the accessory app's window lifecycle; SwiftUI owns its contents.
final class SettingsWindow: NSWindowController {
    let model = SettingsModel()
    var onRestart: (() -> Void)? { get { model.onRestart } set { model.onRestart = newValue } }
    var onChange: (() -> Void)? { get { model.onChange } set { model.onChange = newValue } }

    init() {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 840, height: 720),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                              backing: .buffered, defer: false)
        window.title = "Lookit Settings"
        window.toolbarStyle = .unified
        window.identifier = NSUserInterfaceItemIdentifier("lookit-settings")
        window.isReleasedWhenClosed = false
        window.contentMinSize = NSSize(width: 760, height: 580)
        super.init(window: window)
        model.window = window
        window.contentViewController = NSHostingController(rootView: LookitSettingsView(model: model))
        window.setContentSize(NSSize(width: 840, height: 720))
        window.center()
        window.setFrameAutosaveName("LookitSettings")
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    func present() {
        refresh(.current)
        refreshPreferences()
        showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
    func selectPage(_ page: SettingsPage) { model.page = page }
    func refresh(_ status: SetupStatus) { model.refresh(status) }
    func refreshPreferences() { model.refreshPreferences() }
    func showRestartError() { model.errorMessage = "Couldn’t restart Lookit. Quit it, then open it from Applications." }
}
