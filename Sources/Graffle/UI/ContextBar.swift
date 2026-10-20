import AppKit

/// A round swatch button: a filled dot (fill color) or a ring (stroke color).
final class SwatchButton: NSButton {
    enum Kind { case fill, stroke }
    let kind: Kind
    var color: NSColor = .white { didSet { needsDisplay = true } }

    init(kind: Kind, label: String) {
        self.kind = kind
        super.init(frame: NSRect(x: 0, y: 0, width: 30, height: 30))
        isBordered = false
        title = ""
        setButtonType(.momentaryChange)
        toolTip = label
        setAccessibilityLabel(label)
        translatesAutoresizingMaskIntoConstraints = false
        widthAnchor.constraint(equalToConstant: 30).isActive = true
        heightAnchor.constraint(equalToConstant: 30).isActive = true
        focusRingType = .exterior
    }
    required init?(coder: NSCoder) { fatalError("not used") }
    override var alignmentRectInsets: NSEdgeInsets { NSEdgeInsets() }
    override func draw(_ dirtyRect: NSRect) {
        let r = NSRect(x: 7, y: 7, width: 16, height: 16)
        switch kind {
        case .fill:
            color.setFill(); NSBezierPath(ovalIn: r).fill()
            NSColor(white: 0, alpha: 0.18).setStroke()
            let o = NSBezierPath(ovalIn: r.insetBy(dx: 0.5, dy: 0.5)); o.lineWidth = 1; o.stroke()
        case .stroke:
            color.setStroke()
            let o = NSBezierPath(ovalIn: r.insetBy(dx: 1.5, dy: 1.5)); o.lineWidth = 3; o.stroke()
        }
    }
}

/// The floating toolbar above the selection: fill, stroke, edit text, add connector, duplicate and more.
final class ContextBar: NSView {
    private weak var canvas: CanvasView?
    private let surface = FloatingSurface(radius: Tok.Radius.card)
    let fillSwatch = SwatchButton(kind: .fill, label: "Fill color")
    let strokeSwatch = SwatchButton(kind: .stroke, label: "Stroke color")
    let editText = IconButton(symbol: "textformat.alt", label: "Edit text", size: 30, pointSize: 13)
    let addConnector = IconButton(symbol: "arrow.up.right", label: "Add connector", size: 30, pointSize: 13)
    let duplicate = IconButton(symbol: "plus.square.on.square", label: "Duplicate", tip: "Duplicate (⌘D)", size: 30, pointSize: 13)
    let more = IconButton(symbol: "ellipsis", label: "More actions", size: 30, pointSize: 13)
    private let popover = NSPopover()
    private let presets = ColorPresetsView()
    private var pickTarget = SwatchButton.Kind.fill

