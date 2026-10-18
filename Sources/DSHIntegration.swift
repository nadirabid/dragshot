import Cocoa
import Darwin

/// What the bridge reports after accepting one capture.
struct DSHSendResult {
    let sessionID: String
    let title: String?
    let created: Bool
    let target: String
    let opened: Bool
}

/// One session as exposed by the DSH bridge. `updatedAt` and `lastPromptAt`
/// arrive as epoch milliseconds and are normalized to seconds here.
struct DSHSession {
    let id: String
    let title: String
    let cwd: String?
    let updatedAt: TimeInterval
    let lastPromptAt: TimeInterval?
    let running: Bool

    var activity: TimeInterval { lastPromptAt ?? updatedAt }

    var workspaceName: String? {
        guard let cwd, !cwd.isEmpty else { return nil }
        let name = (cwd as NSString).lastPathComponent
        return name.isEmpty ? cwd : name
    }
}

/// Failures worth showing in the transient notice and the Lookit log.
enum DSHIntegrationError: LocalizedError {
    case disabled
    case notInstalled
    case bridgeUnavailable(String)
    case launchFailed(String)
    case invalidResponse(String)
    case socket(String)
    case server(code: String, message: String)

    var errorDescription: String? {
        switch self {
        case .disabled:
            return "DSH sending is off."
        case .notInstalled:
            return "DeepSeek Harness is not installed."
        case .bridgeUnavailable(let message):
            return message
        case .launchFailed(let message):
            return "Could not open DSH: \(message)"
        case .invalidResponse(let message):
            return "DSH returned an unexpected response: \(message)"
        case .socket(let message):
            return "DSH bridge unavailable: \(message)"
        case .server(let code, let message):
            return message.isEmpty ? "DSH rejected the capture (\(code))." : message
        }
    }
}

/// Local-only DSH adapter.
///
/// The DSH desktop app cannot be driven through its web server from another
/// process, so it runs a host plugin (`dsh-lookit`) that publishes a Unix
/// socket. This class discovers that socket, launches DSH when needed, and
/// sends one image plus note to a new session, the most recent one, or a
/// session chosen in the composer picker.
final class DSHIntegration {
    static let shared = DSHIntegration()

    enum Target: Equatable {
        case recent
        case new
        case session(id: String, title: String)

        var kind: String {
            switch self {
            case .recent: return "recent"
            case .new: return "new"
            case .session: return "session"
            }
        }

        var title: String {
            switch self {
            case .recent: return "Most recent"
            case .new: return "New chat"
            case .session(_, let title): return title
            }
        }
    }

    enum BridgeState {
        case ready
        case appNotRunning
        case bridgeMissing
        case notInstalled
        case checking
        case navigationMissing
        case outdated
    }

    private enum Key {
        static let enabled = "dsh.enabled"
        static let target = "dsh.target"
        static let targetSessionID = "dsh.targetSessionID"
        static let targetSessionTitle = "dsh.targetSessionTitle"
        static let activateAfterSend = "dsh.activateAfterSend"
    }

    static let bundleIdentifier = "com.deepseek.dsh"
    static let fallbackAppPath = "/Applications/DeepSeek Harness.app"
    static let discoveryURL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/Lookit/dsh-bridge.json")

    private let defaults = UserDefaults.standard
    private let workQueue = DispatchQueue(label: "lookit.dsh", qos: .utility)

    private var healthCheckInFlight = false
    private var health: BridgeState = .checking

    private init() {
        if defaults.string(forKey: Key.target) == nil {
            defaults.set("recent", forKey: Key.target)
        }
        if defaults.object(forKey: Key.activateAfterSend) == nil {
            defaults.set(true, forKey: Key.activateAfterSend)
        }
    }

    // MARK: - Settings

    var isEnabled: Bool {
        get { defaults.bool(forKey: Key.enabled) }
        set { defaults.set(newValue, forKey: Key.enabled) }
    }

    var target: Target {
        get {
            switch defaults.string(forKey: Key.target) ?? "recent" {
            case "new":
                return .new
            case "session":
                let id = defaults.string(forKey: Key.targetSessionID) ?? ""
                let title = defaults.string(forKey: Key.targetSessionTitle) ?? "Session"
                return id.isEmpty ? .recent : .session(id: id, title: title)
            default:
                return .recent
            }
        }
        set {
            switch newValue {
            case .recent:
                defaults.set("recent", forKey: Key.target)
                defaults.removeObject(forKey: Key.targetSessionID)
                defaults.removeObject(forKey: Key.targetSessionTitle)
            case .new:
                defaults.set("new", forKey: Key.target)
                defaults.removeObject(forKey: Key.targetSessionID)
                defaults.removeObject(forKey: Key.targetSessionTitle)
            case .session(let id, let title):
                defaults.set("session", forKey: Key.target)
                defaults.set(id, forKey: Key.targetSessionID)
                defaults.set(title, forKey: Key.targetSessionTitle)
            }
        }
    }

