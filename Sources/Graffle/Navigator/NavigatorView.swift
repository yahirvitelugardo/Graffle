import AppKit

extension Notification.Name {
    /// Posted when the Navigator is shown or hidden from the View menu.
    static let navigatorVisibilityChanged = Notification.Name("GraffleNavigatorVisibilityChanged")
}

/// A small map of the whole diagram with a red box for the part that is on screen. Dragging the box (or clicking the map)
/// scrolls the document.
final class NavigatorMapView: NSView {
    weak var canvas: CanvasView? { didSet { needsDisplay = true } }
    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }       // so the percentage field isn't the one focused when the sidebar appears

    private let margin: CGFloat = 8

    private var scroll: NSScrollView? { canvas?.enclosingScrollView }

    /// The canvas area the map shows: everything drawn plus what is on screen, with some air.
    private func world() -> CGRect {
        let visible = scroll?.documentVisibleRect ?? .zero
        let content = canvas?.drawing.contentBounds ?? visible
        return content.union(visible).insetBy(dx: -40, dy: -40)
    }

    /// Canvas -> map scale and offset that fit the world inside the view, centered.
    private func transform() -> (scale: CGFloat, origin: CGPoint, world: CGRect) {
        let w = world()
        let avail = bounds.insetBy(dx: margin, dy: margin)
        let scale = min(avail.width / max(w.width, 1), avail.height / max(w.height, 1))
        let size = CGSize(width: w.width * scale, height: w.height * scale)
        return (scale, CGPoint(x: avail.midX - size.width / 2, y: avail.midY - size.height / 2), w)
    }

    func mapRect(_ canvasRect: CGRect) -> CGRect {
        guard canvas != nil else { return .zero }
        let t = transform()
        return CGRect(x: t.origin.x + (canvasRect.minX - t.world.minX) * t.scale, y: t.origin.y + (canvasRect.minY - t.world.minY) * t.scale,
                      width: canvasRect.width * t.scale, height: canvasRect.height * t.scale)
    }

    func canvasPoint(_ p: CGPoint) -> CGPoint {
        guard canvas != nil else { return .zero }
        let t = transform()
        return CGPoint(x: t.world.minX + (p.x - t.origin.x) / t.scale, y: t.world.minY + (p.y - t.origin.y) / t.scale)
    }

    /// The red box, in the map's coordinates.
    var viewportRect: CGRect { scroll.map { mapRect($0.documentVisibleRect) } ?? .zero }

    override func draw(_ dirtyRect: NSRect) {
        NSColor(white: 0.5, alpha: 0.12).setFill()
        bounds.fill()
        guard let canvas, scroll != nil, let ctx = NSGraphicsContext.current?.cgContext else { return }
        let t = transform()
        // The page, then connectors and shapes drawn simply (their fill and outline colors, no effects).
        let page = mapRect(t.world.intersection(CGRect(origin: .zero, size: CanvasView.canvasSize)))
        NSColor.white.setFill()
        page.fill()
        ctx.saveGState()
        ctx.clip(to: page)
        let drawing = canvas.drawing
        let visible = Set(drawing.layers.filter(\.visible).map(\.id))
        let byID = Dictionary(drawing.shapes.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        ctx.setLineWidth(1)
        for conn in drawing.connectors where visible.contains(conn.layer) {
            guard let a = byID[conn.from], let b = byID[conn.to] else { continue }
            let ra = mapRect(a.frame), rb = mapRect(b.frame)
            ctx.setStrokeColor(NSColor(white: 0.45, alpha: 0.7).cgColor)
            ctx.move(to: CGPoint(x: ra.midX, y: ra.midY))
            ctx.addLine(to: CGPoint(x: rb.midX, y: rb.midY))
            ctx.strokePath()
        }
        for s in drawing.shapes where visible.contains(s.layer) {
            let r = mapRect(s.worldBounds)
            guard r.width > 0.3, r.height > 0.3 else { continue }
            if s.kind == .text {
                ctx.setFillColor(NSColor(white: 0.3, alpha: 0.35).cgColor)
                ctx.fill(CGRect(x: r.minX, y: r.midY - 0.5, width: r.width, height: 1))
                continue
            }
            let fill: RGBA? = s.style.fill.kind == .none ? nil : (s.style.fill.kind == .solid ? s.style.fill.color : s.style.fill.color(at: 0.5))
            let line = s.style.stroke.visible ? s.style.stroke.color : nil
            let rounded = CGPath(roundedRect: r, cornerWidth: min(2, r.width / 2), cornerHeight: min(2, r.height / 2), transform: nil)
            if let fill { ctx.setFillColor(fill.with(alpha: 1).cg); ctx.addPath(rounded); ctx.fillPath() }
            if let line { ctx.setStrokeColor(line.cg); ctx.addPath(rounded); ctx.strokePath() }
            else if fill == nil { ctx.setStrokeColor(NSColor(white: 0.4, alpha: 1).cgColor); ctx.addPath(rounded); ctx.strokePath() }
        }
        ctx.restoreGState()
        // What is on screen.
        let box = viewportRect
        NSColor(srgbRed: 0.92, green: 0.22, blue: 0.22, alpha: 0.10).setFill()
        box.fill()
        NSColor(srgbRed: 0.92, green: 0.22, blue: 0.22, alpha: 1).setStroke()
        let outline = NSBezierPath(rect: box.insetBy(dx: 0.75, dy: 0.75))
        outline.lineWidth = 1.5
        outline.stroke()
    }

    private func scroll(toMapPoint p: CGPoint) { canvas?.scrollCenter(to: canvasPoint(p)) }

    override func mouseDown(with event: NSEvent) { scroll(toMapPoint: convert(event.locationInWindow, from: nil)) }
    override func mouseDragged(with event: NSEvent) { scroll(toMapPoint: convert(event.locationInWindow, from: nil)) }
    override func scrollWheel(with event: NSEvent) { scroll?.scrollWheel(with: event) }
    override func magnify(with event: NSEvent) { scroll?.magnify(with: event) }
    override func resetCursorRects() { addCursorRect(bounds, cursor: .openHand) }
}

