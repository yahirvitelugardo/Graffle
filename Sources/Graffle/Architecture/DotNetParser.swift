import Foundation

/// Reads .NET solutions (`.sln`, `.slnx`) and SDK-style or classic project files (`.csproj`, `.fsproj`, `.vbproj`)
/// into an `ArchitectureGraph`: projects, project references, NuGet packages and shared frameworks.
enum DotNetParser {
    static let projectExtensions: Set<String> = ["csproj", "fsproj", "vbproj"]

    /// Project files listed by a solution, absolute and existing or not.
    static func projects(inSolution url: URL) -> [URL] {
        let base = url.deletingLastPathComponent()
        var paths: [String] = []
        if url.pathExtension.lowercased() == "slnx" {
            if let data = try? Data(contentsOf: url), let doc = try? XMLDocument(data: data, options: []) {
                func walk(_ e: XMLElement) {
                    for c in (e.children ?? []).compactMap({ $0 as? XMLElement }) {
                        if c.name == "Project", let p = c.attribute(forName: "Path")?.stringValue { paths.append(p) }
                        walk(c)
                    }
                }
                if let root = doc.rootElement() { walk(root) }
            }
        } else if let text = try? String(contentsOf: url, encoding: .utf8) {
            // Project("{type}") = "Name", "relative\path.csproj", "{id}"
            for line in text.split(whereSeparator: \.isNewline) where line.hasPrefix("Project(") {
                let quoted = line.split(separator: "\"", omittingEmptySubsequences: true).map(String.init)
                // pieces: Project( , {type}, ) = , Name, ,  , path, ,  , {id}
                if let path = quoted.first(where: { projectExtensions.contains(($0.replacingOccurrences(of: "\\", with: "/") as NSString).pathExtension.lowercased()) }) {
                    paths.append(path)
                }
            }
        }
        return paths.map { base.appendingPathComponent($0.replacingOccurrences(of: "\\", with: "/")).standardizedFileURL }
    }

    struct Parsed {
        var id = ""
        /// Referenced project files; the caller reads them, then connects `id` to each (a node has to exist before an edge can).
        var references: [URL] = []
    }

    /// Adds one project (not the ones it references) to `graph` and returns what it references.
    static func parse(projectURL url: URL, into graph: inout ArchitectureGraph, packageVersions central: [String: String]? = nil) -> Parsed {
        let name = url.deletingPathExtension().lastPathComponent
        let id = "dn:" + name
        var out = Parsed(id: id)
        guard let data = try? Data(contentsOf: url), let doc = try? XMLDocument(data: data, options: []), let root = doc.rootElement() else {
            graph.add(ArchitectureNode(id: id, name: name, kind: .other, detail: "Unreadable project file", container: "Solution"))
            return out
        }
        let sdk = root.attribute(forName: "Sdk")?.stringValue ?? ""
        let folder = url.deletingLastPathComponent()

        func elements(_ tag: String) -> [XMLElement] {
            var found: [XMLElement] = []
            func walk(_ e: XMLElement) {
                for c in (e.children ?? []).compactMap({ $0 as? XMLElement }) {
                    if c.name == tag { found.append(c) }
                    walk(c)
                }
            }
            walk(root)
            return found
        }
        func property(_ tag: String) -> String? {
            elements(tag).compactMap { $0.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines) }.first { !$0.isEmpty }
        }

        let centralVersions = central ?? centralPackageVersions(from: folder)
        var packages: [(name: String, version: String)] = []
        for e in elements("PackageReference") {
            guard let n = e.attribute(forName: "Include")?.stringValue ?? e.attribute(forName: "Update")?.stringValue else { continue }
            let v = e.attribute(forName: "Version")?.stringValue ?? elements("Version").first { $0.parent === e }?.stringValue
                ?? centralVersions[n.lowercased()] ?? ""
            packages.append((n, v))
        }

