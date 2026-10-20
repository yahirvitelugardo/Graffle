import AppKit

/// The electronic symbols Graffle can draw (diagram only: nothing is simulated).
/// Every symbol is one free-form path shape whose leads end at the middle of the frame's sides,
/// so connectors (wires) attach exactly at the pins.
enum CircuitPart: String, CaseIterable {
    case battery, dcSource, acSource, currentSource, ground
    case resistor, potentiometer, capacitor, polarizedCapacitor, inductor, fuse
    case diode, zener, led, npn, pnp
    case switchSPST, lamp, voltmeter, ammeter, motor
    case opAmp, andGate, orGate, notGate, nandGate, norGate, xorGate
    case junction

    enum Category: String, CaseIterable {
        case sources = "Sources", passive = "Passive", semiconductors = "Semiconductors", electromechanical = "Switches and Indicators"
        case logic = "Amplifiers and Logic Gates", wiring = "Wiring"
    }

    var category: Category {
        switch self {
        case .battery, .dcSource, .acSource, .currentSource, .ground: return .sources
        case .resistor, .potentiometer, .capacitor, .polarizedCapacitor, .inductor, .fuse: return .passive
        case .diode, .zener, .led, .npn, .pnp: return .semiconductors
        case .switchSPST, .lamp, .voltmeter, .ammeter, .motor: return .electromechanical
        case .opAmp, .andGate, .orGate, .notGate, .nandGate, .norGate, .xorGate: return .logic
        case .junction: return .wiring
        }
    }

    var title: String {
        switch self {
        case .battery: return "Battery"
        case .dcSource: return "DC Voltage Source"
        case .acSource: return "AC Voltage Source"
        case .currentSource: return "Current Source"
        case .ground: return "Ground"
        case .resistor: return "Resistor"
        case .potentiometer: return "Potentiometer"
        case .capacitor: return "Capacitor"
        case .polarizedCapacitor: return "Polarized Capacitor"
        case .inductor: return "Inductor"
        case .fuse: return "Fuse"
        case .diode: return "Diode"
        case .zener: return "Zener Diode"
        case .led: return "LED"
        case .npn: return "NPN Transistor"
        case .pnp: return "PNP Transistor"
        case .switchSPST: return "Switch"
        case .lamp: return "Lamp"
        case .voltmeter: return "Voltmeter"
        case .ammeter: return "Ammeter"
        case .motor: return "Motor"
        case .opAmp: return "Op-Amp"
        case .andGate: return "AND Gate"
        case .orGate: return "OR Gate"
        case .notGate: return "NOT Gate"
        case .nandGate: return "NAND Gate"
        case .norGate: return "NOR Gate"
        case .xorGate: return "XOR Gate"
        case .junction: return "Junction"
        }
    }

    /// The letter in the reference label (R1, C2, ...).
    var prefix: String {
        switch self {
        case .battery, .dcSource, .acSource: return "V"
        case .currentSource: return "I"
        case .ground, .junction: return ""
        case .resistor, .potentiometer: return "R"
        case .capacitor, .polarizedCapacitor: return "C"
        case .inductor: return "L"
        case .fuse: return "F"
        case .diode, .zener, .led: return "D"
        case .npn, .pnp: return "Q"
        case .switchSPST: return "S"
        case .lamp: return "LP"
        case .voltmeter, .ammeter: return "M"
        case .motor: return "M"
        case .opAmp, .andGate, .orGate, .notGate, .nandGate, .norGate, .xorGate: return "U"
        }
    }

    /// Frame size on the canvas.
    var size: CGSize {
        switch self {
        case .ground: return CGSize(width: 48, height: 56)
        case .npn, .pnp: return CGSize(width: 64, height: 64)
        case .opAmp: return CGSize(width: 96, height: 92)
        case .andGate, .orGate, .notGate, .nandGate, .norGate, .xorGate: return CGSize(width: 88, height: 76)
        case .junction: return CGSize(width: 10, height: 10)
        default: return CGSize(width: 80, height: 64)
        }
    }

