import Cocoa

/// One selectable row in the session picker.
private final class SessionPickerRow: NSView {
    var onClick: (() -> Void)?

    private let iconContainer = NSView()
    private let whale = NSImageView()
    private let newIcon = NSImageView()
    private let titleLabel = NSTextField(labelWithString: "")
    private let subtitleLabel = NSTextField(labelWithString: "")
    private let check = NSImageView()
    private var hover = false
    private var pressed = false

    var selected = false {
        didSet { updateAppearance() }
    }

    var title: String {
        get { titleLabel.stringValue }
        set { titleLabel.stringValue = newValue; setAccessibilityLabel(newValue) }
    }

    var subtitle: String {
        get { subtitleLabel.stringValue }
        set {
            if newValue.hasPrefix("● Running") {
                let font = NSFont.systemFont(ofSize: 10.5, weight: .regular)
                let text = NSMutableAttributedString(
                    string: "●",
                    attributes: [.font: font, .foregroundColor: NSColor.systemGreen]
                )
                text.append(NSAttributedString(
                    string: String(newValue.dropFirst(1)),
                    attributes: [.font: font, .foregroundColor: NSColor.secondaryLabelColor]
                ))
                subtitleLabel.attributedStringValue = text
            } else {
                subtitleLabel.stringValue = newValue
            }
        }
    }

    init(newSession: Bool) {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 9

        iconContainer.wantsLayer = true
        iconContainer.layer?.cornerRadius = 7
        iconContainer.translatesAutoresizingMaskIntoConstraints = false
        addSubview(iconContainer)

        whale.image = BrandAssets.whale
        whale.imageScaling = .scaleProportionallyUpOrDown
        whale.translatesAutoresizingMaskIntoConstraints = false
        iconContainer.addSubview(whale)

        newIcon.image = NSImage(systemSymbolName: "bubble.left", accessibilityDescription: "New chat")
        newIcon.contentTintColor = .controlAccentColor
        newIcon.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 13, weight: .medium)
        newIcon.translatesAutoresizingMaskIntoConstraints = false
        iconContainer.addSubview(newIcon)

        whale.isHidden = newSession
        newIcon.isHidden = !newSession
        iconContainer.layer?.backgroundColor = newSession
            ? NSColor.controlAccentColor.withAlphaComponent(0.12).cgColor
            : NSColor.clear.cgColor

        titleLabel.font = .systemFont(ofSize: 12.5, weight: newSession ? .semibold : .medium)
        titleLabel.textColor = .labelColor
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.maximumNumberOfLines = 1
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(titleLabel)

        subtitleLabel.font = .systemFont(ofSize: 10.5, weight: .regular)
        subtitleLabel.textColor = .secondaryLabelColor
        subtitleLabel.lineBreakMode = .byTruncatingTail
        subtitleLabel.maximumNumberOfLines = 1
        subtitleLabel.translatesAutoresizingMaskIntoConstraints = false
        subtitleLabel.isHidden = newSession
        addSubview(subtitleLabel)

