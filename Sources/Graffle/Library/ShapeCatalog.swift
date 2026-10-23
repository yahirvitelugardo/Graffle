import AppKit

/// One entry of the Shape Library: something that can be put on the canvas with a click or a drag.
struct LibraryItem: Identifiable {
    enum Origin: Equatable { case builtin, circuit, custom }

    let id: String
    var name: String
    let category: String
    let origin: Origin
    /// Size on the canvas.
    var size: CGSize
    /// What it is made of: a plain shape kind, or a free-form outline (points normalized to the frame).
    var kind: ShapeKind = .path
    var outline: [PathSegment]? = nil
    /// Takes the canvas's current fill and line look (circuit symbols and custom shapes bring their own).
    var usesCurrentStyle = true
    var cornerRadius: Double = 0
    var circuit: CircuitPart? = nil
    var custom: Drawing? = nil
    /// For real-world parts (architecture): the true size in centimeters, which the drawing scale turns into points.
    var realSize: CGSize? = nil
    /// Builds the part's shapes in centimeters with the top-left at the origin; they bring their own look.
    var compose: ((UUID) -> [Shape])? = nil

    /// Takes its own colors instead of the canvas's current style.
    var hasOwnLook: Bool { custom != nil || compose != nil }

    /// A drawing with this item in it, its top-left corner at the origin. `number` numbers circuit reference labels.
    func drawing(layer: UUID, style: Style, number: Int = 1, pointsPerCentimeter k: Double = 1) -> Drawing {
        var d = Drawing()
        d.layers = [Layer(name: "Layer 1")]
        if let compose {
            var shapes = compose(layer)
            for i in shapes.indices {
                let f = shapes[i].frame
                shapes[i].frame = CGRect(x: f.minX * k, y: f.minY * k, width: f.width * k, height: f.height * k)
            }
            d.layers[0].id = layer
            d.shapes = shapes
            return d
        }
        if let part = circuit {
            d.layers[0].id = layer
            d.shapes = [part.makeShape(layer: layer, at: .zero, number: number)]
            return d
        }
        if var sub = custom {
            // Keep the saved look; park the objects on the target layer with their top-left at the origin.
            let box = sub.shapes.map(\.worldBounds).reduce(nil) { acc, f in acc.map { $0.union(f) } ?? f } ?? .zero
            for i in sub.shapes.indices {
                sub.shapes[i].frame.origin.x -= box.minX
                sub.shapes[i].frame.origin.y -= box.minY
                sub.shapes[i].layer = layer
            }
            for i in sub.connectors.indices { sub.connectors[i].layer = layer }
            sub.layers = [Layer(id: layer, name: "Layer 1")]
            return sub
        }
        var s = Shape(layer: layer, kind: kind, frame: CGRect(origin: .zero, size: size), style: style, outline: outline, name: name)
        if kind == .rounded || cornerRadius > 0 { s.style.cornerRadius = cornerRadius > 0 ? cornerRadius : 12 }
        if isOpenPath { s.style.fill.kind = .none }
        d.layers[0].id = layer
        d.shapes = [s]
        return d
    }

    /// What the thumbnail draws: the part's shapes (centimeters for real-world parts).
    func previewShapes() -> [Shape] {
        if let sub = custom { return sub.shapes }
        if let compose { return compose(UUID()) }
        return [previewShape()]
    }

    /// A small stand-in shape for drawing the thumbnail.
    func previewShape() -> Shape {
        if let compose, let first = compose(UUID()).last { return first }
        if let part = circuit { return part.makeShape(layer: UUID(), at: .zero, number: 1) }
        return Shape(layer: UUID(), kind: kind, frame: CGRect(origin: .zero, size: size), outline: outline)
    }
}

/// The built-in catalog: basic shapes and polygons, arrows, flowchart blocks, callouts, diagram parts and the circuit symbols.
enum ShapeCatalog {
    static let basic = "Basic Shapes", polygons = "Polygons and Stars", arrows = "Arrows", flowchart = "Flowchart", callouts = "Callouts and Notes"
    static let diagram = "Diagram Parts", er = "Entity-Relationship", architecture = "Architecture", circuits = "Circuit Symbols"
    static let categoryOrder = [basic, polygons, arrows, flowchart, callouts, diagram, er, architecture, circuits]

