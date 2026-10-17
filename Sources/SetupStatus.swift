import Cocoa

struct SetupStatus: Equatable {
    var screen: Bool
    var accessibility: Bool
    var gesture: Bool
    var listener: Bool
    var trackpad: Bool
    var inputMonitoring: Bool = false

    static var current: SetupStatus {
        SetupStatus(screen: Permissions.hasScreenRecording,
                    accessibility: Permissions.hasAccessibility,
                    gesture: Diagnostics.threeFingerDrag == "enabled",
                    listener: EventTap.isRunning, trackpad: Multitouch.isAvailable,
                    inputMonitoring: Permissions.hasInputMonitoring)
    }
    // A functioning filtering tap is direct evidence that input access is sufficient.
    // Do not demand a redundant Input Monitoring grant when Device Control covers it.
    var inputReady: Bool { inputMonitoring || listener }
    var ready: Bool { screen && accessibility && inputReady && gesture && listener && trackpad }
    var summary: String {
        if !screen || !accessibility { return "Allow access to capture and use your gesture." }
        if !inputReady { return "Check Input Monitoring to connect the gesture listener." }
        if !gesture { return "Turn on three-finger drag to finish." }
        if !trackpad { return "Connect a supported trackpad, then restart Lookit." }
        if !listener { return "Restart Lookit to connect the gesture listener." }
        return "You're ready. Drag with three fingers to capture a region."
    }
    func enabled(_ step: SetupStep) -> Bool {
        switch step {
        case .screen: return screen
        case .control: return accessibility
        case .input: return inputReady
        case .gesture: return gesture && trackpad
        }
    }
}

enum SetupStep: Int, CaseIterable {
    case screen, control, input, gesture
    var title: String {
        switch self {
        case .screen: return "Screen Recording"
        case .control: return ProcessInfo.processInfo.operatingSystemVersion.majorVersion >= 27 ? "Device Control" : "Accessibility"
        case .input: return "Input Monitoring"
        case .gesture: return "Three-finger Drag"
        }
    }
    var symbol: String {
        switch self {
        case .screen: return "rectangle.inset.filled"
        case .control: return "cursorarrow"
        case .input: return "keyboard"
        case .gesture: return "hand.draw"
        }
    }
    var pane: String {
        switch self {
        case .screen: return "Screen & System Audio Recording"
        case .control: return Permissions.accessibilityTitle
        case .input: return "Input Monitoring"
        case .gesture: return "Pointer Control"
        }
    }
    var reason: String {
        switch self {
        case .screen: return "Let Lookit capture the area you select. No audio is recorded."
        case .control: return "Let Lookit handle your three-finger gesture without moving the window underneath."
        case .input: return "Let Lookit receive the mouse and keyboard events used by the capture gesture."
        case .gesture: return "Use three fingers to draw a capture area anywhere on your screen."
        }
    }
}

