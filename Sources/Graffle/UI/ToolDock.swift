import AppKit

/// The floating tool dock at the bottom of the canvas.
final class ToolDock: NSView {
    struct Item { let tool: Tool; let symbol: String; let name: String; let key: String }
    static let groups: [[Item]] = [
        [Item(tool: .select, symbol: "cursorarrow", name: "Select", key: "V"),
         Item(tool: .pan, symbol: "hand.raised", name: "Pan", key: "H"),
         Item(tool: .zoom, symbol: "plus.magnifyingglass", name: "Zoom", key: "Z")],
        [Item(tool: .shape(.rectangle), symbol: "rectangle", name: "Rectangle", key: "R"),
         Item(tool: .shape(.rounded), symbol: "app", name: "Rounded rectangle", key: "U"),
         Item(tool: .shape(.ellipse), symbol: "circle", name: "Ellipse", key: "O"),
         Item(tool: .shape(.diamond), symbol: "diamond", name: "Diamond", key: "D"),
         Item(tool: .shape(.triangle), symbol: "triangle", name: "Triangle", key: "Y")],
        [Item(tool: .shape(.text), symbol: "textformat", name: "Text", key: "T"),
         Item(tool: .connector, symbol: "arrow.up.right", name: "Connector", key: "C"),
         Item(tool: .pen, symbol: "pencil.tip", name: "Pen", key: "P")],
        [Item(tool: .line, symbol: "line.diagonal", name: "Line (angle and point snapping, live length)", key: "L"),
         Item(tool: .wall, symbol: "building.2", name: "Wall (as thick as the drawing scale says)", key: "W")],
    ]

    private(set) var buttons: [(Tool, IconButton)] = []
    var onPick: ((Tool) -> Void)?
    private let surface = FloatingSurface(radius: Tok.Radius.dock)

    init() {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        setAccessibilityRole(.toolbar)
        setAccessibilityLabel("Tools")
        addSubview(surface)
        let row = NSStackView()
        row.orientation = .horizontal
        row.spacing = 2          // thirteen 40 pt tools must still fit beside the minimap in a default window
        row.edgeInsets = NSEdgeInsets(top: 6, left: 6, bottom: 6, right: 6)
        row.translatesAutoresizingMaskIntoConstraints = false
        for (gi, group) in Self.groups.enumerated() {
            if gi > 0 { row.addArrangedSubview(divider()) }
            for item in group {
                let b = IconButton(symbol: item.symbol, label: item.name, tip: "\(item.name) (\(item.key))", size: 40, pointSize: 16)
                b.cornerRadius = Tok.Radius.tool
                b.target = self; b.action = #selector(picked(_:))
                b.tag = buttons.count
                row.addArrangedSubview(b)
                buttons.append((item.tool, b))
            }
        }
        surface.addSubview(row)
        NSLayoutConstraint.activate([
            surface.leadingAnchor.constraint(equalTo: leadingAnchor), surface.trailingAnchor.constraint(equalTo: trailingAnchor),
            surface.topAnchor.constraint(equalTo: topAnchor), surface.bottomAnchor.constraint(equalTo: bottomAnchor),
            row.leadingAnchor.constraint(equalTo: surface.leadingAnchor), row.trailingAnchor.constraint(equalTo: surface.trailingAnchor),
            row.topAnchor.constraint(equalTo: surface.topAnchor), row.bottomAnchor.constraint(equalTo: surface.bottomAnchor),
        ])
    }
    required init?(coder: NSCoder) { fatalError("not used") }

    private func divider() -> NSView {
        let v = SurfaceView(frame: .zero)
        v.fill = Tok.divider; v.outline = nil; v.radius = 0
        v.translatesAutoresizingMaskIntoConstraints = false
        v.widthAnchor.constraint(equalToConstant: 1).isActive = true
        v.heightAnchor.constraint(equalToConstant: 24).isActive = true
        return v
    }

    @objc private func picked(_ s: IconButton) { onPick?(buttons[s.tag].0) }

    /// Marks the button of the current tool as active.
    func sync(_ tool: Tool) { for (t, b) in buttons { b.isActive = t == tool; b.setAccessibilityValue(t == tool ? "selected" : nil) } }
}
