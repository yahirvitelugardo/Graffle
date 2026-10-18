import Foundation
import CoreGraphics

/// Kinds of diagram that start from ready-made content to edit (as opposed to Blank, or the ones read from code).
enum Starter: String, CaseIterable {
    case uml, entityRelationship, conceptual, synoptic, pyramid, ishikawa, tree

    var title: String {
        switch self {
        case .uml: return "UML Diagram"
        case .entityRelationship: return "Entity-Relationship Diagram"
        case .conceptual: return "Conceptual Diagram"
        case .synoptic: return "Synoptic Diagram"
        case .pyramid: return "Pyramid Diagram"
        case .ishikawa: return "Ishikawa Diagram"
        case .tree: return "Tree Diagram"
        }
    }

    var subtitle: String {
        switch self {
        case .uml: return "Class diagram with inheritance, an interface and associations (UML)."
        case .entityRelationship: return "Tables with their fields, joined by crow's-foot relationships (modelo entidad-relación)."
        case .conceptual: return "A central concept with related concepts and linking phrases (mapa conceptual)."
        case .synoptic: return "A general idea broken down with braces into main ideas, supporting ideas and details (cuadro sinóptico)."
        case .pyramid: return "Stacked levels, from the top of the pyramid to its base, each with a label (diagrama piramidal)."
        case .ishikawa: return "Cause-and-effect fishbone: six categories of causes pointing at the problem (diagrama de causa y efecto)."
        case .tree: return "A decision tree: a root, chance nodes and outcomes with labelled branches (diagrama de árbol)."
        }
    }
}

enum Starters {
    static func drawing(_ starter: Starter) -> Drawing {
        switch starter {
        case .uml: return uml()
        case .entityRelationship: return entityRelationship()
        case .conceptual: return conceptual()
        case .synoptic: return synoptic()
        case .pyramid: return pyramid()
        case .ishikawa: return ishikawa()
        case .tree: return tree()
        }
    }

    // MARK: Building blocks

    private struct Builder {
        var drawing = Drawing()
        var layer: UUID { drawing.layers[0].id }

        func style(fill: RGBA?, stroke: RGBA?, width: Double = 1.5, corner: Double = 0, textColor: RGBA? = nil, size: Double = 14, bold: Bool = false) -> Style {
            var s = Style()
            if let fill { s.fill.color = fill } else { s.fill.kind = .none }
            if let stroke { s.stroke.color = stroke; s.stroke.width = width } else { s.stroke.visible = false }
            s.cornerRadius = corner
            s.text.size = size
            s.text.bold = bold
            s.text.color = textColor
            return s
        }

        @discardableResult
        mutating func shape(_ kind: ShapeKind, _ frame: CGRect, _ text: String = "", fill: RGBA?, stroke: RGBA?, width: Double = 1.5, corner: Double = 0,
                            textColor: RGBA? = nil, size: Double = 14, bold: Bool = false, group: UUID? = nil, align: HAlign = .center, vAlign: VAlign = .middle) -> UUID {
            var st = style(fill: fill, stroke: stroke, width: width, corner: corner, textColor: textColor, size: size, bold: bold)
            st.text.hAlign = align
            st.text.vAlign = vAlign
            let s = Shape(layer: layer, kind: kind, frame: frame, style: st, text: text, group: group)
            drawing.shapes.append(s)
            return s.id
        }

        mutating func text(_ text: String, _ frame: CGRect, size: Double = 14, bold: Bool = false, align: HAlign = .center, vAlign: VAlign = .middle,
                           color: RGBA? = RGBA(0.14, 0.16, 0.22), group: UUID? = nil) {
            var st = Style.textBox
            st.text.size = size; st.text.bold = bold; st.text.hAlign = align; st.text.vAlign = vAlign; st.text.color = color
            drawing.shapes.append(Shape(layer: layer, kind: .text, frame: frame, style: st, text: text, group: group))
        }

