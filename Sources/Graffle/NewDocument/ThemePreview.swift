import AppKit

/// Draws small pictures of what a diagram looks like, using the same code that draws real documents.
enum ThemePreview {
    /// Which sample diagram to draw.
    enum Sample: Hashable {
        case architecture, classes, starter(Starter)
        var key: String { if case .starter(let s) = self { return "starter-" + s.rawValue }; return self == .architecture ? "architecture" : "classes" }
    }

    /// A tiny architecture: an app and an extension and tests, two modules they use, and a package.
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

    /// A tiny class diagram: a protocol, a base class, a class that extends and implements them, and a struct that uses them.
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

    nonisolated(unsafe) private static var cache: [Data: NSImage] = [:]

    /// A picture of `sample` drawn in `theme`. Must be called on the main thread.
    static func image(for theme: ThemeDefinition, sample: Sample = .architecture) -> NSImage? {
        var key = theme.encoded()
        key.append(Data(sample.key.utf8))
        if let hit = cache[key] { return hit }
        var drawing: Drawing
        switch sample {
        case .architecture: drawing = architectureSample()
        case .classes: drawing = classSample()
        case .starter(let s): drawing = Starters.drawing(s)
        }
        theme.apply(to: &drawing)
        let canvas = CanvasView(frame: NSRect(origin: .zero, size: CanvasView.canvasSize))
        canvas.load(drawing)
        canvas.showGrid = false
        guard let png = canvas.pngData(), let image = NSImage(data: png) else { return nil }
        cache[key] = image
        return image
    }
}
