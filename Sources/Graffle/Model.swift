import AppKit

// MARK: - Colors

struct RGBA: Codable, Equatable {
    var r: Double, g: Double, b: Double, a: Double

    init(_ r: Double, _ g: Double, _ b: Double, _ a: Double = 1) {
        self.r = r; self.g = g; self.b = b; self.a = a
    }

    init(_ color: NSColor) {
        let c = color.usingColorSpace(.sRGB) ?? NSColor(srgbRed: 0, green: 0, blue: 0, alpha: 1)
        self.init(Double(c.redComponent), Double(c.greenComponent), Double(c.blueComponent), Double(c.alphaComponent))
    }

    var ns: NSColor { NSColor(srgbRed: r, green: g, blue: b, alpha: a) }
    var cg: CGColor { ns.cgColor }
    var luminance: Double { 0.299 * r + 0.587 * g + 0.114 * b }
    var isDark: Bool { luminance < 0.5 }
}

// MARK: - Style components

enum FillKind: String, Codable, CaseIterable {
    case none, solid, linear, radial

    var title: String {
        switch self {
        case .none: return "None"
        case .solid: return "Solid Color"
        case .linear: return "Linear Gradient"
        case .radial: return "Radial Gradient"
        }
    }
}

struct GradientStop: Codable, Equatable {
    var color: RGBA
    /// 0...1 along the gradient.
    var position: Double
}

struct Fill: Codable, Equatable {
    var kind: FillKind = .solid
    /// Used by the solid fill.
    var color = RGBA(0.93, 0.96, 1.0)
    /// Used by gradients. Two or more, in any order; they are sorted by position when drawn.
    var stops: [GradientStop] = [GradientStop(color: RGBA(0.93, 0.96, 1.0), position: 0),
                                 GradientStop(color: RGBA(0.50, 0.68, 1.0), position: 1)]
    /// Linear gradients only: 0 = left to right, 90 = top to bottom.
    var angle: Double = 90

    init() {}

    var sortedStops: [GradientStop] { stops.sorted { $0.position < $1.position } }

    /// The gradient's color at `t` (0...1), interpolating between the neighbouring stops.
    func color(at t: Double) -> RGBA {
        let s = sortedStops
        guard let first = s.first, let last = s.last else { return color }
        if t <= first.position { return first.color }
        if t >= last.position { return last.color }
        for i in 1..<s.count where t <= s[i].position {
            let a = s[i - 1], b = s[i]
            let span = b.position - a.position
            let u = span > 0 ? (t - a.position) / span : 0
            return RGBA(a.color.r + (b.color.r - a.color.r) * u, a.color.g + (b.color.g - a.color.g) * u,
                        a.color.b + (b.color.b - a.color.b) * u, a.color.a + (b.color.a - a.color.a) * u)
        }
        return last.color
    }

    var averageLuminance: Double {
        let s = stops
        return s.isEmpty ? color.luminance : s.map { $0.color.luminance }.reduce(0, +) / Double(s.count)
    }

    // Documents from before multi-stop gradients stored a second color instead of `stops`.
    private enum CodingKeys: String, CodingKey { case kind, color, color2, stops, angle }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        kind = try c.decode(FillKind.self, forKey: .kind)
        color = try c.decode(RGBA.self, forKey: .color)
        angle = try c.decode(Double.self, forKey: .angle)
        if let decoded = try c.decodeIfPresent([GradientStop].self, forKey: .stops) {
            stops = decoded
        } else {
            let second = try c.decodeIfPresent(RGBA.self, forKey: .color2) ?? RGBA(0.50, 0.68, 1.0)
            stops = [GradientStop(color: color, position: 0), GradientStop(color: second, position: 1)]
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(kind, forKey: .kind)
        try c.encode(color, forKey: .color)
        try c.encode(stops, forKey: .stops)
        try c.encode(angle, forKey: .angle)
    }
}

enum DashKind: String, Codable, CaseIterable {
    case solid, dashed, longDash, dotted, dashDot

    var title: String {
        switch self {
        case .solid: return "Solid"
        case .dashed: return "Dashed"
        case .longDash: return "Long Dash"
        case .dotted: return "Dotted"
        case .dashDot: return "Dash-Dot"
        }
    }

