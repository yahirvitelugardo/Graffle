import Foundation

/// What is read from a database: tables, their columns and the foreign keys between them.
struct DBColumn: Equatable {
    var name: String
    var type: String
    var isPrimaryKey = false
    var isNullable = true
}

struct DBForeignKey: Equatable {
    var column: String
    var refTable: String          // a table's `id`, as in DBTable.id
    var refColumn: String
}

struct DBTable: Equatable, Identifiable {
    /// "schema.table", or just the table when it has no schema.
    var id: String
    var name: String
    var columns: [DBColumn] = []
    var foreignKeys: [DBForeignKey] = []
}

struct DBSchema: Equatable {
    var tables: [DBTable] = []
    func table(_ id: String) -> DBTable? { tables.first { $0.id == id } }
}

/// Reads `CREATE TABLE` / `ALTER TABLE … FOREIGN KEY` statements from SQL text, whatever the dialect. Approximate, like a map of the script.
enum SQLScriptParser {
    private static func strip(_ sql: String) -> String {
        var s = sql.replacingOccurrences(of: "/\\*[\\s\\S]*?\\*/", with: " ", options: .regularExpression)
        s = s.replacingOccurrences(of: "--[^\\n]*", with: " ", options: .regularExpression)
        return s
    }

    private static func unquote(_ s: String) -> String {
        var t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        t = t.trimmingCharacters(in: CharacterSet(charactersIn: "`\"[]'"))
        return t
    }

    /// "[dbo].[Users]" -> ("dbo.Users" id, "Users" name when the schema is the default one).
    private static func tableID(_ raw: String) -> String {
        let parts = raw.split(separator: ".").map { unquote(String($0)) }
        return parts.joined(separator: ".")
    }

    private static func splitTop(_ s: String) -> [String] {
        var parts: [String] = [], cur = "", depth = 0
        for ch in s {
            if ch == "(" { depth += 1 } else if ch == ")" { depth -= 1 }
            if ch == "," && depth == 0 { parts.append(cur); cur = "" } else { cur.append(ch) }
        }
        if !cur.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { parts.append(cur) }
        return parts
    }

    private static func names(_ list: String) -> [String] { list.split(separator: ",").map { unquote(String($0)) } }

    private static func first(_ pattern: String, in s: String, options: NSRegularExpression.Options = [.caseInsensitive]) -> [String]? {
        guard let re = try? NSRegularExpression(pattern: pattern, options: options) else { return nil }
        let ns = s as NSString
        guard let m = re.firstMatch(in: s, range: NSRange(location: 0, length: ns.length)) else { return nil }
        return (0..<m.numberOfRanges).map { m.range(at: $0).location == NSNotFound ? "" : ns.substring(with: m.range(at: $0)) }
    }

