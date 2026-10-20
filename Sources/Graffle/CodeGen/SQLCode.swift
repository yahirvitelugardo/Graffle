import Foundation

enum SQLDialect: String, CaseIterable {
    case postgres, mysql, sqlite, sqlserver

    var title: String {
        switch self { case .postgres: return "PostgreSQL"; case .mysql: return "MySQL / MariaDB"; case .sqlite: return "SQLite"; case .sqlserver: return "SQL Server" }
    }

    func quote(_ n: String) -> String {
        switch self {
        case .mysql: return "`" + n.replacingOccurrences(of: "`", with: "``") + "`"
        case .sqlserver: return "[" + n.replacingOccurrences(of: "]", with: "]]") + "]"
        default: return "\"" + n.replacingOccurrences(of: "\"", with: "\"\"") + "\""
        }
    }
    var supportsSchemas: Bool { self == .postgres || self == .sqlserver }
}

/// Generates the `CREATE TABLE` script for the tables of an entity-relationship diagram.
enum SQLCode {
    // MARK: Types

    /// (base name, arguments) from "varchar(120)", "DOUBLE PRECISION", "numeric(10, 2)".
    static func split(_ type: String) -> (base: String, args: String) {
        let t = type.trimmingCharacters(in: .whitespaces).lowercased()
        guard let open = t.firstIndex(of: "("), let close = t.lastIndex(of: ")"), open < close else { return (t, "") }
        let base = t[..<open].trimmingCharacters(in: .whitespaces) + t[t.index(after: close)...]
        return (base.trimmingCharacters(in: .whitespaces), t[t.index(after: open)..<close].replacingOccurrences(of: " ", with: ""))
    }

    static func map(_ raw: String, _ d: SQLDialect) -> String {
        let (base, args) = split(raw)
        func pick(_ pg: String, _ my: String, _ lite: String, _ ms: String) -> String {
            switch d { case .postgres: return pg; case .mysql: return my; case .sqlite: return lite; case .sqlserver: return ms }
        }
        switch base {
        case "int", "integer", "int4", "serial", "mediumint": return pick("integer", "INT", "INTEGER", "INT")
        case "bigint", "int8", "bigserial": return pick("bigint", "BIGINT", "INTEGER", "BIGINT")
        case "smallint", "int2", "tinyint": return pick("smallint", "SMALLINT", "INTEGER", "SMALLINT")
        case "text", "longtext", "mediumtext", "clob", "ntext": return pick("text", "TEXT", "TEXT", "NVARCHAR(MAX)")
        case "varchar", "character varying", "nvarchar", "string":
            let n = args.isEmpty ? "255" : args
            return pick("varchar(\(n))", "VARCHAR(\(n))", "TEXT", args.lowercased() == "max" ? "NVARCHAR(MAX)" : "NVARCHAR(\(n))")
        case "char", "character", "nchar", "bpchar":
            let n = args.isEmpty ? "1" : args
            return pick("char(\(n))", "CHAR(\(n))", "TEXT", "NCHAR(\(n))")
        case "bool", "boolean", "bit": return pick("boolean", "TINYINT(1)", "INTEGER", "BIT")
        case "real", "float4": return pick("real", "FLOAT", "REAL", "REAL")
        case "float", "double", "double precision", "float8": return pick("double precision", "DOUBLE", "REAL", "FLOAT")
        case "decimal", "numeric", "money":
            let a = args.isEmpty ? "" : "(\(args))"
            return pick("numeric\(a)", "DECIMAL\(a.isEmpty ? "(10,2)" : a)", "NUMERIC", "DECIMAL\(a.isEmpty ? "(18,2)" : a)")
        case "timestamp", "timestamp without time zone", "timestamp with time zone", "timestamptz", "datetime", "datetime2", "smalldatetime":
            return pick("timestamp", "DATETIME", "TEXT", "DATETIME2")
        case "date": return pick("date", "DATE", "TEXT", "DATE")
        case "time", "time without time zone": return pick("time", "TIME", "TEXT", "TIME")
        case "uuid", "uniqueidentifier": return pick("uuid", "CHAR(36)", "TEXT", "UNIQUEIDENTIFIER")
        case "blob", "bytea", "binary", "varbinary", "longblob": return pick("bytea", "BLOB", "BLOB", "VARBINARY(MAX)")
        case "json", "jsonb": return pick("jsonb", "JSON", "TEXT", "NVARCHAR(MAX)")
        default: return raw.isEmpty ? pick("text", "TEXT", "TEXT", "NVARCHAR(MAX)") : raw
        }
    }

    private static func isInteger(_ raw: String) -> Bool {
        ["int", "integer", "int4", "serial", "bigint", "int8", "bigserial", "smallint", "mediumint"].contains(split(raw).base)
    }

    // MARK: Script

