import Cocoa

/// A transient line of text in the middle of the screen.
///
/// The app is a menu bar accessory with no windows and no dock presence, so when something
/// cannot proceed this is the only place to say so. It takes no focus and dismisses itself.
final class Notice {
    private static var current: NSWindow?

    static func show(_ message: String, seconds: Double = 3.0) {
        current?.orderOut(nil)
        guard let screen = NSScreen.main else { return }

        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 13, weight: .medium),
            .foregroundColor: NSColor.white,
        ]
        let textSize = (message as NSString).size(withAttributes: attrs)
        let padX: CGFloat = 18
        let padY: CGFloat = 12
        let size = NSSize(width: textSize.width + padX * 2, height: textSize.height + padY * 2)

        let frame = NSRect(
            x: screen.frame.midX - size.width / 2,
            y: screen.frame.midY - size.height / 2,
            width: size.width, height: size.height
        )
        let window = NSWindow(contentRect: frame, styleMask: [.borderless],
                              backing: .buffered, defer: false)
        window.level = NSWindow.Level(rawValue: Int(CGShieldingWindowLevel()) + 2)
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = true
        window.ignoresMouseEvents = true
        window.isReleasedWhenClosed = false

        let label = NSTextField(labelWithString: message)
        label.font = .systemFont(ofSize: 13, weight: .medium)
        label.textColor = .white
        label.alignment = .center
        label.frame = NSRect(x: padX, y: padY, width: textSize.width, height: textSize.height)

        let card = NSView(frame: NSRect(origin: .zero, size: size))
        card.wantsLayer = true
        card.layer?.backgroundColor = NSColor(calibratedWhite: 0.10, alpha: 0.94).cgColor
        card.layer?.cornerRadius = 10
        card.layer?.borderWidth = 1
        card.layer?.borderColor = NSColor(calibratedWhite: 1, alpha: 0.14).cgColor
        card.addSubview(label)
        window.contentView = card
        window.orderFrontRegardless()

        current = window
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds) {
            window.orderOut(nil)
            if current === window { current = nil }
        }
    }
}
