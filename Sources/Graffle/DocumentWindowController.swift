import AppKit
import UniformTypeIdentifiers

/// One document window: the tool palette, the canvas with its rulers and zoom, and the inspector.
/// Every document has its own, so any number can be open at once, each with independent state.
final class DocumentWindowController: NSWindowController, NSWindowDelegate, NSMenuItemValidation {
    let canvas = CanvasView(frame: NSRect(origin: .zero, size: CanvasView.canvasSize))
    let scroll = NSScrollView()
    let inspector = InspectorView()
    private var toolButtons: [(Tool, NSButton)] = []

    init() {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1280, height: 820),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable],
                              backing: .buffered, defer: false)
        window.minSize = NSSize(width: 800, height: 500)
        window.tabbingMode = .automatic           // separate windows by default; tabs if the system setting says so
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
        let root = NSView()
        // Let Auto Layout drive the window size: preferred 1280x820 (low priority), 800x500 minimum.
        root.translatesAutoresizingMaskIntoConstraints = false
        window.contentView = root

        let palette = buildPalette()
        palette.translatesAutoresizingMaskIntoConstraints = false

        scroll.documentView = canvas
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = true
        scroll.allowsMagnification = true
        scroll.minMagnification = 0.25
        scroll.maxMagnification = 4
        scroll.backgroundColor = NSColor(white: 0.85, alpha: 1)
        // Rulers in points, in canvas units (the canvas is flipped, so 0 is the top-left corner).
        scroll.hasHorizontalRuler = true
        scroll.hasVerticalRuler = true
        scroll.horizontalRulerView?.measurementUnits = .points
        scroll.verticalRulerView?.measurementUnits = .points
        scroll.rulersVisible = UserDefaults.standard.bool(forKey: "showRulers")
        scroll.translatesAutoresizingMaskIntoConstraints = false

        inspector.translatesAutoresizingMaskIntoConstraints = false

        let left = NSBox(); left.boxType = .separator; left.translatesAutoresizingMaskIntoConstraints = false
        let right = NSBox(); right.boxType = .separator; right.translatesAutoresizingMaskIntoConstraints = false

        [palette, scroll, inspector, left, right].forEach(root.addSubview)

        // Without a preferred size the window shrinks to the Auto Layout minimum (a 1 pt tall content view).
        let preferredW = root.widthAnchor.constraint(equalToConstant: 1280)
        let preferredH = root.heightAnchor.constraint(equalToConstant: 820)
        preferredW.priority = .defaultLow
        preferredH.priority = .defaultLow
        NSLayoutConstraint.activate([
            preferredW, preferredH,
            root.widthAnchor.constraint(greaterThanOrEqualToConstant: 800),
            root.heightAnchor.constraint(greaterThanOrEqualToConstant: 500),

            palette.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            palette.topAnchor.constraint(equalTo: root.topAnchor),
            palette.bottomAnchor.constraint(equalTo: root.bottomAnchor),
            palette.widthAnchor.constraint(equalToConstant: 52),

            left.leadingAnchor.constraint(equalTo: palette.trailingAnchor),
            left.topAnchor.constraint(equalTo: root.topAnchor),
            left.bottomAnchor.constraint(equalTo: root.bottomAnchor),
            left.widthAnchor.constraint(equalToConstant: 1),

            scroll.leadingAnchor.constraint(equalTo: left.trailingAnchor),
            scroll.topAnchor.constraint(equalTo: root.topAnchor),
            scroll.bottomAnchor.constraint(equalTo: root.bottomAnchor),
            scroll.trailingAnchor.constraint(equalTo: right.leadingAnchor),

            right.trailingAnchor.constraint(equalTo: inspector.leadingAnchor),
            right.topAnchor.constraint(equalTo: root.topAnchor),
            right.bottomAnchor.constraint(equalTo: root.bottomAnchor),
            right.widthAnchor.constraint(equalToConstant: 1),

            inspector.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            inspector.topAnchor.constraint(equalTo: root.topAnchor),
            inspector.bottomAnchor.constraint(equalTo: root.bottomAnchor),
            inspector.widthAnchor.constraint(equalToConstant: 260),
        ])

        // Size the window only now that the constraints exist.
        window.setContentSize(NSSize(width: 1280, height: 820))
        window.center()
    }

    private func buildPalette() -> NSView {
        let tools: [(Tool, String, String)] = [
            (.select, "cursorarrow", "Select (V)"),
            (.shape(.rectangle), "rectangle", "Rectangle (R)"),
            (.shape(.rounded), "app", "Rounded Rectangle (U)"),
            (.shape(.ellipse), "circle", "Ellipse (E)"),
            (.shape(.diamond), "diamond", "Diamond (D)"),
            (.shape(.triangle), "triangle", "Triangle (G)"),
            (.shape(.text), "textformat", "Text (T)"),
            (.connector, "arrow.up.right", "Connector (C)"),
            (.pen, "pencil.tip", "Pen (P)"),
        ]
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.spacing = 6
        stack.edgeInsets = NSEdgeInsets(top: 12, left: 8, bottom: 12, right: 8)

        for (i, t) in tools.enumerated() {
            let b = NSButton()
            b.image = NSImage(systemSymbolName: t.1, accessibilityDescription: t.2)
            b.toolTip = t.2
            b.setButtonType(.pushOnPushOff)
            b.bezelStyle = .texturedRounded
            b.imagePosition = .imageOnly
            b.tag = i
            b.target = self
            b.action = #selector(toolPicked(_:))
            b.widthAnchor.constraint(equalToConstant: 36).isActive = true
            b.heightAnchor.constraint(equalToConstant: 32).isActive = true
            stack.addArrangedSubview(b)
            toolButtons.append((t.0, b))
        }
        let wrapper = NSView()
        stack.translatesAutoresizingMaskIntoConstraints = false
        wrapper.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: wrapper.topAnchor),
            stack.leadingAnchor.constraint(equalTo: wrapper.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: wrapper.trailingAnchor),
        ])
        return wrapper
    }

    /// Connects the canvas to this window's inspector and tool palette.
    private func wire() {
        canvas.onChange = { [weak self] in self?.inspector.refreshLayers() }
        canvas.onActiveLayerChange = { [weak self] in self?.inspector.refreshLayers() }
        canvas.onSelectionChange = { [weak self] in self?.inspector.refresh() }
        canvas.onToolChange = { [weak self] in self?.syncToolButtons() }
        inspector.canvas = canvas
        inspector.refresh()
        syncToolButtons()
    }

    @objc private func toolPicked(_ sender: NSButton) {
        canvas.tool = toolButtons[sender.tag].0
        window?.makeFirstResponder(canvas)
    }

    private func syncToolButtons() {
        for (tool, button) in toolButtons { button.state = (tool == canvas.tool) ? .on : .off }
    }

    /// Focuses the canvas once the window is on screen.
    override func showWindow(_ sender: Any?) {
        super.showWindow(sender)
        window?.makeFirstResponder(canvas)
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
        case #selector(exportPNG(_:)), #selector(exportPDF(_:)), #selector(exportSVG(_:)): return canvas.exportBounds() != nil
        default: break
        }
        return true
    }

    // MARK: View actions

    private func setZoom(_ m: CGFloat) {
        scroll.magnification = min(max(m, scroll.minMagnification), scroll.maxMagnification)
    }

    @objc func zoomIn(_ s: Any?) { setZoom(scroll.magnification * 1.25) }
    @objc func zoomOut(_ s: Any?) { setZoom(scroll.magnification / 1.25) }
    @objc func zoomActual(_ s: Any?) { setZoom(1) }
    @objc func toggleRulers(_ s: Any?) {
        scroll.rulersVisible.toggle()
        UserDefaults.standard.set(scroll.rulersVisible, forKey: "showRulers")
    }
    @objc func toggleSmartGuides(_ s: Any?) { canvas.smartGuides.toggle() }
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
