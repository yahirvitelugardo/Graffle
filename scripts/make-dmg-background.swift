// Draws the installer window's background: Assets/dmg-background.png (660 x 400 points, saved at 2x).
import AppKit

let root = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : FileManager.default.currentDirectoryPath)
let out = root.appendingPathComponent("Assets/dmg-background.png")
let size = CGSize(width: 660, height: 400)
let scale: CGFloat = 2

guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width * scale), pixelsHigh: Int(size.height * scale),
                                 bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                 colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
      let gc = NSGraphicsContext(bitmapImageRep: rep) else { exit(1) }
rep.size = size   // 1320 x 800 pixels at 144 dpi: Finder shows it at 660 x 400 points

NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = gc
let ctx = gc.cgContext
ctx.scaleBy(x: scale, y: scale)

// Soft vertical gradient.
let space = CGColorSpace(name: CGColorSpace.sRGB)!
let gradient = CGGradient(colorsSpace: space, colors: [
    CGColor(srgbRed: 0.97, green: 0.98, blue: 1.0, alpha: 1), CGColor(srgbRed: 0.88, green: 0.91, blue: 0.97, alpha: 1),
] as CFArray, locations: [0, 1])!
ctx.drawLinearGradient(gradient, start: CGPoint(x: 0, y: size.height), end: CGPoint(x: 0, y: 0), options: [])

func text(_ s: String, size pt: CGFloat, weight: NSFont.Weight, color: NSColor, at center: CGPoint) {
    let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: pt, weight: weight), .foregroundColor: color]
    let str = NSAttributedString(string: s, attributes: attrs)
    let sz = str.size()
    str.draw(at: CGPoint(x: center.x - sz.width / 2, y: center.y - sz.height / 2))
}

text("Install Graffle", size: 26, weight: .semibold, color: NSColor(white: 0.12, alpha: 1), at: CGPoint(x: 330, y: 340))
text("Drag the app onto the Applications folder", size: 13, weight: .regular, color: NSColor(white: 0.35, alpha: 1),
     at: CGPoint(x: 330, y: 308))

// An arrow between where the app and the Applications folder sit (icons are at x = 170 and x = 490, y = 200 from the top).
let y: CGFloat = 400 - 200
ctx.setStrokeColor(CGColor(srgbRed: 0.35, green: 0.45, blue: 0.70, alpha: 0.9))
ctx.setFillColor(CGColor(srgbRed: 0.35, green: 0.45, blue: 0.70, alpha: 0.9))
ctx.setLineWidth(5)
ctx.setLineCap(.round)
ctx.move(to: CGPoint(x: 250, y: y)); ctx.addLine(to: CGPoint(x: 386, y: y)); ctx.strokePath()
ctx.move(to: CGPoint(x: 415, y: y)); ctx.addLine(to: CGPoint(x: 390, y: y + 17)); ctx.addLine(to: CGPoint(x: 390, y: y - 17)); ctx.closePath()
ctx.fillPath()

text("by EVM  ·  evm.mx", size: 11, weight: .regular, color: NSColor(white: 0.45, alpha: 1), at: CGPoint(x: 330, y: 24))

NSGraphicsContext.restoreGraphicsState()
try rep.representation(using: .png, properties: [:])!.write(to: out)
print("Wrote \(out.path)")
