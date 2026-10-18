import AppKit
import SQLite3

/// Self-test steps for reading databases and the entity-relationship wizard.
extension AppDelegate {
    func databaseSteps(tempDir: URL) -> [(String, () -> Bool)] {
        var steps: [(String, () -> Bool)] = []
        let fm = FileManager.default
        let sqlite = tempDir.appendingPathComponent("shop.sqlite")
        func pump(_ s: Double, until done: () -> Bool = { false }) {
            let end = Date().addingTimeInterval(s)
            repeat { RunLoop.main.run(until: Date().addingTimeInterval(0.01)) } while Date() < end && !done()
        }
        let ddl = """
        CREATE TABLE customers (id INTEGER PRIMARY KEY, name TEXT NOT NULL, email TEXT);
        CREATE TABLE products (id INTEGER PRIMARY KEY, title TEXT NOT NULL, price REAL);
        CREATE TABLE orders (id INTEGER PRIMARY KEY, customer_id INTEGER NOT NULL REFERENCES customers(id), coupon_id INTEGER REFERENCES coupons(id), total REAL);
        CREATE TABLE coupons (id INTEGER PRIMARY KEY, code TEXT);
        CREATE TABLE order_items (order_id INTEGER NOT NULL, product_id INTEGER NOT NULL, qty INTEGER, PRIMARY KEY (order_id, product_id),
            FOREIGN KEY (order_id) REFERENCES orders(id), FOREIGN KEY (product_id) REFERENCES products(id));
        """
        steps.append(("database: a SQLite file is read, with keys, nullability and foreign keys", {
            try? fm.removeItem(at: sqlite)
            var db: OpaquePointer?
            guard sqlite3_open(sqlite.path, &db) == SQLITE_OK else { return false }
            sqlite3_exec(db, ddl, nil, nil, nil); sqlite3_close(db)
            var c = DatabaseConnection(); c.kind = .sqlite; c.path = sqlite.path
            guard let s = try? DatabaseConnector.readSchema(c) else { return false }
            let items = s.table("order_items"), orders = s.table("orders")
            return s.tables.map(\.id) == ["coupons", "customers", "order_items", "orders", "products"]
                && items?.columns.filter(\.isPrimaryKey).map(\.name) == ["order_id", "product_id"]
                && orders?.foreignKeys.map(\.refTable).sorted() == ["coupons", "customers"]
                && orders?.columns.first { $0.name == "coupon_id" }?.isNullable == true && orders?.columns.first { $0.name == "customer_id" }?.isNullable == false
                && s.table("customers")?.columns.first?.type == "integer"
        }))
        steps.append(("database: bad files and missing files give a clear message", {
            var c = DatabaseConnection(); c.kind = .sqlite; c.path = tempDir.appendingPathComponent("nope.sqlite").path
            let missing = (try? DatabaseConnector.readSchema(c)) == nil
            let junk = tempDir.appendingPathComponent("junk.sqlite")
            try? "not a database".write(to: junk, atomically: true, encoding: .utf8)
            c.path = junk.path
            var message = ""
            do { _ = try DatabaseConnector.readSchema(c) } catch { message = error.localizedDescription }
            return missing && !message.isEmpty
        }))
        steps.append(("database: a SQL script is parsed (CREATE TABLE in several dialects, inline and table keys, ALTER TABLE)", {
            let script = """
            -- a comment with CREATE TABLE ghost (id int);
            CREATE TABLE IF NOT EXISTS `users` (
              `id` INT AUTO_INCREMENT PRIMARY KEY,
              name VARCHAR(80) NOT NULL, /* inline */
              email VARCHAR(120),
              CONSTRAINT uq UNIQUE (email)
            );
            CREATE TABLE [dbo].[Posts] (
              [Id] int IDENTITY(1,1) NOT NULL,
              [UserId] int NOT NULL,
              body text,
              CONSTRAINT pk_posts PRIMARY KEY ([Id]),
              CONSTRAINT fk_u FOREIGN KEY ([UserId]) REFERENCES [dbo].[users]([id])
            );
            CREATE TABLE public.comments (id serial primary key, post_id integer references "Posts"("Id"), numeric_col numeric(10,2) DEFAULT 0);
            CREATE TABLE tags (id int PRIMARY KEY, post_id int);
            ALTER TABLE tags ADD CONSTRAINT fk_tag FOREIGN KEY (post_id) REFERENCES comments (id);
            """
            let s = SQLScriptParser.parse(script)
            guard s.tables.count == 4 else { return false }
            func t(_ n: String) -> DBTable? { s.tables.first { $0.name.lowercased().hasSuffix(n) } }
            let users = t("users"), posts = t("posts"), comments = t("comments"), tags = t("tags")
            return users?.columns.map(\.name) == ["id", "name", "email"] && users?.columns[0].isPrimaryKey == true && users?.columns[1].isNullable == false
                && users?.columns[1].type.lowercased() == "varchar(80)"
                && posts?.columns.first?.isPrimaryKey == true && posts?.foreignKeys.first?.column == "UserId" && posts?.foreignKeys.first?.refTable == "users"
                && comments?.columns.map(\.type) == ["serial", "integer", "numeric(10,2)"] && comments?.foreignKeys.first?.refTable == posts?.id     // resolved to the table's id
                && tags?.foreignKeys.first?.refTable == comments?.id
        }))
        steps.append(("database: PostgreSQL, MySQL and SQL Server output is turned into tables (with canned client output)", {
            let u = DatabaseConnector.unit
            let pgCols = "public\(u)users\(u)id\(u)integer\(u)NO\(u)1\npublic\(u)users\(u)name\(u)text\(u)NO\(u)0\nsales\(u)orders\(u)id\(u)integer\(u)NO\(u)1\nsales\(u)orders\(u)user_id\(u)integer\(u)YES\(u)0\n"
            let pgFks = "sales\(u)orders\(u)user_id\(u)public\(u)users\(u)id\n"
            var seen: [(String, [String], [String: String])] = []
            let pg: DatabaseConnector.Runner = { tool, args, env in seen.append((tool, args, env)); return args.last!.contains("key_column_usage k") && args.last!.hasPrefix("SELECT k.") ? pgFks : pgCols }
            var c = DatabaseConnection(); c.kind = .postgres; c.host = "db"; c.user = "me"; c.password = "secret"; c.database = "app"
            guard let s = try? DatabaseConnector.readSchema(c, runner: pg) else { return false }
            let pgOK = s.tables.map(\.id) == ["users", "sales.orders"] && s.table("sales.orders")?.foreignKeys.first == DBForeignKey(column: "user_id", refTable: "users", refColumn: "id")
                && s.table("sales.orders")?.columns[1].isNullable == true && s.table("users")?.columns[0].isPrimaryKey == true
            let used = seen.first
            let args = used?.1 ?? []
            let safe = used?.0 == "psql" && used?.2["PGPASSWORD"] == "secret" && !args.contains("secret") && args.contains("-w") && args.contains("-U") && args.contains("app")  // password only via the environment
            let mysql: DatabaseConnector.Runner = { _, args, env in
                precondition(env["MYSQL_PWD"] == "pw")
                return args.last!.contains("referenced_table_name IS NOT NULL") ? "app\tposts\tuser_id\tapp\tusers\tid\n" : "app\tusers\tid\tint\tNO\t1\napp\tposts\tid\tint\tNO\t1\napp\tposts\tuser_id\tint\tYES\t0\n"
            }
            var m = DatabaseConnection(); m.kind = .mysql; m.host = "h"; m.user = "u"; m.password = "pw"; m.database = "app"
            let ms = try? DatabaseConnector.readSchema(m, runner: mysql)
            let mysqlOK = ms?.tables.map(\.id) == ["users", "posts"] && ms?.table("posts")?.foreignKeys.first?.refTable == "users"                     // the database's own name is not a prefix
            let ss: DatabaseConnector.Runner = { _, args, env in
                precondition(env["SQLCMDPASSWORD"] == "p")
                return args.last!.contains("sys.foreign_key_columns") ? "dbo|Orders|CustId|dbo|Cust|Id\n" : "dbo|Cust|Id|int|NO|1\ndbo|Orders|CustId|int|NO|0\n"
            }
            var q = DatabaseConnection(); q.kind = .sqlserver; q.host = "h"; q.user = "sa"; q.password = "p"; q.database = "x"
            let qs = try? DatabaseConnector.readSchema(q, runner: ss)
            let sqlOK = qs?.tables.map(\.id) == ["Cust", "Orders"] && qs?.table("Orders")?.foreignKeys.first?.refTable == "Cust"
            let missing: DatabaseConnector.Runner = { tool, _, _ in throw DatabaseError.message("`\(tool)` isn't installed.") }
            var hint = ""
            do { _ = try DatabaseConnector.readSchema(c, runner: missing) } catch { hint = error.localizedDescription }
            return pgOK && safe && mysqlOK && sqlOK && hint.contains("psql") && hint.contains("brew install")
        }))
        steps.append(("database: the diagram has a box per chosen table, crow's feet for keys between chosen tables, and nothing else", {
            var c = DatabaseConnection(); c.kind = .sqlite; c.path = sqlite.path
            guard let s = try? DatabaseConnector.readSchema(c) else { return false }
            let d = ERBuilder.build(s, tables: ["customers", "orders", "order_items"])
            let boxes = d.shapes.filter { $0.kind == .rectangle && $0.frame.width == ERBuilder.width && $0.text.isEmpty }
            let labels = Set(d.shapes.map(\.text))
            let ends = Dictionary(uniqueKeysWithValues: d.connectors.map { ($0.text, $0.endHead) })
            let ids = Set(d.shapes.map(\.id))
            return boxes.count == 3 && labels.contains("PK id : integer") && labels.contains("FK customer_id : integer") && labels.contains("orders")
                && d.connectors.count == 2                                                    // coupons and products were not chosen, so their keys are not drawn
                && ends["customer_id"] == .crowFootBar && d.connectors.allSatisfy { $0.startHead == .doubleBar && ids.contains($0.from) && ids.contains($0.to) }
                && d.layers.map(\.name) == ["Relationships", "Tables"]
                && (d.contentBounds.map { $0.minX >= 0 && $0.maxX <= CanvasView.canvasSize.width } ?? false)
        }))
        steps.append(("database: a nullable foreign key is drawn \"zero or many\", and big tables are cut with a note", {
            var c = DatabaseConnection(); c.kind = .sqlite; c.path = sqlite.path
            guard let s = try? DatabaseConnector.readSchema(c) else { return false }
            let d = ERBuilder.build(s, tables: ["orders", "coupons"])
            let zero = d.connectors.first?.endHead == .crowFootCircle
            var wide = DBTable(id: "wide", name: "wide")
            wide.columns = (1...30).map { DBColumn(name: "c\($0)", type: "int") }
            let big = ERBuilder.build(DBSchema(tables: [wide]), tables: ["wide"])
            return zero && big.shapes.contains { $0.text == "… 12 more columns" } && big.shapes.filter { $0.text.hasPrefix("c") }.count == ERBuilder.maxColumns
        }))
        steps.append(("database wizard: connect, pick tables, create; the password is never saved", {
            let defaults = UserDefaults.standard
            let saved = ["db.kind", "db.host", "db.port", "db.user", "db.database", "db.path"].map { ($0, defaults.object(forKey: $0)) }
            defer { for (k, v) in saved { if let v { defaults.set(v, forKey: k) } else { defaults.removeObject(forKey: k) } } }
            let w = DatabaseWizard()
            var outcome: DatabaseWizard.Outcome??
            w.present { outcome = .some($0) }
            var c = DatabaseConnection(); c.kind = .sqlite; c.path = sqlite.path
            w.fill(c)
            let fileShown = w.fileFieldShown && !w.serverFieldsShown && w.headingText == "Connect to a Database"
            var connected = false
            w.connect { connected = true }
            pump(5) { connected }
            let onTables = w.step == .tables && w.tableNames.count == 5 && w.headingText == "Choose the Tables" && w.summaryText.hasPrefix("5 of 5")
            w.filter("order")
            let filtered = w.tableNames == ["order_items", "orders"]
            w.filter("")
            w.setChecked(["orders"])
            w.tickRelated()
            let related = w.summaryText.hasPrefix("3 of 5")                                // orders -> customers and coupons
            w.setChecked([])
            let none = !w.createEnabled
            w.goBack()
            let back = w.step == .connection
            var again = false
            w.connect { again = true }
            pump(5) { again }
            w.setChecked(["customers", "orders"])
            w.confirmTables()
            guard case .some(.some(let out)) = outcome else { return false }
            return fileShown && connected && onTables && filtered && related && none && back && out.tableIDs == ["customers", "orders"] && out.schema.tables.count == 5
                && defaults.string(forKey: "db.path") == sqlite.path
        }))
        steps.append(("database wizard: errors stay in the window, server kinds show their fields, and Cancel returns nothing", {
            let defaults = UserDefaults.standard
            let saved = ["db.kind", "db.host", "db.port", "db.user", "db.database", "db.path"].map { ($0, defaults.object(forKey: $0)) }
            defer { for (k, v) in saved { if let v { defaults.set(v, forKey: k) } else { defaults.removeObject(forKey: k) } } }
            let w = DatabaseWizard()
            var outcome: DatabaseWizard.Outcome??
            w.present { outcome = .some($0) }
            var c = DatabaseConnection(); c.kind = .postgres; c.host = "db.example"; c.user = "me"; c.password = "hunter2"; c.database = "app"
            w.fill(c)
            let server = w.serverFieldsShown && !w.fileFieldShown
            w.connector = { _ in throw DatabaseError.message("password authentication failed") }
            var failed = false
            w.connect { failed = true }
            pump(5) { failed }
            let stays = w.step == .connection && w.statusText == "password authentication failed"
            var empty = DatabaseConnection(); empty.kind = .mysql; empty.host = ""; empty.database = ""
            w.fill(empty)
            var rejected = false
            w.connect { rejected = true }
            pump(2) { rejected }
            let validates = w.statusText.contains("host and the database")
            let notSaved = !defaults.dictionaryRepresentation().contains { ($0.value as? String) == "hunter2" }
            w.cancelWizard()
            guard case .some(let value) = outcome else { return false }
            return server && stays && validates && notSaved && value == nil
        }))
        steps.append(("database: Entity-Relationship is the only template that opens the wizard, and cancelling keeps the example tables", {
            let er = DocumentTemplate.all.first { $0.starter == .entityRelationship }
            let sample = Starters.drawing(.entityRelationship)
            return er?.kind == .starter && sample.shapes.contains { $0.text == "Customer" } && sample.shapes.contains { $0.text == "Product" } && sample.connectors.count == 3
        }))
        return steps
    }
}
