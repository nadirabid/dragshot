import Cocoa

enum BrandAssets {
    /// The official DSH whale mark, generated into the app bundle as a blue PNG.
    static let whale: NSImage? = {
        // NSImage(named:) picks up the @2x representation as well as the 1x.
        if let image = NSImage(named: "whale") { return image }
        if let url = Bundle.main.url(forResource: "whale", withExtension: "png"),
           let image = NSImage(contentsOf: url) {
            return image
        }
        return NSImage(systemSymbolName: "fish.fill", accessibilityDescription: "DSH")
    }()

    static func whaleView() -> NSImageView {
        let view = NSImageView()
        view.image = whale
        view.imageScaling = .scaleProportionallyUpOrDown
        view.contentTintColor = .controlAccentColor
        view.setAccessibilityLabel("DeepSeek Harness")
        return view
    }
}

/// The compact bottom dock chip: whale, DSH, current target, chevron.
/// It draws itself so the glass composer keeps one consistent visual language.
final class TargetChipView: NSView {
    var onClick: (() -> Void)?

    private let whale = BrandAssets.whaleView()
    private let agentLabel = NSTextField(labelWithString: "DSH")
    private let dotLabel = NSTextField(labelWithString: "·")
    private let titleLabel = NSTextField(labelWithString: "")
    private let chevron = NSImageView()
    private var hover = false
    private var pressed = false

    private let horizontalPadding: CGFloat = 8
    private let whaleWidth: CGFloat = 20
    private let gap: CGFloat = 6
    private let chevronWidth: CGFloat = 9
    private var widthConstraint: NSLayoutConstraint!
    private let chipHeight: CGFloat = 30
    private let maxTitleWidth: CGFloat = 230
    private let titleSafety: CGFloat = 24

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.cornerRadius = chipHeight / 2
        layer?.borderWidth = 1

        whale.translatesAutoresizingMaskIntoConstraints = true
        agentLabel.font = .systemFont(ofSize: 9.5, weight: .bold)
        agentLabel.textColor = .secondaryLabelColor
        agentLabel.alignment = .left
        agentLabel.maximumNumberOfLines = 1
        dotLabel.font = .systemFont(ofSize: 11, weight: .regular)
        dotLabel.textColor = .tertiaryLabelColor
        dotLabel.alignment = .center
        titleLabel.font = .systemFont(ofSize: 12, weight: .medium)
        titleLabel.textColor = .labelColor
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.maximumNumberOfLines = 1
        [whale, agentLabel, dotLabel, titleLabel, chevron].forEach(addSubview)

        chevron.image = NSImage(systemSymbolName: "chevron.down", accessibilityDescription: nil)
        chevron.contentTintColor = .tertiaryLabelColor
        chevron.imageScaling = .scaleProportionallyUpOrDown
        chevron.translatesAutoresizingMaskIntoConstraints = true

        setAccessibilityElement(true)
        setAccessibilityRole(.button)
        setAccessibilityLabel("Send target")
        setContentCompressionResistancePriority(.defaultHigh, for: .horizontal)
        setContentHuggingPriority(.defaultHigh, for: .horizontal)
        widthConstraint = widthAnchor.constraint(equalToConstant: 10)
        widthConstraint.priority = NSLayoutConstraint.Priority(999)
        widthConstraint.isActive = true
    }

    required init?(coder: NSCoder) {
        fatalError("TargetChipView is constructed programmatically")
    }

    func configure(harness: Harness) {
        agentLabel.stringValue = harness == .deepseek ? "DSH" : harness.title
        whale.image = harness == .deepseek ? BrandAssets.whale : harness.appURL.map { NSWorkspace.shared.icon(forFile: $0.path) }
        whale.contentTintColor = nil
        whale.setAccessibilityLabel(harness.title)
        chevron.isHidden = harness != .deepseek
        setAccessibilityRole(harness == .deepseek ? .button : .staticText)
    }

    var title: String {
        get { titleLabel.stringValue }
        set {
            titleLabel.stringValue = newValue
            setAccessibilityValue(newValue)
            toolTip = newValue
            invalidateIntrinsicContentSize()
            widthConstraint.constant = naturalWidth
            needsLayout = true
        }
    }

    private var naturalWidth: CGFloat {
        func textWidth(_ field: NSTextField) -> CGFloat {
            let font = field.font ?? NSFont.systemFont(ofSize: 12, weight: .regular)
            return ceil((field.stringValue as NSString).size(withAttributes: [.font: font]).width)
        }
        let agentWidth = textWidth(agentLabel)
        let dotWidth = textWidth(dotLabel)
        let titleWidth = min(textWidth(titleLabel), maxTitleWidth)
        return horizontalPadding * 2 + whaleWidth + gap
            + agentWidth + gap + dotWidth + gap
            + titleWidth + gap + chevronWidth + titleSafety
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: naturalWidth, height: chipHeight)
    }

    override func layout() {
        super.layout()
        let top: CGFloat = (bounds.height - 15) / 2
        var x = horizontalPadding
        whale.frame = NSRect(x: x, y: top, width: whaleWidth, height: 15)
        x += whaleWidth + gap

        let agentSize = agentLabel.intrinsicContentSize
        agentLabel.frame = NSRect(x: x, y: (bounds.height - agentSize.height) / 2,
                                  width: ceil(agentSize.width), height: agentSize.height)
        x += ceil(agentSize.width) + gap

        let dotSize = dotLabel.intrinsicContentSize
        dotLabel.frame = NSRect(x: x, y: (bounds.height - dotSize.height) / 2,
                                width: ceil(dotSize.width), height: dotSize.height)
        x += ceil(dotSize.width) + gap

        let chevronX = bounds.width - horizontalPadding - chevronWidth
        let titleWidth = max(0, chevronX - gap - x)
        titleLabel.frame = NSRect(x: x, y: (bounds.height - 18) / 2,
                                  width: titleWidth, height: 18)
        chevron.frame = NSRect(x: chevronX, y: (bounds.height - chevronWidth) / 2,
                               width: chevronWidth, height: chevronWidth)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in trackingAreas { removeTrackingArea(area) }
        addTrackingArea(NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
            owner: self,
            userInfo: nil
        ))
    }

    override func mouseEntered(with event: NSEvent) {
        hover = true
        updateLayer()
    }

    override func mouseExited(with event: NSEvent) {
        hover = false
        pressed = false
        updateLayer()
    }

    override func mouseDown(with event: NSEvent) {
        pressed = true
        updateLayer()
    }

    override func mouseUp(with event: NSEvent) {
        let inside = bounds.contains(convert(event.locationInWindow, from: nil))
        pressed = false
        updateLayer()
        if inside { onClick?() }
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override var wantsUpdateLayer: Bool { true }

    override func updateLayer() {
        guard let layer else { return }
        let dark = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        let base = dark
            ? NSColor.white.withAlphaComponent(0.10)
            : NSColor.white.withAlphaComponent(0.54)
        let hovered = hover || pressed
        layer.backgroundColor = (hovered
            ? base.blended(withFraction: 0.12, of: .controlAccentColor) ?? base
            : base).cgColor
        layer.borderColor = (dark
            ? NSColor.white.withAlphaComponent(0.16)
            : NSColor.white.withAlphaComponent(0.80)).cgColor
        layer.cornerRadius = chipHeight / 2
        layer.masksToBounds = true
    }
}