        check.image = NSImage(systemSymbolName: "checkmark", accessibilityDescription: "Selected")
        check.contentTintColor = .controlAccentColor
        check.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 12, weight: .semibold)
        check.translatesAutoresizingMaskIntoConstraints = false
        check.isHidden = true
        addSubview(check)

        let titleTop = titleLabel.topAnchor.constraint(equalTo: topAnchor, constant: 7)
        let titleCenter = titleLabel.centerYAnchor.constraint(equalTo: centerYAnchor)
        titleTop.isActive = !newSession
        titleCenter.isActive = newSession

        NSLayoutConstraint.activate([
            iconContainer.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            iconContainer.centerYAnchor.constraint(equalTo: centerYAnchor),
            iconContainer.widthAnchor.constraint(equalToConstant: 24),
            iconContainer.heightAnchor.constraint(equalToConstant: 24),

            whale.leadingAnchor.constraint(equalTo: iconContainer.leadingAnchor),
            whale.trailingAnchor.constraint(equalTo: iconContainer.trailingAnchor),
            whale.topAnchor.constraint(equalTo: iconContainer.topAnchor),
            whale.bottomAnchor.constraint(equalTo: iconContainer.bottomAnchor),

            newIcon.centerXAnchor.constraint(equalTo: iconContainer.centerXAnchor),
            newIcon.centerYAnchor.constraint(equalTo: iconContainer.centerYAnchor),
            newIcon.widthAnchor.constraint(equalToConstant: 14),
            newIcon.heightAnchor.constraint(equalToConstant: 14),

            titleLabel.leadingAnchor.constraint(equalTo: iconContainer.trailingAnchor, constant: 9),
            titleLabel.trailingAnchor.constraint(equalTo: check.leadingAnchor, constant: -6),

            subtitleLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            subtitleLabel.trailingAnchor.constraint(equalTo: titleLabel.trailingAnchor),
            subtitleLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 1),

            check.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            check.centerYAnchor.constraint(equalTo: centerYAnchor),
            check.widthAnchor.constraint(equalToConstant: 13),
            check.heightAnchor.constraint(equalToConstant: 13),
        ])

        setAccessibilityElement(true)
        setAccessibilityRole(.button)
        setAccessibilityLabel(newSession ? "New chat" : "Session")
        toolTip = nil
    }

    required init?(coder: NSCoder) {
        fatalError("SessionPickerRow is constructed programmatically")
    }

    override var wantsUpdateLayer: Bool { true }

    override func updateLayer() {
        guard let layer else { return }
        let base: NSColor = selected
            ? NSColor.controlAccentColor.withAlphaComponent(0.11)
            : (hover ? NSColor.labelColor.withAlphaComponent(0.045) : .clear)
        layer.backgroundColor = base.cgColor
    }

    private func updateAppearance() {
        check.isHidden = !selected
        needsDisplay = true
        updateLayer()
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
}

/// The searchable session list. It is a floating, nonactivating panel so the
/// composer's window can regain key focus when it closes.
final class SessionPickerWindow: NSPanel, NSTextFieldDelegate {
    enum Selection {
        case new
        case session(DSHSession)
    }

    var onSelect: ((Selection) -> Void)?
    var onDismiss: (() -> Void)?
    var target: DSHIntegration.Target = .recent

    private let searchBox = NSView()
    private let searchIcon = NSImageView()
    private let searchField = NSTextField()
    private let clearButton = NSButton()
    private let newRow = SessionPickerRow(newSession: true)
    private let sectionLabel = NSTextField(labelWithString: "RECENT")
    private let countLabel = NSTextField(labelWithString: "")
    private let scroll = NSScrollView()
    private let list = NSStackView()
    private var listHeightConstraint: NSLayoutConstraint!
    private var contentViewBox: NSView!

    private var sessions: [DSHSession] = []
    private var visibleSessions: [DSHSession] = []
    private var rows: [SessionPickerRow] = []
    private var selectedIndex = 0
    private var loading = true
    private var errorText: String?
    private var query = ""
    private var anchor = NSRect.zero
    private var panelFrame = NSRect.zero
    private var anchorScreen: NSScreen?
    private var isDismissing = false
    private var hasPresented = false

    private let panelWidth: CGFloat = 340
    private let rowHeight: CGFloat = 40
    private let maxVisibleRows = 5
    private let baseHeight: CGFloat = 126

    init() {
        super.init(contentRect: NSRect(x: 0, y: 0, width: 340, height: 260),
                   styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered, defer: false)
        level = NSWindow.Level(rawValue: Int(CGShieldingWindowLevel()) + 2)
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        isReleasedWhenClosed = false
        hidesOnDeactivate = false
        becomesKeyOnlyIfNeeded = false
        animationBehavior = .none

        let surface = NSView(frame: NSRect(x: 0, y: 0, width: panelWidth, height: 260))
        surface.wantsLayer = true
        surface.layer?.cornerRadius = 18
        surface.layer?.masksToBounds = true

        let glass = GlassSurfaceView(cornerRadius: 18)
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
        contentViewBox = content

        configureSearch()
        configureRows()
        configureList()
        layoutPicker()

        newRow.onClick = { [weak self] in self?.commit(index: 0) }
    }