    /// A path in normalized coordinates, written as it reads on paper.
    struct Pen {
        var segs: [PathSegment] = []
        mutating func m(_ x: Double, _ y: Double) { segs.append(PathSegment(op: .move, points: [CGPoint(x: x, y: y)])) }
        mutating func l(_ x: Double, _ y: Double) { segs.append(PathSegment(op: .line, points: [CGPoint(x: x, y: y)])) }
        mutating func c(_ x1: Double, _ y1: Double, _ x2: Double, _ y2: Double, _ x: Double, _ y: Double) {
            segs.append(PathSegment(op: .curve, points: [CGPoint(x: x1, y: y1), CGPoint(x: x2, y: y2), CGPoint(x: x, y: y)]))
        }
        mutating func z() { segs.append(PathSegment(op: .close)) }
        mutating func poly(_ pts: [(Double, Double)]) {
            for (i, p) in pts.enumerated() { if i == 0 { m(p.0, p.1) } else { l(p.0, p.1) } }
            z()
        }
        /// A full ellipse as four Bézier arcs.
        mutating func oval(_ cx: Double, _ cy: Double, _ rx: Double, _ ry: Double) {
            let k = 0.5523
            m(cx + rx, cy)
            c(cx + rx, cy + ry * k, cx + rx * k, cy + ry, cx, cy + ry)
            c(cx - rx * k, cy + ry, cx - rx, cy + ry * k, cx - rx, cy)
            c(cx - rx, cy - ry * k, cx - rx * k, cy - ry, cx, cy - ry)
            c(cx + rx * k, cy - ry, cx + rx, cy - ry * k, cx + rx, cy)
            z()
        }
    }

    private static func path(_ build: (inout Pen) -> Void) -> [PathSegment] {
        var p = Pen(); build(&p); return p.segs
    }

    /// A regular polygon with `n` corners inscribed in the unit square, the first corner at the top.
    static func regular(_ n: Int) -> [PathSegment] {
        path { p in
            let pts = (0..<n).map { i -> (Double, Double) in
                let a = -Double.pi / 2 + Double(i) * 2 * .pi / Double(n)
                return (0.5 + 0.5 * cos(a), 0.5 + 0.5 * sin(a))
            }
            // Fill the unit square vertically and horizontally so the frame is tight around the polygon.
            let xs = pts.map(\.0), ys = pts.map(\.1)
            let (x0, x1, y0, y1) = (xs.min()!, xs.max()!, ys.min()!, ys.max()!)
            p.poly(pts.map { (($0.0 - x0) / (x1 - x0), ($0.1 - y0) / (y1 - y0)) })
        }
    }

    /// A star with `n` points; `inner` is the inner radius as a fraction of the outer one.
    static func star(_ n: Int, inner: Double) -> [PathSegment] {
        path { p in
            let pts = (0..<(2 * n)).map { i -> (Double, Double) in
                let a = -Double.pi / 2 + Double(i) * .pi / Double(n)
                let r = i % 2 == 0 ? 0.5 : 0.5 * inner
                return (0.5 + r * cos(a), 0.5 + r * sin(a))
            }
            let xs = pts.map(\.0), ys = pts.map(\.1)
            let (x0, x1, y0, y1) = (xs.min()!, xs.max()!, ys.min()!, ys.max()!)
            p.poly(pts.map { (($0.0 - x0) / (x1 - x0), ($0.1 - y0) / (y1 - y0)) })
        }
    }

    private static func item(_ id: String, _ name: String, _ category: String, _ w: Double, _ h: Double, kind: ShapeKind = .path,
                             corner: Double = 0, _ outline: [PathSegment]? = nil) -> LibraryItem {
        LibraryItem(id: id, name: name, category: category, origin: .builtin, size: CGSize(width: w, height: h), kind: kind, outline: outline, cornerRadius: corner)
    }

