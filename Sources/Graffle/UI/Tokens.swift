import AppKit

/// The one place the interface's colors, radii and spacing are defined. Colors are dynamic: they follow the window's
/// appearance (light or dark), which follows the System / Light / Dark preference in View → Appearance.
enum Tok {
    // MARK: Building

    private static func hex(_ v: UInt32, _ a: CGFloat = 1) -> NSColor {
        NSColor(srgbRed: CGFloat((v >> 16) & 0xff) / 255, green: CGFloat((v >> 8) & 0xff) / 255, blue: CGFloat(v & 0xff) / 255, alpha: a)
    }
    private static func white(_ a: CGFloat) -> NSColor { NSColor(white: 1, alpha: a) }
    private static func black(_ a: CGFloat) -> NSColor { NSColor(white: 0, alpha: a) }

    /// A color that is `light` in the light appearance and `dark` in the dark one.
    static func dynamic(light: NSColor, dark: NSColor) -> NSColor {
        NSColor(name: nil) { $0.bestMatch(from: [.darkAqua, .vibrantDark, .aqua, .vibrantLight]).map { $0 == .darkAqua || $0 == .vibrantDark } == true ? dark : light }
    }

    // MARK: Surfaces

    static let windowBG = dynamic(light: hex(0xECECEF), dark: hex(0x141518))
    static let panelBG = dynamic(light: white(0.72), dark: hex(0x1F2024))
    static let panelOutline = dynamic(light: black(0.08), dark: hex(0x2C2E33))
    static let cardBG = dynamic(light: hex(0xFFFFFF), dark: hex(0x26282D))
    static let cardOutline = dynamic(light: black(0.06), dark: hex(0x2C2E33))
    static let floatingBG = dynamic(light: white(0.90), dark: hex(0x1F2024))

    // MARK: Fields and controls

    static let fieldBG = dynamic(light: hex(0xF2F2F5), dark: hex(0x2A2C31))
    static let fieldHoverBG = dynamic(light: hex(0xEBEBEF), dark: hex(0x2A2C31))
    static let fieldHoverBorder = dynamic(light: .clear, dark: hex(0x3A3D44))
    static let fieldFocusBG = dynamic(light: hex(0xFFFFFF), dark: hex(0x24262B))
    static let focusRing = dynamic(light: hex(0x0071E3, 0.18), dark: hex(0x2563EB, 0.35))
    static let segmentedTrack = dynamic(light: black(0.06), dark: hex(0x2A2C31))
    static let segmentedThumb = dynamic(light: hex(0xFFFFFF), dark: hex(0x3A3D44))
    static let switchOn = dynamic(light: hex(0x34C759), dark: hex(0x2563EB))
    static let switchOff = dynamic(light: hex(0xD1D1D6), dark: hex(0x3A3D44))

    // MARK: Text, icons, lines

    static let textPrimary = dynamic(light: hex(0x1D1D1F), dark: hex(0xECEDEF))
    static let textSecondary = dynamic(light: hex(0x6E6E73), dark: hex(0xA1A4AB))
    static let iconDefault = dynamic(light: hex(0x515154), dark: hex(0xA1A4AB))
    static let hoverFill = dynamic(light: black(0.045), dark: hex(0x2A2C31))
    static let divider = dynamic(light: black(0.08), dark: hex(0x34363C))

    // MARK: Accent and selection

    static let accent = dynamic(light: hex(0x0071E3), dark: hex(0x2563EB))
    static let selectionRow = dynamic(light: hex(0x0071E3), dark: hex(0x1E3A7A))
    static let onAccent = NSColor.white

    // MARK: Canvas (it stays light in both themes: diagrams are printed and exported light)

    static let canvasBG = dynamic(light: hex(0xFFFFFF), dark: hex(0xF6F6F4))
    static let gridDot = dynamic(light: hex(0xDCDCE2), dark: hex(0xCFD1D6))
    static let gridSpacing: CGFloat = 20
    static let guideSnap = dynamic(light: hex(0xFF3B30, 0.55), dark: hex(0xDB2777, 0.55))
    /// The ink for the canvas's minor and major grid lines (used when a drawing is not on dots).
    static let gridLineMinor = black(0.05), gridLineMajor = black(0.09)
    /// The Navigator's map: its page, its shapes' stand-ins and the viewport box.
    static let minimapBackdrop = dynamic(light: black(0.05), dark: white(0.06))
    static let minimapViewport = dynamic(light: hex(0xE8383D), dark: hex(0xFF5A5F))

