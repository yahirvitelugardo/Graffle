import Foundation

/// Analyzes an Xcode workspace, an Xcode project, a Swift package or a folder containing one of them.
enum ArchitectureImporter {
    enum Source: Equatable {
        case workspace(URL), project(URL), package(URL), solution(URL), dotnetProject(URL), gradle(URL)

        var url: URL {
            switch self { case .workspace(let u), .project(let u), .package(let u), .solution(let u), .dotnetProject(let u), .gradle(let u): return u }
        }
    }

    enum ImportError: LocalizedError {
        case nothingToAnalyze(String)
        case empty

        var errorDescription: String? {
            switch self {
            case .nothingToAnalyze(let name): return "No Xcode project, workspace, Package.swift, .NET solution or project, or Gradle build was found in \(name)."
            case .empty: return "The project has no targets to draw."
            }
        }
    }

    /// What `url` is: a workspace/project/package itself, or the best candidate inside a folder
    /// (workspace first, then project, then package).
    static func detect(_ url: URL) -> Source? {
        let fm = FileManager.default
        switch url.pathExtension.lowercased() {
        case "xcworkspace": return .workspace(url)
        case "xcodeproj": return .project(url)
        case "sln", "slnx": return .solution(url)
        case let e where DotNetParser.projectExtensions.contains(e): return .dotnetProject(url)
        default: break
        }
        if GradleParser.settingsNames.contains(url.lastPathComponent) || GradleParser.buildNames.contains(url.lastPathComponent),
           let r = GradleParser.root(for: url) { return .gradle(r) }
        if url.lastPathComponent == "Package.swift" { return .package(url.deletingLastPathComponent()) }
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue else { return nil }
        let entries = ((try? fm.contentsOfDirectory(at: url, includingPropertiesForKeys: nil)) ?? [])
            .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
        if let w = entries.first(where: { $0.pathExtension == "xcworkspace" }) { return .workspace(w) }
        if let p = entries.first(where: { $0.pathExtension == "xcodeproj" }) { return .project(p) }
        if fm.fileExists(atPath: url.appendingPathComponent("Package.swift").path) { return .package(url) }
        if GradleParser.settingsNames.contains(where: { fm.fileExists(atPath: url.appendingPathComponent($0).path) }) { return .gradle(url) }
        if let sln = entries.first(where: { ["sln", "slnx"].contains($0.pathExtension.lowercased()) }) { return .solution(sln) }
        if let proj = entries.first(where: { DotNetParser.projectExtensions.contains($0.pathExtension.lowercased()) }) { return .dotnetProject(proj) }
        return nil
    }

    /// Reads everything, then drops what `options` leaves out.
    static func analyze(_ url: URL, options: ArchitectureOptions = ArchitectureOptions(),
                        runner: @escaping SwiftPackageParser.Runner = SwiftPackageParser.defaultRunner,
                        progress: ((String) -> Void)? = nil) throws -> ArchitectureGraph {
        guard let source = detect(url) else { throw ImportError.nothingToAnalyze(url.lastPathComponent) }
        var run = Run(runner: runner, progress: progress)
        var graph: ArchitectureGraph
        switch source {
        case .workspace(let ws):
            let contents = XcodeWorkspaceParser.parse(workspaceURL: ws)
            graph = ArchitectureGraph(title: ws.deletingPathExtension().lastPathComponent, source: "Xcode workspace")
            let versions = SwiftPackageResolved.versions(at: ws.appendingPathComponent("xcshareddata/swiftpm/Package.resolved"))
            for p in contents.projects { try run.addProject(p, into: &graph, versions: versions) }
            for f in contents.packageFolders { try run.addPackage(f, into: &graph, versions: versions, depth: 0) }
        case .project(let p):
            graph = ArchitectureGraph(title: p.deletingPathExtension().lastPathComponent, source: "Xcode project")
            try run.addProject(p, into: &graph, versions: [:])
        case .package(let f):
            graph = ArchitectureGraph(title: f.lastPathComponent, source: "Swift package")
            try run.addPackage(f, into: &graph, versions: [:], depth: 0)
        case .gradle(let dir):
            graph = GradleParser.parse(root: dir, progress: progress)
            graph.source = "Gradle build"
        case .solution(let sln):
            graph = ArchitectureGraph(title: sln.deletingPathExtension().lastPathComponent, source: ".NET solution")
            for p in DotNetParser.projects(inSolution: sln) { run.addDotNet(p, into: &graph) }
        case .dotnetProject(let proj):
            graph = ArchitectureGraph(title: proj.deletingPathExtension().lastPathComponent, source: ".NET project")
            run.addDotNet(proj, into: &graph)
        }
        if graph.nodes.isEmpty { throw ImportError.empty }
        return graph.filtered(options)
    }

