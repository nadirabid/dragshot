import Cocoa
import QuartzCore

/// A transient glass input surface. The system owns the material and its rounded silhouette.
final class PanelWindow: NSPanel, NSTextViewDelegate, NSWindowDelegate {
    var onSubmit: ((String) -> Void)?
    var onCancel: (() -> Void)?

    private let textView = NSTextView()
    private let scroll = NSScrollView()
    private let attachment = AttachmentPreview()
    private let sendButton = SendButton()
    private var attachmentWidth: NSLayoutConstraint!
    private var attachmentHeight: NSLayoutConstraint!
    private var previewSize = NSSize(width: 240, height: 132)
    private var selection = NSRect.zero
    private var placementScreen: NSScreen?
    private var placeAbove = false
    private var inputWidth: CGFloat = 480
    private var userPositioned = false
    private let targetDock = NSView()
    private let sendToLabel = NSTextField(labelWithString: "Send to")
    private let targetChip = TargetChipView()
    private var scrollBottomDefault: NSLayoutConstraint!
    private var scrollBottomWithDock: NSLayoutConstraint!
    private var sessionPicker: SessionPickerWindow?
    private var pickerClosedAt: TimeInterval = 0
    private var isClearingSlash = false

    init() {
        super.init(contentRect: NSRect(x: 0, y: 0, width: 480, height: 68),
                   styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        level = NSWindow.Level(rawValue: Int(CGShieldingWindowLevel()) + 1)
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        isMovable = true
        isReleasedWhenClosed = false
        hidesOnDeactivate = false
        becomesKeyOnlyIfNeeded = false
        animationBehavior = .none
        delegate = self

        let surface = InputSurface(frame: NSRect(x: 0, y: 0, width: 480, height: 68))
        surface.wantsLayer = true
        let glass = GlassSurfaceView(cornerRadius: 22)
        glass.frame = surface.bounds
        glass.autoresizingMask = [.width, .height]
        let fill = GlassFillView(alpha: 0.60)
        fill.translatesAutoresizingMaskIntoConstraints = false
        glass.addSubview(fill)
        let content = NSView()
        content.wantsLayer = true
        content.translatesAutoresizingMaskIntoConstraints = false
        glass.addSubview(content)
        NSLayoutConstraint.activate([
            fill.leadingAnchor.constraint(equalTo: glass.leadingAnchor),
            fill.trailingAnchor.constraint(equalTo: glass.trailingAnchor),
            fill.topAnchor.constraint(equalTo: glass.topAnchor),
            fill.bottomAnchor.constraint(equalTo: glass.bottomAnchor),
            content.leadingAnchor.constraint(equalTo: glass.leadingAnchor),
            content.trailingAnchor.constraint(equalTo: glass.trailingAnchor),
            content.topAnchor.constraint(equalTo: glass.topAnchor),
            content.bottomAnchor.constraint(equalTo: glass.bottomAnchor),
        ])
        surface.addSubview(glass)
        contentView = surface

        // Keep text drawing separate from the glass material.
        textView.wantsLayer = true
        textView.isRichText = false
        // Keep macOS Writing Tools / Siri assistance out of the transient composer.
        textView.writingToolsBehavior = .none
        textView.isEditable = true
        textView.isSelectable = true
        textView.drawsBackground = false
        textView.font = .systemFont(ofSize: 18, weight: .regular)
        textView.setAccessibilityLabel("Message")
        textView.textColor = .labelColor
        textView.insertionPointColor = .labelColor
        textView.textContainerInset = .zero
        textView.textContainer?.lineFragmentPadding = 0
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        textView.delegate = self

        scroll.wantsLayer = true
        scroll.contentView.wantsLayer = true
        scroll.documentView = textView
        scroll.drawsBackground = false
        scroll.contentView.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.scrollerStyle = .overlay
        scroll.borderType = .noBorder
        scroll.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(scroll)

        attachment.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(attachment)
        attachmentWidth = attachment.widthAnchor.constraint(equalToConstant: previewSize.width)
        attachmentHeight = attachment.heightAnchor.constraint(equalToConstant: previewSize.height)

        sendButton.image = NSImage(systemSymbolName: "paperplane", accessibilityDescription: "Send")
        sendButton.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 13, weight: .medium)
            .applying(NSImage.SymbolConfiguration(paletteColors: [.labelColor]))
        sendButton.imagePosition = .imageOnly
        sendButton.target = self
        sendButton.action = #selector(submitMessage)
        sendButton.toolTip = "Send capture"
        sendButton.setAccessibilityLabel("Send image and message")
        sendButton.imageScaling = .scaleProportionallyDown
        sendButton.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(sendButton)

        // Bottom destination dock. Hidden when DSH is off so the original
        // compact composer is unchanged for non-DSH users.
        sendToLabel.font = .systemFont(ofSize: 10.5, weight: .medium)
        sendToLabel.textColor = .secondaryLabelColor
        sendToLabel.translatesAutoresizingMaskIntoConstraints = false
        targetDock.translatesAutoresizingMaskIntoConstraints = false
        targetDock.addSubview(sendToLabel)
        targetChip.translatesAutoresizingMaskIntoConstraints = false
        targetChip.onClick = { [weak self] in self?.presentSessionPicker() }
        targetDock.addSubview(targetChip)
        content.addSubview(targetDock)
        scrollBottomDefault = scroll.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -18)
        scrollBottomWithDock = scroll.bottomAnchor.constraint(equalTo: targetDock.topAnchor, constant: -10)
        scrollBottomDefault.isActive = true

