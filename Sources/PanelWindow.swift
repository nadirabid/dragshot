import Cocoa
import QuartzCore

/// A transient glass input surface. The system owns the material and its rounded silhouette.
final class PanelWindow: NSPanel, NSTextViewDelegate, NSWindowDelegate {
    var onSubmit: ((String) -> Void)?
    var onCancel: (() -> Void)?

    private let textView = NSTextView()
    private let scroll = NSScrollView()
    private let attachment = AttachmentPreview()
    private let sendButton = NSButton()
    private var attachmentWidth: NSLayoutConstraint!
    private var attachmentHeight: NSLayoutConstraint!
    private var previewSize = NSSize(width: 240, height: 132)
    private var selection = NSRect.zero
    private var placementScreen: NSScreen?
    private var placeAbove = false
    private var inputWidth: CGFloat = 480
    private var userPositioned = false

    init() {
        super.init(contentRect: NSRect(x: 0, y: 0, width: 480, height: 68),
                   styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        level = NSWindow.Level(rawValue: Int(CGShieldingWindowLevel()) + 1)
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        isMovable = true
        isReleasedWhenClosed = false
        hidesOnDeactivate = false
        becomesKeyOnlyIfNeeded = false
        animationBehavior = .none
        delegate = self

        let surface = InputSurface(frame: NSRect(x: 0, y: 0, width: 480, height: 68))
        surface.wantsLayer = true
        let glass = NSGlassEffectView(frame: surface.bounds)
        glass.autoresizingMask = [.width, .height]
        glass.style = .regular
        glass.cornerRadius = 22
        let content = NSView()
        content.wantsLayer = true
        glass.contentView = content
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

        sendButton.isBordered = true
        sendButton.bezelStyle = .accessoryBarAction
        sendButton.showsBorderOnlyWhileMouseInside = true
        sendButton.image = NSImage(systemSymbolName: "paperplane", accessibilityDescription: "Send")
        sendButton.symbolConfiguration = NSImage.SymbolConfiguration(paletteColors: [.labelColor])
            .applying(NSImage.SymbolConfiguration(pointSize: 17, weight: .medium))
        sendButton.imagePosition = .imageOnly
        sendButton.target = self
        sendButton.action = #selector(submitMessage)
        sendButton.toolTip = "Send capture"
        sendButton.setAccessibilityLabel("Send image and message")
        sendButton.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(sendButton)

        NSLayoutConstraint.activate([
            attachment.topAnchor.constraint(equalTo: content.topAnchor, constant: 16),
            attachment.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 18),
            attachmentWidth, attachmentHeight,
            scroll.topAnchor.constraint(equalTo: attachment.bottomAnchor, constant: 14),
            scroll.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -18),
            scroll.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 20),
            scroll.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -64),
            sendButton.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -14),
            sendButton.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -12),
            sendButton.widthAnchor.constraint(equalToConstant: 36),
            sendButton.heightAnchor.constraint(equalToConstant: 36),
        ])
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func sendEvent(_ event: NSEvent) {
        if event.type == .leftMouseDown, let contentView {
            let point = contentView.convert(event.locationInWindow, from: nil)
            if let hit = contentView.hitTest(point),
               !hit.isDescendant(of: scroll), !hit.isDescendant(of: sendButton) {
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
        let initialHeight = 16 + previewSize.height + 14 + 26 + 18
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
        let height = 16 + previewSize.height + 14 + textHeight + 18
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
        guard isVisible, !isKeyWindow else { return }
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

    func textDidChange(_ notification: Notification) {
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
