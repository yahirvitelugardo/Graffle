import Foundation
import CoreGraphics

enum ProjectionSystem: String, CaseIterable {
    case european, american

    var title: String {
        switch self {
        case .european: return "European (first angle: top view below the front)"
        case .american: return "American (third angle: top view above the front)"
        }
    }
}

struct MeshViewOptions {
    var unit: LengthUnit = .millimeter
    var system: ProjectionSystem = .european
    var views: [ViewKind] = [.front, .top, .left, .isometric]
    var creaseDegrees: Double = 30
    var hiddenLines = true
    /// Isometric drawings are usually shown without their hidden lines.
    var hiddenInIsometric = false
    var dimensions = true
    /// Length in points of the part's longest side.
    var size: Double = 260
}

/// Lays the views of a mesh out on a sheet, as editable shapes: one group per view, with its name and (optionally) overall dimensions.
enum MeshDrawing {
    static let ink = RGBA(0.10, 0.11, 0.14)

    /// Where each view sits relative to the front view (column, row), the front being at (1, 1).
    static func cell(_ kind: ViewKind, system: ProjectionSystem) -> (col: Int, row: Int) {
        switch (kind, system) {
        case (.front, _): return (1, 1)
        case (.top, .european): return (1, 2)
        case (.bottom, .european): return (1, 0)
        case (.left, .european): return (2, 1)
        case (.right, .european): return (0, 1)
        case (.back, .european): return (3, 1)
        case (.top, .american): return (1, 0)
        case (.bottom, .american): return (1, 2)
        case (.right, .american): return (2, 1)
        case (.left, .american): return (0, 1)
        case (.back, .american): return (3, 1)
        case (.isometric, _): return (2, 2)
        }
    }

    static func build(_ mesh: Mesh, options: MeshViewOptions) -> Drawing {
        var d = Drawing()
        let layer = d.layers[0].id
        let projector = MeshProjector(mesh: mesh, crease: options.creaseDegrees)
        let views = options.views.map { kind -> ProjectedView in
            var v = projector.project(kind, hiddenLines: options.hiddenLines || kind == .isometric)
            if !options.hiddenLines || (kind == .isometric && !options.hiddenInIsometric) { v.hidden = [] }
            return v
        }
        guard !views.isEmpty else { return d }

        // One scale for every view, so they can be compared; the sheet's scale lets dimensions read in the part's own unit.
        let longest = views.map { max($0.bounds.width, $0.bounds.height) }.max() ?? 1
        let k = options.size / max(longest, 1e-9)                       // points per model unit
        var scale = DrawingScale()
        scale.unit = options.unit
        scale.unitsPerPoint = 1 / k
        d.scale = scale

        let gap: Double = 100, labelRoom: Double = 34, margin: Double = 140
        // Column widths and row heights come from the views placed in them.
        var cells: [(view: ProjectedView, col: Int, row: Int)] = []
        var used = Set<String>()
        for v in views {
            var c = cell(v.kind, system: options.system)
            if used.contains("\(c.col),\(c.row)") { c = (c.col, c.row + 1) }
            used.insert("\(c.col),\(c.row)")
            cells.append((v, c.col, c.row))
        }
        let cols = (cells.map(\.col).max() ?? 0) + 1, rows = (cells.map(\.row).max() ?? 0) + 1
        var colW = [Double](repeating: 0, count: cols), rowH = [Double](repeating: 0, count: rows)
        for c in cells {
            colW[c.col] = max(colW[c.col], Double(c.view.bounds.width) * k)
            rowH[c.row] = max(rowH[c.row], Double(c.view.bounds.height) * k + labelRoom)
        }
        func colX(_ i: Int) -> Double { margin + (0..<i).reduce(0) { $0 + colW[$1] + gap } }
        func rowY(_ i: Int) -> Double { margin + (0..<i).reduce(0) { $0 + rowH[$1] + gap } }

        func pathShape(_ segs: [Segment2D], origin: CGPoint, bounds: CGRect, style: Style, name: String, group: UUID) -> Shape? {
            guard !segs.isEmpty else { return nil }
            func p(_ q: CGPoint) -> CGPoint { CGPoint(x: origin.x + (q.x - bounds.minX) * k, y: origin.y + (bounds.maxY - q.y) * k) }
            let pts = segs.map { (p($0.0), p($0.1)) }
            let xs = pts.flatMap { [$0.0.x, $0.1.x] }, ys = pts.flatMap { [$0.0.y, $0.1.y] }
            let frame = CGRect(x: xs.min()!, y: ys.min()!, width: max(xs.max()! - xs.min()!, 1), height: max(ys.max()! - ys.min()!, 1))
            func n(_ q: CGPoint) -> CGPoint { CGPoint(x: (q.x - frame.minX) / frame.width, y: (q.y - frame.minY) / frame.height) }
            var outline: [PathSegment] = []
            for (a, b) in pts {
                outline.append(PathSegment(op: .move, points: [n(a)]))
                outline.append(PathSegment(op: .line, points: [n(b)]))
            }
            return Shape(layer: layer, kind: .path, frame: frame, style: style, group: group, outline: outline, name: name)
        }

        var anchors: [ViewKind: UUID] = [:]
        for c in cells {
            let v = c.view
            let w = Double(v.bounds.width) * k, h = Double(v.bounds.height) * k
            let origin = CGPoint(x: colX(c.col) + (colW[c.col] - w) / 2, y: rowY(c.row) + (rowH[c.row] - labelRoom - h) / 2)
            let group = UUID()
            // An invisible box with the part's extent: what dimensions measure, and what moves the view when clicked.
            var boxStyle = Style()
            boxStyle.fill.kind = .none; boxStyle.stroke.visible = false
            let box = Shape(layer: layer, kind: .rectangle, frame: CGRect(x: origin.x, y: origin.y, width: max(w, 1), height: max(h, 1)), style: boxStyle,
                            group: group, name: v.kind.title)
            d.shapes.append(box)
            anchors[v.kind] = box.id
            var hiddenStyle = Style()
            hiddenStyle.fill.kind = .none; hiddenStyle.stroke.color = RGBA(0.35, 0.36, 0.40); hiddenStyle.stroke.width = 1
            hiddenStyle.stroke.dash = .dashed; hiddenStyle.stroke.cap = .butt
            if let s = pathShape(v.hidden, origin: origin, bounds: v.bounds, style: hiddenStyle, name: v.kind.title + " (hidden)", group: group) { d.shapes.append(s) }
            var lineStyle = Style()
            lineStyle.fill.kind = .none; lineStyle.stroke.color = ink; lineStyle.stroke.width = 1.8
            lineStyle.stroke.cap = .round; lineStyle.stroke.join = .round
            if let s = pathShape(v.visible, origin: origin, bounds: v.bounds, style: lineStyle, name: v.kind.title + " (lines)", group: group) { d.shapes.append(s) }
            var label = Style.textBox
            label.text.size = 14; label.text.color = ink
            label.text.font = "Menlo"
            d.shapes.append(Shape(layer: layer, kind: .text, frame: CGRect(x: origin.x + w / 2 - 90, y: origin.y + h + 8, width: 180, height: 28), style: label,
                                  text: v.kind.title, group: group, name: v.kind.title + " label"))
        }

        if options.dimensions {
            var st = Style.connector
            st.stroke.color = RGBA(0.10, 0.12, 0.30); st.stroke.width = 1; st.text.size = 11; st.text.color = RGBA(0.10, 0.12, 0.30)
            func dim(_ kind: ViewKind, _ axis: DimensionAxis) {
                guard let id = anchors[kind] else { return }
                d.connectors.append(Connector(layer: layer, from: id, to: id, route: .straight, startHead: .none, endHead: .none, style: st,
                                              dimension: DimensionSpec(axis: axis, offset: 28)))
            }
            dim(.front, .horizontal); dim(.front, .vertical)
            if anchors[.left] == nil { dim(.top, .vertical) } else { dim(.top, .vertical); dim(.left, .horizontal) }
        }
        return d
    }
}