    required init?(coder: NSCoder) {
        fatalError("SessionPickerWindow is constructed programmatically")
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    // MARK: - Construction

    private func configureSearch() {
        searchBox.wantsLayer = true
        searchBox.layer?.cornerRadius = 9
        searchBox.layer?.backgroundColor = NSColor.labelColor.withAlphaComponent(0.065).cgColor
        searchBox.layer?.borderWidth = 1
        searchBox.layer?.borderColor = NSColor.controlAccentColor.withAlphaComponent(0.42).cgColor
        searchBox.translatesAutoresizingMaskIntoConstraints = false
        contentViewBox.addSubview(searchBox)

        searchIcon.image = NSImage(systemSymbolName: "magnifyingglass", accessibilityDescription: nil)
        searchIcon.contentTintColor = .secondaryLabelColor
        searchIcon.imageScaling = .scaleProportionallyUpOrDown
        searchIcon.translatesAutoresizingMaskIntoConstraints = false
        searchBox.addSubview(searchIcon)

        searchField.isBordered = false
        searchField.isBezeled = false
        searchField.drawsBackground = false
        searchField.focusRingType = .none
        searchField.font = .systemFont(ofSize: 12.5, weight: .regular)
        searchField.textColor = .labelColor
        searchField.placeholderString = "Search sessions"
        searchField.delegate = self
        searchField.usesSingleLineMode = true
        searchField.cell?.wraps = false
        searchField.cell?.isScrollable = true
        searchField.setAccessibilityLabel("Search sessions")
        searchField.translatesAutoresizingMaskIntoConstraints = false
        searchBox.addSubview(searchField)

        clearButton.isBordered = false
        clearButton.image = NSImage(systemSymbolName: "xmark.circle.fill", accessibilityDescription: "Clear search")
        clearButton.contentTintColor = .tertiaryLabelColor
        clearButton.target = self
        clearButton.action = #selector(clearSearch)
        clearButton.isHidden = true
        clearButton.translatesAutoresizingMaskIntoConstraints = false
        searchBox.addSubview(clearButton)

        NSLayoutConstraint.activate([
            searchIcon.leadingAnchor.constraint(equalTo: searchBox.leadingAnchor, constant: 9),
            searchIcon.centerYAnchor.constraint(equalTo: searchBox.centerYAnchor),
            searchIcon.widthAnchor.constraint(equalToConstant: 13),
            searchIcon.heightAnchor.constraint(equalToConstant: 13),

            searchField.leadingAnchor.constraint(equalTo: searchIcon.trailingAnchor, constant: 7),
            searchField.trailingAnchor.constraint(equalTo: clearButton.leadingAnchor, constant: -4),
            searchField.centerYAnchor.constraint(equalTo: searchBox.centerYAnchor),
            searchField.heightAnchor.constraint(equalToConstant: 20),

            clearButton.trailingAnchor.constraint(equalTo: searchBox.trailingAnchor, constant: -8),
            clearButton.centerYAnchor.constraint(equalTo: searchBox.centerYAnchor),
            clearButton.widthAnchor.constraint(equalToConstant: 16),
            clearButton.heightAnchor.constraint(equalToConstant: 16),
        ])
    }

    private func configureRows() {
        newRow.translatesAutoresizingMaskIntoConstraints = false
        newRow.title = "New chat"
        contentViewBox.addSubview(newRow)

        sectionLabel.font = .systemFont(ofSize: 9, weight: .bold)
        sectionLabel.textColor = .secondaryLabelColor
        sectionLabel.translatesAutoresizingMaskIntoConstraints = false
        contentViewBox.addSubview(sectionLabel)

        countLabel.font = .systemFont(ofSize: 9, weight: .medium)
        countLabel.textColor = .tertiaryLabelColor
        countLabel.alignment = .right
        countLabel.translatesAutoresizingMaskIntoConstraints = false
        contentViewBox.addSubview(countLabel)
    }

    private func configureList() {
        scroll.drawsBackground = false
        scroll.contentView.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.scrollerStyle = .overlay
        scroll.borderType = .noBorder
        scroll.translatesAutoresizingMaskIntoConstraints = false
        contentViewBox.addSubview(scroll)

        list.orientation = .vertical
        list.alignment = .width
        list.distribution = .fill
        list.spacing = 2
        list.translatesAutoresizingMaskIntoConstraints = false
        scroll.documentView = list
        listHeightConstraint = list.heightAnchor.constraint(equalToConstant: 40)
        NSLayoutConstraint.activate([
            list.leadingAnchor.constraint(equalTo: scroll.contentView.leadingAnchor),
            list.trailingAnchor.constraint(equalTo: scroll.contentView.trailingAnchor),
            list.topAnchor.constraint(equalTo: scroll.contentView.topAnchor),
            list.widthAnchor.constraint(equalTo: scroll.contentView.widthAnchor),
            listHeightConstraint,
        ])
    }

    private func layoutPicker() {
        NSLayoutConstraint.activate([
            searchBox.topAnchor.constraint(equalTo: contentViewBox.topAnchor, constant: 10),
            searchBox.leadingAnchor.constraint(equalTo: contentViewBox.leadingAnchor, constant: 10),
            searchBox.trailingAnchor.constraint(equalTo: contentViewBox.trailingAnchor, constant: -10),
            searchBox.heightAnchor.constraint(equalToConstant: 34),

            newRow.topAnchor.constraint(equalTo: searchBox.bottomAnchor, constant: 8),
            newRow.leadingAnchor.constraint(equalTo: contentViewBox.leadingAnchor, constant: 10),
            newRow.trailingAnchor.constraint(equalTo: contentViewBox.trailingAnchor, constant: -10),
            newRow.heightAnchor.constraint(equalToConstant: rowHeight),

            sectionLabel.topAnchor.constraint(equalTo: newRow.bottomAnchor, constant: 8),
            sectionLabel.leadingAnchor.constraint(equalTo: contentViewBox.leadingAnchor, constant: 18),
            sectionLabel.heightAnchor.constraint(equalToConstant: 14),

            countLabel.centerYAnchor.constraint(equalTo: sectionLabel.centerYAnchor),
            countLabel.trailingAnchor.constraint(equalTo: contentViewBox.trailingAnchor, constant: -18),
            countLabel.leadingAnchor.constraint(greaterThanOrEqualTo: sectionLabel.trailingAnchor, constant: 8),

            scroll.topAnchor.constraint(equalTo: sectionLabel.bottomAnchor, constant: 2),
            scroll.leadingAnchor.constraint(equalTo: contentViewBox.leadingAnchor, constant: 10),
            scroll.trailingAnchor.constraint(equalTo: contentViewBox.trailingAnchor, constant: -10),
            scroll.bottomAnchor.constraint(equalTo: contentViewBox.bottomAnchor, constant: -10),
        ])
    }

    // MARK: - Presentation

    /// Show above the anchor (the bottom dock chip). If there is not enough
    /// room, show below it, clamped to the screen.
    func present(above anchor: NSRect, on screen: NSScreen?, panelFrame: NSRect = .zero) {
        guard !hasPresented else { return }
        hasPresented = true
        self.anchor = anchor
        self.panelFrame = panelFrame
        anchorScreen = screen ?? NSScreen.main
        rebuildRows(resetSelection: true)
        positionWindow()
        makeKeyAndOrderFront(nil)
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.makeFirstResponder(self.searchField)
        }
        loadSessions()
    }

