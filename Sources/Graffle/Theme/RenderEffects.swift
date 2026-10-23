import AppKit

extension UUID {
    /// A stable number derived from the id, so hand-drawn wobble is the same every time a shape is drawn.
    var seed: UInt64 {
        var h: UInt64 = 0xcbf29ce484222325
        withUnsafeBytes(of: uuid) { for b in $0 { h = (h ^ UInt64(b)) &* 0x100000001b3 } }
        return h
    }
}

/// A tiny repeatable random source for hand-drawn effects.
struct SeededRandom {
    private var state: UInt64
    init(_ seed: UInt64) { state = seed == 0 ? 0x9E3779B97F4A7C15 : seed }
    mutating func next() -> Double {
        state ^= state << 13; state ^= state >> 7; state ^= state << 17
        return Double(state % 100_000) / 100_000
    }
}

/// Looks used by themes: hand-drawn lines, hatching, glass, soft shadows and soft 3D.
extension Render {
    // MARK: Hand-drawn lines

    /// A copy of `path` with a gentle, repeatable wobble, like a line drawn by hand. The same `seed` gives the same wobble,
    /// and the wobble is periodic along each outline, so closed shapes meet where they started.
    static func roughened(_ path: CGPath, amount: Double, seed: UInt64) -> CGPath {
        var polylines: [(points: [CGPoint], closed: Bool)] = []
        var current: [CGPoint] = []
        var start = CGPoint.zero, last = CGPoint.zero
        func flush(closed: Bool) { if current.count > 1 { polylines.append((current, closed)) }; current = [] }
        func line(to p: CGPoint) {
            let d = hypot(p.x - last.x, p.y - last.y)
            let n = max(1, Int(d / 5))
            for i in 1...n { let t = CGFloat(i) / CGFloat(n); current.append(CGPoint(x: last.x + (p.x - last.x) * t, y: last.y + (p.y - last.y) * t)) }
            last = p
        }
        path.applyWithBlock { e in
            let p = e.pointee.points
            switch e.pointee.type {
            case .moveToPoint: flush(closed: false); start = p[0]; last = p[0]; current = [p[0]]
            case .addLineToPoint: line(to: p[0])
            case .addQuadCurveToPoint:
                let a = last
                for i in 1...12 {
                    let t = CGFloat(i) / 12, u = 1 - t
                    current.append(CGPoint(x: u * u * a.x + 2 * u * t * p[0].x + t * t * p[1].x, y: u * u * a.y + 2 * u * t * p[0].y + t * t * p[1].y))
                }
                last = p[1]
            case .addCurveToPoint:
                let a = last
                for i in 1...16 {
                    let t = CGFloat(i) / 16, u = 1 - t
                    current.append(CGPoint(x: u * u * u * a.x + 3 * u * u * t * p[0].x + 3 * u * t * t * p[1].x + t * t * t * p[2].x,
                                           y: u * u * u * a.y + 3 * u * u * t * p[0].y + 3 * u * t * t * p[1].y + t * t * t * p[2].y))
                }
                last = p[2]
            case .closeSubpath: line(to: start); flush(closed: true)
            @unknown default: break
            }
        }
        flush(closed: false)

        func unit(_ k: Int) -> Double { Double((seed >> UInt64(k * 11)) & 0x3ff) / 1023.0 }
        let out = CGMutablePath()
        for (pts, closed) in polylines {
            var cum: [CGFloat] = [0]
            for i in 1..<pts.count { cum.append(cum[i - 1] + hypot(pts[i].x - pts[i - 1].x, pts[i].y - pts[i - 1].y)) }
            let length = max(cum.last ?? 1, 1)
            let k1 = max(1, (Double(length) / 70).rounded()), k2 = max(2, (Double(length) / 23).rounded())
            let p1 = unit(0) * 6.28, p2 = unit(1) * 6.28
            let amp = amount * 1.8
            for (i, p) in pts.enumerated() {
                let a = pts[max(i - 1, 0)], b = pts[min(i + 1, pts.count - 1)]
                let tx = b.x - a.x, ty = b.y - a.y
                let l = max(hypot(tx, ty), 0.001)
                let phase = Double(cum[i] / length) * 6.28318
                let n = (sin(phase * k1 + p1) * 0.65 + sin(phase * k2 + p2) * 0.35) * amp
                let q = CGPoint(x: p.x - ty / l * CGFloat(n), y: p.y + tx / l * CGFloat(n))
                if i == 0 { out.move(to: q) } else { out.addLine(to: q) }
            }
            if closed { out.closeSubpath() }
        }
        return out
    }

    /// Strokes `path` the way a crayon would: a few slightly different passes on top of each other.
    static func strokeRough(_ ctx: CGContext, path: CGPath, stroke: Stroke, seed: UInt64) {
        let passes: [(width: Double, alpha: CGFloat, shift: UInt64)] = [(1.0, 1.0, 0), (0.62, 0.6, 7)]
        for pass in passes {
            var s = stroke
            s.width = stroke.width * pass.width
            if s.cap == .butt { s.cap = .round }
            ctx.saveGState()
            applyStroke(ctx, s)
            ctx.setAlpha(pass.alpha)
            ctx.addPath(roughened(path, amount: stroke.roughness * (pass.shift == 0 ? 1 : 1.5), seed: seed &+ pass.shift &* 0x9E3779B97F4A7C15))
            ctx.strokePath()
            ctx.restoreGState()
        }
    }

    // MARK: Effects

