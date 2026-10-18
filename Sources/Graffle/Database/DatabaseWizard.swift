import AppKit

/// The wizard that fills an entity-relationship diagram from a real database: step 1 picks the kind of database and how to
/// connect, step 2 picks which tables to draw. Cancelling at any point leaves things as they were.
final class DatabaseWizard: NSObject, NSWindowDelegate, NSTableViewDataSource, NSTableViewDelegate, NSSearchFieldDelegate {
    struct Outcome { var schema: DBSchema; var tableIDs: [String] }
    enum Step { case connection, tables }

    static let maxTables = 60
    private static let keys = ["db.kind", "db.host", "db.port", "db.user", "db.database", "db.path"]

    let window: NSWindow
    private(set) var step = Step.connection
    private(set) var schema: DBSchema?
    private(set) var checked = Set<String>()
    private var connection = DatabaseConnection()
    private var result: Outcome?
    private var finish: ((Outcome?) -> Void)?
    /// How the structure is read; replaceable so tests don't need a server.
    var connector: (DatabaseConnection) throws -> DBSchema = { try DatabaseConnector.readSchema($0) }
    private var visibleTables: [DBTable] = []

    // Step 1
    private let kindPopup = NSPopUpButton()
    private let hostField = NSTextField(), portField = NSTextField(), userField = NSTextField(), databaseField = NSTextField(), pathField = NSTextField()
    private let passwordField = NSSecureTextField()
    private let chooseFile = NSButton(title: "Choose…", target: nil, action: nil)
    private var serverRows: [NSGridRow] = [], fileRows: [NSGridRow] = []
    private let status = NSTextField(wrappingLabelWithString: "")
    private let spinner = NSProgressIndicator()
    private let connectionPane = NSView()
    // Step 2
    private let tablesPane = NSView()
    private let table = NSTableView()
    private let search = NSSearchField()
    private let summary = NSTextField(labelWithString: "")
    // Buttons
    private let backButton = NSButton(title: "Back", target: nil, action: nil)
    private let cancelButton = NSButton(title: "Cancel", target: nil, action: nil)
    private let primaryButton = NSButton(title: "Connect", target: nil, action: nil)
    private let heading = NSTextField(labelWithString: "")
    private let hint = NSTextField(labelWithString: "")