    /// State shared while following projects and local packages, so none is read twice.
    private struct Run {
        var runner: SwiftPackageParser.Runner
        var progress: ((String) -> Void)?
        var projectsDone = Set<String>()
        var dotnetDone = Set<String>()

        /// Reads a .NET project and, in turn, the projects it references.
        mutating func addDotNet(_ url: URL, into graph: inout ArchitectureGraph) {
            guard dotnetDone.insert(url.standardizedFileURL.path).inserted, FileManager.default.fileExists(atPath: url.path) else { return }
            progress?("Reading \(url.lastPathComponent)…")
            let parsed = DotNetParser.parse(projectURL: url, into: &graph)
            for ref in parsed.references {
                addDotNet(ref, into: &graph)
                graph.connect(parsed.id, "dn:" + ref.deletingPathExtension().lastPathComponent, .dependsOn)
            }
        }
        var packages: [String: SwiftPackageParser.Result] = [:]

        mutating func addProject(_ url: URL, into graph: inout ArchitectureGraph, versions: [String: String]) throws {
            let key = url.standardizedFileURL.path
            guard projectsDone.insert(key).inserted else { return }
            progress?("Reading \(url.lastPathComponent)…")
            var v = versions
            for c in SwiftPackageResolved.candidates(forProjectAt: url) {
                for (k, val) in SwiftPackageResolved.versions(at: c) where v[k] == nil { v[k] = val }
            }
            let r = try XcodeProjectParser.parse(projectURL: url, packageVersions: v)
            graph.merge(r.graph)
            for use in r.localPackageUses {
                let folder = URL(fileURLWithPath: use.packagePath, relativeTo: r.projectFolder).standardizedFileURL
                try link(use, folder: folder, into: &graph, versions: v, depth: 0)
            }
            for other in r.referencedProjects {
                try? addProject(other, into: &graph, versions: v)
            }
        }

        mutating func addPackage(_ folder: URL, into graph: inout ArchitectureGraph, versions: [String: String], depth: Int) throws {
            _ = try load(folder, into: &graph, versions: versions, depth: depth)
        }

        /// Reads a package once, merges its nodes, follows its own local dependencies.
        @discardableResult
        mutating func load(_ folder: URL, into graph: inout ArchitectureGraph, versions: [String: String], depth: Int) throws -> SwiftPackageParser.Result {
            let key = folder.standardizedFileURL.path
            if let done = packages[key] { return done }
            progress?("Reading package \(folder.lastPathComponent)…")
            var v = versions
            for (k, val) in SwiftPackageResolved.versions(at: folder.appendingPathComponent("Package.resolved")) where v[k] == nil { v[k] = val }
            let r = try SwiftPackageParser.parse(folder: folder, packageVersions: v, runner: runner)
            packages[key] = r
            graph.merge(r.graph)
            if depth < 4 {
                for use in r.localUses {
                    let sub = URL(fileURLWithPath: use.packagePath, relativeTo: folder).standardizedFileURL
                    try link(use, folder: sub, into: &graph, versions: v, depth: depth + 1)
                }
            }
            return r
        }

        /// Draws "target uses product P of the local package at `folder`" as edges to the targets P is made of.
        mutating func link(_ use: XcodeProjectParser.LocalPackageUse, folder: URL, into graph: inout ArchitectureGraph,
                           versions: [String: String], depth: Int) throws {
            guard depth < 4, let r = try? load(folder, into: &graph, versions: versions, depth: depth) else { return }
            for t in r.productTargets[use.product] ?? [] { graph.connect(use.fromTarget, t, .dependsOn) }
        }
    }
}