    /// Where wires attach (points in the frame, in points). Connectors snap to the pin that faces them.
    var pins: [CGPoint] {
        let w = size.width, h = size.height, cy = h / 2
        switch self {
        case .junction: return []
        case .ground: return [CGPoint(x: w / 2, y: 0)]
        case .potentiometer: return [CGPoint(x: 0, y: cy), CGPoint(x: w, y: cy), CGPoint(x: w / 2, y: 0)]
        case .npn, .pnp: return [CGPoint(x: 0, y: cy), CGPoint(x: w / 2, y: 0), CGPoint(x: w / 2, y: h)]
        case .opAmp: return [CGPoint(x: 0, y: 24), CGPoint(x: 0, y: 56), CGPoint(x: w, y: 40)]
        case .andGate, .orGate, .nandGate, .norGate, .xorGate: return [CGPoint(x: 0, y: 20), CGPoint(x: 0, y: 44), CGPoint(x: w, y: 32)]
        case .notGate: return [CGPoint(x: 0, y: 32), CGPoint(x: w, y: 32)]
        default: return [CGPoint(x: 0, y: cy), CGPoint(x: w, y: cy)]
        }
    }

    enum Label { case below, right, none }
    var label: Label {
        switch self {
        case .ground, .junction: return .none
        case .npn, .pnp: return .right
        default: return .below
        }
    }

    // MARK: Drawing the symbol

