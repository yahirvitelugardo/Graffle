import AppKit

/// Draws a `.graf` file as a vector PDF for Quick Look (the preview Finder shows when you press the space bar).
/// This file is compiled into both the app and the Quick Look extension, and reuses the canvas's own drawing code,
/// so what the preview shows is exactly what the editor and the exporters draw.
enum DiagramPreview {
    struct Result {
        var pdf: Data
        /// The diagram's size in points; Quick Look sizes its window from this.
        var size: CGSize
        var isEmpty: Bool
    }

    /// The preview window never needs to be bigger than this; the PDF itself stays vector at any zoom.
    static let largestWindow = CGSize(width: 1200, height: 900)

    static func render(fileAt url: URL) throws -> Result {
        let data = try Data(contentsOf: url)
        guard let drawing = try? JSONDecoder().decode(Drawing.self, from: data) else {
            throw CocoaError(.fileReadCorruptFile, userInfo: [NSLocalizedDescriptionKey: "This isn't a Graffle diagram, or it is damaged."])
        }
        return render(drawing)
    }

    /// Must be called on the main thread (it builds an AppKit view); it stops with a clear error otherwise.
    static func render(_ drawing: Drawing) -> Result {
        MainActor.assumeIsolated {
            let canvas = CanvasView(frame: NSRect(origin: .zero, size: CanvasView.canvasSize))
            canvas.load(drawing)
            canvas.showGrid = false
            if let pdf = canvas.pdfData(), let bounds = canvas.exportBounds() {
                return Result(pdf: pdf, size: fit(bounds.size), isEmpty: false)
            }
            return emptyPlaceholder()
        }
    }

    /// The diagram's size scaled down (never up) to fit a sensible preview window.
    static func fit(_ size: CGSize) -> CGSize {
        guard size.width > 0, size.height > 0 else { return CGSize(width: 480, height: 320) }
        let k = min(1, largestWindow.width / size.width, largestWindow.height / size.height)
        return CGSize(width: max(size.width * k, 160), height: max(size.height * k, 120))
    }

    /// What an empty diagram shows, instead of a blank page that looks like a failure.
    static func emptyPlaceholder() -> Result {
        let size = CGSize(width: 480, height: 320)
        let data = NSMutableData()
        var box = CGRect(origin: .zero, size: size)
        guard let consumer = CGDataConsumer(data: data), let ctx = CGContext(consumer: consumer, mediaBox: &box, nil) else {
            return Result(pdf: Data(), size: size, isEmpty: true)
        }
        ctx.beginPDFPage(nil)
        ctx.setFillColor(CGColor(gray: 1, alpha: 1))
        ctx.fill(box)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
        let text = NSAttributedString(string: "Empty diagram", attributes: [
            .font: NSFont.systemFont(ofSize: 22, weight: .medium), .foregroundColor: NSColor(white: 0.55, alpha: 1),
        ])
        let sz = text.size()
        text.draw(at: CGPoint(x: (size.width - sz.width) / 2, y: (size.height - sz.height) / 2))
        NSGraphicsContext.restoreGraphicsState()
        ctx.endPDFPage()
        ctx.closePDF()
        return Result(pdf: data as Data, size: size, isEmpty: true)
    }
}