        /// A straight line as a path shape.
        mutating func line(_ a: CGPoint, _ b: CGPoint, color: RGBA = RGBA(0.25, 0.27, 0.34), width: Double = 1.6, dash: DashKind = .solid, group: UUID? = nil) {
            let rect = CGRect(x: min(a.x, b.x), y: min(a.y, b.y), width: max(abs(a.x - b.x), 1), height: max(abs(a.y - b.y), 1))
            func norm(_ p: CGPoint) -> CGPoint { CGPoint(x: (p.x - rect.minX) / rect.width, y: (p.y - rect.minY) / rect.height) }
            var st = style(fill: nil, stroke: color, width: width)
            st.stroke.dash = dash
            st.stroke.cap = .round
            drawing.shapes.append(Shape(layer: layer, kind: .path, frame: rect, style: st, group: group,
                                        outline: [PathSegment(op: .move, points: [norm(a)]), PathSegment(op: .line, points: [norm(b)])]))
        }

        /// A curly brace "{" that opens to the left, filling `frame`.
        mutating func brace(_ frame: CGRect, color: RGBA = RGBA(0.14, 0.16, 0.22), width: Double = 2) {
            func c(_ a: Double, _ b: Double, _ c: Double, _ d: Double, _ e: Double, _ f: Double) -> PathSegment {
                PathSegment(op: .curve, points: [CGPoint(x: a, y: b), CGPoint(x: c, y: d), CGPoint(x: e, y: f)])
            }
            let outline: [PathSegment] = [
                PathSegment(op: .move, points: [CGPoint(x: 1, y: 0)]),
                c(0.65, 0, 0.5, 0.05, 0.5, 0.2),
                PathSegment(op: .line, points: [CGPoint(x: 0.5, y: 0.4)]),
                c(0.5, 0.46, 0.3, 0.5, 0, 0.5),
                c(0.3, 0.5, 0.5, 0.54, 0.5, 0.6),
                PathSegment(op: .line, points: [CGPoint(x: 0.5, y: 0.8)]),
                c(0.5, 0.95, 0.65, 1, 1, 1),
            ]
            var st = style(fill: nil, stroke: color, width: width)
            st.stroke.cap = .round
            drawing.shapes.append(Shape(layer: layer, kind: .path, frame: frame, style: st, outline: outline))
        }

        /// A filled polygon.
        mutating func polygon(_ points: [CGPoint], fill: RGBA, stroke: RGBA?, width: Double = 2) {
            let xs = points.map(\.x), ys = points.map(\.y)
            let rect = CGRect(x: xs.min()!, y: ys.min()!, width: max(xs.max()! - xs.min()!, 1), height: max(ys.max()! - ys.min()!, 1))
            func norm(_ p: CGPoint) -> CGPoint { CGPoint(x: (p.x - rect.minX) / rect.width, y: (p.y - rect.minY) / rect.height) }
            var segs = [PathSegment(op: .move, points: [norm(points[0])])]
            for p in points.dropFirst() { segs.append(PathSegment(op: .line, points: [norm(p)])) }
            segs.append(PathSegment(op: .close))
            drawing.shapes.append(Shape(layer: layer, kind: .path, frame: rect, style: style(fill: fill, stroke: stroke, width: width), outline: segs))
        }

        mutating func connect(_ a: UUID, _ b: UUID, route: Route = .straight, label: String = "", start: HeadKind = .none, end: HeadKind = .filledArrow,
                              color: RGBA = RGBA(0.25, 0.27, 0.34), width: Double = 1.5, dash: DashKind = .solid) {
            var st = Style.connector
            st.stroke.color = color; st.stroke.width = width; st.stroke.dash = dash
            drawing.connectors.append(Connector(layer: layer, from: a, to: b, route: route, startHead: start, endHead: end, style: st, text: label))
        }
    }

    private static let ink = RGBA(0.14, 0.16, 0.22)

    // MARK: Synoptic (cuadro sinóptico)

    private static func synoptic() -> Drawing {
        var b = Builder()
        let rowHeight: CGFloat = 150, gap: CGFloat = 30, top: CGFloat = 80
        func rowTop(_ i: Int) -> CGFloat { top + CGFloat(i) * (rowHeight + gap) }
        let total = rowHeight * 3 + gap * 2
        b.text("General\nidea", CGRect(x: 60, y: top + total / 2 - 40, width: 170, height: 80), size: 22, bold: true)
        b.brace(CGRect(x: 240, y: top, width: 46, height: total))
        for i in 0..<3 {
            let y = rowTop(i)
            b.text("Main\nidea", CGRect(x: 300, y: y + rowHeight / 2 - 32, width: 150, height: 64), size: 18)
            b.brace(CGRect(x: 456, y: y, width: 40, height: rowHeight))
            b.text("Supporting\nideas", CGRect(x: 510, y: y + rowHeight / 2 - 32, width: 190, height: 64), size: 18)
            b.brace(CGRect(x: 706, y: y, width: 40, height: rowHeight))
            b.text("Detail\nDetail\nDetail", CGRect(x: 760, y: y + rowHeight / 2 - 48, width: 150, height: 96), size: 16)
        }
        return b.drawing
    }

