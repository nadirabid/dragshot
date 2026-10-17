import Cocoa

/// The standard AppKit translucent material used by both the composer and the
/// session picker. Forcing the active state keeps the two surfaces visually
/// identical even when one of them owns keyboard focus.
final class GlassSurfaceView: NSVisualEffectView {
    init(cornerRadius: CGFloat) {
        super.init(frame: .zero)
        material = .popover
        blendingMode = .behindWindow
        state = .active
        isEmphasized = false
        wantsLayer = true
        layer?.cornerRadius = cornerRadius
        layer?.masksToBounds = true
        layer?.borderWidth = 1
        updateBorder()
    }

    required init?(coder: NSCoder) {
        fatalError("GlassSurfaceView is constructed programmatically")
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateBorder()
    }

    private func updateBorder() {
        let dark = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        layer?.borderColor = NSColor.white.withAlphaComponent(dark ? 0.20 : 0.62).cgColor
    }
}