    var activateAfterSend: Bool {
        get { defaults.object(forKey: Key.activateAfterSend) as? Bool ?? true }
        set { defaults.set(newValue, forKey: Key.activateAfterSend) }
    }

    /// The chip's title. The chip adds the agent name separately.
    var targetLabel: String {
        guard isEnabled else { return "Saved locally" }
        return target.title
    }

    var targetAccessibilityLabel: String {
        guard isEnabled else { return "Saved locally" }
        return "Send to DSH, \(target.title)"
    }

    // MARK: - Status

    static var appURL: URL? {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier)
            ?? (FileManager.default.fileExists(atPath: fallbackAppPath)
                ? URL(fileURLWithPath: fallbackAppPath)
                : nil)
    }

    var bridgeState: BridgeState {
        guard Self.appURL != nil else { return .notInstalled }
        if discoverySocketPath() != nil { return health }
        if !isDSHRunning { return .appNotRunning }
        return .bridgeMissing
    }

    var bridgeStatusText: String {
        switch bridgeState {
        case .ready:
            return "Connected"
        case .checking:
            return "Checking connection…"
        case .navigationMissing:
            return "Connected · open DSH to enable chat navigation"
        case .outdated:
            return "Bridge updated · restart DSH to finish"
        case .appNotRunning:
            return "DSH not running (opens on send)"
        case .bridgeMissing:
            return "Not loaded — restart DSH once"
        case .notInstalled:
            return "Not installed"
        }
    }

    /// Probe the actual protocol; a leftover socket alone is not readiness.
    func refreshHealth() {
        guard !healthCheckInFlight else { return }
        guard let socket = discoverySocketPath() else { health = .checking; return }
        healthCheckInFlight = true
        DispatchQueue.global(qos: .utility).async {
            let next: BridgeState
            do {
                let result = try UnixSocketClient.request(socketPath: socket, method: "hello", params: [:], timeout: 2)
                if result["plugin"] as? String != "dsh-lookit" || result["version"] as? String != "0.4.0" {
                    next = .outdated
                } else {
                    next = result["navigationReady"] as? Bool == true ? .ready : .navigationMissing
                }
            } catch { next = .bridgeMissing }
            DispatchQueue.main.async { self.health = next; self.healthCheckInFlight = false }
        }
    }

    var bridgeInstalled: Bool {
        let path = Self.discoveryURL.deletingLastPathComponent()
            .appendingPathComponent("Integrations/dsh-lookit/lib/index.js").path
        return FileManager.default.fileExists(atPath: path)
    }

    /// Uses the bundled payload, so repair also works after deleting the checkout.
    func installBridge(completion: @escaping (Error?) -> Void) {
        guard let installer = Bundle.main.resourceURL?.appendingPathComponent("DSHBridge/install.sh"),
              FileManager.default.fileExists(atPath: installer.path) else {
            completion(DSHIntegrationError.bridgeUnavailable("The bundled bridge installer is missing. Reinstall Lookit."))
            return
        }
        workQueue.async {
            do {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/bin/bash")
                process.arguments = [installer.path, FileManager.default.homeDirectoryForCurrentUser.path]
                let pipe = Pipe()
                process.standardOutput = pipe
                process.standardError = pipe
                try process.run()
                let output = pipe.fileHandleForReading.readDataToEndOfFile()
                process.waitUntilExit()
                let error: Error? = process.terminationStatus == 0 ? nil : DSHIntegrationError.bridgeUnavailable(
                    String(data: output, encoding: .utf8) ?? "Could not install the DSH bridge.")
                DispatchQueue.main.async { self.refreshHealth(); completion(error) }
            } catch { DispatchQueue.main.async { completion(error) } }
        }
    }

    var isDSHRunning: Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: Self.bundleIdentifier).isEmpty
    }

    // MARK: - Launch and focus

    @discardableResult
    func openDSH() -> Bool {
        guard let url = Self.appURL else { return false }
        return NSWorkspace.shared.open(url)
    }

    func activateDSH() {
        guard let app = NSRunningApplication
            .runningApplications(withBundleIdentifier: Self.bundleIdentifier)
            .first else { return }
        app.activate(options: [.activateAllWindows])
    }

    // MARK: - Send

    /// Send one capture. Completion is always delivered on the main queue.
    func send(image: CGImage, text: String, completion: @escaping (Result<DSHSendResult, Error>) -> Void) {
        guard isEnabled else {
            DispatchQueue.main.async { completion(.failure(DSHIntegrationError.disabled)) }
            return
        }
        guard Self.appURL != nil else {
            DispatchQueue.main.async { completion(.failure(DSHIntegrationError.notInstalled)) }
            return
        }
        guard let png = try? Storage.pngData(image: image) else {
            DispatchQueue.main.async {
                completion(.failure(DSHIntegrationError.invalidResponse("could not encode the screenshot")))
            }
            return
        }

        let wasRunning = isDSHRunning
        let target = self.target
        let activateAfterSend = self.activateAfterSend

        workQueue.async { [weak self] in
            guard let self else { return }

            if !wasRunning {
                DispatchQueue.main.async { Notice.show("Opening DSH…") }
                guard self.openDSH() else {
                    DispatchQueue.main.async {
                        completion(.failure(DSHIntegrationError.launchFailed("the app could not be opened")))
                    }
                    return
                }
            }

            guard let socket = self.waitForSocket(timeout: wasRunning ? 3.0 : 20.0) else {
                let message = wasRunning
                    ? "DSH is running, but its Lookit bridge is not loaded. Use Set Up / Repair Bridge in Lookit Settings → Harnesses, then restart DSH."
                    : "DSH did not finish starting in time."
                DispatchQueue.main.async {
                    completion(.failure(DSHIntegrationError.bridgeUnavailable(message)))
                }
                return
            }

            var params: [String: Any] = [
                "target": target.kind,
                "text": text,
                "imageBase64": png.base64EncodedString(),
                "imageMediaType": "image/png",
                "imageName": "lookit.png",
                "mode": "queue",
                "openAfterSend": activateAfterSend,
            ]
            if case .session(let id, _) = target {
                params["sessionId"] = id
            }
            do {
                let result = try UnixSocketClient.request(
                    socketPath: socket,
                    method: "send",
                    params: params,
                    timeout: 60
                )
                guard let sessionID = result["sessionId"] as? String else {
                    throw DSHIntegrationError.invalidResponse("no sessionId")
                }
                let sent = DSHSendResult(
                    sessionID: sessionID,
                    title: result["title"] as? String,
                    created: result["created"] as? Bool ?? false,
                    target: result["target"] as? String ?? target.kind,
                    opened: result["opened"] as? Bool ?? false
                )
                Log.write("sent to DSH session \(sessionID) (\(sent.created ? "new" : "existing"))")
                DispatchQueue.main.async {
                    if activateAfterSend { self.activateDSH() }
                    completion(.success(sent))
                }
            } catch {
                Log.write("DSH send failed: \(error.localizedDescription)")
                DispatchQueue.main.async { completion(.failure(error)) }
            }
        }
    }

    // MARK: - Sessions

    /// Read the bridge's session list. This does not launch DSH: the picker can
    /// still offer New chat, and sending that will launch it. Completion is
    /// always delivered on the main queue.
    func listSessions(completion: @escaping (Result<[DSHSession], Error>) -> Void) {
        guard isEnabled else {
            DispatchQueue.main.async { completion(.failure(DSHIntegrationError.disabled)) }
            return
        }
        guard Self.appURL != nil else {
            DispatchQueue.main.async { completion(.failure(DSHIntegrationError.notInstalled)) }
            return
        }
        let wasRunning = isDSHRunning
        workQueue.async { [weak self] in
            guard let self else { return }
            guard wasRunning else {
                DispatchQueue.main.async {
                    completion(.failure(DSHIntegrationError.bridgeUnavailable(
                        "DSH is not running. Choose New chat to launch it.")))
                }
                return
            }
            guard let socket = self.waitForSocket(timeout: 2.0) else {
                DispatchQueue.main.async {
                    completion(.failure(DSHIntegrationError.bridgeUnavailable(
                        "DSH's bridge is not loaded. Use Set Up / Repair Bridge in Settings → Harnesses.")))
                }
                return
            }
            do {
                let result = try UnixSocketClient.request(
                    socketPath: socket,
                    method: "list",
                    params: [:],
                    timeout: 15
                )
                let items = result["items"] as? [[String: Any]] ?? []
                let sessions = items.compactMap(Self.session(from:))
                DispatchQueue.main.async { completion(.success(sessions)) }
            } catch {
                Log.write("DSH list failed: \(error.localizedDescription)")
                DispatchQueue.main.async { completion(.failure(error)) }
            }
        }
    }

    private static func session(from object: [String: Any]) -> DSHSession? {
        guard let id = object["sessionId"] as? String, !id.isEmpty else { return nil }
        let rawTitle = (object["title"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let updated = (object["updatedAt"] as? NSNumber)?.doubleValue ?? 0
        let lastPrompt = (object["lastPromptAt"] as? NSNumber)?.doubleValue
        return DSHSession(
            id: id,
            title: rawTitle.isEmpty ? "New chat" : rawTitle,
            cwd: object["cwd"] as? String,
            updatedAt: updated > 0 ? updated / 1000 : 0,
            lastPromptAt: lastPrompt.map { $0 / 1000 },
            running: object["running"] as? Bool ?? false
        )
    }

    private func waitForSocket(timeout: TimeInterval) -> String? {
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            if let socket = discoverySocketPath() { return socket }
            Thread.sleep(forTimeInterval: 0.25)
        } while Date() < deadline
        return nil
    }

    /// Read and validate the plugin's discovery file. A stale file whose socket
    /// is gone is treated as missing, so the caller gets the restart advice.
    func discoverySocketPath() -> String? {
        guard let data = try? Data(contentsOf: Self.discoveryURL),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let socket = object["socket"] as? String,
              !socket.isEmpty,
              FileManager.default.fileExists(atPath: socket) else {
            return nil
        }
        return socket
    }
}

