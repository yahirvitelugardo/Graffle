import SwiftUI
import UniformTypeIdentifiers

@main
struct GraffleApp: App {
    var body: some Scene {
        DocumentGroup(newDocument: GrafDocument()) { file in
            EditorView(document: file.$document, fileName: file.fileURL?.deletingPathExtension().lastPathComponent ?? "Diagram")
        }
        DocumentGroupLaunchScene("Graffle") {
            NewDocumentButton("New Diagram")
        } background: {
            LinearGradient(colors: [Color(Tok.windowBG), Color(Tok.canvasBG)], startPoint: .top, endPoint: .bottom)
        }
    }
}
