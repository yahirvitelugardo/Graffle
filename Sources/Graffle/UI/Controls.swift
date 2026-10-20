import AppKit

/// A borderless icon button with a hover fill, an accessible label and a tooltip.
final class IconButton: NSButton {
    var cornerRadius: CGFloat = 8 { didSet { layer?.cornerRadius = cornerRadius } }
    /// When on, the button is drawn as the active one (accent fill, white icon, soft glow): the selected tool in the dock.
    var isActive = false { didSet { updateAppearance() } }
    var activeStyle = false
    private var hovering = false { didSet { updateAppearance() } }
    private var tracking: NSTrackingArea?

    convenience init(symbol: String, label: String, tip: String? = nil, size: CGFloat = 30, pointSize: CGFloat = 14) {
        self.init(frame: NSRect(x: 0, y: 0, width: size, height: size))
        let image = NSImage(systemSymbolName: symbol, accessibilityDescription: label)
        self.image = image?.withSymbolConfiguration(.init(pointSize: pointSize, weight: .regular))
        toolTip = tip ?? label
        setAccessibilityLabel(label)
        translatesAutoresizingMaskIntoConstraints = false
        widthAnchor.constraint(equalToConstant: size).isActive = true
        heightAnchor.constraint(equalToConstant: size).isActive = true
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        isBordered = false
        imagePosition = .imageOnly
        setButtonType(.momentaryChange)
        wantsLayer = true
        layer?.cornerRadius = cornerRadius
        layer?.cornerCurve = .continuous
        focusRingType = .exterior
        updateAppearance()
    }
    required init?(coder: NSCoder) { fatalError("not used") }

    override var alignmentRectInsets: NSEdgeInsets { NSEdgeInsets() }      // the frame is exactly the size asked for
    override var acceptsFirstResponder: Bool { true }
    override func drawFocusRingMask() { NSBezierPath(roundedRect: bounds, xRadius: cornerRadius, yRadius: cornerRadius).fill() }
    override var focusRingMaskBounds: NSRect { bounds }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let t = tracking { removeTrackingArea(t) }
        tracking = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect], owner: self)
        addTrackingArea(tracking!)
    }
    override func mouseEntered(with event: NSEvent) { hovering = true }
    override func mouseExited(with event: NSEvent) { hovering = false }
    override func viewDidChangeEffectiveAppearance() { super.viewDidChangeEffectiveAppearance(); updateAppearance() }

    private func updateAppearance() {
        guard let layer else { return }
        let reduce = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        let apply = { [self] in
            if isActive {
                layer.backgroundColor = Tok.resolve(Tok.accent, for: self)
                contentTintColor = Tok.onAccent
                layer.shadowColor = Tok.resolve(Tok.accent, for: self)
                layer.shadowOpacity = 0.35; layer.shadowRadius = 6; layer.shadowOffset = CGSize(width: 0, height: -2)
            } else {
                layer.backgroundColor = hovering ? Tok.resolve(Tok.hoverFill, for: self) : NSColor.clear.cgColor
                contentTintColor = hovering ? Tok.textPrimary : Tok.iconDefault
                layer.shadowOpacity = 0
            }
        }
        if reduce { apply() } else { NSAnimationContext.runAnimationGroup { $0.duration = 0.16; $0.allowsImplicitAnimation = true; apply() } }
    }
}

/// The primary pill button ("Share").
final class PillButton: NSButton {
    convenience init(title: String) {
        self.init(frame: NSRect(x: 0, y: 0, width: 70, height: 32))
        self.title = title
    }
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        isBordered = false
        setButtonType(.momentaryChange)
        wantsLayer = true
        layer?.cornerRadius = 16
        layer?.cornerCurve = .continuous
        font = .systemFont(ofSize: 13, weight: .semibold)
        translatesAutoresizingMaskIntoConstraints = false
        heightAnchor.constraint(equalToConstant: 32).isActive = true
        updateAppearance()
    }
    required init?(coder: NSCoder) { fatalError("not used") }
    override var alignmentRectInsets: NSEdgeInsets { NSEdgeInsets() }
    override var title: String { didSet { attributedTitle = NSAttributedString(string: title, attributes: [.font: NSFont.systemFont(ofSize: 13, weight: .semibold), .foregroundColor: NSColor.white]); invalidateIntrinsicContentSize() } }
    override var intrinsicContentSize: NSSize { NSSize(width: attributedTitle.size().width + 32, height: 32) }
    private func updateAppearance() {
        layer?.backgroundColor = Tok.resolve(Tok.accent, for: self)
        layer?.shadowColor = NSColor(srgbRed: 0, green: 0.24, blue: 0.55, alpha: 1).cgColor
        layer?.shadowOpacity = 0.25; layer?.shadowRadius = 1.5; layer?.shadowOffset = CGSize(width: 0, height: -1)
    }
    override func viewDidChangeEffectiveAppearance() { super.viewDidChangeEffectiveAppearance(); updateAppearance() }
}

