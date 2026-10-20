import Foundation

/// The meaning behind a generated diagram, saved in the document: the modules and their dependencies, the classes, or the tables.
/// Code generation works from this (the diagram as it was created), not from the shapes on the canvas.
enum DiagramSource: Codable, Equatable {
    case architecture(ArchitectureModel)
    case classes(ClassModel)
    case entityRelationship(ERModel)

    var kindTitle: String {
        switch self {
        case .architecture: return "software architecture"
        case .classes: return "classes"
        case .entityRelationship: return "entity-relationship"
        }
    }
}

struct ArchitectureModel: Codable, Equatable {
    var title: String
    var source: String
    var nodes: [ArchitectureNode]
    var edges: [ArchitectureEdge]

    init(title: String, source: String, nodes: [ArchitectureNode], edges: [ArchitectureEdge]) { self.title = title; self.source = source; self.nodes = nodes; self.edges = edges }
    init(_ graph: ArchitectureGraph) { title = graph.title; source = graph.source; nodes = graph.nodes; edges = graph.edges }
}

struct ClassModel: Codable, Equatable {
    var title: String
    var source: String
    var types: [TypeInfo]
    var relations: [TypeRelation]

    init(title: String, source: String, types: [TypeInfo], relations: [TypeRelation]) { self.title = title; self.source = source; self.types = types; self.relations = relations }
    init(_ graph: ClassGraph) { title = graph.title; source = graph.source; types = graph.types; relations = graph.relations }
}

struct ERModel: Codable, Equatable {
    var title: String
    var schema: DBSchema
    /// The tables that are drawn, in order.
    var tableIDs: [String]

    var tables: [DBTable] { schema.tables.filter { tableIDs.contains($0.id) } }
}
