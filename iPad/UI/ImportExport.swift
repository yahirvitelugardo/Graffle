import SwiftUI
import UIKit
import UniformTypeIdentifiers

// MARK: - Import

struct ImportMenu: View {
    @ObservedObject var model: EditorModel
    @StateObject private var flow: ImportFlow

    init(model: EditorModel) {
        self.model = model
        _flow = StateObject(wrappedValue: ImportFlow(model: model))
    }

    var body: some View {
        Menu {
            Button("Import SVG…", systemImage: "photo") { flow.start(.svg) }
            Button("Import STL as Technical Views…", systemImage: "cube") { flow.start(.stl) }
            Divider()
            Button("Architecture Diagram from Folder…", systemImage: "square.stack.3d.up") { flow.start(.architecture) }
            Button("Class Diagram from Folder…", systemImage: "list.bullet.rectangle") { flow.start(.classes) }
            Button("ER Diagram from SQLite or SQL…", systemImage: "cylinder.split.1x2") { flow.start(.database) }
            Divider()
            Button("Generate Code…", systemImage: "chevron.left.forwardslash.chevron.right") { flow.startCodeGen() }
                .disabled(model.canvas.drawing.source == nil)
        } label: {
            Image(systemName: "square.and.arrow.down").frame(minWidth: 36, minHeight: 36)
        }
        .accessibilityLabel("Import")
        .importFlow(flow)
    }
}

// MARK: - Export

private struct ShareItem: Identifiable {
    let id = UUID()
    let url: URL
}

struct ExportMenu: View {
    @ObservedObject var model: EditorModel
    @State private var shareItem: ShareItem?
    @State private var problem: String?

    var body: some View {
        let empty = model.canvas.drawing.contentBounds == nil
        Menu {
            Menu("PNG Image", systemImage: "photo") {
                ForEach([1, 2, 3], id: \.self) { s in
                    Button("\(s)×") { share(ext: "png", data: model.canvas.pngData(scale: CGFloat(s))) }
                }
            }.disabled(empty)
            Button("PDF", systemImage: "doc.richtext") { share(ext: "pdf", data: model.canvas.pdfData()) }.disabled(empty)
            Button("SVG", systemImage: "scribble.variable") { share(ext: "svg", data: model.canvas.svgData()) }.disabled(empty)
            Button("Graffle Document (.graf)", systemImage: "square.and.pencil") { share(ext: "graf", data: grafData()) }
            Divider()
            Button("Copy as PNG", systemImage: "doc.on.doc") { copyPNG() }.disabled(empty)
            Button("Print…", systemImage: "printer") { printDiagram() }.disabled(empty)
        } label: {
            Image(systemName: "square.and.arrow.up").frame(minWidth: 36, minHeight: 36)
        }
        .accessibilityLabel("Export")
        .sheet(item: $shareItem) { item in
            ShareSheet(items: [item.url]).presentationDetents([.medium, .large])
        }
        .alert("Couldn't export", isPresented: Binding(get: { problem != nil }, set: { if !$0 { problem = nil } })) {
            Button("OK", role: .cancel) {}
        } message: { Text(problem ?? "") }
    }

    private func grafData() -> Data? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try? encoder.encode(model.canvas.drawing)
    }

    /// Writes `data` to a temporary file (so the share sheet offers a properly named file) and shows the share sheet.
    private func share(ext: String, data: Data?) {
        guard let data else { problem = "The diagram couldn't be rendered. Is the canvas empty?"; return }
        do {
            let dir = FileManager.default.temporaryDirectory.appendingPathComponent("graffle-export-\(UUID().uuidString)", isDirectory: true)
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let url = dir.appendingPathComponent("Diagram.\(ext)")
            try data.write(to: url, options: .atomic)
            shareItem = ShareItem(url: url)
        } catch {
            problem = error.localizedDescription
        }
    }

    private func copyPNG() {
        guard let data = model.canvas.pngData(scale: 2), let image = UIImage(data: data) else { problem = "The diagram couldn't be rendered."; return }
        UIPasteboard.general.image = image
    }

    private func printDiagram() {
        guard let pdf = model.canvas.pdfData() else { problem = "The diagram couldn't be rendered."; return }
        let info = UIPrintInfo(dictionary: nil)
        info.outputType = .general
        info.jobName = "Diagram"
        let controller = UIPrintInteractionController.shared
        controller.printInfo = info
        controller.printingItem = pdf
        controller.present(animated: true, completionHandler: nil)
    }
}

/// The system share sheet (AirDrop, Save to Files, Messages…).
struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController { UIActivityViewController(activityItems: items, applicationActivities: nil) }
    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
