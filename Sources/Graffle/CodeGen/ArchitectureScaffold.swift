import Foundation

enum ScaffoldTarget: String, CaseIterable {
    case swiftPackage, dotnet, gradle

    var title: String {
        switch self {
        case .swiftPackage: return "Swift package"
        case .dotnet: return ".NET solution"
        case .gradle: return "Gradle multi-module"
        }
    }

    /// The target the diagram most likely came from, by how its node ids were made.
    static func inferred(from m: ArchitectureModel) -> ScaffoldTarget {
        if m.nodes.contains(where: { $0.id.hasPrefix("dn:") }) { return .dotnet }
        if m.nodes.contains(where: { $0.id.hasPrefix("gr:") }) { return .gradle }
        return .swiftPackage
    }
}

/// Generates an empty project skeleton from an architecture diagram: one module per target, wired by its dependencies.
enum ArchitectureScaffold {
    static func generate(_ model: ArchitectureModel, target: ScaffoldTarget, project: String) throws -> GeneratedProject {
        let modules = model.nodes.filter { $0.kind != .system && $0.kind != .externalPackage }
        guard !modules.isEmpty else { throw CodeGenError.nothingToGenerate("The diagram has no targets to create.") }
        let externals = model.nodes.filter { $0.kind == .externalPackage }
        let names = Ident.unique(modules.map { Ident.pascal($0.name, reserved: []) })
        var nameOf: [String: String] = [:]
        for (n, name) in zip(modules, names) { nameOf[n.id] = name }
        func deps(_ id: String) -> [String] {
            var seen = Set<String>(), out: [String] = []
            for e in model.edges where e.from == id { if let n = nameOf[e.to], n != nameOf[id], seen.insert(n).inserted { out.append(n) } }
            return out
        }
        func externalDeps(_ id: String) -> [String] {
            model.edges.filter { $0.from == id }.compactMap { e in externals.first { $0.id == e.to }?.name }
        }
        let solution = Ident.pascal(project, reserved: [])
        var p = GeneratedProject()

        switch target {
        case .swiftPackage:
            var targets: [String] = [], products: [String] = []
            for (n, name) in zip(modules, names) {
                let d = deps(n.id).map { "\"\($0)\"" }.joined(separator: ", ")
                let isTest = n.kind == .tests
                let kind = isTest ? ".testTarget" : (n.kind == .app || n.kind == .tool ? ".executableTarget" : ".target")
                targets.append("        \(kind)(name: \"\(name)\"\(d.isEmpty ? "" : ", dependencies: [\(d)]"))")
                if !isTest { products.append(n.kind == .app || n.kind == .tool ? "        .executable(name: \"\(name)\", targets: [\"\(name)\"])" : "        .library(name: \"\(name)\", targets: [\"\(name)\"])") }
                let dir = isTest ? "Tests/\(name)" : "Sources/\(name)"
                if isTest { p.add("\(dir)/\(name).swift", "import XCTest\n\nfinal class \(name)Tests: XCTestCase {\n    func testPlaceholder() { }\n}") }
                else if n.kind == .app || n.kind == .tool { p.add("\(dir)/main.swift", "import Foundation\n\nprint(\"\(name)\")") }
                else { p.add("\(dir)/\(name).swift", "public struct \(name) {\n    public init() {}\n}") }
            }
            p.add("Package.swift", "// swift-tools-version:5.9\nimport PackageDescription\n\nlet package = Package(\n    name: \"\(solution)\",\n    products: [\n\(products.joined(separator: ",\n"))\n    ],\n    targets: [\n\(targets.joined(separator: ",\n"))\n    ]\n)")
        case .dotnet:
            var projects: [(name: String, guid: String)] = []
            for (n, name) in zip(modules, names) {
                let guid = UUID().uuidString
                projects.append((name, guid))
                let isTest = n.kind == .tests, isExe = n.kind == .app || n.kind == .tool
                var refs = deps(n.id).map { "    <ProjectReference Include=\"..\\\($0)\\\($0).csproj\" />" }
                var pk = externalDeps(n.id).map { "    <!-- TODO: <PackageReference Include=\"\($0)\" Version=\"…\" /> -->" }
                if isTest { pk.insert("    <PackageReference Include=\"Microsoft.NET.Test.Sdk\" Version=\"17.10.0\" />\n    <PackageReference Include=\"xunit\" Version=\"2.9.0\" />", at: 0) }
                refs = refs.isEmpty ? [] : ["  </ItemGroup>", "  <ItemGroup>"].dropFirst().dropFirst() + refs
                var xml = "<Project Sdk=\"Microsoft.NET.Sdk\">\n\n  <PropertyGroup>\n    <TargetFramework>net8.0</TargetFramework>\n    <ImplicitUsings>enable</ImplicitUsings>\n    <Nullable>enable</Nullable>\n"
                if isExe { xml += "    <OutputType>Exe</OutputType>\n" }
                if isTest { xml += "    <IsPackable>false</IsPackable>\n" }
                xml += "  </PropertyGroup>\n"
                if !refs.isEmpty { xml += "\n  <ItemGroup>\n" + refs.joined(separator: "\n") + "\n  </ItemGroup>\n" }
                if !pk.isEmpty { xml += "\n  <ItemGroup>\n" + pk.joined(separator: "\n") + "\n  </ItemGroup>\n" }
                xml += "\n</Project>"
                p.add("\(name)/\(name).csproj", xml)
                if isExe { p.add("\(name)/Program.cs", "Console.WriteLine(\"\(name)\");") }
                else if isTest { p.add("\(name)/\(name)Tests.cs", "using Xunit;\n\nnamespace \(name);\n\npublic class \(name)Tests\n{\n    [Fact]\n    public void Placeholder() { }\n}") }
                else { p.add("\(name)/\(name).cs", "namespace \(name);\n\npublic class \(name)Placeholder\n{\n}") }
            }
            var sln = "Microsoft Visual Studio Solution File, Format Version 12.00\n"
            for pr in projects { sln += "Project(\"{9A19103F-16F7-4668-BE54-9A1E7A4F7556}\") = \"\(pr.name)\", \"\(pr.name)\\\(pr.name).csproj\", \"{\(pr.guid)}\"\nEndProject\n" }
            sln += "Global\n\tGlobalSection(SolutionConfigurationPlatforms) = preSolution\n\t\tDebug|Any CPU = Debug|Any CPU\n\t\tRelease|Any CPU = Release|Any CPU\n\tEndGlobalSection\n\tGlobalSection(ProjectConfigurationPlatforms) = postSolution\n"
            for pr in projects { for c in ["Debug", "Release"] { sln += "\t\t{\(pr.guid)}.\(c)|Any CPU.ActiveCfg = \(c)|Any CPU\n\t\t{\(pr.guid)}.\(c)|Any CPU.Build.0 = \(c)|Any CPU\n" } }
            sln += "\tEndGlobalSection\nEndGlobal\n"
            p.add("\(solution).sln", sln)
        case .gradle:
            let dirs = names.map { $0.lowercased() }
            p.add("settings.gradle.kts", "rootProject.name = \"\(Ident.package(project))\"\n\n" + dirs.map { "include(\"\($0)\")" }.joined(separator: "\n"))
            for (n, dir) in zip(modules, dirs) {
                let isApp = n.kind == .app || n.kind == .tool
                var g = "plugins {\n    kotlin(\"jvm\") version \"1.9.24\"\n" + (isApp ? "    application\n" : "") + "}\n\nrepositories {\n    mavenCentral()\n}\n\ndependencies {\n"
                for d in deps(n.id) { g += "    implementation(project(\":\(d.lowercased())\"))\n" }
                for e in externalDeps(n.id) { g += "    // TODO: implementation(\"…\") for \(e)\n" }
                if n.kind == .tests { g += "    testImplementation(kotlin(\"test\"))\n" }
                g += "}\n\nkotlin {\n    jvmToolchain(17)\n}\n"
                if isApp { g += "\napplication {\n    mainClass.set(\"\(dir).MainKt\")\n}\n" }
                p.add("\(dir)/build.gradle.kts", g)
                if isApp { p.add("\(dir)/src/main/kotlin/\(dir)/Main.kt", "package \(dir)\n\nfun main() {\n    println(\"\(dir)\")\n}") }
                else if n.kind == .tests { p.add("\(dir)/src/test/kotlin/\(dir)/PlaceholderTest.kt", "package \(dir)\n\nimport kotlin.test.Test\n\nclass PlaceholderTest {\n    @Test\n    fun placeholder() { }\n}") }
                else { p.add("\(dir)/src/main/kotlin/\(dir)/Placeholder.kt", "package \(dir)\n\nclass Placeholder") }
            }
        }

        var readme = "# \(solution)\n\nGenerated by Graffle from a software architecture diagram (\(target.title)): \(modules.count) target\(modules.count == 1 ? "" : "s").\n\nEach target is an empty module wired to the ones it depends on in the diagram.\n"
        if !externals.isEmpty { readme += "\n## External packages to add\n\n" + externals.map { "- \($0.name)" + ($0.detail.isEmpty ? "" : " — \($0.detail)") }.joined(separator: "\n") + "\n" }
        p.add("README.md", readme)
        p.notes = externals.isEmpty ? [] : ["External packages are listed in README.md; add them by hand."]
        p.summary = "\(modules.count) \(target.title) module\(modules.count == 1 ? "" : "s")"
        return p
    }
}
