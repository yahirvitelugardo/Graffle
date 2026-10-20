import AppKit

/// Self-test steps for the Shape Library: the catalog, putting items on the canvas, "My Shapes" and the sidebar.
extension AppDelegate {
    func librarySteps(bundled: Bool) -> [(String, () -> Bool)] {
        var steps: [(String, () -> Bool)] = []
        steps.append(("library: the catalog is large, unique, well-formed and searchable", {
            let items = ShapeCatalog.items
            guard items.count >= 90, Set(items.map(\.id)).count == items.count else { return false }
            guard Set(items.map(\.category)).isSubset(of: Set(ShapeCatalog.categoryOrder)),
                  Set(ShapeCatalog.categoryOrder).isSubset(of: Set(items.map(\.category))) else { return false }
            for item in items where item.compose == nil {
                let s = item.previewShape()
                let box = s.path().boundingBoxOfPath
                // Every outline fills its frame (within a little overshoot for curves) and has some size.
                if item.circuit == nil && (box.width < 1 || box.height < 1 || box.minX < -1 || box.minY < -1 || box.maxX > item.size.width + 1 || box.maxY > item.size.height + 1) {
                    if item.id != "callout-thought" && item.id != "cloud" && item.id != "fc-delay" && item.id != "fc-display" && !item.id.hasPrefix("u-turn") { return false }
                }
            }
            func found(_ q: String) -> [String] { items.filter { ShapeCatalog.matches($0, q) }.map(\.id) }
            return found("hexagon") == ["polygon-6"] && found("resistor") == ["circuit-resistor"] && found("start").contains("fc-terminator")
                && found("").count == items.count && found("zzzz").isEmpty && found("arrow").count >= 8 && found("flowchart process").contains("fc-process")
        }))
        steps.append(("library: every item draws a thumbnail and can be put on the canvas, undone, and put again", {
            let canvas = CanvasView(frame: NSRect(origin: .zero, size: CanvasView.canvasSize))
            let host = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 400, height: 300), styleMask: [.titled], backing: .buffered, defer: true)
            host.contentView?.addSubview(canvas)                                       // a window gives the canvas its undo manager
            defer { host.contentView = nil }
            canvas.load(Drawing())
            for (n, item) in ShapeCatalog.items.enumerated() {
                let image = LibraryThumbnail.image(item, size: CGSize(width: 64, height: 48))
                guard let tiff = image.tiffRepresentation, !tiff.isEmpty else { return false }
                let before = canvas.drawing.shapes.count
                let d = item.drawing(layer: canvas.activeLayerID, style: canvas.defaultStyle, number: 1)
                canvas.undoManager?.groupsByEvent = false
                canvas.undoManager?.beginUndoGrouping()                                   // one undo step per put, as with a real click
                canvas.placeDrawing(d, named: "Add", near: CGPoint(x: 400 + CGFloat(n % 10) * 150, y: 300 + CGFloat(n / 10) * 150), themed: true)
                canvas.undoManager?.endUndoGrouping()
                if canvas.drawing.shapes.count != before + d.shapes.count || canvas.selection.count != d.shapes.count { return false }
            }
            let all = canvas.drawing.shapes.count
            canvas.undoManager?.undo()
            let undone = canvas.drawing.shapes.count < all
            // Two puts of the same item are two different objects; brace-like lines stay unfilled; circuit symbols keep pins.
            let ids = Set(canvas.drawing.shapes.map(\.id))
            let brace = canvas.drawing.shapes.first { $0.name == "Left Brace" }
            let resistor = canvas.drawing.shapes.first { $0.name == "Resistor" }
            return undone && ids.count == canvas.drawing.shapes.count && brace?.style.fill.kind == FillKind.none && resistor?.pins?.count == 2
                && canvas.pngData()?.isEmpty == false
        }))
        steps.append(("library: items land centered where asked, on the active layer, in the theme's look", {
            let canvas = CanvasView(frame: NSRect(origin: .zero, size: CanvasView.canvasSize))
            var d = Drawing()
            ThemeLibrary.theme(id: "chalkboard")?.apply(to: &d)
            canvas.load(d)
            guard let item = ShapeCatalog.items.first(where: { $0.id == "polygon-6" }) else { return false }
            canvas.placeDrawing(item.drawing(layer: canvas.activeLayerID, style: canvas.defaultStyle), named: "Add", near: CGPoint(x: 600, y: 500), themed: true)
            guard let s = canvas.drawing.shapes.first else { return false }
            let plain = Style()
            return abs(s.frame.midX - 600) < 11 && abs(s.frame.midY - 500) < 11 && s.layer == canvas.drawing.layers[0].id
                && (d.theme == nil || s.style.fill != plain.fill || s.style.stroke != plain.stroke)
        }))
        steps.append(("library: My Shapes saves a selection, renames, deletes and keeps it between launches", {
            let file = FileManager.default.temporaryDirectory.appendingPathComponent("graffle-library-\(UUID().uuidString).json")
            defer { try? FileManager.default.removeItem(at: file) }
            let canvas = CanvasView(frame: NSRect(origin: .zero, size: CanvasView.canvasSize))
            var base = Drawing()
            let layer = base.layers[0].id
            var a = Shape(layer: layer, kind: .rectangle, frame: CGRect(x: 200, y: 200, width: 100, height: 60), text: "A")
            a.style.fill.color = RGBA(1, 0.2, 0.2)
            let b = Shape(layer: layer, kind: .ellipse, frame: CGRect(x: 400, y: 260, width: 80, height: 80), text: "B")
            base.shapes = [a, b]
            base.connectors = [Connector(layer: layer, from: a.id, to: b.id)]
            canvas.load(base)
            canvas.selection = [a.id, b.id]
            guard let sub = canvas.selectionDrawing() else { return false }
            let library = ShapeLibrary(file: file)
            guard let saved = library.add(name: "  Pair ", drawing: sub), saved.name == "Pair", library.custom.count == 1 else { return false }
            // It comes back after a restart, first in the list, with its connector and its own colors.
            let again = ShapeLibrary(file: file)
            guard again.custom.count == 1, again.custom[0].name == "Pair", again.allItems.first?.id == saved.id, again.custom[0].custom?.connectors.count == 1 else { return false }
            let target = CanvasView(frame: NSRect(origin: .zero, size: CanvasView.canvasSize))
            target.load(Drawing())
            let drawing = again.custom[0].drawing(layer: target.activeLayerID, style: target.defaultStyle)
            target.placeDrawing(drawing, named: "Add", near: CGPoint(x: 700, y: 700), themed: true)
            let placed = target.drawing
            let red = placed.shapes.contains { $0.style.fill.color == RGBA(1, 0.2, 0.2) }
            let grouped = Set(placed.shapes.compactMap(\.group)).count == 1
            let wired = placed.connectors.count == 1 && Set(placed.shapes.map(\.id)).isSuperset(of: [placed.connectors[0].from, placed.connectors[0].to])
            let center = placed.shapes.map(\.frame).reduce(nil) { acc, f in acc.map { $0.union(f) } ?? f }!
            let centered = abs(center.midX - 700) < 11 && abs(center.midY - 700) < 11
            again.rename(saved.id, to: "Duo")
            let renamed = ShapeLibrary(file: file).custom.first?.name == "Duo"
            again.remove(saved.id)
            let gone = ShapeLibrary(file: file).custom.isEmpty && ShapeLibrary(file: file).item(saved.id) == nil
            return red && grouped && wired && centered && renamed && gone && library.add(name: "x", drawing: Drawing()) == nil
        }))
        steps.append(("library: the sidebar lists My Shapes first, filters by search, and folds categories", {
            let defaults = UserDefaults.standard
            let savedKey = defaults.object(forKey: "ui.library.collapsed")
            defer { if let savedKey { defaults.set(savedKey, forKey: "ui.library.collapsed") } else { defaults.removeObject(forKey: "ui.library.collapsed") } }
            defaults.removeObject(forKey: "ui.library.collapsed")
            let file = FileManager.default.temporaryDirectory.appendingPathComponent("graffle-library-\(UUID().uuidString).json")
            defer { try? FileManager.default.removeItem(at: file) }
            let library = ShapeLibrary(file: file)
            var d = Drawing()
            d.shapes = [Shape(layer: d.layers[0].id, kind: .rectangle, frame: CGRect(x: 0, y: 0, width: 50, height: 50))]
            library.add(name: "Mine", drawing: d)
            let view = LibraryView(library: library)
            view.frame = NSRect(x: 0, y: 0, width: 252, height: 640)
            view.layoutSubtreeIfNeeded()
            let titles = view.grid.sections.map(\.title)
            let order = titles.first == ShapeLibrary.myShapes && Array(titles.dropFirst()) == ShapeCatalog.categoryOrder
            view.setQuery("hexagon")
            let filtered = view.grid.sections.map(\.title) == [ShapeCatalog.polygons] && view.grid.sections[0].items.count == 1
            view.setQuery("")
            view.grid.toggle(ShapeCatalog.basic)
            let folded = view.grid.collapsed.contains(ShapeCatalog.basic)
            let persisted = (defaults.stringArray(forKey: "ui.library.collapsed") ?? []).contains(ShapeCatalog.basic)
            view.grid.toggle(ShapeCatalog.basic)
            view.setQuery("mine")
            let mine = view.grid.sections.map(\.title) == [ShapeLibrary.myShapes]
            // Tooltips come from the grid itself (AppKit doesn't retain a tooltip's owner, which once crashed the app).
            view.setQuery("")
            let tip = view.grid.view(view.grid, stringForToolTip: 0, point: .zero, userData: UnsafeMutableRawPointer(bitPattern: 1))
            let tips = tip == view.grid.sections[0].items[0].name && view.grid.view(view.grid, stringForToolTip: 0, point: .zero, userData: nil).isEmpty
            view.setQuery("mine")
            return tips && order && filtered && folded && persisted && !view.grid.collapsed.contains(ShapeCatalog.basic) && mine
        }))
        steps.append(("library: the window opens and folds the Shape Library, remembers it, and adds dropped items", {
            let defaults = UserDefaults.standard
            let saved = defaults.object(forKey: "ui.libraryVisible")
            defer { if let saved { defaults.set(saved, forKey: "ui.libraryVisible") } else { defaults.removeObject(forKey: "ui.libraryVisible") } }
            defaults.set(false, forKey: "ui.libraryVisible")
            let wc = DocumentWindowController()
            wc.window?.setContentSize(NSSize(width: 1400, height: 800))
            wc.showWindow(nil)
            defer { wc.window?.close() }
            let start = !wc.libraryWanted && !wc.libraryShown
            wc.toggleLibrary(nil)
            let opened = wc.libraryWanted && wc.libraryShown && defaults.bool(forKey: "ui.libraryVisible")
            wc.window?.setContentSize(NSSize(width: 900, height: 800))
            wc.applyLibrary(animated: false)
            let folded = wc.libraryWanted && !wc.libraryShown                           // too narrow: it folds but is still wanted
            wc.window?.setContentSize(NSSize(width: 1400, height: 800))
            wc.applyLibrary(animated: false)
            let back = wc.libraryShown
            // A drop on the canvas is a put at that point.
            guard let item = ShapeCatalog.items.first(where: { $0.id == "star-5" }) else { return false }
            wc.canvas.onLibraryDrop?(item.id, CGPoint(x: 900, y: 700))
            let dropped = wc.canvas.drawing.shapes.count == 1 && abs(wc.canvas.drawing.shapes[0].frame.midX - 900) < 11
            wc.library.onInsert?(item)
            let clicked = wc.canvas.drawing.shapes.count == 2
            wc.toggleLibrary(nil)
            return start && opened && folded && back && dropped && clicked && !wc.libraryWanted && !defaults.bool(forKey: "ui.libraryVisible")
        }))
        return steps
    }
}
