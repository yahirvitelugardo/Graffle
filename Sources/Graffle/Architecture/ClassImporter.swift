import Foundation

/// Reads the source files of a project (Xcode, Swift package, .NET, Android/Gradle, or any folder) and builds its class diagram.
enum ClassImporter {
    enum ImportError: LocalizedError {
        case nothingToAnalyze(String)
        case noTypes

        var errorDescription: String? {
            switch self {
            case .nothingToAnalyze(let name): return "\(name) isn't a folder or project Graffle can read."
            case .noTypes: return "No classes, structs, enums, protocols or interfaces were found. Graffle reads Swift, C#, Kotlin and Java files."
            }
        }
    }

    static let skippedFolders: Set<String> = [
        ".build", "build", "Pods", "Carthage", "DerivedData", "node_modules", ".git", "bin", "obj", "SourcePackages", "checkouts", ".swiftpm",
        ".gradle", ".idea", "Generated", "xcuserdata", ".svn",
    ]
    static let maxFiles = 4000
    static let maxFileSize = 1_500_000

    /// The folder whose source files describe `url`.
    static func root(for url: URL) -> URL? {
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) else { return nil }
        if let source = ArchitectureImporter.detect(url) {
            switch source {
            case .workspace(let u), .project(let u), .solution(let u), .dotnetProject(let u): return u.deletingLastPathComponent()
            case .package(let u), .gradle(let u): return u
            }
        }
        return isDir.boolValue ? url : url.deletingLastPathComponent()
    }

    static func sourceFiles(in root: URL) -> [URL] {
        guard let walker = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.isDirectoryKey, .fileSizeKey],
                                                          options: [.skipsHiddenFiles, .skipsPackageDescendants]) else { return [] }
        var files: [URL] = []
        for case let url as URL in walker {
            if skippedFolders.contains(url.lastPathComponent) { walker.skipDescendants(); continue }
            guard SourceLanguage(pathExtension: url.pathExtension) != nil else { continue }
            if let size = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize, size > maxFileSize { continue }
            files.append(url)
            if files.count >= maxFiles { break }
        }
        return files.sorted { $0.path < $1.path }
    }

    static func looksLikeTest(_ path: String, name: String) -> Bool {
        let parts = path.split(separator: "/")
        if parts.contains(where: { ["Tests", "Test", "UnitTests", "UITests", "androidTest", "test", "tests", "IntegrationTests"].contains(String($0)) }) { return true }
        if parts.contains(where: { $0.hasSuffix("Tests") || $0.hasSuffix(".Tests") }) { return true }
        return name.hasSuffix("Tests") || name.hasSuffix("Test") || name.hasSuffix("Spec")
    }

    static func analyze(_ url: URL, options: ClassOptions = ClassOptions(), progress: ((String) -> Void)? = nil) throws -> ClassGraph {
        guard let root = root(for: url) else { throw ImportError.nothingToAnalyze(url.lastPathComponent) }
        var title = root.lastPathComponent
        var sourceName = "Source folder"
        if let source = ArchitectureImporter.detect(url) {
            switch source {
            case .workspace(let u): title = u.deletingPathExtension().lastPathComponent; sourceName = "Xcode workspace"
            case .project(let u): title = u.deletingPathExtension().lastPathComponent; sourceName = "Xcode project"
            case .package(let u): title = u.lastPathComponent; sourceName = "Swift package"
            case .solution(let u): title = u.deletingPathExtension().lastPathComponent; sourceName = ".NET solution"
            case .dotnetProject(let u): title = u.deletingPathExtension().lastPathComponent; sourceName = ".NET project"
            case .gradle(let u): title = u.lastPathComponent; sourceName = "Gradle build"
            }
        }

        var scanned: [TypeInfo] = []
        var extensions: [TypeScanner.Extension] = []
        let files = sourceFiles(in: root)
        for (i, file) in files.enumerated() {
            if i % 50 == 0 { progress?("Reading source files… \(i) of \(files.count)") }
            guard let language = SourceLanguage(pathExtension: file.pathExtension),
                  let text = (try? String(contentsOf: file, encoding: .utf8)) ?? (try? String(contentsOf: file, encoding: .isoLatin1)) else { continue }
            let relative = file.path.hasPrefix(root.path) ? String(file.path.dropFirst(root.path.count + 1)) : file.lastPathComponent
            var result = TypeScanner.scan(text, language: language, file: relative, includePrivate: options.includePrivate)
            let test = looksLikeTest(relative, name: file.deletingPathExtension().lastPathComponent)
            for i in result.types.indices { result.types[i].isTest = test }
            scanned += result.types
            extensions += result.extensions
        }

        var graph = build(types: scanned, extensions: extensions, options: options)
        graph.title = title
        graph.source = sourceName
        if graph.types.isEmpty { throw ImportError.noTypes }
        return graph
    }

    /// Merges duplicate names, adds what extensions contribute, drops what the options leave out, links the types, and cuts huge graphs.
    static func build(types scanned: [TypeInfo], extensions: [TypeScanner.Extension], options: ClassOptions) -> ClassGraph {
        var byName: [String: TypeInfo] = [:]
        var order: [String] = []
        for t in scanned {
            if let existing = byName[t.name] {
                // A type name used twice (two modules, a nested type): keep the fuller one.
                if t.properties.count + t.methods.count > existing.properties.count + existing.methods.count, !(t.isTest && !existing.isTest) { byName[t.name] = t }
            } else {
                byName[t.name] = t
                order.append(t.name)
            }
        }
        for e in extensions {
            guard var t = byName[e.name] else { continue }
            for s in e.supertypes where !t.supertypes.contains(s) { t.supertypes.append(s) }
            for p in e.properties where !t.properties.contains(p) { t.properties.append(p) }
            for m in e.methods where !t.methods.contains(m) { t.methods.append(m) }
            byName[e.name] = t
        }
        var types = order.compactMap { byName[$0] }
        if !options.includeTests { types.removeAll { $0.isTest } }

        let known = Set(types.map(\.name))
        let kindOf = Dictionary(types.map { ($0.name, $0.kind) }, uniquingKeysWith: { a, _ in a })
        var relations = Set<TypeRelation>()
        for t in types {
            for s in t.supertypes where known.contains(s) && s != t.name {
                relations.insert(TypeRelation(from: t.name, to: s, kind: (kindOf[s]?.isInterface ?? false) ? .implements : .inherits))
            }
        }
        // A property whose type is another known type: an association (not drawn when the pair is already related).
        let related = Set(relations.flatMap { [$0.from + "\u{0}" + $0.to, $0.to + "\u{0}" + $0.from] })
        let word = try? NSRegularExpression(pattern: #"[A-Za-z_]\w*"#)
        for t in types {
            for p in t.properties where !p.hasPrefix("case ") {
                guard let colon = p.firstIndex(of: ":") else { continue }
                let type = String(p[p.index(after: colon)...])
                let ns = type as NSString
                for m in word?.matches(in: type, range: NSRange(location: 0, length: ns.length)) ?? [] {
                    let w = ns.substring(with: m.range)
                    if w != t.name, known.contains(w), !related.contains(t.name + "\u{0}" + w) {
                        relations.insert(TypeRelation(from: t.name, to: w, kind: .association))
                    }
                }
            }
        }

        var graph = ClassGraph(types: types, relations: relations.sorted { ($0.from, $0.to) < ($1.from, $1.to) })
        if types.count > options.maxTypes {
            var degree: [String: Int] = [:]
            for r in graph.relations { degree[r.from, default: 0] += 1; degree[r.to, default: 0] += 1 }
            let keep = Set(types.sorted { (degree[$0.name] ?? 0, $1.name) > (degree[$1.name] ?? 0, $0.name) }.prefix(options.maxTypes).map(\.name))
            graph.truncated = (keep.count, types.count)
            graph.types = types.filter { keep.contains($0.name) }
            graph.relations = graph.relations.filter { keep.contains($0.from) && keep.contains($0.to) }
        }
        return graph
    }
}
