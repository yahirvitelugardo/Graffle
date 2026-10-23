import Foundation

/// One output a diagram can be turned into (a language, a SQL dialect, a project type).
struct CodeGenOption: Identifiable {
    var id: String { title }
    var title: String
    var make: (String) throws -> GeneratedProject

    static func choices(for source: DiagramSource) -> [CodeGenOption] {
        switch source {
        case .classes(let m):
            return ClassCode.languages.map { l in CodeGenOption(title: ClassCode.title(l)) { try ClassCode.generate(m, language: l, project: $0) } }
        case .entityRelationship(let m):
            return SQLDialect.allCases.map { d in CodeGenOption(title: d.title + " (SQL)") { try SQLCode.generate(m, dialect: d, project: $0) } }
        case .architecture(let m):
            let inferred = ScaffoldTarget.inferred(from: m)
            let order = [inferred] + ScaffoldTarget.allCases.filter { $0 != inferred }
            return order.map { t in CodeGenOption(title: t.title) { try ArchitectureScaffold.generate(m, target: t, project: $0) } }
        }
    }

    static func heading(for source: DiagramSource) -> String {
        switch source {
        case .classes: return "Language"
        case .entityRelationship: return "Database"
        case .architecture: return "Project type"
        }
    }
}
