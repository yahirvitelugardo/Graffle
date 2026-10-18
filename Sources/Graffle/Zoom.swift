import AppKit

/// Zooming: the magnification lives in the enclosing scroll view; these are the ways to change it.
extension CanvasView {
    static let minZoom: CGFloat = 0.1
    static let maxZoom: CGFloat = 8

    static let zoomCursor: NSCursor = {
        let config = NSImage.SymbolConfiguration(pointSize: 18, weight: .regular)
        guard let image = NSImage(systemSymbolName: "plus.magnifyingglass", accessibilityDescription: "Zoom")?.withSymbolConfiguration(config) else { return .crosshair }
        return NSCursor(image: image, hotSpot: NSPoint(x: image.size.width / 2, y: image.size.height / 2))
    }()

    /// The current zoom, 1 = 100%.
    var magnification: CGFloat { enclosingScrollView?.magnification ?? 1 }

    /// Zooms to `m` (clamped), keeping `point` (canvas coordinates, default: the middle of what is visible) where it is on screen's center.
    func setMagnification(_ m: CGFloat, centeredAt point: CGPoint? = nil) {
        guard let scroll = enclosingScrollView else { return }
        let clamped = min(max(m, scroll.minMagnification), scroll.maxMagnification)
        scroll.setMagnification(clamped, centeredAt: point ?? CGPoint(x: scroll.documentVisibleRect.midX, y: scroll.documentVisibleRect.midY))
    }

    /// One step in or out (a factor of 2), around `point`.
    func zoomStep(out: Bool, around point: CGPoint? = nil) {
        setMagnification(magnification * (out ? 0.5 : 2), centeredAt: point)
    }

    /// Command + scroll wheel (or trackpad scroll) zooms around the pointer; anything else scrolls as usual.
    override func scrollWheel(with event: NSEvent) {
        guard event.modifierFlags.contains(.command), !event.modifierFlags.contains(.option) else { super.scrollWheel(with: event); return }
        let delta = event.hasPreciseScrollingDeltas ? event.scrollingDeltaY / 60 : event.scrollingDeltaY / 6      // trackpads send many small steps
        guard delta != 0 else { return }
        let factor = CGFloat(pow(2.0, Double(delta)))
        setMagnification(magnification * factor, centeredAt: convert(event.locationInWindow, from: nil))
    }

    /// Zooms so that `rect` (canvas coordinates) fills the view.
    func zoom(toFit rect: CGRect) {
        guard let scroll = enclosingScrollView, rect.width > 0, rect.height > 0 else { return }
        scroll.magnify(toFit: rect)
    }

    /// Fits the whole diagram, with some air around it; an empty canvas goes back to 100%.
    func zoomToFitDiagram() {
        guard let bounds = drawing.contentBounds else { setMagnification(1); return }
        zoom(toFit: bounds.insetBy(dx: -40, dy: -40))
    }

    /// Fits the selected objects; with nothing selected, the whole diagram.
    func zoomToFitSelection() {
        let picked = selectedShapes.map(\.worldBounds)
        guard let first = picked.first else { zoomToFitDiagram(); return }
        zoom(toFit: picked.dropFirst().reduce(first) { $0.union($1) }.insetBy(dx: -40, dy: -40))
    }

    /// Scrolls so `point` (canvas coordinates) is in the middle of the view, without changing the zoom.
    func scrollCenter(to point: CGPoint) {
        guard let scroll = enclosingScrollView else { return }
        let visible = scroll.documentVisibleRect
        var origin = CGPoint(x: point.x - visible.width / 2, y: point.y - visible.height / 2)
        origin.x = min(max(origin.x, 0), max(bounds.width - visible.width, 0))
        origin.y = min(max(origin.y, 0), max(bounds.height - visible.height, 0))
        scroll.contentView.scroll(to: origin)
        scroll.reflectScrolledClipView(scroll.contentView)
    }
}
