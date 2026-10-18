import Foundation
import CoreGraphics

/// Turns a `ClassGraph` into an editable Graffle `Drawing`: one box per type (name, properties, methods) and UML-style relations.
enum ClassDrawing {
    static func look(_ kind: TypeKind) -> ArchitectureDrawing.Look {
        switch kind {
        case .classType: return .init(fill: RGBA(0.85, 0.92, 1.0), stroke: RGBA(0.15, 0.40, 0.85))
        case .structType, .recordType: return .init(fill: RGBA(0.86, 0.96, 0.88), stroke: RGBA(0.18, 0.60, 0.30))
        case .enumType: return .init(fill: RGBA(1.0, 0.92, 0.80), stroke: RGBA(0.90, 0.50, 0.10))
        case .protocolType, .interfaceType: return .init(fill: RGBA(0.93, 0.88, 0.98), stroke: RGBA(0.50, 0.30, 0.75))
        case .actorType: return .init(fill: RGBA(0.86, 0.95, 0.96), stroke: RGBA(0.10, 0.55, 0.60))
        case .objectType: return .init(fill: RGBA(0.94, 0.94, 0.94), stroke: RGBA(0.45, 0.45, 0.45))
        }
    }

    static let lineHeight: CGFloat = 14
    static let maxProperties = 10, maxMethods = 12

    /// What a box lists, cut to a sensible length.
    static func lines(_ items: [String], limit: Int) -> [String] {
        items.count <= limit ? items : Array(items.prefix(limit)) + ["… \(items.count - limit) more"]
    }

    struct Box {
        var type: TypeInfo
        var props: [String]
        var methods: [String]
        var size: CGSize
    }

    static func box(for t: TypeInfo, options: ClassOptions) -> Box {
        let props = options.includeMembers ? lines(t.properties, limit: maxProperties) : []
        let methods = options.includeMembers ? lines(t.methods, limit: maxMethods) : []
        let longest = max((props + methods).map(\.count).max() ?? 0, Int(Double(t.name.count) * 1.35), t.supertypes.isEmpty ? 0 : 14)
        let width = min(340, max(170, CGFloat(longest) * 6.4 + 24))
        var height: CGFloat = 58
        if options.includeMembers {
            height += CGFloat(max(props.count, 1)) * lineHeight + 10
            height += CGFloat(max(methods.count, 1)) * lineHeight + 10
        }
        return Box(type: t, props: props, methods: methods, size: CGSize(width: width, height: height))
    }

