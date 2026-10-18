import AppKit

// MARK: Color helpers

extension RGBA {
    /// "#RGB", "#RRGGBB" or "#RRGGBBAA" (the "#" is optional).
    init?(hex: String) {
        var s = hex.trimmingCharacters(in: .whitespaces)
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.allSatisfy(\.isHexDigit) else { return nil }
        if s.count == 3 { s = s.map { "\($0)\($0)" }.joined() }
        guard s.count == 6 || s.count == 8, let v = UInt64(s, radix: 16) else { return nil }
        let hasAlpha = s.count == 8
        let r = Double((v >> (hasAlpha ? 24 : 16)) & 0xff) / 255
        let g = Double((v >> (hasAlpha ? 16 : 8)) & 0xff) / 255
        let b = Double((v >> (hasAlpha ? 8 : 0)) & 0xff) / 255
        let a = hasAlpha ? Double(v & 0xff) / 255 : 1
        self.init(r, g, b, a)
    }

    var hex: String {
        func byte(_ c: Double) -> Int { Int((min(1, max(0, c)) * 255).rounded()) }
        let base = String(format: "#%02X%02X%02X", byte(r), byte(g), byte(b))
        return a < 0.999 ? base + String(format: "%02X", byte(a)) : base
    }

    func mixed(with other: RGBA, _ t: Double) -> RGBA {
        RGBA(r + (other.r - r) * t, g + (other.g - g) * t, b + (other.b - b) * t, a + (other.a - a) * t)
    }
    func lighter(_ t: Double) -> RGBA { mixed(with: RGBA(1, 1, 1, a), t) }
    func darker(_ t: Double) -> RGBA { mixed(with: RGBA(0, 0, 0, a), t) }
    func with(alpha: Double) -> RGBA { RGBA(r, g, b, alpha) }
    /// More vivid: pushes the channels away from their gray average.
    func vivid(_ t: Double) -> RGBA {
        let m = (r + g + b) / 3
        func f(_ c: Double) -> Double { min(1, max(0, m + (c - m) * (1 + t))) }
        return RGBA(f(r), f(g), f(b), a)
    }
    var saturation: Double { max(r, g, b) - min(r, g, b) }
}

// MARK: The theme file format
//
// A theme is a JSON document (extension `.graftheme`). Everything but `id` and `name` is optional; what a theme leaves
// out falls back to the plain Clean look. (Older files may still have a `page` section: it is ignored.) Colors are "#RRGGBB" or "#RRGGBBAA". See the README for a commented example.

struct ThemeDefinition: Codable, Equatable, Identifiable {
    static let currentFormat = 1

    var format: Int?
    /// A short unique name made of lowercase letters, digits, "-", "_" and ".".
    var id: String
    var name: String
    var author: String?
    var summary: String?
    /// The color of the canvas grid, "#RRGGBBAA" (the alpha sets how faint it is). Set it when the default faint-black grid
    /// wouldn't contrast with the theme's shapes; leave it out otherwise. The canvas itself is never recolored.
    var gridColor: String?
    /// A color shapes are pulled toward (`accentMix` 0 = keep each shape's own color, 1 = every shape gets the accent).
    var accent: String?
    var accentMix: Double?
    var shape: ShapeSpec?
    var connector: ConnectorSpec?

    struct ShapeSpec: Codable, Equatable {
        var fill: FillSpec?
        var stroke: StrokeSpec?
        var shadow: ShadowSpec?
        /// "neumorphic", "crystal", "glass", "hatch" or "clay"
        var effect: String?
        var cornerRadius: Double?
        var opacity: Double?
        var text: TextSpec?
    }
    struct FillSpec: Codable, Equatable {
        /// "solid" (default), "gradient" or "none"
        var mode: String?
        /// A color the shape's own color is mixed into; `tint` says how much of the shape's color shows (0...1).
        var surface: String?
        var tint: Double?
        var lighten: Double?
        var darken: Double?
        var alpha: Double?
        var angle: Double?
    }
    struct StrokeSpec: Codable, Equatable {
        var visible: Bool?
        /// A fixed color; without it the line is the shape's color made lighter or darker.
        var color: String?
        var lighten: Double?
        var darken: Double?
        var alpha: Double?
        var width: Double?
        /// 0...1, how hand-drawn the line is.
        var rough: Double?
        /// "butt", "round" or "square"
        var cap: String?
        /// "solid", "dashed", "longDash", "dotted" or "dashDot"
        var dash: String?
    }
    struct ShadowSpec: Codable, Equatable {
        var color: String?
        var blur: Double?
        var offset: Double?
        var angle: Double?
    }
    struct TextSpec: Codable, Equatable {
        var color: String?
        /// Font families in order of preference; the first one installed is used.
        var fonts: [String]?
        var bold: Bool?
    }
    struct ConnectorSpec: Codable, Equatable {
        var color: String?
        var width: Double?
        var rough: Double?
        var cap: String?
        var dash: String?
        /// A halo around the line.
        var glow: String?
        var textColor: String?
    }

