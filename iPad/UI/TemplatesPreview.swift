import SwiftUI
import UIKit

/// Which sample picture stands for a template or a theme.
enum TemplateSample: Hashable {
    case architecture, classes, starter(Starter)
    var key: String { if case .starter(let s) = self { return "starter-" + s.rawValue }; return self == .architecture ? "architecture" : "classes" }
}

/// Draws small pictures of a diagram in a theme, with the same code that draws real documents.
@MainActor
final class TemplatePreviewRenderer {
    static let shared = TemplatePreviewRenderer()
    private var cache: [Data: UIImage] = [:]
    private lazy var canvas: CanvasView = {
        let c = CanvasView(frame: CGRect(x: 0, y: 0, width: 1000, height: 700))
        c.showGrid = false
        return c
    }()

    static func architectureSample() -> Drawing {
        var g = ArchitectureGraph(title: "Preview", source: "Sample")
        g.add(ArchitectureNode(id: "app", name: "App", kind: .app, detail: "iOS app", container: "S"))
        g.add(ArchitectureNode(id: "widget", name: "Widget", kind: .appExtension, detail: "Extension", container: "S"))
        g.add(ArchitectureNode(id: "tests", name: "Tests", kind: .tests, detail: "Unit tests", container: "S"))
        g.add(ArchitectureNode(id: "feature", name: "Feature", kind: .framework, detail: "Framework", container: "S"))
        g.add(ArchitectureNode(id: "core", name: "Core", kind: .library, detail: "Library", container: "S"))
        g.add(ArchitectureNode(id: "pkg", name: "Network", kind: .externalPackage, detail: "Swift package", container: "P"))
        g.connect("app", "feature", .dependsOn)
        g.connect("widget", "core", .dependsOn)
        g.connect("tests", "core", .dependsOn)
        g.connect("feature", "pkg", .package)
        g.connect("core", "pkg", .package)
        return ArchitectureDrawing.build(g, decorations: false)
    }

    static func classSample() -> Drawing {
        var g = ClassGraph(title: "Preview", source: "Sample")
        g.types = [
            TypeInfo(name: "Shape", kind: .protocolType, language: .swift, properties: ["~ area: Double"], methods: ["~ draw()"]),
            TypeInfo(name: "Base", kind: .classType, language: .swift, properties: ["~ id: Int"], methods: ["~ reset()"]),
            TypeInfo(name: "Circle", kind: .classType, language: .swift, supertypes: ["Base", "Shape"], properties: ["~ radius: Double"], methods: ["~ draw()"]),
            TypeInfo(name: "Canvas", kind: .structType, language: .swift, properties: ["~ shapes: [Shape]"], methods: ["~ render()"]),
        ]
        g.relations = [
            TypeRelation(from: "Circle", to: "Base", kind: .inherits),
            TypeRelation(from: "Circle", to: "Shape", kind: .implements),
            TypeRelation(from: "Canvas", to: "Shape", kind: .association),
        ]
        return ClassDrawing.build(g, options: ClassOptions(), decorations: false)
    }

    func image(for theme: ThemeDefinition, sample: TemplateSample) async -> UIImage? {
        var key = theme.encoded()
        key.append(Data(sample.key.utf8))
        if let hit = cache[key] { return hit }
        await Task.yield()                                       // pictures take a moment each: let the list draw first
        if let hit = cache[key] { return hit }
        var drawing: Drawing
        switch sample {
        case .architecture: drawing = Self.architectureSample()
        case .classes: drawing = Self.classSample()
        case .starter(let s): drawing = Starters.drawing(s)
        }
        theme.apply(to: &drawing)
        canvas.load(drawing)
        guard let png = canvas.pngData(scale: 1), let image = UIImage(data: png) else { return nil }
        cache[key] = image
        return image
    }
}

/// A sample picture on a small white page; with no sample it is a blank page.
struct TemplatePreviewView: View {
    var theme: ThemeDefinition = ThemeLibrary.clean
    var sample: TemplateSample?
    @State private var image: UIImage?

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8).fill(Color.white)
            if let image {
                Image(uiImage: image).resizable().scaledToFit().padding(6)
            } else if sample != nil {
                ProgressView()
            }
        }
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color(Tok.cardOutline), lineWidth: 1))
        .aspectRatio(4.0 / 3.0, contentMode: .fit)
        .task(id: (sample?.key ?? "") + theme.id) {
            guard let sample else { return }
            image = nil
            image = await TemplatePreviewRenderer.shared.image(for: theme, sample: sample)
        }
    }
}
