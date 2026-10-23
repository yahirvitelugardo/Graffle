import SwiftUI

/// The layers list: layers front to back, each with the objects on it. Tap to select, eye and lock to toggle,
/// context menus to rename, reorder and move objects between layers.
struct LayersTab: View {
    @ObservedObject var model: EditorModel

    @State private var collapsed = Set<UUID>()
    @State private var query = ""
    @State private var reordering = false
    @State private var renaming: LayerRename?
    @State private var renameText = ""
    @State private var deleting: UUID?

    struct LayerRename: Identifiable { let id: UUID; let isLayer: Bool }

    private var canvas: CanvasView { model.canvas }

    var body: some View {
        let _ = model.revision
        let drawing = canvas.drawing
        let rows = LayersRows.build(drawing, query: query, collapsed: collapsed)
        VStack(spacing: 0) {
            header(drawing)
            searchField
            if reordering {
                reorderList(drawing)
            } else {
                List {
                    ForEach(rows) { row in
                        switch row.kind {
                        case .layer(let id): layerRow(id, drawing)
                        case .shape(let id): objectRow(id, isShape: true, drawing)
                        case .connector(let id): objectRow(id, isShape: false, drawing)
                        }
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
            footer(drawing)
        }
        .alert(renaming?.isLayer == true ? "Rename Layer" : "Rename Object", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
            TextField("Name", text: $renameText)
            Button("Rename") { commitRename() }
            Button("Cancel", role: .cancel) { renaming = nil }
        }
        .confirmationDialog("Delete this layer and everything on it?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }), titleVisibility: .visible) {
            Button("Delete Layer", role: .destructive) { if let id = deleting { canvas.deleteLayer(id) }; deleting = nil }
            Button("Cancel", role: .cancel) { deleting = nil }
        }
    }

    // MARK: Pieces

    private func header(_ d: Drawing) -> some View {
        HStack(spacing: 4) {
            Text("Layers").font(.system(size: 13, weight: .semibold)).foregroundStyle(Color(Tok.textSecondary))
            Spacer()
            Button { reordering.toggle() } label: {
                Image(systemName: reordering ? "checkmark" : "arrow.up.arrow.down").frame(width: 44, height: 44)
            }
            .accessibilityLabel(reordering ? "Done reordering" : "Reorder layers")
            .disabled(d.layers.count < 2 && !reordering)
            Button { canvas.addLayer() } label: { Image(systemName: "plus").frame(width: 44, height: 44) }
                .accessibilityLabel("Add layer")
        }
        .foregroundStyle(Color(Tok.iconDefault))
        .padding(.leading, 16).padding(.trailing, 4)
    }

    private var searchField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass").foregroundStyle(Color(Tok.textSecondary))
            TextField("Search", text: $query)
                .textInputAutocapitalization(.never).autocorrectionDisabled()
            if !query.isEmpty {
                Button { query = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(Color(Tok.textSecondary)) }
            }
        }
        .padding(.horizontal, 10).frame(height: 40)
        .background(Color(Tok.fieldBG), in: RoundedRectangle(cornerRadius: Tok.Radius.field))
        .padding(.horizontal, 12).padding(.bottom, 6)
    }

    private func footer(_ d: Drawing) -> some View {
        let n = d.shapes.count + d.connectors.count
        return Text("\(n) object\(n == 1 ? "" : "s") · \(canvas.selection.count) selected")
            .font(.system(size: 12)).foregroundStyle(Color(Tok.textSecondary))
            .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 16).padding(.vertical, 10)
    }

