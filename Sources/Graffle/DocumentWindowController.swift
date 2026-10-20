import AppKit
import UniformTypeIdentifiers

/// One document window: a unified toolbar over three rounded cards (sidebar, canvas, inspector), with the tool dock and the
/// minimap/zoom floating over the canvas. Every document has its own, so any number can be open at once.
final class DocumentWindowController: NSWindowController, NSWindowDelegate, NSMenuItemValidation, NSToolbarDelegate {
    let canvas = CanvasView(frame: NSRect(origin: .zero, size: CanvasView.canvasSize))
    let scroll = NSScrollView()
    let inspector = InspectorView()
    let sidebar = SidebarView()
    let dock = ToolDock()
    let zoomOverlay = ZoomOverlay()
    private(set) var contextBar: ContextBar!
    private var overlayView: NSView!

    private let sidebarCard = SurfaceView(frame: .zero)
    private let canvasCard = SurfaceView(frame: .zero)
    private let inspectorCard = SurfaceView(frame: .zero)
    private var sidebarWidth: NSLayoutConstraint!
    private var sidebarGap: NSLayoutConstraint!
    private static let sidebarKey = "ui.sidebarVisible"
    /// Whether the user wants the sidebar (it also folds away by itself in a narrow window).
    private(set) var sidebarWanted = UserDefaults.standard.object(forKey: sidebarKey) as? Bool ?? true
    private(set) var sidebarShown = true

    private let titleButton = NSButton()
    private let pageLabel = NSTextField(labelWithString: "Page 1")
    private let undoButton = IconButton(symbol: "arrow.uturn.backward", label: "Undo", tip: "Undo (⌘Z)", size: 32, pointSize: 15)
    private let redoButton = IconButton(symbol: "arrow.uturn.forward", label: "Redo", tip: "Redo (⇧⌘Z)", size: 32, pointSize: 15)
    private let exportButton = IconButton(symbol: "square.and.arrow.up", label: "Export", tip: "Export", size: 32, pointSize: 15)
    private let shareButton = PillButton(title: "Share")
    private let sidebarToggle = IconButton(symbol: "sidebar.left", label: "Toggle sidebar", tip: "Show or hide the sidebar", size: 30, pointSize: 15)

