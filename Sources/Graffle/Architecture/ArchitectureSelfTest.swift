import AppKit

/// Self-test steps for the architecture importer (run with `--selftest`).
extension AppDelegate {
    func architectureSteps(bundled: Bool, tempDir: URL) -> [(String, () -> Bool)] {
        var steps: [(String, () -> Bool)] = []
        let fm = FileManager.default
        let root = tempDir.appendingPathComponent("arch")
        try? fm.createDirectory(at: root, withIntermediateDirectories: true)

        // A hand-built project: App (depends on, links and embeds Kit; uses a remote package and UIKit), Kit, KitTests.
        func writeProject(named name: String, in dir: URL) -> URL {
            let proj = dir.appendingPathComponent("\(name).xcodeproj")
            try? fm.createDirectory(at: proj, withIntermediateDirectories: true)
            let objects: [String: Any] = [
                "ROOT": ["isa": "PBXProject", "targets": ["T_APP", "T_KIT", "T_TESTS"]],
                "T_APP": ["isa": "PBXNativeTarget", "name": "App", "productType": "com.apple.product-type.application", "productReference": "P_APP",
                          "dependencies": ["D1"], "packageProductDependencies": ["PP1"], "buildPhases": ["FW_APP", "EMB_APP"]],
                "T_KIT": ["isa": "PBXNativeTarget", "name": "Kit", "productType": "com.apple.product-type.framework", "productReference": "P_KIT",
                          "dependencies": [], "buildPhases": []],
                "T_TESTS": ["isa": "PBXNativeTarget", "name": "KitTests", "productType": "com.apple.product-type.bundle.unit-test",
                            "productReference": "P_TESTS", "dependencies": ["D2"], "buildPhases": []],
                "P_APP": ["isa": "PBXFileReference", "path": "App.app"], "P_KIT": ["isa": "PBXFileReference", "path": "Kit.framework"],
                "P_TESTS": ["isa": "PBXFileReference", "path": "KitTests.xctest"],
                "D1": ["isa": "PBXTargetDependency", "target": "T_KIT"], "D2": ["isa": "PBXTargetDependency", "target": "T_KIT"],
                "REMOTE": ["isa": "XCRemoteSwiftPackageReference", "repositoryURL": "https://github.com/acme/Alamo.git",
                           "requirement": ["kind": "upToNextMajorVersion", "minimumVersion": "5.0.0"]],
                "PP1": ["isa": "XCSwiftPackageProductDependency", "productName": "Alamo", "package": "REMOTE"],
                "UIKIT": ["isa": "PBXFileReference", "name": "UIKit.framework", "path": "System/Library/Frameworks/UIKit.framework", "sourceTree": "SDKROOT"],
                "BF1": ["isa": "PBXBuildFile", "fileRef": "P_KIT"], "BF2": ["isa": "PBXBuildFile", "fileRef": "UIKIT"],
                "BF3": ["isa": "PBXBuildFile", "fileRef": "P_KIT"],
                "FW_APP": ["isa": "PBXFrameworksBuildPhase", "files": ["BF1", "BF2"]],
                "EMB_APP": ["isa": "PBXCopyFilesBuildPhase", "files": ["BF3"]],
            ]
            let plist: [String: Any] = ["rootObject": "ROOT", "objects": objects]
            let data = try? PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
            try? data?.write(to: proj.appendingPathComponent("project.pbxproj"))
            return proj
        }
        let projURL = writeProject(named: "Demo", in: root)

        steps.append(("architecture: layout puts dependents above dependencies, breaks cycles, keeps system rows last", {
            typealias E = GraphLayout.Edge
            let size = CGSize(width: 100, height: 40)
            let ids = ["a", "b", "c", "d", "sys"]
            let sizes = Dictionary(uniqueKeysWithValues: ids.map { ($0, size) })
            let chain = GraphLayout.layered(nodes: ids, sizes: sizes, edges: [E(from: "a", to: "b"), E(from: "b", to: "c"), E(from: "a", to: "c"), E(from: "c", to: "sys")],
                                            bottom: [["sys"]])
            let l = chain.layerOf
            let ordered = l["a"]! < l["b"]! && l["b"]! < l["c"]! && l["c"]! < l["sys"]!
            let cyc = GraphLayout.layered(nodes: ["x", "y", "z"], sizes: ["x": size, "y": size, "z": size],
                                          edges: [E(from: "x", to: "y"), E(from: "y", to: "z"), E(from: "z", to: "x")])
            let oneBack = cyc.cycleEdges.count == 1 && Set(cyc.layerOf.values).count == 3
            // No two nodes overlap, and everything lies inside the reported size.
            var ok = true
            for r in [chain, cyc] {
                let frames = r.origins.map { CGRect(origin: $0.value, size: size) }
                for (i, f) in frames.enumerated() {
                    if f.maxX > r.size.width || f.maxY > r.size.height { ok = false }
                    for g in frames[(i + 1)...] where f.intersects(g) { ok = false }
                }
            }
            // A wide row wraps instead of running off.
            let many = (0..<40).map { "n\($0)" }
            let wide = GraphLayout.layered(nodes: many, sizes: Dictionary(uniqueKeysWithValues: many.map { ($0, size) }), edges: [], maxWidth: 800)
            return ordered && oneBack && ok && wide.size.width < 1000 && wide.size.height > 200
        }))
        steps.append(("architecture: an .xcodeproj gives targets, dependencies, embeds, packages and system frameworks", {
            guard let r = try? XcodeProjectParser.parse(projectURL: projURL, packageVersions: ["alamo": "5.8.1"]) else { return false }
            let g = r.graph
            func edge(_ a: String, _ b: String) -> EdgeKind? { g.edges.first { $0.from == a && $0.to == b }?.kind }
            return g.node("Demo:App")?.kind == .app && g.node("Demo:Kit")?.kind == .framework && g.node("Demo:KitTests")?.kind == .tests
                && edge("Demo:App", "Demo:Kit") == .embeds           // depends + links + embeds is one edge, by its most specific kind
                && edge("Demo:KitTests", "Demo:Kit") == .dependsOn
                && edge("Demo:App", "pkg:alamo") == .package && g.node("pkg:alamo")?.detail.contains("5.8.1") == true   // resolved version wins
                && edge("Demo:App", "sys:UIKit") == .dependsOn && g.node("sys:UIKit")?.kind == .system
        }))
        steps.append(("architecture: options drop tests, packages and system frameworks together with their edges", {
            guard let g = try? ArchitectureImporter.analyze(projURL, options: ArchitectureOptions(includeSystemFrameworks: false, includeTests: false, includeExternalPackages: false)) else { return false }
            guard let full = try? ArchitectureImporter.analyze(projURL, options: ArchitectureOptions(includeSystemFrameworks: true, includeTests: true, includeExternalPackages: true)) else { return false }
            return g.nodes.map(\.name).sorted() == ["App", "Kit"] && g.edges.count == 1
                && full.nodes.count == 5 && full.edges.count == 4
        }))
        steps.append(("architecture: real Xcode projects on this machine parse (when present)", {
            let candidates = ["FileExchange/FileExchangeiOS", "FileExchange/FileExchangeMacOS"]
                .map { URL(fileURLWithPath: NSHomeDirectory() + "/Projects/" + $0) }.filter { fm.fileExists(atPath: $0.path) }
            guard !candidates.isEmpty else { print("      (skipped: no sample projects)"); return true }
            for dir in candidates {
                guard let g = try? ArchitectureImporter.analyze(dir), !g.nodes.isEmpty else { return false }
                if ArchitectureDrawing.build(g).shapes.isEmpty { return false }
            }
            return true
        }))

        // A package fixture with canned `dump-package` output, so the test doesn't depend on the toolchain.
        let pkgDir = root.appendingPathComponent("MyKit")
        for sub in ["Sources/Core", "Sources/Net", "Sources/CLI", "Tests/CoreTests"] { try? fm.createDirectory(at: pkgDir.appendingPathComponent(sub), withIntermediateDirectories: true) }
        try? "// swift-tools-version:5.7".write(to: pkgDir.appendingPathComponent("Package.swift"), atomically: true, encoding: .utf8)
        try? "let a = 1".write(to: pkgDir.appendingPathComponent("Sources/Core/a.swift"), atomically: true, encoding: .utf8)
        try? "let b = 1".write(to: pkgDir.appendingPathComponent("Sources/Net/b.swift"), atomically: true, encoding: .utf8)
        try? "let c = 1".write(to: pkgDir.appendingPathComponent("Sources/Net/c.swift"), atomically: true, encoding: .utf8)
        let dump = """
        {"name":"MyKit","dependencies":[{"sourceControl":[{"identity":"swift-argument-parser","location":{"remote":[{"urlString":"https://github.com/apple/swift-argument-parser.git"}]},"requirement":{"range":[{"lowerBound":"1.3.0","upperBound":"2.0.0"}]}}]}],
         "products":[{"name":"MyKit","targets":["Core","Net"],"type":{"library":["automatic"]}}],
         "targets":[{"name":"Core","type":"regular","dependencies":[]},
                    {"name":"Net","type":"regular","dependencies":[{"byName":["Core",null]}]},
                    {"name":"CLI","type":"executable","dependencies":[{"target":["Net",null]},{"product":["ArgumentParser","swift-argument-parser",null,null]}]},
                    {"name":"CoreTests","type":"test","dependencies":[{"byName":["Core",null]}]}]}
        """
        func samePath(_ a: ArchitectureImporter.Source?, _ b: ArchitectureImporter.Source) -> Bool {
            guard let a else { return false }
            return a.url.resolvingSymlinksInPath().path == b.url.resolvingSymlinksInPath().path
        }
        let canned: SwiftPackageParser.Runner = { _ in Data(dump.utf8) }
        steps.append(("architecture: a Swift package gives targets, products, executables, tests and external packages", {
            guard let r = try? SwiftPackageParser.parse(folder: pkgDir, packageVersions: ["swift-argument-parser": "1.3.1"], runner: canned) else { return false }
            let g = r.graph
            func edge(_ a: String, _ b: String) -> EdgeKind? { g.edges.first { $0.from == a && $0.to == b }?.kind }
            return g.node("MyKit:Core")?.kind == .library && g.node("MyKit:CLI")?.kind == .tool && g.node("MyKit:CoreTests")?.kind == .tests
                && g.node("MyKit:Net")?.detail.contains("2 files") == true
                && edge("MyKit:Net", "MyKit:Core") == .dependsOn && edge("MyKit:CLI", "MyKit:Net") == .dependsOn
                && edge("MyKit:CLI", "pkg:swift-argument-parser") == .package
                && g.node("pkg:swift-argument-parser")?.detail.contains("1.3.1") == true
                && r.productTargets["MyKit"] == ["MyKit:Core", "MyKit:Net"]
        }))
        steps.append(("architecture: swift package dump-package really runs on a package (when the toolchain is there)", {
            guard fm.isExecutableFile(atPath: "/usr/bin/swift") else { print("      (skipped: no toolchain)"); return true }
            let real = root.appendingPathComponent("Real")
            try? fm.createDirectory(at: real.appendingPathComponent("Sources/Alpha"), withIntermediateDirectories: true)
            try? fm.createDirectory(at: real.appendingPathComponent("Sources/Beta"), withIntermediateDirectories: true)
            try? "// swift-tools-version:5.7\nimport PackageDescription\nlet package = Package(name: \"Real\", products: [.library(name: \"Real\", targets: [\"Alpha\", \"Beta\"])], targets: [.target(name: \"Alpha\"), .target(name: \"Beta\", dependencies: [\"Alpha\"])])\n"
                .write(to: real.appendingPathComponent("Package.swift"), atomically: true, encoding: .utf8)
            try? "public let a = 1".write(to: real.appendingPathComponent("Sources/Alpha/a.swift"), atomically: true, encoding: .utf8)
            try? "import Alpha\npublic let b = a".write(to: real.appendingPathComponent("Sources/Beta/b.swift"), atomically: true, encoding: .utf8)
            guard let g = try? ArchitectureImporter.analyze(real) else { return false }
            return g.nodes.count == 2 && g.edges.contains { $0.from == "Real:Beta" && $0.to == "Real:Alpha" }
        }))
        steps.append(("architecture: a project using a local package gets edges into that package's targets", {
            let app = root.appendingPathComponent("WithLocal")
            try? fm.createDirectory(at: app, withIntermediateDirectories: true)
            let pkg = app.appendingPathComponent("Libs")
            try? fm.createDirectory(at: pkg.appendingPathComponent("Sources/Core"), withIntermediateDirectories: true)
            let proj = app.appendingPathComponent("Host.xcodeproj")
            try? fm.createDirectory(at: proj, withIntermediateDirectories: true)
            let objects: [String: Any] = [
                "ROOT": ["isa": "PBXProject", "targets": ["T"]],
                "T": ["isa": "PBXNativeTarget", "name": "Host", "productType": "com.apple.product-type.application", "dependencies": [],
                      "packageProductDependencies": ["PP"], "buildPhases": []],
                "LOCAL": ["isa": "XCLocalSwiftPackageReference", "relativePath": "Libs"],
                "PP": ["isa": "XCSwiftPackageProductDependency", "productName": "MyKit", "package": "LOCAL"],
            ]
            let plist: [String: Any] = ["rootObject": "ROOT", "objects": objects]
            try? (try? PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0))?.write(to: proj.appendingPathComponent("project.pbxproj"))
            guard let g = try? ArchitectureImporter.analyze(app, runner: canned) else { return false }
            return samePath(ArchitectureImporter.detect(app), .project(proj))
                && g.edges.contains { $0.from == "Host:Host" && $0.to == "MyKit:Core" }
                && g.edges.contains { $0.from == "Host:Host" && $0.to == "MyKit:Net" }
        }))
        steps.append(("architecture: source detection prefers a workspace, then a project, then a package; rejects other folders", {
            let ws = root.appendingPathComponent("Both")
            try? fm.createDirectory(at: ws.appendingPathComponent("A.xcworkspace"), withIntermediateDirectories: true)
            try? fm.createDirectory(at: ws.appendingPathComponent("A.xcodeproj"), withIntermediateDirectories: true)
            let empty = root.appendingPathComponent("Empty")
            try? fm.createDirectory(at: empty, withIntermediateDirectories: true)
            var rejected = false
            do { _ = try ArchitectureImporter.analyze(empty) } catch { rejected = error is ArchitectureImporter.ImportError }
            return samePath(ArchitectureImporter.detect(ws), .workspace(ws.appendingPathComponent("A.xcworkspace")))
                && samePath(ArchitectureImporter.detect(pkgDir.appendingPathComponent("Package.swift")), .package(pkgDir))
                && ArchitectureImporter.detect(empty) == nil && rejected
        }))
        steps.append(("architecture: a workspace lists its projects and package folders", {
            let ws = root.appendingPathComponent("W.xcworkspace")
            try? fm.createDirectory(at: ws, withIntermediateDirectories: true)
            let xml = "<?xml version=\"1.0\"?><Workspace version=\"1.0\"><FileRef location=\"group:Demo.xcodeproj\"></FileRef><Group location=\"container:\" name=\"G\"><FileRef location=\"group:MyKit\"></FileRef></Group></Workspace>"
            try? xml.write(to: ws.appendingPathComponent("contents.xcworkspacedata"), atomically: true, encoding: .utf8)
            let c = XcodeWorkspaceParser.parse(workspaceURL: ws)
            return c.projects.map(\.lastPathComponent) == ["Demo.xcodeproj"] && c.packageFolders.map(\.lastPathComponent) == ["MyKit"]
        }))
        steps.append(("architecture: the drawing has a node and connector per module, layers, legend, and cycle marks", {
            guard var g = try? ArchitectureImporter.analyze(projURL, options: ArchitectureOptions(includeSystemFrameworks: true)) else { return false }
            g.connect("Demo:Kit", "Demo:App", .dependsOn)           // closes a cycle App -> Kit -> App
            let d = ArchitectureDrawing.build(g)
            let rounded = d.shapes.filter { $0.kind == .rounded && $0.frame.width >= 100 }
            let connectorShapesExist = d.connectors.allSatisfy { c in d.shapes.contains { $0.id == c.from } && d.shapes.contains { $0.id == c.to } }
            let layers = d.layers.map(\.name) == ["Dependencies", "Targets", "Packages", "System", "Legend"]
            let cycle = d.connectors.filter { $0.text == "cycle" }.count == 1
            let title = d.shapes.contains { $0.text == "Demo" }
            let grouped = rounded.allSatisfy { r in d.shapes.contains { $0.group == r.group && $0.id != r.id } || r.frame.height < 50 }
            return rounded.count == g.nodes.count && d.connectors.count == g.edges.count && connectorShapesExist && layers && cycle && title && grouped
        }))
        steps.append(("architecture: the drawing round-trips through JSON", {
            guard let g = try? ArchitectureImporter.analyze(projURL) else { return false }
            let d = ArchitectureDrawing.build(g)
            guard let data = try? JSONEncoder().encode(d), let back = try? JSONDecoder().decode(Drawing.self, from: data) else { return false }
            return back == d
        }))
        steps.append(("architecture: File menu has Import Project Architecture…, and opening a result makes an unsaved document", {
            let file = self.makeMainMenu().items.first { $0.title == "File" }?.submenu
            let hasItem = file?.items.first { $0.title == "Import Project Architecture…" }?.action == #selector(AppDelegate.importXcodeProject(_:))
            guard bundled else { print("      (document part skipped: needs the .app bundle)"); return hasItem }
            guard let g = try? ArchitectureImporter.analyze(projURL) else { return false }
            let doc = GraffleDocument.open(drawing: ArchitectureDrawing.build(g), name: "Demo Architecture")
            let shown = doc.canvas?.drawing.shapes.isEmpty == false
            let unsaved = doc.fileURL == nil && doc.displayName == "Demo Architecture"
            doc.close()
            return hasItem && shown && unsaved
        }))
        // A small .NET solution: Web -> Domain -> Core, Web -> Data -> Core, Tests -> Domain, with NuGet packages.
        let net = root.appendingPathComponent("Shop")
        func write(_ rel: String, _ text: String) {
            let u = net.appendingPathComponent(rel)
            try? fm.createDirectory(at: u.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? text.write(to: u, atomically: true, encoding: .utf8)
        }
        write("Shop.sln", """
        Microsoft Visual Studio Solution File, Format Version 12.00
        Project("{9A19103F-16F7-4668-BE54-9A1E7A4F7556}") = "Shop.Web", "src\\Shop.Web\\Shop.Web.csproj", "{1}"
        EndProject
        Project("{FAE04EC0-301F-11D3-BF4B-00C04F79EFBC}") = "Shop.Data", "src\\Shop.Data\\Shop.Data.csproj", "{2}"
        EndProject
        Project("{2150E333-8FDC-42A3-9474-1A3956D46DE8}") = "src", "src", "{3}"
        EndProject
        Project("{9A19103F-16F7-4668-BE54-9A1E7A4F7556}") = "Shop.Tests", "tests\\Shop.Tests\\Shop.Tests.csproj", "{4}"
        EndProject
        """)
        write("Directory.Packages.props", "<Project><ItemGroup><PackageVersion Include=\"Dapper\" Version=\"2.1.35\" /></ItemGroup></Project>")
        write("src/Shop.Web/Shop.Web.csproj", "<Project Sdk=\"Microsoft.NET.Sdk.Web\"><PropertyGroup><TargetFramework>net8.0</TargetFramework></PropertyGroup><ItemGroup><ProjectReference Include=\"..\\Shop.Domain\\Shop.Domain.csproj\" /><ProjectReference Include=\"..\\Shop.Data\\Shop.Data.csproj\" /></ItemGroup><ItemGroup><PackageReference Include=\"Serilog\" Version=\"3.1.1\" /></ItemGroup></Project>")
        write("src/Shop.Web/Program.cs", "class P {}")
        write("src/Shop.Domain/Shop.Domain.csproj", "<Project Sdk=\"Microsoft.NET.Sdk\"><PropertyGroup><TargetFramework>net8.0</TargetFramework></PropertyGroup><ItemGroup><ProjectReference Include=\"..\\Shop.Core\\Shop.Core.csproj\" /></ItemGroup></Project>")
        write("src/Shop.Domain/A.cs", "class A {}")
        write("src/Shop.Domain/B.cs", "class B {}")
        write("src/Shop.Domain/obj/Generated.cs", "class G {}")
        write("src/Shop.Data/Shop.Data.csproj", "<Project Sdk=\"Microsoft.NET.Sdk\"><PropertyGroup><TargetFrameworks>net8.0;netstandard2.0</TargetFrameworks></PropertyGroup><ItemGroup><ProjectReference Include=\"../Shop.Core/Shop.Core.csproj\" /><PackageReference Include=\"Dapper\" /></ItemGroup></Project>")
        write("src/Shop.Core/Shop.Core.csproj", "<Project Sdk=\"Microsoft.NET.Sdk\"><PropertyGroup><TargetFramework>net8.0</TargetFramework><OutputType>Library</OutputType></PropertyGroup><ItemGroup><FrameworkReference Include=\"Microsoft.AspNetCore.App\" /></ItemGroup></Project>")
        write("tests/Shop.Tests/Shop.Tests.csproj", "<Project Sdk=\"Microsoft.NET.Sdk\"><PropertyGroup><TargetFramework>net8.0</TargetFramework></PropertyGroup><ItemGroup><PackageReference Include=\"Microsoft.NET.Test.Sdk\" Version=\"17.9.0\" /><ProjectReference Include=\"..\\..\\src\\Shop.Domain\\Shop.Domain.csproj\" /></ItemGroup></Project>")
        steps.append(("architecture (.NET): a solution gives projects, references, NuGet packages (with central versions) and frameworks", {
            let sln = net.appendingPathComponent("Shop.sln")
            guard ArchitectureImporter.detect(net)?.url.lastPathComponent == "Shop.sln",
                  let g = try? ArchitectureImporter.analyze(sln, options: ArchitectureOptions(includeSystemFrameworks: true)) else { return false }
            func edge(_ a: String, _ b: String) -> EdgeKind? { g.edges.first { $0.from == a && $0.to == b }?.kind }
            return g.node("dn:Shop.Web")?.kind == .app && g.node("dn:Shop.Web")?.detail.contains("Web app") == true
                && g.node("dn:Shop.Domain")?.kind == .library && g.node("dn:Shop.Domain")?.detail.contains("2 files") == true   // obj/ is not counted
                && g.node("dn:Shop.Domain")?.detail.contains("net8.0") == true
                && g.node("dn:Shop.Data")?.detail.contains("net8.0, netstandard2.0") == true
                && g.node("dn:Shop.Tests")?.kind == .tests && g.node("dn:Shop.Core") != nil     // reached only through references
                && edge("dn:Shop.Web", "dn:Shop.Domain") == .dependsOn && edge("dn:Shop.Domain", "dn:Shop.Core") == .dependsOn
                && edge("dn:Shop.Data", "dn:Shop.Core") == .dependsOn && edge("dn:Shop.Tests", "dn:Shop.Domain") == .dependsOn
                && edge("dn:Shop.Web", "pkg:serilog") == .package && g.node("pkg:serilog")?.detail.contains("3.1.1") == true
                && g.node("pkg:dapper")?.detail.contains("2.1.35") == true
                && edge("dn:Shop.Core", "sys:Microsoft.AspNetCore.App") == .dependsOn
        }))
        steps.append(("architecture (.NET): a single project, a slnx, and a missing reference are handled", {
            let web = net.appendingPathComponent("src/Shop.Web/Shop.Web.csproj")
            guard let single = try? ArchitectureImporter.analyze(web) else { return false }
            write("Lone/Lone.csproj", "<Project Sdk=\"Microsoft.NET.Sdk\"><ItemGroup><ProjectReference Include=\"..\\Gone\\Gone.csproj\" /></ItemGroup></Project>")
            write("Lone/Lone.slnx", "<Solution><Folder Name=\"/x/\"><Project Path=\"Lone.csproj\" /></Folder></Solution>")
            guard let lone = try? ArchitectureImporter.analyze(net.appendingPathComponent("Lone/Lone.slnx")) else { return false }
            return single.nodes.count >= 5 && single.source == ".NET project"
                && lone.node("dn:Gone")?.kind == .other && lone.edges.contains { $0.from == "dn:Lone" && $0.to == "dn:Gone" }
        }))
        steps.append(("architecture (.NET): the drawing builds and project cycles are marked", {
            guard let g = try? ArchitectureImporter.analyze(net.appendingPathComponent("Shop.sln")) else { return false }
            var cyc = g
            cyc.connect("dn:Shop.Core", "dn:Shop.Web", .dependsOn)
            let d = ArchitectureDrawing.build(cyc)
            return d.connectors.contains { $0.text == "cycle" } && d.connectors.count == cyc.edges.count && d.shapes.contains { $0.text == "Shop" }
        }))
        // An Android build in Kotlin DSL with a version catalog, multi-line includes, a typesafe accessor and a commented-out module.
        let droid = root.appendingPathComponent("Droid")
        func put(_ rel: String, _ text: String) {
            let u = droid.appendingPathComponent(rel)
            try? fm.createDirectory(at: u.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? text.write(to: u, atomically: true, encoding: .utf8)
        }
        put("settings.gradle.kts", """
        rootProject.name = "Droid"
        include(":app")
        include(
            ":core:data",
            ":core:model",
            ":feature:home"
        )
        // include(":old")
        """)
        put("build.gradle.kts", "plugins { alias(libs.plugins.android.application) apply false }")
        put("gradle/libs.versions.toml", """
        [versions]
        retrofit = "2.9.0"
        [libraries]
        retrofit = { module = "com.squareup.retrofit2:retrofit", version.ref = "retrofit" }
        okhttp = "com.squareup.okhttp3:okhttp:4.12.0"
        junit = { module = "junit:junit", version = "4.13.2" }
        [plugins]
        android-application = { id = "com.android.application", version = "8.2.0" }
        android-library = { id = "com.android.library", version = "8.2.0" }
        """)
        put("app/build.gradle.kts", "plugins { alias(libs.plugins.android.application) }\nandroid { defaultConfig { minSdk = 26 } }\ndependencies {\n  implementation(project(\":feature:home\"))\n  implementation(projects.core.data)\n  implementation(libs.okhttp)\n  testImplementation(libs.junit)\n  // implementation(project(\":old\"))\n}")
        put("app/src/main/java/A.kt", "class A")
        put("app/src/main/java/B.java", "class B {}")
        put("feature/home/build.gradle.kts", "plugins { id(\"com.android.library\") }\ndependencies { implementation(project(\":core:data\")); api(\"androidx.core:core-ktx:1.12.0\") }")
        put("core/data/build.gradle.kts", "plugins { id(\"com.android.library\") }\ndependencies { api(project(\":core:model\")); implementation(libs.retrofit) }")
        put("core/model/build.gradle.kts", "plugins { id(\"org.jetbrains.kotlin.jvm\") }")
        steps.append(("architecture (Android): Gradle modules, project and catalog dependencies, comments and test configs", {
            guard case .gradle? = ArchitectureImporter.detect(droid), case .gradle? = ArchitectureImporter.detect(droid.appendingPathComponent("app/build.gradle.kts")),
                  let g = try? ArchitectureImporter.analyze(droid) else { return false }
            func edge(_ a: String, _ b: String) -> EdgeKind? { g.edges.first { $0.from == a && $0.to == b }?.kind }
            return g.nodes.filter({ $0.container == "Droid" }).map(\.name).sorted() == ["app", "core:data", "core:model", "feature:home"]   // no root, no :old
                && g.node("gr::app")?.kind == .app && g.node("gr::app")?.detail.contains("minSdk 26") == true
                && g.node("gr::app")?.detail.contains("Kotlin/Java · 2 files") == true
                && g.node("gr::feature:home")?.kind == .library && g.node("gr::core:model")?.detail.contains("JVM library") == true
                && edge("gr::app", "gr::feature:home") == .dependsOn && edge("gr::app", "gr::core:data") == .dependsOn
                && edge("gr::feature:home", "gr::core:data") == .dependsOn && edge("gr::core:data", "gr::core:model") == .dependsOn
                && edge("gr::app", "gr::core:model") == nil && edge("gr::app", "gr::old") == nil
                && edge("gr::core:data", "pkg:com.squareup.retrofit2:retrofit") == .package
                && g.node("pkg:com.squareup.retrofit2:retrofit")?.detail.contains("2.9.0") == true      // version.ref resolved
                && g.node("pkg:com.squareup.okhttp3:okhttp")?.detail.contains("4.12.0") == true
                && edge("gr::feature:home", "pkg:androidx.core:core-ktx") == .package
                && g.node("pkg:junit:junit") == nil                                                      // test configurations are left out
        }))
        steps.append(("architecture (Android): a single-module build and the real FileExchangeAndroid project (when present)", {
            let one = root.appendingPathComponent("OneModule")
            try? fm.createDirectory(at: one, withIntermediateDirectories: true)
            try? "plugins { id 'java-library' }\ndependencies { implementation 'com.google.guava:guava:33.0.0-jre' }".write(to: one.appendingPathComponent("build.gradle"), atomically: true, encoding: .utf8)
            try? "rootProject.name = 'one'".write(to: one.appendingPathComponent("settings.gradle"), atomically: true, encoding: .utf8)
            guard let g = try? ArchitectureImporter.analyze(one), g.node("gr::")?.kind == .library, g.edges.count == 1 else { return false }
            let real = URL(fileURLWithPath: NSHomeDirectory() + "/Projects/FileExchange/FileExchangeAndroid")
            guard fm.fileExists(atPath: real.path) else { print("      (real project skipped: not present)"); return true }
            guard let r = try? ArchitectureImporter.analyze(real) else { return false }
            return r.nodes.contains { $0.kind == .app } && !ArchitectureDrawing.build(r).shapes.isEmpty
        }))
        return steps
    }
}
