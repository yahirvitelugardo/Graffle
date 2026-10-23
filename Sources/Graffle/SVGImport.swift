#if canImport(AppKit)
import AppKit
#else
import UIKit
#endif

/// Reads simple SVG files into editable shapes.
///
/// Supported: rect (rounded), circle, ellipse, line, polyline, polygon, path (M L H V C S Q T A Z, absolute and relative),
/// text/tspan; nested groups with transforms; fill/stroke from attributes or `style=""`; linear and radial gradients with
/// any number of stops; dash patterns; opacity; drop-shadow filters; viewBox. Top-level groups with a `data-name`
/// (as written by this app's SVG export) become layers.
/// Not supported (counted and reported): images, `<use>`, patterns, clip paths, masks, CSS `<style>` blocks, filters other
/// than a drop shadow.
enum SVGImport {
    struct Result {
        var layers: [Layer]
        var shapes: [Shape]
        /// Element names that were left out, with how many of each.
        var skipped: [String: Int]

        var bounds: CGRect? {
            shapes.map(\.worldBounds).reduce(nil) { acc, r in acc.map { $0.union(r) } ?? r }
        }

        var skippedSummary: String? {
            guard !skipped.isEmpty else { return nil }
            return skipped.sorted { $0.key < $1.key }.map { "\($0.value) × <\($0.key)>" }.joined(separator: ", ")
        }

        /// Moves everything so its top-left corner lands on `origin`.
        func placed(at origin: CGPoint) -> Result {
            guard let b = bounds else { return self }
            return translated(dx: origin.x - b.minX, dy: origin.y - b.minY)
        }

        func translated(dx: CGFloat, dy: CGFloat) -> Result {
            var r = self
            for i in r.shapes.indices {
                r.shapes[i].frame.origin.x += dx
                r.shapes[i].frame.origin.y += dy
            }
            return r
        }

        /// Shrinks everything uniformly (about the origin) if it is bigger than `size`.
        func fitted(into size: CGSize) -> Result {
            guard let b = bounds, b.width > 0, b.height > 0 else { return self }
            let f = min(1, size.width / (b.maxX), size.height / (b.maxY))
            guard f < 1 else { return self }
            var r = self
            for i in r.shapes.indices {
                var s = r.shapes[i]
                s.frame = CGRect(x: s.frame.minX * f, y: s.frame.minY * f, width: max(s.frame.width * f, 1), height: max(s.frame.height * f, 1))
                s.style.stroke.width *= Double(f)
                s.style.text.size = max(s.style.text.size * Double(f), 4)
                s.style.cornerRadius *= Double(f)
                s.style.shadow.offset *= Double(f)
                s.style.shadow.blur *= Double(f)
                r.shapes[i] = s
            }
            return r
        }
    }

    enum ImportError: LocalizedError {
        case notSVG
        case unreadable(String)

        var errorDescription: String? {
            switch self {
            case .notSVG: return "This file isn't an SVG image."
            case .unreadable(let why): return "The SVG couldn't be read: \(why)"
            }
        }
    }

    static func parse(_ data: Data, name: String) throws -> Result {
        let doc: XMLDocument
        do { doc = try XMLDocument(data: data, options: [.nodeLoadExternalEntitiesNever]) }
        catch { throw ImportError.unreadable(error.localizedDescription) }
        guard let root = doc.rootElement(), root.localName == "svg" else { throw ImportError.notSVG }
        let parser = Parser(root: root, fallbackLayerName: name)
        return parser.run()
    }

    // MARK: Number, color and transform parsing

    fileprivate static func number(_ s: String?) -> CGFloat? {
        guard let s = s?.trimmingCharacters(in: .whitespaces), !s.isEmpty else { return nil }
        let allowed = Set("0123456789+-.eE")
        let prefix = String(s.prefix { allowed.contains($0) })
        return Double(prefix).map { CGFloat($0) }
    }

    fileprivate static func numbers(_ s: String?) -> [CGFloat] {
        guard let s else { return [] }
        var sc = PathScanner(s)
        var out: [CGFloat] = []
        while let n = sc.number() { out.append(CGFloat(n)) }
        return out
    }

    private static let colorNames: [String: (Double, Double, Double)] = [
        "black": (0, 0, 0), "white": (1, 1, 1), "red": (1, 0, 0), "green": (0, 0.502, 0), "blue": (0, 0, 1),
        "yellow": (1, 1, 0), "orange": (1, 0.647, 0), "purple": (0.502, 0, 0.502), "gray": (0.502, 0.502, 0.502),
        "grey": (0.502, 0.502, 0.502), "silver": (0.753, 0.753, 0.753), "cyan": (0, 1, 1), "aqua": (0, 1, 1),
        "magenta": (1, 0, 1), "fuchsia": (1, 0, 1), "pink": (1, 0.753, 0.796), "brown": (0.647, 0.165, 0.165),
        "navy": (0, 0, 0.502), "teal": (0, 0.502, 0.502), "lime": (0, 1, 0), "maroon": (0.502, 0, 0),
        "olive": (0.502, 0.502, 0), "gold": (1, 0.843, 0), "coral": (1, 0.498, 0.314), "crimson": (0.863, 0.078, 0.235),
        "indigo": (0.294, 0, 0.510), "violet": (0.933, 0.510, 0.933), "tomato": (1, 0.388, 0.278),
        "lightgray": (0.827, 0.827, 0.827), "lightgrey": (0.827, 0.827, 0.827), "darkgray": (0.663, 0.663, 0.663),
        "lightblue": (0.678, 0.847, 0.902), "skyblue": (0.529, 0.808, 0.922), "steelblue": (0.275, 0.510, 0.706),
    ]

