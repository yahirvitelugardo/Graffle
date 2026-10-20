import AppKit

/// The user's own shapes ("My Shapes"): any selection can be saved and put back on the canvas later.
/// They live in one JSON file in Application Support, shared by every document.
final class ShapeLibrary {
    static let myShapes = "My Shapes"
    static let shared = ShapeLibrary(file: ShapeLibrary.defaultFile)
    static let didChange = Notification.Name("GraffleShapeLibraryChanged")

    private struct Saved: Codable { var id: String; var name: String; var drawing: Drawing }

    private let file: URL?
    private(set) var custom: [LibraryItem] = []

    static var defaultFile: URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("Graffle", isDirectory: true).appendingPathComponent("ShapeLibrary.json")
    }

    init(file: URL?) {
        self.file = file
        load()
    }

    var allItems: [LibraryItem] { custom + ShapeCatalog.items }

    func item(_ id: String) -> LibraryItem? { allItems.first { $0.id == id } }

    /// Saves objects as a new library entry and returns it. Connectors between the chosen shapes come along.
    @discardableResult
    func add(name: String, drawing: Drawing) -> LibraryItem? {
        guard !drawing.shapes.isEmpty else { return nil }
        var sub = drawing
        sub.source = nil
        sub.theme = nil
        let box = sub.shapes.map(\.worldBounds).reduce(nil) { acc, f in acc.map { $0.union(f) } ?? f } ?? .zero
        let clean = name.trimmingCharacters(in: .whitespacesAndNewlines)
        var item = LibraryItem(id: "custom-" + UUID().uuidString, name: clean.isEmpty ? "Shape \(custom.count + 1)" : clean,
                               category: Self.myShapes, origin: .custom, size: box.size)
        item.usesCurrentStyle = false
        item.custom = sub
        custom.insert(item, at: 0)
        save()
        return item
    }

    func rename(_ id: String, to name: String) {
        let clean = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty, let i = custom.firstIndex(where: { $0.id == id }) else { return }
        custom[i].name = clean
        save()
    }

    func remove(_ id: String) {
        custom.removeAll { $0.id == id }
        save()
    }

    private func load() {
        guard let file, let data = try? Data(contentsOf: file), let saved = try? JSONDecoder().decode([Saved].self, from: data) else { return }
        custom = saved.map { s in
            let box = s.drawing.shapes.map(\.worldBounds).reduce(nil) { acc, f in acc.map { $0.union(f) } ?? f } ?? .zero
            var item = LibraryItem(id: s.id, name: s.name, category: Self.myShapes, origin: .custom, size: box.size)
            item.usesCurrentStyle = false
            item.custom = s.drawing
            return item
        }
    }

    private func save() {
        defer { NotificationCenter.default.post(name: Self.didChange, object: self) }
        guard let file else { return }
        let saved = custom.compactMap { i in i.custom.map { Saved(id: i.id, name: i.name, drawing: $0) } }
        do {
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(saved).write(to: file, options: .atomic)
        } catch {
            NSLog("Graffle: could not save the shape library: \(error.localizedDescription)")
        }
    }
}
