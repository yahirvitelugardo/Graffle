import AppKit

/// The palette of saved styles: a grid of small previews, then a "+" tile that saves the selection's style.
/// Click a preview to apply it; right-click one to rename, update or delete it.
final class StylePaletteView: NSView, NSViewToolTipOwner {
    var library = StyleLibrary.shared {
        didSet {
            library.onChange = { [weak self] in self?.reload() }
            reload()
        }
    }

    var onApply: ((SavedStyle) -> Void)?
    var onAdd: (() -> Void)?
    var onRename: ((SavedStyle) -> Void)?
    var onUpdate: ((SavedStyle) -> Void)?
    var onDelete: ((SavedStyle) -> Void)?

    static let tileSize = CGSize(width: 40, height: 28)
    static let gap: CGFloat = 8
    static let columns = 5

    override var isFlipped: Bool { true }

    override init(frame: NSRect) {
        super.init(frame: frame)
        library.onChange = { [weak self] in self?.reload() }
        reload()
    }

    required init?(coder: NSCoder) { fatalError() }

    // MARK: Layout

    /// One tile per saved style, plus the "+" tile at the end.
    var tileCount: Int { library.styles.count + 1 }

    func rect(forTile i: Int) -> CGRect {
        let col = i % StylePaletteView.columns, row = i / StylePaletteView.columns
        let t = StylePaletteView.tileSize, g = StylePaletteView.gap
        return CGRect(x: CGFloat(col) * (t.width + g), y: CGFloat(row) * (t.height + g), width: t.width, height: t.height)
    }

    override var intrinsicContentSize: NSSize {
        let rows = (tileCount + StylePaletteView.columns - 1) / StylePaletteView.columns
        let t = StylePaletteView.tileSize, g = StylePaletteView.gap
        return NSSize(width: 232, height: CGFloat(rows) * t.height + CGFloat(max(rows - 1, 0)) * g)
    }

    func tileIndex(at p: CGPoint) -> Int? {
        (0..<tileCount).first { rect(forTile: $0).contains(p) }
    }

    func reload() {
        invalidateIntrinsicContentSize()
        removeAllToolTips()
        for i in 0..<tileCount { addToolTip(rect(forTile: i), owner: self, userData: nil) }
        needsDisplay = true
    }

    func view(_ view: NSView, stringForToolTip tag: NSView.ToolTipTag, point: NSPoint, userData data: UnsafeMutableRawPointer?) -> String {
        guard let i = tileIndex(at: point) else { return "" }
        return i < library.styles.count ? library.styles[i].name + " — click to apply, right-click for more"
                                        : "Save the selected object's style"
    }

