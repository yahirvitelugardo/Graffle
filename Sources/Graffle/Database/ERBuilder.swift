import Foundation
import CoreGraphics

/// Draws the chosen tables of a database as an entity-relationship diagram: a box per table (name, then its columns) and a
/// crow's-foot line for every foreign key between the chosen tables.
enum ERBuilder {
    static let maxColumns = 18
    static let width: CGFloat = 250, head: CGFloat = 32, row: CGFloat = 24

    static func rows(for t: DBTable) -> [(text: String, isKey: Bool)] {
        let fk = Set(t.foreignKeys.map(\.column))
        var rows = t.columns.prefix(maxColumns).map { c -> (String, Bool) in
            let tag = c.isPrimaryKey ? "PK " : (fk.contains(c.name) ? "FK " : "")
            return (tag + c.name + (c.type.isEmpty ? "" : " : " + c.type), c.isPrimaryKey || fk.contains(c.name))
        }
        if t.columns.count > maxColumns { rows.append(("… \(t.columns.count - maxColumns) more columns", false)) }
        return rows.isEmpty ? [("(no columns)", false)] : rows
    }

    static func build(_ schema: DBSchema, tables ids: [String]) -> Drawing {
        let chosen = schema.tables.filter { ids.contains($0.id) }
        var drawing = Drawing()
        drawing.layers = [Layer(name: "Relationships"), Layer(name: "Tables")]
        let relationships = drawing.layers[0].id, tablesLayer = drawing.layers[1].id
        let salmon = RGBA(0.98, 0.72, 0.66), zebra = RGBA(0.90, 0.91, 0.93), line = RGBA(0.33, 0.37, 0.45), ink = RGBA(0.14, 0.16, 0.22)

        // Relationships: from the table that is referenced (one) to the one that holds the key (many).
        let known = Set(chosen.map(\.id))
        var edges: [GraphLayout.Edge] = []
        for t in chosen { for f in t.foreignKeys where known.contains(f.refTable) && f.refTable != t.id { edges.append(.init(from: f.refTable, to: t.id)) } }
        var sizes: [String: CGSize] = [:]
        for t in chosen { sizes[t.id] = CGSize(width: width, height: head + row * CGFloat(rows(for: t).count)) }
        let layout = GraphLayout.layered(nodes: chosen.map(\.id), sizes: sizes, edges: edges, maxWidth: 3300, hGap: 70, vGap: 90, margin: 0)

        var boxOf: [String: UUID] = [:]
        for t in chosen {
            guard let origin = layout.origins[t.id], let size = sizes[t.id] else { continue }
            let o = CGPoint(x: origin.x + 80, y: origin.y + 80)
            let group = UUID()
            func box(_ frame: CGRect, _ text: String, fill: RGBA, stroke: RGBA?, bold: Bool = false, sizePt: Double = 12.5, align: HAlign = .center, color: RGBA? = nil) -> UUID {
                var st = Style()
                st.fill.color = fill
                if let stroke { st.stroke.color = stroke; st.stroke.width = 1.5 } else { st.stroke.visible = false }
                st.text.size = sizePt; st.text.bold = bold; st.text.hAlign = align; st.text.color = color ?? ink
                let s = Shape(layer: tablesLayer, kind: .rectangle, frame: frame, style: st, text: text, group: group)
                drawing.shapes.append(s)
                return s.id
            }
            boxOf[t.id] = box(CGRect(origin: o, size: size), "", fill: RGBA(1, 1, 1), stroke: line)
            _ = box(CGRect(x: o.x, y: o.y, width: width, height: head), t.name, fill: salmon, stroke: line, bold: true, sizePt: 14)
            for (i, r) in rows(for: t).enumerated() {
                _ = box(CGRect(x: o.x, y: o.y + head + row * CGFloat(i), width: width, height: row), r.text, fill: i % 2 == 0 ? RGBA(1, 1, 1) : zebra, stroke: nil,
                        bold: r.isKey, align: .left)
            }
        }
        var seen = Set<String>()
        for t in chosen {
            for f in t.foreignKeys {
                guard let one = boxOf[f.refTable], let many = boxOf[t.id], f.refTable != t.id, seen.insert(f.refTable + "→" + t.id + ":" + f.column).inserted else { continue }
                let nullable = t.columns.first { $0.name == f.column }?.isNullable ?? true
                var st = Style.connector
                st.stroke.color = line; st.stroke.width = 1.5
                drawing.connectors.append(Connector(layer: relationships, from: one, to: many, route: .rounded, startHead: .doubleBar,
                                                    endHead: nullable ? .crowFootCircle : .crowFootBar, style: st, text: f.column))
            }
        }
        return drawing
    }
}
