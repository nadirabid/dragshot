import Cocoa

/// A transparent selection surface on the display where the drag began.
final class OverlayWindow: NSWindow {
    let screenRef: NSScreen
    var selection: NSRect = .zero {
        didSet { contentView?.needsDisplay = true }
    }
    var pointer: NSPoint? {
        didSet { contentView?.needsDisplay = true }
    }

    init(screen: NSScreen) {
        screenRef = screen
        super.init(contentRect: screen.frame, styleMask: .borderless,
                   backing: .buffered, defer: false)
        level = NSWindow.Level(rawValue: Int(CGShieldingWindowLevel()))
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        ignoresMouseEvents = true
        isReleasedWhenClosed = false
        hidesOnDeactivate = false
        animationBehavior = .none
        let view = OverlayView(frame: NSRect(origin: .zero, size: screen.frame.size))
        view.owner = self
        contentView = view
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

private final class OverlayView: NSView {
    weak var owner: OverlayWindow?
    override var isOpaque: Bool { false }

    override func draw(_ dirtyRect: NSRect) {
        guard let owner, let context = NSGraphicsContext.current?.cgContext else { return }
        OverlayRenderer.draw(into: context, selection: owner.selection, pointer: owner.pointer,
                             bounds: bounds, scale: owner.backingScaleFactor)
    }
}
