import UIKit

/// What the Mac canvas got from NSEvent, in canvas coordinates.
struct PointerEvent {
    struct Mods: OptionSet {
        let rawValue: Int
        static let shift = Mods(rawValue: 1)
        static let option = Mods(rawValue: 2)
        static let command = Mods(rawValue: 4)
        static let control = Mods(rawValue: 8)
    }

    /// In canvas coordinates.
    var point: CGPoint
    /// In the canvas view's own coordinates (for panning).
    var viewPoint: CGPoint
    var modifierFlags: Mods = []
    var clickCount: Int = 1
    var isPencil = false
}

/// Keys the canvas reacts to.
enum Key: Equatable {
    case returnKey, escape, delete, left, right, up, down
    case character(String)
}

// MARK: - Zoom

extension CanvasView {
    static let minZoom: CGFloat = 0.1
    static let maxZoom: CGFloat = 8

    var magnification: CGFloat { zoom }

    /// Keeps at least part of the canvas on screen.
    func clampedOrigin(_ o: CGPoint) -> CGPoint {
        let v = visibleRect.size
        return CGPoint(x: min(max(o.x, -v.width / 2), Self.canvasSize.width - v.width / 2),
                       y: min(max(o.y, -v.height / 2), Self.canvasSize.height - v.height / 2))
    }

    /// Zooms to `m` (clamped), keeping the canvas point `point` (default: the middle of the view) where it is on screen.
    func setMagnification(_ m: CGFloat, centeredAt point: CGPoint? = nil) {
        let anchor = point ?? visibleCenter
        let before = viewPoint(fromCanvas: anchor)
        zoom = min(max(m, Self.minZoom), Self.maxZoom)
        scrollOrigin = clampedOrigin(CGPoint(x: anchor.x - before.x / zoom, y: anchor.y - before.y / zoom))
    }

    func zoomStep(out: Bool, around point: CGPoint? = nil) {
        setMagnification(zoom * (out ? 0.5 : 2), centeredAt: point)
    }

    /// Zooms so that `rect` (canvas coordinates) fills the view.
    func zoom(toFit rect: CGRect) {
        guard rect.width > 0, rect.height > 0, bounds.width > 0, bounds.height > 0 else { return }
        let z = min(max(min(bounds.width / rect.width, bounds.height / rect.height), Self.minZoom), Self.maxZoom)
        zoom = z
        scrollOrigin = clampedOrigin(CGPoint(x: rect.midX - bounds.width / z / 2, y: rect.midY - bounds.height / z / 2))
    }

    func zoomToFitDiagram() {
        guard let b = drawing.contentBounds else {
            setMagnification(1)
            scrollCenter(to: CGPoint(x: Self.canvasSize.width / 2, y: Self.canvasSize.height / 2))
            return
        }
        zoom(toFit: b.insetBy(dx: -40, dy: -40))
    }

    func zoomToFitSelection() {
        let picked = selectedShapes.map(\.worldBounds)
        guard let first = picked.first else { zoomToFitDiagram(); return }
        zoom(toFit: picked.dropFirst().reduce(first) { $0.union($1) }.insetBy(dx: -40, dy: -40))
    }

    func scrollCenter(to point: CGPoint) {
        scrollOrigin = clampedOrigin(CGPoint(x: point.x - visibleRect.width / 2, y: point.y - visibleRect.height / 2))
    }
}
