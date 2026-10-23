import SwiftUI
import UniformTypeIdentifiers

extension EditorModel {
    static let libraryDragType = "mx.graffle.library-item"

    /// Puts a library item on the canvas, in the middle of the view or at `point`.
    func insertLibraryItem(_ item: LibraryItem, at point: CGPoint? = nil) {
        let number = canvas.drawing.shapes.filter { $0.name == item.name }.count + 1
        let k = item.realSize != nil ? (canvas.drawing.scale ?? .standard).pointsPerCentimeter : 1          // real-world parts follow the drawing scale
        let drawing = item.drawing(layer: canvas.activeLayerID, style: canvas.defaultStyle, number: number, pointsPerCentimeter: k)
        canvas.placeDrawing(drawing, named: "Add \(item.name)", near: point ?? canvas.visibleCenter, themed: item.usesCurrentStyle || item.circuit != nil)
    }

    /// Lets shapes dragged from the library land on the canvas.
    func installLibraryDrop() {
        canvas.onLibraryDrop = { [weak self] id, point in
            if let item = ShapeLibrary.shared.item(id) { self?.insertLibraryItem(item, at: point) }
        }
    }
}

/// The shape library: search, collapsible categories of thumbnails, and "My Shapes".
struct LibraryTab: View {
    @ObservedObject var model: EditorModel

    @AppStorage("ui.library.collapsed.v1") private var collapsedRaw = ""
    @State private var query = ""
    @State private var tick = 0
    @State private var saving = false
    @State private var saveName = ""
    @State private var renaming: LibraryItem?
    @State private var renameText = ""

    private var collapsed: Set<String> { Set(collapsedRaw.split(separator: "|").map(String.init)) }
    private var searching: Bool { !query.trimmingCharacters(in: .whitespaces).isEmpty }
    private var canSave: Bool { !model.canvas.selection.isEmpty }

    private func sections() -> [(title: String, items: [LibraryItem])] {
        let all = ShapeLibrary.shared.allItems.filter { ShapeCatalog.matches($0, query) }
        var out: [(title: String, items: [LibraryItem])] = []
        let mine = all.filter { $0.origin == .custom }
        if !mine.isEmpty { out.append((ShapeLibrary.myShapes, mine)) }
        for category in ShapeCatalog.categoryOrder {
            let items = all.filter { $0.category == category }
            if !items.isEmpty { out.append((category, items)) }
        }
        return out
    }