    /// A crow's-foot table: a colored header and one row per field, grouped so it moves as one.
    private static func erTable(_ id: String, _ name: String, fields: [String]) -> LibraryItem {
        let layer = UUID(), group = UUID()
        let salmon = RGBA(0.98, 0.72, 0.66), zebra = RGBA(0.90, 0.91, 0.93), line = RGBA(0.33, 0.37, 0.45), ink = RGBA(0.13, 0.14, 0.18)
        let width = 200.0, head = 32.0, row = 26.0
        let height = head + row * Double(fields.count)
        func shape(_ frame: CGRect, _ text: String, fill: RGBA, stroke: Bool, size: Double, bold: Bool, align: HAlign) -> Shape {
            var st = Style()
            st.fill.color = fill
            st.stroke.visible = stroke
            st.stroke.color = line
            st.stroke.width = 1.5
            st.text.size = size
            st.text.bold = bold
            st.text.hAlign = align
            st.text.color = ink
            return Shape(layer: layer, kind: .rectangle, frame: frame, style: st, text: text, group: group)
        }
        var shapes = [shape(CGRect(x: 0, y: 0, width: width, height: height), "", fill: RGBA(1, 1, 1), stroke: true, size: 13, bold: false, align: .center)]
        shapes.append(shape(CGRect(x: 0, y: 0, width: width, height: head), "Table", fill: salmon, stroke: true, size: 15, bold: true, align: .center))
        for (i, field) in fields.enumerated() {
            shapes.append(shape(CGRect(x: 0, y: head + row * Double(i), width: width, height: row), field,
                                fill: i % 2 == 0 ? RGBA(1, 1, 1) : zebra, stroke: false, size: 13, bold: false, align: .left))
        }
        var d = Drawing()
        d.layers = [Layer(id: layer, name: "Layer 1")]
        d.shapes = shapes
        var it = LibraryItem(id: id, name: name, category: er, origin: .builtin, size: CGSize(width: width, height: height))
        it.custom = d
        it.usesCurrentStyle = false
        return it
    }

