import SwiftUI
import UniformTypeIdentifiers

extension UTType {
    /// A Graffle diagram (`.graf`), the same file the Mac app reads and writes.
    static let graf = UTType(exportedAs: "mx.graffle.diagram", conformingTo: .json)
}

struct GrafDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.graf] }
    static var writableContentTypes: [UTType] { [.graf] }

    var drawing: Drawing

    init(drawing: Drawing = Drawing()) { self.drawing = drawing }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else { throw CocoaError(.fileReadCorruptFile) }
        if data.isEmpty { drawing = Drawing(); return }       // a freshly made, still empty file
        do { drawing = try JSONDecoder().decode(Drawing.self, from: data) }
        catch { throw CocoaError(.fileReadCorruptFile, userInfo: [NSLocalizedDescriptionKey: "This isn't a Graffle diagram, or it is damaged."]) }
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return FileWrapper(regularFileWithContents: try encoder.encode(drawing))
    }
}
