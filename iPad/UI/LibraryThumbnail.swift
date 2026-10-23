import SwiftUI
import UIKit

/// Draws the little picture of a library item (the same drawing code as the Mac app's thumbnails).
enum LibraryThumbnail {
    static func draw(_ item: LibraryItem, in rect: CGRect, ink: CGColor, fill: CGColor, ctx: CGContext) {
        ctx.saveGState()
        defer { ctx.restoreGState() }
        var drawing = item.previewShapes()
        if item.kind == .rounded, item.compose == nil, item.custom == nil, !drawing.isEmpty { drawing[0].style.cornerRadius = item.cornerRadius > 0 ? item.cornerRadius : 12 }
        let box = drawing.map(\.worldBounds).reduce(nil) { acc, f in acc.map { $0.union(f) } ?? f } ?? .zero
        guard box.width > 0, box.height > 0 else { return }
        let scale = min(rect.width / box.width, rect.height / box.height)
        ctx.translateBy(x: rect.midX - box.midX * scale, y: rect.midY - box.midY * scale)
        ctx.scaleBy(x: scale, y: scale)
        let line = 1.5 / scale
        for s in drawing {
            let path = s.worldPath()
            ctx.setLineJoin(.round); ctx.setLineCap(.round)
            if item.compose != nil {
                guard s.style.stroke.visible else { continue }
                if s.style.fill.kind != .none { ctx.setFillColor(fill); ctx.addPath(path); ctx.fillPath() }
                ctx.setStrokeColor(ink); ctx.setLineWidth(line); ctx.addPath(path); ctx.strokePath()
                continue
            }
            if item.hasOwnLook {
                if s.style.fill.kind != .none { ctx.setFillColor(s.style.fill.color.cg); ctx.addPath(path); ctx.fillPath() }
                if s.style.stroke.visible { ctx.setStrokeColor(s.style.stroke.color.cg); ctx.setLineWidth(max(line, 1 / scale)); ctx.addPath(path); ctx.strokePath() }
                continue
            }
            let filled = item.circuit == nil && !item.isOpenPath
            if filled || item.circuit == .junction { ctx.setFillColor(item.circuit == .junction ? ink : fill); ctx.addPath(path); ctx.fillPath() }
            if item.circuit != .junction { ctx.setStrokeColor(ink); ctx.setLineWidth(line); ctx.addPath(path); ctx.strokePath() }
        }
    }

    /// An image of the item, used as the drag preview.
    static func image(_ item: LibraryItem, size: CGSize, scheme: ColorScheme) -> UIImage {
        let traits = UITraitCollection(userInterfaceStyle: scheme == .dark ? .dark : .light)
        let ink = Tok.iconDefault.resolvedColor(with: traits).cgColor
        let fill = Tok.accent.resolvedColor(with: traits).withAlphaComponent(0.16).cgColor
        return UIGraphicsImageRenderer(size: size).image { r in
            draw(item, in: CGRect(origin: .zero, size: size).insetBy(dx: 2, dy: 2), ink: ink, fill: fill, ctx: r.cgContext)
        }
    }
}

/// SwiftUI view of an item's thumbnail.
struct LibraryThumbnailView: View {
    let item: LibraryItem
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        Canvas { context, size in
            let traits = UITraitCollection(userInterfaceStyle: scheme == .dark ? .dark : .light)
            let ink = Tok.iconDefault.resolvedColor(with: traits).cgColor
            let fill = Tok.accent.resolvedColor(with: traits).withAlphaComponent(0.16).cgColor
            context.withCGContext { cg in
                LibraryThumbnail.draw(item, in: CGRect(origin: .zero, size: size), ink: ink, fill: fill, ctx: cg)
            }
        }
    }
}
