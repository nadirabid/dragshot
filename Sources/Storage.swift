import Cocoa

struct SavedCapture {
    let name: String
    let pngURL: URL
    let noteURL: URL
}

enum Storage {
    static let directory = NSString(string: "~/Pictures/Lookit").expandingTildeInPath

    static func pngData(image: CGImage) throws -> Data {
        let rep = NSBitmapImageRep(cgImage: image)
        guard let data = rep.representation(using: .png, properties: [:]) else {
            throw CocoaError(.fileWriteUnknown)
        }
        return data
    }

    static func save(image: CGImage, text: String) throws -> SavedCapture {
        let folder = URL(fileURLWithPath: directory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let stamp = ISO8601DateFormatter()
        stamp.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let name = "lookit-\(stamp.string(from: Date()).replacingOccurrences(of: ":", with: "-"))"
        let png = folder.appendingPathComponent(name + ".png")
        let note = folder.appendingPathComponent(name + ".txt")
        try pngData(image: image).write(to: png, options: .atomic)
        do {
            try text.write(to: note, atomically: true, encoding: .utf8)
        } catch {
            try FileManager.default.removeItem(at: png)
            throw error
        }
        return SavedCapture(name: name + ".png", pngURL: png, noteURL: note)
    }

    static func copyToPasteboard(image: CGImage) throws {
        let data = try pngData(image: image)
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        guard pasteboard.setData(data, forType: .png) else {
            throw CocoaError(.fileWriteUnknown)
        }
    }
}
