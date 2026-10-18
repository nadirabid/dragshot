import Cocoa

/// A capture has one destination. Legacy DSH preferences remain the default until
/// the user chooses a harness, preserving existing installations and scripts.
enum Harness: String, CaseIterable, Identifiable {
    case local, deepseek, codex, cursor
    var id: String { rawValue }
    var title: String {
        switch self {
        case .local: return "Save locally only"
        case .deepseek: return "DeepSeek Harness"
        case .codex: return "Codex"
        case .cursor: return "Cursor"
        }
    }
    var scheme: String? {
        switch self {
        case .codex: return "codex"
        case .cursor: return "cursor"
        default: return nil
        }
    }
    var appURL: URL? {
        guard let scheme, let url = URL(string: "\(scheme)://") else { return nil }
        return NSWorkspace.shared.urlForApplication(toOpen: url)
    }
}

enum HarnessIntegration {
    static var destination: Harness {
        get {
            if let stored = UserDefaults.standard.string(forKey: "harness.destination"),
               let harness = Harness(rawValue: stored) { return harness }
            return DSHIntegration.shared.isEnabled ? .deepseek : .local
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: "harness.destination")
            DSHIntegration.shared.isEnabled = newValue == .deepseek
        }
    }
    static var usesDSH: Bool { destination == .deepseek }
    static var codexWorkspace: String {
        get { UserDefaults.standard.string(forKey: "codex.workspace") ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: "codex.workspace") }
    }

    /// Local app deep links populate a draft, never auto-submit. Image bytes stay
    /// on disk and on the clipboard; the draft references the exact saved PNG.
    static func draftURL(for harness: Harness, capture: SavedCapture, text: String, workspace: String = "") throws -> URL {
        var parts = URLComponents()
        let prompt = "\(text.isEmpty ? "Please examine this screenshot." : text)\n\nScreenshot saved by Lookit: \(capture.pngURL.path)\nOpen this local image to see the captured region."
        switch harness {
        case .codex:
            parts.scheme = "codex"
            parts.host = "threads"
            parts.path = "/new"
            parts.queryItems = [URLQueryItem(name: "prompt", value: prompt),
                                URLQueryItem(name: "path", value: workspace.isEmpty ? capture.pngURL.deletingLastPathComponent().path : workspace)]
        case .cursor:
            parts.scheme = "cursor"
            parts.host = "anysphere.cursor-deeplink"
            parts.path = "/prompt"
            parts.queryItems = [URLQueryItem(name: "text", value: prompt)]
        default: throw CocoaError(.featureUnsupported)
        }
        parts.percentEncodedQuery = parts.percentEncodedQuery?.replacingOccurrences(of: "+", with: "%2B")
        // Cursor documents a 10,000-character URL limit. Keep the full note on
        // disk rather than silently truncating it (also bounds Codex launch URLs).
        if (parts.url?.absoluteString.count ?? Int.max) > 10_000 {
            parts.queryItems?[0].value = "Read my complete request from \(capture.noteURL.path), then examine the screenshot at \(capture.pngURL.path). Both are local files saved by Lookit."
        }
        parts.percentEncodedQuery = parts.percentEncodedQuery?.replacingOccurrences(of: "+", with: "%2B")
        guard let url = parts.url, url.absoluteString.count <= 10_000 else { throw CocoaError(.fileReadTooLarge) }
        return url
    }

    static func openApp(_ harness: Harness, completion: @escaping (Error?) -> Void) {
        guard let app = harness.appURL else {
            completion(NSError(domain: "Lookit.Harness", code: 1, userInfo: [NSLocalizedDescriptionKey: "\(harness.title) is not installed or its app link is unavailable."]))
            return
        }
        NSWorkspace.shared.openApplication(at: app, configuration: .init()) { _, error in
            DispatchQueue.main.async { completion(error) }
        }
    }

    static func openDraft(_ harness: Harness, capture: SavedCapture, text: String, completion: @escaping (Error?) -> Void) {
        do {
            let workspace = harness == .codex ? codexWorkspace : ""
            if !workspace.isEmpty {
                var directory: ObjCBool = false
                guard FileManager.default.fileExists(atPath: workspace, isDirectory: &directory), directory.boolValue else {
                    throw NSError(domain: "Lookit.Harness", code: 2, userInfo: [NSLocalizedDescriptionKey: "Choose an existing Codex workspace in Settings → Harnesses."])
                }
            }
            let link = try draftURL(for: harness, capture: capture, text: text, workspace: workspace)
            guard let app = harness.appURL else {
                throw NSError(domain: "Lookit.Harness", code: 1, userInfo: [NSLocalizedDescriptionKey: "\(harness.title) is not installed or its app link is unavailable."])
            }
            // Launch first so a cold application can register its URL receiver.
            NSWorkspace.shared.openApplication(at: app, configuration: .init()) { _, error in
                if let error { DispatchQueue.main.async { completion(error) }; return }
                NSWorkspace.shared.open([link], withApplicationAt: app, configuration: .init()) { _, error in
                    DispatchQueue.main.async { completion(error) }
                }
            }
        } catch { completion(error) }
    }
}