    func pattern(width: Double) -> [CGFloat] {
        let u = CGFloat(max(width, 1.5))
        switch self {
        case .solid: return []
        case .dashed: return [4 * u, 3 * u]
        case .longDash: return [9 * u, 4 * u]
        case .dotted: return [0.01, 2.2 * u]
        case .dashDot: return [5 * u, 2.5 * u, 0.01, 2.5 * u]
        }
    }
}

enum CapKind: String, Codable, CaseIterable {
    case butt, round, square

    var title: String { rawValue.capitalized }
    var cg: CGLineCap {
        switch self {
        case .butt: return .butt
        case .round: return .round
        case .square: return .square
        }
    }
}

enum JoinKind: String, Codable, CaseIterable {
    case miter, round, bevel

    var title: String { rawValue.capitalized }
    var cg: CGLineJoin {
        switch self {
        case .miter: return .miter
        case .round: return .round
        case .bevel: return .bevel
        }
    }
}

struct Stroke: Codable, Equatable {
    var visible = true
    var color = RGBA(0.20, 0.30, 0.50)
    var width: Double = 1.5
    var dash: DashKind = .solid
    var cap: CapKind = .butt
    var join: JoinKind = .round
    /// How hand-drawn the line looks, 0...1 (crayon, chalk). Optional so documents saved before themes still open.
    var rough: Double? = nil

    var roughness: Double { rough ?? 0 }
}

/// Extra rendering on top of the plain fill, used by themes.
enum Effect: String, Codable {
    /// Soft light and dark shadows that make the shape look pressed out of the page.
    case neumorphic
    /// A glass-like highlight and bright rim, strong.
    case crystal
    /// Frosted glass: a faint sheen and a light rim.
    case glass
    /// Hand-drawn diagonal strokes inside the shape (marker, chalk).
    case hatch
    /// Soft 3D: a light edge on the top-left and a shaded one on the bottom-right.
    case clay
}

struct Shadow: Codable, Equatable {
    var enabled = false
    var color = RGBA(0, 0, 0, 0.35)
    var blur: Double = 6
    /// Distance from the object, in points.
    var offset: Double = 6
    /// Direction the shadow falls, in degrees: 0 = right, 90 = down, 180 = left, 270 = up.
    var angle: Double = 45

    /// Offset in canvas coordinates (y grows downward).
    var vector: CGSize {
        let r = angle * .pi / 180
        return CGSize(width: cos(r) * offset, height: sin(r) * offset)
    }
}

enum HAlign: String, Codable, CaseIterable { case left, center, right }
enum VAlign: String, Codable, CaseIterable { case top, middle, bottom }

struct TextFormat: Codable, Equatable {
    var font = "System"
    var size: Double = 14
    var bold = false
    var italic = false
    var underline = false
    var hAlign: HAlign = .center
    var vAlign: VAlign = .middle
    /// nil = pick black or white to contrast with the fill.
    var color: RGBA? = nil

    /// "System" (the interface font) followed by every font family installed on this Mac, A to Z.
    /// Hidden system families (their names start with a dot) are left out.
    static let installedFonts: [String] = {
        let families = Set(NSFontManager.shared.availableFontFamilies.filter { !$0.hasPrefix(".") })
        return ["System"] + families.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }()
}

struct Style: Codable, Equatable {
    var fill = Fill()
    var stroke = Stroke()
    var shadow = Shadow()
    var opacity: Double = 1
    var cornerRadius: Double = 0
    var text = TextFormat()
    var effect: Effect? = nil
    /// What a theme was last applied from: the shape's own color, and the fill the theme produced from it
    /// (if the fill still matches, the original color is reused when another theme is applied).
    var themeBase: RGBA? = nil
    var themeFill: Fill? = nil

    static var textBox: Style {
        var s = Style()
        s.fill.kind = .none
        s.stroke.visible = false
        return s
    }

    static var connector: Style {
        var s = Style()
        s.fill.kind = .none
        s.stroke.color = RGBA(0.25, 0.25, 0.30)
        s.text.size = 12
        return s
    }
}