/// A one-line text field that looks like the design's fields: tinted, rounded, with an accent ring when focused.
final class DesignField: NSTextField {
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        isBordered = false
        drawsBackground = false
        focusRingType = .none
        font = Tok.Font.number()
        textColor = Tok.textPrimary
        wantsLayer = true
        layer?.cornerRadius = Tok.Radius.field
        layer?.cornerCurve = .continuous
        translatesAutoresizingMaskIntoConstraints = false
        heightAnchor.constraint(equalToConstant: 30).isActive = true
        updateAppearance()
    }
    required init?(coder: NSCoder) { fatalError("not used") }

    private var hovering = false { didSet { updateAppearance() } }
    private var focused: Bool { currentEditor() != nil }
    private var tracking: NSTrackingArea?
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let t = tracking { removeTrackingArea(t) }
        tracking = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect], owner: self)
        addTrackingArea(tracking!)
    }
    override func mouseEntered(with event: NSEvent) { hovering = true }
    override func mouseExited(with event: NSEvent) { hovering = false }
    override func becomeFirstResponder() -> Bool { let ok = super.becomeFirstResponder(); updateAppearance(); return ok }
    override func textDidEndEditing(_ notification: Notification) { super.textDidEndEditing(notification); updateAppearance() }
    override func viewDidChangeEffectiveAppearance() { super.viewDidChangeEffectiveAppearance(); updateAppearance() }
    override func layout() { super.layout(); updateAppearance() }

    func updateAppearance() {
        guard let layer else { return }
        let focus = focused
        layer.backgroundColor = Tok.resolve(focus ? Tok.fieldFocusBG : (hovering ? Tok.fieldHoverBG : Tok.fieldBG), for: self)
        layer.borderWidth = focus || hovering ? 1 : 0
        layer.borderColor = Tok.resolve(focus ? Tok.accent : Tok.fieldHoverBorder, for: self)
        layer.shadowColor = Tok.resolve(Tok.accent, for: self)
        layer.shadowOpacity = focus ? 0.35 : 0
        layer.shadowRadius = 3; layer.shadowOffset = .zero
    }

    // Inset the text a little from the rounded edge.
    override var intrinsicContentSize: NSSize { NSSize(width: NSView.noIntrinsicMetric, height: 30) }
}

/// A segmented control in the design's style: a tinted track with a raised thumb on the selected segment.
final class DesignSegmented: NSView {
    var titles: [String] { didSet { rebuild() } }
    var selected = 0 { didSet { if oldValue != selected { updateThumb(animated: true); onChange?(selected) } } }
    var onChange: ((Int) -> Void)?
    private var buttons: [NSButton] = []
    private let thumb = NSView()

    init(titles: [String]) {
        self.titles = titles
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = Tok.Radius.segmented
        layer?.cornerCurve = .continuous
        translatesAutoresizingMaskIntoConstraints = false
        heightAnchor.constraint(equalToConstant: 32).isActive = true
        thumb.wantsLayer = true
        thumb.layer?.cornerRadius = Tok.Radius.segmentedThumb
        thumb.layer?.cornerCurve = .continuous
        thumb.layer?.shadowOpacity = 0.12; thumb.layer?.shadowRadius = 1.5; thumb.layer?.shadowOffset = CGSize(width: 0, height: -1)
        addSubview(thumb)
        setAccessibilityRole(.radioGroup)
        rebuild()
    }
    required init?(coder: NSCoder) { fatalError("not used") }

