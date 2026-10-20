import AppKit

/// The left sidebar: search, the page, and the layers as a tree whose children are the objects on each layer.
final class SidebarView: NSView, NSOutlineViewDataSource, NSOutlineViewDelegate, NSTextFieldDelegate {
    final class Node: NSObject {
        enum Kind: Equatable { case layer(UUID), shape(UUID), connector(UUID) }
        let kind: Kind
        var children: [Node] = []
        var layerID: UUID                        // the layer this node is on (or is)
        init(_ kind: Kind, layer: UUID) { self.kind = kind; self.layerID = layer }
        var objectID: UUID? { switch kind { case .shape(let i), .connector(let i): return i; default: return nil } }
        var isLayer: Bool { if case .layer = kind { return true }; return false }
    }

    private static let dragType = NSPasteboard.PasteboardType("mx.graffle.sidebar-row")

    weak var canvas: CanvasView? { didSet { reload() } }
    private let outline = SidebarOutline()
    private let searchField = NSTextField()
    private let footer = NSTextField(labelWithString: "")
    private var roots: [Node] = []
    private var signature = ""
    private var expanded = Set<UUID>()
    private var knownLayers = Set<UUID>()
    private var updating = false
    private var query = ""

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        translatesAutoresizingMaskIntoConstraints = false
        build()
    }
    required init?(coder: NSCoder) { fatalError("not used") }

    // MARK: Building

    private func header(_ title: String, add: Selector?, addLabel: String, addEnabled: Bool = true, tip: String? = nil) -> NSView {
        let label = NSTextField(labelWithString: title)
        label.font = .systemFont(ofSize: 11.5, weight: .semibold)
        label.textColor = Tok.textSecondary
        let plus = IconButton(symbol: "plus", label: addLabel, tip: tip ?? addLabel, size: 22, pointSize: 11)
        plus.target = self; plus.action = add
        plus.isEnabled = addEnabled
        let row = NSStackView(views: [label, NSView(), plus])
        row.orientation = .horizontal
        row.edgeInsets = NSEdgeInsets(top: 10, left: 16, bottom: 4, right: 10)
        row.translatesAutoresizingMaskIntoConstraints = false
        return row
    }

    private func build() {
        setAccessibilityLabel("Pages and layers")
        // Search
        let searchBox = SurfaceView(frame: .zero)
        searchBox.fill = Tok.hoverFill; searchBox.outline = nil; searchBox.radius = Tok.Radius.field
        searchBox.translatesAutoresizingMaskIntoConstraints = false
        let glass = NSImageView(image: NSImage(systemSymbolName: "magnifyingglass", accessibilityDescription: nil)?.withSymbolConfiguration(.init(pointSize: 12, weight: .regular)) ?? NSImage())
        glass.contentTintColor = Tok.textSecondary
        glass.translatesAutoresizingMaskIntoConstraints = false
        searchField.placeholderString = "Search"
        searchField.isBordered = false; searchField.drawsBackground = false; searchField.focusRingType = .none
        searchField.font = Tok.Font.body(); searchField.textColor = Tok.textPrimary
        searchField.delegate = self
        searchField.setAccessibilityLabel("Search layers")
        searchField.translatesAutoresizingMaskIntoConstraints = false
        [glass, searchField].forEach(searchBox.addSubview)
        NSLayoutConstraint.activate([
            glass.leadingAnchor.constraint(equalTo: searchBox.leadingAnchor, constant: 9), glass.centerYAnchor.constraint(equalTo: searchBox.centerYAnchor),
            searchField.leadingAnchor.constraint(equalTo: glass.trailingAnchor, constant: 6), searchField.trailingAnchor.constraint(equalTo: searchBox.trailingAnchor, constant: -8),
            searchField.centerYAnchor.constraint(equalTo: searchBox.centerYAnchor),
            searchBox.heightAnchor.constraint(equalToConstant: 30),
        ])
        let searchRow = NSView()
        searchRow.translatesAutoresizingMaskIntoConstraints = false
        searchRow.addSubview(searchBox)
        NSLayoutConstraint.activate([
            searchBox.leadingAnchor.constraint(equalTo: searchRow.leadingAnchor, constant: 12), searchBox.trailingAnchor.constraint(equalTo: searchRow.trailingAnchor, constant: -12),
            searchBox.topAnchor.constraint(equalTo: searchRow.topAnchor, constant: 12), searchBox.bottomAnchor.constraint(equalTo: searchRow.bottomAnchor, constant: -6),
        ])

        // The one page (a document has a single canvas; more pages are not supported yet).
        let pageRow = SurfaceView(frame: .zero)
        pageRow.fill = Tok.hoverFill; pageRow.outline = nil; pageRow.radius = 7
        pageRow.translatesAutoresizingMaskIntoConstraints = false
        let pageIcon = NSImageView(image: NSImage(systemSymbolName: "doc", accessibilityDescription: nil)?.withSymbolConfiguration(.init(pointSize: 13, weight: .regular)) ?? NSImage())
        pageIcon.contentTintColor = Tok.accent
        pageIcon.translatesAutoresizingMaskIntoConstraints = false
        let pageName = NSTextField(labelWithString: "Page 1")
        pageName.font = .systemFont(ofSize: 13, weight: .medium); pageName.textColor = Tok.textPrimary
        pageName.translatesAutoresizingMaskIntoConstraints = false
        [pageIcon, pageName].forEach(pageRow.addSubview)
        NSLayoutConstraint.activate([
            pageRow.heightAnchor.constraint(equalToConstant: 30),
            pageIcon.leadingAnchor.constraint(equalTo: pageRow.leadingAnchor, constant: 8), pageIcon.centerYAnchor.constraint(equalTo: pageRow.centerYAnchor),
            pageName.leadingAnchor.constraint(equalTo: pageIcon.trailingAnchor, constant: 9), pageName.centerYAnchor.constraint(equalTo: pageRow.centerYAnchor),
        ])
        let pageHolder = NSView()
        pageHolder.translatesAutoresizingMaskIntoConstraints = false
        pageHolder.addSubview(pageRow)
        NSLayoutConstraint.activate([
            pageRow.leadingAnchor.constraint(equalTo: pageHolder.leadingAnchor, constant: 8), pageRow.trailingAnchor.constraint(equalTo: pageHolder.trailingAnchor, constant: -8),
            pageRow.topAnchor.constraint(equalTo: pageHolder.topAnchor, constant: 2), pageRow.bottomAnchor.constraint(equalTo: pageHolder.bottomAnchor, constant: -8),
        ])

        // The tree
        let column = NSTableColumn(identifier: .init("main"))
        outline.addTableColumn(column)
        outline.outlineTableColumn = column
        outline.headerView = nil
        outline.rowHeight = 30
        outline.intercellSpacing = NSSize(width: 0, height: 1)
        outline.indentationPerLevel = 14
        outline.allowsMultipleSelection = true
        outline.allowsEmptySelection = true
        outline.backgroundColor = .clear
        outline.style = .plain
        outline.selectionHighlightStyle = .regular
        outline.dataSource = self; outline.delegate = self
        outline.registerForDraggedTypes([Self.dragType])
        outline.setDraggingSourceOperationMask(.move, forLocal: true)
        outline.target = self; outline.doubleAction = #selector(rename(_:))
        outline.setAccessibilityLabel("Layers")
        let menu = NSMenu()
        menu.delegate = self
        outline.menu = menu
        let scroll = NSScrollView()
        scroll.documentView = outline
        scroll.hasVerticalScroller = true; scroll.scrollerStyle = .overlay
        scroll.drawsBackground = false; scroll.borderType = .noBorder
        scroll.translatesAutoresizingMaskIntoConstraints = false

        // Footer chip
        footer.font = .systemFont(ofSize: 11.5); footer.textColor = Tok.textSecondary
        footer.translatesAutoresizingMaskIntoConstraints = false
        let footerHolder = NSView()
        footerHolder.translatesAutoresizingMaskIntoConstraints = false
        footerHolder.addSubview(footer)
        NSLayoutConstraint.activate([footer.leadingAnchor.constraint(equalTo: footerHolder.leadingAnchor, constant: 16), footer.centerYAnchor.constraint(equalTo: footerHolder.centerYAnchor),
                                     footerHolder.heightAnchor.constraint(equalToConstant: 32)])

        let pagesHeader = header("Pages", add: #selector(addPage(_:)), addLabel: "Add page", addEnabled: false, tip: "Add page (a document has one page for now)")
        let layersHeader = header("Layers", add: #selector(addLayer(_:)), addLabel: "Add layer")
        let stack = NSStackView(views: [searchRow, pagesHeader, pageHolder, layersHeader, scroll, footerHolder])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 0
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor), stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor), stack.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
        for v in [searchRow, pagesHeader, pageHolder, layersHeader, scroll, footerHolder] as [NSView] {
            v.leadingAnchor.constraint(equalTo: stack.leadingAnchor).isActive = true; v.trailingAnchor.constraint(equalTo: stack.trailingAnchor).isActive = true
        }
        scroll.setContentHuggingPriority(.defaultLow, for: .vertical)
    }

    @objc private func addLayer(_ s: Any?) { canvas?.addLayer() }
    @objc private func addPage(_ s: Any?) {}

    // MARK: Model

    private func tree() -> [Node] {
        guard let d = canvas?.drawing else { return [] }
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        var out: [Node] = []
        for layer in d.layers.reversed() {                                       // front first
            let node = Node(.layer(layer.id), layer: layer.id)
            for s in d.shapes.reversed() where s.layer == layer.id { node.children.append(Node(.shape(s.id), layer: layer.id)) }
            for c in d.connectors.reversed() where c.layer == layer.id { node.children.append(Node(.connector(c.id), layer: layer.id)) }
            if !q.isEmpty {
                let layerMatches = layer.name.lowercased().contains(q)
                node.children = node.children.filter { layerMatches || name(of: $0).lowercased().contains(q) }
                if !layerMatches && node.children.isEmpty { continue }
            }
            out.append(node)
        }
        return out
    }

    private func name(of node: Node) -> String {
        guard let d = canvas?.drawing else { return "" }
        switch node.kind {
        case .layer(let id): return d.layer(id)?.name ?? ""
        case .shape(let id): return d.shapes.first { $0.id == id }?.displayName ?? ""
        case .connector(let id): return d.connectors.first { $0.id == id }?.displayName ?? ""
        }
    }

    private func currentSignature() -> String {
        guard let d = canvas?.drawing else { return "" }
        var parts: [String] = [query]
        for l in d.layers { parts.append("L\(l.id)\(l.name)\(l.visible)\(l.locked)") }
        for s in d.shapes { parts.append("S\(s.id)\(s.layer)\(s.displayName)\(s.kind.rawValue)\(s.locked)") }
        for c in d.connectors { parts.append("C\(c.id)\(c.layer)\(c.displayName)\(c.locked)") }
        return parts.joined(separator: "|")
    }

    /// Rebuilds the tree when the drawing's structure changed, and keeps the selection in step.
    func reload() {
        let sig = currentSignature()
        if sig != signature {
            signature = sig
            roots = tree()
            if let d = canvas?.drawing {                                       // new layers start open
                for l in d.layers where !knownLayers.contains(l.id) { expanded.insert(l.id); knownLayers.insert(l.id) }
            }
            updating = true
            outline.reloadData()
            for r in roots { if case .layer(let id) = r.kind, expanded.contains(id) { outline.expandItem(r) } else { outline.collapseItem(r) } }
            updating = false
        }
        syncSelection()
        updateFooter()
        for row in 0..<outline.numberOfRows { (outline.rowView(atRow: row, makeIfNecessary: false)?.subviews.first as? SidebarCell)?.refreshActive() }
    }

    private func updateFooter() {
        guard let d = canvas?.drawing else { footer.stringValue = ""; return }
        let n = d.shapes.count + d.connectors.count
        footer.stringValue = "\(n) object\(n == 1 ? "" : "s") · \(canvas?.selection.count ?? 0) selected"
    }

    /// Selects, in the list, the rows of the objects selected on the canvas.
    func syncSelection() {
        guard let canvas else { return }
        var rows = IndexSet()
        for row in 0..<outline.numberOfRows {
            if let n = outline.item(atRow: row) as? Node, let id = n.objectID, canvas.selection.contains(id) { rows.insert(row) }
        }
        if rows != outline.selectedRowIndexes {
            updating = true
            outline.selectRowIndexes(rows, byExtendingSelection: false)
            updating = false
        }
        updateFooter()
    }

    // MARK: Data source

    func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int { (item as? Node)?.children.count ?? roots.count }
    func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any { (item as? Node)?.children[index] ?? roots[index] }
    func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool { (item as? Node)?.isLayer == true }
    func outlineViewItemDidExpand(_ notification: Notification) { if let n = notification.userInfo?["NSObject"] as? Node, case .layer(let id) = n.kind, !updating { expanded.insert(id) } }
    func outlineViewItemDidCollapse(_ notification: Notification) { if let n = notification.userInfo?["NSObject"] as? Node, case .layer(let id) = n.kind, !updating { expanded.remove(id) } }

    func outlineView(_ outlineView: NSOutlineView, rowViewForItem item: Any) -> NSTableRowView? { SidebarRow() }

    func outlineView(_ outlineView: NSOutlineView, viewFor tableColumn: NSTableColumn?, item: Any) -> NSView? {
        guard let node = item as? Node, let d = canvas?.drawing else { return nil }
        let cell = SidebarCell()
        cell.owner = self
        cell.node = node
        switch node.kind {
        case .layer(let id):
            guard let l = d.layer(id) else { return nil }
            cell.configure(symbol: "square.3.layers.3d", title: l.name, bold: true, visible: l.visible, locked: l.locked, showFlags: true)
        case .shape(let id):
            guard let s = d.shapes.first(where: { $0.id == id }) else { return nil }
            cell.configure(symbol: Self.symbol(for: s.kind), title: s.displayName, bold: false, visible: true, locked: s.locked, showFlags: s.locked)
        case .connector(let id):
            guard let c = d.connectors.first(where: { $0.id == id }) else { return nil }
            cell.configure(symbol: "arrow.up.right", title: c.displayName, bold: false, visible: true, locked: c.locked, showFlags: c.locked)
        }
        return cell
    }

    static func symbol(for kind: ShapeKind) -> String {
        switch kind {
        case .rectangle: return "rectangle"
        case .rounded: return "app"
        case .ellipse: return "circle"
        case .diamond: return "diamond"
        case .triangle: return "triangle"
        case .text: return "textformat"
        case .path: return "scribble"
        }
    }

    // MARK: Selection

    func outlineViewSelectionDidChange(_ notification: Notification) {
        guard !updating, let canvas else { return }
        var ids = Set<UUID>()
        var layerPicked: UUID?
        for row in outline.selectedRowIndexes {
            guard let n = outline.item(atRow: row) as? Node else { continue }
            if let id = n.objectID { ids.insert(id) } else { layerPicked = n.layerID }
        }
        if ids.isEmpty, let layerPicked { canvas.selection = []; canvas.setActiveLayer(layerPicked); return }
        canvas.selection = ids
    }

    func outlineView(_ outlineView: NSOutlineView, shouldSelectItem item: Any) -> Bool { true }

    // MARK: Editing

    @objc private func rename(_ s: Any?) {
        let row = outline.clickedRow
        guard row >= 0, let cell = outline.view(atColumn: 0, row: row, makeIfNecessary: false) as? SidebarCell else { return }
        cell.beginRename()
    }

    func commitRename(_ node: Node, to name: String) {
        switch node.kind {
        case .layer(let id): canvas?.renameLayer(id, to: name)
        case .shape(let id): canvas?.renameObject(id, to: name)
        case .connector: break
        }
        signature = ""; reload()
    }

    func toggle(_ node: Node, visible: Bool? = nil, locked: Bool? = nil) {
        switch node.kind {
        case .layer(let id): canvas?.setLayer(id, visible: visible, locked: locked)
        case .shape(let id), .connector(let id): if let locked { canvas?.setObject(id, locked: locked) }
        }
    }

    func controlTextDidChange(_ obj: Notification) {
        if (obj.object as? NSTextField) === searchField { query = searchField.stringValue; signature = ""; reload() }
    }

    // MARK: Drag to reorder

    func outlineView(_ outlineView: NSOutlineView, pasteboardWriterForItem item: Any) -> NSPasteboardWriting? {
        guard let n = item as? Node else { return nil }
        let tag: String
        switch n.kind { case .layer(let id): tag = "L:\(id)"; case .shape(let id): tag = "S:\(id)"; case .connector: return nil }
        let pb = NSPasteboardItem()
        pb.setString(tag, forType: Self.dragType)
        return pb
    }

    private func dragged(_ info: NSDraggingInfo) -> (isLayer: Bool, id: UUID)? {
        guard let s = info.draggingPasteboard.string(forType: Self.dragType), s.count > 2, let id = UUID(uuidString: String(s.dropFirst(2))) else { return nil }
        return (s.hasPrefix("L:"), id)
    }

    func outlineView(_ outlineView: NSOutlineView, validateDrop info: NSDraggingInfo, proposedItem item: Any?, proposedChildIndex index: Int) -> NSDragOperation {
        guard query.isEmpty, let drag = dragged(info) else { return [] }
        let node = item as? Node
        if drag.isLayer {
            if node == nil { return .move }
            let top = node!.isLayer ? node! : roots.first { $0.layerID == node!.layerID }
            guard let top, let i = roots.firstIndex(of: top) else { return [] }
            outlineView.setDropItem(nil, dropChildIndex: i)
            return .move
        }
        // A shape: drop between the objects of a layer.
        if let n = node, n.isLayer { return index == NSOutlineViewDropOnItemIndex ? { outlineView.setDropItem(n, dropChildIndex: 0); return .move }() : .move }
        if let n = node, let parent = roots.first(where: { $0.layerID == n.layerID }), let i = parent.children.firstIndex(of: n) {
            outlineView.setDropItem(parent, dropChildIndex: i)
            return .move
        }
        return []
    }

    func outlineView(_ outlineView: NSOutlineView, acceptDrop info: NSDraggingInfo, item: Any?, childIndex index: Int) -> Bool {
        guard let canvas, let drag = dragged(info) else { return false }
        if drag.isLayer {
            var order = roots.map(\.layerID)                                    // front first
            guard let from = order.firstIndex(of: drag.id) else { return false }
            order.remove(at: from)
            var to = index < 0 ? order.count : index
            if from < to { to -= 1 }
            to = max(0, min(to, order.count))
            canvas.moveLayer(drag.id, toIndex: canvas.drawing.layers.count - 1 - to)
            return true
        }
        guard let parent = item as? Node else { return false }
        let siblings = parent.children.filter { if case .shape = $0.kind { return true }; return false }
        let at = index < 0 ? siblings.count : min(index, siblings.count)
        let others = siblings.filter { $0.objectID != drag.id }
        let pos = min(at - (siblings.prefix(at).contains { $0.objectID == drag.id } ? 1 : 0), others.count)
        if pos < others.count, let target = others[pos].objectID {
            canvas.moveObject(drag.id, layer: parent.layerID, relativeTo: target, above: true)       // above what was at that row
        } else if let last = others.last?.objectID {
            canvas.moveObject(drag.id, layer: parent.layerID, relativeTo: last, above: false)        // behind the last one
        } else {
            canvas.moveObject(drag.id, layer: parent.layerID, relativeTo: nil, above: true)
        }
        return true
    }

    // MARK: For tests

    var rowCount: Int { outline.numberOfRows }
    func rowNames() -> [String] { (0..<outline.numberOfRows).compactMap { (outline.item(atRow: $0) as? Node).map(name(of:)) } }
    func selectRows(_ rows: IndexSet) { outline.selectRowIndexes(rows, byExtendingSelection: false) }
    var selectedRows: IndexSet { outline.selectedRowIndexes }
    func node(atRow row: Int) -> Node? { outline.item(atRow: row) as? Node }
    func setSearch(_ text: String) { searchField.stringValue = text; query = text; signature = ""; reload() }
    var footerText: String { footer.stringValue }
    func acceptTestDrop(layer id: UUID, toDisplayIndex: Int) -> Bool {
        guard let canvas else { return false }
        var order = roots.map(\.layerID)
        guard let from = order.firstIndex(of: id) else { return false }
        order.remove(at: from)
        var to = toDisplayIndex
        if from < to { to -= 1 }
        canvas.moveLayer(id, toIndex: canvas.drawing.layers.count - 1 - max(0, min(to, order.count)))
        return true
    }
    func cell(atRow row: Int) -> SidebarCell? { outline.view(atColumn: 0, row: row, makeIfNecessary: true) as? SidebarCell }
    func isActiveLayer(_ id: UUID) -> Bool { canvas?.activeLayerID == id }
    var activeLayerIDForCell: UUID? { canvas?.activeLayerID }
}