    /// `decorations: false` leaves out the title, legend and key (used for small previews).
    static func build(_ graph: ClassGraph, options: ClassOptions = ClassOptions(), decorations: Bool = true) -> Drawing {
        var drawing = Drawing()
        let relationsLayer = Layer(name: "Relationships"), typesLayer = Layer(name: "Types"), notes = Layer(name: "Legend")
        drawing.layers = [relationsLayer, typesLayer, notes]

        let boxes = graph.types.map { box(for: $0, options: options) }
        var sizes: [String: CGSize] = [:]
        for b in boxes { sizes[b.type.name] = b.size }
        // Supertypes sit above what extends or implements them.
        let layout = GraphLayout.layered(
            nodes: graph.types.map(\.name), sizes: sizes,
            edges: graph.relations.filter { $0.kind != .association }.map { GraphLayout.Edge(from: $0.to, to: $0.from) },
            maxWidth: 3000, hGap: 40, vGap: 80)

        let top: CGFloat = decorations ? 80 : 0
        var shapeOf: [String: UUID] = [:]
        for b in boxes {
            guard let origin = layout.origins[b.type.name] else { continue }
            let l = look(b.type.kind)
            let frame = CGRect(x: origin.x, y: origin.y + top, width: b.size.width, height: b.size.height)
            let group = UUID()

            var style = Style()
            style.fill.color = l.fill
            style.stroke.color = l.stroke
            style.stroke.width = 1.6
            style.cornerRadius = 8
            let container = Shape(layer: typesLayer.id, kind: .rounded, frame: frame, style: style, group: group)
            shapeOf[b.type.name] = container.id
            drawing.shapes.append(container)

            func text(_ s: String, _ rect: CGRect, size: CGFloat, bold: Bool = false, align: HAlign = .center, mono: Bool = false,
                      color: RGBA? = nil, italic: Bool = false) {
                var st = Style.textBox
                st.text.size = Double(size)
                st.text.bold = bold
                st.text.italic = italic
                st.text.hAlign = align
                st.text.vAlign = .top
                if mono { st.text.font = "Menlo" }
                st.text.color = color ?? RGBA(0.14, 0.16, 0.22)
                drawing.shapes.append(Shape(layer: typesLayer.id, kind: .text, frame: rect, style: st, text: s, group: group))
            }
            let kindLabel = (b.type.isAbstract ? "abstract " : "") + b.type.kind.rawValue
            text("«\(kindLabel)»", CGRect(x: frame.minX, y: frame.minY + 1, width: frame.width, height: 22), size: 10, color: RGBA(0.40, 0.43, 0.50))
            text(b.type.name, CGRect(x: frame.minX + 4, y: frame.minY + 15, width: frame.width - 8, height: 30), size: 14, bold: true, italic: b.type.isAbstract)
            if !b.type.supertypes.isEmpty {
                text(": " + b.type.supertypes.prefix(3).joined(separator: ", "), CGRect(x: frame.minX + 4, y: frame.minY + 38, width: frame.width - 8, height: 20),
                     size: 9, color: RGBA(0.40, 0.43, 0.50))
            }
            if options.includeMembers {
                func divider(at y: CGFloat) {
                    var st = Style()
                    st.fill.kind = .none
                    st.stroke.color = l.stroke
                    st.stroke.width = 1
                    let outline = [PathSegment(op: .move, points: [CGPoint(x: 0, y: 0.5)]), PathSegment(op: .line, points: [CGPoint(x: 1, y: 0.5)])]
                    drawing.shapes.append(Shape(layer: typesLayer.id, kind: .path, frame: CGRect(x: frame.minX, y: y, width: frame.width, height: 1),
                                                style: st, group: group, outline: outline))
                }
                let propsTop = frame.minY + 58
                let propsHeight = CGFloat(max(b.props.count, 1)) * lineHeight + 10
                divider(at: propsTop)
                if !b.props.isEmpty { text(b.props.joined(separator: "\n"), CGRect(x: frame.minX + 8, y: propsTop + 5, width: frame.width - 12, height: propsHeight - 6), size: 10, align: .left, mono: true) }
                let methodsTop = propsTop + propsHeight
                divider(at: methodsTop)
                if !b.methods.isEmpty { text(b.methods.joined(separator: "\n"), CGRect(x: frame.minX + 8, y: methodsTop + 5, width: frame.width - 12, height: frame.maxY - methodsTop - 6), size: 10, align: .left, mono: true) }
            }
        }

        for r in graph.relations {
            guard let a = shapeOf[r.from], let b = shapeOf[r.to] else { continue }
            var style = Style.connector
            style.stroke.width = 1.4
            var head = HeadKind.hollowTriangle
            switch r.kind {
            case .inherits: style.stroke.color = RGBA(0.25, 0.27, 0.34)
            case .implements: style.stroke.color = RGBA(0.50, 0.30, 0.75); style.stroke.dash = .dashed
            case .association: style.stroke.color = RGBA(0.45, 0.50, 0.60); head = .openArrow
            }
            drawing.connectors.append(Connector(layer: relationsLayer.id, from: a, to: b, route: .rounded, endHead: head, style: style))
        }

        guard decorations else { return ArchitectureDrawing.shifted(drawing) }
        // Title, a one-line key to the arrows, and the kinds that appear.
        var titleStyle = Style.textBox
        titleStyle.text.size = 26; titleStyle.text.bold = true; titleStyle.text.hAlign = .left
        titleStyle.text.color = RGBA(0.12, 0.14, 0.18)
        drawing.shapes.append(Shape(layer: notes.id, kind: .text, frame: CGRect(x: 60, y: 14, width: 1000, height: 46), style: titleStyle, text: graph.title + " — Classes"))
        var sub = Style.textBox
        sub.text.size = 12; sub.text.hAlign = .left; sub.text.color = RGBA(0.40, 0.42, 0.48)
        var info = "\(graph.types.count) types · \(graph.relations.count) relationships"
        if let t = graph.truncated { info += " · showing the \(t.shown) most connected of \(t.total)" }
        drawing.shapes.append(Shape(layer: notes.id, kind: .text, frame: CGRect(x: 60, y: 54, width: 1400, height: 28), style: sub,
                                    text: [graph.source, info].filter { !$0.isEmpty }.joined(separator: " · ")))
        let y = layout.size.height + top + 10
        var x: CGFloat = 60
        for k in TypeKind.allCases where graph.types.contains(where: { $0.kind == k }) {
            let l = look(k)
            var s = Style()
            s.fill.color = l.fill; s.stroke.color = l.stroke; s.cornerRadius = 4
            drawing.shapes.append(Shape(layer: notes.id, kind: .rounded, frame: CGRect(x: x, y: y, width: 22, height: 14), style: s))
            var t = Style.textBox
            t.text.size = 11; t.text.hAlign = .left
            let w = CGFloat(k.rawValue.count) * 8 + 24
            drawing.shapes.append(Shape(layer: notes.id, kind: .text, frame: CGRect(x: x + 26, y: y - 6, width: w, height: 26), style: t, text: k.title))
            x += 26 + w + 14
        }
        var key = Style.textBox
        key.text.size = 11; key.text.hAlign = .left; key.text.color = RGBA(0.40, 0.42, 0.48)
        drawing.shapes.append(Shape(layer: notes.id, kind: .text, frame: CGRect(x: 60, y: y + 26, width: 1400, height: 26), style: key,
                                    text: "Hollow arrow: extends · dashed hollow arrow: implements · open arrow: has a property of that type · + public  − private  # protected  ~ internal"))
        return ArchitectureDrawing.shifted(drawing)
    }
}