    override var acceptsFirstResponder: Bool { true }
    override var focusRingMaskBounds: NSRect { bounds }
    override func drawFocusRingMask() { NSBezierPath(roundedRect: bounds, xRadius: Tok.Radius.segmented, yRadius: Tok.Radius.segmented).fill() }
    override var focusRingType: NSFocusRingType { get { .exterior } set {} }
    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 123: selected = max(0, selected - 1)                       // left
        case 124: selected = min(titles.count - 1, selected + 1)         // right
        default: super.keyDown(with: event)
        }
    }

    private func rebuild() {
        buttons.forEach { $0.removeFromSuperview() }
        buttons = titles.enumerated().map { i, t in
            let b = NSButton(title: t, target: self, action: #selector(pick(_:)))
            b.tag = i; b.isBordered = false; b.setButtonType(.momentaryChange)
            b.font = .systemFont(ofSize: 12.5, weight: .medium)
            b.setAccessibilityLabel(t)
            b.focusRingType = .none
            addSubview(b)
            return b
        }
        needsLayout = true
        updateThumb(animated: false)
    }

    @objc private func pick(_ s: NSButton) { selected = s.tag; window?.makeFirstResponder(self) }

    override func layout() {
        super.layout()
        let inset: CGFloat = 2, n = max(titles.count, 1), w = (bounds.width - inset * 2) / CGFloat(n)
        for (i, b) in buttons.enumerated() { b.frame = NSRect(x: inset + CGFloat(i) * w, y: inset, width: w, height: bounds.height - inset * 2) }
        thumb.frame = NSRect(x: inset + CGFloat(selected) * w, y: inset, width: w, height: bounds.height - inset * 2)
        updateColors()
    }

    private func updateThumb(animated: Bool) {
        let inset: CGFloat = 2, n = max(titles.count, 1), w = (bounds.width - inset * 2) / CGFloat(n)
        let frame = NSRect(x: inset + CGFloat(selected) * w, y: inset, width: w, height: bounds.height - inset * 2)
        if animated, !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            NSAnimationContext.runAnimationGroup { $0.duration = 0.16; $0.allowsImplicitAnimation = true; thumb.animator().frame = frame }
        } else { thumb.frame = frame }
        updateColors()
    }

    private func updateColors() {
        layer?.backgroundColor = Tok.resolve(Tok.segmentedTrack, for: self)
        thumb.layer?.backgroundColor = Tok.resolve(Tok.segmentedThumb, for: self)
        for (i, b) in buttons.enumerated() {
            b.attributedTitle = NSAttributedString(string: titles[i], attributes: [.font: NSFont.systemFont(ofSize: 12.5, weight: .medium),
                                                                                    .foregroundColor: i == selected ? Tok.textPrimary : Tok.textSecondary])
        }
    }
    override func viewDidChangeEffectiveAppearance() { super.viewDidChangeEffectiveAppearance(); updateColors() }
}

/// A view that lets clicks through everywhere except on its subviews (the overlays that float over the canvas).
final class PassthroughView: NSView {
    override func hitTest(_ point: NSPoint) -> NSView? {
        let hit = super.hitTest(point)
        return hit === self ? nil : hit
    }
}

/// A floating pill/card surface: translucent in light mode (with a blur behind it), solid in dark, with the floating shadow.
final class FloatingSurface: NSView {
    private let blur = NSVisualEffectView()
    private let tint = NSView()
    var radius: CGFloat { didSet { applyRadius() } }

    init(radius: CGFloat) {
        self.radius = radius
        super.init(frame: .zero)
        wantsLayer = true
        translatesAutoresizingMaskIntoConstraints = false
        blur.material = .popover; blur.blendingMode = .withinWindow; blur.state = .active
        blur.wantsLayer = true
        tint.wantsLayer = true
        for v in [blur, tint] { v.translatesAutoresizingMaskIntoConstraints = false; addSubview(v) }
        NSLayoutConstraint.activate([
            blur.leadingAnchor.constraint(equalTo: leadingAnchor), blur.trailingAnchor.constraint(equalTo: trailingAnchor),
            blur.topAnchor.constraint(equalTo: topAnchor), blur.bottomAnchor.constraint(equalTo: bottomAnchor),
            tint.leadingAnchor.constraint(equalTo: leadingAnchor), tint.trailingAnchor.constraint(equalTo: trailingAnchor),
            tint.topAnchor.constraint(equalTo: topAnchor), tint.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
        applyRadius()
        updateAppearance()
    }
    required init?(coder: NSCoder) { fatalError("not used") }

    private func applyRadius() {
        for v in [blur, tint] { v.layer?.cornerRadius = radius; v.layer?.cornerCurve = .continuous; v.layer?.masksToBounds = true }
        layer?.cornerRadius = radius
    }

    private var isDarkAppearance: Bool { effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua }

    private func updateAppearance() {
        let dark = isDarkAppearance
        blur.isHidden = dark                                           // dark floating surfaces are solid
        tint.layer?.backgroundColor = Tok.resolve(Tok.floatingBG, for: self)
        layer?.borderWidth = 0.5
        layer?.borderColor = Tok.resolve(Tok.panelOutline, for: self)
        if let layer { Tok.applyFloatingShadow(to: layer, dark: dark) }
    }
    override func viewDidChangeEffectiveAppearance() { super.viewDidChangeEffectiveAppearance(); updateAppearance() }
}