    fileprivate static func color(_ spec: String) -> RGBA? {
        let s = spec.trimmingCharacters(in: .whitespaces).lowercased()
        if s.hasPrefix("#") {
            var h = String(s.dropFirst())
            if h.count == 3 || h.count == 4 { h = h.map { "\($0)\($0)" }.joined() }
            guard h.count == 6 || h.count == 8, let v = UInt64(h, radix: 16) else { return nil }
            if h.count == 6 {
                return RGBA(Double((v >> 16) & 255) / 255, Double((v >> 8) & 255) / 255, Double(v & 255) / 255)
            }
            return RGBA(Double((v >> 24) & 255) / 255, Double((v >> 16) & 255) / 255, Double((v >> 8) & 255) / 255, Double(v & 255) / 255)
        }
        if s.hasPrefix("rgb"), let open = s.firstIndex(of: "("), let close = s.lastIndex(of: ")") {
            let parts = s[s.index(after: open)..<close].split(whereSeparator: { $0 == "," || $0 == " " || $0 == "/" })
            func channel(_ p: Substring) -> Double? {
                if p.hasSuffix("%") { return Double(p.dropLast()).map { $0 / 100 } }
                return Double(p).map { $0 / 255 }
            }
            guard parts.count >= 3, let r = channel(parts[0]), let g = channel(parts[1]), let b = channel(parts[2]) else { return nil }
            var a = 1.0
            if parts.count >= 4 { a = parts[3].hasSuffix("%") ? (Double(parts[3].dropLast()) ?? 100) / 100 : (Double(parts[3]) ?? 1) }
            return RGBA(min(max(r, 0), 1), min(max(g, 0), 1), min(max(b, 0), 1), a)
        }
        if s == "transparent" { return RGBA(0, 0, 0, 0) }
        if let c = colorNames[s] { return RGBA(c.0, c.1, c.2) }
        return nil
    }

    fileprivate static func transform(_ spec: String?) -> CGAffineTransform {
        guard let spec else { return .identity }
        var m = CGAffineTransform.identity
        var rest = Substring(spec)
        while let open = rest.firstIndex(of: "("), let close = rest[open...].firstIndex(of: ")") {
            let name = rest[..<open].trimmingCharacters(in: CharacterSet(charactersIn: " ,\n\t\r"))
            let a = numbers(String(rest[rest.index(after: open)..<close]))
            var t = CGAffineTransform.identity
            switch name {
            case "matrix" where a.count >= 6: t = CGAffineTransform(a: a[0], b: a[1], c: a[2], d: a[3], tx: a[4], ty: a[5])
            case "translate" where a.count >= 1: t = CGAffineTransform(translationX: a[0], y: a.count > 1 ? a[1] : 0)
            case "scale" where a.count >= 1: t = CGAffineTransform(scaleX: a[0], y: a.count > 1 ? a[1] : a[0])
            case "rotate" where a.count >= 1:
                let r = a[0] * .pi / 180
                t = CGAffineTransform(rotationAngle: r)
                if a.count >= 3 {
                    t = CGAffineTransform(translationX: -a[1], y: -a[2]).concatenating(t).concatenating(CGAffineTransform(translationX: a[1], y: a[2]))
                }
            case "skewX" where a.count >= 1: t = CGAffineTransform(a: 1, b: 0, c: tan(a[0] * .pi / 180), d: 1, tx: 0, ty: 0)
            case "skewY" where a.count >= 1: t = CGAffineTransform(a: 1, b: tan(a[0] * .pi / 180), c: 0, d: 1, tx: 0, ty: 0)
            default: break
            }
            // "A B" means B is applied first, then A.
            m = t.concatenating(m)
            rest = rest[rest.index(after: close)...]
        }
        return m
    }

    // MARK: Path data

    /// Walks an SVG number list or path string.
    struct PathScanner {
        private let s: [Character]
        private(set) var i = 0
        init(_ string: String) { s = Array(string) }

        mutating func skipSeparators() {
            while i < s.count, s[i] == " " || s[i] == "," || s[i] == "\n" || s[i] == "\t" || s[i] == "\r" { i += 1 }
        }

        mutating func command() -> Character? {
            skipSeparators()
            guard i < s.count, s[i].isLetter else { return nil }
            defer { i += 1 }
            return s[i]
        }

        var atEnd: Bool { mutating get { skipSeparators(); return i >= s.count } }
        var nextIsNumber: Bool {
            mutating get {
                skipSeparators()
                guard i < s.count else { return false }
                return s[i].isNumber || s[i] == "-" || s[i] == "+" || s[i] == "."
            }
        }

        mutating func number() -> Double? {
            skipSeparators()
            let start = i
            var j = i
            if j < s.count, s[j] == "-" || s[j] == "+" { j += 1 }
            var digits = false
            while j < s.count, s[j].isNumber { j += 1; digits = true }
            if j < s.count, s[j] == "." {
                j += 1
                while j < s.count, s[j].isNumber { j += 1; digits = true }
            }
            guard digits else { return nil }
            if j < s.count, s[j] == "e" || s[j] == "E" {
                var k = j + 1
                if k < s.count, s[k] == "-" || s[k] == "+" { k += 1 }
                if k < s.count, s[k].isNumber {
                    while k < s.count, s[k].isNumber { k += 1 }
                    j = k
                }
            }
            i = j
            return Double(String(s[start..<j]))
        }

