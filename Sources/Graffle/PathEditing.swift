import AppKit

/// Turns a CGPath into the normalized outline stored on `.path` shapes.
enum Outline {
    /// `frame` is the path's tight bounds (at least 1pt each way); segment points are 0...1 within it.
    static func normalize(_ path: CGPath) -> (frame: CGRect, segments: [PathSegment])? {
        let bb = path.boundingBoxOfPath   // tight bounds; `boundingBox` would include curve control points
        guard !bb.isNull, !bb.isInfinite, bb.origin.x.isFinite, bb.origin.y.isFinite else { return nil }
        let w = max(bb.width, 1), h = max(bb.height, 1)
        func norm(_ p: CGPoint) -> CGPoint { CGPoint(x: (p.x - bb.minX) / w, y: (p.y - bb.minY) / h) }

        var segs: [PathSegment] = []
        var current = CGPoint.zero
        path.applyWithBlock { el in
            let e = el.pointee, p = e.points
            switch e.type {
            case .moveToPoint:
                segs.append(PathSegment(op: .move, points: [norm(p[0])])); current = p[0]
            case .addLineToPoint:
                segs.append(PathSegment(op: .line, points: [norm(p[0])])); current = p[0]
            case .addQuadCurveToPoint:
                let c1 = CGPoint(x: current.x + 2 * (p[0].x - current.x) / 3, y: current.y + 2 * (p[0].y - current.y) / 3)
                let c2 = CGPoint(x: p[1].x + 2 * (p[0].x - p[1].x) / 3, y: p[1].y + 2 * (p[0].y - p[1].y) / 3)
                segs.append(PathSegment(op: .curve, points: [norm(c1), norm(c2), norm(p[1])])); current = p[1]
            case .addCurveToPoint:
                segs.append(PathSegment(op: .curve, points: [norm(p[0]), norm(p[1]), norm(p[2])])); current = p[2]
            case .closeSubpath:
                segs.append(PathSegment(op: .close))
            @unknown default: break
            }
        }
        guard !segs.isEmpty else { return nil }
        return (CGRect(x: bb.minX, y: bb.minY, width: w, height: h), segs)
    }
}

/// One anchor of a Bézier path, in canvas coordinates. A missing handle means the curve leaves/enters straight.
struct PenPoint: Equatable {
    var anchor: CGPoint
    var handleIn: CGPoint? = nil
    var handleOut: CGPoint? = nil
}

/// A single Bézier subpath that the pen tool draws and the point editor changes.
struct PenPath: Equatable {
    var points: [PenPoint] = []
    var closed = false

    // MARK: Geometry

    private static func addSegment(_ p: CGMutablePath, _ a: PenPoint, _ b: PenPoint) {
        if a.handleOut == nil && b.handleIn == nil {
            p.addLine(to: b.anchor)
        } else {
            p.addCurve(to: b.anchor, control1: a.handleOut ?? a.anchor, control2: b.handleIn ?? b.anchor)
        }
    }

    /// The path; `cursor` adds a live segment from the last point to the pointer (the pen's rubber band).
    func cgPath(extendingTo cursor: CGPoint? = nil) -> CGPath {
        let p = CGMutablePath()
        guard let first = points.first else { return p }
        p.move(to: first.anchor)
        for i in 1..<max(points.count, 1) { PenPath.addSegment(p, points[i - 1], points[i]) }
        if closed, points.count > 1, let last = points.last {
            PenPath.addSegment(p, last, first)
            p.closeSubpath()
        } else if let c = cursor, let last = points.last {
            if let h = last.handleOut { p.addCurve(to: c, control1: h, control2: c) } else { p.addLine(to: c) }
        }
        return p
    }

    /// The outline in the form `.path` shapes store, plus the frame it is normalized to.
    func outline() -> (frame: CGRect, segments: [PathSegment])? {
        points.count >= 2 ? Outline.normalize(cgPath()) : nil
    }

    // MARK: Reading a shape

