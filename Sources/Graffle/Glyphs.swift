import AppKit

/// Small pictures that stand in for words in the inspector's menus and segmented controls.
/// Line glyphs are drawn in black and marked as templates, so AppKit tints them for light/dark mode
/// and for the highlighted menu row. Color swatches (fill types) are not templates.
enum Glyphs {
    private static func make(_ size: NSSize, template: Bool = true, _ draw: @escaping (CGContext) -> Void) -> NSImage {
        let img = NSImage(size: size, flipped: false) { _ in
            guard let ctx = NSGraphicsContext.current?.cgContext else { return false }
            draw(ctx)
            return true
        }
        img.isTemplate = template
        return img
    }

    private static func ink(_ ctx: CGContext, _ alpha: CGFloat = 1) {
        ctx.setStrokeColor(NSColor(white: 0, alpha: alpha).cgColor)
        ctx.setFillColor(NSColor(white: 0, alpha: alpha).cgColor)
    }

    // MARK: Line pattern

    static func dash(_ kind: DashKind) -> NSImage {
        make(NSSize(width: 96, height: 16)) { ctx in
            ink(ctx)
            let w: CGFloat = 2.5
            ctx.setLineWidth(w)
            ctx.setLineCap(kind == .dotted ? .round : .butt)
            ctx.setLineDash(phase: 0, lengths: kind.pattern(width: Double(w)))
            ctx.move(to: CGPoint(x: 6, y: 8))
            ctx.addLine(to: CGPoint(x: 90, y: 8))
            ctx.strokePath()
        }
    }

    // MARK: Line caps and joins

    /// A fat segment with faint end markers, so butt/round/square differ visibly.
    static func cap(_ kind: CapKind) -> NSImage {
        make(NSSize(width: 96, height: 20)) { ctx in
            ink(ctx, 0.35)
            ctx.setLineWidth(1)
            for x in [28.0, 68.0] { ctx.move(to: CGPoint(x: x, y: 1)); ctx.addLine(to: CGPoint(x: x, y: 19)) }
            ctx.strokePath()
            ink(ctx)
            ctx.setLineWidth(10)
            ctx.setLineCap(kind.cg)
            ctx.move(to: CGPoint(x: 28, y: 10))
            ctx.addLine(to: CGPoint(x: 68, y: 10))
            ctx.strokePath()
        }
    }

    static func join(_ kind: JoinKind) -> NSImage {
        // Kept small: this sits in a narrow row, and a corner reads fine at this size.
        make(NSSize(width: 48, height: 18)) { ctx in
            ink(ctx)
            ctx.setLineWidth(5)
            ctx.setLineJoin(kind.cg)
            ctx.setLineCap(.butt)
            ctx.move(to: CGPoint(x: 15, y: 3))
            ctx.addLine(to: CGPoint(x: 24, y: 12))
            ctx.addLine(to: CGPoint(x: 33, y: 3))
            ctx.strokePath()
        }
    }

    // MARK: Connector types and arrowheads

    static func route(_ route: Route) -> NSImage {
        make(NSSize(width: 96, height: 28)) { ctx in
            let a = CGRect(x: 4, y: 3, width: 16, height: 10)
            let b = CGRect(x: 76, y: 15, width: 16, height: 10)
            ink(ctx, 0.45)
            ctx.setLineWidth(1.2)
            ctx.stroke(a)
            ctx.stroke(b)

            ink(ctx)
            ctx.setLineWidth(1.8)
            ctx.setLineJoin(.round)
            let p1 = CGPoint(x: a.maxX, y: a.midY), p2 = CGPoint(x: b.minX, y: b.midY)
            ctx.move(to: p1)
            switch route {
            case .straight:
                ctx.addLine(to: p2)
            case .curved:
                ctx.addCurve(to: p2, control1: CGPoint(x: p1.x + 28, y: p1.y), control2: CGPoint(x: p2.x - 28, y: p2.y))
            case .orthogonal:
                ctx.addLines(between: [p1, CGPoint(x: 48, y: p1.y), CGPoint(x: 48, y: p2.y), p2])
            case .rounded:
                let mx: CGFloat = 48, r: CGFloat = 5
                ctx.addArc(tangent1End: CGPoint(x: mx, y: p1.y), tangent2End: CGPoint(x: mx, y: p2.y), radius: r)
                ctx.addArc(tangent1End: CGPoint(x: mx, y: p2.y), tangent2End: p2, radius: r)
                ctx.addLine(to: p2)
            }
            ctx.strokePath()
        }
    }

