import Foundation

/// A type as written in a diagram, parsed so it can be written again in another language.
indirect enum CodeType: Equatable {
    case int, long, double, float, bool, string, void, date, uuid, any
    case array(CodeType)
    case optional(CodeType)
    case dict(CodeType, CodeType)
    case named(String)

    static func parse(_ raw: String) -> CodeType {
        var s = raw.trimmingCharacters(in: .whitespaces)
        if s.isEmpty { return .any }
        if s.hasSuffix("?") || s.hasSuffix("!") { return .optional(parse(String(s.dropLast()))) }
        if s.hasPrefix("[") && s.hasSuffix("]") {
            let inner = String(s.dropFirst().dropLast())
            if let colon = topLevel(inner, ":") { return .dict(parse(String(inner[..<colon])), parse(String(inner[inner.index(after: colon)...]))) }
            return .array(parse(inner))
        }
        if s.hasSuffix("[]") { return .array(parse(String(s.dropLast(2)))) }
        if let open = s.firstIndex(of: "<"), s.hasSuffix(">") {
            let name = String(s[..<open])
            let args = splitTop(String(s[s.index(after: open)..<s.index(before: s.endIndex)]))
            switch name {
            case "List", "ArrayList", "Array", "Set", "HashSet", "IEnumerable", "ICollection", "Collection", "IList", "MutableList", "Iterable": return args.first.map { .array(parse($0)) } ?? .array(.any)
            case "Map", "Dictionary", "HashMap", "MutableMap", "IDictionary": return args.count == 2 ? .dict(parse(args[0]), parse(args[1])) : .dict(.string, .any)
            case "Optional", "Nullable": return args.first.map { .optional(parse($0)) } ?? .any
            default: s = name
            }
        }
        if let last = s.split(separator: ".").last { s = String(last) }
        switch s {
        case "Int", "Int32", "UInt", "UInt32", "int", "Integer", "Short", "short", "Int16", "UInt16", "Byte", "byte", "Int8", "UInt8", "uint", "ushort", "sbyte": return .int
        case "Int64", "UInt64", "Long", "long", "ulong": return .long
        case "Double", "double", "Decimal", "decimal", "CGFloat", "BigDecimal": return .double
        case "Float", "float", "Single": return .float
        case "Bool", "bool", "boolean", "Boolean": return .bool
        case "String", "string", "NSString", "CharSequence", "Character", "char", "Char": return .string
        case "Void", "void", "Unit", "()": return .void
        case "Date", "DateTime", "Instant", "LocalDate", "LocalDateTime", "DateTimeOffset", "Timestamp", "TimeInterval": return .date
        case "UUID", "Guid": return .uuid
        case "Any", "AnyObject", "Object", "object", "Any?": return .any
        default: return .named(Ident.name(s, fallback: "Item"))
        }
    }

    private static func topLevel(_ s: String, _ ch: Character) -> String.Index? {
        var depth = 0
        for i in s.indices {
            let c = s[i]
            if "[<(".contains(c) { depth += 1 } else if "]>)".contains(c) { depth -= 1 }
            if c == ch && depth == 0 { return i }
        }
        return nil
    }
    private static func splitTop(_ s: String) -> [String] {
        var parts: [String] = [], cur = "", depth = 0
        for c in s { if "[<(".contains(c) { depth += 1 } else if "]>)".contains(c) { depth -= 1 }
            if c == "," && depth == 0 { parts.append(cur.trimmingCharacters(in: .whitespaces)); cur = "" } else { cur.append(c) } }
        if !cur.isEmpty { parts.append(cur.trimmingCharacters(in: .whitespaces)) }
        return parts
    }

    /// This type written in `lang`. `boxed` is for Java generics, which cannot hold primitives.
    func render(_ lang: SourceLanguage, boxed: Bool = false) -> String {
        switch lang {
        case .swift:
            switch self {
            case .int: return "Int"; case .long: return "Int64"; case .double: return "Double"; case .float: return "Float"; case .bool: return "Bool"
            case .string: return "String"; case .void: return "Void"; case .date: return "Date"; case .uuid: return "UUID"; case .any: return "Any"
            case .array(let t): return "[\(t.render(lang))]"
            case .optional(let t): return t.render(lang) + "?"
            case .dict(let k, let v): return "[\(k.render(lang)): \(v.render(lang))]"
            case .named(let n): return n
            }
        case .csharp:
            switch self {
            case .int: return "int"; case .long: return "long"; case .double: return "double"; case .float: return "float"; case .bool: return "bool"
            case .string: return "string"; case .void: return "void"; case .date: return "DateTime"; case .uuid: return "Guid"; case .any: return "object"
            case .array(let t): return "List<\(t.render(lang))>"
            case .optional(let t): return t.render(lang) + "?"
            case .dict(let k, let v): return "Dictionary<\(k.render(lang)), \(v.render(lang))>"
            case .named(let n): return n
            }
        case .kotlin:
            switch self {
            case .int: return "Int"; case .long: return "Long"; case .double: return "Double"; case .float: return "Float"; case .bool: return "Boolean"
            case .string: return "String"; case .void: return "Unit"; case .date: return "java.util.Date"; case .uuid: return "java.util.UUID"; case .any: return "Any"
            case .array(let t): return "List<\(t.render(lang))>"
            case .optional(let t): return t.render(lang) + "?"
            case .dict(let k, let v): return "Map<\(k.render(lang)), \(v.render(lang))>"
            case .named(let n): return n
            }
        case .java:
            switch self {
            case .int: return boxed ? "Integer" : "int"; case .long: return boxed ? "Long" : "long"; case .double: return boxed ? "Double" : "double"
            case .float: return boxed ? "Float" : "float"; case .bool: return boxed ? "Boolean" : "boolean"
            case .string: return "String"; case .void: return boxed ? "Void" : "void"; case .date: return "java.util.Date"; case .uuid: return "java.util.UUID"; case .any: return "Object"
            case .array(let t): return "java.util.List<\(t.render(lang, boxed: true))>"
            case .optional(let t): return t.render(lang, boxed: true)
            case .dict(let k, let v): return "java.util.Map<\(k.render(lang, boxed: true)), \(v.render(lang, boxed: true))>"
            case .named(let n): return n
            }
        }
    }

    var isVoid: Bool { if case .void = self { return true }; return false }
    var isOptional: Bool { if case .optional = self { return true }; return false }
}

