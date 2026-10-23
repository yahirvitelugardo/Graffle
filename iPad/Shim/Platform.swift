import UIKit

// The shared drawing code was written against AppKit; these aliases let it compile unchanged on iOS.
typealias NSColor = UIColor
typealias NSFont = UIFont
typealias NSFontDescriptor = UIFontDescriptor
typealias NSImage = UIImage
typealias NSSize = CGSize
typealias NSPoint = CGPoint
typealias NSRect = CGRect

extension UIColor {
    convenience init(srgbRed r: CGFloat, green g: CGFloat, blue b: CGFloat, alpha a: CGFloat) {
        self.init(red: r, green: g, blue: b, alpha: a)
    }
    static var labelColor: UIColor { .label }
}

extension LibraryItem {
    /// Lines like braces and brackets have no inside to fill.
    var isOpenPath: Bool {
        guard circuit == nil, custom == nil, let outline, !outline.isEmpty else { return false }
        return !outline.contains { $0.op == .close }
    }
}