    static let items: [LibraryItem] = {
        var out: [LibraryItem] = []

        // MARK: Basic shapes
        out += [
            item("rectangle", "Rectangle", basic, 140, 90, kind: .rectangle),
            item("rounded", "Rounded Rectangle", basic, 140, 90, kind: .rounded, corner: 14),
            item("ellipse", "Ellipse", basic, 140, 90, kind: .ellipse),
            item("circle", "Circle", basic, 100, 100, kind: .ellipse),
            item("diamond", "Diamond", basic, 140, 100, kind: .diamond),
            item("triangle", "Triangle", basic, 120, 100, kind: .triangle),
            item("right-triangle", "Right Triangle", basic, 120, 100, path { $0.poly([(0, 0), (0, 1), (1, 1)]) }),
            item("parallelogram", "Parallelogram", basic, 150, 80, path { $0.poly([(0.2, 0), (1, 0), (0.8, 1), (0, 1)]) }),
            item("trapezoid", "Trapezoid", basic, 150, 80, path { $0.poly([(0.2, 0), (0.8, 0), (1, 1), (0, 1)]) }),
            item("plus", "Cross", basic, 100, 100, path { $0.poly([(0.33, 0), (0.67, 0), (0.67, 0.33), (1, 0.33), (1, 0.67), (0.67, 0.67), (0.67, 1), (0.33, 1), (0.33, 0.67), (0, 0.67), (0, 0.33), (0.33, 0.33)]) }),
            item("ring", "Ring", basic, 100, 100, path { $0.oval(0.5, 0.5, 0.5, 0.5); $0.oval(0.5, 0.5, 0.26, 0.26) }),
            item("heart", "Heart", basic, 110, 100, path { p in
                p.m(0.5, 1); p.c(0.1, 0.72, 0, 0.5, 0, 0.3); p.c(0, 0.1, 0.18, 0, 0.3, 0); p.c(0.4, 0, 0.47, 0.06, 0.5, 0.2)
                p.c(0.53, 0.06, 0.6, 0, 0.7, 0); p.c(0.82, 0, 1, 0.1, 1, 0.3); p.c(1, 0.5, 0.9, 0.72, 0.5, 1); p.z() }),
            item("crescent", "Crescent", basic, 90, 110, path { p in
                p.m(0.7, 0); p.c(0.2, 0.05, 0, 0.3, 0, 0.5); p.c(0, 0.72, 0.25, 0.96, 0.7, 1)
                p.c(0.35, 0.82, 0.3, 0.2, 0.7, 0); p.z() }),
            item("cloud", "Cloud", basic, 160, 100, path { p in
                p.m(0.22, 0.85); p.c(0.02, 0.88, -0.02, 0.55, 0.12, 0.5); p.c(0.0, 0.28, 0.2, 0.15, 0.3, 0.25)
                p.c(0.34, 0.0, 0.62, 0.0, 0.68, 0.22); p.c(0.84, 0.08, 1.02, 0.3, 0.88, 0.48); p.c(1.05, 0.55, 1.0, 0.88, 0.8, 0.85); p.z() }),
            item("lightning", "Lightning Bolt", basic, 90, 130, path { $0.poly([(0.6, 0), (0.1, 0.55), (0.45, 0.55), (0.3, 1), (0.9, 0.4), (0.55, 0.4)]) }),
            item("cylinder", "Cylinder", basic, 100, 130, path { p in
                p.m(0, 0.12); p.c(0, -0.04, 1, -0.04, 1, 0.12); p.l(1, 0.88); p.c(1, 1.04, 0, 1.04, 0, 0.88); p.z()
                p.m(0, 0.12); p.c(0, 0.28, 1, 0.28, 1, 0.12) }),
            item("cube", "Cube", basic, 120, 120, path { p in
                p.poly([(0, 0.25), (0.75, 0.25), (0.75, 1), (0, 1)])
                p.m(0, 0.25); p.l(0.25, 0); p.l(1, 0); p.l(0.75, 0.25)
                p.m(1, 0); p.l(1, 0.75); p.l(0.75, 1) }),
        ]

        // MARK: Polygons and stars
        for (n, name) in [(5, "Pentagon"), (6, "Hexagon"), (7, "Heptagon"), (8, "Octagon"), (9, "Nonagon"), (10, "Decagon"), (12, "Dodecagon")] {
            out.append(item("polygon-\(n)", name, polygons, 110, 110, regular(n)))
        }
        for n in [4, 5, 6, 7, 8, 12] { out.append(item("star-\(n)", "\(n)-Point Star", polygons, 120, 120, star(n, inner: n == 4 ? 0.38 : (n == 5 ? 0.42 : 0.6)))) }
        out.append(item("burst", "Burst", polygons, 130, 130, star(16, inner: 0.78)))

        // MARK: Arrows
        out += [
            item("arrow-right", "Right Arrow", arrows, 150, 80, path { $0.poly([(0, 0.3), (0.62, 0.3), (0.62, 0), (1, 0.5), (0.62, 1), (0.62, 0.7), (0, 0.7)]) }),
            item("arrow-left", "Left Arrow", arrows, 150, 80, path { $0.poly([(1, 0.3), (0.38, 0.3), (0.38, 0), (0, 0.5), (0.38, 1), (0.38, 0.7), (1, 0.7)]) }),
            item("arrow-up", "Up Arrow", arrows, 80, 150, path { $0.poly([(0.3, 1), (0.3, 0.38), (0, 0.38), (0.5, 0), (1, 0.38), (0.7, 0.38), (0.7, 1)]) }),
            item("arrow-down", "Down Arrow", arrows, 80, 150, path { $0.poly([(0.3, 0), (0.3, 0.62), (0, 0.62), (0.5, 1), (1, 0.62), (0.7, 0.62), (0.7, 0)]) }),
            item("arrow-both", "Double Arrow", arrows, 170, 80, path { $0.poly([(0, 0.5), (0.25, 0), (0.25, 0.3), (0.75, 0.3), (0.75, 0), (1, 0.5), (0.75, 1), (0.75, 0.7), (0.25, 0.7), (0.25, 1)]) }),
            item("chevron", "Chevron", arrows, 120, 90, path { $0.poly([(0, 0), (0.6, 0), (1, 0.5), (0.6, 1), (0, 1), (0.4, 0.5)]) }),
            item("home-plate", "Pentagon Arrow", arrows, 150, 80, path { $0.poly([(0, 0), (0.75, 0), (1, 0.5), (0.75, 1), (0, 1)]) }),
            item("notched-arrow", "Notched Arrow", arrows, 150, 80, path { $0.poly([(0, 0.3), (0.12, 0.5), (0, 0.7), (0.62, 0.7), (0.62, 1), (1, 0.5), (0.62, 0), (0.62, 0.3)]) }),
            item("bent-arrow", "Bent Arrow", arrows, 130, 130, path { $0.poly([(0, 1), (0, 0.45), (0.15, 0.3), (0.55, 0.3), (0.55, 0), (1, 0.4), (0.55, 0.8), (0.55, 0.55), (0.3, 0.55), (0.3, 1)]) }),
            item("u-turn", "U-Turn Arrow", arrows, 120, 130, path { p in
                p.m(0, 1); p.l(0, 0.35); p.c(0, -0.1, 0.62, -0.1, 0.62, 0.35); p.l(0.62, 0.45); p.l(0.82, 0.45); p.l(0.5, 0.82); p.l(0.18, 0.45)
                p.l(0.38, 0.45); p.l(0.38, 0.35); p.c(0.38, 0.3, 0.24, 0.3, 0.24, 0.35); p.l(0.24, 1); p.z() }),
        ]

        // MARK: Flowchart
        out += [
            item("fc-process", "Process", flowchart, 140, 80, kind: .rectangle),
            item("fc-terminator", "Terminator", flowchart, 140, 60, kind: .rounded, corner: 30),
            item("fc-decision", "Decision", flowchart, 140, 100, kind: .diamond),
            item("fc-data", "Data", flowchart, 150, 70, path { $0.poly([(0.15, 0), (1, 0), (0.85, 1), (0, 1)]) }),
            item("fc-predefined", "Predefined Process", flowchart, 140, 80, path { p in
                p.poly([(0, 0), (1, 0), (1, 1), (0, 1)]); p.m(0.12, 0); p.l(0.12, 1); p.m(0.88, 0); p.l(0.88, 1) }),
            item("fc-document", "Document", flowchart, 140, 90, path { p in
                p.m(0, 0); p.l(1, 0); p.l(1, 0.82); p.c(0.8, 0.7, 0.7, 0.7, 0.5, 0.85); p.c(0.3, 1, 0.2, 1, 0, 0.88); p.z() }),
            item("fc-multi-document", "Multiple Documents", flowchart, 150, 100, path { p in
                p.m(0.1, 0.1); p.l(0.1, 0); p.l(1, 0); p.l(1, 0.7); p.l(0.9, 0.7)
                p.m(0.2, 0.2); p.l(0.2, 0.1); p.l(0.9, 0.1); p.l(0.9, 0.78)
                p.m(0, 0.2); p.l(0.8, 0.2); p.l(0.8, 0.85); p.c(0.65, 0.78, 0.55, 0.78, 0.4, 0.9); p.c(0.25, 1, 0.12, 1, 0, 0.92); p.z() }),
            item("fc-database", "Database", flowchart, 100, 130, path { p in
                p.m(0, 0.12); p.c(0, -0.04, 1, -0.04, 1, 0.12); p.l(1, 0.88); p.c(1, 1.04, 0, 1.04, 0, 0.88); p.z()
                p.m(0, 0.12); p.c(0, 0.28, 1, 0.28, 1, 0.12) }),
            item("fc-manual-input", "Manual Input", flowchart, 140, 80, path { $0.poly([(0, 0.2), (1, 0), (1, 1), (0, 1)]) }),
            item("fc-delay", "Delay", flowchart, 130, 80, path { p in
                p.m(0, 0); p.l(0.6, 0); p.c(1.1, 0, 1.1, 1, 0.6, 1); p.l(0, 1); p.z() }),
            item("fc-preparation", "Preparation", flowchart, 150, 80, path { $0.poly([(0.15, 0), (0.85, 0), (1, 0.5), (0.85, 1), (0.15, 1), (0, 0.5)]) }),
            item("fc-offpage", "Off-page Connector", flowchart, 80, 90, path { $0.poly([(0, 0), (1, 0), (1, 0.65), (0.5, 1), (0, 0.65)]) }),
            item("fc-connector", "Connector", flowchart, 56, 56, kind: .ellipse),
            item("fc-summing", "Summing Junction", flowchart, 70, 70, path { p in
                p.oval(0.5, 0.5, 0.5, 0.5); p.m(0.146, 0.146); p.l(0.854, 0.854); p.m(0.854, 0.146); p.l(0.146, 0.854) }),
            item("fc-merge", "Merge", flowchart, 90, 80, path { $0.poly([(0, 0), (1, 0), (0.5, 1)]) }),
            item("fc-display", "Display", flowchart, 150, 80, path { p in
                p.m(0, 0.5); p.l(0.2, 0); p.l(0.8, 0); p.c(1.1, 0, 1.1, 1, 0.8, 1); p.l(0.2, 1); p.z() }),
        ]

        // MARK: Callouts and notes
        out += [
            item("callout-round", "Speech Bubble", callouts, 160, 110, path { p in
                p.m(0.1, 0); p.l(0.9, 0); p.c(0.96, 0, 1, 0.04, 1, 0.1); p.l(1, 0.58); p.c(1, 0.64, 0.96, 0.68, 0.9, 0.68); p.l(0.45, 0.68)
                p.l(0.2, 1); p.l(0.25, 0.68); p.l(0.1, 0.68); p.c(0.04, 0.68, 0, 0.64, 0, 0.58); p.l(0, 0.1); p.c(0, 0.04, 0.04, 0, 0.1, 0); p.z() }),
            item("callout-rect", "Callout", callouts, 160, 110, path { $0.poly([(0, 0), (1, 0), (1, 0.68), (0.45, 0.68), (0.2, 1), (0.25, 0.68), (0, 0.68)]) }),
            item("callout-thought", "Thought Bubble", callouts, 160, 120, path { p in
                p.oval(0.5, 0.35, 0.5, 0.35); p.oval(0.2, 0.82, 0.07, 0.07); p.oval(0.08, 0.96, 0.04, 0.04) }),
            item("note", "Note", callouts, 130, 100, path { p in
                p.poly([(0, 0), (0.78, 0), (1, 0.25), (1, 1), (0, 1)]); p.m(0.78, 0); p.l(0.78, 0.25); p.l(1, 0.25) }),
            item("brace-left", "Left Brace", callouts, 40, 140, path { p in
                p.m(1, 0); p.c(0.6, 0, 0.5, 0.05, 0.5, 0.2); p.l(0.5, 0.4); p.c(0.5, 0.46, 0.3, 0.5, 0, 0.5)
                p.c(0.3, 0.5, 0.5, 0.54, 0.5, 0.6); p.l(0.5, 0.8); p.c(0.5, 0.95, 0.6, 1, 1, 1) }),
            item("brace-right", "Right Brace", callouts, 40, 140, path { p in
                p.m(0, 0); p.c(0.4, 0, 0.5, 0.05, 0.5, 0.2); p.l(0.5, 0.4); p.c(0.5, 0.46, 0.7, 0.5, 1, 0.5)
                p.c(0.7, 0.5, 0.5, 0.54, 0.5, 0.6); p.l(0.5, 0.8); p.c(0.5, 0.95, 0.4, 1, 0, 1) }),
            item("bracket-left", "Left Bracket", callouts, 30, 140, path { p in p.m(1, 0); p.l(0, 0); p.l(0, 1); p.l(1, 1) }),
            item("bracket-right", "Right Bracket", callouts, 30, 140, path { p in p.m(0, 0); p.l(1, 0); p.l(1, 1); p.l(0, 1) }),
        ]

        // MARK: Diagram parts
        out += [
            item("actor", "Actor", diagram, 60, 120, path { p in
                p.oval(0.5, 0.14, 0.2, 0.12); p.m(0.5, 0.26); p.l(0.5, 0.62); p.m(0.1, 0.38); p.l(0.9, 0.38)
                p.m(0.5, 0.62); p.l(0.1, 1); p.m(0.5, 0.62); p.l(0.9, 1) }),
            item("package", "Package", diagram, 150, 100, path { p in
                p.poly([(0, 0.12), (0.4, 0.12), (0.4, 0), (0, 0)]); p.poly([(0, 0.12), (1, 0.12), (1, 1), (0, 1)]) }),
            item("component", "Component", diagram, 150, 90, path { p in
                p.poly([(0.08, 0), (1, 0), (1, 1), (0.08, 1)]); p.poly([(0, 0.18), (0.16, 0.18), (0.16, 0.38), (0, 0.38)])
                p.poly([(0, 0.62), (0.16, 0.62), (0.16, 0.82), (0, 0.82)]) }),
            item("server", "Server", diagram, 110, 130, path { p in
                p.poly([(0, 0), (1, 0), (1, 1), (0, 1)]); p.m(0, 0.33); p.l(1, 0.33); p.m(0, 0.66); p.l(1, 0.66)
                p.oval(0.18, 0.165, 0.04, 0.03); p.oval(0.18, 0.495, 0.04, 0.03); p.oval(0.18, 0.825, 0.04, 0.03) }),
            item("monitor", "Monitor", diagram, 130, 110, path { p in
                p.poly([(0, 0), (1, 0), (1, 0.75), (0, 0.75)]); p.m(0.5, 0.75); p.l(0.5, 0.9); p.m(0.25, 1); p.l(0.75, 1); p.m(0.5, 0.9); p.l(0.25, 1); p.m(0.5, 0.9); p.l(0.75, 1) }),
            item("folder", "Folder", diagram, 140, 100, path { $0.poly([(0, 0.1), (0.35, 0.1), (0.45, 0.22), (1, 0.22), (1, 1), (0, 1)]) }),
            item("person", "User", diagram, 90, 110, path { p in
                p.oval(0.5, 0.22, 0.24, 0.2); p.m(0.05, 1); p.c(0.05, 0.62, 0.95, 0.62, 0.95, 1); p.z() }),
        ]

        // MARK: Entity-relationship (Chen notation and crow's-foot tables)
        out += [
            item("er-entity", "Entity", er, 140, 70, kind: .rectangle),
            item("er-weak-entity", "Weak Entity", er, 150, 80, path { p in
                p.poly([(0, 0), (1, 0), (1, 1), (0, 1)]); p.poly([(0.05, 0.1), (0.95, 0.1), (0.95, 0.9), (0.05, 0.9)]) }),
            item("er-relationship", "Relationship", er, 150, 90, kind: .diamond),
            item("er-weak-relationship", "Weak Relationship", er, 160, 100, path { p in
                p.poly([(0.5, 0), (1, 0.5), (0.5, 1), (0, 0.5)]); p.poly([(0.5, 0.13), (0.88, 0.5), (0.5, 0.87), (0.12, 0.5)]) }),
            item("er-attribute", "Attribute", er, 120, 60, kind: .ellipse),
            item("er-multivalued", "Multivalued Attribute", er, 130, 70, path { p in
                p.oval(0.5, 0.5, 0.5, 0.5); p.oval(0.5, 0.5, 0.42, 0.38) }),
            erTable("er-table", "Table", fields: ["id", "name", "email"]),
            erTable("er-table-small", "Table (One Field)", fields: ["id"]),
        ]

        out += ArchitectureCatalog.items

        // MARK: Circuit symbols
        for part in CircuitPart.allCases {
            var it = LibraryItem(id: "circuit-\(part.rawValue)", name: part.title, category: circuits, origin: .circuit, size: part.size)
            it.circuit = part
            it.usesCurrentStyle = false
            out.append(it)
        }
        return out
    }()

    /// Search terms that don't appear in an item's name.
    private static let synonyms: [String: String] = [
        "fc-process": "block step", "fc-terminator": "start end stop oval", "fc-decision": "if branch rhombus", "fc-data": "input output io",
        "fc-database": "storage db", "star-5": "pentagram", "cloud": "weather", "person": "people avatar", "er-entity": "entidad chen", "er-relationship": "relacion rhombus chen", "er-attribute": "atributo chen", "er-table": "tabla database sql crow foot", "actor": "stick figure uml use case",
        "fc-document": "paper file", "arch-door-single": "puerta", "arch-window": "ventana", "arch-stairs": "escalera", "arch-bed-double": "cama", "arch-toilet": "wc inodoro baño", "server": "rack computer", "monitor": "screen display computer",
    ]

    static func matches(_ item: LibraryItem, _ query: String) -> Bool {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        if q.isEmpty { return true }
        let hay = (item.name + " " + item.category + " " + (synonyms[item.id] ?? "") + " " + (item.circuit?.prefix ?? "")).lowercased()
        return q.split(separator: " ").allSatisfy { hay.contains($0) }
    }
}
