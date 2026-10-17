import AppKit
import UniformTypeIdentifiers

/// A Graffle diagram. Each open document has its own window, canvas, inspector and undo history.
/// Reading, saving, Open Recent, Revert, the unsaved-changes sheets and Finder's double-click all come from NSDocument.
@objc(GraffleDocument)
final class GraffleDocument: NSDocument {
    /// The type identifier declared in Info.plist for `.graf` files.
    static let diagramType = "mx.graffle.diagram"

    /// What was last read from disk; the window shows it as soon as it exists.
    private var loaded = Drawing()
    /// Set when the document was made from an SVG: it opens as a new, unsaved diagram with the SVG's name.
    private var importedName: String?
    private var importNotice: String?

    var windowController: DocumentWindowController? { windowControllers.first as? DocumentWindowController }
    var canvas: CanvasView? { windowController?.canvas }

    override class var autosavesInPlace: Bool { false }

    // MARK: Windows

    override func makeWindowControllers() {
        let wc = DocumentWindowController()
        addWindowController(wc)
        wc.canvas.load(loaded)                      // after the window is attached, so undo goes to this document
        updateChangeCount(.changeCleared)

        if importedName != nil {
            // An opened SVG is a new diagram, not a file that "Save" would write back into the SVG.
            fileURL = nil
            fileType = GraffleDocument.diagramType
            updateChangeCount(.changeDone)          // nothing on disk yet: it counts as unsaved
        }
        if let note = importNotice {
            importNotice = nil
            DispatchQueue.main.async { [weak wc] in
                GraffleDocument.warn("Some parts were left out", "Graffle imports simple SVG shapes, paths and text.",
                                     skipped: note, in: wc?.window)
            }
        }
    }

    override var displayName: String! {
        get { (fileURL == nil ? importedName : nil) ?? super.displayName }
        set { super.displayName = newValue }
    }

    // MARK: Reading and writing

    override func data(ofType typeName: String) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(canvas?.drawing ?? loaded)
    }

    override func read(from data: Data, ofType typeName: String) throws {
        let drawing: Drawing
        do { drawing = try JSONDecoder().decode(Drawing.self, from: data) }
        catch { throw CocoaError(.fileReadCorruptFile, userInfo: [NSLocalizedDescriptionKey: "This isn't a Graffle diagram, or it is damaged."]) }
        show(drawing)
    }

    override func read(from url: URL, ofType typeName: String) throws {
        guard url.pathExtension.lowercased() == "svg" || typeName == UTType.svg.identifier else {
            try super.read(from: url, ofType: typeName)
            return
        }
        let name = url.deletingPathExtension().lastPathComponent
        let result = try SVGImport.parse(Data(contentsOf: url), name: name)
        guard !result.shapes.isEmpty else {
            throw CocoaError(.fileReadCorruptFile, userInfo: [NSLocalizedDescriptionKey: "This SVG has no shapes, paths or text that Graffle can read."])
        }
        var d = Drawing()
        let placed = result.placed(at: CGPoint(x: 100, y: 100)).fitted(into: CGSize(width: 3960, height: 2960))
        d.layers = placed.layers
        d.shapes = placed.shapes
        importedName = name
        importNotice = result.skippedSummary
        show(d)
    }

    /// Keeps `drawing` as the document's contents, and shows it if the window already exists (Revert to Saved).
    private func show(_ drawing: Drawing) {
        loaded = drawing
        canvas?.load(drawing)
    }

    // MARK: Alerts

    static func warn(_ title: String, _ detail: String, skipped: String?, in window: NSWindow?) {
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = title
        alert.informativeText = detail + (skipped.map { "\n\nLeft out: \($0)." } ?? "")
        if let window { alert.beginSheetModal(for: window) } else { alert.runModal() }
    }
}
