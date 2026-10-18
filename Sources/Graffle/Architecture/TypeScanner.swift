import Foundation

/// Finds the types (classes, structs, enums, protocols, interfaces…) declared in a source file, with their supertypes,
/// properties and methods. It reads text, not syntax trees, so it is approximate: good for a map of the code, not a compiler.
/// Supports Swift, C#, Kotlin and Java.
enum TypeScanner {
    struct Extension {
        var name: String
        var supertypes: [String]
        var properties: [String]
        var methods: [String]
    }

    struct Result {
        var types: [TypeInfo] = []
        var extensions: [Extension] = []
    }

    // MARK: Cleaning

    /// Removes comments and the inside of string and character literals, keeping line breaks.
    static func strip(_ text: String, language: SourceLanguage) -> String {
        let chars = Array(text.unicodeScalars)
        let n = chars.count
        var out = String.UnicodeScalarView()
        var i = 0
        func at(_ k: Int) -> Unicode.Scalar? { k < n ? chars[k] : nil }
        while i < n {
            let c = chars[i]
            if c == "/", at(i + 1) == "/" {
                while i < n, chars[i] != "\n" { i += 1 }
                continue
            }
            if c == "/", at(i + 1) == "*" {
                i += 2
                while i < n, !(chars[i] == "*" && at(i + 1) == "/") { if chars[i] == "\n" { out.append("\n") }; i += 1 }
                i += 2
                continue
            }
            if c == "\"" {
                if at(i + 1) == "\"", at(i + 2) == "\"" {                       // """ block """
                    i += 3
                    while i < n, !(chars[i] == "\"" && at(i + 1) == "\"" && at(i + 2) == "\"") { if chars[i] == "\n" { out.append("\n") }; i += 1 }
                    i += 3
                    out.append("\""); out.append("\"")
                    continue
                }
                i += 1
                while i < n, chars[i] != "\"", chars[i] != "\n" { if chars[i] == "\\" { i += 1 }; i += 1 }
                i += 1
                out.append("\""); out.append("\"")
                continue
            }
            if c == "'", language != .swift {
                var j = i + 1, len = 0
                while j < n, chars[j] != "'", chars[j] != "\n", len < 4 { if chars[j] == "\\" { j += 1 }; j += 1; len += 1 }
                if j < n, chars[j] == "'" { i = j + 1; out.append("'"); out.append("'"); continue }
            }
            out.append(c)
            i += 1
        }
        return String(out)
    }

    /// The text between the braces that open at `open`, with everything nested one level deeper cut out (leaving `{}`).
    private static func flattenedBody(after open: Int, in ns: NSString) -> (body: String, end: Int)? {
        var depth = 1
        var i = open + 1
        var out: [unichar] = []
        let n = ns.length
        while i < n {
            let c = ns.character(at: i)
            if c == 123 {                                  // {
                depth += 1
                if depth == 2 { out.append(c) }
            } else if c == 125 {                           // }
                depth -= 1
                if depth == 0 { break }
                if depth == 1 { out.append(c) }
            } else if depth == 1 {
                out.append(c)
            }
            i += 1
        }
        guard depth == 0 else { return nil }
        return (String(utf16CodeUnits: out, count: out.count), i)
    }

    // MARK: Declarations

    private static func regex(_ pattern: String) -> NSRegularExpression {
        // swiftlint:disable:next force_try
        try! NSRegularExpression(pattern: pattern, options: [.anchorsMatchLines])
    }