/// A property or method as written in a box of the diagram ("+ name: String", "~ make(_:scale:) → Circle").
struct Member {
    var visibility: Character         // + - # ~
    var name: String
    var type: CodeType?
    var params: [String] = []
    var isEnumCase = false
    var isInit = false

    static func property(_ s: String) -> Member? {
        var t = s.trimmingCharacters(in: .whitespaces)
        if t.hasPrefix("case ") { return Member(visibility: "+", name: String(t.dropFirst(5)).trimmingCharacters(in: .whitespaces), type: nil, isEnumCase: true) }
        var vis: Character = "~"
        if let f = t.first, "+-#~".contains(f) { vis = f; t = String(t.dropFirst()).trimmingCharacters(in: .whitespaces) }
        guard !t.isEmpty, !t.hasPrefix("…") else { return nil }
        if let colon = t.firstIndex(of: ":") {
            return Member(visibility: vis, name: String(t[..<colon]).trimmingCharacters(in: .whitespaces), type: CodeType.parse(String(t[t.index(after: colon)...])))
        }
        return Member(visibility: vis, name: t, type: nil)
    }

    static func method(_ s: String) -> Member? {
        var t = s.trimmingCharacters(in: .whitespaces)
        var vis: Character = "~"
        if let f = t.first, "+-#~".contains(f) { vis = f; t = String(t.dropFirst()).trimmingCharacters(in: .whitespaces) }
        guard !t.hasPrefix("…"), let open = t.firstIndex(of: "("), let close = t.lastIndex(of: ")"), open < close else { return nil }
        let name = String(t[..<open]).trimmingCharacters(in: .whitespaces)
        let inner = String(t[t.index(after: open)..<close])
        var params: [String]
        if inner.contains(":") && !inner.contains(",") && !inner.contains(" ") || inner.hasSuffix(":") {           // Swift labels: "make(_:scale:)"
            params = inner.split(separator: ":").map(String.init)
        } else {
            params = inner.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        }
        var ret: CodeType?
        let rest = t[t.index(after: close)...].trimmingCharacters(in: .whitespaces)
        if rest.hasPrefix("→") { ret = CodeType.parse(String(rest.dropFirst()).trimmingCharacters(in: .whitespaces)) }
        else if rest.hasPrefix(":") { ret = CodeType.parse(String(rest.dropFirst()).trimmingCharacters(in: .whitespaces)) }
        return Member(visibility: vis, name: name, type: ret, params: params, isInit: name == "init")
    }
}

