import Foundation
import CoreGraphics

enum ViewKind: String, CaseIterable {
    case front, top, left, right, bottom, back, isometric

    var title: String {
        switch self {
        case .front: return "Front"
        case .top: return "Top"
        case .left: return "Left side"
        case .right: return "Right side"
        case .bottom: return "Bottom"
        case .back: return "Back"
        case .isometric: return "Isometric"
        }
    }

    /// Direction the viewer looks along, and which way is up on the page (model: X right, Y away from the front, Z up).
    var look: (direction: Vec3, up: Vec3) {
        switch self {
        case .front: return (Vec3(0, 1, 0), Vec3(0, 0, 1))
        case .back: return (Vec3(0, -1, 0), Vec3(0, 0, 1))
        case .left: return (Vec3(1, 0, 0), Vec3(0, 0, 1))
        case .right: return (Vec3(-1, 0, 0), Vec3(0, 0, 1))
        case .top: return (Vec3(0, 0, -1), Vec3(0, 1, 0))
        case .bottom: return (Vec3(0, 0, 1), Vec3(0, -1, 0))
        case .isometric: return (Vec3(-1, 1, -1).normalized, Vec3(0, 0, 1))
        }
    }
}

typealias Segment2D = (CGPoint, CGPoint)

/// One view of a mesh: line segments in model units (x to the right, y up), and the extent of the projected part.
struct ProjectedView {
    var kind: ViewKind
    var visible: [Segment2D]
    var hidden: [Segment2D]
    var bounds: CGRect
}

/// Turns a mesh into line drawings: crease and silhouette edges, with hidden lines found by a depth buffer.
final class MeshProjector {
    private struct Edge { var a: Int, b: Int, n1: Vec3, n2: Vec3?, feature: Bool }

    private let vertices: [Vec3]
    private let faces: [(Int, Int, Int)]
    private var edges: [Edge] = []
    let extent: Double          // diagonal of the part

    /// `crease` is the angle in degrees between neighbouring faces above which their shared edge is drawn.
    init(mesh: Mesh, crease: Double) {
        let b = mesh.bounds ?? (Vec3(0, 0, 0), Vec3(1, 1, 1))
        let diag = max((b.1 - b.0).length, 1e-9)
        extent = diag
        // Weld the vertices STL repeats for every triangle.
        let q = diag * 1e-6
        struct Key: Hashable { var x: Int64, y: Int64, z: Int64 }
        var index: [Key: Int] = [:]
        var verts: [Vec3] = []
        var tris: [(Int, Int, Int)] = []
        func id(_ v: Vec3) -> Int {
            let k = Key(x: Int64((v.x / q).rounded()), y: Int64((v.y / q).rounded()), z: Int64((v.z / q).rounded()))
            if let i = index[k] { return i }
            verts.append(v); index[k] = verts.count - 1
            return verts.count - 1
        }
        for t in mesh.triangles {
            let (i, j, k) = (id(t.0), id(t.1), id(t.2))
            if i != j && j != k && i != k { tris.append((i, j, k)) }
        }
        vertices = verts
        faces = tris

        struct EdgeKey: Hashable { var a: Int, b: Int }
        var map: [EdgeKey: [Vec3]] = [:]
        for (i, j, k) in tris {
            let n = (verts[j] - verts[i]).cross(verts[k] - verts[i])
            guard n.length > 0 else { continue }
            let nn = n.normalized
            for (a, b) in [(i, j), (j, k), (k, i)] { map[EdgeKey(a: min(a, b), b: max(a, b)), default: []].append(nn) }
        }
        let cosCrease = cos(crease * .pi / 180)
        edges = map.map { key, normals in
            if normals.count == 2 {
                return Edge(a: key.a, b: key.b, n1: normals[0], n2: normals[1], feature: normals[0].dot(normals[1]) < cosCrease)
            }
            return Edge(a: key.a, b: key.b, n1: normals[0], n2: nil, feature: true)          // open or non-manifold edges always count
        }
    }