extension SidebarView: NSMenuDelegate {
    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let row = outline.clickedRow
        guard row >= 0, let node = outline.item(atRow: row) as? Node else { return }
        if node.isLayer {
            let rename = NSMenuItem(title: "Rename", action: #selector(menuRename), keyEquivalent: ""); rename.target = self
            let del = NSMenuItem(title: "Delete Layer", action: #selector(menuDelete), keyEquivalent: ""); del.target = self
            del.isEnabled = (canvas?.drawing.layers.count ?? 0) > 1
            menu.addItem(rename); menu.addItem(del)
        } else if case .shape = node.kind {
            let rename = NSMenuItem(title: "Rename", action: #selector(menuRename), keyEquivalent: ""); rename.target = self
            menu.addItem(rename)
        }
    }
    @objc private func menuRename() { rename(nil) }
    @objc private func menuDelete() {
        let row = outline.clickedRow
        if row >= 0, let n = outline.item(atRow: row) as? Node, case .layer(let id) = n.kind { canvas?.deleteLayer(id) }
    }
}

/// An outline view that doesn't draw its own focus ring or alternate rows.
final class SidebarOutline: NSOutlineView {
    override var focusRingType: NSFocusRingType { get { .none } set {} }
    override func drawBackground(inClipRect clipRect: NSRect) {}
}

/// A row that draws the design's selection: a rounded accent bar.
final class SidebarRow: NSTableRowView {
    override var isEmphasized: Bool { get { true } set {} }
    override func drawSelection(in dirtyRect: NSRect) {
        guard isSelected else { return }
        Tok.selectionRow.setFill()
        NSBezierPath(roundedRect: bounds.insetBy(dx: 4, dy: 0), xRadius: 7, yRadius: 7).fill()
    }
    override var interiorBackgroundStyle: NSView.BackgroundStyle { isSelected ? .emphasized : .normal }
    override func drawBackground(in dirtyRect: NSRect) {}
}

/// One row of the tree.
final class SidebarCell: NSTableCellView {
    weak var owner: SidebarView?
    var node: SidebarView.Node?
    private let icon = NSImageView()
    let nameField = NSTextField()
    private let eye = IconButton(symbol: "eye", label: "Hide", size: 24, pointSize: 12)
    private let lock = IconButton(symbol: "lock.open", label: "Lock", size: 24, pointSize: 12)
    private var bold = false
    private var isLayerRow = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        icon.translatesAutoresizingMaskIntoConstraints = false
        nameField.isBordered = false; nameField.drawsBackground = false; nameField.isEditable = false; nameField.focusRingType = .none
        nameField.lineBreakMode = .byTruncatingTail
        nameField.translatesAutoresizingMaskIntoConstraints = false
        nameField.delegate = self
        eye.target = self; eye.action = #selector(toggleEye(_:))
        lock.target = self; lock.action = #selector(toggleLock(_:))
        let row = NSStackView(views: [icon, nameField, eye, lock])
        row.orientation = .horizontal; row.spacing = 7; row.alignment = .centerY; row.distribution = .fill
        row.translatesAutoresizingMaskIntoConstraints = false
        addSubview(row)
        NSLayoutConstraint.activate([
            row.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 2), row.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -6),
            row.centerYAnchor.constraint(equalTo: centerYAnchor), icon.widthAnchor.constraint(equalToConstant: 16),
        ])
        nameField.setContentHuggingPriority(.defaultLow, for: .horizontal)
    }
    required init?(coder: NSCoder) { fatalError("not used") }

    func configure(symbol: String, title: String, bold: Bool, visible: Bool, locked: Bool, showFlags: Bool) {
        self.bold = bold
        isLayerRow = node?.isLayer == true
        icon.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)?.withSymbolConfiguration(.init(pointSize: 13, weight: .regular))
        nameField.stringValue = title
        nameField.setAccessibilityLabel(title)
        eye.isHidden = !isLayerRow
        lock.isHidden = !showFlags
        eye.image = NSImage(systemSymbolName: visible ? "eye" : "eye.slash", accessibilityDescription: visible ? "Hide \(title)" : "Show \(title)")?.withSymbolConfiguration(.init(pointSize: 12, weight: .regular))
        eye.setAccessibilityLabel(visible ? "Hide \(title)" : "Show \(title)"); eye.toolTip = visible ? "Hide" : "Show"
        lock.image = NSImage(systemSymbolName: locked ? "lock.fill" : "lock.open", accessibilityDescription: locked ? "Unlock \(title)" : "Lock \(title)")?.withSymbolConfiguration(.init(pointSize: 12, weight: .regular))
        lock.setAccessibilityLabel(locked ? "Unlock \(title)" : "Lock \(title)"); lock.toolTip = locked ? "Unlock" : "Lock"
        self.visible = visible; self.locked = locked
        applyColors()
    }

    private var visible = true, locked = false

    override var backgroundStyle: NSView.BackgroundStyle { didSet { applyColors() } }

    /// The active layer (where new objects go) is drawn a little stronger.
    func refreshActive() { applyColors() }

    private func applyColors() {
        let selected = backgroundStyle == .emphasized
        let active = isLayerRow && owner?.activeLayerIDForCell == node?.layerID
        let weight: NSFont.Weight = (bold && active) ? .semibold : (bold ? .medium : .regular)
        nameField.font = .systemFont(ofSize: 13, weight: weight)
        let primary: NSColor = selected ? .white : Tok.textPrimary
        nameField.textColor = visible ? primary : (selected ? NSColor.white.withAlphaComponent(0.7) : Tok.textSecondary)
        icon.contentTintColor = selected ? .white : (isLayerRow ? Tok.iconDefault : Tok.accent.withAlphaComponent(0.9))
        eye.contentTintColor = selected ? .white : Tok.iconDefault
        lock.contentTintColor = selected ? .white : (locked ? Tok.textPrimary : Tok.iconDefault)
    }

    @objc private func toggleEye(_ s: Any?) { if let n = node { owner?.toggle(n, visible: !visible) } }
    @objc private func toggleLock(_ s: Any?) { if let n = node { owner?.toggle(n, locked: !locked) } }

    func beginRename() {
        guard let n = node, !(n.objectID != nil && { if case .connector = n.kind { return true }; return false }()) else { return }
        nameField.isEditable = true
        window?.makeFirstResponder(nameField)
        nameField.selectText(nil)
    }
}

extension SidebarCell: NSTextFieldDelegate {
    func controlTextDidEndEditing(_ obj: Notification) {
        guard nameField.isEditable, let n = node else { return }
        nameField.isEditable = false
        owner?.commitRename(n, to: nameField.stringValue)
    }
}
