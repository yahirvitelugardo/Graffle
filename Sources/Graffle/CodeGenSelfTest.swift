import AppKit

/// Self-test steps for generating code from diagrams into empty folders.
extension AppDelegate {
    func codeGenSteps(tempDir: URL) -> [(String, () -> Bool)] {
        var steps: [(String, () -> Bool)] = []
        let fm = FileManager.default
        func fresh(_ name: String) -> URL {
            let u = tempDir.appendingPathComponent(name); try? fm.removeItem(at: u); try? fm.createDirectory(at: u, withIntermediateDirectories: true); return u
        }
        func dbg(_ items: Any...) { FileHandle.standardError.write((items.map { "\($0)" }.joined(separator: " ") + "\n").data(using: .utf8)!) }
        func text(_ p: GeneratedProject, _ path: String) -> String { p.files.first { $0.path == path }?.content ?? "" }

        let schema: DBSchema = {
            var s = DBSchema()
            s.tables = [
                DBTable(id: "dbo.Orders", name: "Orders", columns: [DBColumn(name: "Id", type: "int", isPrimaryKey: true, isNullable: false), DBColumn(name: "CustomerId", type: "int", isNullable: false)],
                        foreignKeys: [DBForeignKey(column: "CustomerId", refTable: "dbo.Customers", refColumn: "Id")]),
                DBTable(id: "dbo.Customers", name: "Customers", columns: [DBColumn(name: "Id", type: "int", isPrimaryKey: true, isNullable: false), DBColumn(name: "Name", type: "varchar(80)", isNullable: false)]),
            ]
            return s
        }()
        let er = ERModel(title: "Shop", schema: schema, tableIDs: schema.tables.map(\.id))

        steps.append(("codegen: SQL is written for all four dialects, parents before children", {
            for d in SQLDialect.allCases {
                guard let p = try? SQLCode.generate(er, dialect: d, project: "Shop") else { print("      sql gen failed", d); return false }
                let sql = text(p, "schema.sql")
                guard let c = sql.range(of: "Customers"), let o = sql.range(of: "Orders"), c.lowerBound < o.lowerBound, sql.contains("PRIMARY KEY"), sql.contains("FOREIGN KEY") || sql.contains("REFERENCES") else { dbg("      SQL for \(d):\n\(sql)"); return false }
            }
            let pg = (try? SQLCode.generate(er, dialect: .postgres, project: "Shop"))
            let my = (try? SQLCode.generate(er, dialect: .mysql, project: "Shop"))
            return text(pg!, "schema.sql").contains("\"Customers\"") && text(my!, "schema.sql").contains("`dbo_Customers`")
        }))

        steps.append(("codegen: a foreign-key cycle is deferred to ALTER TABLE", {
            var s = DBSchema()
            s.tables = [DBTable(id: "a", name: "a", columns: [DBColumn(name: "id", type: "int", isPrimaryKey: true, isNullable: false), DBColumn(name: "b_id", type: "int")], foreignKeys: [DBForeignKey(column: "b_id", refTable: "b", refColumn: "id")]),
                        DBTable(id: "b", name: "b", columns: [DBColumn(name: "id", type: "int", isPrimaryKey: true, isNullable: false), DBColumn(name: "a_id", type: "int")], foreignKeys: [DBForeignKey(column: "a_id", refTable: "a", refColumn: "id")])]
            guard let p = try? SQLCode.generate(ERModel(title: "C", schema: s, tableIDs: ["a", "b"]), dialect: .postgres, project: "C") else { return false }
            return text(p, "schema.sql").contains("ALTER TABLE")
        }))

        let types = [
            TypeInfo(name: "Animal", kind: .classType, language: .swift, supertypes: [], properties: ["+ name: String", "- age: Int"], methods: ["+ speak() → String"], isAbstract: false),
            TypeInfo(name: "Dog", kind: .classType, language: .swift, supertypes: ["Animal", "Named"], properties: ["+ tricks: [String]"], methods: ["+ speak() → String", "+ fetch(item: String)"]),
            TypeInfo(name: "Named", kind: .protocolType, language: .swift, supertypes: [], properties: ["+ name: String"], methods: []),
            TypeInfo(name: "Mood", kind: .enumType, language: .swift, supertypes: [], properties: ["case happy", "case sad"], methods: []),
        ]
        let cm = ClassModel(title: "Zoo", source: "", types: types, relations: [])

        steps.append(("codegen: classes become Swift, C#, Kotlin and Java files", {
            for l in ClassCode.languages {
                do { _ = try ClassCode.generate(cm, language: l, project: "Zoo") } catch { dbg("gen failed", l, error); return false }
                let p = try! ClassCode.generate(cm, language: l, project: "Zoo")
                let exts: String
                switch l { case .swift: exts = "swift"; case .csharp: exts = "cs"; case .kotlin: exts = "kt"; case .java: exts = "java" }
                if p.files.filter({ $0.path.hasSuffix("." + exts) && $0.path != "Package.swift" }).count != 4 { dbg("count", l, p.files.map(\.path)); return false }
            }
            let sw = try! ClassCode.generate(cm, language: .swift, project: "Zoo")
            let dog = text(sw, "Sources/Zoo/Dog.swift")
            let mood = text(sw, "Sources/Zoo/Mood.swift")
            let cs = try! ClassCode.generate(cm, language: .csharp, project: "Zoo")
            let kt = try! ClassCode.generate(cm, language: .kotlin, project: "Zoo")
            let jv = try! ClassCode.generate(cm, language: .java, project: "Zoo")
            return dog.contains("class Dog: Animal, Named") && dog.contains("override func speak") && mood.contains("case happy, sad")
                && text(cs, "Dog.cs").contains("class Dog : Animal, Named") && text(cs, "Dog.cs").contains("override")
                && text(kt, "src/main/kotlin/zoo/Dog.kt").contains("Animal()") && text(jv, "src/main/java/zoo/Dog.java").contains("extends Animal implements Named")
        }))

        let arch = ArchitectureModel(title: "App", source: "", nodes: [
            ArchitectureNode(id: "a", name: "App", kind: .app, detail: "", container: ""),
            ArchitectureNode(id: "c", name: "Core", kind: .library, detail: "", container: ""),
            ArchitectureNode(id: "t", name: "AppTests", kind: .tests, detail: "", container: ""),
            ArchitectureNode(id: "s", name: "Foundation", kind: .system, detail: "", container: ""),
            ArchitectureNode(id: "x", name: "Alamofire", kind: .externalPackage, detail: "5.x", container: ""),
        ], edges: [ArchitectureEdge(from: "a", to: "c", kind: .dependsOn), ArchitectureEdge(from: "t", to: "a", kind: .dependsOn), ArchitectureEdge(from: "a", to: "s", kind: .dependsOn), ArchitectureEdge(from: "c", to: "x", kind: .package)])

        steps.append(("codegen: architecture scaffolds for Swift, .NET and Gradle wire the dependencies", {
            guard let sw = try? ArchitectureScaffold.generate(arch, target: .swiftPackage, project: "App"),
                  let dn = try? ArchitectureScaffold.generate(arch, target: .dotnet, project: "App"),
                  let gr = try? ArchitectureScaffold.generate(arch, target: .gradle, project: "App") else { return false }
            return text(sw, "Package.swift").contains("dependencies: [\"Core\"]") && !text(sw, "Package.swift").contains("Foundation")
                && text(dn, "App/App.csproj").contains("ProjectReference Include=\"..\\Core\\Core.csproj\"") && text(dn, "App.sln").contains("Core.csproj")
                && text(gr, "app/build.gradle.kts").contains("project(\":core\")") && text(gr, "settings.gradle.kts").contains("include(\"core\")")
                && text(sw, "README.md").contains("Alamofire")
                && ScaffoldTarget.inferred(from: ArchitectureModel(title: "", source: "", nodes: [ArchitectureNode(id: "dn:x", name: "x", kind: .app, detail: "", container: "")], edges: [])) == .dotnet
        }))

        steps.append(("codegen: only an empty folder is written, nothing otherwise", {
            let p = try! SQLCode.generate(er, dialect: .sqlite, project: "Shop")
            let full = fresh("cg-full"); try? "x".write(to: full.appendingPathComponent("keep.txt"), atomically: true, encoding: .utf8)
            do { _ = try FolderWriter.write(p, to: full); return false } catch CodeGenError.notEmpty {} catch { return false }
            guard (try? fm.contentsOfDirectory(atPath: full.path))?.sorted() == ["keep.txt"] else { return false }
            let empty = fresh("cg-empty"); try? Data().write(to: empty.appendingPathComponent(".DS_Store"))
            guard (try? FolderWriter.write(p, to: empty)) != nil, fm.fileExists(atPath: empty.appendingPathComponent("schema.sql").path) else { return false }
            let missing = tempDir.appendingPathComponent("cg-new/sub"); try? fm.removeItem(at: tempDir.appendingPathComponent("cg-new"))
            guard (try? FolderWriter.write(p, to: missing)) != nil, fm.fileExists(atPath: missing.appendingPathComponent("schema.sql").path) else { return false }
            return true
        }))

        steps.append(("codegen: unsafe paths are refused and leave the folder empty", {
            var bad = GeneratedProject(); bad.add("ok.txt", "1"); bad.add("../escape.txt", "2")
            let f = fresh("cg-unsafe")
            do { _ = try FolderWriter.write(bad, to: f); return false } catch CodeGenError.unsafePath {} catch { return false }
            return (try? fm.contentsOfDirectory(atPath: f.path))?.isEmpty == true && !fm.fileExists(atPath: tempDir.appendingPathComponent("escape.txt").path)
        }))

        steps.append(("codegen: the model is saved with the document and old documents still open", {
            var d = Drawing(); d.source = .classes(cm)
            guard let data = try? JSONEncoder().encode(d), let back = try? JSONDecoder().decode(Drawing.self, from: data), back.source == .classes(cm) else { return false }
            guard let old = try? JSONEncoder().encode(Drawing()), let o = try? JSONDecoder().decode(Drawing.self, from: old) else { return false }
            return o.source == nil
        }))

        steps.append(("codegen: choices per diagram type, and the whole flow writes through the injected panels", {
            guard CodeGen.choices(for: .classes(cm)).count == 4, CodeGen.choices(for: .entityRelationship(er)).count == 4, CodeGen.choices(for: .architecture(arch)).count == 3 else { return false }
            let target = fresh("cg-flow")
            let saved = (CodeGen.chooseFolder, CodeGen.presentOptions, CodeGen.presentResult)
            defer { (CodeGen.chooseFolder, CodeGen.presentOptions, CodeGen.presentResult) = saved }
            var message = ""
            CodeGen.chooseFolder = { target }
            CodeGen.presentOptions = { _, c in c.first }
            CodeGen.presentResult = { t, _, _ in message = t }
            let rc = DocumentWindowController()
            rc.canvas.load(Drawing())
            guard !rc.canGenerateCode else { return false }
            var d = Drawing(); d.source = .entityRelationship(er); rc.canvas.load(d)
            guard rc.canGenerateCode else { return false }
            rc.generateCode(nil)
            guard message == "Code generated", fm.fileExists(atPath: target.appendingPathComponent("schema.sql").path) else { return false }
            rc.generateCode(nil)
            return message == "Nothing was generated"
        }))
        return steps
    }
}