    init(canvas: CanvasView) {
        self.canvas = canvas
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        setAccessibilityRole(.toolbar)
        setAccessibilityLabel("Selection actions")
        addSubview(surface)
        let divider = SurfaceView(frame: .zero)
        divider.fill = Tok.divider; divider.outline = nil; divider.radius = 0
        divider.translatesAutoresizingMaskIntoConstraints = false
        divider.widthAnchor.constraint(equalToConstant: 1).isActive = true
        divider.heightAnchor.constraint(equalToConstant: 18).isActive = true
        let row = NSStackView(views: [fillSwatch, strokeSwatch, divider, editText, addConnector, duplicate, more])
        row.spacing = 2
        row.edgeInsets = NSEdgeInsets(top: 4, left: 4, bottom: 4, right: 4)
        row.translatesAutoresizingMaskIntoConstraints = false
        row.setCustomSpacing(6, after: strokeSwatch); row.setCustomSpacing(6, after: divider)
        surface.addSubview(row)
        NSLayoutConstraint.activate([
            surface.leadingAnchor.constraint(equalTo: leadingAnchor), surface.trailingAnchor.constraint(equalTo: trailingAnchor),
            surface.topAnchor.constraint(equalTo: topAnchor), surface.bottomAnchor.constraint(equalTo: bottomAnchor),
            row.leadingAnchor.constraint(equalTo: surface.leadingAnchor), row.trailingAnchor.constraint(equalTo: surface.trailingAnchor),
            row.topAnchor.constraint(equalTo: surface.topAnchor), row.bottomAnchor.constraint(equalTo: surface.bottomAnchor),
        ])
        for (b, a) in [(fillSwatch as NSButton, #selector(pickFill(_:))), (strokeSwatch, #selector(pickStroke(_:))), (editText, #selector(doEditText(_:))),
                       (addConnector, #selector(doConnector(_:))), (duplicate, #selector(doDuplicate(_:))), (more, #selector(showMore(_:)))] {
            b.target = self; b.action = a
        }
        // The presets popover.
        let content = NSViewController()
        let holder = NSView(frame: NSRect(x: 0, y: 0, width: 264, height: 100))
        presets.translatesAutoresizingMaskIntoConstraints = false
        holder.addSubview(presets)
        NSLayoutConstraint.activate([
            presets.leadingAnchor.constraint(equalTo: holder.leadingAnchor, constant: 12), presets.topAnchor.constraint(equalTo: holder.topAnchor, constant: 12),
            presets.widthAnchor.constraint(equalToConstant: 240), presets.heightAnchor.constraint(equalToConstant: 76),
            holder.widthAnchor.constraint(equalToConstant: 264), holder.heightAnchor.constraint(equalToConstant: 100),
        ])
        content.view = holder
        popover.contentViewController = content
        popover.behavior = .transient
        presets.onPick = { [weak self] c in self?.applyPicked(c) }
    }
    required init?(coder: NSCoder) { fatalError("not used") }

    // MARK: Showing

    /// Whether the bar should be on screen for the current selection.
    var wantsToShow: Bool {
        guard let canvas else { return false }
        return !canvas.selectedShapes.isEmpty && canvas.tool == .select && !canvas.isEditingText
    }

    /// Updates the swatches, and places the bar above the selection (below it when there is no room), inside `container`.
    func update(in container: NSView) {
        guard let canvas, wantsToShow, let first = canvas.selectedShapes.first else { isHidden = true; return }
        isHidden = false
        fillSwatch.color = first.style.fill.kind == .none ? NSColor(white: 1, alpha: 0) : first.style.fill.color.ns
        strokeSwatch.color = first.style.stroke.visible ? first.style.stroke.color.ns : NSColor(white: 0.7, alpha: 1)
        editText.isEnabled = canvas.selection.count == 1
        let boxes = canvas.selectedShapes.map(\.worldBounds)
        let bounds = boxes.dropFirst().reduce(boxes[0]) { $0.union($1) }
        let rect = canvas.convert(bounds, to: container)
        container.layoutSubtreeIfNeeded()
        let size = fittingSize
        let margin: CGFloat = 46                                                      // room for the rotate knob (above) or the size badge (below)
        var x = rect.midX - size.width / 2
        // `container` is not flipped: y grows upward, so "above the selection" is a larger y.
        var y = rect.maxY + margin
        if container.isFlipped { y = rect.minY - margin - size.height }
        if y + size.height > container.bounds.height - 8 || y < 8 {
            y = container.isFlipped ? rect.maxY + margin : rect.minY - margin - size.height
        }
        x = min(max(x, 8), max(container.bounds.width - size.width - 8, 8))
        y = min(max(y, 8), max(container.bounds.height - size.height - 8, 8))
        frame = NSRect(x: x.rounded(), y: y.rounded(), width: size.width, height: size.height)
    }

    // MARK: Actions

    @objc private func pickFill(_ s: NSButton) { pickTarget = .fill; show(from: s) }
    @objc private func pickStroke(_ s: NSButton) { pickTarget = .stroke; show(from: s) }
    private func show(from button: NSButton) {
        presets.selectedColor = canvas?.selectedShapes.first.map { pickTarget == .fill ? $0.style.fill.color : $0.style.stroke.color }
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .maxY)
    }
    func applyPicked(_ c: RGBA) {
        switch pickTarget {
        case .fill: canvas?.applyStyle("Fill Color") { if $0.fill.kind == .none { $0.fill.kind = .solid }; if $0.fill.kind == .solid { $0.fill.color = c } }
        case .stroke: canvas?.applyStyle("Line Color") { $0.stroke.visible = true; $0.stroke.color = c }
        }
        popover.close()
    }
    @objc private func doEditText(_ s: Any?) { canvas?.editSelectedText() }
    @objc private func doConnector(_ s: Any?) { canvas?.tool = .connector; canvas?.window?.makeFirstResponder(canvas) }
    @objc private func doDuplicate(_ s: Any?) { canvas?.duplicate(nil) }
    @objc private func showMore(_ s: NSButton) {
        guard let canvas else { return }
        let menu = NSMenu()
        func add(_ title: String, _ action: Selector) { let i = NSMenuItem(title: title, action: action, keyEquivalent: ""); i.target = canvas; menu.addItem(i) }
        add("Bring to Front", #selector(CanvasView.bringToFront(_:)))
        add("Send to Back", #selector(CanvasView.sendToBack(_:)))
        menu.addItem(.separator())
        add("Group", #selector(CanvasView.group(_:)))
        add("Lock", #selector(CanvasView.lockSelection(_:)))
        menu.addItem(.separator())
        add("Delete", #selector(CanvasView.delete(_:)))
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: s.bounds.height + 4), in: s)
    }

    // MARK: For tests

    func press(_ label: String) {
        func find(_ v: NSView) -> NSButton? { (v as? NSButton).flatMap { $0.accessibilityLabel() == label ? $0 : nil } ?? v.subviews.lazy.compactMap(find).first }
        if let b = find(self) { _ = b.target?.perform(b.action, with: b) }
    }
    func choose(_ c: RGBA, for kind: SwatchButton.Kind) { pickTarget = kind; applyPicked(c) }
}
