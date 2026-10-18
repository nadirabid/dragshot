import Cocoa

/// Opt-in integration probe. Uses the production encoder, Unix socket client,
/// send flow and response parser. Creates exactly one real DSH test chat.
@main struct DSHSendProbe {
    static func main() {
        guard CommandLine.arguments.contains("--send-test") else {
            print("Requires --send-test: creates one real DSH chat with a test image.")
            exit(2)
        }
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        let image = NSImage(size: NSSize(width: 480, height: 200))
        image.lockFocus()
        NSColor.white.setFill(); NSRect(x: 0, y: 0, width: 480, height: 200).fill()
        NSColor.systemGreen.setFill(); NSRect(x: 24, y: 60, width: 60, height: 60).fill()
        ("LOOKIT DSH 7F3A" as NSString).draw(at: NSPoint(x: 106, y: 78), withAttributes: [
            .font: NSFont.systemFont(ofSize: 28), .foregroundColor: NSColor.black])
        image.unlockFocus()
        let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil)!
        let bridge = DSHIntegration.shared
        // These are this executable's defaults, not local.lookit's preferences.
        bridge.isEnabled = true
        bridge.target = .new
        bridge.activateAfterSend = true
        bridge.send(image: cg, text: "Lookit integration validation. Read the attached image and reply with its text and the color of the square. Do not use tools or change any files.") { result in
            switch result {
            case .success(let sent):
                print("SESSION=\(sent.sessionID) CREATED=\(sent.created) OPENED=\(sent.opened)")
                fflush(stdout)
                exit(sent.created && sent.opened ? 0 : 1)
            case .failure(let error):
                print("FAIL: \(error.localizedDescription)"); fflush(stdout); exit(1)
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 90) { print("FAIL: timeout"); exit(1) }
        app.run()
    }
}
