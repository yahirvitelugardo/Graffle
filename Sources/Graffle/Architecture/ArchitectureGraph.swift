import Foundation

/// What to include when turning a project into a diagram.
struct ArchitectureOptions: Equatable {
    var includeSystemFrameworks = false
    var includeTests = true
    var includeExternalPackages = true
}

enum NodeKind: String, CaseIterable, Codable {
    case app, appExtension, framework, library, tool, tests, externalPackage, system, other

    var title: String {
        switch self {
        case .app: return "App"
        case .appExtension: return "Extension"
        case .framework: return "Framework"
        case .library: return "Library"
        case .tool: return "Tool"
        case .tests: return "Tests"
        case .externalPackage: return "External package"
        case .system: return "System framework"
        case .other: return "Other"
        }
    }
}

enum EdgeKind: String, Codable {
    /// A target depends on, or links, another.
    case dependsOn
    /// An app or framework embeds another product (frameworks, extensions).
    case embeds
    /// A target uses a product of a Swift package.
    case package

    /// When the same two nodes are related in several ways, the most specific one is drawn.
    var rank: Int {
        switch self {
        case .dependsOn: return 0
        case .package: return 1
        case .embeds: return 2
        }
    }
}

struct ArchitectureNode: Equatable, Codable {
    var id: String
    var name: String
    var kind: NodeKind
    /// A short line under the name: "iOS · Swift · 42 files".
    var detail: String
    /// The project or package the node comes from.
    var container: String
}

struct ArchitectureEdge: Hashable, Codable {
    var from: String
    var to: String
    var kind: EdgeKind
}

/// Targets and the dependencies between them, independent of how they will be drawn.
struct ArchitectureGraph {
    var title = ""
    var source = ""
    private(set) var nodes: [ArchitectureNode] = []
    private(set) var edges: [ArchitectureEdge] = []
    private var index: [String: Int] = [:]
    private var edgeIndex: [String: Int] = [:]

    func node(_ id: String) -> ArchitectureNode? { index[id].map { nodes[$0] } }

    /// Adds a node, or keeps the existing one with the same id.
    mutating func add(_ node: ArchitectureNode) {
        guard index[node.id] == nil else { return }
        index[node.id] = nodes.count
        nodes.append(node)
    }

    /// Adds an edge between two existing nodes; a pair is only ever related once, by its most specific kind.
    mutating func connect(_ from: String, _ to: String, _ kind: EdgeKind) {
        guard from != to, index[from] != nil, index[to] != nil else { return }
        let key = from + "\u{0}" + to
        if let i = edgeIndex[key] {
            if kind.rank > edges[i].kind.rank { edges[i].kind = kind }
            return
        }
        edgeIndex[key] = edges.count
        edges.append(ArchitectureEdge(from: from, to: to, kind: kind))
    }

    mutating func merge(_ other: ArchitectureGraph) {
        for n in other.nodes { add(n) }
        for e in other.edges { connect(e.from, e.to, e.kind) }
    }

    /// The graph without what the options leave out (and the edges that touched it).
    func filtered(_ options: ArchitectureOptions) -> ArchitectureGraph {
        var out = ArchitectureGraph(title: title, source: source)
        let dropped: Set<NodeKind> = {
            var s = Set<NodeKind>()
            if !options.includeSystemFrameworks { s.insert(.system) }
            if !options.includeTests { s.insert(.tests) }
            if !options.includeExternalPackages { s.insert(.externalPackage) }
            return s
        }()
        for n in nodes where !dropped.contains(n.kind) { out.add(n) }
        for e in edges { out.connect(e.from, e.to, e.kind) }
        return out
    }

    /// Nodes that depend on nothing and that nothing depends on.
    var isolated: [ArchitectureNode] {
        let touched = Set(edges.flatMap { [$0.from, $0.to] })
        return nodes.filter { !touched.contains($0.id) }
    }
}

/// Counts source files by language.
struct SourceCounts {
    var total = 0, swift = 0, objc = 0, cpp = 0, c = 0

    mutating func add(extension ext: String) {
        switch ext.lowercased() {
        case "swift": swift += 1; total += 1
        case "m": objc += 1; total += 1
        case "mm", "cpp", "cc", "cxx": cpp += 1; total += 1
        case "c": c += 1; total += 1
        default: break
        }
    }

    /// Counts the sources under `folder`, however deep.
    mutating func add(folder: URL) {
        guard let walker = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) else { return }
        for case let file as URL in walker { add(extension: file.pathExtension) }
    }

    /// "Swift/Obj-C · 12 files", or "" when there are none.
    var summary: String {
        guard total > 0 else { return "" }
        var languages: [String] = []
        if swift > 0 { languages.append("Swift") }
        if objc > 0 { languages.append("Obj-C") }
        if cpp > 0 { languages.append("C++") }
        if c > 0 { languages.append("C") }
        return languages.joined(separator: "/") + " · \(total) file" + (total == 1 ? "" : "s")
    }
}
