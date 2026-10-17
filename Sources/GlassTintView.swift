import Cocoa

enum GlassPalette {
    static func whiteTint(light: CGFloat, dark: CGFloat) -> NSColor {
        NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            return NSColor.white.withAlphaComponent(isDark ? dark : light)
        }
    }
}

/// A stable translucent tint over the native glass material.
///
/// NSGlassEffectView is intentionally backdrop-driven, so its apparent color
/// changes with whatever is behind the window. A light tint keeps the composer
/// and picker readable and visually consistent on bright or busy desktops while
/// preserving the glass blur and edge.
final class GlassTintView: NSView {
    private let tintAlpha: CGFloat
    private let borderAlpha: CGFloat
    private let cornerRadius: CGFloat

    init(tintAlpha: CGFloat, borderAlpha: CGFloat, cornerRadius: CGFloat) {
        self.tintAlpha = tintAlpha
        self.borderAlpha = borderAlpha
        self.cornerRadius = cornerRadius
        super.init(frame: .zero)
        wantsLayer = true
    }

    required init?(coder: NSCoder) {
        fatalError("GlassTintView is constructed programmatically")
    }

    override var wantsUpdateLayer: Bool { true }

    override func updateLayer() {
        guard let layer else { return }
        layer.backgroundColor = NSColor.windowBackgroundColor
            .withAlphaComponent(tintAlpha).cgColor
        layer.borderColor = NSColor.white
            .withAlphaComponent(borderAlpha).cgColor
        layer.borderWidth = 1
        layer.cornerRadius = cornerRadius
        layer.masksToBounds = true
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
        updateLayer()
    }
}