// MARK: - Connector options

enum Route: String, Codable, CaseIterable {
    case straight, curved, orthogonal, rounded

    var title: String {
        switch self {
        case .straight: return "Straight"
        case .curved: return "Curved"
        case .orthogonal: return "Orthogonal"
        case .rounded: return "Orthogonal, Rounded"
        }
    }
}

enum HeadKind: String, Codable, CaseIterable {
    case none, filledArrow, openArrow, hollowTriangle, filledDiamond, hollowDiamond, filledCircle, hollowCircle, bar
    /// Entity-relationship ("crow's foot") ends: many, one or many, zero or many, exactly one, zero or one.
    case crowFoot, crowFootBar, crowFootCircle, doubleBar, circleBar

    var title: String {
        switch self {
        case .none: return "None"
        case .filledArrow: return "Arrow"
        case .openArrow: return "Open Arrow"
        case .hollowTriangle: return "Hollow Triangle"
        case .filledDiamond: return "Filled Diamond"
        case .hollowDiamond: return "Hollow Diamond"
        case .filledCircle: return "Filled Circle"
        case .hollowCircle: return "Hollow Circle"
        case .bar: return "Bar"
        case .crowFoot: return "Many"
        case .crowFootBar: return "One or Many"
        case .crowFootCircle: return "Zero or Many"
        case .doubleBar: return "Exactly One"
        case .circleBar: return "Zero or One"
        }
    }
}

// MARK: - Document

struct Layer: Codable, Identifiable, Equatable {
    var id = UUID()
    var name: String
    var visible = true
    var locked = false
}

enum ShapeKind: String, Codable, CaseIterable {
    case rectangle, rounded, ellipse, diamond, triangle, text
    /// A free-form outline (lines, polylines, curves), typically from an imported SVG.
    case path
}

enum PathOp: String, Codable { case move, line, curve, close }

/// One step of a free-form outline. Points are normalized to the shape's frame
/// (0...1 on both axes), so resizing and rotating the shape reshapes the outline.
/// `move`/`line` carry one point, `curve` carries control1, control2 and the end point, `close` none.
struct PathSegment: Codable, Equatable {
    var op: PathOp
    var points: [CGPoint] = []
}

struct Shape: Codable, Identifiable, Equatable {
    var id = UUID()
    var layer: UUID
    var kind: ShapeKind
    var frame: CGRect
    var style = Style()
    var text = ""
    /// Degrees, clockwise on screen, around the frame's center.
    var rotation: Double = 0
    /// Shapes that share a group id are selected and moved together.
    var group: UUID? = nil
    /// Only for `.path` shapes.
    var outline: [PathSegment]? = nil
    /// A locked shape can still be selected and restyled, but not moved, resized, rotated, deleted or edited.
    var locked = false
    /// What the layers list and the inspector call it; empty means "name it after its text or its kind".
    var name: String? = nil

    init(id: UUID = UUID(), layer: UUID, kind: ShapeKind, frame: CGRect, style: Style = Style(), text: String = "",
         rotation: Double = 0, group: UUID? = nil, outline: [PathSegment]? = nil, locked: Bool = false, name: String? = nil) {
        self.name = name
        self.id = id; self.layer = layer; self.kind = kind; self.frame = frame
        self.style = style; self.text = text; self.rotation = rotation; self.group = group; self.outline = outline
        self.locked = locked
    }

    // Documents saved before rotation/groups existed lack those keys.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        layer = try c.decode(UUID.self, forKey: .layer)
        kind = try c.decode(ShapeKind.self, forKey: .kind)
        frame = try c.decode(CGRect.self, forKey: .frame)
        style = try c.decode(Style.self, forKey: .style)
        text = try c.decode(String.self, forKey: .text)
        name = try c.decodeIfPresent(String.self, forKey: .name)
        rotation = try c.decodeIfPresent(Double.self, forKey: .rotation) ?? 0
        group = try c.decodeIfPresent(UUID.self, forKey: .group)
        outline = try c.decodeIfPresent([PathSegment].self, forKey: .outline)
        locked = try c.decodeIfPresent(Bool.self, forKey: .locked) ?? false
    }
}

