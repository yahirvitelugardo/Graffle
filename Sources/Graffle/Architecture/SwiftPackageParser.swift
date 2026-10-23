import Foundation

/// Reads a Swift package with `swift package dump-package` (the official description of a manifest) and turns its
/// targets and their dependencies into an `ArchitectureGraph`.
enum SwiftPackageParser {
    struct Result {
        var graph: ArchitectureGraph
        /// Product name -> the node ids of the targets it is made of, for projects that use the package.
        var productTargets: [String: [String]]
        /// Dependencies on packages that live on disk, to be read in turn.
        var localUses: [XcodeProjectParser.LocalPackageUse]
        var name: String
    }

    enum ParseError: LocalizedError {
        case toolFailed(String)
        case unreadable

        var errorDescription: String? {
            switch self {
            case .toolFailed(let why): return "`swift package dump-package` failed: \(why)"
            case .unreadable: return "The package description couldn't be read."
            }
        }
    }

    /// Produces the JSON that `swift package dump-package` prints for a package folder. Replaceable, so tests can feed canned output.
    typealias Runner = (URL) throws -> Data

    #if !os(macOS)
    static let defaultRunner: Runner = { _ in
        throw ParseError.toolFailed("Reading a Swift package's manifest needs the Swift toolchain, which only exists on a Mac.")
    }
    #else
    static let defaultRunner: Runner = { folder in
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/swift")
        process.arguments = ["package", "--package-path", folder.path, "dump-package"]
        let out = Pipe()
        let errFile = FileManager.default.temporaryDirectory.appendingPathComponent("graffle-dump-\(UUID().uuidString).log")
        FileManager.default.createFile(atPath: errFile.path, contents: nil)
        defer { try? FileManager.default.removeItem(at: errFile) }
        process.standardOutput = out
        process.standardError = try FileHandle(forWritingTo: errFile)
        try process.run()

        // A manifest that hangs (say, waiting on the network) must not hang the app.
        let watchdog = DispatchWorkItem { if process.isRunning { process.terminate() } }
        DispatchQueue.global().asyncAfter(deadline: .now() + 90, execute: watchdog)
        let data = out.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        watchdog.cancel()
        guard process.terminationStatus == 0 else {
            let message = (try? String(contentsOf: errFile, encoding: .utf8)) ?? ""
            throw ParseError.toolFailed(String(message.suffix(400)).trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return data
    }
    #endif

    private struct External {
        var identity: String
        var display: String
        var requirement: String
        var localPath: String?
        var isLocal: Bool { localPath != nil }
    }

    static func parse(folder: URL, packageVersions: [String: String] = [:], runner: Runner = defaultRunner) throws -> Result {
        let data = try runner(folder)
        guard let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any], let name = root["name"] as? String else {
            throw ParseError.unreadable
        }

        // Packages this one depends on.
        var externals: [String: External] = [:]
        for entry in (root["dependencies"] as? [[String: Any]]) ?? [] {
            for (_, value) in entry {
                for e in (value as? [[String: Any]]) ?? [] {
                    guard let identity = (e["identity"] as? String)?.lowercased() else { continue }
                    var url: String?
                    if let loc = e["location"] as? [String: Any] {
                        if let remote = loc["remote"] as? [[String: Any]] { url = remote.first?["urlString"] as? String }
                        else if let remote = loc["remote"] as? [String] { url = remote.first }
                    }
                    let display = url.map { u -> String in
                        var last = u.split(separator: "/").last.map(String.init) ?? u
                        if last.hasSuffix(".git") { last.removeLast(4) }
                        return last
                    } ?? identity
                    externals[identity] = External(identity: identity, display: display, requirement: requirement(e["requirement"]),
                                                   localPath: e["path"] as? String)
                }
            }
        }

        var graph = ArchitectureGraph(title: name, source: "Package.swift")
        var localUses: [XcodeProjectParser.LocalPackageUse] = []
        let targets = (root["targets"] as? [[String: Any]]) ?? []
        let targetNames = Set(targets.compactMap { $0["name"] as? String })
        func id(_ target: String) -> String { "\(name):\(target)" }

        func externalNode(_ identity: String) -> String {
            let ext = externals[identity]
            let version = packageVersions[identity] ?? ext?.requirement ?? ""
            graph.add(ArchitectureNode(id: "pkg:\(identity)", name: ext?.display ?? identity, kind: .externalPackage,
                                       detail: "Swift package" + (version.isEmpty ? "" : " · \(version)"), container: "Packages"))
            return "pkg:\(identity)"
        }

        // Products, so a target can be described as a library or an executable, and others can find its targets.
        var productTargets: [String: [String]] = [:]
        for p in (root["products"] as? [[String: Any]]) ?? [] {
            guard let pname = p["name"] as? String else { continue }
            productTargets[pname] = ((p["targets"] as? [String]) ?? []).map(id)
        }

        for t in targets {
            guard let tname = t["name"] as? String else { continue }
            let type = (t["type"] as? String) ?? "regular"
            let kind: NodeKind, label: String
            switch type {
            case "executable": (kind, label) = (.tool, "Executable")
            case "test": (kind, label) = (.tests, "Tests")
            case "macro": (kind, label) = (.other, "Macro")
            case "plugin": (kind, label) = (.other, "Plugin")
            case "binary": (kind, label) = (.other, "Binary target")
            case "system": (kind, label) = (.other, "System library")
            default: (kind, label) = (.library, "Library")
            }
            var counts = SourceCounts()
            let rel = (t["path"] as? String) ?? ((type == "test" ? "Tests/" : "Sources/") + tname)
            counts.add(folder: folder.appendingPathComponent(rel))
            var parts = [label]
            if !counts.summary.isEmpty { parts.append(counts.summary) }
            graph.add(ArchitectureNode(id: id(tname), name: tname, kind: kind, detail: parts.joined(separator: " · "), container: name))
        }

        for t in targets {
            guard let tname = t["name"] as? String else { continue }
            for dep in (t["dependencies"] as? [[String: Any]]) ?? [] {
                if let a = dep["target"] as? [Any], let n = a.first as? String, targetNames.contains(n) {
                    graph.connect(id(tname), id(n), .dependsOn)
                } else if let a = dep["byName"] as? [Any], let n = a.first as? String {
                    if targetNames.contains(n) {
                        graph.connect(id(tname), id(n), .dependsOn)
                    } else if let ext = externals[n.lowercased()] {
                        if let path = ext.localPath { localUses.append(.init(fromTarget: id(tname), packagePath: path, product: n)) }
                        else { graph.connect(id(tname), externalNode(ext.identity), .package) }
                    } else {
                        graph.connect(id(tname), externalNode(n.lowercased()), .package)     // a product of a package we know nothing else about
                    }
                } else if let a = dep["product"] as? [Any], let product = a.first as? String {
                    let identity = (a.count > 1 ? a[1] as? String : nil)?.lowercased()
                    if let identity, let ext = externals[identity], let path = ext.localPath {
                        localUses.append(.init(fromTarget: id(tname), packagePath: path, product: product))
                    } else {
                        graph.connect(id(tname), externalNode(identity ?? product.lowercased()), .package)
                    }
                }
            }
        }
        return Result(graph: graph, productTargets: productTargets, localUses: localUses, name: name)
    }

    /// "from 5.0.0", "1.2.3", "main"…
    private static func requirement(_ any: Any?) -> String {
        guard let r = any as? [String: Any] else { return "" }
        if let range = r["range"] as? [[String: Any]], let lower = range.first?["lowerBound"] as? String { return "from " + lower }
        if let exact = r["exact"] as? [String], let v = exact.first { return v }
        if let branch = r["branch"] as? [String], let b = branch.first { return b }
        if let rev = r["revision"] as? [String], let v = rev.first { return String(v.prefix(7)) }
        return ""
    }
}
