import Cocoa

/// A quiet, chip-sized send control. The paper-plane is the affordance; the
/// subtle surface appears on hover instead of looking permanently pressed.
final class SendButton: NSButton {
    private var hover = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        isBordered = false
        bezelStyle = .regularSquare
        setButtonType(.momentaryChange)
        focusRingType = .none
        refusesFirstResponder = true
        keyEquivalent = ""
        wantsLayer = true
        layer?.cornerRadius = 15
        layer?.borderWidth = 1
        updateSurface()
    }

    required init?(coder: NSCoder) {
        fatalError("SendButton is constructed programmatically")
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in trackingAreas { removeTrackingArea(area) }
        addTrackingArea(NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
            owner: self,
            userInfo: nil
        ))
    }

    override func mouseEntered(with event: NSEvent) {
        hover = true
        updateSurface()
    }

    override func mouseExited(with event: NSEvent) {
        hover = false
        updateSurface()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateSurface()
    }

    private func updateSurface() {
        layer?.backgroundColor = NSColor.white
            .withAlphaComponent(hover ? 0.52 : 0.28).cgColor
        layer?.borderColor = NSColor.white
            .withAlphaComponent(hover ? 0.78 : 0.55).cgColor
    }
}