    /// A line with the head at its start (`atEnd == false`) or its end.
    static func head(_ kind: HeadKind, atEnd: Bool) -> NSImage {
        make(NSSize(width: 96, height: 22)) { ctx in
            ink(ctx)
            let stroke = Stroke(visible: true, color: RGBA(0, 0, 0), width: 2, dash: .solid, cap: .butt, join: .round)
            let y: CGFloat = 11
            ctx.setLineWidth(2)
            ctx.move(to: CGPoint(x: 6, y: y))
            ctx.addLine(to: CGPoint(x: 90, y: y))
            ctx.strokePath()
            let tip = CGPoint(x: atEnd ? 90 : 6, y: y)
            // Hollow heads erase the line beneath them instead of painting white, which keeps the glyph a clean template.
            Render.drawHead(ctx, kind: kind, tip: tip, angle: atEnd ? 0 : .pi, scale: 1.25, stroke: stroke, eraseHollow: true)
        }
    }

    // MARK: Fill types (color swatches, not templates)

    static func fill(_ kind: FillKind) -> NSImage {
        make(NSSize(width: 44, height: 18), template: false) { ctx in
            let r = CGRect(x: 1, y: 1, width: 42, height: 16)
            let path = CGPath(roundedRect: r, cornerWidth: 3, cornerHeight: 3, transform: nil)
            let space = CGColorSpace(name: CGColorSpace.sRGB)!
            switch kind {
            case .none:
                ctx.setFillColor(NSColor.white.cgColor)
                ctx.addPath(path); ctx.fillPath()
                ctx.saveGState()
                ctx.addPath(path); ctx.clip()
                ctx.setStrokeColor(NSColor(srgbRed: 0.85, green: 0.2, blue: 0.2, alpha: 1).cgColor)
                ctx.setLineWidth(1.5)
                ctx.move(to: CGPoint(x: 4, y: 1)); ctx.addLine(to: CGPoint(x: 40, y: 17))
                ctx.strokePath()
                ctx.restoreGState()
            case .solid:
                ctx.setFillColor(NSColor(srgbRed: 0.35, green: 0.55, blue: 0.95, alpha: 1).cgColor)
                ctx.addPath(path); ctx.fillPath()
            case .linear:
                let g = CGGradient(colorsSpace: space, colors: [NSColor(srgbRed: 1, green: 0.62, blue: 0.3, alpha: 1).cgColor,
                                                                NSColor(srgbRed: 0.45, green: 0.3, blue: 0.9, alpha: 1).cgColor] as CFArray,
                                   locations: [0, 1])!
                ctx.saveGState(); ctx.addPath(path); ctx.clip()
                ctx.drawLinearGradient(g, start: CGPoint(x: r.minX, y: r.midY), end: CGPoint(x: r.maxX, y: r.midY), options: [])
                ctx.restoreGState()
            case .radial:
                let g = CGGradient(colorsSpace: space, colors: [NSColor(srgbRed: 1, green: 0.95, blue: 0.7, alpha: 1).cgColor,
                                                                NSColor(srgbRed: 0.95, green: 0.55, blue: 0.2, alpha: 1).cgColor] as CFArray,
                                   locations: [0, 1])!
                ctx.saveGState(); ctx.addPath(path); ctx.clip()
                ctx.drawRadialGradient(g, startCenter: CGPoint(x: r.midX, y: r.midY), startRadius: 0,
                                       endCenter: CGPoint(x: r.midX, y: r.midY), endRadius: 22, options: [.drawsAfterEndLocation])
                ctx.restoreGState()
            }
            ctx.setStrokeColor(NSColor(white: 0, alpha: 0.35).cgColor)
            ctx.setLineWidth(1)
            ctx.addPath(path); ctx.strokePath()
        }
    }

    // MARK: Text alignment

    static func hAlign(_ a: HAlign) -> NSImage {
        make(NSSize(width: 18, height: 14)) { ctx in
            ink(ctx)
            ctx.setLineWidth(1.6)
            let lengths: [CGFloat] = [15, 9, 13, 7]
            for (i, len) in lengths.enumerated() {
                let y = 2 + CGFloat(i) * 3.4
                let x0: CGFloat
                switch a {
                case .left: x0 = 1.5
                case .center: x0 = (18 - len) / 2
                case .right: x0 = 16.5 - len
                }
                ctx.move(to: CGPoint(x: x0, y: y)); ctx.addLine(to: CGPoint(x: x0 + len, y: y))
            }
            ctx.strokePath()
        }
    }

    static func vAlign(_ a: VAlign) -> NSImage {
        make(NSSize(width: 18, height: 14)) { ctx in
            ink(ctx, 0.4)
            ctx.setLineWidth(1)
            ctx.stroke(CGRect(x: 1.5, y: 1.5, width: 15, height: 11))
            ink(ctx)
            ctx.setLineWidth(1.6)
            let ys: [CGFloat]
            switch a {
            case .top: ys = [10.5, 8]
            case .middle: ys = [8, 5.5]
            case .bottom: ys = [5, 2.5]
            }
            for y in ys { ctx.move(to: CGPoint(x: 4, y: y)); ctx.addLine(to: CGPoint(x: 14, y: y)) }
            ctx.strokePath()
        }
    }
}