    init() {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1320, height: 840),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                              backing: .buffered, defer: false)
        window.minSize = NSSize(width: 760, height: 520)
        window.tabbingMode = .automatic           // separate windows by default; tabs if the system setting says so
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        super.init(window: window)
        window.delegate = self
        shouldCascadeWindows = true               // each new window opens a little down and to the right
        build(window)
        wire()
    }

    required init?(coder: NSCoder) { fatalError() }

    var graffleDocument: GraffleDocument? { document as? GraffleDocument }

    // MARK: Building

    private func build(_ window: NSWindow) {
        let root = SurfaceView(frame: .zero)
        root.fill = Tok.windowBG; root.outline = nil; root.radius = 0
        root.translatesAutoresizingMaskIntoConstraints = false
        window.contentView = root

        // The three cards.
        sidebarCard.fill = Tok.panelBG; sidebarCard.outline = Tok.panelOutline; sidebarCard.radius = Tok.Radius.window
        inspectorCard.fill = Tok.panelBG; inspectorCard.outline = Tok.panelOutline; inspectorCard.radius = Tok.Radius.window
        canvasCard.fill = Tok.canvasBG; canvasCard.outline = Tok.panelOutline; canvasCard.radius = Tok.Radius.window
        for card in [sidebarCard, canvasCard, inspectorCard] {
            card.translatesAutoresizingMaskIntoConstraints = false
            card.layer?.masksToBounds = true
            root.addSubview(card)
        }

        scroll.documentView = canvas
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = true
        scroll.scrollerStyle = .overlay
        scroll.allowsMagnification = true
        scroll.minMagnification = CanvasView.minZoom
        scroll.maxMagnification = CanvasView.maxZoom
        scroll.drawsBackground = true
        scroll.backgroundColor = Tok.canvasBG
        // Rulers in points, in canvas units (the canvas is flipped, so 0 is the top-left corner). Hidden unless asked for.
        scroll.hasHorizontalRuler = true
        scroll.hasVerticalRuler = true
        scroll.horizontalRulerView?.measurementUnits = .points
        scroll.verticalRulerView?.measurementUnits = .points
        scroll.rulersVisible = UserDefaults.standard.bool(forKey: "showRulers")
        scroll.translatesAutoresizingMaskIntoConstraints = false
        canvasCard.addSubview(scroll)

        // Floating over the canvas.
        let overlay = PassthroughView()
        overlay.translatesAutoresizingMaskIntoConstraints = false
        canvasCard.addSubview(overlay)
        overlay.addSubview(dock)
        overlay.addSubview(zoomOverlay)
        overlayView = overlay
        contextBar = ContextBar(canvas: canvas)
        contextBar.translatesAutoresizingMaskIntoConstraints = true
        contextBar.isHidden = true
        overlay.addSubview(contextBar)

        sidebar.translatesAutoresizingMaskIntoConstraints = false
        sidebarCard.addSubview(sidebar)
        inspector.translatesAutoresizingMaskIntoConstraints = false
        inspectorCard.addSubview(inspector)

        let gutter = Tok.Space.gutter
        sidebarWidth = sidebarCard.widthAnchor.constraint(equalToConstant: 236)
        sidebarGap = canvasCard.leadingAnchor.constraint(equalTo: sidebarCard.trailingAnchor, constant: Tok.Space.cardGap)
        let guide = root.safeAreaLayoutGuide
        // Without a preferred size the window shrinks to the Auto Layout minimum.
        let preferredW = root.widthAnchor.constraint(equalToConstant: 1320), preferredH = root.heightAnchor.constraint(equalToConstant: 840)
        preferredW.priority = .defaultLow; preferredH.priority = .defaultLow
        NSLayoutConstraint.activate([
            preferredW, preferredH,
            root.widthAnchor.constraint(greaterThanOrEqualToConstant: 760), root.heightAnchor.constraint(greaterThanOrEqualToConstant: 520),

            sidebarCard.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: gutter),
            sidebarCard.topAnchor.constraint(equalTo: guide.topAnchor), sidebarCard.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -gutter),
            sidebarWidth, sidebarGap,
            canvasCard.topAnchor.constraint(equalTo: guide.topAnchor), canvasCard.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -gutter),
            inspectorCard.leadingAnchor.constraint(equalTo: canvasCard.trailingAnchor, constant: Tok.Space.cardGap),
            inspectorCard.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -gutter),
            inspectorCard.topAnchor.constraint(equalTo: guide.topAnchor), inspectorCard.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -gutter),
            inspectorCard.widthAnchor.constraint(equalToConstant: 280),

            sidebar.leadingAnchor.constraint(equalTo: sidebarCard.leadingAnchor), sidebar.trailingAnchor.constraint(equalTo: sidebarCard.trailingAnchor),
            sidebar.topAnchor.constraint(equalTo: sidebarCard.topAnchor), sidebar.bottomAnchor.constraint(equalTo: sidebarCard.bottomAnchor),
            inspector.leadingAnchor.constraint(equalTo: inspectorCard.leadingAnchor), inspector.trailingAnchor.constraint(equalTo: inspectorCard.trailingAnchor),
            inspector.topAnchor.constraint(equalTo: inspectorCard.topAnchor), inspector.bottomAnchor.constraint(equalTo: inspectorCard.bottomAnchor),

            scroll.leadingAnchor.constraint(equalTo: canvasCard.leadingAnchor), scroll.trailingAnchor.constraint(equalTo: canvasCard.trailingAnchor),
            scroll.topAnchor.constraint(equalTo: canvasCard.topAnchor), scroll.bottomAnchor.constraint(equalTo: canvasCard.bottomAnchor),
            overlay.leadingAnchor.constraint(equalTo: canvasCard.leadingAnchor), overlay.trailingAnchor.constraint(equalTo: canvasCard.trailingAnchor),
            overlay.topAnchor.constraint(equalTo: canvasCard.topAnchor), overlay.bottomAnchor.constraint(equalTo: canvasCard.bottomAnchor),
            dock.bottomAnchor.constraint(equalTo: overlay.bottomAnchor, constant: -20),
            zoomOverlay.trailingAnchor.constraint(equalTo: overlay.trailingAnchor, constant: -16), zoomOverlay.bottomAnchor.constraint(equalTo: overlay.bottomAnchor, constant: -20),
        ])

        // The dock is centered, but gives way to the minimap and zoom pill when the canvas is narrow.
        let center = dock.centerXAnchor.constraint(equalTo: overlay.centerXAnchor)
        center.priority = NSLayoutConstraint.Priority(40)         // below the window's minimum-size fitting: centering never forces the window wider
        let clear = dock.trailingAnchor.constraint(lessThanOrEqualTo: zoomOverlay.leadingAnchor, constant: -12)
        let edge = dock.leadingAnchor.constraint(greaterThanOrEqualTo: overlay.leadingAnchor, constant: 8)
        edge.priority = NSLayoutConstraint.Priority(30)
        NSLayoutConstraint.activate([center, clear, edge])
        buildToolbar(window)
        window.setContentSize(NSSize(width: 1320, height: 840))
        window.center()
        applySidebar(animated: false)
    }

    // MARK: Toolbar

    private enum Item {
        static let sidebar = NSToolbarItem.Identifier("sidebar"), title = NSToolbarItem.Identifier("title")
        static let undo = NSToolbarItem.Identifier("undo"), redo = NSToolbarItem.Identifier("redo")
        static let export = NSToolbarItem.Identifier("export"), share = NSToolbarItem.Identifier("share")
    }

    private func buildToolbar(_ window: NSWindow) {
        titleButton.isBordered = false
        titleButton.setButtonType(.momentaryChange)
        titleButton.target = self; titleButton.action = #selector(showTitleMenu(_:))
        titleButton.alignment = .left
        titleButton.imagePosition = .imageTrailing
        titleButton.image = NSImage(systemSymbolName: "chevron.down", accessibilityDescription: nil)?.withSymbolConfiguration(.init(pointSize: 9, weight: .bold))
        titleButton.setAccessibilityLabel("Document menu")
        titleButton.toolTip = "Rename, duplicate or move this document"
        pageLabel.font = .systemFont(ofSize: 11.5); pageLabel.textColor = Tok.textSecondary
        sidebarToggle.target = self; sidebarToggle.action = #selector(toggleSidebar(_:))
        undoButton.target = canvas; undoButton.action = #selector(CanvasView.undo(_:))
        redoButton.target = canvas; redoButton.action = #selector(CanvasView.redo(_:))
        exportButton.target = self; exportButton.action = #selector(showExportMenu(_:))
        shareButton.target = self; shareButton.action = #selector(showExportMenu(_:))
        shareButton.toolTip = "Export this diagram as PNG, PDF or SVG"
        shareButton.setAccessibilityLabel("Share: export this diagram")

        let toolbar = NSToolbar(identifier: "GraffleDocument")
        toolbar.delegate = self
        toolbar.displayMode = .iconOnly
        toolbar.allowsUserCustomization = false
        window.toolbar = toolbar
        window.toolbarStyle = .unified
        updateTitle()
    }

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [Item.sidebar, Item.title, .flexibleSpace, Item.undo, Item.redo, Item.export, Item.share]
    }
    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] { toolbarDefaultItemIdentifiers(toolbar) }

    func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier id: NSToolbarItem.Identifier, willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        let item = NSToolbarItem(itemIdentifier: id)
        item.isBordered = false
        switch id {
        case Item.sidebar: item.view = sidebarToggle; item.label = "Sidebar"
        case Item.title:
            let stack = NSStackView(views: [titleButton, pageLabel])
            stack.orientation = .vertical; stack.alignment = .leading; stack.spacing = 0
            stack.setHuggingPriority(.defaultLow, for: .horizontal)
            item.view = stack; item.label = "Document"
        case Item.undo: item.view = undoButton; item.label = "Undo"
        case Item.redo: item.view = redoButton; item.label = "Redo"
        case Item.export: item.view = exportButton; item.label = "Export"
        case Item.share: item.view = shareButton; item.label = "Share"
        default: return nil
        }
        return item
    }

    /// The document's name (a menu button) and its page under it.
    func updateTitle() {
        let raw: String = (document?.displayName as String?) ?? window?.title ?? ""
        let name = raw.isEmpty ? "Untitled" : raw
        titleButton.attributedTitle = NSAttributedString(string: name + " ", attributes: [.font: Tok.Font.title(), .foregroundColor: Tok.textPrimary, .kern: -0.14])
        titleButton.sizeToFit()
        titleButton.contentTintColor = Tok.textPrimary
    }

    override func synchronizeWindowTitleWithDocumentName() { super.synchronizeWindowTitleWithDocumentName(); updateTitle() }

    @objc private func showTitleMenu(_ sender: NSButton) {
        let menu = NSMenu()
        for (title, action) in [("Rename…", #selector(NSDocument.rename(_:))), ("Duplicate", #selector(NSDocument.duplicate(_:))),
                                ("Move To…", #selector(NSDocument.move(_:))), ("Revert to Saved", #selector(NSDocument.revertToSaved(_:))),
                                ("Browse All Versions…", #selector(NSDocument.browseVersions(_:)))] {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
            item.target = document
            menu.addItem(item)
        }
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: sender.bounds.height + 2), in: sender)
    }

    @objc private func showExportMenu(_ sender: NSView) {
        let menu = NSMenu()
        for (title, action) in [("Export as PNG…", #selector(exportPNG(_:))), ("Export as PDF…", #selector(exportPDF(_:))), ("Export as SVG…", #selector(exportSVG(_:)))] {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: ""); item.target = self
            menu.addItem(item)
        }
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: sender.bounds.height + 4), in: sender)
    }

    // MARK: Sidebar

    @objc func toggleSidebar(_ sender: Any?) {
        sidebarWanted.toggle()
        UserDefaults.standard.set(sidebarWanted, forKey: Self.sidebarKey)
        applySidebar(animated: true)
    }

    /// Shows or folds the sidebar: it is hidden when the user turned it off, and also when the window is too narrow for three panels.
    func applySidebar(animated: Bool) {
        let narrow = (window?.contentView?.bounds.width ?? 1320) < 1000
        let show = sidebarWanted && !narrow
        guard show != sidebarShown || !animated else { return }
        sidebarShown = show
        let apply = { [self] in
            sidebarWidth.constant = show ? 236 : 0
            sidebarGap.constant = show ? Tok.Space.cardGap : 0
            sidebarCard.alphaValue = show ? 1 : 0
        }
        sidebarCard.isHidden = false
        if animated, !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            NSAnimationContext.runAnimationGroup({ ctx in
                ctx.duration = 0.18; ctx.allowsImplicitAnimation = true
                apply(); window?.contentView?.layoutSubtreeIfNeeded()
            }, completionHandler: { [self] in sidebarCard.isHidden = !show })
        } else {
            apply(); sidebarCard.isHidden = !show
        }
    }

    func windowDidResize(_ notification: Notification) { applySidebar(animated: true) }

    // MARK: Wiring

    /// Connects the canvas to this window's sidebar, inspector, dock and overlays.
    private func wire() {
        canvas.onChange = { [weak self] in
            guard let self else { return }
            sidebar.reload()
            zoomOverlay.refresh()
            updateUndoButtons()
            updateContextBar()
        }
        canvas.onActiveLayerChange = { [weak self] in self?.sidebar.reload() }
        canvas.onSelectionChange = { [weak self] in self?.inspector.refresh(); self?.sidebar.syncSelection(); self?.updateContextBar() }
        canvas.onToolChange = { [weak self] in self?.syncToolButtons() }
        dock.onPick = { [weak self] tool in
            self?.canvas.tool = tool
            self?.window?.makeFirstResponder(self?.canvas)
        }
        inspector.canvas = canvas
        sidebar.canvas = canvas
        zoomOverlay.attach(canvas)
        zoomOverlay.isHidden = !NavigatorPrefs.isVisible
        NotificationCenter.default.addObserver(forName: .navigatorVisibilityChanged, object: nil, queue: nil) { [weak self] _ in
            self?.zoomOverlay.isHidden = !NavigatorPrefs.isVisible
        }
        inspector.refresh()
        syncToolButtons()
        updateUndoButtons()
    }

    /// Undo and Redo dim when there is nothing to undo or redo.
    func updateUndoButtons() {
        undoButton.isEnabled = canvas.undoManager?.canUndo ?? false
        redoButton.isEnabled = canvas.undoManager?.canRedo ?? false
        undoButton.alphaValue = undoButton.isEnabled ? 1 : 0.4
        redoButton.alphaValue = redoButton.isEnabled ? 1 : 0.4
    }

    private func syncToolButtons() { dock.sync(canvas.tool); updateContextBar() }

    /// Places the contextual toolbar above the selection (and hides it when there is nothing to act on).
    func updateContextBar() {
        guard contextBar != nil, overlayView != nil else { return }
        contextBar.update(in: overlayView)
    }

    /// Focuses the canvas once the window is on screen.
    override func showWindow(_ sender: Any?) {
        super.showWindow(sender)
        window?.makeFirstResponder(canvas)
        zoomOverlay.observe()
        let clip = scroll.contentView
        NotificationCenter.default.addObserver(forName: NSView.boundsDidChangeNotification, object: clip, queue: .main) { [weak self] _ in self?.updateContextBar() }
        applySidebar(animated: false)
    }

    // MARK: Window delegate


    /// The canvas registers its undo steps with the document, so the document knows when it has unsaved changes.
    func windowWillReturnUndoManager(_ window: NSWindow) -> UndoManager? { document?.undoManager }

    /// Closing a document with unsaved changes asks to save, with the usual Save / Don't Save / Cancel sheet.
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        guard let doc = document, doc.isDocumentEdited else { return true }
        doc.canClose(withDelegate: self, shouldClose: #selector(document(_:shouldClose:contextInfo:)), contextInfo: nil)
        return false
    }

    @objc private func document(_ doc: NSDocument, shouldClose: Bool, contextInfo: UnsafeMutableRawPointer?) {
        if shouldClose { doc.close() }
    }

    // MARK: Menu validation

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        switch menuItem.action {
        case #selector(toggleRulers(_:)): menuItem.title = scroll.rulersVisible ? "Hide Rulers" : "Show Rulers"
        case #selector(toggleSmartGuides(_:)): menuItem.state = canvas.smartGuides ? .on : .off
        case #selector(toggleGrid(_:)): menuItem.state = canvas.showGrid ? .on : .off
        case #selector(toggleSnap(_:)): menuItem.state = canvas.snapToGrid ? .on : .off
        case #selector(toggleNavigator(_:)): menuItem.title = NavigatorPrefs.isVisible ? "Hide Navigator" : "Show Navigator"
        case #selector(zoomToSelection(_:)): return !canvas.selection.isEmpty
        case #selector(exportPNG(_:)), #selector(exportPDF(_:)), #selector(exportSVG(_:)): return canvas.exportBounds() != nil
        default: break
        }
        return true
    }

    // MARK: View actions

    private func setZoom(_ m: CGFloat) { canvas.setMagnification(m) }

    @objc func zoomIn(_ s: Any?) { setZoom(scroll.magnification * 1.25) }
    @objc func zoomOut(_ s: Any?) { setZoom(scroll.magnification / 1.25) }
    @objc func zoomActual(_ s: Any?) { setZoom(1) }
    @objc func zoomToFit(_ s: Any?) { canvas.zoomToFitDiagram() }
    @objc func zoomToSelection(_ s: Any?) { canvas.zoomToFitSelection() }
    @objc func toggleNavigator(_ s: Any?) { NavigatorPrefs.isVisible.toggle() }
    @objc func toggleRulers(_ s: Any?) {
        scroll.rulersVisible.toggle()
        UserDefaults.standard.set(scroll.rulersVisible, forKey: "showRulers")
    }
    @objc func toggleSmartGuides(_ s: Any?) { canvas.smartGuides.toggle() }
    /// View → Theme…: pick a theme for this diagram from the same gallery as File → New….
    @objc func chooseTheme(_ sender: Any?) {
        guard let window else { return }
        NewDocumentController.presentThemePicker(on: window, selected: canvas.drawing.theme ?? ThemeLibrary.clean) { [weak self] theme in
            self?.canvas.applyTheme(theme)
            self?.window?.makeFirstResponder(self?.canvas)
        }
    }
    @objc func toggleGrid(_ s: Any?) { canvas.showGrid.toggle() }
    @objc func toggleSnap(_ s: Any?) { canvas.snapToGrid.toggle() }

    // MARK: Import and export

    /// Adds an SVG to this document as a new layer, grouped, near the top-left of the view.
    @objc func importSVG(_ s: Any?) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.svg]
        panel.message = "Choose an SVG to add to this diagram"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let result = try SVGImport.parse(Data(contentsOf: url), name: url.deletingPathExtension().lastPathComponent)
            guard !result.shapes.isEmpty else {
                GraffleDocument.warn("Nothing to import", "This SVG has no shapes, paths or text that Graffle can read.",
                                     skipped: result.skippedSummary, in: window)
                return
            }
            canvas.importSVG(result, near: canvas.visibleOrigin)
            window?.makeFirstResponder(canvas)
            if let note = result.skippedSummary {
                GraffleDocument.warn("Some parts were left out", "Graffle imports simple SVG shapes, paths and text.",
                                     skipped: note, in: window)
            }
        } catch {
            NSAlert(error: error).runModal()
        }
    }

    @objc func exportPNG(_ s: Any?) { export(ext: "png", data: canvas.pngData()) }
    @objc func exportPDF(_ s: Any?) { export(ext: "pdf", data: canvas.pdfData()) }
    @objc func exportSVG(_ s: Any?) { export(ext: "svg", data: canvas.svgData()) }

    private func export(ext: String, data: Data?) {
        guard let data else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType(filenameExtension: ext) ?? .data]
        panel.nameFieldStringValue = "\(graffleDocument?.displayName ?? "Untitled").\(ext)"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do { try data.write(to: url, options: .atomic) } catch { NSAlert(error: error).runModal() }
    }
}
