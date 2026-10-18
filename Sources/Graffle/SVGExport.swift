import AppKit

/// Writes a `Drawing` as an SVG 1.1 document.
/// Visible layers become `<g>` groups in stacking order; each shape keeps its own rotation, gradient,
/// dash pattern, shadow and text, so the file stays editable in Illustrator, Figma or Inkscape.
enum SVGExport {
    static func svg(for drawing: Drawing, bounds: CGRect) -> String {
        var w = Writer(drawing: drawing)
        return w.document(bounds: bounds)
    }

    // MARK: Number and color formatting

    fileprivate static func n(_ v: CGFloat) -> String { n(Double(v)) }

    fileprivate static func n(_ v: Double) -> String {
        var s = String(format: "%.2f", v)
        while s.contains(".") && (s.hasSuffix("0") || s.hasSuffix(".")) { s.removeLast() }
        return s == "-0" ? "0" : s
    }

    fileprivate static func hex(_ c: RGBA) -> String {
        func b(_ v: Double) -> Int { Int((min(max(v, 0), 1) * 255).rounded()) }
        return String(format: "#%02x%02x%02x", b(c.r), b(c.g), b(c.b))
    }

    fileprivate static func hex(_ c: NSColor) -> String { hex(RGBA(c)) }

    fileprivate static func escape(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;").replacingOccurrences(of: "\"", with: "&quot;")
    }

    fileprivate static func points(_ pts: [CGPoint]) -> String { pts.map { "\(n($0.x)),\(n($0.y))" }.joined(separator: " ") }

    /// A CGPath as SVG path data.
    fileprivate static func pathData(_ path: CGPath) -> String {
        var d: [String] = []
        path.applyWithBlock { el in
            let e = el.pointee
            let p = e.points
            switch e.type {
            case .moveToPoint: d.append("M\(n(p[0].x)) \(n(p[0].y))")
            case .addLineToPoint: d.append("L\(n(p[0].x)) \(n(p[0].y))")
            case .addQuadCurveToPoint: d.append("Q\(n(p[0].x)) \(n(p[0].y)) \(n(p[1].x)) \(n(p[1].y))")
            case .addCurveToPoint: d.append("C\(n(p[0].x)) \(n(p[0].y)) \(n(p[1].x)) \(n(p[1].y)) \(n(p[2].x)) \(n(p[2].y))")
            case .closeSubpath: d.append("Z")
            @unknown default: break
            }
        }
        return d.joined(separator: " ")
    }

    fileprivate static func fontFamily(_ name: String) -> String {
        name == "System" ? "-apple-system, 'Helvetica Neue', Helvetica, Arial, sans-serif" : "'\(escape(name))', sans-serif"
    }

    // MARK: Text layout (same line breaks as the canvas)

    struct TextLine { var text: String; var baseline: CGFloat }

    /// Wraps `text` into `width` points with the canvas's own rules and returns each line with its baseline offset.
    static func layout(_ text: String, format: TextFormat, width: CGFloat) -> (lines: [TextLine], height: CGFloat) {
        let attrs = Render.attributes(format, color: .black)
        let storage = NSTextStorage(string: text, attributes: attrs)
        let lm = NSLayoutManager()
        let container = NSTextContainer(size: CGSize(width: max(width, 1), height: .greatestFiniteMagnitude))
        container.lineFragmentPadding = 0
        lm.addTextContainer(container)
        storage.addLayoutManager(lm)
        _ = lm.glyphRange(for: container)

        var lines: [TextLine] = []
        let all = NSRange(location: 0, length: lm.numberOfGlyphs)
        lm.enumerateLineFragments(forGlyphRange: all) { rect, _, _, glyphRange, _ in
            let chars = lm.characterRange(forGlyphRange: glyphRange, actualGlyphRange: nil)
            let piece = (text as NSString).substring(with: chars).trimmingCharacters(in: .newlines)
            let baseline = rect.minY + lm.location(forGlyphAt: glyphRange.location).y
            lines.append(TextLine(text: piece.trimmingCharacters(in: CharacterSet(charactersIn: " ")), baseline: baseline))
        }
        return (lines, lm.usedRect(for: container).height)
    }

    // MARK: Document writer

    private struct Writer {
        let drawing: Drawing
        var defs: [String] = []
        var nextID = 1

        init(drawing: Drawing) { self.drawing = drawing }

        mutating func id(_ prefix: String) -> String {
            defer { nextID += 1 }
            return "\(prefix)\(nextID)"
        }

        mutating func document(bounds b: CGRect) -> String {
            var body: [String] = []
            let shapesByID = Dictionary(uniqueKeysWithValues: drawing.shapes.map { ($0.id, $0) })

            for layer in drawing.layers where layer.visible {
                var items: [String] = []
                for c in drawing.connectors where c.layer == layer.id {
                    guard let a = shapesByID[c.from], let z = shapesByID[c.to] else { continue }
                    items.append(connector(c, ConnectorGeometry.make(c, a, z)))
                }
                for s in drawing.shapes where s.layer == layer.id { items.append(shape(s)) }
                let gid = "layer-" + String(layer.id.uuidString.prefix(8)).lowercased()
                body.append("<g id=\"\(gid)\" data-name=\"\(SVGExport.escape(layer.name))\">\n" + items.joined(separator: "\n") + "\n</g>")
            }

            var out = "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n"
            out += "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"\(SVGExport.n(b.width))\" height=\"\(SVGExport.n(b.height))\" "
            out += "viewBox=\"\(SVGExport.n(b.minX)) \(SVGExport.n(b.minY)) \(SVGExport.n(b.width)) \(SVGExport.n(b.height))\">\n"
            if !defs.isEmpty { out += "<defs>\n" + defs.joined(separator: "\n") + "\n</defs>\n" }
            out += "<rect x=\"\(SVGExport.n(b.minX))\" y=\"\(SVGExport.n(b.minY))\" width=\"\(SVGExport.n(b.width))\" height=\"\(SVGExport.n(b.height))\" fill=\"#ffffff\"/>\n"
            out += body.joined(separator: "\n") + "\n</svg>\n"
            return out
        }

        // MARK: Paint

        mutating func fillAttrs(_ f: Fill, frame: CGRect) -> String {
            switch f.kind {
            case .none:
                return "fill=\"none\""
            case .solid:
                return paint(f.color)
            case .linear, .radial:
                let stops = f.sortedStops
                guard stops.count >= 2 else { return paint(stops.first?.color ?? f.color) }
                let gid = id("grad")
                let stopTags = stops.map { s -> String in
                    var tag = "<stop offset=\"\(SVGExport.n(min(max(s.position, 0), 1)))\" stop-color=\"\(SVGExport.hex(s.color))\""
                    if s.color.a < 1 { tag += " stop-opacity=\"\(SVGExport.n(s.color.a))\"" }
                    return tag + "/>"
                }.joined()
                let c = CGPoint(x: frame.midX, y: frame.midY)
                if f.kind == .linear {
                    let rad = CGFloat(f.angle) * .pi / 180
                    let dir = CGPoint(x: cos(rad), y: sin(rad))
                    let half = (abs(frame.width * dir.x) + abs(frame.height * dir.y)) / 2
                    defs.append("<linearGradient id=\"\(gid)\" gradientUnits=\"userSpaceOnUse\" x1=\"\(SVGExport.n(c.x - dir.x * half))\" y1=\"\(SVGExport.n(c.y - dir.y * half))\" x2=\"\(SVGExport.n(c.x + dir.x * half))\" y2=\"\(SVGExport.n(c.y + dir.y * half))\">\(stopTags)</linearGradient>")
                } else {
                    defs.append("<radialGradient id=\"\(gid)\" gradientUnits=\"userSpaceOnUse\" cx=\"\(SVGExport.n(c.x))\" cy=\"\(SVGExport.n(c.y))\" r=\"\(SVGExport.n(max(hypot(frame.width, frame.height) / 2, 1)))\">\(stopTags)</radialGradient>")
                }
                return "fill=\"url(#\(gid))\""
            }
        }

        func paint(_ c: RGBA) -> String {
            var s = "fill=\"\(SVGExport.hex(c))\""
            if c.a < 1 { s += " fill-opacity=\"\(SVGExport.n(c.a))\"" }
            return s
        }

        func strokeAttrs(_ s: Stroke) -> String {
            guard s.visible, s.width > 0 else { return "stroke=\"none\"" }
            var a = "stroke=\"\(SVGExport.hex(s.color))\" stroke-width=\"\(SVGExport.n(s.width))\""
            if s.color.a < 1 { a += " stroke-opacity=\"\(SVGExport.n(s.color.a))\"" }
            let cap: CapKind = (s.dash == .dotted && s.cap == .butt) ? .round : s.cap
            a += " stroke-linecap=\"\(cap.rawValue)\" stroke-linejoin=\"\(s.join.rawValue)\" stroke-miterlimit=\"10\""
            let dash = s.dash.pattern(width: s.width)
            if !dash.isEmpty { a += " stroke-dasharray=\"\(dash.map { SVGExport.n($0) }.joined(separator: " "))\"" }
            return a
        }

        /// Defines a drop-shadow filter and returns its id.
        mutating func shadowFilter(_ sh: Shadow) -> String {
            let fid = id("shadow")
            let v = sh.vector
            defs.append("<filter id=\"\(fid)\" x=\"-50%\" y=\"-50%\" width=\"200%\" height=\"200%\"><feDropShadow dx=\"\(SVGExport.n(v.width))\" dy=\"\(SVGExport.n(v.height))\" stdDeviation=\"\(SVGExport.n(sh.blur / 2))\" flood-color=\"\(SVGExport.hex(sh.color))\" flood-opacity=\"\(SVGExport.n(sh.color.a))\"/></filter>")
            return fid
        }

        // MARK: Shapes

        mutating func shape(_ s: Shape) -> String {
            let st = s.style
            let f = s.frame
            var parts: [String] = []

            // Fill and line (rotated about the center; the shadow stays screen-aligned, so it wraps the rotation).
            let hasPaint = st.fill.kind != .none || (st.stroke.visible && st.stroke.width > 0)
            if hasPaint {
                let paintAttrs = fillAttrs(st.fill, frame: f) + " " + strokeAttrs(st.stroke)
                let element: String
                switch s.kind {
                case .rectangle, .rounded, .text:
                    let r = min(CGFloat(st.cornerRadius), f.width / 2, f.height / 2)
                    let rx = (s.kind == .text) ? 0 : r
                    element = "<rect x=\"\(SVGExport.n(f.minX))\" y=\"\(SVGExport.n(f.minY))\" width=\"\(SVGExport.n(f.width))\" height=\"\(SVGExport.n(f.height))\"" + (rx > 0 ? " rx=\"\(SVGExport.n(rx))\"" : "") + " \(paintAttrs)/>"
                case .ellipse:
                    element = "<ellipse cx=\"\(SVGExport.n(f.midX))\" cy=\"\(SVGExport.n(f.midY))\" rx=\"\(SVGExport.n(f.width / 2))\" ry=\"\(SVGExport.n(f.height / 2))\" \(paintAttrs)/>"
                case .diamond, .triangle:
                    element = "<polygon points=\"\(SVGExport.points(s.polygon ?? []))\" \(paintAttrs)/>"
                case .path:
                    element = "<path d=\"\(SVGExport.pathData(s.path()))\" \(paintAttrs)/>"
                }
                var g = rotated(element, s)
                if st.shadow.enabled { g = "<g filter=\"url(#\(shadowFilter(st.shadow)))\">\(g)</g>" }
                parts.append(g)
            }

            if !s.text.isEmpty { parts.append(rotated(textElement(s), s)) }

            var inner = parts.joined(separator: "\n")
            if st.opacity < 0.999 { inner = "<g opacity=\"\(SVGExport.n(st.opacity))\">\n\(inner)\n</g>" }
            let gid = "shape-" + String(s.id.uuidString.prefix(8)).lowercased()
            var attrs = "id=\"\(gid)\""
            if let g = s.group { attrs += " data-group=\"\(String(g.uuidString.prefix(8)).lowercased())\"" }
            return "<g \(attrs)>\n\(inner)\n</g>"
        }

        func rotated(_ element: String, _ s: Shape) -> String {
            guard s.rotation != 0 else { return element }
            return "<g transform=\"rotate(\(SVGExport.n(s.rotation)) \(SVGExport.n(s.center.x)) \(SVGExport.n(s.center.y)))\">\(element)</g>"
        }

        func textElement(_ s: Shape) -> String {
            let t = s.style.text
            let box = s.frame.insetBy(dx: 8, dy: 4)
            let (lines, h) = SVGExport.layout(s.text, format: t, width: box.width)
            let bh = min(h, box.height)
            let top: CGFloat
            switch t.vAlign {
            case .top: top = box.minY
            case .middle: top = box.midY - bh / 2
            case .bottom: top = box.maxY - bh
            }
            let x: CGFloat, anchor: String
            switch t.hAlign {
            case .left: x = box.minX; anchor = "start"
            case .center: x = box.midX; anchor = "middle"
            case .right: x = box.maxX; anchor = "end"
            }
            return textTag(lines: lines, x: x, top: top, format: t, anchor: anchor,
                           color: Render.textColor(t, fill: s.style.fill))
        }

        func textTag(lines: [TextLine], x: CGFloat, top: CGFloat, format t: TextFormat, anchor: String, color: NSColor) -> String {
            var a = "font-family=\"\(SVGExport.fontFamily(t.font))\" font-size=\"\(SVGExport.n(t.size))\" fill=\"\(SVGExport.hex(color))\" text-anchor=\"\(anchor)\""
            if t.bold { a += " font-weight=\"bold\"" }
            if t.italic { a += " font-style=\"italic\"" }
            if t.underline { a += " text-decoration=\"underline\"" }
            let spans = lines.map { "<tspan x=\"\(SVGExport.n(x))\" y=\"\(SVGExport.n(top + $0.baseline))\" xml:space=\"preserve\">\(SVGExport.escape($0.text))</tspan>" }
            return "<text \(a)>\(spans.joined())</text>"
        }

        // MARK: Connectors

        mutating func connector(_ c: Connector, _ g: ConnectorGeometry) -> String {
            let st = c.style
            var parts: [String] = []
            if st.stroke.visible && st.stroke.width > 0 {
                var line = "<path d=\"\(SVGExport.pathData(g.path))\" fill=\"none\" \(strokeAttrs(st.stroke))/>"
                line += head(c.startHead, g.startPoint, g.startAngle, c.headScale, st.stroke)
                line += head(c.endHead, g.endPoint, g.endAngle, c.headScale, st.stroke)
                if st.shadow.enabled { line = "<g filter=\"url(#\(shadowFilter(st.shadow)))\">\(line)</g>" }
                parts.append(line)
            }
            if !c.text.isEmpty { parts.append(label(c, at: g.labelPoint)) }
            var inner = parts.joined(separator: "\n")
            if st.opacity < 0.999 { inner = "<g opacity=\"\(SVGExport.n(st.opacity))\">\n\(inner)\n</g>" }
            return "<g id=\"connector-\(String(c.id.uuidString.prefix(8)).lowercased())\">\n\(inner)\n</g>"
        }

        func label(_ c: Connector, at p: CGPoint) -> String {
            let t = c.style.text
            let color = t.color?.ns ?? .black
            let str = NSAttributedString(string: c.text, attributes: Render.attributes(t, color: color))
            let size = str.size()
            let font = Render.font(t)
            let rect = CGRect(x: p.x - size.width / 2 - 4, y: p.y - size.height / 2 - 1, width: size.width + 8, height: size.height + 2)
            let bg = "<rect x=\"\(SVGExport.n(rect.minX))\" y=\"\(SVGExport.n(rect.minY))\" width=\"\(SVGExport.n(rect.width))\" height=\"\(SVGExport.n(rect.height))\" rx=\"3\" fill=\"#ffffff\"/>"
            let line = TextLine(text: c.text, baseline: font.ascender)
            // The canvas draws the string with its top at rect.minY + 1.
            return bg + textTag(lines: [line], x: p.x, top: rect.minY + 1, format: t, anchor: "middle", color: color)
        }

        /// Same geometry as `Render.drawHead`.
        func head(_ kind: HeadKind, _ tip: CGPoint, _ angle: CGFloat, _ scale: Double, _ stroke: Stroke) -> String {
            guard kind != .none else { return "" }
            let w = CGFloat(max(stroke.width, 1))
            let len = (8 + w * 1.5) * CGFloat(scale)
            let dir = CGPoint(x: cos(angle), y: sin(angle))
            let perp = CGPoint(x: -dir.y, y: dir.x)
            func pt(_ back: CGFloat, _ side: CGFloat) -> CGPoint {
                CGPoint(x: tip.x - dir.x * back + perp.x * side, y: tip.y - dir.y * back + perp.y * side)
            }
            let ink = SVGExport.hex(stroke.color)
            let line = "stroke=\"\(ink)\" stroke-width=\"\(SVGExport.n(w))\" stroke-linejoin=\"round\" stroke-linecap=\"round\""
            let solid = "fill=\"\(ink)\" \(line)", hollow = "fill=\"#ffffff\" \(line)"

            switch kind {
            case .none: return ""
            case .filledArrow:
                return "<polygon points=\"\(SVGExport.points([pt(0, 0), pt(len, len * 0.38), pt(len, -len * 0.38)]))\" \(solid)/>"
            case .openArrow:
                return "<polyline points=\"\(SVGExport.points([pt(len, len * 0.42), pt(0, 0), pt(len, -len * 0.42)]))\" fill=\"none\" \(line)/>"
            case .hollowTriangle:
                return "<polygon points=\"\(SVGExport.points([pt(0, 0), pt(len, len * 0.38), pt(len, -len * 0.38)]))\" \(hollow)/>"
            case .filledDiamond, .hollowDiamond:
                let pts = SVGExport.points([pt(0, 0), pt(len / 2, len * 0.32), pt(len, 0), pt(len / 2, -len * 0.32)])
                return "<polygon points=\"\(pts)\" \(kind == .filledDiamond ? solid : hollow)/>"
            case .filledCircle, .hollowCircle:
                let c = pt(len * 0.4, 0)
                return "<circle cx=\"\(SVGExport.n(c.x))\" cy=\"\(SVGExport.n(c.y))\" r=\"\(SVGExport.n(len * 0.4))\" \(kind == .filledCircle ? solid : hollow)/>"
            case .bar:
                let a = pt(0, len * 0.45), b = pt(0, -len * 0.45)
                return "<line x1=\"\(SVGExport.n(a.x))\" y1=\"\(SVGExport.n(a.y))\" x2=\"\(SVGExport.n(b.x))\" y2=\"\(SVGExport.n(b.y))\" \(line)/>"
            case .crowFoot, .crowFootBar, .crowFootCircle, .doubleBar, .circleBar:
                let parts = Render.entityEnd(kind, len: len)
                var out = ""
                for (p, q) in parts.lines {
                    let a = pt(p.x, p.y), b = pt(q.x, q.y)
                    out += "<line x1=\"\(SVGExport.n(a.x))\" y1=\"\(SVGExport.n(a.y))\" x2=\"\(SVGExport.n(b.x))\" y2=\"\(SVGExport.n(b.y))\" \(line)/>"
                }
                if let c = parts.circle {
                    let center = pt(c.back, 0)
                    out += "<circle cx=\"\(SVGExport.n(center.x))\" cy=\"\(SVGExport.n(center.y))\" r=\"\(SVGExport.n(c.radius))\" \(hollow)/>"
                }
                return out
            }
        }
    }
}