        /// Arc flags are single characters and may be written without separators ("a1 1 0 01.5.5").
        mutating func flag() -> Bool? {
            skipSeparators()
            guard i < s.count, s[i] == "0" || s[i] == "1" else { return nil }
            defer { i += 1 }
            return s[i] == "1"
        }
    }

    /// Converts an SVG arc to cubic Béziers (SVG 1.1 implementation notes, F.6).
    static func arc(from p0: CGPoint, rx rxIn: Double, ry ryIn: Double, rotation: Double, large: Bool, sweep: Bool,
                    to p1: CGPoint) -> [(CGPoint, CGPoint, CGPoint)] {
        var rx = abs(rxIn), ry = abs(ryIn)
        if rx == 0 || ry == 0 || (p0.x == p1.x && p0.y == p1.y) { return [(p0, p1, p1)] }
        let phi = rotation * .pi / 180
        let cosP = cos(phi), sinP = sin(phi)
        let dx = Double(p0.x - p1.x) / 2, dy = Double(p0.y - p1.y) / 2
        let x1p = cosP * dx + sinP * dy, y1p = -sinP * dx + cosP * dy

        let lambda = (x1p * x1p) / (rx * rx) + (y1p * y1p) / (ry * ry)
        if lambda > 1 { rx *= sqrt(lambda); ry *= sqrt(lambda) }

        let num = rx * rx * ry * ry - rx * rx * y1p * y1p - ry * ry * x1p * x1p
        let den = rx * rx * y1p * y1p + ry * ry * x1p * x1p
        let coef = (large == sweep ? -1.0 : 1.0) * sqrt(max(0, num / den))
        let cxp = coef * rx * y1p / ry, cyp = -coef * ry * x1p / rx
        let cx = cosP * cxp - sinP * cyp + Double(p0.x + p1.x) / 2
        let cy = sinP * cxp + cosP * cyp + Double(p0.y + p1.y) / 2

        func angle(_ ux: Double, _ uy: Double, _ vx: Double, _ vy: Double) -> Double { atan2(ux * vy - uy * vx, ux * vx + uy * vy) }
        let theta1 = angle(1, 0, (x1p - cxp) / rx, (y1p - cyp) / ry)
        var delta = angle((x1p - cxp) / rx, (y1p - cyp) / ry, (-x1p - cxp) / rx, (-y1p - cyp) / ry)
        if !sweep && delta > 0 { delta -= 2 * .pi }
        if sweep && delta < 0 { delta += 2 * .pi }

        let n = max(1, Int(ceil(abs(delta) / (.pi / 2) - 1e-9)))
        let step = delta / Double(n)
        let t = 4.0 / 3.0 * tan(step / 4)
        func map(_ x: Double, _ y: Double) -> CGPoint {
            CGPoint(x: cx + cosP * rx * x - sinP * ry * y, y: cy + sinP * rx * x + cosP * ry * y)
        }
        var out: [(CGPoint, CGPoint, CGPoint)] = []
        for k in 0..<n {
            let a1 = theta1 + Double(k) * step, a2 = a1 + step
            let c1 = map(cos(a1) - t * sin(a1), sin(a1) + t * cos(a1))
            let c2 = map(cos(a2) + t * sin(a2), sin(a2) - t * cos(a2))
            let e = k == n - 1 ? p1 : map(cos(a2), sin(a2))
            out.append((c1, c2, e))
        }
        return out
    }

    /// Parses SVG path data into a CGPath (quadratic curves are raised to cubics).
    static func path(_ d: String) -> CGPath {
        let path = CGMutablePath()
        var sc = PathScanner(d)
        var cur = CGPoint.zero, start = CGPoint.zero
        var lastCubic: CGPoint?, lastQuad: CGPoint?
        var cmd: Character = "M"

        func cubic(_ c1: CGPoint, _ c2: CGPoint, _ e: CGPoint) {
            path.addCurve(to: e, control1: c1, control2: c2)
            lastCubic = c2; lastQuad = nil; cur = e
        }

        while true {
            if let c = sc.command() { cmd = c }
            else if !sc.nextIsNumber { break }
            else if cmd == "M" { cmd = "L" } else if cmd == "m" { cmd = "l" }   // extra pairs after a moveto are linetos

            let rel = cmd.isLowercase
            let ox = rel ? cur.x : 0, oy = rel ? cur.y : 0
            func pt() -> CGPoint? {
                guard let x = sc.number(), let y = sc.number() else { return nil }
                return CGPoint(x: CGFloat(x) + ox, y: CGFloat(y) + oy)
            }

            switch Character(cmd.uppercased()) {
            case "M":
                guard let p = pt() else { return path }
                path.move(to: p); cur = p; start = p; lastCubic = nil; lastQuad = nil
            case "L":
                guard let p = pt() else { return path }
                path.addLine(to: p); cur = p; lastCubic = nil; lastQuad = nil
            case "H":
                guard let x = sc.number() else { return path }
                cur = CGPoint(x: CGFloat(x) + ox, y: cur.y); path.addLine(to: cur); lastCubic = nil; lastQuad = nil
            case "V":
                guard let y = sc.number() else { return path }
                cur = CGPoint(x: cur.x, y: CGFloat(y) + oy); path.addLine(to: cur); lastCubic = nil; lastQuad = nil
            case "C":
                guard let c1 = pt(), let c2 = pt(), let e = pt() else { return path }
                cubic(c1, c2, e)
            case "S":
                guard let c2 = pt(), let e = pt() else { return path }
                let c1 = lastCubic.map { CGPoint(x: 2 * cur.x - $0.x, y: 2 * cur.y - $0.y) } ?? cur
                cubic(c1, c2, e)
            case "Q":
                guard let q = pt(), let e = pt() else { return path }
                let c1 = CGPoint(x: cur.x + 2 * (q.x - cur.x) / 3, y: cur.y + 2 * (q.y - cur.y) / 3)
                let c2 = CGPoint(x: e.x + 2 * (q.x - e.x) / 3, y: e.y + 2 * (q.y - e.y) / 3)
                cubic(c1, c2, e)
                lastQuad = q; lastCubic = nil
            case "T":
                guard let e = pt() else { return path }
                let q = lastQuad.map { CGPoint(x: 2 * cur.x - $0.x, y: 2 * cur.y - $0.y) } ?? cur
                let c1 = CGPoint(x: cur.x + 2 * (q.x - cur.x) / 3, y: cur.y + 2 * (q.y - cur.y) / 3)
                let c2 = CGPoint(x: e.x + 2 * (q.x - e.x) / 3, y: e.y + 2 * (q.y - e.y) / 3)
                cubic(c1, c2, e)
                lastQuad = q; lastCubic = nil
            case "A":
                guard let rx = sc.number(), let ry = sc.number(), let rot = sc.number(),
                      let large = sc.flag(), let sweep = sc.flag(), let e = pt() else { return path }
                for (c1, c2, end) in arc(from: cur, rx: rx, ry: ry, rotation: rot, large: large, sweep: sweep, to: e) {
                    path.addCurve(to: end, control1: c1, control2: c2)
                }
                cur = e; lastCubic = nil; lastQuad = nil
            case "Z":
                path.closeSubpath(); cur = start; lastCubic = nil; lastQuad = nil
            default:
                return path
            }
        }
        return path
    }