        NSLayoutConstraint.activate([
            attachment.topAnchor.constraint(equalTo: content.topAnchor, constant: 16),
            attachment.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 18),
            attachmentWidth, attachmentHeight,
            scroll.topAnchor.constraint(equalTo: attachment.bottomAnchor, constant: 14),
            scroll.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 20),
            scroll.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -64),
            sendButton.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -16),
            sendButton.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -16),
            sendButton.widthAnchor.constraint(equalToConstant: 30),
            sendButton.heightAnchor.constraint(equalToConstant: 30),
            targetDock.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 20),
            targetDock.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -16),
            targetDock.heightAnchor.constraint(equalToConstant: 30),
            targetDock.trailingAnchor.constraint(lessThanOrEqualTo: sendButton.leadingAnchor, constant: -8),
            sendToLabel.leadingAnchor.constraint(equalTo: targetDock.leadingAnchor),
            sendToLabel.centerYAnchor.constraint(equalTo: targetDock.centerYAnchor),
            targetChip.leadingAnchor.constraint(equalTo: sendToLabel.trailingAnchor, constant: 7),
            targetChip.centerYAnchor.constraint(equalTo: targetDock.centerYAnchor),
            targetChip.trailingAnchor.constraint(equalTo: targetDock.trailingAnchor),
            targetChip.heightAnchor.constraint(equalToConstant: 30),
        ])
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func sendEvent(_ event: NSEvent) {
        if event.type == .leftMouseDown, let contentView {
            let point = contentView.convert(event.locationInWindow, from: nil)
            if let hit = contentView.hitTest(point),
               !hit.isDescendant(of: scroll), !hit.isDescendant(of: sendButton),
               !hit.isDescendant(of: targetDock) {
                // AppKit owns tracking, display transitions, and the mouse-up. Controls
                // keep their normal events, including selection inside the message.
                userPositioned = true
                performDrag(with: event)
                return
            }
        }
        super.sendEvent(event)
    }

    func present(near rect: NSRect, on screen: NSScreen) {
        userPositioned = false
        selection = rect
        placementScreen = screen
        inputWidth = min(480, screen.visibleFrame.width - 32)
        let scale = min(240 / max(rect.width, 1), 144 / max(rect.height, 1), 1)
        previewSize = NSSize(width: max(56, rect.width * scale), height: max(56, rect.height * scale))
        attachmentWidth.constant = previewSize.width
        attachmentHeight.constant = previewSize.height
        attachment.prepare()
        dismissSessionPicker(restoreFocus: false)
        let dockVisible = DSHIntegration.shared.isEnabled
        targetDock.isHidden = !dockVisible
        scrollBottomDefault.isActive = !dockVisible
        scrollBottomWithDock.isActive = dockVisible
        targetChip.title = DSHIntegration.shared.targetLabel
        targetChip.setAccessibilityValue(DSHIntegration.shared.targetAccessibilityLabel)
        let initialHeight = 16 + previewSize.height + 14 + 26 + 18 + (dockVisible ? 38 : 0)
        placeAbove = rect.minY - initialHeight - 14 < screen.visibleFrame.minY + 16
        textView.string = ""
        textView.setSelectedRange(NSRange(location: 0, length: 0))
        resizeToFit()
        contentView?.layoutSubtreeIfNeeded()

        alphaValue = 1
        makeKeyAndOrderFront(nil)
        makeFirstResponder(textView)
        Log.write("input opened: empty=\(textView.string.isEmpty), editorFocused=\(firstResponder === textView)")
    }

    func attach(_ image: CGImage) {
        attachment.setImage(image)
    }

    @objc private func submitMessage() {
        onSubmit?(textView.string)
    }

    private func resizeToFit() {
        let layoutScreen = userPositioned ? (screen ?? placementScreen) : placementScreen
        guard let screen = layoutScreen, let container = textView.textContainer,
              let layout = textView.layoutManager else { return }
        container.containerSize = NSSize(width: inputWidth - 84, height: CGFloat.greatestFiniteMagnitude)
        layout.ensureLayout(for: container)
        let usedHeight = layout.usedRect(for: container).height
        let textHeight = min(max(26, ceil(usedHeight)), 130)
        let dockVisible = DSHIntegration.shared.isEnabled
        let height = 16 + previewSize.height + 14 + textHeight + 18 + (dockVisible ? 38 : 0)
        let visible = screen.visibleFrame
        let proposedX = userPositioned ? frame.minX : selection.midX - inputWidth / 2
        let x = min(max(proposedX, visible.minX + 16), visible.maxX - inputWidth - 16)
        let proposedY: CGFloat
        if userPositioned {
            // Grow downward from the user's chosen top edge, not the original capture.
            proposedY = frame.maxY - height
        } else {
            proposedY = placeAbove ? selection.maxY + 14 : selection.minY - height - 14
        }
        let y = min(max(proposedY, visible.minY + 16), visible.maxY - height - 16)
        let target = NSRect(x: x, y: y, width: inputWidth, height: height)
        guard frame != target else { return }
        // Resize the actual text surface, not an animated snapshot of its previous contents.
        setFrame(target, display: true)
        contentView?.needsDisplay = true
        contentView?.layoutSubtreeIfNeeded()
        invalidateShadow()
    }

    func windowDidResignKey(_ notification: Notification) {
        // The session picker is a sibling key window; resigning to it is not a
        // reason to throw away the draft.
        guard isVisible, !isKeyWindow, sessionPicker == nil else { return }
        Log.write("input dismissed: keyboard focus moved away")
        onCancel?()
    }

    func textView(_ textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        switch selector {
        case #selector(NSResponder.insertNewline(_:)):
            if textView.hasMarkedText() { return false }
            if NSApp.currentEvent?.modifierFlags.contains(.shift) == true { return false }
            submitMessage()
            return true
        case #selector(NSResponder.cancelOperation(_:)):
            if textView.hasMarkedText() { return false }
            onCancel?()
            return true
        default:
            return false
        }
    }

    // MARK: - Session picker

    var isSessionPickerVisible: Bool { sessionPicker != nil }

    func presentSessionPicker() {
        guard DSHIntegration.shared.isEnabled, sessionPicker == nil, isVisible else { return }
        // A click on the chip while the picker is open closes it and then reaches
        // the chip. Do not immediately reopen on that same click.
        guard ProcessInfo.processInfo.systemUptime - pickerClosedAt > 0.25 else { return }
        let picker = SessionPickerWindow()
        picker.target = DSHIntegration.shared.target
        picker.onSelect = { [weak self] selection in
            guard let self else { return }
            switch selection {
            case .new:
                DSHIntegration.shared.target = .new
            case .session(let session):
                DSHIntegration.shared.target = .session(id: session.id, title: session.title)
            }
            self.targetChip.title = DSHIntegration.shared.targetLabel
            self.targetChip.setAccessibilityValue(DSHIntegration.shared.targetAccessibilityLabel)
            self.dismissSessionPicker(restoreFocus: true)
        }
        picker.onDismiss = { [weak self] in self?.dismissSessionPicker(restoreFocus: true) }
        sessionPicker = picker
        let anchor = targetChip.window?.convertToScreen(targetChip.convert(targetChip.bounds, to: nil))
            ?? NSRect(x: frame.midX, y: frame.minY, width: 1, height: 1)
        picker.present(above: anchor, on: screen ?? placementScreen, panelFrame: frame)
        Log.write("session picker opened")
    }

    func dismissSessionPicker(restoreFocus: Bool = true) {
        guard let picker = sessionPicker else { return }
        sessionPicker = nil
        pickerClosedAt = ProcessInfo.processInfo.systemUptime
        picker.onSelect = nil
        picker.onDismiss = nil
        picker.orderOut(nil)
        if restoreFocus, isVisible {
            makeKeyAndOrderFront(nil)
            makeFirstResponder(textView)
        }
    }

    func closeSessionPicker() {
        dismissSessionPicker(restoreFocus: false)
    }

    /// The global event tap asks the composer first. A click inside the popover
    /// is passed through; a click outside closes it and keeps the draft.
    func handleOutsideInteraction(at point: NSPoint) -> Bool {
        guard let picker = sessionPicker else { return false }
        if picker.frame.contains(point) { return false }
        dismissSessionPicker(restoreFocus: true)
        return true
    }

