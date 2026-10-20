import AppKit

extension LibraryItem {
    /// Lines like braces and brackets have no inside to fill.
    var isOpenPath: Bool {
        guard circuit == nil, custom == nil, let outline, !outline.isEmpty else { return false }
        return !outline.contains { $0.op == .close }
    }
}

/// Draws the little picture of a library item.
enum LibraryThumbnail {
    static func draw(_ item: LibraryItem, in rect: CGRect, ink: CGColor, fill: CGColor, ctx: CGContext) {
        ctx.saveGState()
        defer { ctx.restoreGState() }
        var drawing = item.previewShapes()
        if item.kind == .rounded, item.compose == nil, item.custom == nil, !drawing.isEmpty { drawing[0].style.cornerRadius = item.cornerRadius > 0 ? item.cornerRadius : 12 }
        let box = drawing.map(\.worldBounds).reduce(nil) { acc, f in acc.map { $0.union(f) } ?? f } ?? .zero
        guard box.width > 0, box.height > 0 else { return }
        let scale = min(rect.width / box.width, rect.height / box.height)
        ctx.translateBy(x: rect.midX - box.midX * scale, y: rect.midY - box.midY * scale)
        ctx.scaleBy(x: scale, y: scale)
        let line = 1.5 / scale
        for s in drawing {
            let path = s.worldPath()
            ctx.setLineJoin(.round); ctx.setLineCap(.round)
            if item.compose != nil {
                // Real-world parts follow the panel's ink; their white "cut-outs" (no outline) are only for the canvas.
                guard s.style.stroke.visible else { continue }
                if s.style.fill.kind != .none { ctx.setFillColor(fill); ctx.addPath(path); ctx.fillPath() }
                ctx.setStrokeColor(ink); ctx.setLineWidth(line); ctx.addPath(path); ctx.strokePath()
                continue
            }
            if item.hasOwnLook {
                // Saved shapes and real-world parts keep their own colors.
                if s.style.fill.kind != .none { ctx.setFillColor(s.style.fill.color.cg); ctx.addPath(path); ctx.fillPath() }
                if s.style.stroke.visible { ctx.setStrokeColor(s.style.stroke.color.cg); ctx.setLineWidth(max(line, 1 / scale)); ctx.addPath(path); ctx.strokePath() }
                continue
            }
            let filled = item.circuit == nil && !item.isOpenPath
            if filled || item.circuit == .junction { ctx.setFillColor(item.circuit == .junction ? ink : fill); ctx.addPath(path); ctx.fillPath() }
            if item.circuit != .junction { ctx.setStrokeColor(ink); ctx.setLineWidth(line); ctx.addPath(path); ctx.strokePath() }
        }
    }

    static func image(_ item: LibraryItem, size: CGSize) -> NSImage {
        NSImage(size: size, flipped: true) { rect in
            guard let ctx = NSGraphicsContext.current?.cgContext else { return false }
            draw(item, in: rect.insetBy(dx: 2, dy: 2), ink: NSColor.labelColor.cgColor, fill: NSColor.labelColor.withAlphaComponent(0.10).cgColor, ctx: ctx)
            return true
        }
    }
}

/// The scrolling content of the Shape Library: collapsible categories, each a grid of items.
final class LibraryGrid: NSView, NSDraggingSource, NSViewToolTipOwner {
    static let dragType = NSPasteboard.PasteboardType("mx.graffle.library-item")
    private static let collapsedKey = "ui.library.collapsed"

    var onInsert: ((LibraryItem) -> Void)?
    var onRename: ((LibraryItem) -> Void)?
    var onDelete: ((LibraryItem) -> Void)?

    private(set) var sections: [(title: String, items: [LibraryItem])] = []
    private(set) var collapsed: Set<String> = Set(UserDefaults.standard.stringArray(forKey: LibraryGrid.collapsedKey) ?? [])
    private var hovered: String?
    private var pressed: (item: LibraryItem, point: CGPoint)?
    private var cells: [(rect: CGRect, item: LibraryItem)] = []
    private var headers: [(rect: CGRect, title: String)] = []
    private var tracking: NSTrackingArea?

    private let cellSize = CGSize(width: 66, height: 74), headerHeight: CGFloat = 30, inset: CGFloat = 8

    override var isFlipped: Bool { true }
    override init(frame: NSRect) { super.init(frame: frame); setAccessibilityRole(.list); setAccessibilityLabel("Shape Library") }
    required init?(coder: NSCoder) { fatalError("not used") }

    func setSections(_ s: [(title: String, items: [LibraryItem])]) {
        sections = s
        relayout()
    }

    /// Categories fold away; an active search shows every match regardless.
    var searching = false