    static func parse(_ sql: String) -> DBSchema {
        let text = strip(sql)
        let ns = text as NSString
        var tables: [DBTable] = []
        let header = try! NSRegularExpression(pattern: #"create\s+(?:(?:global\s+|local\s+)?(?:temporary|temp)\s+|unlogged\s+)?table\s+(?:if\s+not\s+exists\s+)?([`"\[\]\w.]+)\s*\("#, options: [.caseInsensitive])
        for m in header.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
            let name = tableID(ns.substring(with: m.range(at: 1)))
            var depth = 1, i = m.range.location + m.range.length
            let start = i
            while i < ns.length, depth > 0 {
                let c = ns.character(at: i)
                if c == 40 { depth += 1 } else if c == 41 { depth -= 1 }
                i += 1
            }
            guard depth == 0 else { continue }
            let body = ns.substring(with: NSRange(location: start, length: i - 1 - start))
            var table = DBTable(id: name, name: name)
            var pk: [String] = []
            for item in splitTop(body) {
                let t = item.trimmingCharacters(in: .whitespacesAndNewlines)
                if t.isEmpty { continue }
                if let c = first(#"^(?:constraint\s+\S+\s+)?primary\s+key\s*\(([^)]*)\)"#, in: t) { pk += names(c[1]); continue }
                if let c = first(#"^(?:constraint\s+\S+\s+)?foreign\s+key\s*\(([^)]*)\)\s*references\s+([`"\[\]\w.]+)\s*(?:\(([^)]*)\))?"#, in: t) {
                    let cols = names(c[1]), refs = names(c[3])
                    for (k, col) in cols.enumerated() { table.foreignKeys.append(DBForeignKey(column: col, refTable: tableID(c[2]), refColumn: k < refs.count ? refs[k] : "id")) }
                    continue
                }
                if first(#"^(?:constraint|unique|check|key|index|fulltext|spatial|exclude|like|period)\b"#, in: t) != nil { continue }
                // A column: name, type, then modifiers.
                guard let c = first(#"^([`"\[][^`"\]]+[`"\]]|\w+)\s*(.*)$"#, in: t, options: [.caseInsensitive, .dotMatchesLineSeparators]) else { continue }
                let colName = unquote(c[1])
                let rest = c[2]
                let typeEnd = rest.range(of: #"\b(not\s+null|null|primary|references|default|unique|check|auto_increment|autoincrement|identity|generated|collate|constraint|comment|on\s+update)\b"#,
                                         options: [.regularExpression, .caseInsensitive])
                let type = (typeEnd.map { String(rest[..<$0.lowerBound]) } ?? rest).trimmingCharacters(in: .whitespacesAndNewlines)
                var col = DBColumn(name: colName, type: type)
                if rest.range(of: #"\bprimary\s+key\b"#, options: [.regularExpression, .caseInsensitive]) != nil { col.isPrimaryKey = true; col.isNullable = false }
                if rest.range(of: #"\bnot\s+null\b"#, options: [.regularExpression, .caseInsensitive]) != nil { col.isNullable = false }
                if let r = first(#"references\s+([`"\[\]\w.]+)\s*(?:\(([^)]*)\))?"#, in: rest) {
                    table.foreignKeys.append(DBForeignKey(column: colName, refTable: tableID(r[1]), refColumn: names(r[2]).first ?? "id"))
                }
                table.columns.append(col)
            }
            for i in table.columns.indices where pk.contains(table.columns[i].name) { table.columns[i].isPrimaryKey = true; table.columns[i].isNullable = false }
            tables.append(table)
        }
        // ALTER TABLE x ADD [CONSTRAINT n] FOREIGN KEY (c) REFERENCES t (c)
        let alter = try! NSRegularExpression(pattern: #"alter\s+table\s+(?:only\s+)?([`"\[\]\w.]+)\s+add\s+(?:constraint\s+\S+\s+)?foreign\s+key\s*\(([^)]*)\)\s*references\s+([`"\[\]\w.]+)\s*(?:\(([^)]*)\))?"#, options: [.caseInsensitive])
        for m in alter.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
            func g(_ i: Int) -> String { m.range(at: i).location == NSNotFound ? "" : ns.substring(with: m.range(at: i)) }
            guard let idx = tables.firstIndex(where: { $0.id == tableID(g(1)) }) else { continue }
            let cols = names(g(2)), refs = names(g(4))
            for (k, col) in cols.enumerated() { tables[idx].foreignKeys.append(DBForeignKey(column: col, refTable: tableID(g(3)), refColumn: k < refs.count ? refs[k] : "id")) }
        }
        return resolved(DBSchema(tables: tables))
    }

    /// Foreign keys that name a table without its schema are matched to the table that has that name.
    static func resolved(_ schema: DBSchema) -> DBSchema {
        var out = schema
        let ids = Set(schema.tables.map(\.id))
        for t in out.tables.indices {
            for f in out.tables[t].foreignKeys.indices where !ids.contains(out.tables[t].foreignKeys[f].refTable) {
                let ref = out.tables[t].foreignKeys[f].refTable
                let last = (ref.split(separator: ".").last.map(String.init) ?? ref).lowercased()
                if let match = schema.tables.first(where: { ($0.id.split(separator: ".").last.map(String.init) ?? $0.id).lowercased() == last }) { out.tables[t].foreignKeys[f].refTable = match.id }
            }
        }
        return out
    }
}