    var body: some View {
        let _ = tick
        let _ = model.revision
        let secs = sections()
        VStack(spacing: 0) {
            HStack {
                Text("Shape Library").font(.system(size: 13, weight: .semibold)).foregroundStyle(Color(Tok.textSecondary))
                Spacer()
                Button {
                    guard let sub = model.canvas.selectionDrawing() else { return }
                    saveName = sub.shapes.count == 1 ? sub.shapes[0].displayName : "My Shape"
                    saving = true
                } label: { Image(systemName: "plus").frame(width: 44, height: 44) }
                    .disabled(!canSave)
                    .accessibilityLabel("Save selection to library")
            }
            .foregroundStyle(Color(Tok.iconDefault))
            .padding(.leading, 16).padding(.trailing, 4)

            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").foregroundStyle(Color(Tok.textSecondary))
                TextField("Search shapes", text: $query).textInputAutocapitalization(.never).autocorrectionDisabled()
                if !query.isEmpty {
                    Button { query = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(Color(Tok.textSecondary)) }
                }
            }
            .padding(.horizontal, 10).frame(height: 40)
            .background(Color(Tok.fieldBG), in: RoundedRectangle(cornerRadius: Tok.Radius.field))
            .padding(.horizontal, 12).padding(.bottom, 6)

            if secs.isEmpty {
                Spacer()
                Text("No shapes match “\(query)”.").font(.system(size: 13)).foregroundStyle(Color(Tok.textSecondary))
                Spacer()
            } else {
                ScrollView {
                    LazyVStack(spacing: 0, pinnedViews: []) {
                        ForEach(secs, id: \.title) { section in
                            header(section.title, count: section.items.count)
                            if searching || !collapsed.contains(section.title) {
                                LazyVGrid(columns: [GridItem(.adaptive(minimum: 72, maximum: 96), spacing: 4)], spacing: 4) {
                                    ForEach(section.items) { item in cell(item) }
                                }
                                .padding(.horizontal, 8).padding(.bottom, 6)
                            }
                        }
                    }
                }
            }
            Text("Tap a shape, or drag it onto the canvas.")
                .font(.system(size: 11)).foregroundStyle(Color(Tok.textSecondary))
                .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 14).padding(.vertical, 10)
        }
        .onAppear { model.installLibraryDrop() }
        .onReceive(NotificationCenter.default.publisher(for: ShapeLibrary.didChange)) { _ in tick &+= 1 }
        .alert("Save to Shape Library", isPresented: $saving) {
            TextField("Name", text: $saveName)
            Button("Save") {
                if let sub = model.canvas.selectionDrawing(), ShapeLibrary.shared.add(name: saveName, drawing: sub) != nil { query = "" }
            }
            Button("Cancel", role: .cancel) {}
        } message: { Text("The selected objects become a shape in “My Shapes”, ready to use in any diagram.") }
        .alert("Rename Shape", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
            TextField("Name", text: $renameText)
            Button("Rename") { if let it = renaming { ShapeLibrary.shared.rename(it.id, to: renameText) }; renaming = nil }
            Button("Cancel", role: .cancel) { renaming = nil }
        }
    }

    private func header(_ title: String, count: Int) -> some View {
        let open = searching || !collapsed.contains(title)
        return Button {
            guard !searching else { return }
            var c = collapsed
            if c.contains(title) { c.remove(title) } else { c.insert(title) }
            collapsedRaw = c.sorted().joined(separator: "|")
        } label: {
            HStack {
                Image(systemName: open ? "chevron.down" : "chevron.right").font(.system(size: 10, weight: .bold)).frame(width: 14)
                Text(title).font(.system(size: 13, weight: .semibold))
                Spacer()
                Text("\(count)").font(.system(size: 12))
            }
            .foregroundStyle(Color(Tok.textSecondary))
            .padding(.horizontal, 16).frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func cell(_ item: LibraryItem) -> some View {
        Button { model.insertLibraryItem(item) } label: {
            VStack(spacing: 4) {
                LibraryThumbnailView(item: item).frame(height: 38).padding(.horizontal, 6)
                Text(item.name).font(.system(size: 10.5)).foregroundStyle(Color(Tok.textSecondary))
                    .lineLimit(2).multilineTextAlignment(.center).frame(height: 28, alignment: .top)
            }
            .padding(.top, 8).padding(.horizontal, 2)
            .frame(maxWidth: .infinity, minHeight: 78)
            .contentShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(item.name)
        .onDrag {
            let provider = NSItemProvider()
            let data = Data(item.id.utf8)
            provider.registerDataRepresentation(forTypeIdentifier: EditorModel.libraryDragType, visibility: .all) { done in
                done(data, nil); return nil
            }
            provider.suggestedName = item.name
            return provider
        } preview: {
            Image(uiImage: LibraryThumbnail.image(item, size: CGSize(width: 64, height: 48), scheme: .light)).background(Color.white.opacity(0.9))
        }
        .contextMenu {
            Button("Add to Diagram", systemImage: "plus.square") { model.insertLibraryItem(item) }
            if item.origin == .custom {
                Button("Rename…", systemImage: "pencil") { renameText = item.name; renaming = item }
                Button("Delete from Library", systemImage: "trash", role: .destructive) { ShapeLibrary.shared.remove(item.id) }
            }
        }
    }
}