    func toggle(_ title: String) {
        if collapsed.contains(title) { collapsed.remove(title) } else { collapsed.insert(title) }
        UserDefaults.standard.set(Array(collapsed), forKey: Self.collapsedKey)
        relayout()
    }

    private var columns: Int { max(1, Int((bounds.width - inset * 2) / cellSize.width)) }

    override func layout() { super.layout(); relayout(resizeOnly: true) }

    private func relayout(resizeOnly: Bool = false) {
        cells = []; headers = []
        var y: CGFloat = 4
        let cols = columns
        let xPad = max(inset, (bounds.width - CGFloat(cols) * cellSize.width) / 2)
        for section in sections where !section.items.isEmpty {
            headers.append((CGRect(x: 0, y: y, width: bounds.width, height: headerHeight), section.title))
            y += headerHeight
            if searching || !collapsed.contains(section.title) {
                for (i, item) in section.items.enumerated() {
                    let r = CGRect(x: xPad + CGFloat(i % cols) * cellSize.width, y: y + CGFloat(i / cols) * cellSize.height, width: cellSize.width, height: cellSize.height)
                    cells.append((r, item))
                }
                y += CGFloat((section.items.count + cols - 1) / cols) * cellSize.height + 6
            }
        }
        let height = y + 8
        if abs(frame.height - height) > 0.5 { setFrameSize(NSSize(width: frame.width, height: height)) }
        removeAllToolTips()
        // The owner is not retained by AppKit, so it must be this view; the cell index travels as the (unretained) user data.
        for (i, c) in cells.enumerated() { addToolTip(c.rect, owner: self, userData: UnsafeMutableRawPointer(bitPattern: i + 1)) }
        needsDisplay = true
    }

    func view(_ view: NSView, stringForToolTip tag: NSView.ToolTipTag, point: NSPoint, userData data: UnsafeMutableRawPointer?) -> String {
        guard let data else { return "" }
        let i = Int(bitPattern: data) - 1
        return cells.indices.contains(i) ? cells[i].item.name : ""
    }

    // MARK: Drawing

    override func draw(_ dirty: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        let ink = Tok.resolve(Tok.iconDefault, for: self), fill = Tok.resolve(Tok.accent, for: self).copy(alpha: 0.16) ?? ink
        for h in headers where h.rect.intersects(dirty) {
            let open = searching || !collapsed.contains(h.title)
            let chevron = NSImage(systemSymbolName: open ? "chevron.down" : "chevron.right", accessibilityDescription: nil)?
                .withSymbolConfiguration(.init(pointSize: 9, weight: .bold))
            chevron?.isTemplate = true
            if let chevron {
                NSGraphicsContext.saveGraphicsState()
                Tok.textSecondary.set()
                chevron.draw(in: CGRect(x: 14, y: h.rect.midY - 5, width: 10, height: 10))
                NSGraphicsContext.restoreGraphicsState()
            }
            let count = sections.first { $0.title == h.title }?.items.count ?? 0
            let text = NSAttributedString(string: h.title, attributes: [.font: NSFont.systemFont(ofSize: 11.5, weight: .semibold), .foregroundColor: Tok.textSecondary])
            text.draw(at: CGPoint(x: 30, y: h.rect.midY - 8))
            let n = NSAttributedString(string: "\(count)", attributes: [.font: NSFont.systemFont(ofSize: 10.5), .foregroundColor: Tok.textSecondary])
            n.draw(at: CGPoint(x: bounds.width - 14 - n.size().width, y: h.rect.midY - 7))
        }
        for c in cells where c.rect.intersects(dirty) {
            if hovered == c.item.id {
                ctx.setFillColor(Tok.resolve(Tok.hoverFill, for: self))
                ctx.addPath(CGPath(roundedRect: c.rect.insetBy(dx: 2, dy: 2), cornerWidth: 8, cornerHeight: 8, transform: nil)); ctx.fillPath()
            }
            let art = CGRect(x: c.rect.minX + 9, y: c.rect.minY + 7, width: c.rect.width - 18, height: 38)
            LibraryThumbnail.draw(c.item, in: art, ink: ink, fill: fill, ctx: ctx)
            let style = NSMutableParagraphStyle(); style.alignment = .center; style.lineBreakMode = .byTruncatingTail
            NSAttributedString(string: c.item.name, attributes: [.font: NSFont.systemFont(ofSize: 9.5), .foregroundColor: Tok.textSecondary, .paragraphStyle: style])
                .draw(in: CGRect(x: c.rect.minX + 2, y: c.rect.minY + 50, width: c.rect.width - 4, height: 22))
        }
    }

