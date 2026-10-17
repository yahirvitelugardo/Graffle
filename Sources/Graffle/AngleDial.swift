import AppKit

/// A round angle control: drag the needle around the circle. 0° points right and angles grow clockwise on screen,
/// the same convention the rest of the app uses for gradients, shadows and rotation.
final class AngleDial: NSControl {
    var angle: Double = 0 { didSet { needsDisplay = true } }

    /// Called when the user turns the dial (not when `angle` is set from code).
    var onChange: ((Double) -> Void)?

    override var isFlipped: Bool { true }
    override var intrinsicContentSize: NSSize { NSSize(width: 30, height: 30) }
    override var acceptsFirstResponder: Bool { false }

    override func draw(_ dirtyRect: NSRect) {
        let r = min(bounds.width, bounds.height) / 2 - 2
        let c = CGPoint(x: bounds.midX, y: bounds.midY)

        let face = NSBezierPath(ovalIn: NSRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2))
        NSColor.controlBackgroundColor.setFill()
        face.fill()
        NSColor.tertiaryLabelColor.setStroke()
        face.lineWidth = 1
        face.stroke()

        // Ticks at 0°, 90°, 180° and 270°.
        NSColor.tertiaryLabelColor.setStroke()
        for k in 0..<4 {
            let a = CGFloat(k) * .pi / 2
            let tick = NSBezierPath()
            tick.move(to: CGPoint(x: c.x + cos(a) * (r - 3), y: c.y + sin(a) * (r - 3)))
            tick.line(to: CGPoint(x: c.x + cos(a) * r, y: c.y + sin(a) * r))
            tick.lineWidth = 1
            tick.stroke()
        }

        let a = CGFloat(angle) * .pi / 180
        let tip = CGPoint(x: c.x + cos(a) * (r - 4), y: c.y + sin(a) * (r - 4))
        let needle = NSBezierPath()
        needle.move(to: c)
        needle.line(to: tip)
        needle.lineWidth = 2
        needle.lineCapStyle = .round
        NSColor.controlAccentColor.setStroke()
        needle.stroke()
        NSColor.controlAccentColor.setFill()
        NSBezierPath(ovalIn: NSRect(x: tip.x - 3, y: tip.y - 3, width: 6, height: 6)).fill()
        NSColor.secondaryLabelColor.setFill()
        NSBezierPath(ovalIn: NSRect(x: c.x - 1.5, y: c.y - 1.5, width: 3, height: 3)).fill()
    }

    override func mouseDown(with event: NSEvent) { if isEnabled { turn(to: event) } }
    override func mouseDragged(with event: NSEvent) { if isEnabled { turn(to: event) } }

    private func turn(to event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        var deg = atan2(p.y - bounds.midY, p.x - bounds.midX) * 180 / .pi
        if event.modifierFlags.contains(.shift) { deg = (deg / 15).rounded() * 15 }   // Shift snaps to 15°
        angle = AngleDial.normalized(deg.rounded())
        onChange?(angle)
    }

    /// Any angle folded into 0..<360.
    static func normalized(_ degrees: Double) -> Double {
        let r = degrees.truncatingRemainder(dividingBy: 360)
        return r < 0 ? r + 360 : r
    }
}