    static func generate(_ model: ERModel, dialect d: SQLDialect, project: String? = nil) throws -> GeneratedProject {
        let tables = model.tables
        guard !tables.isEmpty else { throw CodeGenError.nothingToGenerate("The diagram has no tables to generate a schema from.") }
        let chosen = Set(tables.map(\.id))

        // Names: "schema.table" is qualified where the database has schemas, and flattened where it doesn't.
        func qualified(_ id: String) -> (schema: String?, table: String) {
            let parts = id.split(separator: ".").map(String.init)
            if parts.count >= 2 { return d.supportsSchemas ? (parts[0], parts[1...].joined(separator: "_")) : (nil, parts.joined(separator: "_")) }
            return (nil, id)
        }
        func ref(_ id: String) -> String {
            let q = qualified(id)
            return (q.schema.map { d.quote($0) + "." } ?? "") + d.quote(q.table)
        }

        // Dependency order: a table comes after the tables it refers to. What cannot be ordered (cycles) gets its keys added afterwards.
        var order: [DBTable] = [], placed = Set<String>()
        var remaining = tables
        while !remaining.isEmpty {
            let ready = remaining.filter { t in t.foreignKeys.allSatisfy { !chosen.contains($0.refTable) || $0.refTable == t.id || placed.contains($0.refTable) } }
            let next = ready.isEmpty ? [remaining[0]] : ready
            for t in next { order.append(t); placed.insert(t.id) }
            remaining.removeAll { r in next.contains { $0.id == r.id } }
        }
        let position = Dictionary(uniqueKeysWithValues: order.enumerated().map { ($1.id, $0) })

        var out = ["-- Schema generated by Graffle from the diagram\(project.map { " “\($0)”" } ?? ""), for \(d.title)."]
        out.append("-- Review the types and add indexes, constraints and defaults before using it for real data.")
        if d.supportsSchemas {
            let schemas = Set(tables.compactMap { qualified($0.id).schema })
            for s in schemas.sorted() { out.append(d == .postgres ? "\nCREATE SCHEMA IF NOT EXISTS \(d.quote(s));" : "\nIF NOT EXISTS (SELECT * FROM sys.schemas WHERE name = '\(s)') EXEC('CREATE SCHEMA \(d.quote(s))');\nGO") }
        }
        var deferred: [String] = []
        var notes: [String] = []
        for t in order {
            let pk = t.columns.filter(\.isPrimaryKey)
            let singleIntegerKey = pk.count == 1 && isInteger(pk[0].type)
            var lines: [String] = []
            for c in t.columns {
                var type = map(c.type, d)
                var extra = ""
                if singleIntegerKey, c.isPrimaryKey {
                    switch d {
                    case .postgres: type = split(c.type).base.contains("big") ? "bigint" : "integer"; extra = " GENERATED BY DEFAULT AS IDENTITY"
                    case .mysql: extra = " AUTO_INCREMENT"
                    case .sqlite: type = "INTEGER"; extra = " PRIMARY KEY AUTOINCREMENT"
                    case .sqlserver: extra = " IDENTITY(1,1)"
                    }
                }
                let nullability = (c.isNullable && !c.isPrimaryKey) ? "" : " NOT NULL"
                lines.append("  \(d.quote(c.name)) \(type)\(nullability)\(extra)")
            }
            if !pk.isEmpty && !(d == .sqlite && singleIntegerKey) {
                lines.append("  PRIMARY KEY (\(pk.map { d.quote($0.name) }.joined(separator: ", ")))")
            }
            // Foreign keys inline when the table they point to already exists; otherwise (cycles) afterwards.
            for (i, f) in t.foreignKeys.enumerated() where chosen.contains(f.refTable) {
                let clause = "FOREIGN KEY (\(d.quote(f.column))) REFERENCES \(ref(f.refTable)) (\(d.quote(f.refColumn)))"
                let backward = f.refTable == t.id || (position[f.refTable] ?? 0) < (position[t.id] ?? 0) || d == .sqlite
                if backward { lines.append("  " + clause) }
                else {
                    deferred.append("ALTER TABLE \(ref(t.id)) ADD CONSTRAINT \(d.quote("fk_\(qualified(t.id).table)_\(i + 1)")) \(clause);")
                }
            }
            for f in t.foreignKeys where !chosen.contains(f.refTable) { notes.append("\(t.name).\(f.column) refers to \(f.refTable), which isn't in the diagram: its foreign key was left out.") }
            out.append("\nCREATE TABLE \(ref(t.id)) (\n\(lines.joined(separator: ",\n"))\n);")
        }
        if !deferred.isEmpty { out.append("\n-- Keys that close a cycle between tables\n" + deferred.joined(separator: "\n")) }

        var project = GeneratedProject()
        project.add("schema.sql", out.joined(separator: "\n"))
        project.add("README.md", "# Database schema\n\nGenerated by Graffle for \(d.title): \(tables.count) table\(tables.count == 1 ? "" : "s").\n\nRun `schema.sql` on an empty database.\n"
                    + (notes.isEmpty ? "" : "\n## Notes\n\n" + notes.map { "- " + $0 }.joined(separator: "\n") + "\n"))
        project.summary = "schema.sql for \(d.title) with \(tables.count) table\(tables.count == 1 ? "" : "s")"
        project.notes = notes
        return project
    }
}
