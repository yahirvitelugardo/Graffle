import AppKit

enum Tool: Equatable {
    case select
    case shape(ShapeKind)
    case connector
    case pen
    /// Click to zoom in (Option-click to zoom out); drag a box to zoom to it.
    case zoom
}

final class CanvasView: NSView, NSTextFieldDelegate, NSMenuItemValidation {
    static let canvasSize = CGSize(width: 4000, height: 3000)
    static let pasteType = NSPasteboard.PasteboardType("mx.graffle.drawing")

    // MARK: State

    private(set) var drawing = Drawing() {
        didSet {
            let usable = interactiveLayerIDs
            var live = Set<UUID>()
            for s in drawing.shapes where usable.contains(s.layer) { live.insert(s.id) }
            for c in drawing.connectors where usable.contains(c.layer) { live.insert(c.id) }
            let pruned = selection.intersection(live)
            if pruned != selection { selection = pruned }
            needsDisplay = true
            onChange?()
        }
    }

    /// The selected ids in the order they were picked (the first is the reference for "Same Size").
    /// Objects that arrive together, as in a marquee or Select All, are ordered back to front.
    private(set) var selectionOrder: [UUID] = []

    var selection = Set<UUID>() {
        didSet {
            let added = selection.subtracting(oldValue)
            if !added.isEmpty || selectionOrder.count != selection.count {
                let z: (UUID) -> Int = { id in self.drawing.shapes.firstIndex { $0.id == id } ?? (self.drawing.shapes.count + 1) }
                selectionOrder = selectionOrder.filter(selection.contains) + added.sorted { z($0) < z($1) }
            }
            if let id = editingID, selection != [id] { endPathEdit() }
            needsDisplay = true
            syncActiveLayerToSelection()
            onSelectionChange?()
        }
    }

    var tool: Tool = .select {
        didSet {
            // Leaving the pen with a path half drawn keeps what was drawn; leaving select ends point editing.
            if oldValue == .pen, tool != .pen, penPath != nil { finishPen(closed: false, thenSelect: false) }
            if tool != .select { endPathEdit() }
            window?.invalidateCursorRects(for: self)
            needsDisplay = true
            onToolChange?()
        }
    }

    var showGrid = true { didSet { needsDisplay = true } }
    var snapToGrid = true
    var defaultStyle = Style()
    var isExporting = false

    var onChange: (() -> Void)?
    var onSelectionChange: (() -> Void)?
    var onToolChange: (() -> Void)?
    var onActiveLayerChange: (() -> Void)?

    private let gridSize: CGFloat = 10
    private let minSize: CGFloat = 12

    private enum Drag {
        case none
        case move(anchorOrigin: CGPoint, start: CGPoint, before: Drawing)
        case resize(id: UUID, handle: Int, before: Drawing)
        case rotate(id: UUID, before: Drawing)
        case pen                                                    // dragging handles out of the point just placed
        case pathAnchor(index: Int, last: CGPoint, before: Drawing) // moving an anchor in point-edit mode
        case pathHandle(index: Int, out: Bool, mirror: Bool, before: Drawing)
        case resizeGroup(handle: Int, start: CGRect, before: Drawing)
        case create(id: UUID, start: CGPoint, before: Drawing)
        case rubber(start: CGPoint, base: Set<UUID>)
        case connect(from: UUID)
        case zoom(start: CGPoint, out: Bool)
    }

    private var drag = Drag.none
    private var rubberRect: CGRect?
    private var connectPoint: CGPoint?
    private var connectTarget: UUID?
    private var pasteCount = 0

    // Pen tool: the path being drawn. Point editing: the path of the selected shape, in canvas coordinates.
    private(set) var penPath: PenPath?
    private var penCursor: CGPoint?
    private(set) var editingPath: PenPath?
    private var editingID: UUID?
    private(set) var selectedPoint: Int?

    /// An alignment line drawn while a move snaps to another shape.
    struct SmartGuide: Equatable {
        var vertical: Bool        // true: a vertical line at x = position
        var position: CGFloat
        var from: CGFloat
        var to: CGFloat
    }

    /// A bracket drawn across a gap that equals another gap, with the gap's size beside it.
    struct SpacingMark: Equatable {
        var horizontal: Bool      // true: the bracket runs left-right at y = `at`
        var from: CGFloat
        var to: CGFloat
        var at: CGFloat
    }

    private(set) var smartGuideLines: [SmartGuide] = []
    private(set) var smartSpacingMarks: [SpacingMark] = []

    /// Moves snap to the edges and centers of other shapes. Off with View -> Smart Guides, or hold Option.
    var smartGuides: Bool = UserDefaults.standard.object(forKey: "smartGuides") as? Bool ?? true {
        didSet { UserDefaults.standard.set(smartGuides, forKey: "smartGuides") }
    }

    private var coalesceKey: String?
    private var coalesceTime = Date.distantPast

