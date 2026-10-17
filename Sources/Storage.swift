import Cocoa

enum Storage {
    static let directory = NSString(string: "~/Pictures/DragShot").expandingTildeInPath

    static func save(image: CGImage, text: String) throws -> String {
        let folder = URL(fileURLWithPath: directory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let stamp = ISO8601DateFormatter()
        stamp.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let name = "dragshot-\(stamp.string(from: Date()).replacingOccurrences(of: ":", with: "-"))"
        let png = folder.appendingPathComponent(name + ".png")
        let note = folder.appendingPathComponent(name + ".txt")
        let rep = NSBitmapImageRep(cgImage: image)
        guard let data = rep.representation(using: .png, properties: [:]) else {
            throw CocoaError(.fileWriteUnknown)
        }
        try data.write(to: png, options: .atomic)
        do {
            try text.write(to: note, atomically: true, encoding: .utf8)
        } catch {
            try FileManager.default.removeItem(at: png)
            throw error
        }
        return name + ".png"
    }

    static func copyToPasteboard(image: CGImage) throws {
        let rep = NSBitmapImageRep(cgImage: image)
        guard let data = rep.representation(using: .png, properties: [:]) else {
            throw CocoaError(.fileWriteUnknown)
        }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        guard pasteboard.setData(data, forType: .png) else {
            throw CocoaError(.fileWriteUnknown)
        }
    }
}
