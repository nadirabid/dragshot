import Cocoa

/// Draw only the selection affordances, in Cocoa points, over the unchanged desktop.
enum OverlayRenderer {
    static func draw(into context: CGContext, selection: NSRect, pointer: NSPoint?,
                     bounds: NSRect, scale: CGFloat) {
        context.saveGState()
        defer { context.restoreGState() }
        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)

        context.clear(bounds)
        if selection.width >= 1, selection.height >= 1 {
            let radius = min(5, min(selection.width, selection.height) / 2)
            let path = CGPath(roundedRect: selection, cornerWidth: radius,
                              cornerHeight: radius, transform: nil)
            context.saveGState()
            context.setShadow(offset: .zero, blur: 3, color: CGColor(gray: 0, alpha: 0.45))
            context.addPath(path)
            context.setStrokeColor(CGColor(gray: 1, alpha: 0.92))
            context.setLineWidth(1)
            context.strokePath()
            context.restoreGState()
        }

        if let pointer {
            let cursor = NSCursor.crosshair
            let size = cursor.image.size
            let rect = NSRect(x: pointer.x - cursor.hotSpot.x,
                              y: pointer.y - (size.height - cursor.hotSpot.y),
                              width: size.width, height: size.height)
            cursor.image.draw(in: rect)
        }

        // Dimensions help while aiming; once released, the input is the only control.
        guard selection.width >= 1, selection.height >= 1,
              let pointer else { return }
        let text = "\(Int((selection.width * scale).rounded())) × \(Int((selection.height * scale).rounded()))"
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .medium),
            .foregroundColor: NSColor.white.withAlphaComponent(0.95),
        ]
        let textSize = (text as NSString).size(withAttributes: attributes)
        let size = NSSize(width: textSize.width + 18, height: textSize.height + 10)
        let anchor = pointer
        var x = anchor.x + 18
        var y = anchor.y - size.height - 18
        if x + size.width > bounds.maxX - 8 { x = anchor.x - size.width - 18 }
        if y < bounds.minY + 8 { y = anchor.y + 18 }
        x = min(max(x, bounds.minX + 8), bounds.maxX - size.width - 8)
        y = min(max(y, bounds.minY + 8), bounds.maxY - size.height - 8)
        let label = NSRect(origin: NSPoint(x: x, y: y), size: size)
        context.saveGState()
        context.setShadow(offset: CGSize(width: 0, height: -1), blur: 4,
                          color: CGColor(gray: 0, alpha: 0.18))
        context.addPath(CGPath(roundedRect: label, cornerWidth: size.height / 2,
                              cornerHeight: size.height / 2, transform: nil))
        context.setFillColor(CGColor(gray: 0.12, alpha: 0.86))
        context.fillPath()
        context.restoreGState()
        (text as NSString).draw(at: NSPoint(x: x + 9, y: y + 5), withAttributes: attributes)
    }
}
