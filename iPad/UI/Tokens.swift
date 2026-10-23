import UIKit

/// The interface's colors, radii and spacing, shared with the Mac app's design. Colors follow light / dark.
enum Tok {
    private static func hex(_ v: UInt32, _ a: CGFloat = 1) -> UIColor {
        UIColor(red: CGFloat((v >> 16) & 0xff) / 255, green: CGFloat((v >> 8) & 0xff) / 255, blue: CGFloat(v & 0xff) / 255, alpha: a)
    }
    private static func white(_ a: CGFloat) -> UIColor { UIColor(white: 1, alpha: a) }
    private static func black(_ a: CGFloat) -> UIColor { UIColor(white: 0, alpha: a) }

    /// A color that is `light` in the light appearance and `dark` in the dark one.
    static func dynamic(light: UIColor, dark: UIColor) -> UIColor {
        UIColor { $0.userInterfaceStyle == .dark ? dark : light }
    }

    // Surfaces
    static let windowBG = dynamic(light: hex(0xECECEF), dark: hex(0x141518))
    static let panelBG = dynamic(light: white(0.72), dark: hex(0x1F2024))
    static let panelOutline = dynamic(light: black(0.08), dark: hex(0x2C2E33))
    static let cardBG = dynamic(light: hex(0xFFFFFF), dark: hex(0x26282D))
    static let cardOutline = dynamic(light: black(0.06), dark: hex(0x2C2E33))
    static let floatingBG = dynamic(light: white(0.90), dark: hex(0x1F2024))

    // Fields and controls
    static let fieldBG = dynamic(light: hex(0xF2F2F5), dark: hex(0x2A2C31))
    static let segmentedTrack = dynamic(light: black(0.06), dark: hex(0x2A2C31))
    static let segmentedThumb = dynamic(light: hex(0xFFFFFF), dark: hex(0x3A3D44))

    // Text, icons, lines
    static let textPrimary = dynamic(light: hex(0x1D1D1F), dark: hex(0xECEDEF))
    static let textSecondary = dynamic(light: hex(0x6E6E73), dark: hex(0xA1A4AB))
    static let iconDefault = dynamic(light: hex(0x515154), dark: hex(0xA1A4AB))
    static let hoverFill = dynamic(light: black(0.045), dark: hex(0x2A2C31))
    static let divider = dynamic(light: black(0.08), dark: hex(0x34363C))

    // Accent and selection
    static let accent = dynamic(light: hex(0x0071E3), dark: hex(0x2563EB))
    static let selectionRow = dynamic(light: hex(0x0071E3), dark: hex(0x1E3A7A))
    static let onAccent = UIColor.white

    // Canvas (it stays light in both themes: diagrams are printed and exported light)
    static let canvasBG = dynamic(light: hex(0xFFFFFF), dark: hex(0xF6F6F4))
    static let gridDot = dynamic(light: hex(0xDCDCE2), dark: hex(0xCFD1D6))
    static let gridSpacing: CGFloat = 20
    static let guideSnap = dynamic(light: hex(0xFF3B30, 0.55), dark: hex(0xDB2777, 0.55))
    static let gridLineMinor = black(0.05), gridLineMajor = black(0.09)

    enum Radius {
        static let window: CGFloat = 14, card: CGFloat = 12, dock: CGFloat = 18, tool: CGFloat = 12, field: CGFloat = 8
    }
}

extension UIColor {
    /// True for pale colors (text that would vanish on white).
    var isLight: Bool { RGBA(self).luminance > 0.7 }
}

enum NSSound {
    static func beep() { UINotificationFeedbackGenerator().notificationOccurred(.warning) }
}
