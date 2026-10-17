import Cocoa

/// Produces a clean README image from the real AppKit composer. It uses a
/// caller-supplied wallpaper and sample content, so no personal desktop
/// content is captured.
enum ReadmeShot {
    static func run(backgroundPath: String) {
        guard let screen = NSScreen.main else { exit(2) }
        let wallpaper = NSImage(contentsOfFile: backgroundPath)
        let background = WallpaperWindow(screen: screen, image: wallpaper)
        background.orderFrontRegardless()

        DSHIntegration.shared.isEnabled = true
        DSHIntegration.shared.target = .recent

        let panel = PanelWindow()
        let rect = NSRect(x: screen.frame.minX + 1200,
                          y: screen.frame.minY + 720,
                          width: 420, height: 240)
        panel.present(near: rect, on: screen)
        panel.attach(fixture())
        panel.setDraftForTesting("What’s off in this chart?")

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) {
            let bounds = screen.frame.insetBy(dx: 12, dy: 40)
            let captureSize = NSSize(width: 1600, height: 900)
            let x = bounds.maxX - captureSize.width
            let y = min(max(panel.frame.midY - captureSize.height / 2, bounds.minY),
                        bounds.maxY - captureSize.height)
            let capture = NSRect(origin: NSPoint(x: x, y: y), size: captureSize)
            Task { @MainActor in
                try? await E2E.screenshot(screen: screen, rect: capture, name: "readme-shot.png")
                exit(0)
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 8) { exit(0) }
        }
    }

    private static func fixture() -> CGImage {
        let size = NSSize(width: 720, height: 420)
        let image = NSImage(size: size)
        image.lockFocus()
        NSColor(srgbRed: 0.964, green: 0.972, blue: 0.988, alpha: 1).setFill()
        NSRect(origin: .zero, size: size).fill()

        let card = NSRect(x: 24, y: 24, width: 672, height: 372)
        NSColor.white.setFill()
        NSBezierPath(roundedRect: card, xRadius: 18, yRadius: 18).fill()

        ("Weekly overview" as NSString).draw(at: NSPoint(x: 58, y: 338), withAttributes: [
            .font: NSFont.systemFont(ofSize: 24, weight: .semibold),
            .foregroundColor: NSColor(srgbRed: 0.13, green: 0.14, blue: 0.17, alpha: 1),
        ])
        ("Activity over the last seven days" as NSString).draw(at: NSPoint(x: 58, y: 311), withAttributes: [
            .font: NSFont.systemFont(ofSize: 13, weight: .regular),
            .foregroundColor: NSColor(srgbRed: 0.48, green: 0.50, blue: 0.56, alpha: 1),
        ])

        let grid = NSBezierPath()
        for y in stride(from: 92, through: 260, by: 42) {
            grid.move(to: NSPoint(x: 58, y: y))
            grid.line(to: NSPoint(x: 662, y: y))
        }
        NSColor(srgbRed: 0.91, green: 0.93, blue: 0.96, alpha: 1).setStroke()
        grid.lineWidth = 1
        grid.stroke()

        let heights: [CGFloat] = [66, 96, 74, 138, 104, 174, 126]
        let barWidth: CGFloat = 44
        let gap: CGFloat = 36
        for (index, height) in heights.enumerated() {
            let x = 74 + CGFloat(index) * (barWidth + gap)
            let bar = NSRect(x: x, y: 100, width: barWidth, height: height)
            NSColor(srgbRed: 0.30, green: 0.42, blue: 0.996, alpha: 1).setFill()
            NSBezierPath(roundedRect: bar, xRadius: 7, yRadius: 7).fill()
        }
        image.unlockFocus()
        return image.cgImage(forProposedRect: nil, context: nil, hints: nil)!
    }
}

private final class WallpaperView: NSView {
    var image: NSImage?

    override var isFlipped: Bool { false }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.black.setFill()
        bounds.fill()
        guard let image, image.size.width > 0, image.size.height > 0 else { return }
        let scale = max(bounds.width / image.size.width, bounds.height / image.size.height)
        let drawSize = NSSize(width: image.size.width * scale, height: image.size.height * scale)
        let drawRect = NSRect(x: (bounds.width - drawSize.width) / 2,
                              y: (bounds.height - drawSize.height) / 2,
                              width: drawSize.width, height: drawSize.height)
        image.draw(in: drawRect, from: NSRect(origin: .zero, size: image.size),
                   operation: .sourceOver, fraction: 1)
    }
}

private final class WallpaperWindow: NSWindow {
    init(screen: NSScreen, image: NSImage?) {
        super.init(contentRect: screen.frame,
                   styleMask: [.borderless], backing: .buffered, defer: false)
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        isOpaque = true
        backgroundColor = .black
        hasShadow = false
        isMovable = false
        ignoresMouseEvents = true
        isReleasedWhenClosed = false
        let view = WallpaperView(frame: NSRect(origin: .zero, size: screen.frame.size))
        view.image = image
        contentView = view
    }
}
