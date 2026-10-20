import Foundation

struct GeneratedFile: Equatable {
    /// Relative to the target folder, with "/" separators.
    var path: String
    var content: String
}

/// Everything a generator produced, ready to be written into a folder.
struct GeneratedProject: Equatable {
    var files: [GeneratedFile] = []
    /// A one-line description for the summary ("12 files: a Swift package with 5 targets").
    var summary = ""
    /// Things the generator could not decide (external packages to add by hand, unknown types…), for the README and the summary.
    var notes: [String] = []

    mutating func add(_ path: String, _ content: String) { files.append(GeneratedFile(path: path, content: content.hasSuffix("\n") ? content : content + "\n")) }
}

enum CodeGenError: LocalizedError, Equatable {
    case notEmpty([String])
    case notAFolder
    case unsafePath(String)
    case writeFailed(String)
    case nothingToGenerate(String)

    var errorDescription: String? {
        switch self {
        case .notEmpty(let names):
            let shown = names.prefix(4).joined(separator: ", ") + (names.count > 4 ? ", …" : "")
            return "This folder isn't empty (it contains \(shown)). Code is only generated into an empty folder, so nothing is overwritten. Choose an empty folder, or make a new one."
        case .notAFolder: return "That isn't a folder."
        case .unsafePath(let p): return "The generator produced an unsafe file path (\(p)); nothing was written."
        case .writeFailed(let why): return "The files couldn't be written: \(why)"
        case .nothingToGenerate(let why): return why
        }
    }
}

/// Writes a generated project into a folder, but only an empty one, and either all of it or none of it.
enum FolderWriter {
    /// Files that macOS puts in folders by itself; they don't make a folder "not empty".
    static let ignored: Set<String> = [".DS_Store", ".localized"]

    /// The names inside `folder` that stop it from counting as empty (nil when it doesn't exist yet).
    static func blockers(in folder: URL) throws -> [String]? {
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: folder.path, isDirectory: &isDir) else { return nil }
        guard isDir.boolValue else { throw CodeGenError.notAFolder }
        let names = (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
        return names.filter { !ignored.contains($0) }.sorted()
    }

    /// Checks the folder without writing anything.
    static func check(_ folder: URL) throws {
        if let names = try blockers(in: folder), !names.isEmpty { throw CodeGenError.notEmpty(names) }
    }

    @discardableResult
    static func write(_ project: GeneratedProject, to folder: URL) throws -> [URL] {
        try check(folder)
        for f in project.files {
            let parts = f.path.split(separator: "/").map(String.init)
            if f.path.hasPrefix("/") || parts.isEmpty || parts.contains("..") || parts.contains(".") || f.path.contains("\0") { throw CodeGenError.unsafePath(f.path) }
        }
        let fm = FileManager.default
        var createdFolder = false
        var written: [URL] = []
        var dirs: [URL] = []
        do {
            if !fm.fileExists(atPath: folder.path) { try fm.createDirectory(at: folder, withIntermediateDirectories: true); createdFolder = true }
            for f in project.files {
                let url = f.path.split(separator: "/").reduce(folder) { $0.appendingPathComponent(String($1)) }
                let dir = url.deletingLastPathComponent()
                var d = dir
                while d.path.count > folder.path.count, !fm.fileExists(atPath: d.path) { dirs.append(d); d = d.deletingLastPathComponent() }
                try fm.createDirectory(at: dir, withIntermediateDirectories: true)
                try f.content.write(to: url, atomically: true, encoding: .utf8)
                written.append(url)
            }
            return written
        } catch {
            for u in written { try? fm.removeItem(at: u) }
            for d in dirs.sorted(by: { $0.path.count > $1.path.count }) { try? fm.removeItem(at: d) }
            if createdFolder { try? fm.removeItem(at: folder) }
            throw CodeGenError.writeFailed(error.localizedDescription)
        }
    }
}

