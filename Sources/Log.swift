import Foundation

/// stderr is only mirrored when a terminal is attached. Writing to an unread pipe would
/// block, and this process spends its life on the main thread waiting for gestures.
enum Log {
    static let path = NSString(string: "~/Library/Logs/DragShot.log").expandingTildeInPath

    private static let queue = DispatchQueue(label: "dragshot.log")
    private static let toTerminal = isatty(STDERR_FILENO) == 1
    private static let formatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss.SSS"
        return f
    }()

    static func write(_ message: String) {
        let line = "[\(formatter.string(from: Date()))] \(message)\n"
        queue.async {
            let url = URL(fileURLWithPath: path)
            if let handle = try? FileHandle(forWritingTo: url) {
                handle.seekToEndOfFile()
                handle.write(line.data(using: .utf8) ?? Data())
                try? handle.close()
            } else {
                try? FileManager.default.createDirectory(
                    at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                try? line.write(to: url, atomically: true, encoding: .utf8)
            }
            if toTerminal {
                FileHandle.standardError.write(line.data(using: .utf8) ?? Data())
            }
        }
    }
}