struct Connector: Codable, Identifiable, Equatable {
    var id = UUID()
    var layer: UUID
    var from: UUID
    var to: UUID
    var route: Route = .straight
    var startHead: HeadKind = .none
    var endHead: HeadKind = .filledArrow
    var headScale: Double = 1
    var style = Style.connector
    var text = ""
    /// A locked connector can't be deleted, re-routed or relabelled.
    var locked = false

    init(id: UUID = UUID(), layer: UUID, from: UUID, to: UUID, route: Route = .straight, startHead: HeadKind = .none,
         endHead: HeadKind = .filledArrow, headScale: Double = 1, style: Style = .connector, text: String = "",
         locked: Bool = false) {
        self.id = id; self.layer = layer; self.from = from; self.to = to; self.route = route
        self.startHead = startHead; self.endHead = endHead; self.headScale = headScale
        self.style = style; self.text = text; self.locked = locked
    }

    // Documents saved before locking existed lack that key.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        layer = try c.decode(UUID.self, forKey: .layer)
        from = try c.decode(UUID.self, forKey: .from)
        to = try c.decode(UUID.self, forKey: .to)
        route = try c.decode(Route.self, forKey: .route)
        startHead = try c.decode(HeadKind.self, forKey: .startHead)
        endHead = try c.decode(HeadKind.self, forKey: .endHead)
        headScale = try c.decode(Double.self, forKey: .headScale)
        style = try c.decode(Style.self, forKey: .style)
        text = try c.decode(String.self, forKey: .text)
        locked = try c.decodeIfPresent(Bool.self, forKey: .locked) ?? false
    }
}

/// The whole document. Layers are stored bottom-to-top; inside a layer, shapes keep their array order.
struct Drawing: Codable, Equatable {
    var layers: [Layer] = [Layer(name: "Layer 1")]
    var shapes: [Shape] = []
    var connectors: [Connector] = []
    /// The theme this drawing uses, embedded so the file looks the same on a Mac that doesn't have the theme installed.
    /// It also styles new objects. Nil = the plain default look.
    var theme: ThemeDefinition? = nil
    /// What the diagram was made from, so code can be generated from it later (nil for diagrams drawn by hand).
    var source: DiagramSource? = nil

    func layer(_ id: UUID) -> Layer? { layers.first { $0.id == id } }

    var contentBounds: CGRect? {
        let visible = Set(layers.filter(\.visible).map(\.id))
        return shapes.filter { visible.contains($0.layer) }.map(\.worldBounds)
            .reduce(nil) { acc, f in acc.map { $0.union(f) } ?? f }
    }
}

// MARK: - Shape geometry

enum Side { case left, right, top, bottom }

extension Shape {
    var center: CGPoint { CGPoint(x: frame.midX, y: frame.midY) }

    var radians: CGFloat { CGFloat(rotation) * .pi / 180 }

    private func rotated(_ p: CGPoint, by a: CGFloat) -> CGPoint {
        guard a != 0 else { return p }
        let c = center, dx = p.x - c.x, dy = p.y - c.y
        return CGPoint(x: c.x + dx * cos(a) - dy * sin(a), y: c.y + dx * sin(a) + dy * cos(a))
    }

    /// A point in the shape's own (unrotated) frame -> canvas coordinates.
    func toWorld(_ p: CGPoint) -> CGPoint { rotated(p, by: radians) }
    /// Canvas coordinates -> the shape's own (unrotated) frame.
    func toLocal(_ p: CGPoint) -> CGPoint { rotated(p, by: -radians) }

    /// Axis-aligned bounds of the rotated frame.
    var worldBounds: CGRect {
        guard rotation != 0 else { return frame }
        let pts = [CGPoint(x: frame.minX, y: frame.minY), CGPoint(x: frame.maxX, y: frame.minY),
                   CGPoint(x: frame.maxX, y: frame.maxY), CGPoint(x: frame.minX, y: frame.maxY)].map(toWorld)
        let xs = pts.map(\.x), ys = pts.map(\.y)
        return CGRect(x: xs.min()!, y: ys.min()!, width: xs.max()! - xs.min()!, height: ys.max()! - ys.min()!)
    }