    private enum EditTarget { case shape(UUID), connector(UUID) }
    private var editor: NSTextField?
    private var editTarget: EditTarget?
    private var editStartText = ""

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }

    private var zoom: CGFloat { enclosingScrollView?.magnification ?? 1 }

    // MARK: Layers

    private var storedActiveLayer: UUID?

    /// New objects go here. Falls back to the topmost layer if the stored one no longer exists.
    var activeLayerID: UUID {
        if let id = storedActiveLayer, drawing.layers.contains(where: { $0.id == id }) { return id }
        return drawing.layers[drawing.layers.count - 1].id
    }

    func setActiveLayer(_ id: UUID) {
        guard drawing.layer(id) != nil, storedActiveLayer != id else { return }
        storedActiveLayer = id
        onActiveLayerChange?()
    }

    private var interactiveLayerIDs: Set<UUID> {
        Set(drawing.layers.filter { $0.visible && !$0.locked }.map(\.id))
    }

    private func syncActiveLayerToSelection() {
        guard selection.count == 1, let id = selection.first else { return }
        let layer = drawing.shapes.first { $0.id == id }?.layer ?? drawing.connectors.first { $0.id == id }?.layer
        if let layer, layer != storedActiveLayer {
            storedActiveLayer = layer
            onActiveLayerChange?()
        }
    }

    func addLayer() {
        let name = "Layer \(drawing.layers.count + 1)"
        let layer = Layer(name: name)
        mutate("Add Layer") { d in
            if let i = d.layers.firstIndex(where: { $0.id == activeLayerID }) {
                d.layers.insert(layer, at: i + 1)
            } else {
                d.layers.append(layer)
            }
        }
        setActiveLayer(layer.id)
    }

    func deleteLayer(_ id: UUID) {
        guard drawing.layers.count > 1 else { return }
        mutate("Delete Layer") { d in
            d.layers.removeAll { $0.id == id }
            let gone = Set(d.shapes.filter { $0.layer == id }.map(\.id))
            d.shapes.removeAll { $0.layer == id }
            d.connectors.removeAll { $0.layer == id || gone.contains($0.from) || gone.contains($0.to) }
        }
    }

    /// `up` moves toward the front (later in the array).
    func moveLayer(_ id: UUID, up: Bool) {
        mutate("Reorder Layer") { d in
            guard let i = d.layers.firstIndex(where: { $0.id == id }) else { return }
            let j = up ? i + 1 : i - 1
            guard d.layers.indices.contains(j) else { return }
            d.layers.swapAt(i, j)
        }
    }

    func renameLayer(_ id: UUID, to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        mutate("Rename Layer") { d in
            if let i = d.layers.firstIndex(where: { $0.id == id }) { d.layers[i].name = trimmed }
        }
    }

    func setLayer(_ id: UUID, visible: Bool? = nil, locked: Bool? = nil) {
        mutate(visible != nil ? "Show/Hide Layer" : "Lock/Unlock Layer") { d in
            guard let i = d.layers.firstIndex(where: { $0.id == id }) else { return }
            if let v = visible { d.layers[i].visible = v }
            if let l = locked { d.layers[i].locked = l }
        }
    }

    func moveSelection(toLayer id: UUID) {
        guard drawing.layer(id) != nil, !selection.isEmpty else { return }
        mutate("Move to Layer") { d in
            for i in d.shapes.indices where selection.contains(d.shapes[i].id) { d.shapes[i].layer = id }
            for i in d.connectors.indices where selection.contains(d.connectors[i].id) { d.connectors[i].layer = id }
        }
        // Selection may now be on a hidden/locked layer; didSet pruned it if so.
    }

    // MARK: Document API

    func load(_ newDrawing: Drawing) {
        endEditing(commit: false)
        var d = newDrawing
        if d.layers.isEmpty { d.layers = [Layer(name: "Layer 1")] }
        let known = Set(d.layers.map(\.id))
        let fallback = d.layers[0].id
        for i in d.shapes.indices where !known.contains(d.shapes[i].layer) { d.shapes[i].layer = fallback }
        for i in d.connectors.indices where !known.contains(d.connectors[i].layer) { d.connectors[i].layer = fallback }
        selection = []
        storedActiveLayer = nil
        drawing = d
        undoManager?.removeAllActions()
        onActiveLayerChange?()
    }

    /// Registers an undo step that restores `old`; the undo handler registers the redo.
    private func commit(_ old: Drawing, _ name: String) {
        coalesceKey = nil
        undoManager?.registerUndo(withTarget: self) { view in
            let current = view.drawing
            view.drawing = old
            view.commit(current, name)
        }
        undoManager?.setActionName(name)
    }

    /// With `coalesce`, repeated edits of the same kind within a second (a slider drag, a color panel)
    /// collapse into a single undo step.
    private func mutate(_ name: String, coalesce: Bool = false, _ change: (inout Drawing) -> Void) {
        let old = drawing
        var new = drawing
        change(&new)
        guard new != old else { return }
        drawing = new
        if coalesce, coalesceKey == name, Date().timeIntervalSince(coalesceTime) < 1 {
            coalesceTime = Date()
            return
        }
        commit(old, name)
        coalesceKey = coalesce ? name : nil
        coalesceTime = Date()
    }

    func shape(_ id: UUID) -> Shape? { drawing.shapes.first { $0.id == id } }

    var hasLockedObjects: Bool { drawing.shapes.contains { $0.locked } || drawing.connectors.contains { $0.locked } }
    private var selectionHasLocked: Bool { selectedShapes.contains { $0.locked } || selectedConnectors.contains { $0.locked } }
    private var selectionHasUnlocked: Bool { selectedShapes.contains { !$0.locked } || selectedConnectors.contains { !$0.locked } }

    private func geometry(_ c: Connector) -> ConnectorGeometry? {
        guard let a = shape(c.from), let b = shape(c.to) else { return nil }
        return ConnectorGeometry.make(c, a, b)
    }

    // MARK: Style API (used by the inspector)

    var selectedShapes: [Shape] { drawing.shapes.filter { selection.contains($0.id) } }
    var selectedConnectors: [Connector] { drawing.connectors.filter { selection.contains($0.id) } }

    func currentStyle() -> Style {
        selectedShapes.first?.style ?? selectedConnectors.first?.style ?? defaultStyle
    }

    func applyStyle(_ name: String, _ change: @escaping (inout Style) -> Void) {
        if selection.isEmpty {
            change(&defaultStyle)
            return
        }
        mutate(name, coalesce: true) { d in
            for i in d.shapes.indices where selection.contains(d.shapes[i].id) { change(&d.shapes[i].style) }
            for i in d.connectors.indices where selection.contains(d.connectors[i].id) { change(&d.connectors[i].style) }
        }
    }

    func applyShapes(_ name: String, _ change: @escaping (inout Shape) -> Void) {
        mutate(name, coalesce: true) { d in
            for i in d.shapes.indices where selection.contains(d.shapes[i].id) && !d.shapes[i].locked { change(&d.shapes[i]) }
        }
    }

    func applyConnector(_ name: String, _ change: @escaping (inout Connector) -> Void) {
        mutate(name, coalesce: true) { d in
            for i in d.connectors.indices where selection.contains(d.connectors[i].id) && !d.connectors[i].locked { change(&d.connectors[i]) }
        }
    }

    // MARK: Themes

    /// Restyles every shape and connector, and the page, to `theme` (one undo step), and keeps it for new objects.
    func applyTheme(_ theme: ThemeDefinition) {
        mutate("Apply Theme") { theme.apply(to: &$0) }
        needsDisplay = true
    }

    // MARK: Drawing

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        (isExporting ? NSColor.white : Tok.canvasBG).setFill()
        dirtyRect.fill()

        if !isExporting && showGrid { drawGrid(ctx, dirtyRect) }

        for layer in drawing.layers where layer.visible {
            for c in drawing.connectors where c.layer == layer.id {
                guard let g = geometry(c) else { continue }
                drawConnector(c, g, in: ctx)
            }
            for s in drawing.shapes where s.layer == layer.id { drawShape(s, in: ctx) }
        }

        guard !isExporting else { return }
        drawOverlays(in: ctx)
    }

    /// Dots, one every 20 points (a theme can recolor them so they contrast with its shapes).
    private func drawGrid(_ ctx: CGContext, _ rect: CGRect) {
        let spacing = Tok.gridSpacing
        let custom = drawing.theme?.gridColor.flatMap { RGBA(hex: $0) }
        var color = custom?.cg ?? Tok.gridDot.cgColor
        effectiveAppearance.performAsCurrentDrawingAppearance { color = custom?.cg ?? Tok.gridDot.cgColor }
        let z = max(zoom, 0.01)
        let radius = max(0.9, 1.1 / z)
        guard spacing * z >= 6 else { return }                               // too small to be useful when zoomed far out
        ctx.saveGState()
        ctx.setFillColor(color)
        let x0 = floor(rect.minX / spacing) * spacing, y0 = floor(rect.minY / spacing) * spacing
        var y = y0
        while y <= rect.maxY {
            var x = x0
            while x <= rect.maxX { ctx.fillEllipse(in: CGRect(x: x - radius, y: y - radius, width: radius * 2, height: radius * 2)); x += spacing }
            y += spacing
        }
        ctx.restoreGState()
    }

    private func drawShape(_ s: Shape, in ctx: CGContext) {
        let st = s.style
        let path = s.path()
        let translucent = st.opacity < 0.999

        ctx.saveGState()
        if translucent {
            ctx.setAlpha(CGFloat(st.opacity))
            ctx.beginTransparencyLayer(auxiliaryInfo: nil)
        }

        // Shadow is applied to the fill+stroke group as a whole, so it is cast once.
        let shadowed = st.shadow.enabled && (st.fill.kind != .none || st.stroke.visible)
        if shadowed {
            ctx.setShadow(offset: st.shadow.vector,
                          blur: CGFloat(st.shadow.blur), color: st.shadow.color.cg)
            ctx.beginTransparencyLayer(auxiliaryInfo: nil)
        }
        ctx.saveGState()
        ctx.concatenate(s.rotationTransform)
        let seed = s.id.seed
        let rough = st.stroke.roughness > 0 && st.stroke.visible
        let outline = rough ? Render.roughened(path, amount: st.stroke.roughness, seed: seed) : path   // hand-drawn fills wobble with their edge
        if st.fill.kind != .none, st.effect == .neumorphic {
            Render.neumorphicShadows(ctx, path: outline, fill: st.fill, size: min(s.frame.width, s.frame.height))
        }
        Render.fill(ctx, path: outline, fill: st.fill)
        switch st.effect {
        case .crystal? where st.fill.kind != .none: Render.crystalGloss(ctx, path: path, frame: s.frame)
        case .glass? where st.fill.kind != .none: Render.glassSheen(ctx, path: path, frame: s.frame)
        case .clay? where st.fill.kind != .none: Render.clayShading(ctx, path: path)
        case .hatch?: Render.hatch(ctx, path: outline, frame: s.frame, color: Render.hatchColor(for: st.fill), seed: seed)
        default: break
        }
        if st.stroke.visible && st.stroke.width > 0 {
            if rough {
                Render.strokeRough(ctx, path: path, stroke: st.stroke, seed: seed)
            } else {
                ctx.saveGState()
                Render.applyStroke(ctx, st.stroke)
                ctx.addPath(path)
                ctx.strokePath()
                ctx.restoreGState()
            }
        }
        ctx.restoreGState()
        if shadowed { ctx.endTransparencyLayer() }

        if !s.text.isEmpty, !(editor != nil && isEditing(shape: s.id)) {
            ctx.saveGState()
            ctx.concatenate(s.rotationTransform)
            Render.drawText(s.text, in: s.frame.insetBy(dx: 8, dy: 4), format: st.text,
                            color: Render.textColor(st.text, fill: st.fill))
            ctx.restoreGState()
        }

        if translucent { ctx.endTransparencyLayer() }
        ctx.restoreGState()
    }

    private func drawConnector(_ c: Connector, _ g: ConnectorGeometry, in ctx: CGContext) {
        let st = c.style
        ctx.saveGState()
        if st.opacity < 0.999 { ctx.setAlpha(CGFloat(st.opacity)) }

        if selection.contains(c.id) && !isExporting {
            ctx.setStrokeColor(Tok.accent.withAlphaComponent(0.35).cgColor)
            ctx.setLineWidth(CGFloat(st.stroke.width) + 6)
            ctx.setLineCap(.round)
            ctx.addPath(g.path)
            ctx.strokePath()
        }
        if st.stroke.visible && st.stroke.width > 0 {
            ctx.saveGState()
            if st.shadow.enabled {
                ctx.setShadow(offset: st.shadow.vector,
                              blur: CGFloat(st.shadow.blur), color: st.shadow.color.cg)
            }
            if st.stroke.roughness > 0 {
                Render.strokeRough(ctx, path: g.path, stroke: st.stroke, seed: c.id.seed)
            } else {
                Render.applyStroke(ctx, st.stroke)
                ctx.addPath(g.path)
                ctx.strokePath()
            }
            ctx.restoreGState()
            Render.drawHead(ctx, kind: c.startHead, tip: g.startPoint, angle: g.startAngle, scale: c.headScale, stroke: st.stroke)
            Render.drawHead(ctx, kind: c.endHead, tip: g.endPoint, angle: g.endAngle, scale: c.headScale, stroke: st.stroke)
        }
        ctx.restoreGState()

        if !c.text.isEmpty, !(editor != nil && isEditing(connector: c.id)) {
            drawConnectorLabel(c, at: g.labelPoint)
        }
    }

    private func drawConnectorLabel(_ c: Connector, at p: CGPoint) {
        let color = c.style.text.color?.ns ?? .black
        let str = NSAttributedString(string: c.text, attributes: Render.attributes(c.style.text, color: color))
        let sz = str.size()
        let rect = CGRect(x: p.x - sz.width / 2 - 4, y: p.y - sz.height / 2 - 1, width: sz.width + 8, height: sz.height + 2)
        (isExporting ? NSColor.white : Tok.canvasBG).setFill()
        NSBezierPath(roundedRect: rect, xRadius: 3, yRadius: 3).fill()
        str.draw(at: CGPoint(x: rect.minX + 4, y: rect.minY + 1))
    }

    private func drawOverlays(in ctx: CGContext) {
        let accent = Tok.accent
        let z = max(zoom, 0.01)

        for s in selectedShapes where editingPath == nil {      // while editing points, the anchors are the outline
            ctx.saveGState()
            ctx.concatenate(s.rotationTransform)
            ctx.setStrokeColor(accent.cgColor)
            ctx.setLineWidth(1 / z)
            if selection.count > 1 { ctx.setLineDash(phase: 0, lengths: [4 / z, 3 / z]) }
            ctx.stroke(s.frame.insetBy(dx: -2 / z, dy: -2 / z))
            ctx.restoreGState()
        }

        if let b = groupBounds, !selectionHasLocked {          // a group with a locked member has no resize box
            ctx.setStrokeColor(accent.cgColor)
            ctx.setLineWidth(1 / z)
            ctx.stroke(b.insetBy(dx: -4 / z, dy: -4 / z))
            for r in handleRects(for: b.insetBy(dx: -4 / z, dy: -4 / z)) {
                ctx.setFillColor(NSColor.white.cgColor)
                ctx.fill(r)
                ctx.setStrokeColor(accent.cgColor)
                ctx.stroke(r)
            }
        }

        for s in selectedShapes where s.locked { drawLockBadge(on: s.worldBounds, in: ctx) }
        for c in selectedConnectors where c.locked {
            if let g = geometry(c) { drawLockBadge(on: CGRect(x: g.labelPoint.x, y: g.labelPoint.y, width: 0, height: 0), in: ctx) }
        }
        if !smartGuideLines.isEmpty {
            ctx.saveGState()
            ctx.setStrokeColor(Tok.guideSnap.cgColor)
            ctx.setLineWidth(1 / z)
            let pad = 8 / z
            for g in smartGuideLines {
                if g.vertical { ctx.move(to: CGPoint(x: g.position, y: g.from - pad)); ctx.addLine(to: CGPoint(x: g.position, y: g.to + pad)) }
                else { ctx.move(to: CGPoint(x: g.from - pad, y: g.position)); ctx.addLine(to: CGPoint(x: g.to + pad, y: g.position)) }
            }
            ctx.strokePath()
            ctx.restoreGState()
        }
        if !smartSpacingMarks.isEmpty { drawSpacingMarks(in: ctx) }
        if let pen = penPath { drawPen(pen, in: ctx) }
        if let edit = editingPath { drawPointEditing(edit, in: ctx) }

        if selection.count == 1, editingPath == nil, let s = selectedShapes.first, !s.locked {
            ctx.saveGState()
            ctx.concatenate(s.rotationTransform)
            let knob = rotateHandleRect(for: s.frame)
            ctx.setStrokeColor(accent.cgColor)
            ctx.setLineWidth(1 / z)
            ctx.move(to: CGPoint(x: s.frame.midX, y: s.frame.minY))
            ctx.addLine(to: CGPoint(x: knob.midX, y: knob.maxY))
            ctx.strokePath()
            ctx.setFillColor(accent.cgColor)
            ctx.fillEllipse(in: knob)
            for r in handleRects(for: s.frame) {
                ctx.setFillColor(NSColor.white.cgColor)
                ctx.fill(r)
                ctx.setStrokeColor(accent.cgColor)
                ctx.setLineWidth(1 / z)
                ctx.stroke(r)
            }
            ctx.restoreGState()
        }

        if let r = rubberRect {
            ctx.setFillColor(accent.withAlphaComponent(0.12).cgColor)
            ctx.fill(r)
            ctx.setStrokeColor(accent.cgColor)
            ctx.setLineWidth(1 / z)
            ctx.stroke(r)
        }

        if case .connect(let fromID) = drag, let from = shape(fromID), let p = connectPoint {
            let target = connectTarget.flatMap { shape($0) }
            let end = target?.boundaryPoint(toward: from.center) ?? p
            let start = from.boundaryPoint(toward: end)
            ctx.setStrokeColor(accent.cgColor)
            ctx.setLineWidth(2 / z)
            ctx.setLineDash(phase: 0, lengths: [6 / z, 4 / z])
            ctx.move(to: start); ctx.addLine(to: end)
            ctx.strokePath()
            if let t = target {
                ctx.setLineDash(phase: 0, lengths: [])
                ctx.addPath(t.worldPath())
                ctx.strokePath()
            }
        }
    }

    // MARK: Hit testing (topmost visible, unlocked layer first)

    private func handleRects(for f: CGRect) -> [CGRect] {
        let s = 8 / max(zoom, 0.01)
        let pts = [
            CGPoint(x: f.minX, y: f.minY), CGPoint(x: f.midX, y: f.minY), CGPoint(x: f.maxX, y: f.minY),
            CGPoint(x: f.maxX, y: f.midY), CGPoint(x: f.maxX, y: f.maxY), CGPoint(x: f.midX, y: f.maxY),
            CGPoint(x: f.minX, y: f.maxY), CGPoint(x: f.minX, y: f.midY),
        ]
        return pts.map { CGRect(x: $0.x - s / 2, y: $0.y - s / 2, width: s, height: s) }
    }

    /// The round knob above the top edge that rotates the shape.
    private func rotateHandleRect(for f: CGRect) -> CGRect {
        let z = max(zoom, 0.01), r = 5 / z
        return CGRect(x: f.midX - r, y: f.minY - 24 / z - r, width: r * 2, height: r * 2)
    }

    /// 0...7 are the resize handles, 8 is the rotation knob. `p` is in canvas coordinates.
    private func handleIndex(at p: CGPoint, for s: Shape) -> Int? {
        let lp = s.toLocal(p)
        let slop = 3 / max(zoom, 0.01)
        if rotateHandleRect(for: s.frame).insetBy(dx: -slop, dy: -slop).contains(lp) { return 8 }
        return handleRects(for: s.frame).firstIndex { $0.insetBy(dx: -slop, dy: -slop).contains(lp) }
    }

    private func hit(_ s: Shape, _ p: CGPoint) -> Bool {
        let lp = s.toLocal(p)
        switch s.kind {
        case .text:
            return s.frame.insetBy(dx: -4, dy: -4).contains(lp)
        case .path:
            // Lines have no inside to click, so also accept a click on the stroke itself.
            let path = s.path()
            if s.style.fill.kind != .none, path.contains(lp) { return true }
            let width = max(8, CGFloat(s.style.stroke.width) + 6) / max(zoom, 0.5)
            return path.copy(strokingWithWidth: width, lineCap: .round, lineJoin: .round, miterLimit: 10).contains(lp)
        default:
            return s.path().contains(lp)
        }
    }

    /// Every selectable shape that shares a group with `s` (or just `s`).
    private func groupMembers(of s: Shape) -> Set<UUID> {
        guard let g = s.group else { return [s.id] }
        let usable = interactiveLayerIDs
        return Set(drawing.shapes.filter { $0.group == g && usable.contains($0.layer) }.map(\.id))
    }

    private func expandGroups(_ ids: Set<UUID>) -> Set<UUID> {
        var out = ids
        for s in drawing.shapes where ids.contains(s.id) { out.formUnion(groupMembers(of: s)) }
        return out
    }

    private func shapeIndex(at p: CGPoint) -> Int? {
        for layer in drawing.layers.reversed() where layer.visible && !layer.locked {
            for i in drawing.shapes.indices.reversed() where drawing.shapes[i].layer == layer.id && hit(drawing.shapes[i], p) {
                return i
            }
        }
        return nil
    }

    private func connectorIndex(at p: CGPoint) -> Int? {
        for layer in drawing.layers.reversed() where layer.visible && !layer.locked {
            for i in drawing.connectors.indices.reversed() where drawing.connectors[i].layer == layer.id {
                let c = drawing.connectors[i]
                guard let g = geometry(c) else { continue }
                let width = max(10, CGFloat(c.style.stroke.width) + 8) / max(zoom, 0.5)
                if g.path.copy(strokingWithWidth: width, lineCap: .round, lineJoin: .round, miterLimit: 10).contains(p) {
                    return i
                }
            }
        }
        return nil
    }

    private func snap(_ p: CGPoint) -> CGPoint {
        guard snapToGrid else { return p }
        return CGPoint(x: (p.x / gridSize).rounded() * gridSize, y: (p.y / gridSize).rounded() * gridSize)
    }

    private func normalizedRect(_ a: CGPoint, _ b: CGPoint) -> CGRect {
        CGRect(x: min(a.x, b.x), y: min(a.y, b.y), width: abs(a.x - b.x), height: abs(a.y - b.y))
    }

    private func resized(_ f: CGRect, handle h: Int, to p: CGPoint) -> CGRect {
        var minX = f.minX, maxX = f.maxX, minY = f.minY, maxY = f.maxY
        if [0, 6, 7].contains(h) { minX = min(p.x, maxX - minSize) }
        if [2, 3, 4].contains(h) { maxX = max(p.x, minX + minSize) }
        if [0, 1, 2].contains(h) { minY = min(p.y, maxY - minSize) }
        if [4, 5, 6].contains(h) { maxY = max(p.y, minY + minSize) }
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    // MARK: Resizing several shapes as one

    /// On-screen bounds of the selected shapes when two or more are selected (the group's box).
    private var groupBounds: CGRect? {
        let sel = selectedShapes
        guard sel.count >= 2 else { return nil }
        return sel.map(\.worldBounds).reduce(nil) { acc, r in acc.map { $0.union(r) } ?? r }
    }

    /// The group's handles sit just outside its box so they don't cover the shapes on its edge.
    private func groupHandleIndex(at p: CGPoint) -> Int? {
        guard let b = groupBounds else { return nil }
        let z = max(zoom, 0.01), slop = 3 / z
        return handleRects(for: b.insetBy(dx: -4 / z, dy: -4 / z)).firstIndex { $0.insetBy(dx: -slop, dy: -slop).contains(p) }
    }

    /// A rectangle of the given size whose corner opposite `handle` stays where it was in `start`.
    private func anchoredRect(_ start: CGRect, handle h: Int, width w: CGFloat, height ht: CGFloat) -> CGRect {
        switch h {
        case 0: return CGRect(x: start.maxX - w, y: start.maxY - ht, width: w, height: ht)
        case 2: return CGRect(x: start.minX, y: start.maxY - ht, width: w, height: ht)
        case 6: return CGRect(x: start.maxX - w, y: start.minY, width: w, height: ht)
        default: return CGRect(x: start.minX, y: start.minY, width: w, height: ht)
        }
    }

    /// Maps every selected shape from the box `old` into the box `new`.
    /// Shapes turned by a quarter turn swap which axis scales their width; other angles scale evenly,
    /// because a rotated shape can't be sheared.
    private func scaled(_ before: Drawing, from old: CGRect, to new: CGRect) -> Drawing {
        let sx = new.width / old.width, sy = new.height / old.height
        var d = before
        for i in d.shapes.indices where selection.contains(d.shapes[i].id) && !d.shapes[i].locked {
            let s = d.shapes[i]
            let c = s.center
            let nc = CGPoint(x: new.minX + (c.x - old.minX) * sx, y: new.minY + (c.y - old.minY) * sy)
            var w = s.frame.width, h = s.frame.height
            let turns = Int((s.rotation / 90).rounded())
            if abs(s.rotation - Double(turns) * 90) < 0.01 {
                if turns % 2 == 0 { w *= sx; h *= sy } else { w *= sy; h *= sx }
            } else {
                let u = sqrt(sx * sy)
                w *= u; h *= u
            }
            w = max(w, 4); h = max(h, 4)
            d.shapes[i].frame = CGRect(x: nc.x - w / 2, y: nc.y - h / 2, width: w, height: h)
        }
        return d
    }

    /// Resizes `s` by dragging `handle` to canvas point `p`. The opposite edge stays put on screen even when rotated.
    private func resizedFrame(of s: Shape, handle h: Int, to p: CGPoint, gridSnap: Bool = true) -> CGRect {
        let f = s.frame
        guard s.rotation != 0 else { return resized(f, handle: h, to: gridSnap ? snap(p) : p) }

        let local = s.toLocal(p)
        let nf = resized(f, handle: h, to: gridSnap ? snap(local) : local)
        func anchor(_ r: CGRect) -> CGPoint {
            CGPoint(x: [0, 6, 7].contains(h) ? r.maxX : ([2, 3, 4].contains(h) ? r.minX : r.midX),
                    y: [0, 1, 2].contains(h) ? r.maxY : ([4, 5, 6].contains(h) ? r.minY : r.midY))
        }
        let anchorWorld = s.toWorld(anchor(f))
        let a = anchor(nf)
        let vx = nf.midX - a.x, vy = nf.midY - a.y
        let r = s.radians
        let center = CGPoint(x: anchorWorld.x + vx * cos(r) - vy * sin(r), y: anchorWorld.y + vx * sin(r) + vy * cos(r))
        return CGRect(x: center.x - nf.width / 2, y: center.y - nf.height / 2, width: nf.width, height: nf.height)
    }

    // MARK: Mouse

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        let p = convert(event.locationInWindow, from: nil)

        switch tool {
        case .select: selectMouseDown(p, event)
        case .shape(let kind): beginCreate(kind, at: p, modifiers: event.modifierFlags)
        case .connector:
            if let i = shapeIndex(at: p) {
                drag = .connect(from: drawing.shapes[i].id)
                connectPoint = p
            }
        case .pen:
            penMouseDown(p, event)
        case .zoom:
            drag = .zoom(start: p, out: event.modifierFlags.contains(.option))
        }
    }

    private func selectMouseDown(_ p: CGPoint, _ event: NSEvent) {
        let shift = event.modifierFlags.contains(.shift)

        if editingPath != nil, pathEditMouseDown(p, event) { return }

        if !selectionHasLocked, let h = groupHandleIndex(at: p), let b = groupBounds {
            drag = .resizeGroup(handle: h, start: b, before: drawing)
            return
        }
        if selection.count == 1, let s = selectedShapes.first, !s.locked, let h = handleIndex(at: p, for: s) {
            drag = h == 8 ? .rotate(id: s.id, before: drawing) : .resize(id: s.id, handle: h, before: drawing)
            return
        }
        if let i = shapeIndex(at: p) {
            let s = drawing.shapes[i]
            if event.clickCount == 2 {
                selection = [s.id]
                // A drawn path has points to edit; every other shape has text.
                if s.kind == .path { beginPathEdit(s.id) } else { beginEditing(.shape(s.id)) }
                return
            }
            let members = groupMembers(of: s)
            if shift {
                if selection.contains(s.id) { selection.subtract(members); return }
                selection.formUnion(members)
            } else if !selection.contains(s.id) {
                selection = members
            }
            drag = .move(anchorOrigin: s.frame.origin, start: p, before: drawing)
        } else if let i = connectorIndex(at: p) {
            let c = drawing.connectors[i]
            if event.clickCount == 2 {
                selection = [c.id]
                beginEditing(.connector(c.id))
                return
            }
            if shift {
                if selection.contains(c.id) { selection.remove(c.id) } else { selection.insert(c.id) }
            } else {
                selection = [c.id]
            }
        } else {
            if !shift { selection = [] }
            drag = .rubber(start: p, base: selection)
        }
    }

    private func beginCreate(_ kind: ShapeKind, at p: CGPoint, modifiers: NSEvent.ModifierFlags = []) {
        var start = snap(p)
        if smartGuides, !modifiers.contains(.option) {
            start = snapPoint(start, x: true, y: true, targets: guideTargets(excluding: []))   // line the first corner up too
        }
        var s = Shape(layer: activeLayerID, kind: kind,
                      frame: CGRect(origin: start, size: CGSize(width: 1, height: 1)))
        if kind == .text {
            s.style = .textBox
            s.style.text = defaultStyle.text
        } else {
            s.style = defaultStyle
            if kind == .rounded && s.style.cornerRadius == 0 { s.style.cornerRadius = 12 }
            if let theme = drawing.theme { theme.apply(to: &s.style, kind: kind) }
        }
        let before = drawing
        drawing.shapes.append(s)
        selection = [s.id]
        drag = .create(id: s.id, start: start, before: before)
    }

    override func mouseDragged(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)

        switch drag {
        case .none:
            break

        case .move(let origin, let start, let before):
            let target = snap(CGPoint(x: origin.x + p.x - start.x, y: origin.y + p.y - start.y))
            var dx = target.x - origin.x, dy = target.y - origin.y
            smartGuideLines = []
            smartSpacingMarks = []
            if smartGuides, !event.modifierFlags.contains(.option) {
                let snapped = guideSnap(before: before, dx: dx, dy: dy)
                dx = snapped.dx; dy = snapped.dy
                smartGuideLines = snapped.lines
                smartSpacingMarks = snapped.marks
            }
            var d = before
            for i in d.shapes.indices where selection.contains(d.shapes[i].id) && !d.shapes[i].locked {
                d.shapes[i].frame.origin.x += dx
                d.shapes[i].frame.origin.y += dy
            }
            drawing = d

        case .resize(let id, let handle, let before):
            var d = before
            smartGuideLines = []
            if let i = d.shapes.firstIndex(where: { $0.id == id }) {
                // A rotated shape's edges don't run along the axes, so guides apply only to upright ones.
                if smartGuides, !event.modifierFlags.contains(.option), d.shapes[i].rotation == 0 {
                    let targets = guideTargets(excluding: [id], in: before)
                    let axes = movedAxes(handle: handle)
                    let target = snapPoint(snap(p), x: axes.x, y: axes.y, targets: targets)
                    d.shapes[i].frame = resizedFrame(of: d.shapes[i], handle: handle, to: target, gridSnap: false)
                    smartGuideLines = guideLines(for: d.shapes[i].frame, targets: targets)
                } else {
                    d.shapes[i].frame = resizedFrame(of: d.shapes[i], handle: handle, to: p)
                }
            }
            drawing = d

        case .pen:
            guard var pen = penPath, let i = pen.points.indices.last else { break }
            let a = pen.points[i].anchor
            if hypot(p.x - a.x, p.y - a.y) >= 3 {
                // Dragging out of a new point pulls a handle forward and its mirror image backward: a smooth point.
                pen.points[i].handleOut = p
                pen.points[i].handleIn = CGPoint(x: 2 * a.x - p.x, y: 2 * a.y - p.y)
            } else {
                pen.points[i].handleOut = nil
                pen.points[i].handleIn = nil
            }
            penPath = pen
            needsDisplay = true

        case .pathAnchor(let index, let last, let before):
            guard var path = editingPath else { break }
            path.moveAnchor(index, by: CGSize(width: p.x - last.x, height: p.y - last.y))
            drag = .pathAnchor(index: index, last: p, before: before)
            applyEditedPath(path)

        case .pathHandle(let index, let out, let mirror, _):
            guard var path = editingPath else { break }
            path.setHandle(index, out: out, to: p, mirror: mirror && !event.modifierFlags.contains(.option))
            applyEditedPath(path)

        case .resizeGroup(let handle, let start, let before):
            // The handle sits 4 pt outside the box; subtract that so the edge follows the pointer exactly.
            let z = max(zoom, 0.01)
            let outer = handleRects(for: start.insetBy(dx: -4 / z, dy: -4 / z))[handle], inner = handleRects(for: start)[handle]
            let target = CGPoint(x: p.x - (outer.midX - inner.midX), y: p.y - (outer.midY - inner.midY))
            smartGuideLines = []
            var edge = snap(target)
            let useGuides = smartGuides && !event.modifierFlags.contains(.option)
            let targets = useGuides ? guideTargets(excluding: selection, in: before) : []
            if useGuides {
                let axes = movedAxes(handle: handle)
                edge = snapPoint(edge, x: axes.x, y: axes.y, targets: targets)
            }
            var nb = resized(start, handle: handle, to: edge)
            if event.modifierFlags.contains(.shift), [0, 2, 4, 6].contains(handle) {
                // Corner + Shift keeps the proportions, driven by whichever axis moved more.
                let k = max(nb.width / start.width, nb.height / start.height)
                nb = anchoredRect(start, handle: handle, width: start.width * k, height: start.height * k)
            }
            if useGuides { smartGuideLines = guideLines(for: nb, targets: targets) }
            drawing = scaled(before, from: start, to: nb)

        case .rotate(let id, let before):
            var d = before
            if let i = d.shapes.firstIndex(where: { $0.id == id }) {
                let c = d.shapes[i].center
                var deg = atan2(p.y - c.y, p.x - c.x) * 180 / .pi + 90   // the knob sits above the shape
                if event.modifierFlags.contains(.shift) { deg = (deg / 15).rounded() * 15 }
                deg = deg.truncatingRemainder(dividingBy: 360)
                if deg < 0 { deg += 360 }
                d.shapes[i].rotation = Double(deg)
            }
            drawing = d

        case .create(let id, let start, _):
            if let i = drawing.shapes.firstIndex(where: { $0.id == id }) {
                var end = snap(p)
                smartGuideLines = []
                let useGuides = smartGuides && !event.modifierFlags.contains(.option)
                let targets = useGuides ? guideTargets(excluding: [id]) : []
                if useGuides { end = snapPoint(end, x: true, y: true, targets: targets) }
                let r = normalizedRect(start, end)
                drawing.shapes[i].frame = CGRect(x: r.minX, y: r.minY, width: max(r.width, 1), height: max(r.height, 1))
                if useGuides { smartGuideLines = guideLines(for: drawing.shapes[i].frame, targets: targets) }
            }

        case .rubber(let start, let base):
            let r = normalizedRect(start, p)
            rubberRect = r
            // A click that wobbles a pixel or two isn't a marquee; without this it would pick up any shape
            // whose bounding box happens to contain the point (corners of diamonds, diagonal lines...).
            guard r.width >= 3 || r.height >= 3 else { selection = base; break }
            let usable = interactiveLayerIDs
            let inside = drawing.shapes.filter { usable.contains($0.layer) && $0.worldBounds.intersects(r) }.map(\.id)
            selection = base.union(expandGroups(Set(inside)))

        case .zoom(let start, _):
            rubberRect = normalizedRect(start, p)

        case .connect(let from):
            connectPoint = p
            if let i = shapeIndex(at: p), drawing.shapes[i].id != from {
                connectTarget = drawing.shapes[i].id
            } else {
                connectTarget = nil
            }
            needsDisplay = true
        }
    }

    override func mouseUp(with event: NSEvent) {
        defer {
            drag = .none
            smartGuideLines = []
            smartSpacingMarks = []
            rubberRect = nil
            connectPoint = nil
            connectTarget = nil
            needsDisplay = true
        }

        switch drag {
        case .move(_, _, let before):
            if drawing != before { commit(before, "Move") }

        case .resize(_, _, let before):
            if drawing != before { commit(before, "Resize") }

        case .rotate(_, let before):
            if drawing != before { commit(before, "Rotate") }

        case .pen:
            break   // the point stays; the path is finished with Return, a double click, Esc or a click on its first point

        case .pathAnchor(_, _, let before), .pathHandle(_, _, _, let before):
            if drawing != before { commit(before, "Edit Path") }

        case .resizeGroup(_, _, let before):
            if drawing != before { commit(before, "Resize Group") }

        case .create(let id, let start, let before):
            guard let i = drawing.shapes.firstIndex(where: { $0.id == id }) else { return }
            var f = drawing.shapes[i].frame
            if f.width < 8 && f.height < 8 {
                let isText = drawing.shapes[i].kind == .text
                f = CGRect(origin: start, size: isText ? CGSize(width: 120, height: 32) : CGSize(width: 120, height: 72))
            }
            f.size.width = max(f.width, minSize)
            f.size.height = max(f.height, minSize)
            drawing.shapes[i].frame = f
            commit(before, "Add Shape")
            let isText = drawing.shapes[i].kind == .text
            tool = .select
            if isText { beginEditing(.shape(id)) }

        case .connect(let from):
            if let to = connectTarget {
                var c = Connector(layer: activeLayerID, from: from, to: to)
                c.style = defaultConnectorStyle
                if let theme = drawing.theme { theme.applyToConnector(&c.style) }
                mutate("Add Connector") { $0.connectors.append(c) }
                selection = [c.id]
            }
            tool = .select

        case .zoom(let start, let out):
            let p = convert(event.locationInWindow, from: nil)
            let r = rubberRect ?? normalizedRect(start, p)
            rubberRect = nil
            if out || r.width < 6 || r.height < 6 { zoomStep(out: out, around: p) } else { zoom(toFit: r) }
            needsDisplay = true

        case .rubber, .none:
            break
        }
    }

    /// New connectors inherit the stroke the user last picked, but never a fill.
    private var defaultConnectorStyle: Style {
        var s = Style.connector
        s.stroke.width = defaultStyle.stroke.width
        return s
    }

    // MARK: Keyboard

    override func keyDown(with event: NSEvent) {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)

        if penPath != nil {
            switch event.keyCode {
            case 36, 76: finishPen(closed: false); return                       // Return / Enter
            case 53: finishPen(closed: false); return                           // Esc keeps what is drawn
            case 51, 117:                                                       // Delete takes back the last point
                penPath?.points.removeLast()
                if penPath?.points.isEmpty == true { penPath = nil; penCursor = nil }
                needsDisplay = true
                return
            default: break
            }
        }
        if editingPath != nil {
            switch event.keyCode {
            case 36, 76, 53: endPathEdit(); return
            case 51, 117: deleteSelectedPoint(); return
            default: break
            }
        } else if event.keyCode == 36, selection.count == 1, let s = selectedShapes.first, s.kind == .path {
            beginPathEdit(s.id)
            return
        }

        switch event.keyCode {
        case 51, 117: delete(nil)
        case 123: nudge(-1, 0, big: flags.contains(.shift))
        case 124: nudge(1, 0, big: flags.contains(.shift))
        case 125: nudge(0, 1, big: flags.contains(.shift))
        case 126: nudge(0, -1, big: flags.contains(.shift))
        case 53:
            tool = .select
            selection = []
        default:
            guard flags.subtracting(.shift).isEmpty, let ch = event.charactersIgnoringModifiers?.lowercased() else {
                super.keyDown(with: event)
                return
            }
            switch ch {
            case "v": tool = .select
            case "r": tool = .shape(.rectangle)
            case "u": tool = .shape(.rounded)
            case "e": tool = .shape(.ellipse)
            case "d": tool = .shape(.diamond)
            case "g": tool = .shape(.triangle)
            case "t": tool = .shape(.text)
            case "c": tool = .connector
            case "p": tool = .pen
            case "z": tool = .zoom
            default: super.keyDown(with: event)
            }
        }
    }

    private func nudge(_ dx: CGFloat, _ dy: CGFloat, big: Bool) {
        let step: CGFloat = big ? gridSize : 1
        mutate("Nudge") { d in
            for i in d.shapes.indices where selection.contains(d.shapes[i].id) && !d.shapes[i].locked {
                d.shapes[i].frame.origin.x += dx * step
                d.shapes[i].frame.origin.y += dy * step
            }
        }
    }

    // MARK: Text editing

    private func isEditing(shape id: UUID) -> Bool {
        if case .shape(let e)? = editTarget { return e == id }
        return false
    }

    private func isEditing(connector id: UUID) -> Bool {
        if case .connector(let e)? = editTarget { return e == id }
        return false
    }

    private func beginEditing(_ target: EditTarget) {
        endEditing(commit: true)

        let rect: CGRect, text: String, format: TextFormat, color: NSColor
        switch target {
        case .shape(let id):
            guard let s = shape(id), !s.locked else { NSSound.beep(); return }
            format = s.style.text
            let lineH = CGFloat(format.size) * 1.6
            rect = CGRect(x: s.frame.minX + 6, y: s.frame.midY - lineH / 2, width: max(s.frame.width - 12, 20), height: lineH)
            text = s.text
            color = Render.textColor(format, fill: s.style.fill)
        case .connector(let id):
            guard let c = drawing.connectors.first(where: { $0.id == id }), !c.locked, let g = geometry(c) else { NSSound.beep(); return }
            format = c.style.text
            let lineH = CGFloat(format.size) * 1.6
            rect = CGRect(x: g.labelPoint.x - 60, y: g.labelPoint.y - lineH / 2, width: 120, height: lineH)
            text = c.text
            color = format.color?.ns ?? .black
        }

        let field = NSTextField(frame: rect)
        field.stringValue = text
        field.font = Render.font(format)
        switch format.hAlign {
        case .left: field.alignment = .left
        case .center: field.alignment = .center
        case .right: field.alignment = .right
        }
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.textColor = color
        field.delegate = self
        addSubview(field)

        editor = field
        editTarget = target
        editStartText = text
        needsDisplay = true
        window?.makeFirstResponder(field)
    }

    private func endEditing(commit shouldCommit: Bool) {
        guard let field = editor, let target = editTarget else { return }
        let newText = field.stringValue
        editor = nil
        editTarget = nil
        field.removeFromSuperview()
        window?.makeFirstResponder(self)

        if shouldCommit, newText != editStartText {
            mutate("Edit Text") { d in
                switch target {
                case .shape(let id): if let i = d.shapes.firstIndex(where: { $0.id == id }) { d.shapes[i].text = newText }
                case .connector(let id): if let i = d.connectors.firstIndex(where: { $0.id == id }) { d.connectors[i].text = newText }
                }
            }
        }
        needsDisplay = true
    }

    func controlTextDidEndEditing(_ obj: Notification) { endEditing(commit: true) }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        if commandSelector == #selector(NSResponder.cancelOperation(_:)) {
            endEditing(commit: false)
            return true
        }
        return false
    }

    // MARK: Edit actions

    @objc func undo(_ sender: Any?) { coalesceKey = nil; undoManager?.undo() }
    @objc func redo(_ sender: Any?) { coalesceKey = nil; undoManager?.redo() }

    override func selectAll(_ sender: Any?) {
        let usable = interactiveLayerIDs
        selection = Set(drawing.shapes.filter { usable.contains($0.layer) }.map(\.id))
    }

    @objc func delete(_ sender: Any?) {
        guard !selection.isEmpty else { return }
        mutate("Delete") { d in
            // Locked objects stay; connectors go with any shape that is deleted.
            let removedShapes = Set(d.shapes.filter { selection.contains($0.id) && !$0.locked }.map(\.id))
            d.shapes.removeAll { removedShapes.contains($0.id) }
            d.connectors.removeAll {
                (selection.contains($0.id) && !$0.locked) || removedShapes.contains($0.from) || removedShapes.contains($0.to)
            }
        }
    }

    private func selectionSubset() -> Drawing {
        let ids = Set(selectedShapes.map(\.id))
        var sub = Drawing()
        sub.layers = drawing.layers
        sub.shapes = drawing.shapes.filter { ids.contains($0.id) }
        sub.connectors = drawing.connectors.filter { ids.contains($0.from) && ids.contains($0.to) }
        return sub
    }

    private func insert(_ sub: Drawing, offset: CGFloat) {
        var map: [UUID: UUID] = [:]
        var groupMap: [UUID: UUID] = [:]
        var newIDs = Set<UUID>()
        let active = activeLayerID
        mutate("Paste") { d in
            // Keep the original layer when it exists here; otherwise drop objects on the active layer.
            func target(_ layer: UUID) -> UUID { d.layer(layer) != nil ? layer : active }
            for var s in sub.shapes {
                let old = s.id
                s.id = UUID()
                s.locked = false
                s.layer = target(s.layer)
                if let g = s.group {
                    if groupMap[g] == nil { groupMap[g] = UUID() }
                    s.group = groupMap[g]
                }
                map[old] = s.id
                s.frame.origin.x += offset
                s.frame.origin.y += offset
                d.shapes.append(s)
                newIDs.insert(s.id)
            }
            for var c in sub.connectors {
                guard let f = map[c.from], let t = map[c.to] else { continue }
                c.id = UUID(); c.from = f; c.to = t
                c.locked = false
                c.layer = target(c.layer)
                d.connectors.append(c)
                newIDs.insert(c.id)
            }
        }
        selection = newIDs
    }

    @objc func copy(_ sender: Any?) {
        guard !selection.isEmpty, let data = try? JSONEncoder().encode(selectionSubset()) else { return }
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setData(data, forType: Self.pasteType)
        pasteCount = 0
    }

    @objc func cut(_ sender: Any?) {
        copy(nil)
        delete(nil)
    }

    @objc func paste(_ sender: Any?) {
        guard let data = NSPasteboard.general.data(forType: Self.pasteType),
              let sub = try? JSONDecoder().decode(Drawing.self, from: data) else { return }
        pasteCount += 1
        insert(sub, offset: CGFloat(pasteCount) * 20)
    }

    @objc func duplicate(_ sender: Any?) {
        guard !selection.isEmpty else { return }
        insert(selectionSubset(), offset: 20)
    }

    /// A small padlock at the top-right of a locked object, drawn only while it is selected.
    private func drawLockBadge(on bounds: CGRect, in ctx: CGContext) {
        let z = max(zoom, 0.01), u = 1 / z
        let w = 12 * u, h = 9 * u
        let body = CGRect(x: bounds.maxX + 4 * u, y: bounds.minY - h - 6 * u, width: w, height: h)
        let accent = Tok.accent.cgColor
        ctx.saveGState()
        ctx.setFillColor(accent)
        ctx.addPath(CGPath(roundedRect: body, cornerWidth: 2 * u, cornerHeight: 2 * u, transform: nil))
        ctx.fillPath()
        ctx.setStrokeColor(accent)
        ctx.setLineWidth(1.6 * u)
        ctx.addArc(center: CGPoint(x: body.midX, y: body.minY), radius: 3.4 * u, startAngle: .pi, endAngle: 0, clockwise: false)
        ctx.strokePath()
        ctx.restoreGState()
    }

    // MARK: Pen tool

    private func penMouseDown(_ p: CGPoint, _ event: NSEvent) {
        let z = max(zoom, 0.01)
        if var pen = penPath {
            if event.clickCount >= 2 {
                // The first click of a double click already placed the last point; the second just ends the path.
                finishPen(closed: false)
                return
            }
            if pen.points.count >= 2, let first = pen.points.first, hypot(first.anchor.x - p.x, first.anchor.y - p.y) <= 8 / z {
                finishPen(closed: true)      // a click on the first point closes the shape
                return
            }
            pen.points.append(PenPoint(anchor: p))
            penPath = pen
        } else {
            penPath = PenPath(points: [PenPoint(anchor: p)])
        }
        penCursor = p
        drag = .pen
        needsDisplay = true
    }

    /// Turns the path being drawn into a shape (one undo step). Fewer than two points is discarded.
    func finishPen(closed: Bool, thenSelect: Bool = true) {
        guard var pen = penPath else { return }
        penPath = nil
        penCursor = nil
        pen.closed = closed
        defer { needsDisplay = true }
        guard pen.points.count >= 2, let o = pen.outline() else {
            if thenSelect { tool = .select }
            return
        }
        var style = defaultStyle
        if !closed { style.fill.kind = .none }          // an open curve has nothing to fill
        style.stroke.visible = true
        if style.stroke.width <= 0 { style.stroke.width = 1.5 }
        if let theme = drawing.theme { theme.apply(to: &style, kind: .path) }
        let shape = Shape(layer: activeLayerID, kind: .path, frame: o.frame, style: style, outline: o.segments)
        mutate("Draw Path") { $0.shapes.append(shape) }
        if thenSelect {
            tool = .select
            selection = [shape.id]
        }
    }

    override func mouseMoved(with event: NSEvent) {
        guard penPath != nil else { return }
        penCursor = convert(event.locationInWindow, from: nil)
        needsDisplay = true
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for a in trackingAreas { removeTrackingArea(a) }
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseMoved, .activeInKeyWindow, .inVisibleRect],
                                       owner: self, userInfo: nil))
    }

    override func resetCursorRects() {
        if tool == .pen { addCursorRect(visibleRect, cursor: .crosshair) }
        if tool == .zoom { addCursorRect(visibleRect, cursor: Self.zoomCursor) }
    }

    private func drawAnchor(_ p: CGPoint, selected: Bool, hot: Bool = false, in ctx: CGContext) {
        let z = max(zoom, 0.01), s = (hot ? 9 : 6) / z
        let r = CGRect(x: p.x - s / 2, y: p.y - s / 2, width: s, height: s)
        ctx.setFillColor((selected || hot ? Tok.accent : NSColor.white).cgColor)
        ctx.fill(r)
        ctx.setStrokeColor(Tok.accent.cgColor)
        ctx.setLineWidth(1 / z)
        ctx.stroke(r)
    }

    private func drawHandle(from a: CGPoint, to h: CGPoint, in ctx: CGContext) {
        let z = max(zoom, 0.01), r = 3.5 / z
        ctx.setStrokeColor(Tok.accent.cgColor)
        ctx.setLineWidth(1 / z)
        ctx.move(to: a); ctx.addLine(to: h)
        ctx.strokePath()
        ctx.setFillColor(NSColor.white.cgColor)
        let dot = CGRect(x: h.x - r, y: h.y - r, width: r * 2, height: r * 2)
        ctx.fillEllipse(in: dot)
        ctx.strokeEllipse(in: dot)
    }

    private func drawPen(_ pen: PenPath, in ctx: CGContext) {
        let z = max(zoom, 0.01)
        ctx.saveGState()
        ctx.setStrokeColor(Tok.accent.cgColor)
        ctx.setLineWidth(1.5 / z)
        ctx.setLineJoin(.round)
        ctx.addPath(pen.cgPath(extendingTo: penCursor))
        ctx.strokePath()
        ctx.restoreGState()

        if let last = pen.points.last {
            if let h = last.handleOut { drawHandle(from: last.anchor, to: h, in: ctx) }
            if let h = last.handleIn { drawHandle(from: last.anchor, to: h, in: ctx) }
        }
        // The first point grows when the pointer is over it: clicking there closes the shape.
        let nearFirst = pen.points.count >= 2 && penCursor.map {
            hypot(pen.points[0].anchor.x - $0.x, pen.points[0].anchor.y - $0.y) <= 8 / z
        } == true
        for (i, pt) in pen.points.enumerated() {
            drawAnchor(pt.anchor, selected: i == pen.points.count - 1, hot: i == 0 && nearFirst, in: ctx)
        }
    }

    // MARK: Point editing

    /// Starts editing the anchors and handles of a drawn path. Returns false for paths with several subpaths.
    @discardableResult
    func beginPathEdit(_ id: UUID) -> Bool {
        guard let s = shape(id), !s.locked, let path = PenPath.from(s) else { NSSound.beep(); return false }
        selection = [id]
        editingID = id
        editingPath = path
        selectedPoint = nil
        // Editing works in canvas coordinates, so a rotated path is baked into its points (it looks the same).
        if s.rotation != 0 { commitEditedPath(path, "Edit Path") }
        needsDisplay = true
        return true
    }

    func endPathEdit() {
        guard editingPath != nil || editingID != nil else { return }
        editingPath = nil
        editingID = nil
        selectedPoint = nil
        drag = .none
        needsDisplay = true
    }

    /// Writes `path` into the shape without registering undo (for live dragging).
    private func applyEditedPath(_ path: PenPath) {
        guard let id = editingID, let o = path.outline(), let i = drawing.shapes.firstIndex(where: { $0.id == id }) else { return }
        editingPath = path
        drawing.shapes[i].frame = o.frame
        drawing.shapes[i].outline = o.segments
        drawing.shapes[i].rotation = 0
    }

    /// Writes `path` into the shape as one undo step.
    private func commitEditedPath(_ path: PenPath, _ name: String) {
        guard let id = editingID, let o = path.outline() else { return }
        mutate(name) { d in
            if let i = d.shapes.firstIndex(where: { $0.id == id }) {
                d.shapes[i].frame = o.frame
                d.shapes[i].outline = o.segments
                d.shapes[i].rotation = 0
            }
        }
        editingPath = path
    }

    /// Selects an anchor in point-edit mode (nil clears it).
    func selectPathPoint(_ i: Int?) {
        selectedPoint = i
        needsDisplay = true
    }

    func deleteSelectedPoint() {
        guard var path = editingPath, let i = selectedPoint, path.points.count > 2 else { NSSound.beep(); return }
        path.removePoint(i)
        selectedPoint = nil
        commitEditedPath(path, "Delete Point")
    }

    /// Handles a click while editing points. Returns true when the click was used.
    private func pathEditMouseDown(_ p: CGPoint, _ event: NSEvent) -> Bool {
        guard var path = editingPath, let id = editingID else { return false }
        let z = max(zoom, 0.01), reach = 6 / z
        func near(_ a: CGPoint) -> Bool { hypot(a.x - p.x, a.y - p.y) <= reach }

        // The selected point's handles first: they stick out past neighboring anchors.
        if let sel = selectedPoint, path.points.indices.contains(sel) {
            let pt = path.points[sel]
            if let h = pt.handleOut, near(h) {
                drag = .pathHandle(index: sel, out: true, mirror: path.isSmooth(sel), before: drawing)
                return true
            }
            if let h = pt.handleIn, near(h) {
                drag = .pathHandle(index: sel, out: false, mirror: path.isSmooth(sel), before: drawing)
                return true
            }
        }
        for i in path.points.indices.reversed() where near(path.points[i].anchor) {
            selectedPoint = i
            if event.clickCount == 2 {                      // double click: smooth <-> corner
                path.toggleSmooth(i)
                commitEditedPath(path, "Change Point")
            } else {
                drag = .pathAnchor(index: i, last: p, before: drawing)
            }
            needsDisplay = true
            return true
        }
        if let hit = path.nearest(to: p), hit.distance <= reach, event.clickCount == 2 {
            path.insertPoint(segment: hit.segment, t: hit.t)       // double click on the line: add a point there
            selectedPoint = hit.segment + 1 < path.points.count ? hit.segment + 1 : path.points.count - 1
            commitEditedPath(path, "Add Point")
            return true
        }
        // Clicking the path itself keeps the session (and deselects any point); anywhere else ends it.
        if let i = shapeIndex(at: p), drawing.shapes[i].id == id {
            selectedPoint = nil
            needsDisplay = true
            return true
        }
        endPathEdit()
        return false
    }

    private func drawPointEditing(_ path: PenPath, in ctx: CGContext) {
        let z = max(zoom, 0.01)
        ctx.saveGState()
        ctx.setStrokeColor(Tok.accent.withAlphaComponent(0.6).cgColor)
        ctx.setLineWidth(1 / z)
        ctx.addPath(path.cgPath())
        ctx.strokePath()
        ctx.restoreGState()

        if let sel = selectedPoint, path.points.indices.contains(sel) {
            let pt = path.points[sel]
            if let h = pt.handleIn { drawHandle(from: pt.anchor, to: h, in: ctx) }
            if let h = pt.handleOut { drawHandle(from: pt.anchor, to: h, in: ctx) }
        }
        for (i, pt) in path.points.enumerated() { drawAnchor(pt.anchor, selected: i == selectedPoint, in: ctx) }
    }

    // MARK: SVG import

    /// Adds imported layers and shapes as one undo step. The shapes are grouped so the import moves as a unit,
    /// and it lands near `origin` (top-left), shrunk to fit if it is bigger than the canvas.
    func importSVG(_ result: SVGImport.Result, near origin: CGPoint) {
        let limit = CGSize(width: Self.canvasSize.width - 40, height: Self.canvasSize.height - 40)
        let placed = result.placed(at: snap(origin)).fitted(into: limit)
        guard !placed.shapes.isEmpty else { return }
        let group: UUID? = placed.shapes.count > 1 ? UUID() : nil
        mutate("Import SVG") { d in
            d.layers.append(contentsOf: placed.layers)
            for var s in placed.shapes {
                s.group = group
                d.shapes.append(s)
            }
        }
        if let top = placed.layers.last { setActiveLayer(top.id) }
        selection = Set(placed.shapes.map(\.id))
    }

    /// Top-left of the part of the canvas currently on screen, for placing imports where the user is looking.
    var visibleOrigin: CGPoint {
        CGPoint(x: visibleRect.minX + 40, y: visibleRect.minY + 40)
    }

    // MARK: Smart guides

    private func guideThreshold() -> CGFloat { 6 / max(zoom, 0.01) }
    private func xs(_ r: CGRect) -> [CGFloat] { [r.minX, r.midX, r.maxX] }
    private func ys(_ r: CGRect) -> [CGFloat] { [r.minY, r.midY, r.maxY] }

    /// On-screen bounds of every shape on a visible layer except `ids`: what moves, resizes and new shapes align to.
    private func guideTargets(excluding ids: Set<UUID>, in d: Drawing? = nil) -> [CGRect] {
        let doc = d ?? drawing
        let visible = Set(doc.layers.filter(\.visible).map(\.id))
        return doc.shapes.filter { !ids.contains($0.id) && visible.contains($0.layer) }.map(\.worldBounds)
    }

    /// Pulls a pointer position onto the nearest edge or center of another shape, per axis, when within a few points.
    private func snapPoint(_ p: CGPoint, x: Bool, y: Bool, targets: [CGRect]) -> CGPoint {
        let thr = guideThreshold()
        var out = p
        if x {
            var best: CGFloat?
            for t in targets { for k in xs(t) { let d = k - p.x; if abs(d) <= thr, best == nil || abs(d) < abs(best!) { best = d } } }
            if let b = best { out.x += b }
        }
        if y {
            var best: CGFloat?
            for t in targets { for k in ys(t) { let d = k - p.y; if abs(d) <= thr, best == nil || abs(d) < abs(best!) { best = d } } }
            if let b = best { out.y += b }
        }
        return out
    }

    /// Guide lines for every edge or center of `box` that lines up with one of `targets`.
    private func guideLines(for box: CGRect, targets: [CGRect]) -> [SmartGuide] {
        var lines: [SmartGuide] = []
        func add(_ line: SmartGuide) {
            if let i = lines.firstIndex(where: { $0.vertical == line.vertical && abs($0.position - line.position) < 0.5 }) {
                lines[i].from = min(lines[i].from, line.from); lines[i].to = max(lines[i].to, line.to)
            } else {
                lines.append(line)
            }
        }
        for o in targets {
            for a in xs(box) { for b in xs(o) where abs(a - b) < 0.5 {
                add(SmartGuide(vertical: true, position: b, from: min(box.minY, o.minY), to: max(box.maxY, o.maxY)))
            } }
            for a in ys(box) { for b in ys(o) where abs(a - b) < 0.5 {
                add(SmartGuide(vertical: false, position: b, from: min(box.minX, o.minX), to: max(box.maxX, o.maxX)))
            } }
        }
        return lines
    }

    /// Nudges a move by (dx, dy) so the moving selection lines up with other shapes, or sits at equal distances from them,
    /// when within a few points; returns the adjusted move plus the guides and spacing marks to draw.
    private func guideSnap(before: Drawing, dx: CGFloat, dy: CGFloat)
        -> (dx: CGFloat, dy: CGFloat, lines: [SmartGuide], marks: [SpacingMark]) {
        let movingIDs = Set(before.shapes.filter { selection.contains($0.id) && !$0.locked }.map(\.id))
        let moving = before.shapes.filter { movingIDs.contains($0.id) }.map(\.worldBounds)
        guard let first = moving.first else { return (dx, dy, [], []) }
        let box = moving.dropFirst().reduce(first) { $0.union($1) }.offsetBy(dx: dx, dy: dy)
        let others = guideTargets(excluding: movingIDs, in: before)
        let thr = guideThreshold()

        var adjX: CGFloat?, adjY: CGFloat?
        for o in others {
            for a in xs(box) { for b in xs(o) { let d = b - a; if abs(d) <= thr, adjX == nil || abs(d) < abs(adjX!) { adjX = d } } }
            for a in ys(box) { for b in ys(o) { let d = b - a; if abs(d) <= thr, adjY == nil || abs(d) < abs(adjY!) { adjY = d } } }
        }
        // Where nothing lines up, look for equal spacing along that axis.
        if adjX == nil { adjX = spacingAdjust(box, others, horizontal: true, threshold: thr) }
        if adjY == nil { adjY = spacingAdjust(box, others, horizontal: false, threshold: thr) }

        let fixed = box.offsetBy(dx: adjX ?? 0, dy: adjY ?? 0)
        let marks = spacingMarks(fixed, others, horizontal: true) + spacingMarks(fixed, others, horizontal: false)
        return (dx + (adjX ?? 0), dy + (adjY ?? 0), guideLines(for: fixed, targets: others), marks)
    }

    private func drawSpacingMarks(in ctx: CGContext) {
        let z = max(zoom, 0.01), tick = 4 / z
        let color = Tok.guideSnap
        ctx.saveGState()
        ctx.setStrokeColor(color.cgColor)
        ctx.setLineWidth(1 / z)
        for m in smartSpacingMarks {
            if m.horizontal {
                ctx.move(to: CGPoint(x: m.from, y: m.at)); ctx.addLine(to: CGPoint(x: m.to, y: m.at))
                ctx.move(to: CGPoint(x: m.from, y: m.at - tick)); ctx.addLine(to: CGPoint(x: m.from, y: m.at + tick))
                ctx.move(to: CGPoint(x: m.to, y: m.at - tick)); ctx.addLine(to: CGPoint(x: m.to, y: m.at + tick))
            } else {
                ctx.move(to: CGPoint(x: m.at, y: m.from)); ctx.addLine(to: CGPoint(x: m.at, y: m.to))
                ctx.move(to: CGPoint(x: m.at - tick, y: m.from)); ctx.addLine(to: CGPoint(x: m.at + tick, y: m.from))
                ctx.move(to: CGPoint(x: m.at - tick, y: m.to)); ctx.addLine(to: CGPoint(x: m.at + tick, y: m.to))
            }
        }
        ctx.strokePath()
        ctx.restoreGState()

        // The size of the gap, so equal spacing can be read off the canvas.
        let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 10 / z, weight: .semibold), .foregroundColor: color]
        for m in smartSpacingMarks {
            let label = NSAttributedString(string: "\(Int((m.to - m.from).rounded()))", attributes: attrs)
            let sz = label.size()
            let origin = m.horizontal ? CGPoint(x: (m.from + m.to) / 2 - sz.width / 2, y: m.at - tick - sz.height - 1 / z)
                                      : CGPoint(x: m.at + tick + 2 / z, y: (m.from + m.to) / 2 - sz.height / 2)
            label.draw(at: origin)
        }
    }

    /// The axes a resize handle moves: (x, y).
    private func movedAxes(handle h: Int) -> (x: Bool, y: Bool) {
        ([0, 2, 3, 4, 6, 7].contains(h), [0, 1, 2, 4, 5, 6].contains(h))
    }

    // MARK: Equal spacing

    private struct Axis {
        let horizontal: Bool
        func lo(_ r: CGRect) -> CGFloat { horizontal ? r.minX : r.minY }
        func hi(_ r: CGRect) -> CGFloat { horizontal ? r.maxX : r.maxY }
        func crossLo(_ r: CGRect) -> CGFloat { horizontal ? r.minY : r.minX }
        func crossHi(_ r: CGRect) -> CGFloat { horizontal ? r.maxY : r.maxX }
    }

    /// Shapes that share a row (for horizontal spacing) or a column (for vertical) with `box`.
    private func sameLine(_ box: CGRect, _ others: [CGRect], _ ax: Axis) -> [CGRect] {
        others.filter { ax.crossHi($0) > ax.crossLo(box) && ax.crossLo($0) < ax.crossHi(box) }
    }

    /// How far to shift `box` along the axis so its gaps match: equal to each other when it sits between two shapes,
    /// or equal to a gap that already exists between two other shapes in the line. nil when nothing is close enough.
    private func spacingAdjust(_ box: CGRect, _ others: [CGRect], horizontal: Bool, threshold: CGFloat) -> CGFloat? {
        let ax = Axis(horizontal: horizontal)
        let row = sameLine(box, others, ax)
        guard !row.isEmpty, row.count <= 80 else { return nil }

        let left = row.filter { ax.hi($0) <= ax.lo(box) + 0.001 }.max { ax.hi($0) < ax.hi($1) }
        let right = row.filter { ax.lo($0) >= ax.hi(box) - 0.001 }.min { ax.lo($0) < ax.lo($1) }

        var candidates: [CGFloat] = []
        if let l = left, let r = right {
            let gapL = ax.lo(box) - ax.hi(l), gapR = ax.lo(r) - ax.hi(box)
            candidates.append((gapR - gapL) / 2)                         // centered between its two neighbors
        }
        let ordered = row.sorted { ax.lo($0) < ax.lo($1) }
        for i in 0..<max(ordered.count - 1, 0) {
            let a = ordered[i], b = ordered[i + 1]
            let g = ax.lo(b) - ax.hi(a)
            guard g > 1 else { continue }
            if let l = left { candidates.append((ax.hi(l) + g) - ax.lo(box)) }     // same gap as a and b, to the right of l
            if let r = right { candidates.append((ax.lo(r) - g) - ax.hi(box)) }    // same gap, to the left of r
        }
        return candidates.filter { abs($0) <= threshold }.min { abs($0) < abs($1) }
    }

    /// Brackets across every gap beside `box` that equals another gap in the same line, so the equality is visible.
    private func spacingMarks(_ box: CGRect, _ others: [CGRect], horizontal: Bool) -> [SpacingMark] {
        let ax = Axis(horizontal: horizontal)
        let row = sameLine(box, others, ax)
        guard !row.isEmpty, row.count <= 80 else { return [] }

        struct Gap { var from: CGFloat; var to: CGFloat; var at: CGFloat; var touchesBox: Bool }
        let items = (row.map { ($0, false) } + [(box, true)]).sorted { ax.lo($0.0) < ax.lo($1.0) }
        var gaps: [Gap] = []
        for i in 0..<max(items.count - 1, 0) {
            let a = items[i], b = items[i + 1]
            guard ax.hi(a.0) < ax.lo(b.0) - 0.5 else { continue }
            let cross = (max(ax.crossLo(a.0), ax.crossLo(b.0)) + min(ax.crossHi(a.0), ax.crossHi(b.0))) / 2
            gaps.append(Gap(from: ax.hi(a.0), to: ax.lo(b.0), at: cross, touchesBox: a.1 || b.1))
        }
        var marked = Set<Int>()
        for (i, g) in gaps.enumerated() where g.touchesBox {
            for (j, h) in gaps.enumerated() where j != i && abs((h.to - h.from) - (g.to - g.from)) < 0.5 {
                marked.insert(i); marked.insert(j)
            }
        }
        return marked.sorted().map { SpacingMark(horizontal: horizontal, from: gaps[$0].from, to: gaps[$0].to, at: gaps[$0].at) }
    }

    // MARK: Distribute and match size

    /// Spreads three or more shapes so the gaps between them are equal; the outermost keep their places.
    /// tag: 0 horizontally, 1 vertically. Locked shapes stay where they are.
    @objc func distribute(_ sender: NSMenuItem) {
        let horizontal = sender.tag == 0
        let items = selectedShapes.map { (id: $0.id, box: $0.worldBounds) }
            .sorted { horizontal ? $0.box.minX < $1.box.minX : $0.box.minY < $1.box.minY }
        guard items.count >= 3 else { return }

        func lead(_ r: CGRect) -> CGFloat { horizontal ? r.minX : r.minY }
        func trail(_ r: CGRect) -> CGFloat { horizontal ? r.maxX : r.maxY }
        func size(_ r: CGRect) -> CGFloat { horizontal ? r.width : r.height }
        let start = items.map { lead($0.box) }.min()!, end = items.map { trail($0.box) }.max()!
        let gap = (end - start - items.reduce(0) { $0 + size($1.box) }) / CGFloat(items.count - 1)

        var cursor = start
        var moves: [UUID: CGFloat] = [:]
        for it in items {
            moves[it.id] = cursor - lead(it.box)
            cursor += size(it.box) + gap
        }
        mutate(horizontal ? "Distribute Horizontally" : "Distribute Vertically") { d in
            for i in d.shapes.indices where !d.shapes[i].locked {
                guard let delta = moves[d.shapes[i].id] else { continue }
                if horizontal { d.shapes[i].frame.origin.x += delta } else { d.shapes[i].frame.origin.y += delta }
            }
        }
    }

    /// Gives the selected shapes the width and/or height of the one selected first.
    /// tag: 0 width, 1 height, 2 both. Each keeps its top-left corner; locked shapes are left alone.
    @objc func matchSize(_ sender: NSMenuItem) {
        guard selectedShapes.count >= 2,
              let refID = selectionOrder.first(where: { id in selectedShapes.contains { $0.id == id } }),
              let ref = shape(refID) else { return }
        let tag = sender.tag
        mutate(tag == 0 ? "Same Width" : tag == 1 ? "Same Height" : "Same Size") { d in
            for i in d.shapes.indices where selection.contains(d.shapes[i].id) && d.shapes[i].id != refID && !d.shapes[i].locked {
                if tag != 1 { d.shapes[i].frame.size.width = ref.frame.width }
                if tag != 0 { d.shapes[i].frame.size.height = ref.frame.height }
            }
        }
    }

    // MARK: Copy and paste style

    private struct StyleClip {
        var style: Style
        var fromConnector: Bool
    }

    /// Shared by every canvas, so a style can be copied in one document window and pasted in another.
    private static var styleClip: StyleClip?

    var hasStyleClip: Bool { Self.styleClip != nil }

    /// The look of the first selected object, and whether it is a connector.
    func styleForSaving() -> (style: Style, fromConnector: Bool) {
        if let s = selectedShapes.first { return (s.style, false) }
        if let c = selectedConnectors.first { return (c.style, true) }
        return (defaultStyle, false)
    }

    @objc func copyStyle(_ sender: Any?) {
        guard !selection.isEmpty else { return }
        let source = styleForSaving()
        Self.styleClip = StyleClip(style: source.style, fromConnector: source.fromConnector)
    }

    @objc func pasteStyle(_ sender: Any?) {
        guard let clip = Self.styleClip else { return }
        applyLook(clip.style, fromConnector: clip.fromConnector, name: "Paste Style")
    }

    /// Gives every selected object `style` (one undo step). With nothing selected it becomes the look of new objects.
    /// Locked objects take it too: a lock protects geometry, not appearance.
    func applyLook(_ style: Style, fromConnector: Bool, name: String = "Apply Style") {
        if selection.isEmpty {
            defaultStyle = defaultStyle.receiving(style, sourceIsConnector: fromConnector, targetIsConnector: false)
            onSelectionChange?()
            return
        }
        mutate(name) { d in
            for i in d.shapes.indices where selection.contains(d.shapes[i].id) {
                d.shapes[i].style = d.shapes[i].style.receiving(style, sourceIsConnector: fromConnector, targetIsConnector: false)
            }
            for i in d.connectors.indices where selection.contains(d.connectors[i].id) {
                d.connectors[i].style = d.connectors[i].style.receiving(style, sourceIsConnector: fromConnector, targetIsConnector: true)
            }
        }
    }

    // MARK: Lock

    @objc func lockSelection(_ sender: Any?) { setLocked(true) }
    @objc func unlockSelection(_ sender: Any?) { setLocked(false) }

    private func setLocked(_ on: Bool) {
        guard !selection.isEmpty else { return }
        if on { endPathEdit() }
        mutate(on ? "Lock" : "Unlock") { d in
            for i in d.shapes.indices where selection.contains(d.shapes[i].id) { d.shapes[i].locked = on }
            for i in d.connectors.indices where selection.contains(d.connectors[i].id) { d.connectors[i].locked = on }
        }
    }

    @objc func unlockAll(_ sender: Any?) {
        mutate("Unlock All") { d in
            for i in d.shapes.indices { d.shapes[i].locked = false }
            for i in d.connectors.indices { d.connectors[i].locked = false }
        }
    }

    /// Edits the text of the selected shape or label, or the points of a drawn path.
    @objc func editSelection(_ sender: Any?) {
        guard selection.count == 1 else { return }
        if let s = selectedShapes.first {
            if s.kind == .path { beginPathEdit(s.id) } else { beginEditing(.shape(s.id)) }
        } else if let c = selectedConnectors.first {
            beginEditing(.connector(c.id))
        }
    }

    @objc func moveToLayerItem(_ sender: NSMenuItem) {
        if let id = sender.representedObject as? UUID { moveSelection(toLayer: id) }
    }

    // MARK: Context menu

    /// Right-click: an unselected object under the pointer becomes the selection (with its whole group);
    /// empty canvas clears it. The menu then offers what applies to that selection.
    override func menu(for event: NSEvent) -> NSMenu? {
        guard tool != .pen else { return nil }
        let p = convert(event.locationInWindow, from: nil)
        window?.makeFirstResponder(self)          // ends any text editing first
        if let i = shapeIndex(at: p) {
            let s = drawing.shapes[i]
            if !selection.contains(s.id) { selection = groupMembers(of: s) }
        } else if let i = connectorIndex(at: p) {
            let c = drawing.connectors[i]
            if !selection.contains(c.id) { selection = [c.id] }
        } else {
            selection = []
        }
        return contextMenu()
    }

    func contextMenu() -> NSMenu {
        let menu = NSMenu(title: "Canvas")
        menu.autoenablesItems = true

        @discardableResult
        func add(_ title: String, _ action: Selector, key: String = "", mods: NSEvent.ModifierFlags = .command,
                 tag: Int = 0, to target: NSMenu? = nil) -> NSMenuItem {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
            item.keyEquivalentModifierMask = key.isEmpty ? [] : mods
            item.target = self
            item.tag = tag
            (target ?? menu).addItem(item)
            return item
        }

        if selection.isEmpty {
            add("Paste", #selector(paste(_:)), key: "v")
            add("Paste Style", #selector(pasteStyle(_:)), key: "v", mods: [.command, .option])
            add("Select All", #selector(selectAll(_:)), key: "a")
            if hasLockedObjects {
                menu.addItem(.separator())
                add("Unlock All", #selector(unlockAll(_:)))
            }
            return menu
        }

        add("Cut", #selector(cut(_:)), key: "x")
        add("Copy", #selector(copy(_:)), key: "c")
        add("Paste", #selector(paste(_:)), key: "v")
        add("Duplicate", #selector(duplicate(_:)), key: "d")
        add("Delete", #selector(delete(_:)))
        menu.addItem(.separator())

        add("Copy Style", #selector(copyStyle(_:)), key: "c", mods: [.command, .option])
        add("Paste Style", #selector(pasteStyle(_:)), key: "v", mods: [.command, .option])
        menu.addItem(.separator())

        add("Group", #selector(group(_:)), key: "g")
        add("Ungroup", #selector(ungroup(_:)), key: "g", mods: [.command, .shift])
        menu.addItem(.separator())

        add("Lock", #selector(lockSelection(_:)), key: "l")
        add("Unlock", #selector(unlockSelection(_:)), key: "l", mods: [.command, .option])
        if hasLockedObjects { add("Unlock All", #selector(unlockAll(_:))) }
        menu.addItem(.separator())

        add("Bring to Front", #selector(bringToFront(_:)), key: "]", mods: [.command, .shift])
        add("Send to Back", #selector(sendToBack(_:)), key: "[", mods: [.command, .shift])

        let layers = NSMenu(title: "Move to Layer")
        let chosen = Set((selectedShapes.map(\.layer)) + selectedConnectors.map(\.layer))
        for l in drawing.layers.reversed() {
            let item = NSMenuItem(title: l.name, action: #selector(moveToLayerItem(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = l.id
            item.state = chosen == [l.id] ? .on : .off
            layers.addItem(item)
        }
        let layersItem = NSMenuItem(title: "Move to Layer", action: nil, keyEquivalent: "")
        layersItem.submenu = layers
        menu.addItem(layersItem)

        if selectedShapes.count >= 2 {
            let align = NSMenu(title: "Align")
            for (i, name) in ["Left", "Center", "Right", "Top", "Middle", "Bottom"].enumerated() {
                add(name, #selector(self.align(_:)), tag: i, to: align)
            }
            let alignItem = NSMenuItem(title: "Align", action: nil, keyEquivalent: "")
            alignItem.submenu = align
            menu.addItem(alignItem)
        }

        if selectedShapes.count >= 3 {
            let dist = NSMenu(title: "Distribute")
            add("Horizontally", #selector(self.distribute(_:)), tag: 0, to: dist)
            add("Vertically", #selector(self.distribute(_:)), tag: 1, to: dist)
            let item = NSMenuItem(title: "Distribute", action: nil, keyEquivalent: "")
            item.submenu = dist
            menu.addItem(item)
        }
        if selectedShapes.count >= 2 {
            let match = NSMenu(title: "Match Size")
            add("Same Width", #selector(self.matchSize(_:)), tag: 0, to: match)
            add("Same Height", #selector(self.matchSize(_:)), tag: 1, to: match)
            add("Same Size", #selector(self.matchSize(_:)), tag: 2, to: match)
            let item = NSMenuItem(title: "Match Size", action: nil, keyEquivalent: "")
            item.submenu = match
            menu.addItem(item)
        }

        if selection.count == 1 {
            menu.addItem(.separator())
            if let s = selectedShapes.first { add(s.kind == .path ? "Edit Points" : "Edit Text", #selector(editSelection(_:)), key: "\r", mods: []) }
            else { add("Edit Label", #selector(editSelection(_:)), key: "\r", mods: []) }
        }
        return menu
    }

    // MARK: Groups

    @objc func group(_ sender: Any?) {
        guard selectedShapes.count > 1 else { return }
        let g = UUID()
        mutate("Group") { d in
            for i in d.shapes.indices where selection.contains(d.shapes[i].id) { d.shapes[i].group = g }
        }
    }

    @objc func ungroup(_ sender: Any?) {
        mutate("Ungroup") { d in
            for i in d.shapes.indices where selection.contains(d.shapes[i].id) { d.shapes[i].group = nil }
        }
    }

    // MARK: Arrange actions

    @objc func bringToFront(_ sender: Any?) {
        mutate("Bring to Front") { d in
            let moving = d.shapes.filter { selection.contains($0.id) }
            d.shapes.removeAll { selection.contains($0.id) }
            d.shapes.append(contentsOf: moving)
        }
    }

    @objc func sendToBack(_ sender: Any?) {
        mutate("Send to Back") { d in
            let moving = d.shapes.filter { selection.contains($0.id) }
            d.shapes.removeAll { selection.contains($0.id) }
            d.shapes.insert(contentsOf: moving, at: 0)
        }
    }

    /// tag: 0 left, 1 center, 2 right, 3 top, 4 middle, 5 bottom
    @objc func align(_ sender: NSMenuItem) {
        let sel = selectedShapes
        guard sel.count > 1, let bounds = sel.map(\.worldBounds).reduce(nil, { acc, f in acc.map { $0.union(f) } ?? f }) else { return }
        mutate("Align") { d in
            for i in d.shapes.indices where selection.contains(d.shapes[i].id) && !d.shapes[i].locked {
                let wb = d.shapes[i].worldBounds   // align what is seen on screen, rotated or not
                var dx: CGFloat = 0, dy: CGFloat = 0
                switch sender.tag {
                case 0: dx = bounds.minX - wb.minX
                case 1: dx = bounds.midX - wb.midX
                case 2: dx = bounds.maxX - wb.maxX
                case 3: dy = bounds.minY - wb.minY
                case 4: dy = bounds.midY - wb.midY
                default: dy = bounds.maxY - wb.maxY
                }
                d.shapes[i].frame.origin.x += dx
                d.shapes[i].frame.origin.y += dy
            }
        }
    }

    // MARK: Menu validation

    func validateMenuItem(_ item: NSMenuItem) -> Bool {
        switch item.action {
        case #selector(undo(_:)):
            let um = undoManager
            item.title = (um?.canUndo ?? false) ? "Undo \(um?.undoActionName ?? "")" : "Undo"
            return um?.canUndo ?? false
        case #selector(redo(_:)):
            let um = undoManager
            item.title = (um?.canRedo ?? false) ? "Redo \(um?.redoActionName ?? "")" : "Redo"
            return um?.canRedo ?? false
        case #selector(delete(_:)), #selector(cut(_:)):
            return selectionHasUnlocked                  // locked objects can't be deleted
        case #selector(copy(_:)), #selector(duplicate(_:)), #selector(bringToFront(_:)), #selector(sendToBack(_:)),
             #selector(moveToLayerItem(_:)):
            return !selection.isEmpty
        case #selector(distribute(_:)):
            return selectedShapes.count >= 3
        case #selector(matchSize(_:)):
            return selectedShapes.count >= 2
        case #selector(copyStyle(_:)):
            return !selection.isEmpty
        case #selector(pasteStyle(_:)):
            return hasStyleClip                          // with nothing selected it sets the style of new objects
        case #selector(lockSelection(_:)):
            return selectionHasUnlocked
        case #selector(unlockSelection(_:)):
            return selectionHasLocked
        case #selector(unlockAll(_:)):
            return hasLockedObjects
        case #selector(editSelection(_:)):
            return selection.count == 1 && !selectionHasLocked
        case #selector(paste(_:)):
            return NSPasteboard.general.data(forType: Self.pasteType) != nil
        case #selector(align(_:)), #selector(group(_:)):
            return selectedShapes.count > 1
        case #selector(ungroup(_:)):
            return selectedShapes.contains { $0.group != nil }
        default:
            return true
        }
    }

    // MARK: Export

    func exportBounds() -> CGRect? {
        drawing.contentBounds?.insetBy(dx: -24, dy: -24)
    }

    func pdfData() -> Data? {
        guard let rect = exportBounds() else { return nil }
        isExporting = true
        defer { isExporting = false }
        return dataWithPDF(inside: rect)
    }

    func svgData() -> Data? {
        guard let rect = exportBounds() else { return nil }
        return SVGExport.svg(for: drawing, bounds: rect).data(using: .utf8)
    }

    func pngData() -> Data? {
        guard let rect = exportBounds(), let rep = bitmapImageRepForCachingDisplay(in: rect) else { return nil }
        isExporting = true
        defer { isExporting = false }
        cacheDisplay(in: rect, to: rep)
        return rep.representation(using: .png, properties: [:])
    }
}