    /// Projects the part along `kind`'s direction. `resolution` is the size in pixels of the depth buffer's long side.
    func project(_ kind: ViewKind, hiddenLines: Bool = true, resolution: Int = 900) -> ProjectedView {
        let (d, upHint) = kind.look
        let right = d.cross(upHint).normalized
        let up = right.cross(d).normalized
        func screen(_ v: Vec3) -> (x: Double, y: Double, z: Double) { (v.dot(right), v.dot(up), v.dot(d)) }
        let pts = vertices.map(screen)
        guard let first = pts.first else { return ProjectedView(kind: kind, visible: [], hidden: [], bounds: .zero) }
        var minX = first.x, maxX = first.x, minY = first.y, maxY = first.y
        for p in pts { minX = min(minX, p.x); maxX = max(maxX, p.x); minY = min(minY, p.y); maxY = max(maxY, p.y) }
        let w = max(maxX - minX, 1e-9), h = max(maxY - minY, 1e-9)
        let scale = Double(resolution) / max(w, h)
        let pw = Int(w * scale) + 4, ph = Int(h * scale) + 4
        func px(_ p: (x: Double, y: Double, z: Double)) -> (x: Double, y: Double, z: Double) { ((p.x - minX) * scale + 2, (p.y - minY) * scale + 2, p.z) }

        // Which edges are drawn from this side: creases, and the outline where a front face meets a back face.
        var drawn: [Edge] = []
        for e in edges {
            if e.feature { drawn.append(e); continue }
            if let n2 = e.n2, e.n1.dot(d) * n2.dot(d) < 0 { drawn.append(e) }
        }

        var segments: (visible: [Segment2D], hidden: [Segment2D]) = ([], [])
        func model(_ x: Double, _ y: Double) -> CGPoint { CGPoint(x: x, y: y) }

        guard hiddenLines else {
            for e in drawn { segments.visible.append((model(pts[e.a].x, pts[e.a].y), model(pts[e.b].x, pts[e.b].y))) }
            return ProjectedView(kind: kind, visible: segments.visible, hidden: [], bounds: CGRect(x: minX, y: minY, width: w, height: h))
        }

        let base = extent * 0.002
        // Depth buffer: the nearest surface at every pixel.
        var depth = [Float](repeating: .infinity, count: pw * ph)
        for (i, j, k) in faces {
            let a = px(pts[i]), b = px(pts[j]), c = px(pts[k])
            let area = (b.x - a.x) * (c.y - a.y) - (b.y - a.y) * (c.x - a.x)
            if abs(area) < 1e-12 { continue }
            let x0 = max(Int(min(a.x, b.x, c.x).rounded(.down)), 0), x1 = min(Int(max(a.x, b.x, c.x).rounded(.up)), pw - 1)
            let y0 = max(Int(min(a.y, b.y, c.y).rounded(.down)), 0), y1 = min(Int(max(a.y, b.y, c.y).rounded(.up)), ph - 1)
            if x0 > x1 || y0 > y1 { continue }
            // Push the surface slightly away (more where it is steep), so the edges drawn on it are never judged hidden by it.
            let dzdx = ((b.z - a.z) * (c.y - a.y) - (c.z - a.z) * (b.y - a.y)) / area
            let dzdy = ((c.z - a.z) * (b.x - a.x) - (b.z - a.z) * (c.x - a.x)) / area
            let bias = Float(base + hypot(dzdx, dzdy) * 4)
            for y in y0...y1 {
                for x in x0...x1 {
                    let sx = Double(x) + 0.5, sy = Double(y) + 0.5
                    let w0 = ((b.x - sx) * (c.y - sy) - (b.y - sy) * (c.x - sx)) / area
                    let w1 = ((c.x - sx) * (a.y - sy) - (c.y - sy) * (a.x - sx)) / area
                    let w2 = 1 - w0 - w1
                    if w0 < -1e-9 || w1 < -1e-9 || w2 < -1e-9 { continue }
                    let z = Float(w0 * a.z + w1 * b.z + w2 * c.z) + bias
                    let o = y * pw + x
                    if z < depth[o] { depth[o] = z }
                }
            }
        }

        func isVisible(_ x: Double, _ y: Double, _ z: Double) -> Bool {
            let ix = min(max(Int(x), 0), pw - 1), iy = min(max(Int(y), 0), ph - 1)
            // The nearest surface within a pixel: an edge on the outline of the part sits on the border of the pixels
            // its faces cover, so looking at the neighbours is what tells a front edge from the identical one behind it.
            var nearest = Double.infinity
            for dy in -1...1 { for dx in -1...1 {
                let jx = ix + dx, jy = iy + dy
                guard jx >= 0, jy >= 0, jx < pw, jy < ph else { continue }
                nearest = min(nearest, Double(depth[jy * pw + jx]))
            } }
            return z <= nearest
        }

        for e in drawn {
            let p = px(pts[e.a]), q = px(pts[e.b])
            let length = hypot(q.x - p.x, q.y - p.y)
            if length < 0.5 { continue }                                 // an edge seen end-on is a point
            let steps = max(Int(length), 1)
            var flags = (0...steps).map { i -> Bool in
                let t = Double(i) / Double(steps)
                return isVisible(p.x + (q.x - p.x) * t, p.y + (q.y - p.y) * t, p.z + (q.z - p.z) * t)
            }
            // Short gaps in a visible line are rasterization noise, not hidden parts.
            var i = 0
            while i < flags.count {
                if !flags[i] {
                    var j = i
                    while j < flags.count && !flags[j] { j += 1 }
                    // A few hidden samples at the end of a line, or between visible stretches, are noise at a corner or a rim.
                    if j - i <= 4, i == 0 || flags[i - 1], j == flags.count || flags[j], !(i == 0 && j == flags.count) { for k in i..<j { flags[k] = true } }
                    i = j
                } else { i += 1 }
            }
            var start = 0
            while start < flags.count {
                var end = start
                while end + 1 < flags.count && flags[end + 1] == flags[start] { end += 1 }
                let t0 = Double(start) / Double(steps), t1 = Double(end) / Double(steps)
                let a = model(pts[e.a].x + (pts[e.b].x - pts[e.a].x) * t0, pts[e.a].y + (pts[e.b].y - pts[e.a].y) * t0)
                let b = model(pts[e.a].x + (pts[e.b].x - pts[e.a].x) * t1, pts[e.a].y + (pts[e.b].y - pts[e.a].y) * t1)
                if end > start || steps == 1 { if flags[start] { segments.visible.append((a, b)) } else { segments.hidden.append((a, b)) } }
                start = end + 1
            }
        }
        return ProjectedView(kind: kind, visible: Self.merged(segments.visible, tolerance: extent * 1e-4), hidden: Self.merged(segments.hidden, tolerance: extent * 1e-4),
                             bounds: CGRect(x: minX, y: minY, width: w, height: h))
    }

