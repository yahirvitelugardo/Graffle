import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// Draws small pictures of a theme: a few sample shapes and connectors with the theme applied.
@MainActor
enum ThemeSwatch {
    private static var cache: [Data: UIImage] = [:]
    private static let scratch = CanvasView()

    static func sampleDrawing() -> Drawing {
        let layer = Layer(name: "Layer 1")
        var d = Drawing()
        d.layers = [layer]
        func shape(_ kind: ShapeKind, _ x: CGFloat, _ y: CGFloat, _ text: String) -> Shape {
            Shape(layer: layer.id, kind: kind, frame: CGRect(x: x, y: y, width: 120, height: 64), text: text)
        }
        let a = shape(.rounded, 0, 0, "Client"), b = shape(.rectangle, 200, 0, "Server")
        let c = shape(.ellipse, 0, 120, "Cache"), e = shape(.diamond, 200, 120, "Ok?")
        d.shapes = [a, b, c, e]
        d.connectors = [Connector(layer: layer.id, from: a.id, to: b.id), Connector(layer: layer.id, from: a.id, to: c.id),
                        Connector(layer: layer.id, from: b.id, to: e.id)]
        return d
    }

    static func image(for theme: ThemeDefinition) -> UIImage? {
        let key = theme.encoded()
        if let hit = cache[key] { return hit }
        var d = sampleDrawing()
        theme.apply(to: &d)
        scratch.load(d)
        scratch.showGrid = false
        guard let data = scratch.pngData(scale: 1.5), let img = UIImage(data: data) else { return nil }
        cache[key] = img
        return img
    }
}

/// Picks a theme for the drawing; `.graftheme` files can be imported.
struct ThemesSheet: View {
    @ObservedObject var model: EditorModel
    @Environment(\.dismiss) private var dismiss

    @State private var themes: [ThemeDefinition] = ThemeLibrary.all
    @State private var importing = false
    @State private var errorText: String?

    private var currentID: String { model.canvas.drawing.theme?.id ?? "clean" }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 200, maximum: 280), spacing: 14)], spacing: 14) {
                    ForEach(themes) { theme in card(theme) }
                }
                .padding(16)
            }
            .background(Color(Tok.windowBG))
            .navigationTitle("Themes")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Done") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { importing = true } label: { Label("Import Theme…", systemImage: "square.and.arrow.down") }
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .themesChanged)) { _ in themes = ThemeLibrary.all }
        .fileImporter(isPresented: $importing, allowedContentTypes: importTypes) { result in
            switch result {
            case .success(let url): importTheme(url)
            case .failure(let e): errorText = e.localizedDescription
            }
        }
        .alert("Couldn’t Import Theme", isPresented: Binding(get: { errorText != nil }, set: { if !$0 { errorText = nil } })) {
            Button("OK", role: .cancel) {}
        } message: { Text(errorText ?? "") }
    }

    private var importTypes: [UTType] {
        [UTType(filenameExtension: ThemeLibrary.fileExtension), .json, .plainText].compactMap { $0 }
    }

    private func importTheme(_ url: URL) {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        do {
            try ThemeLibrary.importTheme(from: url)
            themes = ThemeLibrary.all
        } catch {
            errorText = error.localizedDescription
        }
    }

    private func card(_ theme: ThemeDefinition) -> some View {
        let selected = theme.id == currentID
        return Button {
            model.canvas.applyTheme(theme)
            dismiss()
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                ZStack {
                    Color.white
                    if let img = ThemeSwatch.image(for: theme) {
                        Image(uiImage: img).resizable().scaledToFit().padding(8)
                    }
                }
                .frame(height: 130)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color(Tok.cardOutline), lineWidth: 1))
                HStack {
                    Text(theme.name).font(.system(size: 15, weight: .semibold)).foregroundStyle(Color(Tok.textPrimary))
                    Spacer()
                    if selected { Image(systemName: "checkmark.circle.fill").foregroundStyle(Color(Tok.accent)) }
                }
                if let s = theme.summary, !s.isEmpty {
                    Text(s).font(.system(size: 12)).foregroundStyle(Color(Tok.textSecondary)).lineLimit(2).multilineTextAlignment(.leading)
                }
            }
            .padding(10)
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .topLeading)
            .background(Color(Tok.cardBG), in: RoundedRectangle(cornerRadius: Tok.Radius.card))
            .overlay(RoundedRectangle(cornerRadius: Tok.Radius.card).stroke(selected ? Color(Tok.accent) : Color(Tok.cardOutline), lineWidth: selected ? 2 : 1))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(selected ? "\(theme.name), current theme" : theme.name)
    }
}