    /// A CGPath as normalized outline segments, plus the frame they are normalized to.
    fileprivate static func outline(from path: CGPath) -> (frame: CGRect, segments: [PathSegment])? {
        Outline.normalize(path)
    }

    // MARK: Parser

    private enum Paint {
        case none
        case solid(RGBA)
        case gradient(Fill)
    }

    private struct Context {
        var matrix = CGAffineTransform.identity
        var props: [String: String] = [:]
        var opacity = 1.0
        var shadow: Shadow?
        var layer: Int = 0
    }

    private static let inherited: Set<String> = [
        "fill", "fill-opacity", "stroke", "stroke-width", "stroke-opacity", "stroke-dasharray", "stroke-linecap",
        "stroke-linejoin", "font-size", "font-family", "font-weight", "font-style", "text-anchor", "text-decoration", "color",
    ]

    private static let ignoredQuietly: Set<String> = [
        "defs", "title", "desc", "metadata", "linearGradient", "radialGradient", "filter", "stop", "namedview",
    ]

    private final class Parser {
        let root: XMLElement
        var layers: [Layer] = []
        var shapes: [Shape] = []
        var skipped: [String: Int] = [:]
        var byID: [String: XMLElement] = [:]
        let fallbackLayerName: String
        var baseLayer: Int?

        init(root: XMLElement, fallbackLayerName: String) {
            self.root = root
            self.fallbackLayerName = fallbackLayerName
        }

        // MARK: Driver

        func run() -> Result {
            index(root)

            var ctx = Context()
            ctx.matrix = viewBoxTransform()
            ctx.props = [:]
            let page = pageRect()
            for child in elements(of: root) {
                if let tag = child.localName, SVGImport.ignoredQuietly.contains(tag) { continue }
                if isPageBackground(child, page) { continue }
                var c = ctx
                if child.localName == "g", let name = child.attribute(forName: "data-name")?.stringValue {
                    layers.append(Layer(name: name))
                    c.layer = layers.count - 1
                } else {
                    c.layer = base()
                }
                walk(child, c)
            }
            if layers.isEmpty { layers = [Layer(name: fallbackLayerName)] }
            for i in shapes.indices where shapes[i].layer == UUID(uuid: UUID_NULL) { shapes[i].layer = layers[0].id }
            return Result(layers: layers, shapes: shapes, skipped: skipped)
        }

        /// The drawing area in the SVG's own units (viewBox, else width/height).
        func pageRect() -> CGRect? {
            let vb = SVGImport.numbers(root.attribute(forName: "viewBox")?.stringValue)
            if vb.count == 4 { return CGRect(x: vb[0], y: vb[1], width: vb[2], height: vb[3]) }
            if let w = SVGImport.number(root.attribute(forName: "width")?.stringValue),
               let h = SVGImport.number(root.attribute(forName: "height")?.stringValue) { return CGRect(x: 0, y: 0, width: w, height: h) }
            return nil
        }

        /// A white, borderless rectangle covering the whole page is a background, not a shape
        /// (this app's SVG export writes one so the file matches its PNG and PDF).
        func isPageBackground(_ e: XMLElement, _ page: CGRect?) -> Bool {
            guard e.localName == "rect", let page,
                  let x = SVGImport.number(attr(e, "x")), let y = SVGImport.number(attr(e, "y")),
                  let w = SVGImport.number(attr(e, "width")), let h = SVGImport.number(attr(e, "height")),
                  abs(x - page.minX) < 0.5, abs(y - page.minY) < 0.5, abs(w - page.width) < 0.5, abs(h - page.height) < 0.5
            else { return false }
            let d = declared(e)
            let fill = (d["fill"] ?? "black").lowercased()
            let white = ["#fff", "#ffffff", "white"].contains(fill)
            return white && (d["stroke"] ?? "none") == "none"
        }