    /// Transform that turns the unrotated path into its on-canvas position.
    var rotationTransform: CGAffineTransform {
        CGAffineTransform(translationX: center.x, y: center.y).rotated(by: radians).translatedBy(x: -center.x, y: -center.y)
    }

    var polygon: [CGPoint]? {
        let f = frame
        switch kind {
        case .diamond:
            return [CGPoint(x: f.midX, y: f.minY), CGPoint(x: f.maxX, y: f.midY),
                    CGPoint(x: f.midX, y: f.maxY), CGPoint(x: f.minX, y: f.midY)]
        case .triangle:
            return [CGPoint(x: f.midX, y: f.minY), CGPoint(x: f.maxX, y: f.maxY), CGPoint(x: f.minX, y: f.maxY)]
        default:
            return nil
        }
    }

    func path() -> CGPath {
        switch kind {
        case .text:
            return CGPath(rect: frame, transform: nil)
        case .rectangle, .rounded:
            let r = min(CGFloat(style.cornerRadius), frame.width / 2, frame.height / 2)
            return r > 0 ? CGPath(roundedRect: frame, cornerWidth: r, cornerHeight: r, transform: nil)
                         : CGPath(rect: frame, transform: nil)
        case .ellipse:
            return CGPath(ellipseIn: frame, transform: nil)
        case .diamond, .triangle:
            let p = CGMutablePath()
            p.addLines(between: polygon ?? [])
            p.closeSubpath()
            return p
        case .path:
            let p = CGMutablePath()
            let f = frame
            func pt(_ q: CGPoint) -> CGPoint { CGPoint(x: f.minX + q.x * f.width, y: f.minY + q.y * f.height) }
            for seg in outline ?? [] {
                switch (seg.op, seg.points.count) {
                case (.move, 1...): p.move(to: pt(seg.points[0]))
                case (.line, 1...): p.addLine(to: pt(seg.points[0]))
                case (.curve, 3...): p.addCurve(to: pt(seg.points[2]), control1: pt(seg.points[0]), control2: pt(seg.points[1]))
                case (.close, _): p.closeSubpath()
                default: break
                }
            }
            return p
        }
    }

    /// The outline as it appears on the canvas (rotated).
    func worldPath() -> CGPath {
        var t = rotationTransform
        return path().copy(using: &t) ?? path()
    }

    func sideMidpoint(_ side: Side) -> CGPoint { toWorld(localSideMidpoint(side)) }

    private func localSideMidpoint(_ side: Side) -> CGPoint {
        // A triangle's slanted edges sit a quarter of the width inside the bounding box at mid-height.
        let inset: CGFloat = kind == .triangle ? frame.width / 4 : 0
        switch side {
        case .left: return CGPoint(x: frame.minX + inset, y: frame.midY)
        case .right: return CGPoint(x: frame.maxX - inset, y: frame.midY)
        case .top: return CGPoint(x: frame.midX, y: frame.minY)
        case .bottom: return CGPoint(x: frame.midX, y: frame.maxY)
        }
    }

    /// Point where the ray from the shape's center toward `target` leaves the outline.
    func boundaryPoint(toward target: CGPoint) -> CGPoint {
        toWorld(localBoundaryPoint(toward: toLocal(target)))
    }

    private func localBoundaryPoint(toward target: CGPoint) -> CGPoint {
        let c = center
        let dx = target.x - c.x, dy = target.y - c.y
        if dx == 0 && dy == 0 { return c }
        let hw = max(frame.width / 2, 0.001), hh = max(frame.height / 2, 0.001)

        switch kind {
        case .ellipse:
            let t = 1 / sqrt((dx * dx) / (hw * hw) + (dy * dy) / (hh * hh))
            return CGPoint(x: c.x + dx * t, y: c.y + dy * t)
        case .diamond, .triangle:
            guard let pts = polygon else { return c }
            var best = CGFloat.infinity
            for i in pts.indices {
                let a = pts[i], b = pts[(i + 1) % pts.count]
                if let t = Shape.rayHit(origin: c, dx: dx, dy: dy, a, b), t < best { best = t }
            }
            return best.isFinite ? CGPoint(x: c.x + dx * best, y: c.y + dy * best) : c
        default:
            let tx = dx == 0 ? CGFloat.infinity : hw / abs(dx)
            let ty = dy == 0 ? CGFloat.infinity : hh / abs(dy)
            let t = min(tx, ty)
            return CGPoint(x: c.x + dx * t, y: c.y + dy * t)
        }
    }