    // MARK: Mouse

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let t = tracking { removeTrackingArea(t) }
        tracking = NSTrackingArea(rect: bounds, options: [.mouseMoved, .mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect], owner: self)
        addTrackingArea(tracking!)
    }

    private func item(at p: CGPoint) -> LibraryItem? { cells.first { $0.rect.contains(p) }?.item }

    override func mouseMoved(with event: NSEvent) {
        let id = item(at: convert(event.locationInWindow, from: nil))?.id
        if id != hovered { hovered = id; needsDisplay = true }
    }
    override func mouseExited(with event: NSEvent) { hovered = nil; needsDisplay = true }

    override func mouseDown(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        if let h = headers.first(where: { $0.rect.contains(p) }) { if !searching { toggle(h.title) }; return }
        if let it = item(at: p) { pressed = (it, p) }
    }

    override func mouseDragged(with event: NSEvent) {
        guard let press = pressed else { return }
        let p = convert(event.locationInWindow, from: nil)
        guard hypot(p.x - press.point.x, p.y - press.point.y) > 4 else { return }
        pressed = nil
        let pb = NSPasteboardItem()
        pb.setString(press.item.id, forType: Self.dragType)
        let drag = NSDraggingItem(pasteboardWriter: pb)
        let size = CGSize(width: 64, height: 48)
        drag.setDraggingFrame(CGRect(x: p.x - size.width / 2, y: p.y - size.height / 2, width: size.width, height: size.height), contents: LibraryThumbnail.image(press.item, size: size))
        beginDraggingSession(with: [drag], event: event, source: self)
    }

    override func mouseUp(with event: NSEvent) {
        defer { pressed = nil }
        guard let press = pressed, item(at: convert(event.locationInWindow, from: nil))?.id == press.item.id else { return }
        onInsert?(press.item)
    }

    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation { .copy }

    override func menu(for event: NSEvent) -> NSMenu? {
        guard let it = item(at: convert(event.locationInWindow, from: nil)) else { return nil }
        let menu = NSMenu()
        let insert = NSMenuItem(title: "Add to Diagram", action: #selector(menuInsert(_:)), keyEquivalent: "")
        insert.target = self; insert.representedObject = it.id
        menu.addItem(insert)
        if it.origin == .custom {
            menu.addItem(.separator())
            let rename = NSMenuItem(title: "Rename…", action: #selector(menuRename(_:)), keyEquivalent: "")
            let delete = NSMenuItem(title: "Delete from Library", action: #selector(menuDelete(_:)), keyEquivalent: "")
            for m in [rename, delete] { m.target = self; m.representedObject = it.id; menu.addItem(m) }
        }
        return menu
    }

    private func menuItem(_ sender: NSMenuItem) -> LibraryItem? {
        guard let id = sender.representedObject as? String else { return nil }
        return sections.lazy.flatMap(\.items).first { $0.id == id }
    }
    @objc private func menuInsert(_ s: NSMenuItem) { if let it = menuItem(s) { onInsert?(it) } }
    @objc private func menuRename(_ s: NSMenuItem) { if let it = menuItem(s) { onRename?(it) } }
    @objc private func menuDelete(_ s: NSMenuItem) { if let it = menuItem(s) { onDelete?(it) } }
}

/// The right-hand card that lists every shape: search at the top, categories below.
final class LibraryView: NSView, NSTextFieldDelegate {
    let grid = LibraryGrid(frame: .zero)
    private let searchField = NSTextField()
    private let scroll = NSScrollView()
    private let addButton = IconButton(symbol: "plus", label: "Save selection to library", tip: "Save the selected objects as a shape in “My Shapes”", size: 28, pointSize: 12)
    private let emptyNote = NSTextField(wrappingLabelWithString: "")
    private let library: ShapeLibrary
    private(set) var query = ""

    var onInsert: ((LibraryItem) -> Void)? { didSet { grid.onInsert = onInsert } }
    var onSaveSelection: (() -> Void)?

    init(library: ShapeLibrary = .shared) {
        self.library = library
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        setAccessibilityLabel("Shape Library")
        build()
        reload()
        NotificationCenter.default.addObserver(self, selector: #selector(libraryChanged), name: ShapeLibrary.didChange, object: library)
    }
    required init?(coder: NSCoder) { fatalError("not used") }
    deinit { NotificationCenter.default.removeObserver(self) }

    @objc private func libraryChanged() { reload() }

    private func build() {
        let title = NSTextField(labelWithString: "Shape Library")
        title.font = .systemFont(ofSize: 11.5, weight: .semibold)
        title.textColor = Tok.textSecondary
        addButton.target = self; addButton.action = #selector(saveSelection(_:))
        addButton.isEnabled = false
        let head = NSStackView(views: [title, NSView(), addButton])
        head.orientation = .horizontal
        head.edgeInsets = NSEdgeInsets(top: 10, left: 16, bottom: 0, right: 10)
        head.translatesAutoresizingMaskIntoConstraints = false

        let searchBox = SurfaceView(frame: .zero)
        searchBox.fill = Tok.hoverFill; searchBox.outline = nil; searchBox.radius = Tok.Radius.field
        searchBox.translatesAutoresizingMaskIntoConstraints = false
        let glass = NSImageView(image: NSImage(systemSymbolName: "magnifyingglass", accessibilityDescription: nil)?.withSymbolConfiguration(.init(pointSize: 12, weight: .regular)) ?? NSImage())
        glass.contentTintColor = Tok.textSecondary
        glass.translatesAutoresizingMaskIntoConstraints = false
        searchField.placeholderString = "Search shapes"
        searchField.isBordered = false; searchField.drawsBackground = false; searchField.focusRingType = .none
        searchField.font = Tok.Font.body(); searchField.textColor = Tok.textPrimary
        searchField.delegate = self
        searchField.setAccessibilityLabel("Search shapes")
        searchField.translatesAutoresizingMaskIntoConstraints = false
        [glass, searchField].forEach(searchBox.addSubview)

        scroll.documentView = grid
        scroll.hasVerticalScroller = true
        scroll.scrollerStyle = .overlay
        scroll.drawsBackground = false
        scroll.translatesAutoresizingMaskIntoConstraints = false

        emptyNote.font = .systemFont(ofSize: 12); emptyNote.textColor = Tok.textSecondary
        emptyNote.alignment = .center
        emptyNote.isHidden = true
        emptyNote.translatesAutoresizingMaskIntoConstraints = false

        let hint = NSTextField(wrappingLabelWithString: "Click a shape, or drag it onto the canvas.")
        hint.font = .systemFont(ofSize: 10.5); hint.textColor = Tok.textSecondary
        hint.translatesAutoresizingMaskIntoConstraints = false

        [head, searchBox, scroll, emptyNote, hint].forEach(addSubview)
        NSLayoutConstraint.activate([
            head.leadingAnchor.constraint(equalTo: leadingAnchor), head.trailingAnchor.constraint(equalTo: trailingAnchor), head.topAnchor.constraint(equalTo: topAnchor),
            searchBox.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12), searchBox.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            searchBox.topAnchor.constraint(equalTo: head.bottomAnchor, constant: 6), searchBox.heightAnchor.constraint(equalToConstant: 30),
            glass.leadingAnchor.constraint(equalTo: searchBox.leadingAnchor, constant: 9), glass.centerYAnchor.constraint(equalTo: searchBox.centerYAnchor),
            searchField.leadingAnchor.constraint(equalTo: glass.trailingAnchor, constant: 6), searchField.trailingAnchor.constraint(equalTo: searchBox.trailingAnchor, constant: -8),
            searchField.centerYAnchor.constraint(equalTo: searchBox.centerYAnchor),
            scroll.leadingAnchor.constraint(equalTo: leadingAnchor), scroll.trailingAnchor.constraint(equalTo: trailingAnchor),
            scroll.topAnchor.constraint(equalTo: searchBox.bottomAnchor, constant: 8), scroll.bottomAnchor.constraint(equalTo: hint.topAnchor, constant: -4),
            emptyNote.centerXAnchor.constraint(equalTo: centerXAnchor), emptyNote.centerYAnchor.constraint(equalTo: centerYAnchor),
            emptyNote.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: 20),
            hint.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14), hint.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),
            hint.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -10),
        ])
        grid.autoresizingMask = [.width]
    }

    override func layout() {
        super.layout()
        if abs(grid.frame.width - scroll.contentSize.width) > 0.5 { grid.setFrameSize(NSSize(width: scroll.contentSize.width, height: grid.frame.height)) }
    }

    /// Rebuilds the list for the current search: My Shapes first, then the built-in categories.
    func reload() {
        let all = library.allItems.filter { ShapeCatalog.matches($0, query) }
        var sections: [(title: String, items: [LibraryItem])] = []
        let mine = all.filter { $0.origin == .custom }
        if !mine.isEmpty { sections.append((ShapeLibrary.myShapes, mine)) }
        for category in ShapeCatalog.categoryOrder {
            let items = all.filter { $0.category == category }
            if !items.isEmpty { sections.append((category, items)) }
        }
        grid.searching = !query.trimmingCharacters(in: .whitespaces).isEmpty
        grid.setSections(sections)
        emptyNote.stringValue = "No shapes match “\(query)”."
        emptyNote.isHidden = !sections.isEmpty
    }

    func controlTextDidChange(_ obj: Notification) {
        query = searchField.stringValue
        reload()
    }

    func setQuery(_ q: String) { searchField.stringValue = q; query = q; reload() }

    /// The save button is only useful when something is selected.
    func setCanSave(_ on: Bool) { addButton.isEnabled = on; addButton.alphaValue = on ? 1 : 0.4 }

    @objc private func saveSelection(_ sender: Any?) { onSaveSelection?() }
}