    private func reorderList(_ d: Drawing) -> some View {
        List {
            ForEach(Array(d.layers.reversed())) { l in
                HStack {
                    Image(systemName: "square.3.layers.3d").frame(width: 22)
                    Text(l.name).lineLimit(1)
                }
                .frame(minHeight: 44)
                .foregroundStyle(Color(Tok.textPrimary))
            }
            .onMove { from, to in
                // The list shows front first; the drawing stores back first.
                var order = Array(d.layers.reversed().map(\.id))
                order.move(fromOffsets: from, toOffset: to)
                guard let moved = from.first.map({ d.layers.reversed()[$0].id }), let at = order.firstIndex(of: moved) else { return }
                canvas.moveLayer(moved, toIndex: d.layers.count - 1 - at)
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .environment(\.editMode, .constant(.active))
    }

    private func layerRow(_ id: UUID, _ d: Drawing) -> some View {
        let layer = d.layer(id)
        let active = canvas.activeLayerID == id
        let open = !collapsed.contains(id) || !query.isEmpty
        let layerIndex = d.layers.firstIndex { $0.id == id } ?? 0
        return HStack(spacing: 2) {
            Button {
                if collapsed.contains(id) { collapsed.remove(id) } else { collapsed.insert(id) }
            } label: {
                Image(systemName: open ? "chevron.down" : "chevron.right").font(.system(size: 11, weight: .bold))
                    .frame(width: 30, height: 44)
            }
            .buttonStyle(.plain).foregroundStyle(Color(Tok.textSecondary))
            .accessibilityLabel(open ? "Collapse layer" : "Expand layer")
            Image(systemName: "square.3.layers.3d").frame(width: 22)
            Text(layer?.name ?? "").font(.system(size: 15, weight: active ? .semibold : .medium)).lineLimit(1)
                .opacity(layer?.visible == false ? 0.5 : 1)
                .padding(.leading, 6)
            Spacer(minLength: 4)
            Button { canvas.setLayer(id, visible: !(layer?.visible ?? true)) } label: {
                Image(systemName: layer?.visible == false ? "eye.slash" : "eye").frame(width: 44, height: 44)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(layer?.visible == false ? "Show \(layer?.name ?? "layer")" : "Hide \(layer?.name ?? "layer")")
            Button { canvas.setLayer(id, locked: !(layer?.locked ?? false)) } label: {
                Image(systemName: layer?.locked == true ? "lock.fill" : "lock.open").frame(width: 44, height: 44)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(layer?.locked == true ? "Unlock \(layer?.name ?? "layer")" : "Lock \(layer?.name ?? "layer")")
        }
        .foregroundStyle(Color(Tok.textPrimary))
        .frame(minHeight: 44)
        .contentShape(Rectangle())
        .onTapGesture { canvas.selection = []; canvas.setActiveLayer(id) }
        .listRowBackground(active ? Color(Tok.accent).opacity(0.14) : Color.clear)
        .listRowInsets(EdgeInsets(top: 0, leading: 6, bottom: 0, trailing: 6))
        .contextMenu {
            Button("Rename", systemImage: "pencil") { renameText = layer?.name ?? ""; renaming = LayerRename(id: id, isLayer: true) }
            Button("Make Active", systemImage: "scope") { canvas.setActiveLayer(id) }
            Button("Move Selection Here", systemImage: "arrow.right.square") { canvas.moveSelection(toLayer: id) }
                .disabled(canvas.selection.isEmpty)
            Divider()
            Button("Bring Forward", systemImage: "arrow.up") { canvas.moveLayer(id, up: true) }
                .disabled(layerIndex >= d.layers.count - 1)
            Button("Send Backward", systemImage: "arrow.down") { canvas.moveLayer(id, up: false) }
                .disabled(layerIndex == 0)
            Divider()
            Button("Delete Layer", systemImage: "trash", role: .destructive) { deleting = id }
                .disabled(d.layers.count < 2)
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button(role: .destructive) { deleting = id } label: { Label("Delete", systemImage: "trash") }
                .disabled(d.layers.count < 2)
        }
    }

    private func objectRow(_ id: UUID, isShape: Bool, _ d: Drawing) -> some View {
        let shape = isShape ? d.shapes.first { $0.id == id } : nil
        let conn = isShape ? nil : d.connectors.first { $0.id == id }
        let name = shape?.displayName ?? conn?.displayName ?? ""
        let locked = shape?.locked ?? conn?.locked ?? false
        let layer = shape?.layer ?? conn?.layer ?? UUID()
        let selected = canvas.selection.contains(id)
        let symbol = shape.map { LayersRows.symbol(for: $0.kind) } ?? "arrow.up.right"
        return HStack(spacing: 8) {
            Image(systemName: symbol).frame(width: 22)
                .foregroundStyle(selected ? Color(Tok.onAccent) : Color(Tok.accent).opacity(0.9))
            Text(name).font(.system(size: 14)).lineLimit(1)
            Spacer(minLength: 4)
            Button { canvas.setObject(id, locked: !locked) } label: {
                Image(systemName: locked ? "lock.fill" : "lock.open").frame(width: 44, height: 44)
                    .opacity(locked ? 1 : 0.45)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(locked ? "Unlock \(name)" : "Lock \(name)")
        }
        .foregroundStyle(selected ? Color(Tok.onAccent) : Color(Tok.textPrimary))
        .frame(minHeight: 44)
        .contentShape(Rectangle())
        .onTapGesture {
            if selected && canvas.selection.count > 1 { canvas.selection.remove(id) }
            else if selected { canvas.selection = [] }
            else { canvas.selection = [id] }
        }
        .listRowBackground(selected ? RoundedRectangle(cornerRadius: 7).fill(Color(Tok.selectionRow)).padding(.horizontal, 4) : nil)
        .listRowInsets(EdgeInsets(top: 0, leading: 34, bottom: 0, trailing: 6))
        .contextMenu {
            if isShape { Button("Rename", systemImage: "pencil") { renameText = name; renaming = LayerRename(id: id, isLayer: false) } }
            Button(selected ? "Deselect" : "Add to Selection", systemImage: "checkmark.circle") {
                if selected { canvas.selection.remove(id) } else { canvas.selection.insert(id) }
            }
            if isShape {
                Button("Bring Forward", systemImage: "arrow.up") { nudge(id, layer: layer, up: true, d) }
                Button("Send Backward", systemImage: "arrow.down") { nudge(id, layer: layer, up: false, d) }
                Menu("Move to Layer", systemImage: "square.3.layers.3d") {
                    ForEach(Array(d.layers.reversed())) { l in
                        Button(l.name) { canvas.moveObject(id, layer: l.id, relativeTo: nil, above: true) }
                            .disabled(l.id == layer)
                    }
                }
            }
        }
    }

    // MARK: Actions

    private func commitRename() {
        guard let r = renaming else { return }
        if r.isLayer { canvas.renameLayer(r.id, to: renameText) } else { canvas.renameObject(r.id, to: renameText) }
        renaming = nil
    }

    /// Moves a shape one step toward the front or back among the shapes of its layer.
    private func nudge(_ id: UUID, layer: UUID, up: Bool, _ d: Drawing) {
        let same = d.shapes.filter { $0.layer == layer }.map(\.id)
        guard let i = same.firstIndex(of: id) else { return }
        let j = up ? i + 1 : i - 1
        guard same.indices.contains(j) else { return }
        canvas.moveObject(id, layer: layer, relativeTo: same[j], above: up)
    }
}

/// The flattened rows of the layers list.
enum LayersRows {
    struct Row: Identifiable {
        enum Kind: Hashable { case layer(UUID), shape(UUID), connector(UUID) }
        let kind: Kind
        var id: Kind { kind }
    }

    /// Layers front first, each followed by its shapes and connectors (front first), filtered by `query`.
    static func build(_ d: Drawing, query: String, collapsed: Set<UUID>) -> [Row] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        var out: [Row] = []
        for layer in d.layers.reversed() {
            var kids: [Row] = []
            for s in d.shapes.reversed() where s.layer == layer.id { kids.append(Row(kind: .shape(s.id))) }
            for c in d.connectors.reversed() where c.layer == layer.id { kids.append(Row(kind: .connector(c.id))) }
            if !q.isEmpty {
                let layerMatches = layer.name.lowercased().contains(q)
                kids = kids.filter { r in
                    if layerMatches { return true }
                    switch r.kind {
                    case .shape(let id): return d.shapes.first { $0.id == id }?.displayName.lowercased().contains(q) ?? false
                    case .connector(let id): return d.connectors.first { $0.id == id }?.displayName.lowercased().contains(q) ?? false
                    case .layer: return false
                    }
                }
                if !layerMatches && kids.isEmpty { continue }
            }
            out.append(Row(kind: .layer(layer.id)))
            if q.isEmpty && collapsed.contains(layer.id) { continue }
            out += kids
        }
        return out
    }

    static func symbol(for kind: ShapeKind) -> String {
        switch kind {
        case .rectangle: return "rectangle"
        case .rounded: return "app"
        case .ellipse: return "circle"
        case .diamond: return "diamond"
        case .triangle: return "triangle"
        case .text: return "textformat"
        case .path: return "scribble"
        }
    }
}
