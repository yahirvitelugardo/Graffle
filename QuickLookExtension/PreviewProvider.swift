import AppKit
import OSLog
import QuickLookUI
import UniformTypeIdentifiers

/// Finder's space-bar preview for `.graf` files. Quick Look launches this extension, hands it the file, and shows
/// the PDF it returns. The drawing itself is done by `DiagramPreview`, the same code the app uses.
@objc(PreviewProvider)
final class PreviewProvider: QLPreviewProvider, QLPreviewingController {
    /// To follow what the extension does: `log show --last 5m --predicate 'subsystem == "mx.graffle.app.quicklook"'`.
    private let log = Logger(subsystem: "mx.graffle.app.quicklook", category: "preview")

    func providePreview(for request: QLFilePreviewRequest) async throws -> QLPreviewReply {
        do {
            // Drawing builds AppKit views, which must happen on the main thread.
            let result = try await MainActor.run { try DiagramPreview.render(fileAt: request.fileURL) }
            log.notice("Previewed a diagram: \(result.pdf.count, privacy: .public) bytes of PDF, \(Int(result.size.width), privacy: .public) x \(Int(result.size.height), privacy: .public) pt, empty: \(result.isEmpty, privacy: .public)")
            let reply = QLPreviewReply(dataOfContentType: .pdf, contentSize: result.size) { _ in result.pdf }
            reply.title = request.fileURL.deletingPathExtension().lastPathComponent
            return reply
        } catch {
            log.error("Could not preview the file: \(error.localizedDescription, privacy: .public)")
            throw error
        }
    }
}
