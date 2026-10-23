import Foundation
import SQLite3

enum DatabaseKind: String, CaseIterable {
    case sqlite, postgres, mysql, sqlserver, sqlScript

    var title: String {
        switch self {
        case .sqlite: return "SQLite (file)"
        case .postgres: return "PostgreSQL"
        case .mysql: return "MySQL / MariaDB"
        case .sqlserver: return "SQL Server"
        case .sqlScript: return "SQL script (.sql)"
        }
    }
    var isFile: Bool { self == .sqlite || self == .sqlScript }
    var defaultPort: String {
        switch self { case .postgres: return "5432"; case .mysql: return "3306"; case .sqlserver: return "1433"; default: return "" }
    }
    var defaultUser: String {
        switch self { case .postgres: return "postgres"; case .mysql: return "root"; case .sqlserver: return "sa"; default: return "" }
    }
    /// The command-line client that is used to talk to the server.
    var client: String? {
        switch self { case .postgres: return "psql"; case .mysql: return "mysql"; case .sqlserver: return "sqlcmd"; default: return nil }
    }
    var installHint: String {
        switch self {
        case .postgres: return "Install the PostgreSQL client (for example `brew install libpq`) and try again."
        case .mysql: return "Install the MySQL client (for example `brew install mysql-client`) and try again."
        case .sqlserver: return "Install sqlcmd (for example `brew install sqlcmd`) and try again."
        default: return ""
        }
    }
}

struct DatabaseConnection: Equatable {
    var kind: DatabaseKind = .sqlite
    var host = "localhost"
    var port = ""
    var user = ""
    /// Used for this connection only; Graffle never saves it.
    var password = ""
    var database = ""
    /// The file for SQLite and SQL scripts.
    var path = ""
}

enum DatabaseError: LocalizedError {
    case message(String)
    var errorDescription: String? { if case .message(let m) = self { return m } else { return nil } }
}

/// Reads a database's structure.
enum DatabaseConnector {
    /// Runs a command-line client: (executable name, arguments, environment) -> its output. Replaceable so tests can feed canned output.
    typealias Runner = (String, [String], [String: String]) throws -> String

    static let unit = "\u{1F}"

    static func readSchema(_ c: DatabaseConnection, runner: Runner = run) throws -> DBSchema {
        switch c.kind {
        case .sqlite: return try readSQLite(path: c.path)
        case .sqlScript:
            guard let text = (try? String(contentsOfFile: c.path, encoding: .utf8)) ?? (try? String(contentsOfFile: c.path, encoding: .isoLatin1)) else {
                throw DatabaseError.message("The file couldn't be read.")
            }
            let schema = SQLScriptParser.parse(text)
            if schema.tables.isEmpty { throw DatabaseError.message("No CREATE TABLE statements were found in this script.") }
            return schema
        case .postgres, .mysql, .sqlserver: return try readServer(c, runner: runner)
        }
    }

    // MARK: SQLite

