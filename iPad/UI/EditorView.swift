import SwiftUI

enum InspectorTab: String, CaseIterable, Identifiable {
    case format, arrange, layers, library
    var id: String { rawValue }
    var title: String {
        switch self {
        case .format: return "Format"
        case .arrange: return "Arrange"
        case .layers: return "Layers"
        case .library: return "Library"
        }
    }
    var symbol: String {
        switch self {
        case .format: return "paintbrush"
        case .arrange: return "square.2.layers.3d"
        case .layers: return "square.3.layers.3d"
        case .library: return "books.vertical"
        }
    }
}

struct EditorView: View {
    @Binding var document: GrafDocument
    let fileName: String

    @StateObject private var model = EditorModel()
    @State private var showInspector = true
    @State private var tab: InspectorTab = .format
    @State private var showTemplates = false
    @State private var showThemes = false
    @AppStorage("canvas.showGrid") private var showGrid = true
    @AppStorage("canvas.snapToGrid") private var snapToGrid = true

    var body: some View {
        ZStack {
            CanvasRepresentable(canvas: model.canvas)
                .ignoresSafeArea(edges: .bottom)

            HStack {
                ToolDock(model: model)
                    .padding(.leading, 12)
                Spacer()
            }

            VStack {
                Spacer()
                ContextBar(model: model)
                    .padding(.bottom, 14)
            }

            VStack {
                Spacer()
                HStack {
                    Spacer()
                    ZoomControls(model: model)
                        .padding(14)
                }
            }
        }
        .inspector(isPresented: $showInspector) {
            InspectorHost(model: model, tab: $tab)
                .inspectorColumnWidth(min: 300, ideal: 340, max: 420)
        }
        .toolbar { EditorToolbar(model: model, showInspector: $showInspector, tab: $tab, showTemplates: $showTemplates, showThemes: $showThemes,
                                 showGrid: $showGrid, snapToGrid: $snapToGrid) }
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showTemplates) { TemplatesSheet(model: model) }
        .sheet(isPresented: $showThemes) { ThemesSheet(model: model) }
        .onAppear {
            model.sink = { drawing in
                if document.drawing != drawing { document.drawing = drawing }
            }
            model.canvas.showGrid = showGrid
            model.canvas.snapToGrid = snapToGrid
            model.load(document.drawing)
            if document.drawing.shapes.isEmpty && document.drawing.connectors.isEmpty { showTemplates = true }
        }
        .onChange(of: showGrid) { _, v in model.canvas.showGrid = v }
        .onChange(of: snapToGrid) { _, v in model.canvas.snapToGrid = v }
    }
}

/// Zoom in/out/fit, bottom right.
struct ZoomControls: View {
    @ObservedObject var model: EditorModel

    var body: some View {
        HStack(spacing: 2) {
            Button { model.canvas.zoomStep(out: true) } label: { Image(systemName: "minus").frame(width: 36, height: 36) }
            Menu {
                Button("Zoom to Fit") { model.canvas.zoomToFitDiagram() }
                Button("Zoom to Selection") { model.canvas.zoomToFitSelection() }
                Divider()
                ForEach([25, 50, 100, 150, 200, 400], id: \.self) { pct in
                    Button("\(pct)%") { model.canvas.setMagnification(CGFloat(pct) / 100) }
                }
            } label: {
                Text("\(model.zoomPercent)%").font(.system(size: 13, weight: .medium).monospacedDigit()).frame(minWidth: 52, minHeight: 36)
            }
            Button { model.canvas.zoomStep(out: false) } label: { Image(systemName: "plus").frame(width: 36, height: 36) }
        }
        .foregroundStyle(Color(Tok.iconDefault))
        .background(.regularMaterial, in: Capsule())
        .overlay(Capsule().stroke(Color(Tok.panelOutline), lineWidth: 0.5))
        .shadow(color: .black.opacity(0.12), radius: 10, y: 3)
    }
}

struct EditorToolbar: ToolbarContent {
    @ObservedObject var model: EditorModel
    @Binding var showInspector: Bool
    @Binding var tab: InspectorTab
    @Binding var showTemplates: Bool
    @Binding var showThemes: Bool
    @Binding var showGrid: Bool
    @Binding var snapToGrid: Bool

    var body: some ToolbarContent {
        ToolbarItemGroup(placement: .topBarLeading) {
            Button { model.canvas.undoLast() } label: { Image(systemName: "arrow.uturn.backward") }
                .disabled(!model.canvas.canUndo)
            Button { model.canvas.redoLast() } label: { Image(systemName: "arrow.uturn.forward") }
                .disabled(!model.canvas.canRedo)
        }
        ToolbarItemGroup(placement: .topBarTrailing) {
            ExportMenu(model: model)
            ImportMenu(model: model)
            Menu {
                Toggle("Show Grid", isOn: $showGrid)
                Toggle("Snap to Grid", isOn: $snapToGrid)
                Toggle("Smart Guides", isOn: Binding(get: { model.canvas.smartGuides }, set: { model.canvas.smartGuides = $0; model.objectWillChange.send() }))
                Toggle("Object Snap", isOn: Binding(get: { model.canvas.objectSnap }, set: { model.canvas.objectSnap = $0; model.objectWillChange.send() }))
                Toggle("Right-Angle Lines", isOn: Binding(get: { model.canvas.orthoMode }, set: { model.canvas.orthoMode = $0; model.objectWillChange.send() }))
                Divider()
                Toggle("Fingers Scroll, Pencil Draws", isOn: Binding(get: { model.fingerPans }, set: { model.fingerPans = $0 }))
                Divider()
                Button("Templates…", systemImage: "square.grid.2x2") { showTemplates = true }
                Button("Themes…", systemImage: "paintpalette") { showThemes = true }
            } label: { Image(systemName: "slider.horizontal.3") }
            Button { showInspector.toggle() } label: { Image(systemName: "sidebar.trailing") }
        }
    }
}