/// Generates the classes, structs, enums and interfaces of a classes diagram as source files.
enum ClassCode {
    static let languages: [SourceLanguage] = [.swift, .csharp, .kotlin, .java]

    static func title(_ l: SourceLanguage) -> String {
        switch l { case .swift: return "Swift"; case .csharp: return "C#"; case .kotlin: return "Kotlin"; case .java: return "Java" }
    }

    private static func reserved(_ l: SourceLanguage) -> Set<String> {
        switch l { case .swift: return Ident.swiftKeywords; case .csharp: return Ident.csharpKeywords; case .kotlin: return Ident.kotlinKeywords; case .java: return Ident.javaKeywords }
    }

    static func generate(_ model: ClassModel, language l: SourceLanguage, project: String) throws -> GeneratedProject {
        guard !model.types.isEmpty else { throw CodeGenError.nothingToGenerate("The diagram has no classes to generate code from.") }
        let projectName = Ident.pascal(project, reserved: [])
        let pkg = Ident.package(project)
        var out = GeneratedProject()
        var notes: [String] = []

        // Names, made valid and unique; supertypes are looked up through them.
        let names = Ident.unique(model.types.map { Ident.name($0.name, reserved: reserved(l)) })
        var rename: [String: String] = [:]
        for (t, n) in zip(model.types, names) { rename[t.name] = n }
        let byName = Dictionary(model.types.map { ($0.name, $0) }, uniquingKeysWith: { a, _ in a })

        func isInterface(_ name: String) -> Bool? { byName[name].map { $0.kind.isInterface } }
        func baseChain(_ t: TypeInfo) -> [TypeInfo] {
            var chain: [TypeInfo] = [], cur = t, seen = Set([t.name])
            while let base = cur.supertypes.compactMap({ byName[$0] }).first(where: { !$0.kind.isInterface && !seen.contains($0.name) }), cur.kind == .classType {
                chain.append(base); seen.insert(base.name); cur = base
            }
            return chain
        }
        func memberNames(_ t: TypeInfo) -> Set<String> { Set(t.methods.compactMap { Member.method($0)?.name }) }
        func inheritedMethods(_ t: TypeInfo) -> Set<String> {
            var names = Set<String>()
            for b in baseChain(t) { names.formUnion(memberNames(b)) }
            for s in t.supertypes { if let i = byName[s], i.kind.isInterface { names.formUnion(memberNames(i)) } }
            return names
        }
        func isOverridden(_ method: String, in t: TypeInfo) -> Bool {
            model.types.contains { other in other.name != t.name && baseChain(other).contains { $0.name == t.name } && memberNames(other).contains(method) }
        }

        for (t, name) in zip(model.types, names) {
            let props = t.properties.compactMap(Member.property)
            let methods = t.methods.compactMap(Member.method)
            func paramType(_ p: String) -> CodeType {
                let clean = Ident.name(p, fallback: "value")
                return props.first { $0.name == p || $0.name == clean }?.type ?? .any
            }
            func paramText(_ raw: String, _ idx: Int) -> (label: String, name: String, type: CodeType) {
                var p = raw.trimmingCharacters(in: .whitespaces), explicit: CodeType?
                if let colon = p.firstIndex(of: ":"), colon != p.startIndex {                      // "item: String"
                    let ty = p[p.index(after: colon)...].trimmingCharacters(in: .whitespaces)
                    if !ty.isEmpty { explicit = CodeType.parse(ty) }
                    p = String(p[..<colon]).trimmingCharacters(in: .whitespaces)
                } else if let sp = p.lastIndex(of: " ") {                                           // "String item"
                    explicit = CodeType.parse(String(p[..<sp]))
                    p = String(p[p.index(after: sp)...])
                }
                let n = p == "_" || p.isEmpty ? "arg\(idx + 1)" : p
                let clean = Ident.name(n, reserved: reserved(l), fallback: "arg\(idx + 1)")
                return (p, clean, explicit ?? paramType(n))
            }
            func vis(_ c: Character, inInterface: Bool = false) -> String {
                if inInterface { return l == .swift || l == .csharp || l == .java ? (l == .swift ? "" : "") : "" }
                // "~" (no modifier in the source) becomes public: a weaker access can't implement or override a public member.
                switch (c, l) {
                case ("+", .kotlin), ("~", .kotlin): return ""
                case ("+", _), ("~", _): return "public "
                case ("-", _): return "private "
                case ("#", .swift): return "internal "
                case ("#", _): return "protected "
                default: return ""
                }
            }

            // Supertypes: a base class and/or interfaces.
            var base: String?
            var interfaces: [String] = []
            for s in t.supertypes {
                let n = rename[s] ?? Ident.name(s, reserved: reserved(l))
                let known = isInterface(s)
                let isStructLike = t.kind != .classType
                if known == true || isStructLike { interfaces.append(n) }
                else if known == false, base == nil { base = n }
                else if known == nil {
                    switch l {
                    case .swift: interfaces.append(n)                                                   // unknown conformances (Hashable, Codable…)
                    case .csharp: if n.count > 1, n.first == "I", n.dropFirst().first!.isUppercase { interfaces.append(n) } else if base == nil { base = n } else { interfaces.append(n) }
                    default: interfaces.append(n); notes.append("\(t.name): “\(s)” isn't in the diagram; it was added as an interface — change it to a base class if it is one.")
                    }
                } else { interfaces.append(n) }
            }
            if l == .java && t.kind.isInterface { base = nil }

            var lines: [String] = []
            var header = ""
            func ind(_ n: Int) -> String { String(repeating: "    ", count: n) }

            // ----- Body members
            var body: [String] = []
            let inInterface = t.kind.isInterface
            let inherited = inheritedMethods(t)

            switch l {
            case .swift:
                if t.kind == .enumType {
                    let cases = props.filter(\.isEnumCase).map { Ident.name($0.name, reserved: reserved(l), fallback: "value") }
                    body += cases.isEmpty ? [] : ["case " + cases.joined(separator: ", ")]
                } else {
                    for p in props where !p.isEnumCase {
                        let ty = p.type ?? .any
                        let n = Ident.name(p.name, reserved: reserved(l), fallback: "value")
                        if inInterface { body.append("var \(n): \(ty.render(l)) { get set }"); continue }
                        let def: String
                        switch ty {
                        case .int, .long: def = " = 0"; case .double, .float: def = " = 0"; case .bool: def = " = false"; case .string: def = " = \"\""
                        case .array: def = " = []"; case .dict: def = " = [:]"; case .optional: def = " = nil"; case .date: def = " = Date()"; case .uuid: def = " = UUID()"; default: def = ""
                        }
                        let typeText = def.isEmpty ? ty.render(l) + "!" : ty.render(l)
                        body.append("\(vis(p.visibility))var \(n): \(typeText)\(def)")
                    }
                    for m in methods {
                        let ps = m.params.enumerated().map { paramText($1, $0) }
                        let sig = ps.map { p -> String in
                            let label = p.label == "_" ? "_ " : (p.label == p.name || p.label.isEmpty ? "" : p.label + " ")
                            return "\(label)\(p.name): \(p.type.render(l))"
                        }.joined(separator: ", ")
                        if m.isInit {
                            if inInterface { continue }
                            body.append("\(vis(m.visibility, inInterface: false).isEmpty ? "" : vis(m.visibility))init(\(sig)) {\(base != nil ? " super.init() " : "")}")
                            continue
                        }
                        let n = Ident.name(m.name, reserved: reserved(l), fallback: "run")
                        let ret = m.type.flatMap { $0.isVoid ? nil : " -> " + $0.render(l) } ?? ""
                        let override = inherited.contains(m.name) && base != nil && baseChain(t).contains { memberNames($0).contains(m.name) } ? "override " : ""
                        if inInterface { body.append("func \(n)(\(sig))\(ret)"); continue }
                        let impl = ret.isEmpty ? "{ /* TODO */ }" : "{ fatalError(\"TODO: implement \(n)\") }"
                        body.append("\(vis(m.visibility))\(override)func \(n)(\(sig))\(ret) \(impl)")
                    }
                }
                let kind: String
                switch t.kind {
                case .classType: kind = "class"; case .structType, .recordType: kind = "struct"; case .enumType: kind = "enum"; case .protocolType, .interfaceType: kind = "protocol"
                case .actorType: kind = "actor"; case .objectType: kind = "class"
                }
                let supers = ([base].compactMap { $0 } + interfaces)
                header = "public \(kind) \(name)" + (supers.isEmpty ? "" : ": " + supers.joined(separator: ", ")) + " {"
                lines = ["import Foundation", "", header] + body.map { ind(1) + $0 } + ["}"]
                if t.kind == .objectType { lines = ["import Foundation", "", "public final class \(name) {", ind(1) + "public static let shared = \(name)()", ind(1) + "private init() {}"] + body.map { ind(1) + $0 } + ["}"] }
                out.add("Sources/\(projectName)/\(name).swift", lines.joined(separator: "\n"))

            case .csharp:
                if t.kind == .enumType {
                    let cases = props.filter(\.isEnumCase).map { Ident.name($0.name, reserved: reserved(l), fallback: "Value") }
                    body += cases.isEmpty ? [] : [cases.joined(separator: ", ")]
                } else {
                    for p in props where !p.isEnumCase {
                        let ty = p.type ?? .any
                        let n = Ident.pascal(p.name, reserved: reserved(l))
                        if inInterface { body.append("\(ty.render(l)) \(n) { get; set; }"); continue }
                        var def = ""
                        if t.kind != .structType { switch ty { case .string: def = " = \"\";"; case .array, .dict: def = " = new();"; case .named, .any: def = " = default!;"; default: break } }
                        body.append("\(vis(p.visibility))\(ty.render(l)) \(n) { get; set; }\(def)")
                    }
                    for m in methods {
                        let sig = m.params.enumerated().map { paramText($1, $0) }.map { "\($0.type.render(l)) \($0.name)" }.joined(separator: ", ")
                        if m.isInit || m.name == t.name {
                            if !inInterface { body.append("\(vis(m.visibility))\(name)(\(sig)) { }") }
                            continue
                        }
                        let n = Ident.pascal(m.name, reserved: reserved(l))
                        let ret = (m.type ?? .void).render(l)
                        if inInterface { body.append("\(ret) \(n)(\(sig));"); continue }
                        let isOverride = baseChain(t).contains { memberNames($0).contains(m.name) }
                        let virt = isOverridden(m.name, in: t) ? "virtual " : ""
                        let mod = isOverride ? "override " : virt
                        let impl = ret == "void" ? "{ }" : "{ throw new NotImplementedException(); }"
                        body.append("\(vis(m.visibility).isEmpty ? "public " : vis(m.visibility))\(mod)\(ret) \(n)(\(sig)) \(impl)")
                    }
                }
                let kind: String
                switch t.kind {
                case .classType, .objectType, .actorType: kind = t.kind == .objectType ? "static class" : "class"
                case .structType: kind = "struct"; case .recordType: kind = "record"; case .enumType: kind = "enum"; case .protocolType, .interfaceType: kind = "interface"
                }
                let iname = t.kind.isInterface && !(name.count > 1 && name.first == "I" && name.dropFirst().first!.isUppercase) ? name : name
                let supers = ([base].compactMap { $0 } + interfaces)
                header = "public \(t.isAbstract && t.kind == .classType ? "abstract " : "")\(kind) \(iname)" + (supers.isEmpty ? "" : " : " + supers.joined(separator: ", "))
                lines = ["namespace \(projectName);", "", "using System;", "using System.Collections.Generic;", "", header, "{"] + body.map { ind(1) + $0 } + ["}"]
                out.add("\(name).cs", lines.joined(separator: "\n"))

            case .kotlin:
                if t.kind == .enumType {
                    let cases = props.filter(\.isEnumCase).map { Ident.name($0.name, reserved: reserved(l), fallback: "VALUE") }
                    body += cases.isEmpty ? [] : [cases.joined(separator: ", ")]
                } else {
                    for p in props where !p.isEnumCase {
                        let ty = p.type ?? .any
                        let n = Ident.camel(p.name, reserved: reserved(l))
                        if inInterface { body.append("var \(n): \(ty.render(l))"); continue }
                        var decl: String
                        switch ty {
                        case .int, .long: decl = "var \(n): \(ty.render(l)) = 0"; case .double: decl = "var \(n): Double = 0.0"; case .float: decl = "var \(n): Float = 0f"
                        case .bool: decl = "var \(n): Boolean = false"; case .string: decl = "var \(n): String = \"\""
                        case .array: decl = "var \(n): \(ty.render(l)) = emptyList()"; case .dict: decl = "var \(n): \(ty.render(l)) = emptyMap()"
                        case .optional: decl = "var \(n): \(ty.render(l)) = null"; default: decl = "lateinit var \(n): \(ty.render(l))"
                        }
                        body.append("\(vis(p.visibility))\(decl)")
                    }
                    for m in methods {
                        let sig = m.params.enumerated().map { paramText($1, $0) }.map { "\($0.name): \($0.type.render(l))" }.joined(separator: ", ")
                        if m.isInit || m.name == t.name { continue }                              // Kotlin constructors are declared on the class line
                        let n = Ident.camel(m.name, reserved: reserved(l))
                        let ret = m.type.flatMap { $0.isVoid ? nil : ": " + $0.render(l) } ?? ""
                        let override = inherited.contains(m.name) ? "override " : ""
                        if inInterface { body.append("fun \(n)(\(sig))\(ret)"); continue }
                        let open = isOverridden(m.name, in: t) && override.isEmpty ? "open " : ""
                        body.append("\(vis(m.visibility))\(override)\(open)fun \(n)(\(sig))\(ret) { TODO() }")
                    }
                }
                let supers = ([base.map { $0 + "()" }].compactMap { $0 } + interfaces)
                let supersText = supers.isEmpty ? "" : " : " + supers.joined(separator: ", ")
                let kind: String
                switch t.kind {
                case .classType, .actorType: kind = t.isAbstract ? "abstract class" : "open class"
                case .structType, .recordType: kind = "data class"; case .enumType: kind = "enum class"; case .protocolType, .interfaceType: kind = "interface"; case .objectType: kind = "object"
                }
                let ctor = (t.kind == .structType || t.kind == .recordType) && props.contains(where: { !$0.isEnumCase }) ? "" : (t.kind == .classType ? "()" : "")
                var dataParams = ""
                if t.kind == .structType || t.kind == .recordType {                                // a data class needs a primary constructor
                    let ps = props.filter { !$0.isEnumCase }.map { p -> String in
                        let ty = (p.type ?? .any)
                        let def: String
                        switch ty { case .int, .long: def = " = 0"; case .double: def = " = 0.0"; case .float: def = " = 0f"; case .bool: def = " = false"; case .string: def = " = \"\""
                        case .array: def = " = emptyList()"; case .dict: def = " = emptyMap()"; case .optional: def = " = null"; default: def = "" }
                        return "var \(Ident.camel(p.name, reserved: reserved(l))): \(ty.render(l))\(def)"
                    }
                    dataParams = "(" + (ps.isEmpty ? "val id: Int = 0" : ps.joined(separator: ", ")) + ")"
                    body = body.filter { !$0.hasPrefix("var ") && !$0.hasPrefix("lateinit") && !$0.hasPrefix("private var") && !$0.hasPrefix("protected var") && !$0.hasPrefix("internal var") }
                }
                _ = ctor
                header = "\(kind) \(name)\(dataParams)\(supersText) {"
                lines = ["package \(pkg)", "", header] + body.map { ind(1) + $0 } + ["}"]
                if body.isEmpty { lines = ["package \(pkg)", "", "\(kind) \(name)\(dataParams)\(supersText)"] }
                out.add("src/main/kotlin/\(pkg)/\(name).kt", lines.joined(separator: "\n"))

            case .java:
                if t.kind == .enumType {
                    let cases = props.filter(\.isEnumCase).map { Ident.name($0.name, reserved: reserved(l), fallback: "VALUE") }
                    body += cases.isEmpty ? [] : [cases.joined(separator: ", ") + ";"]
                } else {
                    for p in props where !p.isEnumCase {
                        let ty = p.type ?? .any
                        let n = Ident.camel(p.name, reserved: reserved(l))
                        if inInterface { continue }                                                 // interfaces have no instance fields
                        body.append("\(vis(p.visibility))\(ty.render(l)) \(n);")
                    }
                    for m in methods {
                        let sig = m.params.enumerated().map { paramText($1, $0) }.map { "\($0.type.render(l)) \($0.name)" }.joined(separator: ", ")
                        if m.isInit || m.name == t.name {
                            if !inInterface { body.append("\(vis(m.visibility))\(name)(\(sig)) { }") }
                            continue
                        }
                        let n = Ident.camel(m.name, reserved: reserved(l))
                        let ret = (m.type ?? .void).render(l)
                        let annotation = inherited.contains(m.name) && !inInterface ? "@Override " : ""
                        if inInterface { body.append("\(ret) \(n)(\(sig));"); continue }
                        let impl = ret == "void" ? "{ }" : "{ throw new UnsupportedOperationException(\"TODO\"); }"
                        body.append("\(annotation)\(vis(m.visibility).isEmpty ? "" : vis(m.visibility))\(ret) \(n)(\(sig)) \(impl)")
                    }
                }
                let kind: String
                switch t.kind {
                case .classType, .actorType, .objectType: kind = t.isAbstract ? "abstract class" : "class"
                case .structType, .recordType: kind = "class"; case .enumType: kind = "enum"; case .protocolType, .interfaceType: kind = "interface"
                }
                var text = "public \(kind) \(name)"
                if t.kind.isInterface { if !interfaces.isEmpty { text += " extends " + interfaces.joined(separator: ", ") } }
                else {
                    if let base { text += " extends \(base)" }
                    if !interfaces.isEmpty && t.kind != .enumType || (t.kind == .enumType && !interfaces.isEmpty) { text += " implements " + interfaces.joined(separator: ", ") }
                }
                lines = ["package \(pkg);", "", text + " {"] + body.map { ind(1) + $0 } + ["}"]
                out.add("src/main/java/\(pkg)/\(name).java", lines.joined(separator: "\n"))
            }
        }

        // The build files.
        switch l {
        case .swift:
            out.add("Package.swift", """
            // swift-tools-version:5.9
            import PackageDescription

            let package = Package(
                name: "\(projectName)",
                products: [.library(name: "\(projectName)", targets: ["\(projectName)"])],
                targets: [.target(name: "\(projectName)")]
            )
            """)
        case .csharp:
            out.add("\(projectName).csproj", """
            <Project Sdk="Microsoft.NET.Sdk">

              <PropertyGroup>
                <TargetFramework>net8.0</TargetFramework>
                <ImplicitUsings>enable</ImplicitUsings>
                <Nullable>enable</Nullable>
              </PropertyGroup>

            </Project>
            """)
        case .kotlin:
            out.add("settings.gradle.kts", "rootProject.name = \"\(pkg)\"")
            out.add("build.gradle.kts", "plugins {\n    kotlin(\"jvm\") version \"1.9.24\"\n}\n\nrepositories {\n    mavenCentral()\n}\n\nkotlin {\n    jvmToolchain(17)\n}")
        case .java:
            out.add("settings.gradle.kts", "rootProject.name = \"\(pkg)\"")
            out.add("build.gradle.kts", "plugins {\n    java\n}\n\nrepositories {\n    mavenCentral()\n}\n\njava {\n    toolchain.languageVersion.set(JavaLanguageVersion.of(17))\n}")
        }
        out.add("README.md", "# \(projectName)\n\nGenerated by Graffle from a classes diagram (\(title(l))): \(model.types.count) type\(model.types.count == 1 ? "" : "s").\n\nThe files are skeletons: members are declared, method bodies are placeholders (`TODO`), and parameter types the diagram doesn't carry are `\(CodeType.any.render(l))`.\n"
                    + (notes.isEmpty ? "" : "\n## Notes\n\n" + Array(Set(notes)).sorted().map { "- " + $0 }.joined(separator: "\n") + "\n"))
        out.notes = Array(Set(notes)).sorted()
        out.summary = "\(model.types.count) \(title(l)) file\(model.types.count == 1 ? "" : "s") plus the build files"
        return out
    }
}
