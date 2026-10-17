import AppKit

/// A named look the user can apply to any object, in any document.
struct SavedStyle: Codable, Identifiable, Equatable {
    var id = UUID()
    var name: String
    var style: Style
    /// Saved from a connector: a line-only look, so applying it to a shape must not wipe the shape's fill.
    var fromConnector = false
}

extension Style {
    /// This style after receiving `source`'s look. Fill and corner radius only travel between shapes:
    /// a connector has no fill, and a connector's empty fill must not erase a shape's.
    func receiving(_ source: Style, sourceIsConnector: Bool, targetIsConnector: Bool) -> Style {
        var s = source
        if targetIsConnector || sourceIsConnector {
            s.fill = fill
            s.cornerRadius = cornerRadius
        }
        return s
    }
}

/// The user's palette of saved styles. It lives in the app's preferences, so it is shared by every document.
final class StyleLibrary {
    static let shared = StyleLibrary()
    static let defaultsKey = "graffleSavedStyles"

    private let defaults: UserDefaults
    private(set) var styles: [SavedStyle] = []

    /// Called after every change, so a palette on screen can redraw.
    var onChange: (() -> Void)?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: StyleLibrary.defaultsKey) {
            // Even an empty list is respected: the starters are only seeded the very first time.
            styles = (try? JSONDecoder().decode([SavedStyle].self, from: data)) ?? []
        } else {
            styles = StyleLibrary.starters
            persist()
        }
    }

    @discardableResult
    func add(name: String, style: Style, fromConnector: Bool = false) -> SavedStyle {
        let saved = SavedStyle(name: name, style: style, fromConnector: fromConnector)
        styles.append(saved)
        persist()
        onChange?()
        return saved
    }

    func rename(_ id: UUID, to name: String) {
        guard let i = styles.firstIndex(where: { $0.id == id }) else { return }
        styles[i].name = name
        persist()
        onChange?()
    }

    func update(_ id: UUID, style: Style, fromConnector: Bool) {
        guard let i = styles.firstIndex(where: { $0.id == id }) else { return }
        styles[i].style = style
        styles[i].fromConnector = fromConnector
        persist()
        onChange?()
    }

    func delete(_ id: UUID) {
        styles.removeAll { $0.id == id }
        persist()
        onChange?()
    }

    func style(_ id: UUID) -> SavedStyle? { styles.first { $0.id == id } }

    private func persist() {
        if let data = try? JSONEncoder().encode(styles) { defaults.set(data, forKey: StyleLibrary.defaultsKey) }
    }

    // MARK: Starters

    /// A few looks to start from, so the palette is useful before the user has saved anything.
    static var starters: [SavedStyle] {
        func make(_ name: String, _ build: (inout Style) -> Void) -> SavedStyle {
            var s = Style()
            build(&s)
            return SavedStyle(name: name, style: s)
        }
        return [
            make("Blueprint") { s in
                s.fill.color = RGBA(0.86, 0.91, 1.0); s.stroke.color = RGBA(0.17, 0.30, 0.55); s.stroke.width = 1.5
            },
            make("Solid Blue") { s in
                s.fill.color = RGBA(0.23, 0.44, 0.88); s.stroke.visible = false
            },
            make("Warm Gradient") { s in
                s.fill.kind = .linear; s.fill.angle = 90
                s.fill.stops = [GradientStop(color: RGBA(1.0, 0.70, 0.42), position: 0), GradientStop(color: RGBA(0.95, 0.36, 0.47), position: 1)]
                s.stroke.visible = false; s.cornerRadius = 12
                s.shadow = Shadow(enabled: true, color: RGBA(0, 0, 0, 0.3), blur: 8, offset: 5, angle: 90)
            },
            make("Soft Card") { s in
                s.fill.color = RGBA(1, 1, 1); s.stroke.color = RGBA(0.82, 0.84, 0.88); s.stroke.width = 1; s.cornerRadius = 10
                s.shadow = Shadow(enabled: true, color: RGBA(0, 0, 0, 0.22), blur: 12, offset: 4, angle: 90)
            },
            make("Outline") { s in
                s.fill.kind = .none; s.stroke.color = RGBA(0.2, 0.2, 0.22); s.stroke.width = 2
            },
            make("Dashed Outline") { s in
                s.fill.kind = .none; s.stroke.color = RGBA(0.4, 0.4, 0.45); s.stroke.width = 1.5; s.stroke.dash = .dashed
            },
            make("Sticky Note") { s in
                s.fill.color = RGBA(1.0, 0.95, 0.69); s.stroke.color = RGBA(0.88, 0.71, 0.0); s.stroke.width = 1; s.cornerRadius = 4
            },
        ]
    }
}