/// A small part to try the feature with: a U-shaped bracket made of unit cubes (only the outside faces are generated).
enum MeshSamples {
    static func voxels(_ filled: Set<[Int]>, size: Double = 10) -> Mesh {
        var mesh = Mesh()
        let dirs: [(Int, Int, Int)] = [(1, 0, 0), (-1, 0, 0), (0, 1, 0), (0, -1, 0), (0, 0, 1), (0, 0, -1)]
        for v in filled {
            for (dx, dy, dz) in dirs where !filled.contains([v[0] + dx, v[1] + dy, v[2] + dz]) {
                // The four corners of the face on that side, as two triangles.
                func corner(_ a: Int, _ b: Int) -> Vec3 {
                    var p = [Double(v[0]), Double(v[1]), Double(v[2])]
                    if dx != 0 { p[0] += dx > 0 ? 1 : 0; p[1] += Double(a); p[2] += Double(b) }
                    else if dy != 0 { p[1] += dy > 0 ? 1 : 0; p[0] += Double(a); p[2] += Double(b) }
                    else { p[2] += dz > 0 ? 1 : 0; p[0] += Double(a); p[1] += Double(b) }
                    return Vec3(p[0] * size, p[1] * size, p[2] * size)
                }
                let c = [corner(0, 0), corner(1, 0), corner(1, 1), corner(0, 1)]
                mesh.triangles.append((c[0], c[1], c[2])); mesh.triangles.append((c[0], c[2], c[3]))
            }
        }
        return mesh
    }

    static func bracket() -> Mesh {
        var cells = Set<[Int]>()
        for x in 0..<5 { for y in 0..<3 { cells.insert([x, y, 0]) } }                    // base
        for y in 0..<3 { for z in 1..<4 { cells.insert([0, y, z]); cells.insert([4, y, z]) } }   // two walls
        return voxels(cells)
    }

    /// A UV sphere (poles on the Z axis).
    static func sphere(rings: Int = 16, segments: Int = 24, radius r: Double = 10) -> Mesh {
        var m = Mesh()
        func p(_ i: Int, _ j: Int) -> Vec3 {
            let a = Double.pi * Double(i) / Double(rings), b = 2 * Double.pi * Double(j % segments) / Double(segments)
            return Vec3(r * sin(a) * cos(b), r * sin(a) * sin(b), r * cos(a))
        }
        for i in 0..<rings { for j in 0..<segments {
            if i > 0 { m.triangles.append((p(i, j), p(i + 1, j), p(i, j + 1))) }
            if i < rings - 1 { m.triangles.append((p(i, j + 1), p(i + 1, j), p(i + 1, j + 1))) }
        } }
        return m
    }
}