    /// The symbol as strokes in a frame of `size` (y grows downward).
    private func strokes() -> [Stroke2D] {
        let w = Double(size.width), h = Double(size.height), cy = h / 2
        var out: [Stroke2D] = []
        func line(_ pts: [(Double, Double)]) { out.append(.poly(pts.map { CGPoint(x: $0.0, y: $0.1) }, closed: false)) }
        func closed(_ pts: [(Double, Double)]) { out.append(.poly(pts.map { CGPoint(x: $0.0, y: $0.1) }, closed: true)) }
        func circle(_ cx: Double, _ cyy: Double, _ r: Double) { out.append(.circle(CGPoint(x: cx, y: cyy), r)) }
        func arrow(tip: (Double, Double), from: (Double, Double), length: Double = 6) {
            let dx = tip.0 - from.0, dy = tip.1 - from.1, d = max(hypot(dx, dy), 0.001)
            let ux = dx / d, uy = dy / d
            let bx = tip.0 - ux * length, by = tip.1 - uy * length
            line([(bx - uy * length * 0.5, by + ux * length * 0.5), tip, (bx + uy * length * 0.5, by - ux * length * 0.5)])
        }

        switch self {
        case .resistor:
            line([(0, cy), (12, cy), (18, cy - 14), (30, cy + 14), (42, cy - 14), (54, cy + 14), (62, cy), (w, cy)])
        case .potentiometer:
            line([(0, cy), (12, cy), (18, cy - 10), (30, cy + 10), (42, cy - 10), (54, cy + 10), (62, cy), (w, cy)])
            line([(w / 2, 0), (w / 2, cy - 12)])
            arrow(tip: (w / 2, cy - 11), from: (w / 2, cy - 22))
        case .capacitor:
            line([(0, cy), (34, cy)]); line([(34, cy - 16), (34, cy + 16)])
            line([(46, cy - 16), (46, cy + 16)]); line([(46, cy), (w, cy)])
        case .polarizedCapacitor:
            line([(0, cy), (34, cy)]); line([(34, cy - 16), (34, cy + 16)])
            out.append(.curve(CGPoint(x: 48, y: cy - 16), CGPoint(x: 38, y: cy - 8), CGPoint(x: 38, y: cy + 8), CGPoint(x: 48, y: cy + 16)))
            line([(43, cy), (w, cy)])
            line([(22, cy - 14), (22, cy - 6)]); line([(18, cy - 10), (26, cy - 10)])
        case .inductor:
            line([(0, cy), (14, cy)])
            for i in 0..<4 {
                let x = 14 + Double(i) * 13
                out.append(.curve(CGPoint(x: x, y: cy), CGPoint(x: x, y: cy - 17), CGPoint(x: x + 13, y: cy - 17), CGPoint(x: x + 13, y: cy)))
            }
            line([(66, cy), (w, cy)])
        case .fuse:
            line([(0, cy), (16, cy)]); closed([(16, cy - 9), (64, cy - 9), (64, cy + 9), (16, cy + 9)])
            line([(16, cy), (64, cy)]); line([(64, cy), (w, cy)])
        case .battery:
            line([(0, cy), (30, cy)]); line([(30, cy - 18), (30, cy + 18)]); line([(40, cy - 10), (40, cy + 10)])
            line([(50, cy - 18), (50, cy + 18)]); line([(60, cy - 10), (60, cy + 10)]); line([(60, cy), (w, cy)])
            line([(20, cy - 12), (20, cy - 4)]); line([(16, cy - 8), (24, cy - 8)])
        case .dcSource:
            line([(0, cy), (24, cy)]); circle(40, cy, 16); line([(56, cy), (w, cy)])
            line([(30, cy), (36, cy)]); line([(33, cy - 3), (33, cy + 3)]); line([(45, cy), (51, cy)])
        case .acSource:
            line([(0, cy), (24, cy)]); circle(40, cy, 16); line([(56, cy), (w, cy)])
            out.append(.curve(CGPoint(x: 30, y: cy), CGPoint(x: 33, y: cy - 12), CGPoint(x: 37, y: cy - 12), CGPoint(x: 40, y: cy)))
            out.append(.curve(CGPoint(x: 40, y: cy), CGPoint(x: 43, y: cy + 12), CGPoint(x: 47, y: cy + 12), CGPoint(x: 50, y: cy)))
        case .currentSource:
            line([(0, cy), (24, cy)]); circle(40, cy, 16); line([(56, cy), (w, cy)])
            line([(30, cy), (50, cy)]); arrow(tip: (50, cy), from: (40, cy), length: 7)
        case .ground:
            line([(w / 2, 0), (w / 2, 28)]); line([(6, 28), (w - 6, 28)]); line([(14, 37), (w - 14, 37)]); line([(21, 46), (w - 21, 46)])
        case .diode, .zener, .led:
            line([(0, cy), (28, cy)]); closed([(28, cy - 16), (28, cy + 16), (52, cy)]); line([(52, cy), (w, cy)])
            if self == .zener { line([(46, cy - 12), (52, cy - 16), (52, cy + 16), (58, cy + 12)]) }
            else { line([(52, cy - 16), (52, cy + 16)]) }
            if self == .led {
                line([(56, cy - 20), (66, cy - 30)]); arrow(tip: (66, cy - 30), from: (56, cy - 20))
                line([(64, cy - 13), (74, cy - 23)]); arrow(tip: (74, cy - 23), from: (64, cy - 13))
            }
        case .npn, .pnp:
            line([(0, cy), (24, cy)]); line([(24, cy - 16), (24, cy + 16)])
            line([(24, cy - 6), (w / 2, cy - 16), (w / 2, 0)])
            line([(24, cy + 6), (w / 2, cy + 16), (w / 2, h)])
            if self == .npn { arrow(tip: (30, cy + 13.5), from: (26.4, cy + 9), length: 7) }    // out of the emitter
            else { arrow(tip: (25.6, cy + 8), from: (30, cy + 13.5), length: 7) }               // into the emitter
        case .switchSPST:
            line([(0, cy), (20, cy)]); line([(20, cy), (58, cy - 20)]); line([(60, cy), (w, cy)])
            circle(20, cy, 2.5); circle(60, cy, 2.5)
        case .lamp:
            line([(0, cy), (24, cy)]); circle(40, cy, 16); line([(56, cy), (w, cy)])
            line([(29, cy - 11), (51, cy + 11)]); line([(29, cy + 11), (51, cy - 11)])
        case .voltmeter, .ammeter, .motor:
            line([(0, cy), (24, cy)]); circle(40, cy, 16); line([(56, cy), (w, cy)])
        case .opAmp:
            closed([(16, 8), (16, 72), (80, 40)])
            line([(0, 24), (16, 24)]); line([(0, 56), (16, 56)]); line([(80, 40), (w, 40)])
            line([(22, 24), (30, 24)]); line([(22, 56), (30, 56)]); line([(26, 52), (26, 60)])
        case .andGate, .nandGate:
            line([(0, 20), (16, 20)]); line([(0, 44), (16, 44)])
            out.append(.poly([CGPoint(x: 40, y: 8), CGPoint(x: 16, y: 8), CGPoint(x: 16, y: 56), CGPoint(x: 40, y: 56)], closed: false))
            out.append(.curve(CGPoint(x: 40, y: 8), CGPoint(x: 74, y: 8), CGPoint(x: 74, y: 56), CGPoint(x: 40, y: 56)))
            if self == .nandGate { circle(70, 32, 4); line([(74, 32), (w, 32)]) } else { line([(65.5, 32), (w, 32)]) }
        case .orGate, .norGate, .xorGate:
            orBody(&out, lead: self == .xorGate ? 16 : 22)
            if self == .xorGate { out.append(.curve(CGPoint(x: 10, y: 8), CGPoint(x: 20, y: 22), CGPoint(x: 20, y: 42), CGPoint(x: 10, y: 56))) }
            if self == .norGate { circle(76, 32, 4); line([(80, 32), (w, 32)]) } else { line([(72, 32), (w, 32)]) }
        case .notGate:
            line([(0, 32), (16, 32)]); closed([(16, 12), (16, 52), (62, 32)]); circle(66.5, 32, 4); line([(70.5, 32), (w, 32)])
        case .junction:
            break
        }
        return out
    }

