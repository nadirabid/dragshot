import Cocoa

// Render the menu bar's exact SF Symbol in white with no tile or background.
// Run with a Swift toolchain/SDK matching build.sh, then iconutil the iconset.
let output = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
let symbol = NSImage(systemSymbolName: "crop", accessibilityDescription: nil)!
    .withSymbolConfiguration(.init(pointSize: 256, weight: .regular))!
let formats: [(String, Int)] = [
    ("icon_16x16", 16), ("icon_16x16@2x", 32),
    ("icon_32x32", 32), ("icon_32x32@2x", 64),
    ("icon_128x128", 128), ("icon_128x128@2x", 256),
    ("icon_256x256", 256), ("icon_256x256@2x", 512),
    ("icon_512x512", 512), ("icon_512x512@2x", 1024)
]
for (name, size) in formats {
    let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
    let side = CGFloat(size)
    let ratio = symbol.size.width / symbol.size.height
    let height = side * 0.76
    let width = height * ratio
    symbol.draw(in: NSRect(x: (side - width) / 2, y: (side - height) / 2,
                           width: width, height: height))
    NSColor.white.setFill()
    NSRect(x: 0, y: 0, width: side, height: side).fill(using: .sourceIn)
    NSGraphicsContext.restoreGraphicsState()
    try bitmap.representation(using: .png, properties: [:])!
        .write(to: output.appendingPathComponent(name + ".png"))
}