        func base() -> Int {
            if let b = baseLayer { return b }
            layers.append(Layer(name: fallbackLayerName))
            baseLayer = layers.count - 1
            return layers.count - 1
        }

        func index(_ e: XMLElement) {
            if let id = e.attribute(forName: "id")?.stringValue { byID[id] = e }
            for c in elements(of: e) { index(c) }
        }

        func elements(of e: XMLElement) -> [XMLElement] { (e.children ?? []).compactMap { $0 as? XMLElement } }

        /// `viewBox` plus width/height: a uniform scale and a shift to the box's origin.
        func viewBoxTransform() -> CGAffineTransform {
            let vb = SVGImport.numbers(root.attribute(forName: "viewBox")?.stringValue)
            guard vb.count == 4, vb[2] > 0, vb[3] > 0 else { return .identity }
            var t = CGAffineTransform(translationX: -vb[0], y: -vb[1])
            if let w = SVGImport.number(root.attribute(forName: "width")?.stringValue), w > 0,
               let h = SVGImport.number(root.attribute(forName: "height")?.stringValue), h > 0 {
                let s = min(w / vb[2], h / vb[3])
                t = t.concatenating(CGAffineTransform(scaleX: s, y: s))
            }
            return t
        }

        // MARK: Walking

        func attr(_ e: XMLElement, _ name: String) -> String? { e.attribute(forName: name)?.stringValue }

        /// Presentation attributes, overridden by the inline `style`.
        func declared(_ e: XMLElement) -> [String: String] {
            var d: [String: String] = [:]
            for key in SVGImport.inherited.union(["opacity", "display", "visibility", "filter"]) {
                if let v = attr(e, key) { d[key] = v.trimmingCharacters(in: .whitespaces) }
            }
            if let style = attr(e, "style") {
                for decl in style.split(separator: ";") {
                    let kv = decl.split(separator: ":", maxSplits: 1)
                    if kv.count == 2 { d[kv[0].trimmingCharacters(in: .whitespaces)] = kv[1].trimmingCharacters(in: .whitespaces) }
                }
            }
            return d
        }

        func walk(_ e: XMLElement, _ parent: Context) {
            guard let tag = e.localName else { return }
            if SVGImport.ignoredQuietly.contains(tag) { return }
            let own = declared(e)
            if own["display"] == "none" || own["visibility"] == "hidden" { return }

            var ctx = parent
            ctx.matrix = SVGImport.transform(attr(e, "transform")).concatenating(parent.matrix)
            for (k, v) in own where SVGImport.inherited.contains(k) { ctx.props[k] = v }
            if let o = own["opacity"], let v = SVGImport.number(o) { ctx.opacity *= Double(min(max(v, 0), 1)) }
            if let f = own["filter"], let sh = dropShadow(f) { ctx.shadow = sh }

            switch tag {
            case "g", "svg", "a", "switch":
                for c in elements(of: e) { walk(c, ctx) }
            case "rect": rect(e, ctx)
            case "circle": ellipse(e, ctx, circle: true)
            case "ellipse": ellipse(e, ctx, circle: false)
            case "line": line(e, ctx)
            case "polyline": poly(e, ctx, closed: false)
            case "polygon": poly(e, ctx, closed: true)
            case "path": pathElement(e, ctx)
            case "text": text(e, ctx)
            default: skipped[tag, default: 0] += 1
            }
        }

        // MARK: Styles

        func gradientFill(_ id: String, alpha: Double) -> Fill? {
            guard let e = byID[id], e.localName == "linearGradient" || e.localName == "radialGradient" else { return nil }
            // Follow href chains for stops and geometry.
            var chain: [XMLElement] = [e]
            var next = e
            while chain.count < 5, let href = (attr(next, "href") ?? next.attribute(forName: "xlink:href")?.stringValue),
                  href.hasPrefix("#"), let target = byID[String(href.dropFirst())] {
                chain.append(target); next = target
            }
            guard let stopHolder = chain.first(where: { !elements(of: $0).filter { $0.localName == "stop" }.isEmpty }) else { return nil }

            var stops: [GradientStop] = []
            for s in elements(of: stopHolder) where s.localName == "stop" {
                let decl = declared(s)
                var offset = 0.0
                if let o = attr(s, "offset") {
                    offset = o.hasSuffix("%") ? (Double(o.dropLast().trimmingCharacters(in: .whitespaces)) ?? 0) / 100 : (Double(o) ?? 0)
                }
                var c = RGBA(0, 0, 0)
                if let spec = attr(s, "stop-color") ?? decl["stop-color"] ?? parseStyle(s)["stop-color"], let parsed = SVGImport.color(spec) { c = parsed }
                if let so = attr(s, "stop-opacity") ?? parseStyle(s)["stop-opacity"], let v = Double(so) { c.a *= v }
                c.a *= alpha
                stops.append(GradientStop(color: c, position: min(max(offset, 0), 1)))
            }
            guard stops.count >= 2 else { return nil }

            var f = Fill()
            f.stops = stops
            if e.localName == "radialGradient" {
                f.kind = .radial
            } else {
                f.kind = .linear
                func coord(_ name: String, _ fallback: Double) -> Double {
                    for el in chain {
                        if let v = attr(el, name) {
                            return v.hasSuffix("%") ? (Double(v.dropLast()) ?? 0) / 100 : (Double(v) ?? fallback)
                        }
                    }
                    return fallback
                }
                let dx = coord("x2", 1) - coord("x1", 0), dy = coord("y2", 0) - coord("y1", 0)
                var deg = atan2(dy, dx) * 180 / .pi
                if deg < 0 { deg += 360 }
                f.angle = deg
            }
            return f
        }