    /// The editable points of a `.path` shape, in canvas coordinates. Returns nil when the shape has several
    /// subpaths (not editable here).
    static func from(_ shape: Shape) -> PenPath? {
        guard shape.kind == .path, let segs = shape.outline, !segs.isEmpty else { return nil }
        let f = shape.frame
        func world(_ q: CGPoint) -> CGPoint {
            shape.toWorld(CGPoint(x: f.minX + q.x * f.width, y: f.minY + q.y * f.height))
        }
        var pts: [PenPoint] = []
        var closed = false
        var moves = 0
        for seg in segs {
            switch seg.op {
            case .move:
                moves += 1
                guard moves == 1, let p = seg.points.first else { return nil }
                pts.append(PenPoint(anchor: world(p)))
            case .line:
                guard !pts.isEmpty, let p = seg.points.first else { return nil }
                pts.append(PenPoint(anchor: world(p)))
            case .curve:
                guard !pts.isEmpty, seg.points.count >= 3 else { return nil }
                pts[pts.count - 1].handleOut = world(seg.points[0])
                pts.append(PenPoint(anchor: world(seg.points[2]), handleIn: world(seg.points[1])))
            case .close:
                closed = true
            }
        }
        guard pts.count >= 2 else { return nil }

        // A closed path often repeats its first point at the end; fold that into the first anchor.
        if closed, let last = pts.last, hypot(last.anchor.x - pts[0].anchor.x, last.anchor.y - pts[0].anchor.y) < 0.01 {
            pts[0].handleIn = last.handleIn
            pts.removeLast()
        }
        // Handles that sit on their anchor are the same as no handle.
        for i in pts.indices {
            if let h = pts[i].handleIn, PenPath.same(h, pts[i].anchor) { pts[i].handleIn = nil }
            if let h = pts[i].handleOut, PenPath.same(h, pts[i].anchor) { pts[i].handleOut = nil }
        }
        return pts.count >= 2 ? PenPath(points: pts, closed: closed) : nil
    }

    private static func same(_ a: CGPoint, _ b: CGPoint) -> Bool { abs(a.x - b.x) < 1e-6 && abs(a.y - b.y) < 1e-6 }

    // MARK: Editing

    /// True when both handles exist and point in opposite directions.
    func isSmooth(_ i: Int) -> Bool {
        guard points.indices.contains(i), let hi = points[i].handleIn, let ho = points[i].handleOut else { return false }
        let a = points[i].anchor
        let ux = hi.x - a.x, uy = hi.y - a.y, vx = ho.x - a.x, vy = ho.y - a.y
        let lu = hypot(ux, uy), lv = hypot(vx, vy)
        guard lu > 1e-6, lv > 1e-6 else { return false }
        return abs(ux * vy - uy * vx) < 1e-3 * lu * lv && ux * vx + uy * vy < 0
    }

    /// Smooth -> corner (drops both handles); corner -> smooth (handles along the neighbors' direction).
    mutating func toggleSmooth(_ i: Int) {
        guard points.indices.contains(i) else { return }
        if points[i].handleIn != nil || points[i].handleOut != nil {
            points[i].handleIn = nil
            points[i].handleOut = nil
            return
        }
        let n = points.count
        let prev = (i > 0) ? points[i - 1].anchor : (closed ? points[n - 1].anchor : nil)
        let next = (i < n - 1) ? points[i + 1].anchor : (closed ? points[0].anchor : nil)
        let a = points[i].anchor
        let from = prev ?? a, to = next ?? a
        var dx = to.x - from.x, dy = to.y - from.y
        let len = hypot(dx, dy)
        guard len > 1e-6 else { return }
        dx /= len; dy /= len
        let reach = min(prev.map { hypot($0.x - a.x, $0.y - a.y) } ?? .infinity,
                        next.map { hypot($0.x - a.x, $0.y - a.y) } ?? .infinity) / 3
        guard reach.isFinite, reach > 0 else { return }
        if prev != nil { points[i].handleIn = CGPoint(x: a.x - dx * reach, y: a.y - dy * reach) }
        if next != nil { points[i].handleOut = CGPoint(x: a.x + dx * reach, y: a.y + dy * reach) }
    }

    mutating func moveAnchor(_ i: Int, by d: CGSize) {
        guard points.indices.contains(i) else { return }
        func shift(_ p: CGPoint) -> CGPoint { CGPoint(x: p.x + d.width, y: p.y + d.height) }
        points[i].anchor = shift(points[i].anchor)
        points[i].handleIn = points[i].handleIn.map(shift)
        points[i].handleOut = points[i].handleOut.map(shift)
    }

