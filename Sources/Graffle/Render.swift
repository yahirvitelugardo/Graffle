import AppKit

/// Stateless drawing helpers shared by the canvas and the exporters.
enum Render {
    // MARK: Text

    static func font(_ t: TextFormat) -> NSFont {
        let size = CGFloat(t.size)
        var f: NSFont
        if t.font == "System" {
            f = .systemFont(ofSize: size)
        } else {
            let desc = NSFontDescriptor(fontAttributes: [.family: t.font])
            f = NSFont(descriptor: desc, size: size) ?? .systemFont(ofSize: size)
        }
        let fm = NSFontManager.shared
        if t.bold { f = fm.convert(f, toHaveTrait: .boldFontMask) }
        if t.italic { f = fm.convert(f, toHaveTrait: .italicFontMask) }
        return f
    }

    /// Black or white, whichever contrasts with the fill (explicit text color wins).
    static func textColor(_ t: TextFormat, fill: Fill) -> NSColor {
        if let c = t.color { return c.ns }
        switch fill.kind {
        case .none: return .black
        case .solid: return (fill.color.a > 0.3 && fill.color.isDark) ? .white : .black
        case .linear, .radial:
            return fill.averageLuminance < 0.5 ? .white : .black
        }
    }

    static func attributes(_ t: TextFormat, color: NSColor) -> [NSAttributedString.Key: Any] {
        let para = NSMutableParagraphStyle()
        switch t.hAlign {
        case .left: para.alignment = .left
        case .center: para.alignment = .center
        case .right: para.alignment = .right
        }
        para.lineBreakMode = .byWordWrapping
        var attrs: [NSAttributedString.Key: Any] = [
            .font: font(t), .foregroundColor: color, .paragraphStyle: para,
        ]
        if t.underline { attrs[.underlineStyle] = NSUnderlineStyle.single.rawValue }
        return attrs
    }

    static func drawText(_ text: String, in rect: CGRect, format t: TextFormat, color: NSColor) {
        let str = NSAttributedString(string: text, attributes: attributes(t, color: color))
        let h = str.boundingRect(with: CGSize(width: rect.width, height: .greatestFiniteMagnitude),
                                 options: [.usesLineFragmentOrigin]).height
        let bh = min(h, rect.height)
        let y: CGFloat
        switch t.vAlign {
        case .top: y = rect.minY
        case .middle: y = rect.midY - bh / 2
        case .bottom: y = rect.maxY - bh
        }
        str.draw(with: CGRect(x: rect.minX, y: y, width: rect.width, height: bh), options: [.usesLineFragmentOrigin])
    }

    // MARK: Stroke and fill

    static func applyStroke(_ ctx: CGContext, _ s: Stroke) {
        ctx.setStrokeColor(s.color.cg)
        ctx.setLineWidth(CGFloat(s.width))
        // Dots need round caps to read as dots.
        ctx.setLineCap(s.dash == .dotted && s.cap == .butt ? .round : s.cap.cg)
        ctx.setLineJoin(s.join.cg)
        ctx.setLineDash(phase: 0, lengths: s.dash.pattern(width: s.width))
    }

