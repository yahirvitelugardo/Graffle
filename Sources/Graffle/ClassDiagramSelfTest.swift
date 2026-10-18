import AppKit

/// Self-test steps for the class diagram: the source scanner, the importer, the drawing and the Reverse Engineering choice.
extension AppDelegate {
    func classDiagramSteps(tempDir: URL) -> [(String, () -> Bool)] {
        var steps: [(String, () -> Bool)] = []
        let fm = FileManager.default
        let root = tempDir.appendingPathComponent("classes")
        func write(_ rel: String, _ text: String) {
            let u = root.appendingPathComponent(rel)
            try? fm.createDirectory(at: u.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? text.write(to: u, atomically: true, encoding: .utf8)
        }
        let swift = """
        // class Commented { var ghost: Int }
        protocol Shape { var area: Double { get }; func draw() }
        class Base { var id: Int = 0; func reset() {} }
        final class Circle: Base, Shape, Hashable {
            let radius: Double
            private var cache: [Int] = []
            var area: Double { radius * radius }
            init(radius: Double) { self.radius = radius }
            func draw() { let s = "{ not a block"; print(s) }
            static func make(_ r: Double, scale: Double) -> Circle { Circle(radius: r) }
        }
        struct Canvas { var shapes: [Shape]; var owner: Circle? }
        enum Mode: String { case fast, slow(Int) }
        extension Circle: CustomStringConvertible { var description: String { "c" } }
        actor Store {}
        """
        let csharp = """
        namespace Demo
        {
            public interface IRepo<T> { T Find(int id); }
            public abstract class Entity { public int Id { get; set; } protected string name; }
            public class User : Entity, IRepo<User>
            {
                public string Email { get; set; }
                private int secret;
                public User(string email) { Email = email; }
                public User Find(int id) { return null; }
                public static void Reset() {}
            }
            public enum Role { Admin, Guest = 2 }
        }
        """
        let kotlin = """
        interface Greeter { fun greet(name: String): String }
        open class Person(val name: String, private val age: Int) : Greeter { override fun greet(name: String) = "hi" }
        data class Employee(val boss: Person) : Person("x", 1)
        object Registry { val all = listOf<Person>() }
        enum class Color { RED, GREEN }
        """
        let java = """
        public interface Visitor { void visit(Node n); }
        public class Node implements Visitor { private int value; public Node next; public void visit(Node n) {} }
        public class Leaf extends Node { }
        """
        write("Sources/Shapes.swift", swift)
        write("Demo/Entities.cs", csharp)
        write("app/src/main/Person.kt", kotlin)
        write("app/src/main/java/Tree.java", java)
        write("Tests/ShapeTests.swift", "class ShapeTests { func testIt() {} }")
        write("build/Generated.swift", "class ShouldBeSkipped {}")

        func scan(_ text: String, _ lang: SourceLanguage, priv: Bool = false) -> TypeScanner.Result { TypeScanner.scan(text, language: lang, file: "x", includePrivate: priv) }

        steps.append(("classes: Swift types, supertypes, members, enum cases and extensions are read; comments and strings are ignored", {
            let r = scan(swift, .swift)
            func t(_ n: String) -> TypeInfo? { r.types.first { $0.name == n } }
            guard let circle = t("Circle"), let shape = t("Shape"), let canvas = t("Canvas"), let mode = t("Mode") else { return false }
            return r.types.map(\.name) == ["Shape", "Base", "Circle", "Canvas", "Mode", "Store"]                       // Commented is a comment
                && shape.kind == .protocolType && t("Store")?.kind == .actorType && canvas.kind == .structType && mode.kind == .enumType
                && circle.supertypes == ["Base", "Shape", "Hashable"]
                && circle.properties.contains("~ radius: Double") && !circle.properties.contains { $0.contains("cache") }   // private is hidden
                && circle.methods.contains("~ draw()") && circle.methods.contains("~ make(_:scale:) → Circle") && circle.methods.contains("~ init(radius:)")
                && mode.properties == ["case fast", "case slow"]
                && canvas.properties.contains("~ shapes: [Shape]") && canvas.properties.contains("~ owner: Circle?")
                && r.extensions.first?.name == "Circle" && r.extensions.first?.supertypes == ["CustomStringConvertible"]
                && scan(swift, .swift, priv: true).types.first { $0.name == "Circle" }!.properties.contains("- cache: [Int]")
        }))
        steps.append(("classes: C#, Kotlin and Java types are read too, with their own visibility rules", {
            let cs = scan(csharp, .csharp), kt = scan(kotlin, .kotlin), jv = scan(java, .java)
            func t(_ r: TypeScanner.Result, _ n: String) -> TypeInfo? { r.types.first { $0.name == n } }
            guard let entity = t(cs, "Entity"), let user = t(cs, "User"), let role = t(cs, "Role"), let person = t(kt, "Person"),
                  let employee = t(kt, "Employee"), let node = t(jv, "Node") else { return false }
            let csharpOK = cs.types.map(\.name) == ["IRepo", "Entity", "User", "Role"] && t(cs, "IRepo")?.kind == .interfaceType && entity.isAbstract
                && entity.properties == ["+ Id: int", "# name: string"] && user.supertypes == ["Entity", "IRepo"]
                && user.properties == ["+ Email: string"]                                                   // `secret` is private by default in C#
                && user.methods.contains("+ User(email)") && user.methods.contains("+ Find(id) → User") && user.methods.contains("+ Reset()")
                && role.properties == ["case Admin", "case Guest"]
            let kotlinOK = person.supertypes == ["Greeter"] && person.properties == ["+ name: String"] && person.methods == ["+ greet(name)"]
                && employee.supertypes == ["Person"] && employee.properties == ["+ boss: Person"]
                && t(kt, "Registry")?.kind == .objectType && t(kt, "Color")?.properties == ["case RED", "case GREEN"]
            let javaOK = jv.types.map(\.name) == ["Visitor", "Node", "Leaf"] && node.supertypes == ["Visitor"] && node.properties == ["+ next: Node"]
                && t(jv, "Leaf")?.supertypes == ["Node"]
            return csharpOK && kotlinOK && javaOK
        }))
        steps.append(("classes: the importer reads a folder, skips build output, links types and respects the options", {
            guard let g = try? ClassImporter.analyze(root) else { return false }
            let names = Set(g.types.map(\.name))
            func rel(_ a: String, _ b: String) -> RelationKind? { g.relations.first { $0.from == a && $0.to == b }?.kind }
            let all = names.isSuperset(of: ["Shape", "Circle", "User", "Person", "Node", "Leaf"]) && !names.contains("ShouldBeSkipped") && !names.contains("ShapeTests")
            let links = rel("Circle", "Base") == .inherits && rel("Circle", "Shape") == .implements && rel("User", "Entity") == .inherits
                && rel("User", "IRepo") == .implements && rel("Employee", "Person") == .inherits && rel("Leaf", "Node") == .inherits
                && rel("Canvas", "Shape") == .association && rel("Canvas", "Circle") == .association
                && rel("Registry", "Person") == nil                                                            // `listOf<Person>()` has no declared type
            var opts = ClassOptions(); opts.includeTests = true
            let withTests = (try? ClassImporter.analyze(root, options: opts))?.types.contains { $0.name == "ShapeTests" && $0.isTest } == true
            var small = ClassOptions(); small.maxTypes = 5
            let cut = (try? ClassImporter.analyze(root, options: small)).map { $0.types.count == 5 && $0.truncated?.shown == 5 && $0.truncated!.total > 5 } ?? false
            var emptyFound = false
            let empty = tempDir.appendingPathComponent("no-types")
            try? fm.createDirectory(at: empty, withIntermediateDirectories: true)
            try? "just text".write(to: empty.appendingPathComponent("a.swift"), atomically: true, encoding: .utf8)
            do { _ = try ClassImporter.analyze(empty) } catch { emptyFound = error is ClassImporter.ImportError }
            // A project file points at its parent folder.
            let proj = tempDir.appendingPathComponent("holder/App.xcodeproj")
            try? fm.createDirectory(at: proj, withIntermediateDirectories: true)
            let rooted = ClassImporter.root(for: proj)?.lastPathComponent == "holder"
            return all && links && withTests && cut && emptyFound && rooted && g.title == "classes" && g.source == "Source folder"
        }))
        steps.append(("classes: the drawing has a grouped box per type, dividers, arrows by relation kind, a key and the layers", {
            guard let g = try? ClassImporter.analyze(root) else { return false }
            let d = ClassDrawing.build(g)
            let boxes = d.shapes.filter { $0.kind == .rounded && $0.frame.width >= 160 }
            let grouped = boxes.allSatisfy { b in d.shapes.filter { $0.group == b.group }.count >= 3 }
            let dividers = d.shapes.filter { $0.kind == .path }.count == boxes.count * 2
            func heads(_ k: RelationKind) -> Set<HeadKind> {
                Set(g.relations.filter { $0.kind == k }.compactMap { r in
                    guard let a = boxes.first(where: { b in d.shapes.contains { $0.group == b.group && $0.text == r.from && $0.style.text.bold } }),
                          let c = d.connectors.first(where: { $0.from == a.id }) else { return nil }
                    return c.endHead
                })
            }
            let hollow = d.connectors.contains { $0.endHead == .hollowTriangle } && d.connectors.contains { $0.endHead == .openArrow }
            let dashed = d.connectors.contains { $0.style.stroke.dash == .dashed }
            var plain = ClassOptions(); plain.includeMembers = false
            let slim = ClassDrawing.build(g, options: plain)
            let layers = d.layers.map(\.name) == ["Relationships", "Types", "Legend"]
            let key = d.shapes.contains { $0.text.hasPrefix("Hollow arrow") } && d.shapes.contains { $0.text.hasSuffix("Classes") }
            let noBoxMembers = slim.shapes.filter { $0.kind == .path }.isEmpty && slim.shapes.count < d.shapes.count
            _ = heads(.inherits)
            return boxes.count == g.types.count && grouped && dividers && d.connectors.count == g.relations.count && hollow && dashed && layers && key && noBoxMembers
        }))
        steps.append(("classes: themes restyle a class diagram, and it survives saving", {
            guard let g = try? ClassImporter.analyze(root) else { return false }
            var d = ClassDrawing.build(g)
            ThemeLibrary.theme(id: "midnight")?.apply(to: &d)
            let lettering = d.shapes.filter { $0.kind == .text && $0.text.hasPrefix("+") || $0.text.hasPrefix("~") }
                .allSatisfy { ($0.style.text.color?.luminance ?? 0) > 0.7 }                                    // members sit inside the dark boxes
            guard let data = try? JSONEncoder().encode(d), let back = try? JSONDecoder().decode(Drawing.self, from: data) else { return false }
            let canvas = CanvasView(frame: NSRect(origin: .zero, size: CanvasView.canvasSize))
            canvas.load(d)
            return back == d && lettering && (canvas.pngData()?.count ?? 0) > 1000
        }))
        steps.append(("classes: Software Architecture and Classes are separate choices in the wizard, and File has Import Class Diagram…", {
            let file = self.makeMainMenu().items.first { $0.title == "File" }?.submenu
            let hasItem = file?.items.first { $0.title == "Import Class Diagram…" }?.action == #selector(AppDelegate.importClassDiagram(_:))
            let defaults = UserDefaults.standard
            let saved = ["newDocument.template", "newDocument.theme"].map { ($0, defaults.object(forKey: $0)) }
            defer { for (key, value) in saved { if let value { defaults.set(value, forKey: key) } else { defaults.removeObject(forKey: key) } } }
            var picks: [NewDocumentController.Choice] = []
            func run(_ kind: DocumentTemplate.Kind, theme: String) {
                let w = NewDocumentController.presentNewDocument { picks.append($0) }
                w.select(template: DocumentTemplate.all.first { $0.kind == kind }!)
                w.confirm()
                w.select(theme: theme)
                w.confirm()
            }
            run(.classes, theme: "clay")
            run(.architecture, theme: "midnight")
            run(.blank, theme: "clean")
            return hasItem && picks.map(\.template.kind) == [.classes, .architecture, .blank] && picks.map(\.theme.id) == ["clay", "midnight", "clean"]
        }))
        steps.append(("classes: the class and architecture samples draw (they are the wizard's pictures)", {
            let c = ThemePreview.classSample(), a = ThemePreview.architectureSample()
            let imageC = ThemePreview.image(for: ThemeLibrary.clean, sample: .classes), imageA = ThemePreview.image(for: ThemeLibrary.clean, sample: .architecture)
            return c.shapes.count > 10 && c.connectors.count == 3 && a.connectors.count == 5 && imageC != nil && imageA != nil
                && !c.shapes.contains { $0.text == "Preview" } && !a.shapes.contains { $0.text == "Preview" }          // no title in a thumbnail
        }))
        steps.append(("classes: this app's own sources make a class diagram (when run from the repo)", {
            let sources = URL(fileURLWithPath: fm.currentDirectoryPath).appendingPathComponent("Sources/Graffle")
            guard fm.fileExists(atPath: sources.path) else { print("      (skipped: not run from the repo)"); return true }
            guard let g = try? ClassImporter.analyze(sources) else { return false }
            let d = ClassDrawing.build(g)
            return g.types.contains { $0.name == "CanvasView" && $0.kind == .classType && $0.methods.count > 10 }
                && g.types.contains { $0.name == "Drawing" && $0.kind == .structType } && g.relations.count > 20 && !d.shapes.isEmpty
        }))
        return steps
    }
}