    // MARK: Conceptual (mapa conceptual)

    private static func conceptual() -> Drawing {
        var b = Builder()
        let palette: [RGBA] = [RGBA(1.0, 0.42, 0.55), RGBA(1.0, 0.76, 0.25), RGBA(0.27, 0.63, 0.88), RGBA(0.27, 0.82, 0.72), RGBA(0.62, 0.47, 0.70), RGBA(1.0, 0.60, 0.25)]
        let phrases = ["includes", "requires", "is part of", "produces", "depends on", "leads to"]
        let center = CGPoint(x: 560, y: 520)
        let main = b.shape(.ellipse, CGRect(x: center.x - 120, y: center.y - 62, width: 240, height: 124), "Main concept", fill: RGBA(1, 1, 1),
                           stroke: ink, width: 3, textColor: ink, size: 20, bold: true)
        for (i, color) in palette.enumerated() {
            let angle = (Double(i) * 60 - 90) * .pi / 180
            let c = CGPoint(x: center.x + CGFloat(cos(angle)) * 340, y: center.y + CGFloat(sin(angle)) * 270)
            let node = b.shape(.ellipse, CGRect(x: c.x - 88, y: c.y - 44, width: 176, height: 88), "Concept \(i + 1)", fill: color, stroke: color.darker(0.18),
                               width: 3, textColor: RGBA(1, 1, 1), size: 16, bold: true)
            b.connect(main, node, label: phrases[i], color: color.darker(0.1), width: 2)
            // A smaller concept hanging off every second one.
            if i % 2 == 0 {
                let outward = CGPoint(x: CGFloat(cos(angle)), y: CGFloat(sin(angle)))
                let s = CGPoint(x: c.x + outward.x * 190 + (i == 2 ? 70 : 0), y: c.y + outward.y * 110 + (i == 0 ? -10 : 40))
                let sub = b.shape(.ellipse, CGRect(x: s.x - 62, y: s.y - 32, width: 124, height: 64), "Example", fill: color.lighter(0.25), stroke: color,
                                  width: 2, textColor: ink, size: 13)
                b.connect(node, sub, label: "e.g.", color: color.darker(0.1), width: 1.6, dash: .dotted)
            }
        }
        return b.drawing
    }

    // MARK: Entity-relationship

    private static func entityRelationship() -> Drawing {
        var b = Builder()
        let salmon = RGBA(0.98, 0.72, 0.66), zebra = RGBA(0.90, 0.91, 0.93), line = RGBA(0.33, 0.37, 0.45)
        func table(_ name: String, _ fields: [String], at origin: CGPoint) -> UUID {
            let group = UUID()
            let width: CGFloat = 220, head: CGFloat = 32, row: CGFloat = 26
            let height = head + row * CGFloat(fields.count)
            let box = b.shape(.rectangle, CGRect(x: origin.x, y: origin.y, width: width, height: height), fill: RGBA(1, 1, 1), stroke: line, width: 1.5, group: group)
            b.shape(.rectangle, CGRect(x: origin.x, y: origin.y, width: width, height: head), name, fill: salmon, stroke: line, width: 1.5, textColor: ink, size: 15,
                    bold: true, group: group)
            for (i, field) in fields.enumerated() {
                let y = origin.y + head + row * CGFloat(i)
                b.shape(.rectangle, CGRect(x: origin.x, y: y, width: width, height: row), field, fill: i % 2 == 0 ? RGBA(1, 1, 1) : zebra, stroke: nil,
                        textColor: ink, size: 13, group: group, align: .left)
            }
            return box
        }
        let customer = table("Customer", ["id", "name", "email"], at: CGPoint(x: 80, y: 90))
        let order = table("Order", ["id", "customer_id", "ordered_at", "total"], at: CGPoint(x: 460, y: 90))
        let item = table("OrderItem", ["id", "order_id", "product_id", "quantity"], at: CGPoint(x: 460, y: 340))
        let product = table("Product", ["id", "name", "price"], at: CGPoint(x: 80, y: 340))
        b.connect(customer, order, route: .rounded, label: "places", start: .doubleBar, end: .crowFootCircle, color: line)
        b.connect(order, item, route: .rounded, label: "contains", start: .doubleBar, end: .crowFootBar, color: line)
        b.connect(product, item, route: .rounded, label: "is sold in", start: .doubleBar, end: .crowFootCircle, color: line)
        return b.drawing
    }