    // MARK: Drawing

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        for (i, saved) in library.styles.enumerated() {
            StylePaletteView.drawTile(saved.style, in: rect(forTile: i), ctx)
        }
        drawPlusTile(rect(forTile: library.styles.count), ctx)
    }

    /// A small tile showing what the style looks like on a rounded shape.
    static func drawTile(_ style: Style, in rect: CGRect, _ ctx: CGContext) {
        ctx.saveGState()
        // The tile itself, so white and pale fills still read.
        let tile = CGPath(roundedRect: rect, cornerWidth: 6, cornerHeight: 6, transform: nil)
        ctx.setFillColor(NSColor(white: 0.93, alpha: 1).cgColor)
        ctx.addPath(tile); ctx.fillPath()
        ctx.setStrokeColor(NSColor(white: 0, alpha: 0.12).cgColor)
        ctx.setLineWidth(1)
        ctx.addPath(tile); ctx.strokePath()

        let body = rect.insetBy(dx: 7, dy: 6)
        let radius = style.cornerRadius > 0 ? min(CGFloat(style.cornerRadius) / 2, 6) : 2
        let path = CGPath(roundedRect: body, cornerWidth: radius, cornerHeight: radius, transform: nil)
        let hasLook = style.fill.kind != .none || style.stroke.visible

        if !hasLook {
            // A text-only style: show the font instead of an empty box.
            var t = style.text
            t.size = 13; t.hAlign = .center; t.vAlign = .middle
            Render.drawText("Aa", in: rect, format: t, color: Render.textColor(t, fill: style.fill))
            ctx.restoreGState()
            return
        }

        ctx.setAlpha(CGFloat(max(style.opacity, 0.25)))
        let shadowed = style.shadow.enabled
        if shadowed {
            let v = style.shadow.vector
            ctx.setShadow(offset: CGSize(width: v.width * 0.3, height: v.height * 0.3), blur: min(CGFloat(style.shadow.blur) * 0.4, 4),
                          color: style.shadow.color.cg)
            ctx.beginTransparencyLayer(auxiliaryInfo: nil)
        }
        Render.fill(ctx, path: path, fill: style.fill)
        if style.stroke.visible && style.stroke.width > 0 {
            ctx.saveGState()
            var thin = style.stroke
            thin.width = min(max(style.stroke.width, 1), 2.5)     // widths are for full-size shapes
            Render.applyStroke(ctx, thin)
            if thin.dash != .solid { ctx.setLineDash(phase: 0, lengths: [3, 2.5]) }   // a dash must be visible at this size
            ctx.addPath(path); ctx.strokePath()
            ctx.restoreGState()
        }
        if shadowed { ctx.endTransparencyLayer() }
        ctx.restoreGState()
    }

    private func drawPlusTile(_ rect: CGRect, _ ctx: CGContext) {
        ctx.saveGState()
        let path = CGPath(roundedRect: rect.insetBy(dx: 0.5, dy: 0.5), cornerWidth: 6, cornerHeight: 6, transform: nil)
        ctx.setStrokeColor(NSColor.tertiaryLabelColor.cgColor)
        ctx.setLineWidth(1)
        ctx.setLineDash(phase: 0, lengths: [3, 3])
        ctx.addPath(path); ctx.strokePath()
        ctx.setLineDash(phase: 0, lengths: [])
        ctx.setStrokeColor(NSColor.secondaryLabelColor.cgColor)
        ctx.setLineWidth(1.5)
        ctx.setLineCap(.round)
        ctx.move(to: CGPoint(x: rect.midX - 5, y: rect.midY)); ctx.addLine(to: CGPoint(x: rect.midX + 5, y: rect.midY))
        ctx.move(to: CGPoint(x: rect.midX, y: rect.midY - 5)); ctx.addLine(to: CGPoint(x: rect.midX, y: rect.midY + 5))
        ctx.strokePath()
        ctx.restoreGState()
    }

    /// The tile as an image, for tests and anywhere a preview is needed.
    static func image(for style: Style) -> NSImage {
        NSImage(size: tileSize, flipped: true) { rect in
            guard let ctx = NSGraphicsContext.current?.cgContext else { return false }
            drawTile(style, in: rect, ctx)
            return true
        }
    }

    // MARK: Mouse

    override func mouseDown(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        guard let i = tileIndex(at: p) else { return }
        if i < library.styles.count { onApply?(library.styles[i]) } else { onAdd?() }
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        let p = convert(event.locationInWindow, from: nil)
        guard let i = tileIndex(at: p), i < library.styles.count else { return nil }
        let saved = library.styles[i]
        let menu = NSMenu(title: saved.name)
        func add(_ title: String, _ action: Selector) {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
            item.target = self
            item.representedObject = saved.id
            menu.addItem(item)
        }
        add("Apply", #selector(menuApply(_:)))
        menu.addItem(.separator())
        add("Rename…", #selector(menuRename(_:)))
        add("Update from Selection", #selector(menuUpdate(_:)))
        menu.addItem(.separator())
        add("Delete", #selector(menuDelete(_:)))
        return menu
    }

    private func saved(_ sender: NSMenuItem) -> SavedStyle? {
        (sender.representedObject as? UUID).flatMap { library.style($0) }
    }

    @objc private func menuApply(_ sender: NSMenuItem) { if let s = saved(sender) { onApply?(s) } }
    @objc private func menuRename(_ sender: NSMenuItem) { if let s = saved(sender) { onRename?(s) } }
    @objc private func menuUpdate(_ sender: NSMenuItem) { if let s = saved(sender) { onUpdate?(s) } }
    @objc private func menuDelete(_ sender: NSMenuItem) { if let s = saved(sender) { onDelete?(s) } }
}