    static func gradient(_ stops: [(RGBA, CGFloat)]) -> CGGradient {
        CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB)!, colors: stops.map { $0.0.cg } as CFArray, locations: stops.map { $0.1 })!
    }

    /// Soft shadows in two directions: light from the top-left, dark to the bottom-right.
    static func neumorphicShadows(_ ctx: CGContext, path: CGPath, fill: Fill, size: CGFloat) {
        let d = max(4, min(10, size * 0.08))
        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: -d, height: -d), blur: d * 1.6,
                      color: NSColor(white: 1, alpha: 0.95).cgColor)
        Render.fill(ctx, path: path, fill: fill)
        ctx.restoreGState()
        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: d, height: d), blur: d * 1.6,
                      color: NSColor(srgbRed: 0.45, green: 0.5, blue: 0.62, alpha: 0.5).cgColor)
        Render.fill(ctx, path: path, fill: fill)
        ctx.restoreGState()
    }

    /// A glossy highlight across the top, a faint glow at the bottom and a bright rim, clipped to the shape.
    static func crystalGloss(_ ctx: CGContext, path: CGPath, frame f: CGRect) {
        ctx.saveGState()
        ctx.addPath(path)
        ctx.clip()
        ctx.saveGState()
        ctx.addEllipse(in: CGRect(x: f.minX - f.width * 0.2, y: f.minY - f.height * 0.8, width: f.width * 1.4, height: f.height * 1.55))
        ctx.clip()
        ctx.drawLinearGradient(gradient([(RGBA(1, 1, 1, 0.7), 0), (RGBA(1, 1, 1, 0.08), 1)]),
                               start: CGPoint(x: f.midX, y: f.minY), end: CGPoint(x: f.midX, y: f.minY + f.height * 0.75), options: [])
        ctx.restoreGState()
        ctx.drawLinearGradient(gradient([(RGBA(1, 1, 1, 0), 0), (RGBA(1, 1, 1, 0.28), 1)]),
                               start: CGPoint(x: f.midX, y: f.minY + f.height * 0.6), end: CGPoint(x: f.midX, y: f.maxY), options: [])
        ctx.setStrokeColor(NSColor(white: 1, alpha: 0.75).cgColor)
        ctx.setLineWidth(3)
        ctx.addPath(path)
        ctx.strokePath()
        ctx.restoreGState()
    }

    /// Frosted glass: a soft sheen over the top and a thin light rim on the inside.
    static func glassSheen(_ ctx: CGContext, path: CGPath, frame f: CGRect) {
        ctx.saveGState()
        ctx.addPath(path)
        ctx.clip()
        ctx.drawLinearGradient(gradient([(RGBA(1, 1, 1, 0.32), 0), (RGBA(1, 1, 1, 0), 1)]),
                               start: CGPoint(x: f.minX, y: f.minY), end: CGPoint(x: f.midX + f.width * 0.15, y: f.maxY), options: [])
        ctx.setStrokeColor(NSColor(white: 1, alpha: 0.45).cgColor)
        ctx.setLineWidth(2.5)
        ctx.addPath(path)
        ctx.strokePath()
        ctx.restoreGState()
    }

    /// Diagonal pen strokes inside the shape, with uneven lengths, like a marker or chalk scribble.
    static func hatch(_ ctx: CGContext, path: CGPath, frame f: CGRect, color: RGBA, seed: UInt64) {
        var rng = SeededRandom(seed)
        ctx.saveGState()
        ctx.addPath(path)
        ctx.clip()
        ctx.setStrokeColor(color.cg)
        ctx.setLineWidth(1.7)
        ctx.setLineCap(.round)
        let spacing: CGFloat = 8, slant = f.height * 0.9
        var x = f.minX - slant
        while x < f.maxX {
            let jitter = CGFloat(rng.next() * 3 - 1.5)
            let top = f.minY + CGFloat(rng.next()) * f.height * 0.18
            let bottom = f.maxY - CGFloat(rng.next()) * f.height * 0.18
            let t0 = (bottom - f.minY) / f.height, t1 = (top - f.minY) / f.height
            ctx.move(to: CGPoint(x: x + slant * (1 - t0) + jitter, y: bottom))
            ctx.addLine(to: CGPoint(x: x + slant * (1 - t1) + jitter, y: top))
            x += spacing + CGFloat(rng.next() * 3)
        }
        ctx.strokePath()
        ctx.restoreGState()
    }

    /// A lit edge on the top-left and a shaded one on the bottom-right, as on a soft 3D button.
    static func clayShading(_ ctx: CGContext, path: CGPath) {
        ctx.saveGState()
        ctx.addPath(path)
        ctx.clip()
        for (width, alpha) in [(14.0, 0.10), (8.0, 0.14), (3.0, 0.22)] {
            ctx.saveGState()
            ctx.translateBy(x: 4, y: 4)
            ctx.setStrokeColor(NSColor(white: 1, alpha: alpha).cgColor)
            ctx.setLineWidth(width)
            ctx.addPath(path)
            ctx.strokePath()
            ctx.restoreGState()
            ctx.saveGState()
            ctx.translateBy(x: -4, y: -4)
            ctx.setStrokeColor(NSColor(srgbRed: 0.1, green: 0.05, blue: 0.2, alpha: alpha * 1.3).cgColor)
            ctx.setLineWidth(width)
            ctx.addPath(path)
            ctx.strokePath()
            ctx.restoreGState()
        }
        ctx.restoreGState()
    }

    /// Black or white strokes that read on this fill.
    static func hatchColor(for fill: Fill) -> RGBA {
        switch fill.kind {
        case .none: return RGBA(1, 1, 1, 0.4)
        default: return fill.averageLuminance > 0.6 ? RGBA(0, 0, 0, 0.22) : RGBA(1, 1, 1, 0.42)
        }
    }
}
