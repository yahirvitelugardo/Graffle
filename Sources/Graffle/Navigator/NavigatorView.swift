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
        Tok.minimapBackdrop.setFill()
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
        Tok.minimapViewport.withAlphaComponent(0.10).setFill()
        box.fill()
        Tok.minimapViewport.setStroke()
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

/// Whether the minimap (and zoom pill) are shown. View → Hide/Show Navigator; on by default.
enum NavigatorPrefs {
    static let visibleKey = "navigator.visible"
    static var isVisible: Bool {
        get { UserDefaults.standard.object(forKey: visibleKey) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: visibleKey); NotificationCenter.default.post(name: .navigatorVisibilityChanged, object: nil) }
    }
}