/// Turns names from a diagram into identifiers a compiler accepts.
enum Ident {
    static let swiftKeywords: Set<String> = ["class", "struct", "enum", "protocol", "extension", "func", "var", "let", "import", "init", "default", "case", "in", "is", "as", "self", "Type", "Any", "Self", "operator", "internal", "public", "private", "static", "return", "true", "false", "nil", "subscript", "where", "do", "repeat", "switch", "if", "else", "for", "while", "break", "continue"]
    static let javaKeywords: Set<String> = ["class", "interface", "enum", "package", "import", "public", "private", "protected", "static", "final", "abstract", "new", "return", "int", "long", "double", "float", "boolean", "char", "byte", "short", "void", "default", "switch", "case", "this", "super", "extends", "implements", "null", "true", "false", "if", "else", "for", "while", "do", "try", "catch", "throw", "throws", "native", "transient", "volatile", "synchronized", "assert", "break", "continue", "goto", "const", "instanceof", "strictfp", "var", "record"]
    static let csharpKeywords: Set<String> = ["class", "struct", "interface", "enum", "namespace", "using", "public", "private", "protected", "internal", "static", "readonly", "abstract", "sealed", "new", "return", "int", "long", "double", "float", "bool", "char", "byte", "short", "void", "default", "switch", "case", "this", "base", "object", "string", "null", "true", "false", "if", "else", "for", "foreach", "while", "do", "try", "catch", "throw", "params", "ref", "out", "in", "is", "as", "event", "delegate", "operator", "lock", "checked", "const", "decimal", "virtual", "override", "extern", "fixed", "implicit", "explicit", "sizeof", "typeof", "unsafe", "volatile", "goto", "break", "continue", "finally"]
    static let kotlinKeywords: Set<String> = ["class", "interface", "object", "package", "import", "fun", "val", "var", "when", "in", "is", "as", "typealias", "this", "super", "null", "true", "false", "if", "else", "for", "while", "do", "try", "catch", "throw", "return", "break", "continue"]

    /// A valid identifier: letters and digits only, not starting with a digit, optionally avoiding `reserved` words.
    static func name(_ raw: String, reserved: Set<String> = [], fallback: String = "Item") -> String {
        var out = ""
        for ch in raw { if ch.isLetter || ch.isNumber || ch == "_" { out.append(ch) } else if !out.isEmpty && out.last != "_" { out.append("_") } }
        out = out.trimmingCharacters(in: CharacterSet(charactersIn: "_"))
        if out.isEmpty { out = fallback }
        if out.first!.isNumber { out = "_" + out }
        if reserved.contains(out) { out += "_" }
        return out
    }

    /// PascalCase from "order_item", "order item" or "OrderItem".
    static func pascal(_ raw: String, reserved: Set<String> = []) -> String {
        let words = raw.split { !($0.isLetter || $0.isNumber) }.map(String.init)
        if words.count == 1, let w = words.first, w.contains(where: \.isUppercase) { return name(w.prefix(1).uppercased() + w.dropFirst(), reserved: reserved) }
        let joined = words.map { $0.prefix(1).uppercased() + $0.dropFirst().lowercased() }.joined()
        return name(joined, reserved: reserved)
    }

    static func camel(_ raw: String, reserved: Set<String> = []) -> String {
        let p = pascal(raw)
        return name(p.prefix(1).lowercased() + p.dropFirst(), reserved: reserved)
    }

    /// A lowercase package name such as "myproject".
    static func package(_ raw: String) -> String {
        let s = name(raw, fallback: "app").lowercased().replacingOccurrences(of: "_", with: "")
        return s.isEmpty || s.first!.isNumber ? "app" + s : s
    }

    /// Makes names unique by suffixing numbers.
    static func unique(_ names: [String]) -> [String] {
        var seen: [String: Int] = [:]
        return names.map { n in
            let k = n.lowercased()
            seen[k, default: 0] += 1
            return seen[k]! == 1 ? n : "\(n)\(seen[k]!)"
        }
    }
}
