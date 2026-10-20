import CoreGraphics
import Foundation

enum DimensionAxis: String, Codable, CaseIterable {
    case horizontal, vertical, aligned

    var title: String {
        switch self {
        case .horizontal: return "Horizontal"
        case .vertical: return "Vertical"
        case .aligned: return "Aligned"
        }
    }
}

/// Marks a connector as a dimension line: it measures instead of linking.
/// Its two ends are the shapes it measures (the same shape twice = that shape's own width, height or length).
struct DimensionSpec: Codable, Equatable {
    var axis: DimensionAxis = .horizontal
    /// How far the dimension line sits from what it measures, in points (up or to the left of it).
    var offset: Double = 36
}

enum Dimensions {
    static let gap: CGFloat = 4          // between the object and the start of an extension line
    static let overshoot: CGFloat = 5    // how far extension lines pass the dimension line
    static let tick: CGFloat = 5         // half-length of the architectural slash

    /// The two measured points of a dimension (before the offset is applied) and whether the line is the axis-aligned kind.
    /// A shape's extent: the true ends of a straight line (not its padded frame), else the bounds of the rotated frame.
    static func extent(of s: Shape) -> CGRect {
        guard let (p, q) = Drafting.straightEnds(of: s) else { return s.worldBounds }
        return CGRect(x: min(p.x, q.x), y: min(p.y, q.y), width: abs(p.x - q.x), height: abs(p.y - q.y))
    }

    static func measuredPoints(_ spec: DimensionSpec, _ a: Shape, _ b: Shape) -> (CGPoint, CGPoint) {
        let A = extent(of: a), B = extent(of: b)
        switch spec.axis {
        case .horizontal:
            if a.id == b.id { return (CGPoint(x: A.minX, y: A.minY), CGPoint(x: A.maxX, y: A.minY)) }
            let (x1, x2): (CGFloat, CGFloat) = A.maxX <= B.minX ? (A.maxX, B.minX) : (B.maxX <= A.minX ? (B.maxX, A.minX) : (A.midX, B.midX))
            return (CGPoint(x: x1, y: A.minY), CGPoint(x: x2, y: B.minY))
        case .vertical:
            if a.id == b.id { return (CGPoint(x: A.minX, y: A.minY), CGPoint(x: A.minX, y: A.maxY)) }
            let (y1, y2): (CGFloat, CGFloat) = A.maxY <= B.minY ? (A.maxY, B.minY) : (B.maxY <= A.minY ? (B.maxY, A.minY) : (A.midY, B.midY))
            return (CGPoint(x: A.minX, y: y1), CGPoint(x: B.minX, y: y2))
        case .aligned:
            if a.id == b.id {
                if let ends = Drafting.straightEnds(of: a) { return ends }
                return (CGPoint(x: A.minX, y: A.minY), CGPoint(x: A.maxX, y: A.maxY))
            }
            return (a.boundaryPoint(toward: b.center), b.boundaryPoint(toward: a.center))
        }
    }

    static func geometry(_ c: Connector, _ spec: DimensionSpec, _ a: Shape, _ b: Shape, scale: DrawingScale?) -> ConnectorGeometry {
        let (p1, p2) = measuredPoints(spec, a, b)
        let off = CGFloat(spec.offset)
        var q1: CGPoint, q2: CGPoint
        var normal: CGPoint            // from the object toward the dimension line
        switch spec.axis {
        case .horizontal:
            let y = min(p1.y, p2.y) - off
            q1 = CGPoint(x: p1.x, y: y); q2 = CGPoint(x: p2.x, y: y)
            normal = CGPoint(x: 0, y: off >= 0 ? -1 : 1)
        case .vertical:
            let x = min(p1.x, p2.x) - off
            q1 = CGPoint(x: x, y: p1.y); q2 = CGPoint(x: x, y: p2.y)
            normal = CGPoint(x: off >= 0 ? -1 : 1, y: 0)
        case .aligned:
            let d = CGPoint(x: p2.x - p1.x, y: p2.y - p1.y)
            let len = max(hypot(d.x, d.y), 0.0001)
            var n = CGPoint(x: d.y / len, y: -d.x / len)
            if n.y > 0.0001 || (abs(n.y) <= 0.0001 && n.x > 0) { n = CGPoint(x: -n.x, y: -n.y) }       // up, or to the left
            q1 = CGPoint(x: p1.x + n.x * off, y: p1.y + n.y * off); q2 = CGPoint(x: p2.x + n.x * off, y: p2.y + n.y * off)
            normal = off >= 0 ? n : CGPoint(x: -n.x, y: -n.y)
        }
        let path = CGMutablePath()
        path.move(to: q1); path.addLine(to: q2)
        // Extension lines: from just off the object to just past the dimension line.
        for (p, q) in [(p1, q1), (p2, q2)] {
            path.move(to: CGPoint(x: p.x + normal.x * gap, y: p.y + normal.y * gap))
            path.addLine(to: CGPoint(x: q.x + normal.x * overshoot, y: q.y + normal.y * overshoot))
        }
        // Architectural ticks: a short slash at 45 degrees across each end of the dimension line.
        let dir = CGPoint(x: q2.x - q1.x, y: q2.y - q1.y)
        let theta = atan2(dir.y, dir.x) - .pi / 4
        let t = CGPoint(x: cos(theta) * tick, y: sin(theta) * tick)
        for q in [q1, q2] {
            path.move(to: CGPoint(x: q.x - t.x, y: q.y - t.y)); path.addLine(to: CGPoint(x: q.x + t.x, y: q.y + t.y))
        }
        let measured = hypot(q2.x - q1.x, q2.y - q1.y)
        let along = atan2(dir.y, dir.x)
        var g = ConnectorGeometry(path: path, startPoint: q1, startAngle: along + .pi, endPoint: q2, endAngle: along,
                                  labelPoint: CGPoint(x: (q1.x + q2.x) / 2, y: (q1.y + q2.y) / 2))
        g.measureText = (scale ?? .standard).format(points: Double(measured))
        g.measuredLength = Double(measured)
        return g
    }
}