        func parseStyle(_ e: XMLElement) -> [String: String] {
            var d: [String: String] = [:]
            if let style = attr(e, "style") {
                for decl in style.split(separator: ";") {
                    let kv = decl.split(separator: ":", maxSplits: 1)
                    if kv.count == 2 { d[kv[0].trimmingCharacters(in: .whitespaces)] = kv[1].trimmingCharacters(in: .whitespaces) }
                }
            }
            return d
        }

        func paint(_ spec: String, alpha: Double, ctx: Context) -> Paint {
            let s = spec.trimmingCharacters(in: .whitespaces)
            if s == "none" { return .none }
            if s.hasPrefix("url("), let hash = s.firstIndex(of: "#"), let close = s.firstIndex(of: ")") {
                let id = String(s[s.index(after: hash)..<close])
                if let g = gradientFill(id, alpha: alpha) { return .gradient(g) }
                // Missing paint server: use the fallback color if there is one, else nothing.
                let tail = s[s.index(after: close)...].trimmingCharacters(in: .whitespaces)
                if let c = SVGImport.color(tail) { return .solid(c) }
                return .none
            }
            if s == "currentColor" { return .solid(SVGImport.color(ctx.props["color"] ?? "black") ?? RGBA(0, 0, 0)) }
            guard var c = SVGImport.color(s) else { return .none }
            c.a *= alpha
            return c.a <= 0 ? .none : .solid(c)
        }

        /// `scale` carries the transform's size change into stroke widths.
        func style(_ ctx: Context, scale: Double) -> Style {
            var st = Style()
            let p = ctx.props

            let fillAlpha = Double(p["fill-opacity"] ?? "") ?? 1
            switch paint(p["fill"] ?? "black", alpha: fillAlpha, ctx: ctx) {
            case .none: st.fill.kind = .none
            case .solid(let c): st.fill.kind = .solid; st.fill.color = c
            case .gradient(let g): st.fill = g
            }

            let strokeAlpha = Double(p["stroke-opacity"] ?? "") ?? 1
            switch paint(p["stroke"] ?? "none", alpha: strokeAlpha, ctx: ctx) {
            case .none: st.stroke.visible = false
            case .solid(let c): st.stroke.visible = true; st.stroke.color = c
            case .gradient(let g): st.stroke.visible = true; st.stroke.color = g.stops.first?.color ?? RGBA(0, 0, 0)
            }
            let width = Double(SVGImport.number(p["stroke-width"]) ?? 1) * scale
            st.stroke.width = width
            if width <= 0 { st.stroke.visible = false }

            switch p["stroke-linecap"] {
            case "round": st.stroke.cap = .round
            case "square": st.stroke.cap = .square
            default: st.stroke.cap = .butt
            }
            switch p["stroke-linejoin"] {
            case "round": st.stroke.join = .round
            case "bevel": st.stroke.join = .bevel
            default: st.stroke.join = .miter
            }
            st.stroke.dash = dashKind(p["stroke-dasharray"], width: max(width, 1.5), scale: scale)

            st.opacity = ctx.opacity
            if let sh = ctx.shadow { st.shadow = sh }
            return st
        }

        /// The closest of this app's dash patterns.
        func dashKind(_ spec: String?, width u: Double, scale: Double) -> DashKind {
            guard let spec, spec != "none" else { return .solid }
            // Dash lengths are in the element's own units, so bring them to canvas units like the stroke width.
            let a = SVGImport.numbers(spec).map { Double($0) * scale }
            guard let first = a.first, a.contains(where: { $0 > 0 }) else { return .solid }
            if a.count >= 4, a.contains(where: { $0 < 0.5 * u }) && a.contains(where: { $0 >= 2 * u }) { return .dashDot }
            if first < 0.5 * u { return .dotted }
            return first >= 7 * u ? .longDash : .dashed
        }

        func dropShadow(_ filterRef: String) -> Shadow? {
            guard let hash = filterRef.firstIndex(of: "#"), let close = filterRef.firstIndex(of: ")"),
                  let f = byID[String(filterRef[filterRef.index(after: hash)..<close])] else { return nil }
            for fe in elements(of: f) where fe.localName == "feDropShadow" {
                var sh = Shadow()
                sh.enabled = true
                let dx = Double(SVGImport.number(attr(fe, "dx")) ?? 2), dy = Double(SVGImport.number(attr(fe, "dy")) ?? 2)
                sh.offset = hypot(dx, dy)
                var deg = atan2(dy, dx) * 180 / .pi
                if deg < 0 { deg += 360 }
                sh.angle = deg
                sh.blur = Double(SVGImport.number(attr(fe, "stdDeviation")) ?? 2) * 2
                var color = SVGImport.color(attr(fe, "flood-color") ?? "black") ?? RGBA(0, 0, 0)
                color.a = Double(SVGImport.number(attr(fe, "flood-opacity")) ?? 1)
                sh.color = color
                return sh
            }
            return nil
        }

        // MARK: Geometry helpers

        struct Decomposed { var sx: CGFloat; var sy: CGFloat; var rotation: Double; var skewed: Bool }

