import AppKit

/// A gradient bar with draggable color-stop markers underneath.
/// Click a marker to select it, drag it to move it, click the bar to add a stop.
final class GradientEditorView: NSView {
    var stops: [GradientStop] = [] { didSet { needsDisplay = true } }
    var selected = 0 { didSet { needsDisplay = true } }

    /// The user picked a different stop.
    var onSelect: (() -> Void)?
    /// The user changed the stops (moved, added or removed one).
    var onEdit: (() -> Void)?

    private let inset: CGFloat = 12
    private var dragging = false

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    override var intrinsicContentSize: NSSize { NSSize(width: NSView.noIntrinsicMetric, height: 46) }

    private var bar: NSRect { NSRect(x: inset, y: 2, width: max(bounds.width - inset * 2, 1), height: 22) }

    private func x(_ t: Double) -> CGFloat { bar.minX + CGFloat(min(max(t, 0), 1)) * bar.width }
    private func t(_ x: CGFloat) -> Double { Double(min(max((x - bar.minX) / bar.width, 0), 1)) }

    // MARK: Drawing

    override func draw(_ dirtyRect: NSRect) {
        let sorted = stops.sorted { $0.position < $1.position }
        let barPath = NSBezierPath(roundedRect: bar, xRadius: 4, yRadius: 4)

        if sorted.count >= 2,
           let g = NSGradient(colors: sorted.map { $0.color.ns }, atLocations: sorted.map { CGFloat($0.position) },
                              colorSpace: .sRGB) {
            // Light checkerboard under the bar so translucent stops read as translucent.
            NSGraphicsContext.saveGraphicsState()
            barPath.addClip()
            NSColor(white: 0.92, alpha: 1).setFill()
            bar.fill()
            NSColor(white: 0.78, alpha: 1).setFill()
            var row = 0
            var y = bar.minY
            while y < bar.maxY {
                var col = row % 2
                var cx = bar.minX + CGFloat(col) * 6
                while cx < bar.maxX { NSRect(x: cx, y: y, width: 6, height: 6).fill(); cx += 12; col += 2 }
                y += 6; row += 1
            }
            g.draw(in: bar, angle: 0)
            NSGraphicsContext.restoreGraphicsState()
        }
        NSColor.separatorColor.setStroke()
        barPath.lineWidth = 1
        barPath.stroke()

        for (i, s) in stops.enumerated() where i != selected { drawMarker(s, selected: false) }
        if stops.indices.contains(selected) { drawMarker(stops[selected], selected: true) }
    }

    private func drawMarker(_ s: GradientStop, selected: Bool) {
        let cx = x(s.position), top = bar.maxY + 1
        let p = NSBezierPath()
        p.move(to: NSPoint(x: cx, y: top))
        p.line(to: NSPoint(x: cx + 6, y: top + 7))
        p.line(to: NSPoint(x: cx + 6, y: top + 18))
        p.line(to: NSPoint(x: cx - 6, y: top + 18))
        p.line(to: NSPoint(x: cx - 6, y: top + 7))
        p.close()
        NSColor.white.setFill()
        p.fill()
        // The color swatch inside the marker.
        s.color.ns.setFill()
        NSRect(x: cx - 4, y: top + 9, width: 8, height: 7).fill()
        (selected ? NSColor.controlAccentColor : NSColor.secondaryLabelColor).setStroke()
        p.lineWidth = selected ? 2 : 1
        p.stroke()
    }

    // MARK: Mouse and keyboard

    private func markerIndex(at p: NSPoint) -> Int? {
        guard p.y >= bar.maxY - 3 else { return nil }
        // Later stops are drawn on top, so test them first; prefer the selected one on ties.
        if stops.indices.contains(selected), abs(p.x - x(stops[selected].position)) <= 7 { return selected }
        return stops.indices.reversed().first { abs(p.x - x(stops[$0].position)) <= 7 }
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        let p = convert(event.locationInWindow, from: nil)

        if let i = markerIndex(at: p) {
            selected = i
            dragging = true
            onSelect?()
        } else if bar.insetBy(dx: -4, dy: 0).contains(p) {
            let pos = t(p.x)
            let fill = Fill.sampling(stops)
            stops.append(GradientStop(color: fill.color(at: pos), position: pos))
            selected = stops.count - 1
            dragging = true
            onSelect?()
            onEdit?()
        }
    }

    override func mouseDragged(with event: NSEvent) {
        guard dragging, stops.indices.contains(selected) else { return }
        let p = convert(event.locationInWindow, from: nil)
        var pos = t(p.x)
        if event.modifierFlags.contains(.shift) { pos = (pos * 20).rounded() / 20 }   // 5% steps
        stops[selected].position = pos
        onEdit?()
    }

    override func mouseUp(with event: NSEvent) { dragging = false }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 51 || event.keyCode == 117 { removeSelected() } else { super.keyDown(with: event) }
    }

    // MARK: Editing

    func removeSelected() {
        guard stops.count > 2, stops.indices.contains(selected) else { return }
        stops.remove(at: selected)
        selected = min(selected, stops.count - 1)
        onSelect?()
        onEdit?()
    }

    func reverse() {
        stops = stops.map { GradientStop(color: $0.color, position: 1 - $0.position) }
        onEdit?()
    }
}

extension Fill {
    /// A throwaway fill whose stops are `stops`, for color lookups.
    static func sampling(_ stops: [GradientStop]) -> Fill {
        var f = Fill()
        f.stops = stops
        return f
    }
}