    private static func readSQLite(path: String) throws -> DBSchema {
        var db: OpaquePointer?
        guard sqlite3_open_v2(path, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK, let db else {
            throw DatabaseError.message("The SQLite file couldn't be opened.")
        }
        defer { sqlite3_close(db) }
        func rows(_ sql: String) throws -> [[String]] {
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK, let stmt else {
                throw DatabaseError.message(String(cString: sqlite3_errmsg(db)))
            }
            defer { sqlite3_finalize(stmt) }
            var out: [[String]] = []
            while sqlite3_step(stmt) == SQLITE_ROW {
                out.append((0..<sqlite3_column_count(stmt)).map { i in sqlite3_column_text(stmt, i).map { String(cString: $0) } ?? "" })
            }
            return out
        }
        var tables: [DBTable] = []
        for row in try rows("SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%' ORDER BY name") {
            let name = row[0]
            let quoted = "\"" + name.replacingOccurrences(of: "\"", with: "\"\"") + "\""
            var t = DBTable(id: name, name: name)
            for c in try rows("PRAGMA table_info(\(quoted))") {                        // cid, name, type, notnull, dflt, pk
                t.columns.append(DBColumn(name: c[1], type: c[2].lowercased(), isPrimaryKey: c[5] != "0", isNullable: c[3] == "0" && c[5] == "0"))
            }
            for f in try rows("PRAGMA foreign_key_list(\(quoted))") {                  // id, seq, table, from, to, ...
                t.foreignKeys.append(DBForeignKey(column: f[3], refTable: f[2], refColumn: f[4].isEmpty ? "id" : f[4]))
            }
            tables.append(t)
        }
        if tables.isEmpty { throw DatabaseError.message("This database has no tables.") }
        return DBSchema(tables: tables)
    }

    // MARK: Servers (through their command-line clients)

    /// Where the clients usually live, besides the PATH.
    static let searchPaths = ["/opt/homebrew/bin", "/opt/homebrew/opt/libpq/bin", "/opt/homebrew/opt/mysql-client/bin", "/usr/local/bin", "/usr/local/opt/libpq/bin",
                              "/usr/local/opt/mysql-client/bin", "/usr/local/mysql/bin", "/Applications/Postgres.app/Contents/Versions/latest/bin", "/usr/bin"]

    static func find(_ tool: String) -> String? {
        let dirs = (ProcessInfo.processInfo.environment["PATH"] ?? "").split(separator: ":").map(String.init) + searchPaths
        return dirs.map { $0 + "/" + tool }.first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    #if !os(macOS)
    static func run(_ tool: String, _ args: [String], _ env: [String: String]) throws -> String {
        throw DatabaseError.message("Server databases need the `\(tool)` command-line client, which only exists on a Mac. Open a SQLite file or a SQL script instead.")
    }
    #else
    static func run(_ tool: String, _ args: [String], _ env: [String: String]) throws -> String {
        guard let exe = find(tool) else { throw DatabaseError.message("`\(tool)` isn't installed.") }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: exe)
        process.arguments = args
        process.environment = ProcessInfo.processInfo.environment.merging(env) { $1 }
        let tmp = FileManager.default.temporaryDirectory
        let outFile = tmp.appendingPathComponent("graffle-db-\(UUID().uuidString).out"), errFile = tmp.appendingPathComponent("graffle-db-\(UUID().uuidString).err")
        FileManager.default.createFile(atPath: outFile.path, contents: nil)
        FileManager.default.createFile(atPath: errFile.path, contents: nil)
        defer { try? FileManager.default.removeItem(at: outFile); try? FileManager.default.removeItem(at: errFile) }
        process.standardOutput = try FileHandle(forWritingTo: outFile)
        process.standardError = try FileHandle(forWritingTo: errFile)
        process.standardInput = FileHandle.nullDevice
        try process.run()
        let watchdog = DispatchWorkItem { if process.isRunning { process.terminate() } }
        DispatchQueue.global().asyncAfter(deadline: .now() + 40, execute: watchdog)
        process.waitUntilExit()
        watchdog.cancel()
        let out = (try? String(contentsOf: outFile, encoding: .utf8)) ?? ""
        if process.terminationStatus != 0 {
            let err = ((try? String(contentsOf: errFile, encoding: .utf8)) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            throw DatabaseError.message(err.isEmpty ? "The connection failed (\(tool) exited with \(process.terminationStatus))." : String(err.suffix(500)))
        }
        return out
    }
    #endif

    private static func command(for c: DatabaseConnection, sql: String) -> (tool: String, args: [String], env: [String: String]) {
        switch c.kind {
        case .postgres:
            return ("psql", ["-h", c.host, "-p", c.port.isEmpty ? "5432" : c.port, "-U", c.user, "-d", c.database, "-X", "-w", "-A", "-t", "-F", unit, "-c", sql],
                    ["PGPASSWORD": c.password, "PGCONNECT_TIMEOUT": "10"])
        case .mysql:
            return ("mysql", ["-h", c.host, "-P", c.port.isEmpty ? "3306" : c.port, "-u", c.user, "-D", c.database, "--connect-timeout=10", "-B", "-N", "-e", sql],
                    ["MYSQL_PWD": c.password])
        default:
            return ("sqlcmd", ["-S", c.host + "," + (c.port.isEmpty ? "1433" : c.port), "-U", c.user, "-d", c.database, "-C", "-l", "10", "-h", "-1", "-W", "-s", "|", "-Q", "SET NOCOUNT ON; " + sql],
                    ["SQLCMDPASSWORD": c.password])
        }
    }

    /// Rows of fields from the client's output (psql separates with the unit separator, mysql with tabs, sqlcmd with "|").
    static func parse(_ output: String, kind: DatabaseKind) -> [[String]] {
        let sep: Character = kind == .postgres ? Character(unit) : (kind == .mysql ? "\t" : "|")
        return output.split(whereSeparator: \.isNewline).map { $0.split(separator: sep, omittingEmptySubsequences: false).map { $0.trimmingCharacters(in: .whitespaces) } }
            .filter { $0.count > 1 }
    }

    static func columnsQuery(_ kind: DatabaseKind) -> String {
        let hidden: String
        switch kind {
        case .postgres: hidden = "c.table_schema NOT IN ('pg_catalog','information_schema')"
        case .mysql: hidden = "c.table_schema = DATABASE()"
        default: hidden = "c.table_schema NOT IN ('sys','INFORMATION_SCHEMA')"
        }
        return "SELECT c.table_schema, c.table_name, c.column_name, c.data_type, c.is_nullable, CASE WHEN pk.column_name IS NULL THEN 0 ELSE 1 END "
            + "FROM information_schema.columns c JOIN information_schema.tables t ON t.table_schema = c.table_schema AND t.table_name = c.table_name AND t.table_type = 'BASE TABLE' "
            + "LEFT JOIN (SELECT k.table_schema, k.table_name, k.column_name FROM information_schema.table_constraints tc JOIN information_schema.key_column_usage k "
            + "ON tc.constraint_name = k.constraint_name AND tc.table_schema = k.table_schema AND tc.table_name = k.table_name WHERE tc.constraint_type = 'PRIMARY KEY') pk "
            + "ON pk.table_schema = c.table_schema AND pk.table_name = c.table_name AND pk.column_name = c.column_name "
            + "WHERE \(hidden) ORDER BY c.table_schema, c.table_name, c.ordinal_position"
    }

    static func foreignKeysQuery(_ kind: DatabaseKind) -> String {
        switch kind {
        case .postgres:
            return "SELECT k.table_schema, k.table_name, k.column_name, u.table_schema, u.table_name, u.column_name FROM information_schema.table_constraints tc "
                + "JOIN information_schema.key_column_usage k ON tc.constraint_name = k.constraint_name AND tc.table_schema = k.table_schema "
                + "JOIN information_schema.constraint_column_usage u ON u.constraint_name = tc.constraint_name AND u.constraint_schema = tc.table_schema WHERE tc.constraint_type = 'FOREIGN KEY'"
        case .mysql:
            return "SELECT table_schema, table_name, column_name, referenced_table_schema, referenced_table_name, referenced_column_name FROM information_schema.key_column_usage "
                + "WHERE referenced_table_name IS NOT NULL AND table_schema = DATABASE()"
        default:
            return "SELECT SCHEMA_NAME(t.schema_id), t.name, c.name, SCHEMA_NAME(rt.schema_id), rt.name, rc.name FROM sys.foreign_key_columns fkc "
                + "JOIN sys.tables t ON t.object_id = fkc.parent_object_id JOIN sys.columns c ON c.object_id = t.object_id AND c.column_id = fkc.parent_column_id "
                + "JOIN sys.tables rt ON rt.object_id = fkc.referenced_object_id JOIN sys.columns rc ON rc.object_id = rt.object_id AND rc.column_id = fkc.referenced_column_id"
        }
    }

    private static func readServer(_ c: DatabaseConnection, runner: Runner) throws -> DBSchema {
        func rows(_ sql: String) throws -> [[String]] {
            let cmd = command(for: c, sql: sql)
            do { return parse(try runner(cmd.tool, cmd.args, cmd.env), kind: c.kind) }
            catch let e as DatabaseError {
                if case .message(let m) = e, m.contains("isn't installed") { throw DatabaseError.message(m + " " + c.kind.installHint) }
                throw e
            }
        }
        // The schema shown in table names is left out for the default one.
        let plain: Set<String> = ["public", "dbo", c.database]
        func id(_ schema: String, _ table: String) -> String { plain.contains(schema) || schema.isEmpty ? table : schema + "." + table }
        var tables: [DBTable] = []
        var index: [String: Int] = [:]
        for r in try rows(columnsQuery(c.kind)) where r.count >= 6 {
            let tid = id(r[0], r[1])
            if index[tid] == nil { index[tid] = tables.count; tables.append(DBTable(id: tid, name: tid)) }
            tables[index[tid]!].columns.append(DBColumn(name: r[2], type: r[3], isPrimaryKey: r[5] == "1", isNullable: r[4].uppercased() == "YES" && r[5] != "1"))
        }
        if tables.isEmpty { throw DatabaseError.message("The connection worked, but no tables were found.") }
        for r in try rows(foreignKeysQuery(c.kind)) where r.count >= 6 {
            guard let i = index[id(r[0], r[1])] else { continue }
            let fk = DBForeignKey(column: r[2], refTable: id(r[3], r[4]), refColumn: r[5])
            if !tables[i].foreignKeys.contains(fk) { tables[i].foreignKeys.append(fk) }
        }
        return DBSchema(tables: tables)
    }
}