        func decompose(_ m: CGAffineTransform) -> Decomposed {
            let sx = hypot(m.a, m.b), sy = hypot(m.c, m.d)
            let skew = abs(m.a * m.c + m.b * m.d)
            return Decomposed(sx: sx, sy: sy, rotation: Double(atan2(m.b, m.a) * 180 / .pi),
                              skewed: skew > 1e-3 * max(sx * sy, 1e-9))
        }

        func layerID(_ ctx: Context) -> UUID {
            ctx.layer < layers.count ? layers[ctx.layer].id : UUID(uuid: UUID_NULL)
        }

        func addPathShape(_ path: CGPath, _ ctx: Context) {
            guard let o = SVGImport.outline(from: path) else { return }
            let d = decompose(ctx.matrix)
            shapes.append(Shape(layer: layerID(ctx), kind: .path, frame: o.frame,
                                style: style(ctx, scale: Double(sqrt(max(d.sx * d.sy, 1e-9)))), outline: o.segments))
        }

        /// A box-like element: keeps it as a native rotated shape unless the transform shears it.
        func addBox(kind: ShapeKind, local: CGRect, radius: CGFloat, ctx: Context, fallback: CGPath) {
            let d = decompose(ctx.matrix)
            if d.skewed {
                var t = ctx.matrix
                addPathShape(fallback.copy(using: &t) ?? fallback, ctx)
                return
            }
            let c = CGPoint(x: local.midX, y: local.midY).applying(ctx.matrix)
            let w = local.width * d.sx, h = local.height * d.sy
            var st = style(ctx, scale: Double((d.sx + d.sy) / 2))
            st.cornerRadius = Double(radius * d.sx)
            shapes.append(Shape(layer: layerID(ctx), kind: kind, frame: CGRect(x: c.x - w / 2, y: c.y - h / 2, width: w, height: h),
                                style: st, rotation: d.rotation < 0 ? d.rotation + 360 : d.rotation))
        }

        // MARK: Elements

        func rect(_ e: XMLElement, _ ctx: Context) {
            let x = SVGImport.number(attr(e, "x")) ?? 0, y = SVGImport.number(attr(e, "y")) ?? 0
            guard let w = SVGImport.number(attr(e, "width")), let h = SVGImport.number(attr(e, "height")), w > 0, h > 0 else { return }
            var rx = SVGImport.number(attr(e, "rx")), ry = SVGImport.number(attr(e, "ry"))
            if rx == nil { rx = ry }
            if ry == nil { ry = rx }
            let r = min(rx ?? 0, w / 2, h / 2)
            let local = CGRect(x: x, y: y, width: w, height: h)
            let fallback = r > 0 ? CGPath(roundedRect: local, cornerWidth: r, cornerHeight: min(ry ?? r, h / 2), transform: nil)
                                 : CGPath(rect: local, transform: nil)
            addBox(kind: r > 0 ? .rounded : .rectangle, local: local, radius: r, ctx: ctx, fallback: fallback)
        }

        func ellipse(_ e: XMLElement, _ ctx: Context, circle: Bool) {
            let cx = SVGImport.number(attr(e, "cx")) ?? 0, cy = SVGImport.number(attr(e, "cy")) ?? 0
            let rx: CGFloat, ry: CGFloat
            if circle { rx = SVGImport.number(attr(e, "r")) ?? 0; ry = rx }
            else { rx = SVGImport.number(attr(e, "rx")) ?? 0; ry = SVGImport.number(attr(e, "ry")) ?? 0 }
            guard rx > 0, ry > 0 else { return }
            let local = CGRect(x: cx - rx, y: cy - ry, width: rx * 2, height: ry * 2)
            addBox(kind: .ellipse, local: local, radius: 0, ctx: ctx, fallback: CGPath(ellipseIn: local, transform: nil))
        }

        func line(_ e: XMLElement, _ ctx: Context) {
            let p = CGMutablePath()
            p.move(to: CGPoint(x: SVGImport.number(attr(e, "x1")) ?? 0, y: SVGImport.number(attr(e, "y1")) ?? 0))
            p.addLine(to: CGPoint(x: SVGImport.number(attr(e, "x2")) ?? 0, y: SVGImport.number(attr(e, "y2")) ?? 0))
            var t = ctx.matrix
            addPathShape(p.copy(using: &t) ?? p, ctx)
        }

        func poly(_ e: XMLElement, _ ctx: Context, closed: Bool) {
            let n = SVGImport.numbers(attr(e, "points"))
            guard n.count >= 4 else { return }
            let pts = stride(from: 0, to: n.count - 1, by: 2).map { CGPoint(x: n[$0], y: n[$0 + 1]).applying(ctx.matrix) }
            if closed, let native = nativePolygon(pts) {
                var st = style(ctx, scale: Double(sqrt(max(abs(ctx.matrix.a * ctx.matrix.d - ctx.matrix.b * ctx.matrix.c), 1e-9))))
                st.cornerRadius = 0
                shapes.append(Shape(layer: layerID(ctx), kind: native.kind, frame: native.frame, style: st))
                return
            }
            let p = CGMutablePath()
            p.addLines(between: pts)
            if closed { p.closeSubpath() }
            addPathShape(p, ctx)
        }