    private static func rayHit(origin o: CGPoint, dx: CGFloat, dy: CGFloat, _ a: CGPoint, _ b: CGPoint) -> CGFloat? {
        let ex = b.x - a.x, ey = b.y - a.y
        let denom = dx * ey - dy * ex
        if abs(denom) < 1e-9 { return nil }
        let wx = a.x - o.x, wy = a.y - o.y
        let t = (wx * ey - wy * ex) / denom
        let u = (wx * dy - wy * dx) / denom
        return (t > 0 && u >= -1e-9 && u <= 1 + 1e-9) ? t : nil
    }
}

// MARK: - Connector routing

struct ConnectorGeometry {
    var path: CGPath
    var startPoint: CGPoint
    var startAngle: CGFloat   // direction pointing out of the line at the start
    var endPoint: CGPoint
    var endAngle: CGFloat     // direction pointing out of the line at the end
    var labelPoint: CGPoint

    static func make(_ c: Connector, _ a: Shape, _ b: Shape) -> ConnectorGeometry {
        switch c.route {
        case .straight: return straight(a, b)
        case .curved: return curved(a, b)
        case .orthogonal: return orthogonal(a, b, rounded: false)
        case .rounded: return orthogonal(a, b, rounded: true)
        }
    }

    private static func angle(from p: CGPoint, to q: CGPoint) -> CGFloat { atan2(q.y - p.y, q.x - p.x) }

    private static func straight(_ a: Shape, _ b: Shape) -> ConnectorGeometry {
        let p1 = a.boundaryPoint(toward: b.center)
        let p2 = b.boundaryPoint(toward: a.center)
        let path = CGMutablePath()
        path.move(to: p1)
        path.addLine(to: p2)
        return ConnectorGeometry(path: path, startPoint: p1, startAngle: angle(from: p2, to: p1),
                                 endPoint: p2, endAngle: angle(from: p1, to: p2),
                                 labelPoint: CGPoint(x: (p1.x + p2.x) / 2, y: (p1.y + p2.y) / 2))
    }

    /// The side of `s` whose outward normal (after rotation) points most directly at `target`.
    private static func facingSide(of s: Shape, toward target: CGPoint) -> (point: CGPoint, normal: CGPoint) {
        let dx = target.x - s.center.x, dy = target.y - s.center.y
        let len = max(hypot(dx, dy), 0.0001)
        let dir = CGPoint(x: dx / len, y: dy / len)
        // Horizontal sides are listed first so an exact tie keeps the old "prefer left/right" behaviour.
        let sides: [(Side, CGPoint)] = [(.right, CGPoint(x: 1, y: 0)), (.left, CGPoint(x: -1, y: 0)),
                                        (.bottom, CGPoint(x: 0, y: 1)), (.top, CGPoint(x: 0, y: -1))]
        let r = s.radians
        var best = (side: Side.right, normal: CGPoint(x: 1, y: 0), score: -CGFloat.infinity)
        for (side, n) in sides {
            let nw = CGPoint(x: n.x * cos(r) - n.y * sin(r), y: n.x * sin(r) + n.y * cos(r))
            let score = nw.x * dir.x + nw.y * dir.y
            if score > best.score + 1e-9 { best = (side, nw, score) }
        }
        return (s.sideMidpoint(best.side), best.normal)
    }

    /// Anchor points and outward normals on both shapes; `horizontal` is the dominant axis leaving `a`.
    private static func anchors(_ a: Shape, _ b: Shape)
        -> (p1: CGPoint, p2: CGPoint, n1: CGPoint, n2: CGPoint, horizontal: Bool) {
        let from = facingSide(of: a, toward: b.center)
        let to = facingSide(of: b, toward: a.center)
        return (from.point, to.point, from.normal, to.normal, abs(from.normal.x) >= abs(from.normal.y))
    }