/// The Navigator, at the top of the inspector: the map, a zoom slider with a small and a large rectangle at its ends,
/// the zoom percentage and a Fit button. It belongs to one document window.
final class NavigatorView: NSView, NSTextFieldDelegate {
    static let visibleKey = "navigator.visible"
    /// Whether the user wants the Navigator on screen (View → Show/Hide Navigator). On by default.
    static var isVisible: Bool {
        get { UserDefaults.standard.object(forKey: visibleKey) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: visibleKey); NotificationCenter.default.post(name: .navigatorVisibilityChanged, object: nil) }
    }

    let map = NavigatorMapView()
    let slider = NSSlider(value: 0, minValue: Double(log2(CanvasView.minZoom)), maxValue: Double(log2(CanvasView.maxZoom)), target: nil, action: nil)
    let field = NSTextField()
    private let fitButton = NSButton()
    private weak var canvas: CanvasView?
    private var observers: [NSObjectProtocol] = []

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        build()
    }
    required init?(coder: NSCoder) { fatalError("not used") }
    deinit { observers.forEach(NotificationCenter.default.removeObserver) }

    /// A rectangle drawn at `size`, as a menu-bar-style template image: the ends of the zoom slider.
    static func rectangleIcon(_ size: NSSize) -> NSImage {
        let canvas = NSSize(width: 22, height: 18)
        let image = NSImage(size: canvas, flipped: false) { _ in
            let r = NSRect(x: (canvas.width - size.width) / 2, y: (canvas.height - size.height) / 2, width: size.width, height: size.height)
            let path = NSBezierPath(roundedRect: r.insetBy(dx: 0.7, dy: 0.7), xRadius: 1.5, yRadius: 1.5)
            path.lineWidth = 1.4
            NSColor.black.setStroke()
            path.stroke()
            return true
        }
        image.isTemplate = true
        return image
    }

    private func iconButton(_ size: NSSize, _ tip: String, _ action: Selector) -> NSButton {
        let b = NSButton()
        b.image = NavigatorView.rectangleIcon(size)
        b.isBordered = false
        b.imagePosition = .imageOnly
        b.contentTintColor = .secondaryLabelColor
        b.toolTip = tip
        b.target = self
        b.action = action
        b.translatesAutoresizingMaskIntoConstraints = false
        b.setAccessibilityLabel(tip)
        return b
    }

    private func build() {
        translatesAutoresizingMaskIntoConstraints = false
        map.translatesAutoresizingMaskIntoConstraints = false
        map.wantsLayer = true
        map.layer?.cornerRadius = 6
        map.layer?.masksToBounds = true
        map.setAccessibilityLabel("Diagram map; the red box is what is on screen")
        addSubview(map)

        let small = iconButton(NSSize(width: 8, height: 6), "Zoom out", #selector(stepOut(_:)))
        let large = iconButton(NSSize(width: 17, height: 13), "Zoom in", #selector(stepIn(_:)))
        slider.isContinuous = true
        slider.target = self
        slider.action = #selector(sliderMoved(_:))
        slider.controlSize = .small
        slider.setAccessibilityLabel("Zoom")
        slider.translatesAutoresizingMaskIntoConstraints = false

        field.alignment = .center
        field.font = .monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        field.stringValue = "100%"
        field.delegate = self
        field.target = self
        field.action = #selector(fieldEntered(_:))
        field.controlSize = .small
        field.focusRingType = .none
        field.setAccessibilityLabel("Zoom percentage")
        field.translatesAutoresizingMaskIntoConstraints = false

        fitButton.title = "Fit"
        fitButton.bezelStyle = .rounded
        fitButton.controlSize = .small
        fitButton.target = self
        fitButton.action = #selector(fit(_:))
        fitButton.toolTip = "Zoom to fit the whole diagram"
        fitButton.translatesAutoresizingMaskIntoConstraints = false

        [small, slider, large, field, fitButton].forEach(addSubview)
        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: 232),
            map.topAnchor.constraint(equalTo: topAnchor),
            map.leadingAnchor.constraint(equalTo: leadingAnchor),
            map.trailingAnchor.constraint(equalTo: trailingAnchor),
            map.heightAnchor.constraint(equalToConstant: 128),
            small.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 2),
            small.topAnchor.constraint(equalTo: map.bottomAnchor, constant: 8),
            small.widthAnchor.constraint(equalToConstant: 22), small.heightAnchor.constraint(equalToConstant: 18),
            large.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -2),
            large.centerYAnchor.constraint(equalTo: small.centerYAnchor),
            large.widthAnchor.constraint(equalToConstant: 22), large.heightAnchor.constraint(equalToConstant: 18),
            slider.leadingAnchor.constraint(equalTo: small.trailingAnchor, constant: 4),
            slider.trailingAnchor.constraint(equalTo: large.leadingAnchor, constant: -4),
            slider.centerYAnchor.constraint(equalTo: small.centerYAnchor),
            field.leadingAnchor.constraint(equalTo: leadingAnchor),
            field.widthAnchor.constraint(equalToConstant: 60),
            field.topAnchor.constraint(equalTo: small.bottomAnchor, constant: 6),
            field.bottomAnchor.constraint(equalTo: bottomAnchor),
            fitButton.trailingAnchor.constraint(equalTo: trailingAnchor),
            fitButton.centerYAnchor.constraint(equalTo: field.centerYAnchor),
        ])
    }

    // MARK: Binding to a document

    /// Shows `canvas`; called once the window is built.
    func attach(_ canvas: CanvasView) {
        self.canvas = canvas
        map.canvas = canvas
        refresh()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        observeScrolling()
        refresh()
    }

    /// Follows scrolling, zooming and resizing of the document view.
    private func observeScrolling() {
        observers.forEach(NotificationCenter.default.removeObserver)
        observers = []
        guard let scroll = canvas?.enclosingScrollView else { return }
        let clip = scroll.contentView
        clip.postsBoundsChangedNotifications = true
        clip.postsFrameChangedNotifications = true
        for name in [NSView.boundsDidChangeNotification, NSView.frameDidChangeNotification] {
            observers.append(NotificationCenter.default.addObserver(forName: name, object: clip, queue: .main) { [weak self] _ in self?.refresh() })
        }
        observers.append(NotificationCenter.default.addObserver(forName: NSScrollView.didEndLiveMagnifyNotification, object: scroll, queue: .main) { [weak self] _ in self?.refresh() })
    }

    /// The drawing changed (or scrolled or zoomed): redraw the map and update the zoom controls.
    func refresh() {
        if observers.isEmpty, canvas?.enclosingScrollView != nil { observeScrolling() }
        map.needsDisplay = true
        guard let canvas, let scroll = canvas.enclosingScrollView else { field.stringValue = "—"; return }
        slider.doubleValue = Double(log2(max(scroll.magnification, CanvasView.minZoom)))
        if !(window?.firstResponder === field.currentEditor() && field.currentEditor() != nil) { field.stringValue = NavigatorView.percent(scroll.magnification) }
    }

    static func percent(_ m: CGFloat) -> String { "\(Int((m * 100).rounded()))%" }

    // MARK: Actions

    @objc private func sliderMoved(_ s: NSSlider) {
        canvas?.setMagnification(CGFloat(pow(2, s.doubleValue)))
        refresh()
    }
    @objc private func stepIn(_ s: Any?) { canvas?.zoomStep(out: false); refresh() }
    @objc private func stepOut(_ s: Any?) { canvas?.zoomStep(out: true); refresh() }
    @objc private func fit(_ s: Any?) { canvas?.zoomToFitDiagram(); refresh() }

    /// A number (with or without "%") typed in the field is the new zoom, 10%...800%.
    @objc private func fieldEntered(_ s: NSTextField) {
        let digits = s.stringValue.filter { $0.isNumber || $0 == "." }
        if let value = Double(digits), value > 0 { canvas?.setMagnification(CGFloat(value / 100)) }
        refresh()
        s.stringValue = canvas.map { NavigatorView.percent($0.magnification) } ?? "—"
    }
}