#if DRAGSHOT_TESTING
    var testPickerVisible: Bool { isSessionPickerVisible }
    var testEditorFocused: Bool { firstResponder === textView }

    func testTypeSlash() {
        textView.insertText("/", replacementRange: NSRange(location: 0, length: 0))
    }

    func setDraftForTesting(_ text: String) {
        textView.string = text
        textView.setSelectedRange(NSRange(location: (text as NSString).length, length: 0))
        resizeToFit()
    }
#endif

    func textDidChange(_ notification: Notification) {
        if !isClearingSlash,
           DSHIntegration.shared.isEnabled,
           sessionPicker == nil,
           !textView.hasMarkedText(),
           textView.string == "/",
           textView.selectedRange().location == 1 {
            // DSH-style command entry: a leading slash opens the picker and is
            // consumed. A slash after text remains literal.
            isClearingSlash = true
            textView.string = ""
            textView.setSelectedRange(NSRange(location: 0, length: 0))
            isClearingSlash = false
            resizeToFit()
            presentSessionPicker()
            return
        }
        resizeToFit()
    }
}

/// Clear the window's backing surface independently of the glass compositor and editor.
private final class InputSurface: NSView {
    private let silhouette = CAShapeLayer()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.mask = silhouette
    }

    required init?(coder: NSCoder) {
        fatalError("InputSurface is constructed programmatically")
    }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        silhouette.frame = bounds
        silhouette.path = CGPath(roundedRect: bounds, cornerWidth: 22, cornerHeight: 22, transform: nil)
        CATransaction.commit()
    }

    override var isOpaque: Bool { false }
    override func draw(_ dirtyRect: NSRect) {
        NSGraphicsContext.current?.cgContext.clear(dirtyRect)
    }
}