    private static func curved(_ a: Shape, _ b: Shape) -> ConnectorGeometry {
        let (p1, p2, n1, n2, _) = anchors(a, b)
        // Leave and enter each shape along its outward normal.
        let off = max(40, hypot(p2.x - p1.x, p2.y - p1.y) / 2)
        let c1 = CGPoint(x: p1.x + n1.x * off, y: p1.y + n1.y * off)
        let c2 = CGPoint(x: p2.x + n2.x * off, y: p2.y + n2.y * off)
        let path = CGMutablePath()
        path.move(to: p1)
        path.addCurve(to: p2, control1: c1, control2: c2)
        let mid = CGPoint(x: (p1.x + 3 * c1.x + 3 * c2.x + p2.x) / 8, y: (p1.y + 3 * c1.y + 3 * c2.y + p2.y) / 8)
        return ConnectorGeometry(path: path, startPoint: p1, startAngle: angle(from: c1, to: p1),
                                 endPoint: p2, endAngle: angle(from: c2, to: p2), labelPoint: mid)
    }

    private static func orthogonal(_ a: Shape, _ b: Shape, rounded: Bool) -> ConnectorGeometry {
        let (p1, p2, _, _, horizontal) = anchors(a, b)
        var pts = [p1]
        if horizontal {
            let mx = (p1.x + p2.x) / 2
            pts += [CGPoint(x: mx, y: p1.y), CGPoint(x: mx, y: p2.y)]
        } else {
            let my = (p1.y + p2.y) / 2
            pts += [CGPoint(x: p1.x, y: my), CGPoint(x: p2.x, y: my)]
        }
        pts.append(p2)

        let path = CGMutablePath()
        if rounded {
            path.move(to: pts[0])
            for i in 1..<(pts.count - 1) {
                let inLen = hypot(pts[i].x - pts[i - 1].x, pts[i].y - pts[i - 1].y)
                let outLen = hypot(pts[i + 1].x - pts[i].x, pts[i + 1].y - pts[i].y)
                let r = min(14, inLen / 2, outLen / 2)
                path.addArc(tangent1End: pts[i], tangent2End: pts[i + 1], radius: max(r, 0))
            }
            path.addLine(to: pts[pts.count - 1])
        } else {
            path.addLines(between: pts)
        }

        func far(_ from: CGPoint, _ others: [CGPoint]) -> CGPoint? { others.first { hypot($0.x - from.x, $0.y - from.y) > 0.5 } }
        let startRef = far(p1, Array(pts.dropFirst())) ?? p2
        let endRef = far(p2, Array(pts.dropLast().reversed())) ?? p1
        let label = CGPoint(x: (pts[1].x + pts[2].x) / 2, y: (pts[1].y + pts[2].y) / 2)
        return ConnectorGeometry(path: path, startPoint: p1, startAngle: angle(from: startRef, to: p1),
                                 endPoint: p2, endAngle: angle(from: endRef, to: p2), labelPoint: label)
    }
}

// MARK: - Names shown in lists

extension ShapeKind {
    var title: String {
        switch self {
        case .rectangle: return "Rectangle"
        case .rounded: return "Rounded rectangle"
        case .ellipse: return "Ellipse"
        case .diamond: return "Diamond"
        case .triangle: return "Triangle"
        case .text: return "Text"
        case .path: return "Path"
        }
    }
}

extension Shape {
    /// The name in the layers list: the given name, else the first line of its text, else its kind.
    var displayName: String {
        if let n = name?.trimmingCharacters(in: .whitespacesAndNewlines), !n.isEmpty { return n }
        let line = text.split(whereSeparator: \.isNewline).first.map { $0.trimmingCharacters(in: .whitespaces) } ?? ""
        return line.isEmpty ? kind.title : line
    }
}

extension Connector {
    var displayName: String { text.trimmingCharacters(in: .whitespaces).isEmpty ? "Connector" : text.trimmingCharacters(in: .whitespaces) }
}