    /// The body of an OR gate: a concave back and two curves meeting at the tip (72, 32); input leads reach `lead`.
    private func orBody(_ out: inout [Stroke2D], lead: Double) {
        out.append(.poly([CGPoint(x: 0, y: 20), CGPoint(x: lead, y: 20)], closed: false))
        out.append(.poly([CGPoint(x: 0, y: 44), CGPoint(x: lead, y: 44)], closed: false))
        out.append(.curve(CGPoint(x: 16, y: 8), CGPoint(x: 40, y: 8), CGPoint(x: 62, y: 16), CGPoint(x: 72, y: 32)))
        out.append(.curve(CGPoint(x: 16, y: 56), CGPoint(x: 40, y: 56), CGPoint(x: 62, y: 48), CGPoint(x: 72, y: 32)))
        out.append(.curve(CGPoint(x: 16, y: 8), CGPoint(x: 26, y: 22), CGPoint(x: 26, y: 42), CGPoint(x: 16, y: 56)))
    }

    /// The letter drawn inside round meters and motors.
    private var glyph: String? {
        switch self {
        case .voltmeter: return "V"
        case .ammeter: return "A"
        case .motor: return "M"
        default: return nil
        }
    }

    /// The symbol as a free-form outline (points normalized to the frame, as `Shape.outline` wants).
    var outline: [PathSegment] {
        let w = size.width, h = size.height
        func n(_ p: CGPoint) -> CGPoint { CGPoint(x: p.x / w, y: p.y / h) }
        var segs: [PathSegment] = []
        for s in strokes() {
            switch s {
            case .poly(let pts, let closed):
                guard let first = pts.first else { continue }
                segs.append(PathSegment(op: .move, points: [n(first)]))
                for p in pts.dropFirst() { segs.append(PathSegment(op: .line, points: [n(p)])) }
                if closed { segs.append(PathSegment(op: .close)) }
            case .curve(let a, let c1, let c2, let b):
                segs.append(PathSegment(op: .move, points: [n(a)]))
                segs.append(PathSegment(op: .curve, points: [n(c1), n(c2), n(b)]))
            case .circle(let c, let r):
                // Four Bézier arcs approximate a circle.
                let k = r * 0.5523
                let pts = [CGPoint(x: c.x + r, y: c.y), CGPoint(x: c.x, y: c.y + r), CGPoint(x: c.x - r, y: c.y), CGPoint(x: c.x, y: c.y - r)]
                segs.append(PathSegment(op: .move, points: [n(pts[0])]))
                segs.append(PathSegment(op: .curve, points: [n(CGPoint(x: c.x + r, y: c.y + k)), n(CGPoint(x: c.x + k, y: c.y + r)), n(pts[1])]))
                segs.append(PathSegment(op: .curve, points: [n(CGPoint(x: c.x - k, y: c.y + r)), n(CGPoint(x: c.x - r, y: c.y + k)), n(pts[2])]))
                segs.append(PathSegment(op: .curve, points: [n(CGPoint(x: c.x - r, y: c.y - k)), n(CGPoint(x: c.x - k, y: c.y - r)), n(pts[3])]))
                segs.append(PathSegment(op: .curve, points: [n(CGPoint(x: c.x + k, y: c.y - r)), n(CGPoint(x: c.x + r, y: c.y - k)), n(pts[0])]))
                segs.append(PathSegment(op: .close))
            }
        }
        return segs
    }

