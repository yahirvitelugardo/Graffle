import CoreGraphics
import Foundation

/// Geometry helpers for precise drawing: angle constraints, snap points and straight lines.
enum Drafting {
    enum SnapKind: String {
        case endpoint = "Endpoint", midpoint = "Midpoint", center = "Center", corner = "Corner"
    }

    struct SnapPoint: Equatable {
        var point: CGPoint
        var kind: SnapKind
    }

    /// Moves `p` so the line from `start` to it points along a multiple of `degrees` (keeping its length).
    static func constrain(_ p: CGPoint, from start: CGPoint, stepDegrees degrees: Double) -> CGPoint {
        let dx = p.x - start.x, dy = p.y - start.y
        let len = hypot(dx, dy)
        guard len > 0, degrees > 0 else { return p }
        let step = degrees * .pi / 180
        let a = (atan2(dy, dx) / step).rounded() * step
        return CGPoint(x: start.x + cos(a) * len, y: start.y + sin(a) * len)
    }

    /// Angle of the line a -> b in degrees, 0 = to the right, counterclockwise on screen, 0..<360.
    static func angle(from a: CGPoint, to b: CGPoint) -> Double {
        var deg = atan2(-(b.y - a.y), b.x - a.x) * 180 / .pi
        if deg < 0 { deg += 360 }
        return deg >= 359.9995 ? 0 : deg
    }

    /// A straight line from `a` to `b` as a path shape (the frame is the line's bounding box, at least 1 point thick).
    static func lineShape(from a: CGPoint, to b: CGPoint, layer: UUID, style: Style, name: String? = nil) -> Shape {
        let rect = CGRect(x: min(a.x, b.x), y: min(a.y, b.y), width: max(abs(a.x - b.x), 1), height: max(abs(a.y - b.y), 1))
        func norm(_ p: CGPoint) -> CGPoint { CGPoint(x: (p.x - rect.minX) / rect.width, y: (p.y - rect.minY) / rect.height) }
        return Shape(layer: layer, kind: .path, frame: rect, style: style,
                     outline: [PathSegment(op: .move, points: [norm(a)]), PathSegment(op: .line, points: [norm(b)])], name: name)
    }

    /// The two ends of a shape that is a single straight line, in canvas coordinates.
    static func straightEnds(of s: Shape) -> (CGPoint, CGPoint)? {
        guard s.kind == .path, let o = s.outline, o.count == 2, o[0].op == .move, o[1].op == .line,
              let p = o[0].points.first, let q = o[1].points.first else { return nil }
        func world(_ n: CGPoint) -> CGPoint { s.toWorld(CGPoint(x: s.frame.minX + n.x * s.frame.width, y: s.frame.minY + n.y * s.frame.height)) }
        return (world(p), world(q))
    }

    /// Snap targets of a shape: line ends and middles, corners, side midpoints and the center.
    static func snapPoints(of s: Shape) -> [SnapPoint] {
        if s.kind == .text { return [] }
        if let (a, b) = straightEnds(of: s) {
            return [SnapPoint(point: a, kind: .endpoint), SnapPoint(point: b, kind: .endpoint),
                    SnapPoint(point: CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2), kind: .midpoint)]
        }
        let f = s.frame
        let corners = [CGPoint(x: f.minX, y: f.minY), CGPoint(x: f.maxX, y: f.minY), CGPoint(x: f.maxX, y: f.maxY), CGPoint(x: f.minX, y: f.maxY)]
        let mids = [CGPoint(x: f.midX, y: f.minY), CGPoint(x: f.maxX, y: f.midY), CGPoint(x: f.midX, y: f.maxY), CGPoint(x: f.minX, y: f.midY)]
        return corners.map { SnapPoint(point: s.toWorld($0), kind: .corner) } + mids.map { SnapPoint(point: s.toWorld($0), kind: .midpoint) }
            + [SnapPoint(point: s.center, kind: .center)]
    }

    /// The snap point nearest `p` within `radius`, if any (endpoints win ties).
    static func nearest(_ p: CGPoint, in points: [SnapPoint], radius: CGFloat) -> SnapPoint? {
        let rank: [SnapKind: Int] = [.endpoint: 0, .corner: 1, .midpoint: 2, .center: 3]
        return points.filter { hypot($0.point.x - p.x, $0.point.y - p.y) <= radius }
            .min { (hypot($0.point.x - p.x, $0.point.y - p.y), rank[$0.kind] ?? 9) < (hypot($1.point.x - p.x, $1.point.y - p.y), rank[$1.kind] ?? 9) }
    }

    /// Turns shapes together by `degrees` clockwise about `c`: each shape's center travels around `c` and the shape turns with it,
    /// so parts made of several shapes (a door and its opening) stay assembled.
    static func rotate(_ shapes: inout [Shape], by degrees: Double, about c: CGPoint) {
        let a = degrees * .pi / 180
        for i in shapes.indices {
            let ctr = shapes[i].center
            let dx = ctr.x - c.x, dy = ctr.y - c.y
            let nx = c.x + dx * cos(a) - dy * sin(a), ny = c.y + dx * sin(a) + dy * cos(a)
            shapes[i].frame.origin = CGPoint(x: nx - shapes[i].frame.width / 2, y: ny - shapes[i].frame.height / 2)
            var r = (shapes[i].rotation + degrees).truncatingRemainder(dividingBy: 360)
            if r < 0 { r += 360 }
            shapes[i].rotation = r
        }
    }
}
