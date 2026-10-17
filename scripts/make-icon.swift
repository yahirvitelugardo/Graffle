// Builds Assets/AppIcon.iconset (and a preview) from Assets/AppIcon-source.jpg.
// The art is placed on a rounded-square tile with the margin and soft shadow macOS icons use.
// Run through scripts/make-icon.sh, which also turns the iconset into AppIcon.icns.
import AppKit

let root = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : FileManager.default.currentDirectoryPath)
let source = root.appendingPathComponent("Assets/AppIcon-source.jpg")
let iconset = root.appendingPathComponent("Assets/AppIcon.iconset")

guard let art = NSImage(contentsOf: source), let cg = art.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
    FileHandle.standardError.write(Data("Can't read \(source.path)\n".utf8))
    exit(1)
}

func render(_ px: Int) -> Data? {
    let s = CGFloat(px) / 1024
    guard let ctx = CGContext(data: nil, width: px, height: px, bitsPerComponent: 8, bytesPerRow: 0,
                              space: CGColorSpace(name: CGColorSpace.sRGB)!,
                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
    ctx.interpolationQuality = .high

    // macOS icon grid: an 824-pt tile centered in a 1024-pt canvas, corner radius about 22.4% of the tile.
    let tile = CGRect(x: 100 * s, y: 100 * s, width: 824 * s, height: 824 * s)
    let path = CGPath(roundedRect: tile, cornerWidth: 184 * s, cornerHeight: 184 * s, transform: nil)

    // Soft drop shadow under the tile.
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -10 * s), blur: 22 * s, color: CGColor(gray: 0, alpha: 0.30))
    ctx.setFillColor(CGColor(gray: 1, alpha: 1))
    ctx.addPath(path); ctx.fillPath()
    ctx.restoreGState()

    // The artwork, clipped to the tile.
    ctx.saveGState()
    ctx.addPath(path); ctx.clip()
    // The source art has generous white margins; enlarge it so it fills the tile like a normal app icon.
    let zoom: CGFloat = 1.15
    ctx.draw(cg, in: tile.insetBy(dx: -tile.width * (zoom - 1) / 2, dy: -tile.height * (zoom - 1) / 2))
    ctx.restoreGState()

    // A hairline edge so the white tile reads on a white background.
    ctx.setStrokeColor(CGColor(gray: 0, alpha: 0.10))
    ctx.setLineWidth(max(1, 2 * s))
    ctx.addPath(path); ctx.strokePath()

    guard let img = ctx.makeImage() else { return nil }
    return NSBitmapImageRep(cgImage: img).representation(using: .png, properties: [:])
}

try? FileManager.default.removeItem(at: iconset)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

// name -> pixel size, as iconutil expects.
let sizes: [(String, Int)] = [
    ("icon_16x16", 16), ("icon_16x16@2x", 32), ("icon_32x32", 32), ("icon_32x32@2x", 64),
    ("icon_128x128", 128), ("icon_128x128@2x", 256), ("icon_256x256", 256), ("icon_256x256@2x", 512),
    ("icon_512x512", 512), ("icon_512x512@2x", 1024),
]
for (name, px) in sizes {
    guard let data = render(px) else { FileHandle.standardError.write(Data("Failed at \(name)\n".utf8)); exit(1) }
    try data.write(to: iconset.appendingPathComponent(name + ".png"))
}
print("Wrote \(sizes.count) sizes to \(iconset.path)")
