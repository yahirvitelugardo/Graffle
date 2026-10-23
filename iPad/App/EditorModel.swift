import SwiftUI
import Combine

/// Bridges the UIKit canvas to SwiftUI: panels observe `revision` and read the canvas.
@MainActor
final class EditorModel: ObservableObject {
    let canvas = CanvasView()

    /// Bumps whenever the drawing, the selection, the tool or the layers change, so every panel refreshes.
    @Published private(set) var revision = 0
    @Published private(set) var zoomPercent = 100
    @Published private(set) var isEditingText = false

    /// Called with the drawing after each change (the document saves from it).
    var sink: ((Drawing) -> Void)?
    private var pendingFit = true
    private var loaded = false

    init() {
        canvas.installInputs()
        installLibraryDrop()
        canvas.onChange = { [weak self] in self?.changed(drawing: true) }
        canvas.onSelectionChange = { [weak self] in self?.changed(drawing: false) }
        canvas.onToolChange = { [weak self] in self?.changed(drawing: false) }
        canvas.onActiveLayerChange = { [weak self] in self?.changed(drawing: false) }
        canvas.onEditingChange = { [weak self] in
            guard let self else { return }
            self.isEditingText = self.canvas.isEditingText
            self.changed(drawing: false)
        }
        canvas.onViewChange = { [weak self] in self?.viewChanged() }
        canvas.fingerMode = UserDefaults.standard.bool(forKey: "canvas.fingerPans") ? .pan : .draw
    }

    /// Opens `drawing` in the canvas (once per editor).
    func load(_ drawing: Drawing) {
        guard !loaded else { return }
        loaded = true
        canvas.load(drawing)
        pendingFit = true
        viewChanged()
    }

    private func changed(drawing: Bool) {
        revision &+= 1
        if drawing { sink?(canvas.drawing) }
    }

    private func viewChanged() {
        if pendingFit, canvas.bounds.width > 0 {
            pendingFit = false
            fitOnOpen()
        }
        let pct = Int((canvas.zoom * 100).rounded())
        if pct != zoomPercent { zoomPercent = pct }
    }

    /// A drawing opens fitted (never magnified past 100%); an empty one opens at the middle of the page.
    private func fitOnOpen() {
        guard let b = canvas.drawing.contentBounds else {
            canvas.zoom = 1
            canvas.scrollCenter(to: CGPoint(x: 600, y: 420))
            return
        }
        canvas.zoom(toFit: b.insetBy(dx: -60, dy: -60))
        if canvas.zoom > 1 {
            canvas.zoom = 1
            canvas.scrollCenter(to: CGPoint(x: b.midX, y: b.midY))
        }
    }

    var fingerPans: Bool {
        get { canvas.fingerMode == .pan }
        set {
            canvas.fingerMode = newValue ? .pan : .draw
            UserDefaults.standard.set(newValue, forKey: "canvas.fingerPans")
            revision &+= 1
        }
    }

    // MARK: Tools

    var tool: Tool {
        get { canvas.tool }
        set { canvas.tool = newValue }
    }
    var hasSelection: Bool { !canvas.selection.isEmpty }
}