    // MARK: Shape of things

    enum Radius {
        static let window: CGFloat = 14, card: CGFloat = 12, dock: CGFloat = 18, tool: CGFloat = 12, field: CGFloat = 8
        static let segmented: CGFloat = 9, segmentedThumb: CGFloat = 7
    }
    enum Space {
        static let base: CGFloat = 4, cardPadding: CGFloat = 12, gutter: CGFloat = 10, cardGap: CGFloat = 10
    }
    enum Font {
        static func body() -> NSFont { .systemFont(ofSize: 13) }
        static func label() -> NSFont { .systemFont(ofSize: 11.5, weight: .medium) }
        static func section() -> NSFont { .systemFont(ofSize: 12.5, weight: .semibold) }
        static func title() -> NSFont { .systemFont(ofSize: 14, weight: .semibold) }
        /// Numbers line up in columns.
        static func number() -> NSFont { .monospacedDigitSystemFont(ofSize: 12.5, weight: .medium) }
    }

    // MARK: Layer styling helpers (colors on layers must be resolved for the current appearance)

    /// Sets `layer.backgroundColor` etc. from dynamic colors, resolved against `view`'s appearance.
    static func resolve(_ color: NSColor, for view: NSView) -> CGColor {
        var out = color.cgColor
        view.effectiveAppearance.performAsCurrentDrawingAppearance { out = color.cgColor }
        return out
    }

    /// The floating shadow of docks, context bars, zoom and minimap.
    static func applyFloatingShadow(to layer: CALayer, dark: Bool) {
        layer.shadowColor = (dark ? hex(0x141518) : NSColor.black).cgColor
        layer.shadowOpacity = dark ? 0.22 : 0.14
        layer.shadowRadius = dark ? 10 : 16
        layer.shadowOffset = CGSize(width: 0, height: -6)
    }
}

/// A view with a rounded, filled, outlined background whose dynamic colors follow the appearance.
class SurfaceView: NSView {
    var fill: NSColor = Tok.cardBG { didSet { needsDisplay = true; updateSurface() } }
    var outline: NSColor? = Tok.cardOutline { didSet { updateSurface() } }
    var outlineWidth: CGFloat = 0.5 { didSet { updateSurface() } }
    var radius: CGFloat = Tok.Radius.card { didSet { layer?.cornerRadius = radius } }

    override init(frame frameRect: NSRect) { super.init(frame: frameRect); setup() }
    required init?(coder: NSCoder) { super.init(coder: coder); setup() }

    private func setup() {
        wantsLayer = true
        layer?.cornerCurve = .continuous
        layer?.cornerRadius = radius
        updateSurface()
    }

    func updateSurface() {
        layer?.backgroundColor = Tok.resolve(fill, for: self)
        layer?.borderColor = outline.map { Tok.resolve($0, for: self) }
        layer?.borderWidth = outline == nil ? 0 : outlineWidth
    }

    override func viewDidChangeEffectiveAppearance() { super.viewDidChangeEffectiveAppearance(); updateSurface() }
    override func updateLayer() { updateSurface() }
}

// MARK: - The System / Light / Dark preference

enum UIAppearance: String, CaseIterable {
    case system, light, dark

    static let key = "ui.appearance"
    var title: String { rawValue.capitalized }

    static var current: UIAppearance {
        get { UserDefaults.standard.string(forKey: key).flatMap(UIAppearance.init(rawValue:)) ?? .system }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: key); newValue.apply() }
    }

    /// Makes the whole app follow this choice (System follows macOS live).
    func apply() {
        switch self {
        case .system: NSApp.appearance = nil
        case .light: NSApp.appearance = NSAppearance(named: .aqua)
        case .dark: NSApp.appearance = NSAppearance(named: .darkAqua)
        }
        NotificationCenter.default.post(name: .uiAppearanceChanged, object: nil)
    }
}

extension Notification.Name {
    static let uiAppearanceChanged = Notification.Name("GraffleUIAppearanceChanged")
}
