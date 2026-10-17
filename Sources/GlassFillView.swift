import Cocoa

/// A light, appearance-aware fill over the standard vibrancy material. It keeps
/// text readable on very bright or busy desktops while preserving the blur.
final class GlassFillView: NSView {
    private let alpha: CGFloat

    init(alpha: CGFloat) {
        self.alpha = alpha
        super.init(frame: .zero)
        wantsLayer = true
    }

    required init?(coder: NSCoder) {
        fatalError("GlassFillView is constructed programmatically")
    }

    override var wantsUpdateLayer: Bool { true }

    override func updateLayer() {
        layer?.backgroundColor = NSColor.windowBackgroundColor.withAlphaComponent(alpha).cgColor
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
        updateLayer()
    }
}