/// Minimal blocking client for the bridge's newline-delimited JSON protocol.
/// It opens one connection per request and closes it, which keeps the server
/// stateless and the Swift side easy to reason about.
private enum UnixSocketClient {
    static func request(
        socketPath: String,
        method: String,
        params: [String: Any],
        timeout: TimeInterval
    ) throws -> [String: Any] {
        let id = UUID().uuidString
        let object: [String: Any] = ["id": id, "method": method, "params": params]
        var data = try JSONSerialization.data(withJSONObject: object)
        data.append(0x0A)

        let descriptor = socket(AF_UNIX, SOCK_STREAM, 0)
        guard descriptor >= 0 else {
            throw DSHIntegrationError.socket("socket() failed: \(errnoText())")
        }
        defer { close(descriptor) }
        var noSignal: Int32 = 1
        setsockopt(descriptor, SOL_SOCKET, SO_NOSIGPIPE, &noSignal, socklen_t(MemoryLayout<Int32>.size))

        var timeoutValue = timeval(tv_sec: Int(timeout), tv_usec: 0)
        setsockopt(descriptor, SOL_SOCKET, SO_RCVTIMEO, &timeoutValue,
                   socklen_t(MemoryLayout<timeval>.size))
        setsockopt(descriptor, SOL_SOCKET, SO_SNDTIMEO, &timeoutValue,
                   socklen_t(MemoryLayout<timeval>.size))

        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        let pathBytes = Array(socketPath.utf8)
        let capacity = MemoryLayout.size(ofValue: address.sun_path)
        guard pathBytes.count < capacity else {
            throw DSHIntegrationError.socket("socket path is too long")
        }
        withUnsafeMutablePointer(to: &address.sun_path) { pointer in
            pointer.withMemoryRebound(to: CChar.self, capacity: capacity) { destination in
                for (index, byte) in pathBytes.enumerated() {
                    destination[index] = CChar(bitPattern: byte)
                }
                destination[pathBytes.count] = 0
            }
        }

        let connected = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPointer in
                connect(descriptor, sockaddrPointer, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard connected == 0 else {
            throw DSHIntegrationError.socket("connect() failed: \(errnoText())")
        }

        var writeError: Error?
        data.withUnsafeBytes { raw in
            var offset = 0
            while offset < raw.count {
                let written = write(descriptor, raw.baseAddress!.advanced(by: offset), raw.count - offset)
                if written > 0 {
                    offset += written
                    continue
                }
                if written < 0, errno == EINTR { continue }
                writeError = DSHIntegrationError.socket("write() failed: \(errnoText())")
                return
            }
        }
        if let writeError { throw writeError }

        var response = Data()
        var buffer = [UInt8](repeating: 0, count: 64 * 1024)
        let maximumResponseBytes = 4 * 1024 * 1024
        while response.count < maximumResponseBytes {
            let count = buffer.withUnsafeMutableBytes { raw in
                read(descriptor, raw.baseAddress, raw.count)
            }
            if count > 0 {
                response.append(contentsOf: buffer[0..<count])
                if response.contains(0x0A) { break }
                continue
            }
            if count == 0 { break }
            if errno == EINTR { continue }
            throw DSHIntegrationError.socket("read() failed: \(errnoText())")
        }

        guard let newline = response.firstIndex(of: 0x0A) else {
            throw DSHIntegrationError.invalidResponse("the response had no newline")
        }
        let line = response.subdata(in: 0..<newline)
        guard let object = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
              let ok = object["ok"] as? Bool else {
            throw DSHIntegrationError.invalidResponse("the response was not JSON")
        }
        if ok {
            guard let result = object["result"] as? [String: Any] else {
                throw DSHIntegrationError.invalidResponse("the response had no result")
            }
            return result
        }
        let error = object["error"] as? [String: Any]
        let code = error?["code"] as? String ?? "unknown"
        let message = error?["message"] as? String ?? "DSH rejected the capture."
        throw DSHIntegrationError.server(code: code, message: message)
    }

    private static func errnoText() -> String {
        String(cString: strerror(errno))
    }
}
