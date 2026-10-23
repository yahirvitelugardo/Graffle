import SwiftUI

/// The floating column of drawing tools on the left.
struct ToolDock: View {
    @ObservedObject var model: EditorModel

    private struct Item: Identifiable {
        let tool: Tool
        let symbol: String
        let title: String
        var id: String { title }
    }

    private let items: [Item] = [
        Item(tool: .select, symbol: "cursorarrow", title: "Select"),
        Item(tool: .shape(.rectangle), symbol: "rectangle", title: "Rectangle"),
        Item(tool: .shape(.rounded), symbol: "app", title: "Rounded Rectangle"),
        Item(tool: .shape(.ellipse), symbol: "circle", title: "Ellipse"),
        Item(tool: .shape(.diamond), symbol: "diamond", title: "Diamond"),
        Item(tool: .shape(.triangle), symbol: "triangle", title: "Triangle"),
        Item(tool: .shape(.text), symbol: "textformat", title: "Text"),
        Item(tool: .connector, symbol: "point.topleft.down.to.point.bottomright.curvepath", title: "Connector"),
        Item(tool: .pen, symbol: "pencil.tip", title: "Pen"),
        Item(tool: .line, symbol: "line.diagonal", title: "Line"),
        Item(tool: .wall, symbol: "rectangle.split.2x1", title: "Wall"),
        Item(tool: .pan, symbol: "hand.raised", title: "Hand"),
    ]

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 4) {
                ForEach(items) { item in
                    let active = model.tool == item.tool
                    Button { model.tool = item.tool } label: {
                        Image(systemName: item.symbol)
                            .font(.system(size: 18, weight: .regular))
                            .frame(width: 44, height: 44)
                            .foregroundStyle(active ? Color.white : Color(Tok.iconDefault))
                            .background(active ? Color(Tok.accent) : Color.clear, in: RoundedRectangle(cornerRadius: Tok.Radius.tool, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(item.title)
                    .help(item.title)
                }
            }
            .padding(6)
        }
        .frame(width: 56)
        .frame(maxHeight: CGFloat(items.count) * 48 + 12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: Tok.Radius.dock, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Tok.Radius.dock, style: .continuous).stroke(Color(Tok.panelOutline), lineWidth: 0.5))
        .shadow(color: .black.opacity(0.12), radius: 12, y: 4)
    }
}
