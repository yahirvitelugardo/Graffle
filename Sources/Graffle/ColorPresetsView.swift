import AppKit

/// A palette of ready-made fill colors: a row of six large grays, and under each a small 2 x 2 block
/// of one hue running from saturated (top) to pale (bottom).
final class ColorPresetsView: NSView {
    private static func hex(_ v: UInt32) -> RGBA {
        RGBA(Double((v >> 16) & 255) / 255, Double((v >> 8) & 255) / 255, Double(v & 255) / 255)
    }

    static let grays: [RGBA] = [0x000000, 0x2B2B2B, 0x565656, 0x8D8D8D, 0xC3C3C3, 0xFFFFFF].map(hex)

    /// Blue, red, magenta, green, cyan, yellow. Each hue: top-left, top-right, bottom-left, bottom-right.
    static let hues: [[RGBA]] = [
        [0x0014FF, 0x3347FF, 0x7580FF, 0xBBBFFF],
        [0xF52B1B, 0xF04E45, 0xF37D78, 0xF8B8B4],
        [0xEB3CFF, 0xEF5CFF, 0xF188F5, 0xF5BDF8],
        [0x55FF33, 0x66FF4D, 0x8FEE7C, 0xBAF5AD],
        [0x40F5F5, 0x66FAFA, 0x8CF5F5, 0xBEFAFA],
        [0xFFFF1A, 0xFFFF59, 0xFAF28A, 0xFFFFBF],
    ].map { $0.map(hex) }

    struct Swatch {
        var rect: CGRect
        var color: RGBA
        var large: Bool
    }

    /// The color the current fill already has, outlined in the palette if it is one of the swatches.
    var selectedColor: RGBA? { didSet { needsDisplay = true } }

    /// Called with the swatch's color when one is clicked.
    var onPick: ((RGBA) -> Void)?

    override var isFlipped: Bool { true }
    override var intrinsicContentSize: NSSize { NSSize(width: 232, height: 76) }

    /// All 30 swatches laid out for the current width: large ones first, then the small ones group by group.
    var swatches: [Swatch] {
        let large: CGFloat = 32, innerGap: CGFloat = 4, rowGap: CGFloat = 10
        let gap = max((bounds.width - 6 * large) / 5, 2)
        let small = (large - innerGap) / 2
        var out: [Swatch] = []
        for (i, c) in ColorPresetsView.grays.enumerated() {
            out.append(Swatch(rect: CGRect(x: CGFloat(i) * (large + gap), y: 0, width: large, height: large), color: c, large: true))
        }
        for (g, colors) in ColorPresetsView.hues.enumerated() {
            let x0 = CGFloat(g) * (large + gap)
            for (k, c) in colors.enumerated() {
                let col = CGFloat(k % 2), row = CGFloat(k / 2)
                out.append(Swatch(rect: CGRect(x: x0 + col * (small + innerGap), y: large + rowGap + row * (small + 6),
                                               width: small, height: small), color: c, large: false))
            }
        }
        return out
    }

    private func matches(_ a: RGBA, _ b: RGBA) -> Bool {
        abs(a.r - b.r) < 0.004 && abs(a.g - b.g) < 0.004 && abs(a.b - b.b) < 0.004 && a.a > 0.99
    }

    override func draw(_ dirtyRect: NSRect) {
        for s in swatches {
            let radius: CGFloat = s.large ? 9 : 4
            let path = NSBezierPath(roundedRect: s.rect, xRadius: radius, yRadius: radius)
            s.color.ns.setFill()
            path.fill()
            NSColor(white: 0, alpha: 0.28).setStroke()
            path.lineWidth = 1
            path.stroke()
            if let sel = selectedColor, matches(sel, s.color) {
                let ring = NSBezierPath(roundedRect: s.rect.insetBy(dx: -2.5, dy: -2.5), xRadius: radius + 2, yRadius: radius + 2)
                Tok.accent.setStroke()
                ring.lineWidth = 2
                ring.stroke()
            }
        }
    }

    override func mouseDown(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        if let hit = swatches.first(where: { $0.rect.contains(p) }) {
            selectedColor = hit.color
            onPick?(hit.color)
        }
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        toolTip = "Click a swatch to use it as the fill color"
    }
}