    /// Test hook. The self-test can drive the picker without DSH.
    func injectSessions(_ sessions: [DSHSession], target: DSHIntegration.Target) {
        self.sessions = sessions
        self.target = target
        loading = false
        errorText = nil
        rebuildRows(resetSelection: true)
        positionWindow()
    }

    func requestDismiss() {
        guard !isDismissing else { return }
        isDismissing = true
        onDismiss?()
    }

    private func loadSessions() {
        loading = true
        errorText = nil
        rebuildRows(resetSelection: true)
        DSHIntegration.shared.listSessions { [weak self] result in
            guard let self else { return }
            loading = false
            switch result {
            case .success(let sessions):
                self.sessions = sessions
                self.errorText = nil
            case .failure(let error):
                self.sessions = []
                self.errorText = error.localizedDescription
            }
            self.target = DSHIntegration.shared.target
            self.rebuildRows(resetSelection: true)
            self.positionWindow()
        }
    }

    // MARK: - Rows and selection

    private func filteredSessions() -> [DSHSession] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return sessions }
        return sessions.filter { session in
            session.title.localizedCaseInsensitiveContains(trimmed)
                || (session.cwd ?? "").localizedCaseInsensitiveContains(trimmed)
        }
    }

    private func rebuildRows(resetSelection: Bool) {
        visibleSessions = filteredSessions()
        for view in list.arrangedSubviews {
            list.removeArrangedSubview(view)
            view.removeFromSuperview()
        }
        rows = []

        if visibleSessions.isEmpty {
            let message: String
            if loading {
                message = "Loading sessions…"
            } else if let errorText {
                message = errorText
            } else if query.isEmpty {
                message = "No recent sessions"
            } else {
                message = "No sessions match “\(query)”"
            }
            let label = NSTextField(wrappingLabelWithString: message)
            label.font = .systemFont(ofSize: 11.5, weight: .regular)
            label.textColor = .secondaryLabelColor
            label.maximumNumberOfLines = 2
            label.translatesAutoresizingMaskIntoConstraints = false
            let holder = NSView()
            holder.translatesAutoresizingMaskIntoConstraints = false
            holder.addSubview(label)
            NSLayoutConstraint.activate([
                label.leadingAnchor.constraint(equalTo: holder.leadingAnchor, constant: 8),
                label.trailingAnchor.constraint(equalTo: holder.trailingAnchor, constant: -8),
                label.centerYAnchor.constraint(equalTo: holder.centerYAnchor),
                holder.heightAnchor.constraint(equalToConstant: 40),
            ])
            list.addArrangedSubview(holder)
            holder.widthAnchor.constraint(equalTo: list.widthAnchor).isActive = true
        } else {
            for (index, session) in visibleSessions.enumerated() {
                let row = SessionPickerRow(newSession: false)
                row.title = session.title
                row.subtitle = subtitle(for: session)
                row.toolTip = session.cwd
                row.onClick = { [weak self] in self?.commit(index: index + 1) }
                rows.append(row)
                list.addArrangedSubview(row)
                row.heightAnchor.constraint(equalToConstant: rowHeight).isActive = true
                row.widthAnchor.constraint(equalTo: list.widthAnchor).isActive = true
            }
        }

        sectionLabel.stringValue = query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "RECENT" : "RESULTS"
        countLabel.stringValue = visibleSessions.isEmpty ? "" : "\(visibleSessions.count)"

        let entriesCount = 1 + visibleSessions.count
        if resetSelection {
            selectedIndex = initialSelectionIndex()
        } else {
            selectedIndex = min(max(0, selectedIndex), max(0, entriesCount - 1))
        }
        updateSelection()
        fitWindow()
    }

    private func initialSelectionIndex() -> Int {
        switch target {
        case .new:
            return 0
        case .recent:
            return visibleSessions.isEmpty ? 0 : 1
        case .session(let id, _):
            if let index = visibleSessions.firstIndex(where: { $0.id == id }) {
                return index + 1
            }
            return visibleSessions.isEmpty ? 0 : 1
        }
    }

    private func updateSelection() {
        newRow.selected = selectedIndex == 0
        for (index, row) in rows.enumerated() {
            row.selected = selectedIndex == index + 1
        }
        if selectedIndex > 0, selectedIndex <= rows.count {
            let row = rows[selectedIndex - 1]
            row.scrollToVisible(row.bounds)
        }
    }

    private func subtitle(for session: DSHSession) -> String {
        var parts: [String] = []
        if session.running {
            parts.append("● Running")
        }
        if let cwd = session.workspaceName { parts.append(cwd) }
        if let age = relativeAge(session.activity) { parts.append(age) }
        return parts.isEmpty ? "DSH session" : parts.joined(separator: " · ")
    }

    private func relativeAge(_ timestamp: TimeInterval) -> String? {
        guard timestamp > 0 else { return nil }
        let seconds = max(0, Date().timeIntervalSince1970 - timestamp)
        switch seconds {
        case ..<60:
            return "just now"
        case ..<3600:
            return "\(Int(seconds / 60))m ago"
        case ..<86_400:
            return "\(Int(seconds / 3600))h ago"
        default:
            return "\(Int(seconds / 86_400))d ago"
        }
    }

    private func commit(index: Int) {
        if index == 0 {
            finish(.new)
            return
        }
        let sessionIndex = index - 1
        guard visibleSessions.indices.contains(sessionIndex) else { return }
        finish(.session(visibleSessions[sessionIndex]))
    }

    private func finish(_ selection: Selection) {
        guard !isDismissing else { return }
        isDismissing = true
        onSelect?(selection)
    }

    // MARK: - Search

    func controlTextDidChange(_ notification: Notification) {
        query = searchField.stringValue
        clearButton.isHidden = query.isEmpty
        rebuildRows(resetSelection: false)
        // On a fresh query, select the first result. On an empty query, restore
        // the current target so the checkmark still tells the truth.
        if query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            selectedIndex = initialSelectionIndex()
        } else {
            selectedIndex = visibleSessions.isEmpty ? 0 : 1
        }
        updateSelection()
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        switch commandSelector {
        case #selector(NSResponder.moveDown(_:)):
            let maxIndex = visibleSessions.count
            selectedIndex = min(maxIndex, selectedIndex + 1)
            updateSelection()
            return true
        case #selector(NSResponder.moveUp(_:)):
            selectedIndex = max(0, selectedIndex - 1)
            updateSelection()
            return true
        case #selector(NSResponder.insertNewline(_:)):
            commit(index: selectedIndex)
            return true
        case #selector(NSResponder.cancelOperation(_:)):
            requestDismiss()
            return true
        default:
            return false
        }
    }

    @objc private func clearSearch() {
        searchField.stringValue = ""
        query = ""
        clearButton.isHidden = true
        selectedIndex = initialSelectionIndex()
        rebuildRows(resetSelection: true)
        makeFirstResponder(searchField)
    }

    // MARK: - Window sizing

    private func fitWindow() {
        let rowCount = max(1, visibleSessions.count)
        let totalListHeight = CGFloat(rowCount) * rowHeight
            + CGFloat(max(0, rowCount - 1)) * 2
        listHeightConstraint.constant = max(rowHeight, totalListHeight)
        let visibleRows = max(1, min(rowCount, maxVisibleRows))
        let visibleListHeight = CGFloat(visibleRows) * rowHeight
            + CGFloat(max(0, visibleRows - 1)) * 2
        let height = baseHeight + visibleListHeight
        if frame.height != height {
            setFrame(NSRect(origin: frame.origin, size: NSSize(width: panelWidth, height: height)),
                     display: true)
        }
        positionWindow()
    }

    private func positionWindow() {
        let screen = anchorScreen ?? NSScreen.main
        guard let visible = screen?.visibleFrame else { return }
        let height = frame.height
        let gap: CGFloat = 12
        let topLimit = visible.maxY - 12
        let bottomLimit = visible.minY + 12

        // B layout: the picker sits beside the composer, bottom-aligned when
        // possible. Fall back to above/below the target chip on narrow screens.
        if panelFrame != .zero {
            let y = max(bottomLimit, min(panelFrame.minY, topLimit - height))
            let rightX = panelFrame.maxX + gap
            if rightX + panelWidth <= visible.maxX - 12 {
                setFrame(NSRect(x: rightX, y: y, width: panelWidth, height: height), display: true)
                return
            }
            let leftX = panelFrame.minX - panelWidth - gap
            if leftX >= visible.minX + 12 {
                setFrame(NSRect(x: leftX, y: y, width: panelWidth, height: height), display: true)
                return
            }
        }

        var x = anchor.minX
        x = min(max(x, visible.minX + 12), visible.maxX - panelWidth - 12)
        var y = anchor.maxY + 8
        if y + height > topLimit {
            y = anchor.minY - height - 8
        }
        y = max(bottomLimit, y)
        let target = NSRect(x: x, y: y, width: panelWidth, height: height)
        if frame != target { setFrame(target, display: true) }
    }

    // MARK: - Self-test support

    /// A small text summary of the picker state for the test harness.
    var testSummary: String {
        "loading=\(loading) sessions=\(sessions.count) visible=\(visibleSessions.count) selected=\(selectedIndex) query=\(query)"
    }
}