    /// Joins segments that lie on one line and touch or overlap into single long segments (a straight edge made of many
    /// mesh edges becomes one line, which also keeps dashes even).
    static func merged(_ segments: [Segment2D], tolerance: Double) -> [Segment2D] {
        struct Key: Hashable { var angle: Int, offset: Int }
        let angleStep = 2e-3
        var groups: [Key: [(t0: Double, t1: Double, dir: CGPoint, normal: Double)]] = [:]
        for (a, b) in segments {
            var dx = Double(b.x - a.x), dy = Double(b.y - a.y)
            let len = hypot(dx, dy)
            if len < 1e-12 { continue }
            dx /= len; dy /= len
            if dx < 0 || (dx == 0 && dy < 0) { dx = -dx; dy = -dy }                      // one direction per line
            let t0 = Double(a.x) * dx + Double(a.y) * dy, t1 = Double(b.x) * dx + Double(b.y) * dy
            let normal = Double(a.x) * -dy + Double(a.y) * dx
            let key = Key(angle: Int((atan2(dy, dx) / angleStep).rounded()), offset: Int((normal / max(tolerance * 4, 1e-12)).rounded()))
            groups[key, default: []].append((min(t0, t1), max(t0, t1), CGPoint(x: dx, y: dy), normal))
        }
        var out: [Segment2D] = []
        for (_, g) in groups {
            let sorted = g.sorted { $0.t0 < $1.t0 }
            var cur = sorted[0]
            func emit(_ s: (t0: Double, t1: Double, dir: CGPoint, normal: Double)) {
                let d = s.dir, nx = -Double(d.y) * s.normal, ny = Double(d.x) * s.normal
                out.append((CGPoint(x: nx + Double(d.x) * s.t0, y: ny + Double(d.y) * s.t0), CGPoint(x: nx + Double(d.x) * s.t1, y: ny + Double(d.y) * s.t1)))
            }
            for s in sorted.dropFirst() {
                if s.t0 <= cur.t1 + tolerance { cur.t1 = max(cur.t1, s.t1) } else { emit(cur); cur = s }
            }
            emit(cur)
        }
        return out
    }
}