    override init() {
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 640, height: 520), styleMask: [.titled, .closable], backing: .buffered, defer: false)
        super.init()
        window.title = "Entity-Relationship Diagram from a Database"
        window.isReleasedWhenClosed = false
        window.delegate = self
        loadSaved()
        build()
        refresh()
    }

    // MARK: Presenting

    /// Shows the wizard and waits for it. Nil means the user cancelled.
    static func run() -> Outcome? {
        let wizard = DatabaseWizard()
        wizard.window.center()
        var out: Outcome?
        wizard.finish = { out = $0; NSApp.stopModal() }
        NSApp.activate(ignoringOtherApps: true)
        NSApp.runModal(for: wizard.window)
        wizard.window.orderOut(nil)
        return out
    }

    /// For tests and non-modal use: calls `done` once, with the outcome or nil.
    func present(done: @escaping (Outcome?) -> Void) { finish = done; window.center(); window.makeKeyAndOrderFront(nil) }

    // MARK: Building

    private func label(_ text: String, size: CGFloat = 13, weight: NSFont.Weight = .regular, color: NSColor = .labelColor) -> NSTextField {
        let l = NSTextField(labelWithString: text)
        l.font = .systemFont(ofSize: size, weight: weight); l.textColor = color
        return l
    }

    private func build() {
        guard let content = window.contentView else { return }
        heading.font = .systemFont(ofSize: 20, weight: .semibold)
        hint.font = .systemFont(ofSize: 12); hint.textColor = .secondaryLabelColor
        for v in [heading, hint, connectionPane, tablesPane, backButton, cancelButton, primaryButton] as [NSView] { v.translatesAutoresizingMaskIntoConstraints = false; content.addSubview(v) }

        // Step 1: kind and connection.
        for k in DatabaseKind.allCases { kindPopup.addItem(withTitle: k.title) }
        kindPopup.target = self; kindPopup.action = #selector(kindChanged(_:))
        for f in [hostField, portField, userField, databaseField, pathField, passwordField] as [NSTextField] { f.translatesAutoresizingMaskIntoConstraints = false }
        portField.placeholderString = "default"
        passwordField.placeholderString = "not saved"
        pathField.isEditable = false
        pathField.lineBreakMode = .byTruncatingMiddle
        pathField.usesSingleLineMode = true
        pathField.cell?.wraps = false
        pathField.cell?.isScrollable = true
        pathField.widthAnchor.constraint(equalToConstant: 270).isActive = true
        pathField.placeholderString = "Choose a file…"
        chooseFile.target = self; chooseFile.action = #selector(pickFile(_:))
        let grid = NSGridView()
        grid.translatesAutoresizingMaskIntoConstraints = false
        grid.rowSpacing = 10; grid.columnSpacing = 12
        func add(_ title: String, _ field: NSView, into rows: inout [NSGridRow]) {
            let r = grid.addRow(with: [label(title, color: .secondaryLabelColor), field])
            r.cell(at: 0).xPlacement = .trailing
            rows.append(r)
        }
        let typeRow = grid.addRow(with: [label("Database", color: .secondaryLabelColor), kindPopup])
        typeRow.cell(at: 0).xPlacement = .trailing
        add("Host", hostField, into: &serverRows); add("Port", portField, into: &serverRows); add("User", userField, into: &serverRows)
        add("Password", passwordField, into: &serverRows); add("Database", databaseField, into: &serverRows)
        let fileBox = NSStackView(views: [pathField, chooseFile]); fileBox.spacing = 8
        add("File", fileBox, into: &fileRows)
        grid.column(at: 1).width = 360
        status.font = .systemFont(ofSize: 12); status.textColor = .systemRed; status.maximumNumberOfLines = 4
        status.translatesAutoresizingMaskIntoConstraints = false
        spinner.style = .spinning; spinner.controlSize = .small; spinner.isDisplayedWhenStopped = false
        spinner.translatesAutoresizingMaskIntoConstraints = false
        let note = NSTextField(wrappingLabelWithString: "Graffle only reads table and column names and foreign keys; it never changes the database. The password is used for this connection and not saved. PostgreSQL, MySQL and SQL Server connect through their command-line client (psql, mysql, sqlcmd), which must be installed.")
        note.font = .systemFont(ofSize: 11); note.textColor = .tertiaryLabelColor
        note.translatesAutoresizingMaskIntoConstraints = false
        for v in [grid, status, spinner, note] as [NSView] { connectionPane.addSubview(v) }
        NSLayoutConstraint.activate([
            grid.topAnchor.constraint(equalTo: connectionPane.topAnchor, constant: 6), grid.leadingAnchor.constraint(equalTo: connectionPane.leadingAnchor),
            status.topAnchor.constraint(equalTo: grid.bottomAnchor, constant: 14), status.leadingAnchor.constraint(equalTo: connectionPane.leadingAnchor),
            status.trailingAnchor.constraint(equalTo: connectionPane.trailingAnchor),
            spinner.leadingAnchor.constraint(equalTo: grid.leadingAnchor), spinner.topAnchor.constraint(equalTo: grid.bottomAnchor, constant: 14),
            note.leadingAnchor.constraint(equalTo: connectionPane.leadingAnchor), note.trailingAnchor.constraint(equalTo: connectionPane.trailingAnchor),
            note.bottomAnchor.constraint(equalTo: connectionPane.bottomAnchor),
        ])

        // Step 2: the tables.
        search.placeholderString = "Filter tables"
        search.delegate = self
        search.translatesAutoresizingMaskIntoConstraints = false
        let check = NSTableColumn(identifier: .init("check")); check.width = 28; check.title = ""
        let box = NSButtonCell(); box.setButtonType(.switch); box.title = ""; check.dataCell = box
        let name = NSTableColumn(identifier: .init("name")); name.title = "Table"; name.width = 300
        let cols = NSTableColumn(identifier: .init("cols")); cols.title = "Columns"; cols.width = 80
        let keys = NSTableColumn(identifier: .init("fks")); keys.title = "Foreign keys"; keys.width = 100
        for c in [check, name, cols, keys] { table.addTableColumn(c) }
        table.dataSource = self; table.delegate = self
        table.rowHeight = 22
        table.allowsMultipleSelection = true
        let scroll = NSScrollView()
        scroll.documentView = table; scroll.hasVerticalScroller = true; scroll.borderType = .bezelBorder
        scroll.translatesAutoresizingMaskIntoConstraints = false
        let all = NSButton(title: "Select All", target: self, action: #selector(selectAll(_:))), none = NSButton(title: "Select None", target: self, action: #selector(selectNone(_:)))
        let related = NSButton(title: "Add Related", target: self, action: #selector(addRelated(_:)))
        related.toolTip = "Also tick the tables that the ticked ones refer to"
        summary.font = .systemFont(ofSize: 12); summary.textColor = .secondaryLabelColor
        for v in [search, scroll, all, none, related, summary] as [NSView] { v.translatesAutoresizingMaskIntoConstraints = false; tablesPane.addSubview(v) }
        NSLayoutConstraint.activate([
            search.topAnchor.constraint(equalTo: tablesPane.topAnchor), search.leadingAnchor.constraint(equalTo: tablesPane.leadingAnchor), search.widthAnchor.constraint(equalToConstant: 220),
            all.leadingAnchor.constraint(equalTo: search.trailingAnchor, constant: 12), all.centerYAnchor.constraint(equalTo: search.centerYAnchor),
            none.leadingAnchor.constraint(equalTo: all.trailingAnchor, constant: 6), none.centerYAnchor.constraint(equalTo: search.centerYAnchor),
            related.leadingAnchor.constraint(equalTo: none.trailingAnchor, constant: 6), related.centerYAnchor.constraint(equalTo: search.centerYAnchor),
            scroll.topAnchor.constraint(equalTo: search.bottomAnchor, constant: 10), scroll.leadingAnchor.constraint(equalTo: tablesPane.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: tablesPane.trailingAnchor), scroll.bottomAnchor.constraint(equalTo: summary.topAnchor, constant: -8),
            summary.leadingAnchor.constraint(equalTo: tablesPane.leadingAnchor), summary.bottomAnchor.constraint(equalTo: tablesPane.bottomAnchor),
        ])

        for b in [backButton, cancelButton, primaryButton] { b.target = self }
        backButton.action = #selector(back(_:)); cancelButton.action = #selector(cancel(_:)); primaryButton.action = #selector(primary(_:))
        cancelButton.keyEquivalent = "\u{1b}"; primaryButton.keyEquivalent = "\r"
        NSLayoutConstraint.activate([
            heading.topAnchor.constraint(equalTo: content.topAnchor, constant: 22), heading.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 28),
            hint.topAnchor.constraint(equalTo: heading.bottomAnchor, constant: 4), hint.leadingAnchor.constraint(equalTo: heading.leadingAnchor),
            hint.trailingAnchor.constraint(lessThanOrEqualTo: content.trailingAnchor, constant: -28),
            connectionPane.topAnchor.constraint(equalTo: hint.bottomAnchor, constant: 18), connectionPane.leadingAnchor.constraint(equalTo: heading.leadingAnchor),
            connectionPane.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -28), connectionPane.bottomAnchor.constraint(equalTo: primaryButton.topAnchor, constant: -16),
            tablesPane.topAnchor.constraint(equalTo: connectionPane.topAnchor), tablesPane.leadingAnchor.constraint(equalTo: connectionPane.leadingAnchor),
            tablesPane.trailingAnchor.constraint(equalTo: connectionPane.trailingAnchor), tablesPane.bottomAnchor.constraint(equalTo: connectionPane.bottomAnchor),
            primaryButton.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -22), primaryButton.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -18),
            primaryButton.widthAnchor.constraint(greaterThanOrEqualToConstant: 96),
            cancelButton.trailingAnchor.constraint(equalTo: primaryButton.leadingAnchor, constant: -10), cancelButton.centerYAnchor.constraint(equalTo: primaryButton.centerYAnchor),
            cancelButton.widthAnchor.constraint(greaterThanOrEqualToConstant: 80),
            backButton.trailingAnchor.constraint(equalTo: cancelButton.leadingAnchor, constant: -10), backButton.centerYAnchor.constraint(equalTo: primaryButton.centerYAnchor),
            backButton.widthAnchor.constraint(greaterThanOrEqualToConstant: 80),
        ])
        window.defaultButtonCell = primaryButton.cell as? NSButtonCell
    }

    // MARK: State

    private func loadSaved() {
        let d = UserDefaults.standard
        if let raw = d.string(forKey: "db.kind"), let k = DatabaseKind(rawValue: raw) { connection.kind = k }
        connection.host = d.string(forKey: "db.host") ?? "localhost"
        connection.port = d.string(forKey: "db.port") ?? ""
        connection.user = d.string(forKey: "db.user") ?? ""
        connection.database = d.string(forKey: "db.database") ?? ""
        connection.path = d.string(forKey: "db.path") ?? ""
        if !FileManager.default.fileExists(atPath: connection.path) { connection.path = "" }
        if connection.user.isEmpty { connection.user = connection.kind.defaultUser }
    }

    private func saveFields() {
        let d = UserDefaults.standard
        d.set(connection.kind.rawValue, forKey: "db.kind"); d.set(connection.host, forKey: "db.host"); d.set(connection.port, forKey: "db.port")
        d.set(connection.user, forKey: "db.user"); d.set(connection.database, forKey: "db.database"); d.set(connection.path, forKey: "db.path")
    }

    private func readFields() {
        connection.kind = DatabaseKind.allCases[max(0, kindPopup.indexOfSelectedItem)]
        connection.host = hostField.stringValue.trimmingCharacters(in: .whitespaces)
        connection.port = portField.stringValue.trimmingCharacters(in: .whitespaces)
        connection.user = userField.stringValue.trimmingCharacters(in: .whitespaces)
        connection.password = passwordField.stringValue
        connection.database = databaseField.stringValue.trimmingCharacters(in: .whitespaces)
        connection.path = pathField.stringValue
    }

    private func refresh() {
        let onConnection = step == .connection
        connectionPane.isHidden = !onConnection
        tablesPane.isHidden = onConnection
        backButton.isHidden = onConnection
        if onConnection {
            heading.stringValue = "Connect to a Database"
            hint.stringValue = "Step 1 of 2 — choose the kind of database and how to reach it"
            primaryButton.title = "Connect"
            kindPopup.selectItem(at: DatabaseKind.allCases.firstIndex(of: connection.kind) ?? 0)
            hostField.stringValue = connection.host; portField.stringValue = connection.port; userField.stringValue = connection.user
            databaseField.stringValue = connection.database; pathField.stringValue = connection.path
            let file = connection.kind.isFile
            serverRows.forEach { $0.isHidden = file }
            fileRows.forEach { $0.isHidden = !file }
            portField.placeholderString = connection.kind.defaultPort.isEmpty ? "default" : connection.kind.defaultPort
        } else {
            heading.stringValue = "Choose the Tables"
            hint.stringValue = "Step 2 of 2 — tick what goes into the diagram (up to \(Self.maxTables))"
            primaryButton.title = "Create Diagram"
            applyFilter()
            updateSummary()
        }
    }

    private func updateSummary() {
        let n = checked.count, total = schema?.tables.count ?? 0
        summary.stringValue = "\(n) of \(total) tables ticked" + (n > Self.maxTables ? " — too many: untick some (the limit is \(Self.maxTables))" : "")
        primaryButton.isEnabled = step == .connection || (n > 0 && n <= Self.maxTables)
    }

    private func applyFilter() {
        let q = search.stringValue.trimmingCharacters(in: .whitespaces).lowercased()
        visibleTables = (schema?.tables ?? []).filter { q.isEmpty || $0.name.lowercased().contains(q) }
        table.reloadData()
    }

    // MARK: Actions

    @objc private func kindChanged(_ s: Any?) {
        let old = connection.kind
        readFields()
        if connection.user.isEmpty || connection.user == old.defaultUser { connection.user = connection.kind.defaultUser }
        status.stringValue = ""
        refresh()
    }

    @objc private func pickFile(_ s: Any?) {
        let panel = NSOpenPanel()
        panel.message = connection.kind == .sqlite ? "Choose a SQLite database file" : "Choose a SQL script"
        panel.canChooseDirectories = false
        if panel.runModal() == .OK, let url = panel.url { pathField.stringValue = url.path; connection.path = url.path }
    }

    @objc private func primary(_ s: Any?) { step == .connection ? connect(completion: nil) : create() }

    /// Reads the database in the background, then moves to the table list.
    func connect(completion: (() -> Void)?) {
        readFields()
        if connection.kind.isFile && connection.path.isEmpty { status.stringValue = "Choose a file first."; completion?(); return }
        if !connection.kind.isFile && (connection.host.isEmpty || connection.database.isEmpty) { status.stringValue = "Enter at least the host and the database name."; completion?(); return }
        status.stringValue = ""
        primaryButton.isEnabled = false; spinner.startAnimation(nil)
        let c = connection, read = connector
        DispatchQueue.global(qos: .userInitiated).async {
            let outcome = Result { try read(c) }
            // Back on the main run loop (not the main queue, which a nested run loop in tests cannot service).
            RunLoop.main.perform(inModes: [.common]) { [self] in
                spinner.stopAnimation(nil); primaryButton.isEnabled = true
                switch outcome {
                case .success(let s):
                    saveFields()
                    schema = s
                    // Start with the first tables ticked, so Create works straight away.
                    checked = Set(s.tables.prefix(min(12, Self.maxTables)).map(\.id))
                    search.stringValue = ""
                    step = .tables
                    refresh()
                case .failure(let e):
                    status.stringValue = e.localizedDescription
                }
                completion?()
            }
            CFRunLoopWakeUp(CFRunLoopGetMain())
        }
    }

    private func create() {
        guard let schema, !checked.isEmpty, checked.count <= Self.maxTables else { return }
        let ids = schema.tables.map(\.id).filter { checked.contains($0) }
        result = Outcome(schema: schema, tableIDs: ids)
        close()
    }

    @objc private func back(_ s: Any?) { step = .connection; refresh() }
    @objc private func cancel(_ s: Any?) { result = nil; close() }
    @objc private func selectAll(_ s: Any?) { checked.formUnion(visibleTables.map(\.id)); table.reloadData(); updateSummary() }
    @objc private func selectNone(_ s: Any?) { checked.subtract(visibleTables.map(\.id)); table.reloadData(); updateSummary() }
    @objc private func addRelated(_ s: Any?) {
        guard let schema else { return }
        var grew = true
        while grew {
            grew = false
            for t in schema.tables where checked.contains(t.id) { for f in t.foreignKeys where schema.table(f.refTable) != nil && checked.insert(f.refTable).inserted { grew = true } }
        }
        table.reloadData(); updateSummary()
    }
    func controlTextDidChange(_ obj: Notification) { if (obj.object as? NSSearchField) === search { applyFilter() } }

    private func close() {
        let done = finish; finish = nil
        let out = result
        if window.isVisible || NSApp.modalWindow === window { window.orderOut(nil) }
        done?(out)
    }

    func windowWillClose(_ notification: Notification) {
        if finish != nil { result = nil; let done = finish; finish = nil; done?(nil) }
    }

    // MARK: Table

    func numberOfRows(in tableView: NSTableView) -> Int { visibleTables.count }

    func tableView(_ tableView: NSTableView, objectValueFor tableColumn: NSTableColumn?, row: Int) -> Any? {
        let t = visibleTables[row]
        switch tableColumn?.identifier.rawValue {
        case "check": return checked.contains(t.id) ? 1 : 0
        case "name": return t.name
        case "cols": return t.columns.count
        default: return t.foreignKeys.count
        }
    }

    func tableView(_ tableView: NSTableView, setObjectValue object: Any?, for tableColumn: NSTableColumn?, row: Int) {
        guard tableColumn?.identifier.rawValue == "check" else { return }
        let id = visibleTables[row].id
        if (object as? Int ?? 0) == 1 { checked.insert(id) } else { checked.remove(id) }
        updateSummary()
    }

    // MARK: For tests

    var tableNames: [String] { visibleTables.map(\.name) }
    func fill(_ c: DatabaseConnection) {
        connection = c
        refresh()
        passwordField.stringValue = c.password
    }
    func setChecked(_ ids: Set<String>) { checked = ids; table.reloadData(); updateSummary() }
    func filter(_ text: String) { search.stringValue = text; applyFilter() }
    func confirmTables() { create() }
    func goBack() { back(nil) }
    func cancelWizard() { cancel(nil) }
    func tickRelated() { addRelated(nil) }
    var statusText: String { status.stringValue }
    var summaryText: String { summary.stringValue }
    var createEnabled: Bool { primaryButton.isEnabled }
    var serverFieldsShown: Bool { !(serverRows.first?.isHidden ?? true) }
    var fileFieldShown: Bool { !(fileRows.first?.isHidden ?? true) }
    var headingText: String { heading.stringValue }
    var passwordIsSaved: Bool { UserDefaults.standard.dictionaryRepresentation().values.contains { ($0 as? String) == connection.password && !connection.password.isEmpty } }
}