/// A stable attachment slot keeps the editor still while screen capture finishes.
private final class AttachmentPreview: NSView {
    private let imageView = NSImageView()
    private let progress = NSProgressIndicator()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.cornerRadius = 12
        layer?.masksToBounds = true
        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.wantsLayer = true
        imageView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(imageView)
        progress.style = .spinning
        progress.controlSize = .small
        progress.isDisplayedWhenStopped = false
        progress.translatesAutoresizingMaskIntoConstraints = false
        addSubview(progress)
        NSLayoutConstraint.activate([
            imageView.leadingAnchor.constraint(equalTo: leadingAnchor),
            imageView.trailingAnchor.constraint(equalTo: trailingAnchor),
            imageView.topAnchor.constraint(equalTo: topAnchor),
            imageView.bottomAnchor.constraint(equalTo: bottomAnchor),
            progress.centerXAnchor.constraint(equalTo: centerXAnchor),
            progress.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
        setAccessibilityElement(true)
        setAccessibilityRole(.image)
        setAccessibilityLabel("Screenshot attachment")
    }

    required init?(coder: NSCoder) {
        fatalError("AttachmentPreview is constructed programmatically")
    }

    override var wantsUpdateLayer: Bool { true }

    override func updateLayer() {
        layer?.backgroundColor = NSColor.quaternaryLabelColor.cgColor
        layer?.borderColor = NSColor.separatorColor.withAlphaComponent(0.2).cgColor
        layer?.borderWidth = 0.5
    }

    func prepare() {
        imageView.image = nil
        imageView.layer?.removeAllAnimations()
        progress.stopAnimation(nil)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
            guard let self, self.imageView.image == nil, self.window?.isVisible == true else { return }
            self.progress.startAnimation(nil)
        }
    }

    func setImage(_ image: CGImage) {
        progress.stopAnimation(nil)
        imageView.image = NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height))
        setAccessibilityLabel("Screenshot attachment, \(image.width) by \(image.height) pixels")
        guard window?.isVisible == true,
              !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else { return }
        // Animate only the arriving image; the caret and composer never move or fade.
        let reveal = CABasicAnimation(keyPath: "opacity")
        reveal.fromValue = 0
        reveal.toValue = 1
        reveal.duration = 0.16
        imageView.layer?.add(reveal, forKey: "attachmentReveal")
        let settle = CABasicAnimation(keyPath: "transform.translation.y")
        settle.fromValue = -5
        settle.toValue = 0
        settle.duration = 0.18
        settle.timingFunction = CAMediaTimingFunction(name: .easeOut)
        imageView.layer?.add(settle, forKey: "attachmentSettle")
    }
}