    static func fill(_ ctx: CGContext, path: CGPath, fill f: Fill) {
        switch f.kind {
        case .none:
            return
        case .solid:
            ctx.setFillColor(f.color.cg)
            ctx.addPath(path)
            ctx.fillPath()
        case .linear, .radial:
            let b = path.boundingBoxOfPath
            let stops = f.sortedStops
            guard stops.count >= 2, let space = CGColorSpace(name: CGColorSpace.sRGB),
                  let g = CGGradient(colorsSpace: space, colors: stops.map { $0.color.cg } as CFArray,
                                     locations: stops.map { CGFloat(min(max($0.position, 0), 1)) })
            else {
                // A single stop is just a flat color.
                if let only = f.stops.first {
                    ctx.setFillColor(only.color.cg)
                    ctx.addPath(path)
                    ctx.fillPath()
                }
                return
            }
            ctx.saveGState()
            ctx.addPath(path)
            ctx.clip()
            let c = CGPoint(x: b.midX, y: b.midY)
            if f.kind == .linear {
                let rad = CGFloat(f.angle) * .pi / 180
                let dir = CGPoint(x: cos(rad), y: sin(rad))
                // Half the extent of the box projected on the gradient axis, so the ends touch the corners.
                let half = (abs(b.width * dir.x) + abs(b.height * dir.y)) / 2
                ctx.drawLinearGradient(g, start: CGPoint(x: c.x - dir.x * half, y: c.y - dir.y * half),
                                       end: CGPoint(x: c.x + dir.x * half, y: c.y + dir.y * half),
                                       options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
            } else {
                ctx.drawRadialGradient(g, startCenter: c, startRadius: 0, endCenter: c,
                                       endRadius: max(hypot(b.width, b.height) / 2, 1),
                                       options: [.drawsAfterEndLocation])
            }
            ctx.restoreGState()
        }
    }

    // MARK: Arrowheads

    /// `angle` points out of the line, through `tip`.
    /// With `eraseHollow`, hollow heads clear their interior (for template glyphs) instead of painting it white.
    static func drawHead(_ ctx: CGContext, kind: HeadKind, tip: CGPoint, angle: CGFloat, scale: Double, stroke: Stroke,
                         eraseHollow: Bool = false) {
        guard kind != .none else { return }
        let w = CGFloat(max(stroke.width, 1))
        let len = (8 + w * 1.5) * CGFloat(scale)
        let dir = CGPoint(x: cos(angle), y: sin(angle))
        let perp = CGPoint(x: -dir.y, y: dir.x)
        func pt(_ back: CGFloat, _ side: CGFloat) -> CGPoint {
            CGPoint(x: tip.x - dir.x * back + perp.x * side, y: tip.y - dir.y * back + perp.y * side)
        }

        ctx.saveGState()
        ctx.setLineDash(phase: 0, lengths: [])
        ctx.setLineJoin(.round)
        ctx.setLineCap(.round)
        ctx.setLineWidth(w)
        ctx.setStrokeColor(stroke.color.cg)

        /// Fills the current path with `color`, or erases it when drawing a template glyph.
        func paintHollow() {
            if eraseHollow {
                ctx.saveGState()
                ctx.setBlendMode(.clear)
                ctx.fillPath()
                ctx.restoreGState()
            } else {
                ctx.setFillColor(NSColor.white.cgColor)
                ctx.fillPath()
            }
        }

        func polygon(_ pts: [CGPoint], filled: Bool) {
            ctx.addLines(between: pts)
            ctx.closePath()
            if filled {
                ctx.setFillColor(stroke.color.cg)
                ctx.drawPath(using: .fillStroke)
            } else {
                let path = ctx.path
                ctx.beginPath()
                if let path { ctx.addPath(path) }
                paintHollow()
                if let path { ctx.addPath(path) }
                ctx.strokePath()
            }
        }

        switch kind {
        case .none:
            break
        case .filledArrow:
            polygon([pt(0, 0), pt(len, len * 0.38), pt(len, -len * 0.38)], filled: true)
        case .openArrow:
            ctx.move(to: pt(len, len * 0.42)); ctx.addLine(to: pt(0, 0)); ctx.addLine(to: pt(len, -len * 0.42))
            ctx.strokePath()
        case .hollowTriangle:
            polygon([pt(0, 0), pt(len, len * 0.38), pt(len, -len * 0.38)], filled: false)
        case .filledDiamond, .hollowDiamond:
            polygon([pt(0, 0), pt(len / 2, len * 0.32), pt(len, 0), pt(len / 2, -len * 0.32)],
                    filled: kind == .filledDiamond)
        case .filledCircle, .hollowCircle:
            let c = pt(len * 0.4, 0), r = len * 0.4
            let circle = CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)
            if kind == .filledCircle {
                ctx.addEllipse(in: circle)
                ctx.setFillColor(stroke.color.cg)
                ctx.drawPath(using: .fillStroke)
            } else {
                ctx.addEllipse(in: circle)
                paintHollow()
                ctx.addEllipse(in: circle)
                ctx.strokePath()
            }
        case .bar:
            ctx.move(to: pt(0, len * 0.45)); ctx.addLine(to: pt(0, -len * 0.45))
            ctx.strokePath()
        case .crowFoot, .crowFootBar, .crowFootCircle, .doubleBar, .circleBar:
            let parts = entityEnd(kind, len: len)
            for (a, b) in parts.lines {
                ctx.move(to: pt(a.x, a.y)); ctx.addLine(to: pt(b.x, b.y))
            }
            ctx.strokePath()
            if let c = parts.circle {
                let center = pt(c.back, 0)
                let circle = CGRect(x: center.x - c.radius, y: center.y - c.radius, width: c.radius * 2, height: c.radius * 2)
                ctx.addEllipse(in: circle)
                paintHollow()
                ctx.addEllipse(in: circle)
                ctx.strokePath()
            }
        }
        ctx.restoreGState()
    }

    /// The strokes of an entity-relationship line end, as (back, side) offsets from the tip: each line is a pair of points,
    /// plus an optional hollow circle (distance back from the tip, radius). Shared by the canvas and the SVG export.
    static func entityEnd(_ kind: HeadKind, len: CGFloat) -> (lines: [(CGPoint, CGPoint)], circle: (back: CGFloat, radius: CGFloat)?) {
        func bar(_ back: CGFloat) -> (CGPoint, CGPoint) { (CGPoint(x: back, y: len * 0.45), CGPoint(x: back, y: -len * 0.45)) }
        let foot = len * 0.95
        let toes: [(CGPoint, CGPoint)] = [
            (CGPoint(x: foot, y: 0), CGPoint(x: 0, y: len * 0.5)),
            (CGPoint(x: foot, y: 0), CGPoint(x: 0, y: 0)),
            (CGPoint(x: foot, y: 0), CGPoint(x: 0, y: -len * 0.5)),
        ]
        switch kind {
        case .crowFoot: return (toes, nil)
        case .crowFootBar: return (toes + [bar(len * 1.3)], nil)
        case .crowFootCircle: return (toes, (len * 1.55, len * 0.32))
        case .doubleBar: return ([bar(len * 0.3), bar(len * 0.7)], nil)
        case .circleBar: return ([bar(len * 0.3)], (len * 0.85, len * 0.32))
        default: return ([], nil)
        }
    }
}
