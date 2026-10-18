import Foundation
import CoreGraphics

/// Turns an `ArchitectureGraph` into an editable Graffle `Drawing`.
enum ArchitectureDrawing {
    struct Look { var fill: RGBA; var stroke: RGBA; var dashed = false }

    static func look(_ kind: NodeKind) -> Look {
        switch kind {
        case .app: return Look(fill: RGBA(0.85, 0.92, 1.0), stroke: RGBA(0.15, 0.40, 0.85))
        case .appExtension: return Look(fill: RGBA(1.0, 0.92, 0.80), stroke: RGBA(0.90, 0.50, 0.10))
        case .framework: return Look(fill: RGBA(0.86, 0.96, 0.88), stroke: RGBA(0.18, 0.60, 0.30))
        case .library: return Look(fill: RGBA(0.90, 0.97, 0.84), stroke: RGBA(0.40, 0.62, 0.15))
        case .tool: return Look(fill: RGBA(0.93, 0.88, 0.98), stroke: RGBA(0.50, 0.30, 0.75))
        case .tests: return Look(fill: RGBA(0.94, 0.94, 0.94), stroke: RGBA(0.45, 0.45, 0.45), dashed: true)
        case .externalPackage: return Look(fill: RGBA(0.97, 0.96, 0.99), stroke: RGBA(0.45, 0.35, 0.65))
        case .system: return Look(fill: RGBA(0.97, 0.97, 0.97), stroke: RGBA(0.62, 0.62, 0.62))
        case .other: return Look(fill: RGBA(0.96, 0.96, 0.90), stroke: RGBA(0.55, 0.55, 0.35))
        }
    }

    static func nodeSize(_ node: ArchitectureNode) -> CGSize {
        let longest = max(node.name.count, node.detail.count * 3 / 4)
        let w = node.kind == .system ? 150 : max(190, min(300, CGFloat(longest) * 9 + 40))
        return CGSize(width: w, height: node.kind == .system ? 40 : 62)
    }

    /// `decorations: false` leaves out the title and legend (used for small previews).
    static func build(_ graph: ArchitectureGraph, decorations: Bool = true) -> Drawing {
        var drawing = Drawing()
        let connectorsLayer = Layer(name: "Dependencies")
        let targets = Layer(name: "Targets"), packages = Layer(name: "Packages"), system = Layer(name: "System")
        let notes = Layer(name: "Legend")
        drawing.layers = [connectorsLayer, targets, packages, system, notes]

        let nodes = graph.nodes
        var sizes: [String: CGSize] = [:]
        for n in nodes { sizes[n.id] = nodeSize(n) }
        let layout = GraphLayout.layered(
            nodes: nodes.map(\.id), sizes: sizes,
            edges: graph.edges.map { GraphLayout.Edge(from: $0.from, to: $0.to) },
            bottom: [Set(nodes.filter { $0.kind == .externalPackage }.map(\.id)), Set(nodes.filter { $0.kind == .system }.map(\.id))])

        let top: CGFloat = decorations ? 80 : 0     // room for the title
        var shapeOf: [String: UUID] = [:]
        for n in nodes {
            guard let origin = layout.origins[n.id], let size = sizes[n.id] else { continue }
            let l = look(n.kind)
            let layer = n.kind == .system ? system : (n.kind == .externalPackage ? packages : targets)
            var style = Style()
            style.fill.color = l.fill
            style.stroke.color = l.stroke
            style.stroke.width = 1.6
            style.stroke.dash = l.dashed ? .dashed : .solid
            style.cornerRadius = 10
            style.text.bold = true
            style.text.size = n.kind == .system ? 13 : 15
            style.text.vAlign = n.kind == .system ? .middle : .top
            style.text.color = RGBA(0.12, 0.14, 0.18)
            let frame = CGRect(x: origin.x, y: origin.y + top, width: size.width, height: size.height)
            let group = UUID()
            let shape = Shape(layer: layer.id, kind: .rounded, frame: frame, style: style, text: n.name, group: group)
            shapeOf[n.id] = shape.id
            drawing.shapes.append(shape)
            if n.kind != .system && !n.detail.isEmpty {
                var sub = Style.textBox
                sub.text.size = 11
                sub.text.color = RGBA(0.35, 0.38, 0.45)
                let box = CGRect(x: frame.minX + 4, y: frame.minY + 30, width: size.width - 8, height: 26)
                drawing.shapes.append(Shape(layer: layer.id, kind: .text, frame: box, style: sub, text: n.detail, group: group))
            }
        }

        for e in graph.edges {
            guard let a = shapeOf[e.from], let b = shapeOf[e.to] else { continue }
            var style = Style.connector
            style.stroke.width = 1.4
            var text = ""
            switch e.kind {
            case .dependsOn: style.stroke.color = RGBA(0.30, 0.33, 0.40)
            case .embeds: style.stroke.color = RGBA(0.90, 0.50, 0.10); style.stroke.dash = .dashed
            case .package: style.stroke.color = RGBA(0.50, 0.30, 0.75)
            }
            if layout.cycleEdges.contains(GraphLayout.Edge(from: e.from, to: e.to)) {
                style.stroke.color = RGBA(0.85, 0.15, 0.15); style.stroke.dash = .dashed; text = "cycle"
            }
            drawing.connectors.append(Connector(layer: connectorsLayer.id, from: a, to: b, route: .rounded, style: style, text: text))
        }

        guard decorations else { return shifted(drawing) }
        // Title and legend.
        var titleStyle = Style.textBox
        titleStyle.text.size = 26; titleStyle.text.bold = true; titleStyle.text.hAlign = .left
        titleStyle.text.color = RGBA(0.12, 0.14, 0.18)
        drawing.shapes.append(Shape(layer: notes.id, kind: .text, frame: CGRect(x: 60, y: 14, width: 900, height: 46), style: titleStyle, text: graph.title))
        var subStyle = Style.textBox
        subStyle.text.size = 12; subStyle.text.hAlign = .left; subStyle.text.color = RGBA(0.40, 0.42, 0.48)
        let counts = "\(nodes.count) modules · \(graph.edges.count) dependencies"
        drawing.shapes.append(Shape(layer: notes.id, kind: .text, frame: CGRect(x: 60, y: 54, width: 900, height: 28), style: subStyle,
                                    text: [graph.source, counts].filter { !$0.isEmpty }.joined(separator: " · ")))

        let present = NodeKind.allCases.filter { k in nodes.contains { $0.kind == k } }
        var x: CGFloat = 60
        let y = layout.size.height + top + 10
        for k in present {
            let l = look(k)
            var s = Style()
            s.fill.color = l.fill; s.stroke.color = l.stroke; s.stroke.dash = l.dashed ? .dashed : .solid; s.cornerRadius = 4
            drawing.shapes.append(Shape(layer: notes.id, kind: .rounded, frame: CGRect(x: x, y: y, width: 22, height: 14), style: s))
            var t = Style.textBox
            t.text.size = 11; t.text.hAlign = .left
            let w = CGFloat(k.title.count) * 8 + 24
            drawing.shapes.append(Shape(layer: notes.id, kind: .text, frame: CGRect(x: x + 26, y: y - 6, width: w, height: 26), style: t, text: k.title))
            x += 26 + w + 14
        }
        return shifted(drawing)
    }

    /// Leaves room above and to the left, for themes whose page extends around the diagram (frames, orbs).
    static func shifted(_ drawing: Drawing) -> Drawing {
        var drawing = drawing
        for i in drawing.shapes.indices {
            drawing.shapes[i].frame.origin.x += 130
            drawing.shapes[i].frame.origin.y += 100
        }
        return drawing
    }
}