    /// Drags one handle. With `mirror`, the opposite handle swings to stay in line (keeping its own length).
    mutating func setHandle(_ i: Int, out: Bool, to p: CGPoint, mirror: Bool) {
        guard points.indices.contains(i) else { return }
        let a = points[i].anchor
        if out { points[i].handleOut = p } else { points[i].handleIn = p }
        guard mirror else { return }
        let dx = p.x - a.x, dy = p.y - a.y
        let len = hypot(dx, dy)
        guard len > 1e-6 else { return }
        let other = out ? points[i].handleIn : points[i].handleOut
        let otherLen = other.map { hypot($0.x - a.x, $0.y - a.y) } ?? len
        let opposite = CGPoint(x: a.x - dx / len * otherLen, y: a.y - dy / len * otherLen)
        if out { points[i].handleIn = opposite } else { points[i].handleOut = opposite }
    }

    mutating func removePoint(_ i: Int) {
        guard points.indices.contains(i), points.count > 2 else { return }
        points.remove(at: i)
    }

    // MARK: Hit testing and splitting

    private func segmentEnds(_ i: Int) -> (PenPoint, PenPoint)? {
        let n = points.count
        if i < n - 1 { return (points[i], points[i + 1]) }
        return (closed && i == n - 1 && n > 1) ? (points[n - 1], points[0]) : nil
    }

    private static func bezier(_ p0: CGPoint, _ p1: CGPoint, _ p2: CGPoint, _ p3: CGPoint, _ t: CGFloat) -> CGPoint {
        let u = 1 - t
        let a = u * u * u, b = 3 * u * u * t, c = 3 * u * t * t, d = t * t * t
        return CGPoint(x: a * p0.x + b * p1.x + c * p2.x + d * p3.x, y: a * p0.y + b * p1.y + c * p2.y + d * p3.y)
    }

    /// The point on the path closest to `p`: which segment, how far along it (0...1), and the distance.
    func nearest(to p: CGPoint) -> (segment: Int, t: CGFloat, distance: CGFloat)? {
        var best: (Int, CGFloat, CGFloat)?
        for i in points.indices {
            guard let (a, b) = segmentEnds(i) else { continue }
            let p0 = a.anchor, p1 = a.handleOut ?? a.anchor, p2 = b.handleIn ?? b.anchor, p3 = b.anchor
            let steps = 48
            for k in 0...steps {
                let t = CGFloat(k) / CGFloat(steps)
                let q = PenPath.bezier(p0, p1, p2, p3, t)
                let d = hypot(q.x - p.x, q.y - p.y)
                if best == nil || d < best!.2 { best = (i, t, d) }
            }
        }
        return best.map { (segment: $0.0, t: $0.1, distance: $0.2) }
    }

    /// Adds an anchor on `segment` at parameter `t` without changing the curve's shape (de Casteljau split).
    mutating func insertPoint(segment i: Int, t: CGFloat) {
        guard let (a, b) = segmentEnds(i) else { return }
        func lerp(_ p: CGPoint, _ q: CGPoint) -> CGPoint { CGPoint(x: p.x + (q.x - p.x) * t, y: p.y + (q.y - p.y) * t) }
        let p0 = a.anchor, p1 = a.handleOut ?? a.anchor, p2 = b.handleIn ?? b.anchor, p3 = b.anchor
        let straight = a.handleOut == nil && b.handleIn == nil

        var mid = PenPoint(anchor: lerp(p0, p3))
        var first = a, second = b
        if !straight {
            let p01 = lerp(p0, p1), p12 = lerp(p1, p2), p23 = lerp(p2, p3)
            let p012 = lerp(p01, p12), p123 = lerp(p12, p23)
            mid = PenPoint(anchor: lerp(p012, p123), handleIn: p012, handleOut: p123)
            first.handleOut = p01
            second.handleIn = p23
        }
        let n = points.count
        let j = (i + 1) % n
        points[i] = first
        points[j] = second
        points.insert(mid, at: i == n - 1 ? n : i + 1)
    }
}