    // MARK: Validation

    enum Problem: LocalizedError {
        case invalid([String])
        case unreadable
        case newerFormat(Int)
        case reservedID(String)

        var errorDescription: String? {
            switch self {
            case .invalid(let issues): return "The theme file has problems:\n• " + issues.joined(separator: "\n• ")
            case .unreadable: return "This isn't a Graffle theme file, or it is damaged."
            case .newerFormat(let n): return "This theme uses format \(n), which this version of Graffle doesn't understand. Update Graffle."
            case .reservedID(let id): return "The id “\(id)” belongs to a theme that comes with Graffle. Give your theme another id."
            }
        }
    }

    static let idPattern = "^[a-z0-9][a-z0-9._-]{0,63}$"
    static let effects: Set<String> = ["neumorphic", "crystal", "glass", "hatch", "clay"]
    static let caps: Set<String> = ["butt", "round", "square"]
    static let dashes = Set(DashKind.allCases.map(\.rawValue))
    static let fillModes: Set<String> = ["solid", "gradient", "none"]

    /// Everything wrong with the theme, in plain words (empty = fine).
    func problems() -> [String] {
        var out: [String] = []
        if id.range(of: ThemeDefinition.idPattern, options: .regularExpression) == nil {
            out.append("id must be lowercase letters, digits, “-”, “_” or “.” (found “\(id)”)")
        }
        if name.trimmingCharacters(in: .whitespaces).isEmpty { out.append("name is empty") }
        func color(_ label: String, _ s: String?) { if let s, RGBA(hex: s) == nil { out.append("\(label): “\(s)” is not a color like #RRGGBB") } }
        func choice(_ label: String, _ s: String?, _ allowed: Set<String>) {
            if let s, !allowed.contains(s) { out.append("\(label): “\(s)” is not one of \(allowed.sorted().joined(separator: ", "))") }
        }
        color("accent", accent)
        color("gridColor", gridColor)
        if let s = shape {
            choice("shape.effect", s.effect, ThemeDefinition.effects)
            choice("shape.fill.mode", s.fill?.mode, ThemeDefinition.fillModes)
            color("shape.fill.surface", s.fill?.surface)
            color("shape.stroke.color", s.stroke?.color)
            color("shape.shadow.color", s.shadow?.color)
            color("shape.text.color", s.text?.color)
            choice("shape.stroke.cap", s.stroke?.cap, ThemeDefinition.caps)
            choice("shape.stroke.dash", s.stroke?.dash, ThemeDefinition.dashes)
        }
        if let c = connector {
            color("connector.color", c.color); color("connector.glow", c.glow); color("connector.textColor", c.textColor)
            choice("connector.cap", c.cap, ThemeDefinition.caps)
            choice("connector.dash", c.dash, ThemeDefinition.dashes)
        }
        return out
    }

    /// Reads and checks a theme file's contents.
    static func decode(_ data: Data) throws -> ThemeDefinition {
        guard let def = try? JSONDecoder().decode(ThemeDefinition.self, from: data) else { throw Problem.unreadable }
        if let f = def.format, f > currentFormat { throw Problem.newerFormat(f) }
        let issues = def.problems()
        if !issues.isEmpty { throw Problem.invalid(issues) }
        return def
    }

    func encoded() -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return (try? encoder.encode(self)) ?? Data()
    }

    var isClean: Bool { id == "clean" }
}
