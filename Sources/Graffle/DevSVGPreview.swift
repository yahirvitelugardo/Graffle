import AppKit
import WebKit

/// Dev helper: `Graffle --svg-to-png in.svg out.png` renders an SVG with WebKit (a real browser engine,
/// unlike NSImage's SVG decoder, which ignores <text> and filters) so exports can be checked visually.
final class SVGSnapshotter: NSObject, WKNavigationDelegate {
    private let web: WKWebView
    private let output: URL

    init(svg: URL, output: URL, size: CGSize) {
        web = WKWebView(frame: CGRect(origin: .zero, size: size))
        self.output = output
        super.init()
        web.navigationDelegate = self
        web.loadFileURL(svg, allowingReadAccessTo: svg.deletingLastPathComponent())
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        let cfg = WKSnapshotConfiguration()
        webView.takeSnapshot(with: cfg) { [output] image, _ in
            if let tiff = image?.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff) {
                try? rep.representation(using: .png, properties: [:])?.write(to: output)
            }
            exit(0)
        }
    }
}
