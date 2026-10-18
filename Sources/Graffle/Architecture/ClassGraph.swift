import Foundation

/// What to include when turning a project's types into a class diagram.
struct ClassOptions: Equatable {
    var includeMembers = true
    var includeTests = false
    var includePrivate = false
    /// Very large projects are cut to the most connected types so the diagram stays readable.
    var maxTypes = 150
}

enum SourceLanguage: String {
    case swift, csharp, kotlin, java

    init?(pathExtension ext: String) {
        switch ext.lowercased() {
        case "swift": self = .swift
        case "cs": self = .csharp
        case "kt": self = .kotlin
        case "java": self = .java
        default: return nil
        }
    }
}

enum TypeKind: String, CaseIterable {
    case classType = "class", structType = "struct", enumType = "enum", protocolType = "protocol", interfaceType = "interface"
    case actorType = "actor", objectType = "object", recordType = "record"

    var isInterface: Bool { self == .protocolType || self == .interfaceType }
    var title: String { rawValue.prefix(1).uppercased() + rawValue.dropFirst() }
}

struct TypeInfo: Equatable {
    var name: String
    var kind: TypeKind
    var language: SourceLanguage
    /// The names after the ":" (or `extends` / `implements`), cleaned of generics: base classes and protocols, known or not.
    var supertypes: [String] = []
    var properties: [String] = []
    var methods: [String] = []
    var file: String = ""
    var isTest = false
    var isAbstract = false
}

enum RelationKind: String {
    /// A class extends another.
    case inherits
    /// A type adopts a protocol or implements an interface.
    case implements
    /// A property of one type has another type.
    case association

    var rank: Int { self == .association ? 0 : 1 }
}

struct TypeRelation: Hashable {
    var from: String
    var to: String
    var kind: RelationKind
}

/// The types of a project and how they relate, independent of how they will be drawn.
struct ClassGraph {
    var title = ""
    var source = ""
    var types: [TypeInfo] = []
    var relations: [TypeRelation] = []
    /// Set when only part of a large project is shown: (shown, total).
    var truncated: (shown: Int, total: Int)?

    func type(named name: String) -> TypeInfo? { types.first { $0.name == name } }
}