        // What kind of project this is.
        let outputType = property("OutputType")?.lowercased() ?? ""
        let isTest = property("IsTestProject")?.lowercased() == "true"
            || packages.contains { $0.name.lowercased() == "microsoft.net.test.sdk" }
        let isWeb = sdk.contains("Sdk.Web")
        let kind: NodeKind, label: String
        if isTest { (kind, label) = (.tests, "Tests") }
        else if isWeb { (kind, label) = (.app, "Web app") }
        else if outputType == "exe" || outputType == "winexe" { (kind, label) = (.app, "Application") }
        else { (kind, label) = (.library, "Library") }

        let frameworks = (property("TargetFramework") ?? property("TargetFrameworks") ?? property("TargetFrameworkVersion")).map { $0.replacingOccurrences(of: ";", with: ", ") }
        let language = url.pathExtension.lowercased() == "fsproj" ? "F#" : (url.pathExtension.lowercased() == "vbproj" ? "VB" : "C#")
        let ext = url.pathExtension.lowercased() == "fsproj" ? "fs" : (url.pathExtension.lowercased() == "vbproj" ? "vb" : "cs")
        var files = 0
        if let walker = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) {
            for case let f as URL in walker {
                if ["bin", "obj", "node_modules"].contains(f.lastPathComponent) { walker.skipDescendants(); continue }
                if f.pathExtension.lowercased() == ext { files += 1 }
            }
        }
        var parts = [label]
        if let frameworks { parts.append(frameworks) }
        if files > 0 { parts.append("\(language) · \(files) file" + (files == 1 ? "" : "s")) }
        graph.add(ArchitectureNode(id: id, name: name, kind: kind, detail: parts.joined(separator: " · "), container: "Solution"))

        for e in elements("ProjectReference") {
            guard let path = e.attribute(forName: "Include")?.stringValue else { continue }
            let target = folder.appendingPathComponent(path.replacingOccurrences(of: "\\", with: "/")).standardizedFileURL
            let other = target.deletingPathExtension().lastPathComponent
            if !FileManager.default.fileExists(atPath: target.path) {
                graph.add(ArchitectureNode(id: "dn:" + other, name: other, kind: .other, detail: "Project file not found", container: "Solution"))
            }
            out.references.append(target)
        }
        for p in packages {
            let key = p.name.lowercased()
            graph.add(ArchitectureNode(id: "pkg:" + key, name: p.name, kind: .externalPackage,
                                       detail: "NuGet package" + (p.version.isEmpty ? "" : " · \(p.version)"), container: "Packages"))
            graph.connect(id, "pkg:" + key, .package)
        }
        for e in elements("FrameworkReference") {
            guard let n = e.attribute(forName: "Include")?.stringValue else { continue }
            graph.add(ArchitectureNode(id: "sys:" + n, name: n, kind: .system, detail: "Shared framework", container: "System"))
            graph.connect(id, "sys:" + n, .dependsOn)
        }
        return out
    }

    /// Central package management: `Directory.Packages.props` in this folder or above.
    static func centralPackageVersions(from folder: URL) -> [String: String] {
        var dir = folder
        for _ in 0..<8 {
            let props = dir.appendingPathComponent("Directory.Packages.props")
            if let data = try? Data(contentsOf: props), let doc = try? XMLDocument(data: data, options: []) {
                var out: [String: String] = [:]
                func walk(_ e: XMLElement) {
                    for c in (e.children ?? []).compactMap({ $0 as? XMLElement }) {
                        if c.name == "PackageVersion", let n = c.attribute(forName: "Include")?.stringValue,
                           let v = c.attribute(forName: "Version")?.stringValue { out[n.lowercased()] = v }
                        walk(c)
                    }
                }
                if let root = doc.rootElement() { walk(root) }
                return out
            }
            let up = dir.deletingLastPathComponent()
            if up == dir { break }
            dir = up
        }
        return [:]
    }
}