        /// Recognizes this app's diamond and triangle polygons, so they come back as editable native shapes.
        func nativePolygon(_ pts: [CGPoint]) -> (kind: ShapeKind, frame: CGRect)? {
            guard pts.count == 3 || pts.count == 4 else { return nil }
            let xs = pts.map(\.x), ys = pts.map(\.y)
            let box = CGRect(x: xs.min()!, y: ys.min()!, width: xs.max()! - xs.min()!, height: ys.max()! - ys.min()!)
            guard box.width > 0, box.height > 0 else { return nil }
            let tol = max(0.5, 0.005 * max(box.width, box.height))
            func near(_ p: CGPoint, _ x: CGFloat, _ y: CGFloat) -> Bool { abs(p.x - x) <= tol && abs(p.y - y) <= tol }
            if pts.count == 4, near(pts[0], box.midX, box.minY), near(pts[1], box.maxX, box.midY),
               near(pts[2], box.midX, box.maxY), near(pts[3], box.minX, box.midY) { return (.diamond, box) }
            if pts.count == 3, near(pts[0], box.midX, box.minY), near(pts[1], box.maxX, box.maxY),
               near(pts[2], box.minX, box.maxY) { return (.triangle, box) }
            return nil
        }

        func pathElement(_ e: XMLElement, _ ctx: Context) {
            guard let d = attr(e, "d") else { return }
            let local = SVGImport.path(d)
            var t = ctx.matrix
            addPathShape(local.copy(using: &t) ?? local, ctx)
        }

        // MARK: Text

        struct TextLineInfo { var y: CGFloat; var text: String }

        func text(_ e: XMLElement, _ ctx: Context) {
            let x = SVGImport.numbers(attr(e, "x")).first ?? 0
            var y = SVGImport.numbers(attr(e, "y")).first ?? 0
            var lines: [TextLineInfo] = []

            func append(_ s: String, atNewLine newLine: Bool, y lineY: CGFloat) {
                if newLine || lines.isEmpty { lines.append(TextLineInfo(y: lineY, text: s)) }
                else { lines[lines.count - 1].text += s }
            }
            for node in e.children ?? [] {
                if let t = node as? XMLElement, t.localName == "tspan" {
                    let ty = SVGImport.numbers(attr(t, "y")).first
                    let dy = SVGImport.numbers(attr(t, "dy")).first ?? 0
                    let hasX = attr(t, "x") != nil
                    var newLine = false
                    if let ty, ty != y { y = ty; newLine = true }
                    else if hasX && dy != 0 { y += dy; newLine = true }
                    else if lines.isEmpty { newLine = true }
                    append(t.stringValue ?? "", atNewLine: newLine, y: y)
                } else if node.kind == .text, let s = node.stringValue {
                    let trimmed = s.replacingOccurrences(of: "\n", with: " ").trimmingCharacters(in: .whitespaces)
                    if !trimmed.isEmpty { append(trimmed, atNewLine: lines.isEmpty, y: y) }
                }
            }
            lines = lines.map { TextLineInfo(y: $0.y, text: $0.text.trimmingCharacters(in: .whitespaces)) }.filter { !$0.text.isEmpty }
            guard let first = lines.first else { return }

            let d = decompose(ctx.matrix)
            let scale = max((d.sx + d.sy) / 2, 0.0001)
            var fmt = TextFormat()
            fmt.size = Double(SVGImport.number(ctx.props["font-size"]) ?? 16) * Double(scale)
            fmt.font = fontChoice(ctx.props["font-family"])
            let weight = ctx.props["font-weight"] ?? ""
            fmt.bold = weight == "bold" || weight == "bolder" || (Int(weight) ?? 400) >= 600
            fmt.italic = ctx.props["font-style"] == "italic" || ctx.props["font-style"] == "oblique"
            fmt.underline = (ctx.props["text-decoration"] ?? "").contains("underline")
            switch ctx.props["text-anchor"] {
            case "middle": fmt.hAlign = .center
            case "end": fmt.hAlign = .right
            default: fmt.hAlign = .left
            }
            fmt.vAlign = .top
            let fillAlpha = Double(ctx.props["fill-opacity"] ?? "") ?? 1
            if case .solid(let c) = paint(ctx.props["fill"] ?? "black", alpha: fillAlpha, ctx: ctx) { fmt.color = c } else { fmt.color = RGBA(0, 0, 0) }

            // Box big enough for the longest line, placed so the first baseline sits where the SVG put it.
            let font = Render.font(fmt)
            let attrs: [NSAttributedString.Key: Any] = [.font: font]
            let width = lines.map { NSAttributedString(string: $0.text, attributes: attrs).size().width }.max() ?? 20
            let lineH = font.ascender - font.descender + font.leading
            let w = ceil(width) + 20, h = lineH * CGFloat(lines.count) + 8
            let anchor = CGPoint(x: x, y: first.y).applying(ctx.matrix)
            let left: CGFloat
            switch fmt.hAlign {
            case .left: left = anchor.x - 8
            case .center: left = anchor.x - w / 2
            case .right: left = anchor.x - w + 8
            }
            let top = anchor.y - font.ascender - 4

            var st = Style.textBox
            st.text = fmt
            st.opacity = ctx.opacity
            shapes.append(Shape(layer: layerID(ctx), kind: .text, frame: CGRect(x: left, y: top, width: w, height: h), style: st,
                                text: lines.map(\.text).joined(separator: "\n"), rotation: d.rotation < 0 ? d.rotation + 360 : d.rotation))
        }

        /// Maps a CSS font-family list to one of this app's fonts.
        func fontChoice(_ family: String?) -> String {
            guard let family else { return "System" }
            let names = family.split(separator: ",").map { $0.trimmingCharacters(in: CharacterSet(charactersIn: " '\"")).lowercased() }
            for n in names {
                if let match = TextFormat.installedFonts.first(where: { $0.lowercased() == n }) { return match }
            }
            return "System"
        }
    }
}
