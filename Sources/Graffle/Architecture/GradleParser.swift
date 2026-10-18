import Foundation

/// Reads a Gradle build (Android or JVM) without running Gradle: `settings.gradle(.kts)` lists the modules, each module's
/// `build.gradle(.kts)` its plugins and dependencies, and `gradle/libs.versions.toml` resolves version-catalog names.
enum GradleParser {
    static let settingsNames = ["settings.gradle.kts", "settings.gradle"]
    static let buildNames = ["build.gradle.kts", "build.gradle"]

    /// The folder holding `settings.gradle(.kts)`, starting at `url` (a folder or a Gradle file) and looking up a few levels.
    static func root(for url: URL) -> URL? {
        var isDir: ObjCBool = false
        var dir = FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) && !isDir.boolValue ? url.deletingLastPathComponent() : url
        for _ in 0..<5 {
            if settingsNames.contains(where: { FileManager.default.fileExists(atPath: dir.appendingPathComponent($0).path) }) { return dir }
            let up = dir.deletingLastPathComponent()
            if up == dir { break }
            dir = up
        }
        return nil
    }

    private static func read(_ url: URL) -> String {
        let text = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
        // Drop // and /* */ comments so commented-out modules and dependencies don't count.
        var out = text.replacingOccurrences(of: "/\\*[\\s\\S]*?\\*/", with: "", options: .regularExpression)
        out = out.replacingOccurrences(of: "(?m)(^|[^:\"'])//.*$", with: "$1", options: .regularExpression)
        return out
    }

    private static func firstFile(_ names: [String], in dir: URL) -> URL? {
        names.map { dir.appendingPathComponent($0) }.first { FileManager.default.fileExists(atPath: $0.path) }
    }

    private static func matches(_ pattern: String, in text: String) -> [[String]] {
        guard let re = try? NSRegularExpression(pattern: pattern) else { return [] }
        let ns = text as NSString
        return re.matches(in: text, range: NSRange(location: 0, length: ns.length)).map { m in
            (0..<m.numberOfRanges).map { m.range(at: $0).location == NSNotFound ? "" : ns.substring(with: m.range(at: $0)) }
        }
    }

    /// "androidApplication", "android-application" and "android.application" all become "androidapplication".
    private static func squash(_ s: String) -> String {
        s.lowercased().filter { $0 != "." && $0 != "-" && $0 != "_" }
    }

    // MARK: Version catalog

    struct Catalog {
        var libraries: [String: (module: String, version: String)] = [:]    // squashed alias -> coordinates
        var plugins: [String: String] = [:]                                    // squashed alias -> plugin id
    }

    static func catalog(in root: URL) -> Catalog {
        var c = Catalog()
        let file = root.appendingPathComponent("gradle/libs.versions.toml")
        guard let text = try? String(contentsOf: file, encoding: .utf8) else { return c }
        var versions: [String: String] = [:]
        var section = ""
        for raw in text.split(whereSeparator: \.isNewline) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("#") || line.isEmpty { continue }
            if line.hasPrefix("[") { section = line.trimmingCharacters(in: CharacterSet(charactersIn: "[] ")); continue }
            guard let eq = line.firstIndex(of: "=") else { continue }
            let key = line[..<eq].trimmingCharacters(in: .whitespaces)
            let value = String(line[line.index(after: eq)...]).trimmingCharacters(in: .whitespaces)
            func attr(_ name: String) -> String? { matches("\(name)\\s*=\\s*\"([^\"]*)\"", in: value).first?[1] }
            switch section {
            case "versions":
                versions[key] = value.trimmingCharacters(in: CharacterSet(charactersIn: "\"")).isEmpty ? attr("strictly") ?? "" : (value.hasPrefix("\"") ? value.trimmingCharacters(in: CharacterSet(charactersIn: "\"")) : attr("require") ?? attr("strictly") ?? "")
            case "libraries":
                var module = attr("module") ?? ""
                if module.isEmpty, let g = attr("group"), let n = attr("name") { module = "\(g):\(n)" }
                var version = attr("version") ?? ""
                if let ref = attr("version.ref") ?? matches("version\\s*=\\s*\\{\\s*ref\\s*=\\s*\"([^\"]*)\"", in: value).first?[1] { version = versions[ref] ?? "" }
                if value.hasPrefix("\"") {                                     // key = "group:artifact:version"
                    let parts = value.trimmingCharacters(in: CharacterSet(charactersIn: "\"")).split(separator: ":").map(String.init)
                    if parts.count >= 2 { module = parts[0] + ":" + parts[1]; version = parts.count > 2 ? parts[2] : "" }
                }
                if !module.isEmpty { c.libraries[squash(key)] = (module, version) }
            case "plugins":
                if let id = attr("id") { c.plugins[squash(key)] = id }
                else if value.hasPrefix("\"") { c.plugins[squash(key)] = value.split(separator: ":").first.map { String($0).trimmingCharacters(in: CharacterSet(charactersIn: "\"")) } ?? "" }
            default:
                break
            }
        }
        return c
    }

    // MARK: Modules

    /// Module paths (":app", ":core:data") from `include(...)`, in the order written.
    static func modulePaths(settings: String) -> [String] {
        var out: [String] = []
        let lines = settings.components(separatedBy: .newlines)
        var i = 0
        while i < lines.count {
            if lines[i].range(of: "\\binclude\\b(?!Build)", options: .regularExpression) != nil {
                var j = i
                while j < lines.count {
                    for m in matches("[\"'](:?[\\w\\-.:]+)[\"']", in: lines[j]) {
                        var p = m[1]
                        if !p.hasPrefix(":") { p = ":" + p }
                        if !out.contains(p) { out.append(p) }
                    }
                    let t = lines[j].trimmingCharacters(in: .whitespaces)
                    if t.hasSuffix(",") || t.hasSuffix("(") { j += 1 } else { break }
                }
                i = j
            }
            i += 1
        }
        return out
    }

    static func parse(root: URL, progress: ((String) -> Void)? = nil) -> ArchitectureGraph {
        let settings = firstFile(settingsNames, in: root).map(read) ?? ""
        var paths = modulePaths(settings: settings)
        let rootName = matches("rootProject\\.name\\s*=\\s*[\"']([^\"']+)[\"']", in: settings).first?[1] ?? root.lastPathComponent
        // The root project is a module only when it is the whole build, or has code of its own (usually it just configures the others).
        let rootHasCode = FileManager.default.fileExists(atPath: root.appendingPathComponent("src").path)
        if firstFile(buildNames, in: root) != nil, !paths.contains(":"), paths.isEmpty || rootHasCode { paths.insert(":", at: 0) }

        // `project(":x").projectDir = file("y")` moves a module.
        var dirOverride: [String: String] = [:]
        for m in matches("project\\(\\s*[\"'](:[^\"']+)[\"']\\s*\\)\\.projectDir\\s*=\\s*(?:new\\s+)?[Ff]ile\\(\\s*[\"']([^\"']+)[\"']", in: settings) { dirOverride[m[1]] = m[2] }

        let cat = catalog(in: root)
        var graph = ArchitectureGraph(title: rootName, source: "Gradle build")
        struct Module { var path: String; var dir: URL; var build: String }
        var modules: [Module] = []
        for p in paths {
            let dir = p == ":" ? root : root.appendingPathComponent(dirOverride[p] ?? String(p.dropFirst()).replacingOccurrences(of: ":", with: "/"))
            let build = firstFile(buildNames, in: dir).map(read) ?? ""
            modules.append(Module(path: p, dir: dir, build: build))
        }
        func id(_ path: String) -> String { "gr:" + path }
        func display(_ path: String) -> String { path == ":" ? rootName : String(path.dropFirst()) }
        let bySquashed = Dictionary(modules.map { (squash($0.path.replacingOccurrences(of: ":", with: ".")), $0.path) }, uniquingKeysWith: { a, _ in a })

        for m in modules {
            progress?("Reading \(display(m.path))…")
            let plugins = pluginIDs(in: m.build, catalog: cat).map(squash)
            func has(_ s: String) -> Bool { plugins.contains { $0.contains(s) } }
            let kind: NodeKind, label: String
            if has("androidapplication") { (kind, label) = (.app, "Android app") }
            else if has("androiddynamicfeature") { (kind, label) = (.appExtension, "Dynamic feature") }
            else if has("androidtest") && !has("androidtestimpl") { (kind, label) = (.tests, "Android test") }
            else if has("androidlibrary") { (kind, label) = (.library, "Android library") }
            else if has("kotlinmultiplatform") { (kind, label) = (.library, "Multiplatform") }
            else if has("javalibrary") || has("kotlinjvm") || has("kotlinandroid") || has("javaplatform") || plugins.contains("java") || plugins.contains("kotlin") { (kind, label) = (.library, "JVM library") }
            else if m.build.isEmpty { (kind, label) = (.other, "No build file") }
            else { (kind, label) = (.library, "Module") }

            var counts = (kotlin: 0, java: 0)
            if let walker = FileManager.default.enumerator(at: m.dir, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) {
                for case let f as URL in walker {
                    let name = f.lastPathComponent
                    if ["build", "node_modules", "Pods"].contains(name) { walker.skipDescendants(); continue }
                    // A nested module is counted as its own, not as part of this one.
                    if f.hasDirectoryPath, f != m.dir, modules.contains(where: { $0.dir.standardizedFileURL == f.standardizedFileURL && $0.path != m.path }) { walker.skipDescendants(); continue }
                    switch f.pathExtension.lowercased() { case "kt": counts.kotlin += 1; case "java": counts.java += 1; default: break }
                }
            }
            var parts = [label]
            if let min = matches("minSdk(?:Version)?\\s*=?\\s*(\\d+)", in: m.build).first?[1] { parts.append("minSdk \(min)") }
            let total = counts.kotlin + counts.java
            if total > 0 {
                let langs = [counts.kotlin > 0 ? "Kotlin" : nil, counts.java > 0 ? "Java" : nil].compactMap { $0 }.joined(separator: "/")
                parts.append("\(langs) · \(total) file" + (total == 1 ? "" : "s"))
            }
            graph.add(ArchitectureNode(id: id(m.path), name: display(m.path), kind: kind, detail: parts.joined(separator: " · "), container: rootName))
        }

        let skipConfigs = ["test", "androidtest", "testfixtures"]
        for m in modules {
            for dep in dependencies(in: m.build) {
                let config = dep.configuration.lowercased()
                if skipConfigs.contains(where: { config.hasPrefix($0) }) { continue }
                switch dep.target {
                case .project(let path):
                    let normal = path.hasPrefix(":") ? path : ":" + path
                    if modules.contains(where: { $0.path == normal }) { graph.connect(id(m.path), id(normal), .dependsOn) }
                case .accessor(let name):
                    if let path = bySquashed[squash(name)] { graph.connect(id(m.path), id(path), .dependsOn) }
                case .coordinates(let module, let version):
                    addExternal(module, version: version, from: id(m.path), into: &graph)
                case .catalog(let alias):
                    if let lib = cat.libraries[squash(alias)] { addExternal(lib.module, version: lib.version, from: id(m.path), into: &graph) }
                }
            }
        }
        return graph
    }

    private static func addExternal(_ module: String, version: String, from: String, into graph: inout ArchitectureGraph) {
        let parts = module.split(separator: ":").map(String.init)
        guard parts.count >= 2 else { return }
        let nid = "pkg:" + parts[0].lowercased() + ":" + parts[1].lowercased()
        graph.add(ArchitectureNode(id: nid, name: parts[1], kind: .externalPackage,
                                   detail: parts[0] + (version.isEmpty ? "" : " · \(version)"), container: "Packages"))
        graph.connect(from, nid, .package)
    }

    private static func pluginIDs(in build: String, catalog: Catalog) -> [String] {
        var ids: [String] = []
        for m in matches("id\\s*\\(?\\s*[\"']([^\"']+)[\"']", in: build) { ids.append(m[1]) }
        for m in matches("apply\\s+plugin\\s*:\\s*[\"']([^\"']+)[\"']", in: build) { ids.append(m[1]) }
        for m in matches("kotlin\\s*\\(\\s*[\"']([^\"']+)[\"']\\s*\\)", in: build) { ids.append("kotlin-" + m[1]) }
        for m in matches("alias\\s*\\(\\s*libs\\.plugins\\.([\\w.]+)\\s*\\)", in: build) {
            ids.append(catalog.plugins[squash(m[1])] ?? m[1])
        }
        for m in matches("^\\s*(java-library|java|kotlin|`java-library`|`kotlin-dsl`)\\s*$", in: build) { ids.append(m[1].trimmingCharacters(in: CharacterSet(charactersIn: "`"))) }
        return ids
    }

    enum Target {
        case project(String), accessor(String), coordinates(String, String), catalog(String)
    }

    struct Dependency { var configuration: String; var target: Target }

    static func dependencies(in build: String) -> [Dependency] {
        var out: [Dependency] = []
        let config = "([A-Za-z]*(?:[Ii]mplementation|[Aa]pi|[Cc]ompileOnly|[Rr]untimeOnly|[Cc]ompile|[Kk]apt|[Kk]sp|[Aa]nnotationProcessor))"
        // Statements can share a line (`dependencies { api(...); implementation(...) }`).
        let templated = build.replacingOccurrences(of: "\\$\\{([^}\\n]*)\\}", with: "$1", options: .regularExpression)   // ${v} must not look like a block
        let statements = templated.replacingOccurrences(of: "[{};]", with: "\n", options: .regularExpression)
        for line in statements.components(separatedBy: .newlines) {
            guard let c = matches("^\\s*\(config)\\b", in: line).first?[1] else { continue }
            if let p = matches("project\\(\\s*(?:path\\s*[=:]\\s*)?[\"'](:?[^\"']+)[\"']", in: line).first?[1] {
                out.append(Dependency(configuration: c, target: .project(p)))
            } else if let a = matches("\\bprojects\\.([\\w.]+)", in: line).first?[1] {
                out.append(Dependency(configuration: c, target: .accessor(a)))
            } else if let a = matches("\\blibs\\.(?!plugins\\.|versions\\.|bundles\\.)([\\w.]+)", in: line).first?[1] {
                out.append(Dependency(configuration: c, target: .catalog(a)))
            } else if let m = matches("[\"']([\\w.\\-]+):([\\w.\\-]+)(?::([\\w.\\-+${}]+))?[\"']", in: line).first {
                out.append(Dependency(configuration: c, target: .coordinates(m[1] + ":" + m[2], m[3])))
            }
        }
        return out
    }
}