    private static let swiftDecl = regex(#"^[ \t]*(?:@[\w.]+(?:\([^)\n]*\))?[ \t]+)*(?:(?:public|open|internal|fileprivate|private|package|final|indirect|nonisolated)[ \t]+)*(class|struct|enum|protocol|actor|extension)[ \t]+([A-Za-z_][\w.]*)(?:<[^\n{]*?>)?[ \t]*(?::[ \t]*([^{;]*?))?[ \t]*(?:where[^{;]*)?\s*\{"#)
    private static let csharpDecl = regex(#"^[ \t]*(?:\[[^\]\n]*\][ \t]*)*(?:(?:public|internal|private|protected|static|abstract|sealed|partial|readonly|unsafe|new|file)[ \t]+)*(class|struct|interface|enum|record(?:[ \t]+(?:class|struct))?)[ \t]+([A-Za-z_]\w*)(?:<[^\n{(]*?>)?(?:\([^)]*\))?\s*(?::\s*([^{;]*?))?\s*(?:where[^{;]*)?\s*\{"#)
    private static let kotlinDecl = regex(#"^[ \t]*(?:@[\w.]+(?:\([^)\n]*\))?[ \t]+)*(?:(?:public|private|internal|protected|open|abstract|sealed|data|enum|inner|annotation|value|expect|actual)[ \t]+)*(class|interface|object)[ \t]+([A-Za-z_]\w*)(?:<[^\n{(:]*?>)?(?:[ \t]*(?:private|internal|public)?[ \t]*(?:constructor)?[ \t]*\(([^)]*)\))?[ \t]*(?::[ \t]*([^{\n=]*?))?[ \t]*(?:where[^{\n]*)?[ \t]*(?:(\{)|$)"#)
    private static let javaDecl = regex(#"^[ \t]*(?:@[\w.]+(?:\([^)\n]*\))?[ \t]*)*(?:(?:public|private|protected|static|final|abstract|sealed|non-sealed|strictfp)[ \t]+)*(class|interface|enum|record|@interface)[ \t]+([A-Za-z_]\w*)(?:<[^{]*?>)?(?:\s*\([^)]*\))?(?:\s+extends\s+([^{]*?))?(?:\s+implements\s+([^{]*?))?(?:\s+permits[^{]*)?\s*\{"#)

    private static func decl(for language: SourceLanguage) -> NSRegularExpression {
        switch language {
        case .swift: return swiftDecl
        case .csharp: return csharpDecl
        case .kotlin: return kotlinDecl
        case .java: return javaDecl
        }
    }

    // MARK: Scanning

    static func scan(_ raw: String, language: SourceLanguage, file: String, includePrivate: Bool) -> Result {
        let stripped = strip(raw, language: language)
        let ns = stripped as NSString
        var result = Result()
        let matches = decl(for: language).matches(in: stripped, range: NSRange(location: 0, length: ns.length))
        for m in matches {
            func group(_ i: Int) -> String? {
                guard i < m.numberOfRanges, m.range(at: i).location != NSNotFound else { return nil }
                return ns.substring(with: m.range(at: i))
            }
            guard let keyword = group(1), let rawName = group(2) else { continue }
            let name = rawName.split(separator: ".").last.map(String.init) ?? rawName
            let declText = ns.substring(with: m.range)
            var supers = splitTypes(group(3) ?? "")
            if language == .java { supers += splitTypes(group(4) ?? "") }
            var bodyText = ""
            var kotlinParams = ""
            if language == .kotlin {
                kotlinParams = group(3) ?? ""
                supers = splitTypes(group(4) ?? "")
                // A Kotlin type may have no body at all.
                if group(5) != nil {
                    let open = m.range.location + (declText as NSString).range(of: "{", options: .backwards).location
                    if let b = flattenedBody(after: open, in: ns) { bodyText = b.body }
                } else if let next = nextNonSpace(after: m.range.location + m.range.length, in: ns), ns.character(at: next) == 123,
                          let b = flattenedBody(after: next, in: ns) { bodyText = b.body }
            } else {
                let open = m.range.location + m.range.length - 1
                guard open < ns.length, ns.character(at: open) == 123, let b = flattenedBody(after: open, in: ns) else { continue }
                bodyText = b.body
            }

            var kind = typeKind(keyword)
            if kind == .classType, declText.range(of: #"\benum\b"#, options: .regularExpression) != nil { kind = .enumType }   // Kotlin: `enum class`
            let abstract = declText.range(of: #"\babstract\b"#, options: .regularExpression) != nil
            let members = parseMembers(bodyText, typeName: name, kind: kind, language: language, includePrivate: includePrivate)
            var props = members.properties
            if language == .kotlin { props = kotlinConstructorProperties(kotlinParams, includePrivate: includePrivate) + props }
            if keyword == "extension" {
                result.extensions.append(Extension(name: name, supertypes: supers, properties: props, methods: members.methods))
            } else {
                result.types.append(TypeInfo(name: name, kind: kind, language: language, supertypes: supers, properties: props,
                                             methods: members.methods, file: file, isTest: false, isAbstract: abstract))
            }
        }
        return result
    }

    private static func nextNonSpace(after index: Int, in ns: NSString) -> Int? {
        var i = index
        while i < ns.length {
            let c = ns.character(at: i)
            if c != 32 && c != 9 && c != 10 && c != 13 { return i }
            i += 1
        }
        return nil
    }

    private static func typeKind(_ keyword: String) -> TypeKind {
        switch keyword {
        case "class", "extension": return .classType
        case "struct": return .structType
        case "enum": return .enumType
        case "protocol": return .protocolType
        case "interface", "@interface": return .interfaceType
        case "actor": return .actorType
        case "object": return .objectType
        default: return keyword.hasPrefix("record") ? .recordType : .classType
        }
    }

    /// "Base<T>, Proto & Other, Foo(args)" -> ["Base", "Proto", "Other", "Foo"]
    static func splitTypes(_ text: String) -> [String] {
        var parts: [String] = [], current = "", depth = 0
        for ch in text {
            if ch == "<" || ch == "(" || ch == "[" { depth += 1; continue }        // generics and arguments are dropped
            if ch == ">" || ch == ")" || ch == "]" { depth = max(0, depth - 1); continue }
            guard depth == 0 else { continue }
            if ch == "," || ch == "&" { parts.append(current); current = "" } else { current.append(ch) }
        }
        parts.append(current)
        return parts.compactMap { raw -> String? in
            var s = raw
            for word in ["where", "class", "struct", "new"] { if let r = s.range(of: " \(word)") { s = String(s[..<r.lowerBound]) } }
            s = s.trimmingCharacters(in: .whitespacesAndNewlines)
            if s.hasPrefix("any ") || s.hasPrefix("some ") { s = String(s.dropFirst(4)) }
            s = s.split(separator: ".").last.map(String.init) ?? s
            s = s.trimmingCharacters(in: CharacterSet(charactersIn: "?! "))
            return s.isEmpty || s.contains(" ") ? nil : s
        }
    }

    // MARK: Members

    private static let modifierWords: Set<String> = [
        "public", "private", "protected", "internal", "fileprivate", "open", "package", "static", "final", "abstract", "override", "virtual",
        "sealed", "readonly", "const", "async", "extern", "unsafe", "partial", "new", "lateinit", "lazy", "weak", "unowned", "mutating",
        "nonmutating", "required", "convenience", "dynamic", "nonisolated", "indirect", "class", "default", "synchronized", "native",
        "transient", "volatile", "inline", "suspend", "operator", "infix", "tailrec", "external", "data", "expect", "actual", "event",
        "optional", "protected", "volatile", "strictfp", "noinline", "crossinline", "reified", "vararg",
    ]
    private static let keywordStarts: Set<String> = [
        "return", "new", "throw", "using", "if", "while", "for", "foreach", "switch", "else", "lock", "namespace", "import", "package", "typealias",
        "var", "val", "let", "func", "fun", "init", "case", "subscript", "deinit", "get", "set", "when", "try", "do", "catch", "break", "continue",
    ]

    private static let attribute = regex(#"^\s*(?:@[\w.]+(?:\([^)]*\))?\s*|\[[^\]]*\]\s*)+"#)

    /// The body's statements: one per line or `;`, with line breaks inside parentheses folded away.
    private static func statements(_ body: String) -> [String] {
        var folded = "", depth = 0
        for ch in body {
            if ch == "(" { depth += 1 }
            if ch == ")" { depth = max(0, depth - 1) }
            if ch == "\n" && depth > 0 { folded.append(" ") } else if ch == ";" { folded.append("\n") } else { folded.append(ch) }
        }
        return folded.replacingOccurrences(of: "{}", with: "{}\n").split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }

    private static func first(_ re: NSRegularExpression, in s: String) -> [String]? {
        let ns = s as NSString
        guard let m = re.firstMatch(in: s, range: NSRange(location: 0, length: ns.length)) else { return nil }
        return (0..<m.numberOfRanges).map { m.range(at: $0).location == NSNotFound ? "" : ns.substring(with: m.range(at: $0)) }
    }

    private static let swiftProp = regex(#"^(?:var|let)\s+([A-Za-z_]\w*)\s*(?::\s*([^={]+?))?\s*(?:=[^{]*)?(?:\{\})?\s*$"#)
    private static let swiftFunc = regex(#"^func\s+([^\s(<]+)\s*(?:<[^>]*>)?\s*\(([^)]*)\)\s*(?:async\s+)?(?:throws\s+|rethrows\s+)?(?:->\s*([^{]+?))?\s*(?:where[^{]*)?(?:\{\})?\s*$"#)
    private static let swiftInit = regex(#"^init[?!]?\s*\(([^)]*)\)"#)
    private static let swiftCase = regex(#"^case\s+(.+)$"#)
    private static let kotlinProp = regex(#"^(?:val|var)\s+(?:<[^>]*>\s*)?(?:[\w.<>?]+\.)?([A-Za-z_]\w*)\s*(?::\s*([^={]+?))?\s*(?:=.*|by\s.*)?(?:\{\})?\s*$"#)
    private static let kotlinFunc = regex(#"^fun\s+(?:<[^>]*>\s*)?(?:[\w.<>?]+\.)?([A-Za-z_]\w*)\s*\(([^)]*)\)\s*(?::\s*([^={]+?))?\s*(?:=.*)?(?:\{\})?\s*$"#)
    private static let cMethod = regex(#"^(?:<[^>]*>\s*)?([\w<>\[\],.?]+(?:\s*\?)?)\s+([A-Za-z_]\w*)\s*(?:<[^>]*>)?\s*\(([^)]*)\)"#)
    private static let cProperty = regex(#"^([\w<>\[\],.?]+)\s+([A-Za-z_]\w*)\s*(?:\{\}|=>)"#)
    private static let cField = regex(#"^([\w<>\[\],.?]+)\s+([A-Za-z_]\w*)\s*(?:=.*)?$"#)

    private static func visibility(_ mods: [String], language: SourceLanguage, inInterface: Bool) -> (symbol: String, hidden: Bool) {
        if inInterface { return ("+", false) }
        if mods.contains("private") || mods.contains("fileprivate") { return ("-", true) }
        if mods.contains("protected") { return ("#", false) }
        if mods.contains("public") || mods.contains("open") { return ("+", false) }
        switch language {
        case .csharp: return ("-", true)               // members are private unless said otherwise
        case .java: return ("~", false)                // package-private
        case .swift: return ("~", false)               // internal
        case .kotlin: return (mods.contains("internal") ? "~" : "+", false)
        }
    }

    /// The parameter names (Swift: labels) of "(a: Int, _ b: Int)" -> "a:b:" or, for the other languages, "a, b".
    private static func paramList(_ params: String, language: SourceLanguage) -> String {
        let parts = splitTop(params)
        let names = parts.compactMap { p -> String? in
            let s = p.trimmingCharacters(in: .whitespaces)
            if s.isEmpty { return nil }
            switch language {
            case .swift:
                let head = s.split(separator: ":", maxSplits: 1).first.map(String.init) ?? s
                let words = head.split(separator: " ").map(String.init)
                let label = words.first ?? ""                          // "_" stays "_": no label at the call site
                return label + ":"
            case .kotlin:
                var head = s.split(separator: ":", maxSplits: 1).first.map(String.init) ?? s
                for w in ["vararg ", "noinline ", "crossinline ", "val ", "var "] { head = head.replacingOccurrences(of: w, with: "") }
                return head.trimmingCharacters(in: .whitespaces)
            default:
                var noDefault = s
                if let eq = noDefault.firstIndex(of: "=") { noDefault = String(noDefault[..<eq]) }
                return noDefault.split(separator: " ").last.map(String.init)
            }
        }
        return language == .swift ? names.joined() : names.joined(separator: ", ")
    }

    private static func splitTop(_ s: String) -> [String] {
        var parts: [String] = [], current = "", depth = 0
        for ch in s {
            if "<([{".contains(ch) { depth += 1 }
            if ">)]}".contains(ch) { depth = max(0, depth - 1) }
            if ch == "," && depth == 0 { parts.append(current); current = "" } else { current.append(ch) }
        }
        parts.append(current)
        return parts
    }

    private static func clip(_ s: String, _ n: Int = 28) -> String {
        let t = s.trimmingCharacters(in: .whitespaces)
        return t.count > n ? String(t.prefix(n - 1)) + "…" : t
    }

    private static func parseMembers(_ body: String, typeName: String, kind: TypeKind, language: SourceLanguage, includePrivate: Bool)
        -> (properties: [String], methods: [String]) {
        var props: [String] = [], methods: [String] = []
        var enumDone = false
        for var line in statements(body) {
            // Leading attributes and modifiers.
            if let m = attribute.firstMatch(in: line, range: NSRange(location: 0, length: (line as NSString).length)) {
                line = (line as NSString).substring(from: m.range.length).trimmingCharacters(in: .whitespaces)
            }
            var mods: [String] = []
            while let word = line.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true).first.map(String.init),
                  modifierWords.contains(word), line.count > word.count {
                mods.append(word)
                line = String(line.dropFirst(word.count)).trimmingCharacters(in: .whitespaces)
            }
            guard !line.isEmpty else { continue }
            // Enum cases.
            if kind == .enumType {
                if language == .swift, let c = first(swiftCase, in: line) {
                    for item in splitTop(c[1]) {
                        let name = item.split(separator: "(").first.map { $0.split(separator: "=").first.map(String.init) ?? String($0) } ?? item
                        props.append("case " + clip(name.trimmingCharacters(in: .whitespaces)))
                    }
                    continue
                }
                if language != .swift, !enumDone, line.range(of: #"^[A-Z][A-Za-z0-9_]*(\(.*\))?(\s*=\s*\w+)?(\s*,\s*[A-Z][A-Za-z0-9_]*(\(.*\))?(\s*=\s*\w+)?)*,?$"#, options: .regularExpression) != nil {
                    for item in splitTop(line) {
                        let name = item.split(separator: "(").first.map(String.init)?.split(separator: "=").first.map(String.init) ?? item
                        let t = name.trimmingCharacters(in: .whitespaces)
                        if !t.isEmpty { props.append("case " + clip(t)) }
                    }
                    enumDone = true
                    continue
                }
            }

            let vis = visibility(mods, language: language, inInterface: kind.isInterface)
            if vis.hidden && !includePrivate { continue }
            let v = vis.symbol

            switch language {
            case .swift:
                if let m = first(swiftProp, in: line) {
                    props.append("\(v) \(m[1])" + (m[2].isEmpty ? "" : ": " + clip(m[2])))
                } else if let m = first(swiftFunc, in: line) {
                    methods.append("\(v) \(m[1])(\(paramList(m[2], language: .swift)))" + (m[3].isEmpty ? "" : " → " + clip(m[3])))
                } else if let m = first(swiftInit, in: line) {
                    methods.append("\(v) init(\(paramList(m[1], language: .swift)))")
                }
            case .kotlin:
                if let m = first(kotlinProp, in: line) {
                    props.append("\(v) \(m[1])" + (m[2].isEmpty ? "" : ": " + clip(m[2])))
                } else if let m = first(kotlinFunc, in: line) {
                    methods.append("\(v) \(m[1])(\(paramList(m[2], language: .kotlin)))" + (m[3].isEmpty ? "" : ": " + clip(m[3])))
                }
            case .csharp, .java:
                guard let word = line.split(separator: " ").first.map(String.init), !keywordStarts.contains(word) else { continue }
                if line.hasPrefix(typeName + "("), let m = first(regex(#"^\w+\s*\(([^)]*)\)"#), in: line) {
                    methods.append("\(v) \(typeName)(\(paramList(m[1], language: language)))")
                } else if let m = first(cMethod, in: line), !keywordStarts.contains(m[1]) {
                    methods.append("\(v) \(m[2])(\(paramList(m[3], language: language)))" + (m[1] == "void" ? "" : " → " + clip(m[1])))
                } else if language == .csharp, let m = first(cProperty, in: line), !line.contains("(") {
                    props.append("\(v) \(m[2]): \(clip(m[1]))")
                } else if !line.contains("("), let m = first(cField, in: line) {
                    props.append("\(v) \(m[2]): \(clip(m[1]))")
                }
            }
        }
        return (props, methods)
    }

    /// `class User(val name: String, var age: Int)` -> properties.
    private static func kotlinConstructorProperties(_ params: String, includePrivate: Bool) -> [String] {
        splitTop(params).compactMap { raw in
            var p = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            var isPrivate = false
            while let w = p.split(separator: " ", maxSplits: 1).first.map(String.init), ["private", "public", "protected", "internal", "override", "open"].contains(w) {
                if w == "private" { isPrivate = true }
                p = String(p.dropFirst(w.count)).trimmingCharacters(in: .whitespaces)
            }
            guard p.hasPrefix("val ") || p.hasPrefix("var ") else { return nil }
            if isPrivate && !includePrivate { return nil }
            let rest = String(p.dropFirst(4))
            let name = rest.split(separator: ":", maxSplits: 1).first.map { $0.trimmingCharacters(in: .whitespaces) } ?? rest
            let type = rest.split(separator: ":", maxSplits: 1).dropFirst().first.map { $0.split(separator: "=").first.map(String.init) ?? "" } ?? ""
            return "\(isPrivate ? "-" : "+") \(name)" + (type.isEmpty ? "" : ": " + clip(type))
        }
    }
}