    // MARK: Pyramid

    private static func pyramid() -> Drawing {
        var b = Builder()
        let colors: [RGBA] = [RGBA(0.30, 0.45, 0.78), RGBA(0.25, 0.60, 0.55), RGBA(0.75, 0.75, 0.42), RGBA(0.98, 0.78, 0.38), RGBA(0.98, 0.58, 0.25), RGBA(0.85, 0.22, 0.28)]
        let labels = ["Top level", "Second level", "Third level", "Fourth level", "Fifth level", "Base level"]
        let levels = colors.count
        let level: CGFloat = 78, gap: CGFloat = 6, baseWidth: CGFloat = 600
        let centerX: CGFloat = 520, top: CGFloat = 90
        let total = CGFloat(levels) * (level + gap)
        func half(_ y: CGFloat) -> CGFloat { (y - top) / total * baseWidth / 2 }
        for i in 0..<levels {
            let y0 = top + CGFloat(i) * (level + gap), y1 = y0 + level
            let color = colors[i]
            b.polygon([CGPoint(x: centerX - half(y0), y: y0), CGPoint(x: centerX + half(y0), y: y0),
                       CGPoint(x: centerX + half(y1), y: y1), CGPoint(x: centerX - half(y1), y: y1)], fill: color, stroke: RGBA(1, 1, 1), width: 2)
            b.text("\([5, 10, 20, 30, 50, 75][i])%", CGRect(x: centerX - 50, y: y0 + level / 2 - 14, width: 100, height: 28), size: 17, bold: true,
                   color: RGBA(1, 1, 1))
            let edge = centerX + half(y1) - (half(y1) - half(y0)) / 2 + 14
            b.line(CGPoint(x: edge, y: y0 + level / 2), CGPoint(x: centerX + baseWidth / 2 + 36, y: y0 + level / 2), color: color, width: 2.5)
            b.shape(.ellipse, CGRect(x: centerX + baseWidth / 2 + 30, y: y0 + level / 2 - 6, width: 12, height: 12), fill: color, stroke: nil)
            b.text(labels[i], CGRect(x: centerX + baseWidth / 2 + 50, y: y0 + level / 2 - 15, width: 190, height: 30), size: 17, bold: true, align: .left,
                   color: color.darker(0.1))
        }
        return b.drawing
    }

    // MARK: Ishikawa (fishbone)

