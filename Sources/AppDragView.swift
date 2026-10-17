import Cocoa

/// Finder-compatible app file drag, including first-click drags from an inactive window.
final class AppDragView: NSView, NSDraggingSource {
    static var isDragging = false
    let appURL: URL
    private let icon = NSImageView()
    private var dragStart: NSPoint?
    init(appURL: URL = Bundle.main.bundleURL) {
        self.appURL = appURL.resolvingSymlinksInPath()
        super.init(frame: .zero)
        icon.image = NSImage(systemSymbolName: "crop", accessibilityDescription: "Drag Lookit")
        icon.contentTintColor = .labelColor
        icon.symbolConfiguration = .init(pointSize: 26, weight: .regular)
        icon.translatesAutoresizingMaskIntoConstraints = false
        let title = NSTextField(labelWithString: "Lookit.app")
        title.font = .systemFont(ofSize: 14, weight: .semibold)
        let path = NSTextField(labelWithString: self.appURL.deletingLastPathComponent().path)
        path.font = .systemFont(ofSize: 10)
        path.textColor = .secondaryLabelColor
        path.lineBreakMode = .byTruncatingMiddle
        let hint = NSTextField(labelWithString: "Drag into a privacy list in System Settings")
        hint.font = .systemFont(ofSize: 11)
        hint.textColor = .secondaryLabelColor
        let stack = NSStackView(views: [title, path, hint])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 4
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(icon)
        addSubview(stack)
        NSLayoutConstraint.activate([
            icon.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 20),
            icon.centerYAnchor.constraint(equalTo: centerYAnchor),
            icon.widthAnchor.constraint(equalToConstant: 40), icon.heightAnchor.constraint(equalToConstant: 40),
            stack.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 18),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            path.widthAnchor.constraint(equalTo: stack.widthAnchor),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
        toolTip = self.appURL.path
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
        setAccessibilityLabel("Drag Lookit app into System Settings. Press to reveal in Finder.")
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override var mouseDownCanMoveWindow: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func shouldDelayWindowOrdering(for event: NSEvent) -> Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { super.hitTest(point) == nil ? nil : self }
    override func resetCursorRects() { addCursorRect(bounds, cursor: .openHand) }
    override func mouseDown(with event: NSEvent) { dragStart = event.locationInWindow }
    override func mouseUp(with event: NSEvent) { dragStart = nil }
    override func mouseDragged(with event: NSEvent) {
        guard let start = dragStart, !Self.isDragging,
              hypot(event.locationInWindow.x - start.x, event.locationInWindow.y - start.y) > 3 else { return }
        dragStart = nil
        Self.isDragging = true
        NSApp.preventWindowOrdering()
        let item = NSDraggingItem(pasteboardWriter: appURL as NSURL)
        let point = convert(event.locationInWindow, from: nil)
        item.setDraggingFrame(NSRect(x: point.x - 24, y: point.y - 24, width: 48, height: 48),
                              contents: NSWorkspace.shared.icon(forFile: appURL.path))
        let session = beginDraggingSession(with: [item], event: event, source: self)
        session.animatesToStartingPositionsOnCancelOrFail = true
        Log.write("setup app drag started: \(appURL.path)")
    }
    override func accessibilityPerformPress() -> Bool {
        NSWorkspace.shared.activateFileViewerSelecting([appURL])
        return true
    }
    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation { .copy }
    func ignoreModifierKeys(for session: NSDraggingSession) -> Bool { true }
    func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
        Self.isDragging = false
        Log.write("setup app drag ended: \(operation.rawValue)")
    }
}