    private enum Stroke2D {
        case poly([CGPoint], closed: Bool)
        case curve(CGPoint, CGPoint, CGPoint, CGPoint)
        case circle(CGPoint, Double)
    }

    // MARK: Making shapes

    static let ink = RGBA(0.14, 0.16, 0.22)

    /// A new symbol with its top-left corner at `origin`. `number` is the sequence number for its reference label.
    func makeShape(layer: UUID, at origin: CGPoint, number: Int, rotation: Double = 0) -> Shape {
        var st = Style()
        st.fill.kind = .none
        st.stroke.color = Self.ink
        st.stroke.width = 2
        st.stroke.cap = .round
        st.stroke.join = .round
        st.text.size = 11
        st.text.color = Self.ink
        let frame = CGRect(origin: origin, size: size)
        var text = prefix.isEmpty ? "" : "\(prefix)\(number)"
        switch label {
        case .below: st.text.vAlign = .bottom
        case .right: st.text.hAlign = .right
        case .none: break
        }
        if let g = glyph { text = g }                       // meters and motors say what they are inside the circle
        if glyph != nil { st.text.size = 14; st.text.bold = true; st.text.vAlign = .middle }
        if self == .junction {
            st.fill.kind = .solid
            st.fill.color = Self.ink
            return Shape(layer: layer, kind: .ellipse, frame: frame, style: st, rotation: rotation, name: title)
        }
        let local = pins.map { CGPoint(x: $0.x / size.width, y: $0.y / size.height) }
        return Shape(layer: layer, kind: .path, frame: frame, style: st, text: text, rotation: rotation, outline: outline, name: title, pins: local)
    }

    /// A wire between two symbols.
    static func wire(layer: UUID, from: UUID, to: UUID) -> Connector {
        var st = Style.connector
        st.stroke.color = ink
        st.stroke.width = 2
        return Connector(layer: layer, from: from, to: to, route: .orthogonal, startHead: .none, endHead: .none, style: st)
    }

    /// A small picture of the symbol for menus.
    func icon(size box: NSSize = NSSize(width: 34, height: 22)) -> NSImage {
        let shape = makeShape(layer: UUID(), at: .zero, number: 1)
        return NSImage(size: box, flipped: true) { rect in
            guard let ctx = NSGraphicsContext.current?.cgContext else { return false }
            let s = shape.frame.size
            let scale = min(rect.width / s.width, rect.height / s.height)
            ctx.translateBy(x: (rect.width - s.width * scale) / 2, y: (rect.height - s.height * scale) / 2)
            ctx.scaleBy(x: scale, y: scale)
            NSColor.labelColor.setStroke()
            NSColor.labelColor.setFill()
            ctx.setLineWidth(1.5 / scale)
            ctx.setLineCap(.round)
            ctx.setLineJoin(.round)
            ctx.addPath(shape.path())
            if shape.kind == .ellipse { ctx.fillPath() } else { ctx.strokePath() }
            return true
        }
    }
}