    private static func ishikawa() -> Drawing {
        var b = Builder()
        let spineY: CGFloat = 410, spineStart: CGFloat = 90, spineEnd: CGFloat = 880
        let colors: [RGBA] = [RGBA(0.45, 0.65, 0.20), RGBA(0.20, 0.60, 0.60), RGBA(0.30, 0.45, 0.78), RGBA(0.60, 0.35, 0.65), RGBA(0.85, 0.45, 0.20), RGBA(0.80, 0.25, 0.35)]
        let categories = ["Method", "Machine", "Material", "Manpower", "Measurement", "Environment"]
        b.line(CGPoint(x: spineStart, y: spineY), CGPoint(x: spineEnd, y: spineY), color: ink, width: 4)
        b.shape(.rounded, CGRect(x: spineEnd, y: spineY - 55, width: 190, height: 110), "Problem\n(effect)", fill: RGBA(0.13, 0.35, 0.45), stroke: nil, corner: 22,
                textColor: RGBA(1, 1, 1), size: 20, bold: true)
        let ribXs: [CGFloat] = [170, 430, 690]
        for (col, x) in ribXs.enumerated() {
            for (side, sign) in [(0, CGFloat(-1)), (1, CGFloat(1))] {
                let index = side * 3 + col
                let color = colors[index]
                let top = spineY + sign * 260                                   // where the rib starts, away from the spine
                let meet = CGPoint(x: x + 120, y: spineY)
                b.line(CGPoint(x: x, y: top), meet, color: color, width: 4)
                b.shape(.rounded, CGRect(x: x - 75, y: sign < 0 ? top - 44 : top + 6, width: 150, height: 38), categories[index], fill: color, stroke: nil, corner: 14,
                        textColor: RGBA(1, 1, 1), size: 16, bold: true)
                for k in 1...3 {
                    let t = CGFloat(k) / 4                                      // along the rib, from the category toward the spine
                    let p = CGPoint(x: x + (meet.x - x) * t, y: top + (meet.y - top) * t)
                    b.line(CGPoint(x: p.x - 105, y: p.y), p, color: color, width: 2)
                    b.text("Cause", CGRect(x: p.x - 105, y: p.y - 22, width: 90, height: 20), size: 12, align: .left)
                }
            }
        }
        return b.drawing
    }

    // MARK: Tree (decision tree)

    private static func tree() -> Drawing {
        var b = Builder()
        let blue = RGBA(0.15, 0.42, 0.90), orange = RGBA(1.0, 0.55, 0.35), pink = RGBA(1.0, 0.55, 0.85)
        let root = b.shape(.rectangle, CGRect(x: 80, y: 450, width: 90, height: 64), "Start", fill: RGBA(0.78, 0.86, 1.0), stroke: blue, width: 3, textColor: ink, size: 16)
        let options = ["Option A", "Option B", "Option C"]
        let outcomes = [("Likely", "0.3"), ("Normal", "0.5"), ("Unlikely", "0.2")]
        let ys: [CGFloat] = [190, 482, 774]
        for (i, y) in ys.enumerated() {
            let node = b.shape(.ellipse, CGRect(x: 430, y: y - 36, width: 72, height: 72), "\(i + 2)", fill: RGBA(1.0, 0.92, 0.65), stroke: orange, width: 3, textColor: ink, size: 16)
            b.connect(root, node, label: options[i])
            for (j, outcome) in outcomes.enumerated() {
                let leaf = b.shape(.triangle, CGRect(x: 810, y: y + CGFloat(j - 1) * 104 - 36, width: 76, height: 72), "\((j + 1) * 1000)", fill: RGBA(1.0, 0.85, 0.97),
                                   stroke: pink, width: 3, textColor: ink, size: 14, vAlign: .bottom)
                b.connect(node, leaf, label: "\(outcome.0) \(outcome.1)")
            }
        }
        return b.drawing
    }

    // MARK: UML

    private static func uml() -> Drawing {
        var g = ClassGraph(title: "UML", source: "")
        g.types = [
            TypeInfo(name: "Person", kind: .classType, language: .java, properties: ["+ name: String", "+ email: String"], methods: ["+ login()", "+ logout()"], isAbstract: true),
            TypeInfo(name: "Student", kind: .classType, language: .java, supertypes: ["Person", "Enrollable"], properties: ["+ studentId: int"], methods: ["+ enroll(course)"]),
            TypeInfo(name: "Teacher", kind: .classType, language: .java, supertypes: ["Person"], properties: ["- salary: double"], methods: ["+ grade(student)"]),
            TypeInfo(name: "Enrollable", kind: .interfaceType, language: .java, methods: ["+ enroll(course)"]),
            TypeInfo(name: "Course", kind: .classType, language: .java, properties: ["+ title: String", "+ credits: int"], methods: ["+ addStudent(student)"]),
        ]
        g.relations = [
            TypeRelation(from: "Student", to: "Person", kind: .inherits),
            TypeRelation(from: "Teacher", to: "Person", kind: .inherits),
            TypeRelation(from: "Student", to: "Enrollable", kind: .implements),
            TypeRelation(from: "Course", to: "Teacher", kind: .association),
            TypeRelation(from: "Course", to: "Student", kind: .association),
        ]
        return ClassDrawing.build(g, options: ClassOptions(), decorations: false)
    }
}
