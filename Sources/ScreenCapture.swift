import Cocoa
import ScreenCaptureKit

enum CaptureError: LocalizedError {
    case permission, displayUnavailable, timedOut
    var errorDescription: String? {
        switch self {
        case .permission: return "Screen Recording permission is required."
        case .displayUnavailable: return "The selected display is no longer available."
        case .timedOut: return "Screen capture timed out. Please try again."
        }
    }
}

enum ScreenCapture {
    /// Both the timeout and asynchronous result finish on the main actor, exactly once.
    /// Cancellation and the controller's generation check prevent stale UI from reopening.
    static func capture(screen: NSScreen, rect: NSRect,
                        completion: @escaping (Result<CGImage, Error>) -> Void) -> Task<Void, Never> {
        var completed = false
        func finish(_ result: Result<CGImage, Error>) {
            guard !completed else { return }
            completed = true
            completion(result)
        }
        let timeout = DispatchWorkItem { finish(.failure(CaptureError.timedOut)) }
        DispatchQueue.main.asyncAfter(deadline: .now() + 4, execute: timeout)

        return Task { @MainActor in
            defer { timeout.cancel() }
            do {
                guard Permissions.hasScreenRecording else { throw CaptureError.permission }
                let content = try await SCShareableContent.excludingDesktopWindows(
                    false, onScreenWindowsOnly: true)
                try Task.checkCancellation()
                guard !completed else { return }
                guard let id = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")]
                        as? CGDirectDisplayID,
                      let display = content.displays.first(where: { $0.displayID == id }) else {
                    throw CaptureError.displayUnavailable
                }
                let ownApps = content.applications.filter {
                    $0.processID == ProcessInfo.processInfo.processIdentifier
                }
                let filter = SCContentFilter(display: display,
                                             excludingApplications: ownApps, exceptingWindows: [])
                let config = SCStreamConfiguration()
                config.showsCursor = false
                config.captureResolution = .best
                config.scalesToFit = false
                config.sourceRect = CGRect(
                    x: rect.minX - screen.frame.minX, y: screen.frame.maxY - rect.maxY,
                    width: rect.width, height: rect.height)
                config.width = max(1, Int((rect.width * screen.backingScaleFactor).rounded()))
                config.height = max(1, Int((rect.height * screen.backingScaleFactor).rounded()))
                let image = try await SCScreenshotManager.captureImage(
                    contentFilter: filter, configuration: config)
                try Task.checkCancellation()
                finish(.success(image))
            } catch {
                finish(.failure(error))
            }
        }
    }
}
