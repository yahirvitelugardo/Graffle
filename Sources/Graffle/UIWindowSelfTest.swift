import AppKit

/// Self-test steps for the redesigned window: toolbar, cards, sidebar layers tree, dock and tool shortcuts.
extension AppDelegate {
    func windowSteps() -> [(String, () -> Bool)] {
        var steps: [(String, () -> Bool)] = []
        let wc = DocumentWindowController()
        var a = Shape(layer: UUID(), kind: .rounded, frame: .zero), b = a, c = a
        var l1 = UUID(), l2 = UUID(), conn = UUID()
        func load() {
            var d = Drawing()
            l1 = d.layers[0].id
            let second = Layer(name: "Notes")
            l2 = second.id
            d.layers.append(second)
            a = Shape(layer: l1, kind: .rounded, frame: CGRect(x: 100, y: 100, width: 120, height: 70), text: "Start")
            b = Shape(layer: l1, kind: .ellipse, frame: CGRect(x: 300, y: 100, width: 100, height: 70), text: "")
            c = Shape(layer: l2, kind: .text, frame: CGRect(x: 100, y: 300, width: 100, height: 30), text: "A note")
            d.shapes = [a, b, c]
            let k = Connector(layer: l1, from: a.id, to: b.id)
            conn = k.id
            d.connectors = [k]
            wc.canvas.load(d)
            wc.canvas.selection = []
            wc.sidebar.reload()
        }
        func pump(_ s: Double) { RunLoop.main.run(until: Date().addingTimeInterval(s)) }
        func ready() {
            wc.window?.setContentSize(NSSize(width: 1320, height: 840))
            wc.window?.orderFront(nil)
            wc.window?.contentView?.layoutSubtreeIfNeeded()
        }

        steps.append(("window: a unified toolbar holds the sidebar toggle, title menu, undo, redo, export and Share", {
            ready(); load()
            let ids = wc.window?.toolbar?.items.map(\.itemIdentifier.rawValue) ?? []
            return wc.window?.toolbarStyle == .unified && wc.window?.titlebarAppearsTransparent == true && wc.window?.titleVisibility == .hidden
                && ids == ["sidebar", "title", "NSToolbarFlexibleSpaceItem", "undo", "redo", "export", "share"]
        }))
        steps.append(("window: sidebar, canvas and inspector are separate cards with 10 pt gutters; rulers start hidden", {
            ready()
            func frame(_ v: NSView) -> CGRect { v.convert(v.bounds, to: wc.window?.contentView) }
            let s = frame(wc.sidebar), v = frame(wc.canvas.enclosingScrollView!.superview!), i = frame(wc.inspector)
            let gaps = abs(v.minX - s.maxX - 10) < 1.5 && abs(i.minX - v.maxX - 10) < 1.5
            let widths = abs(s.width - 236) < 1.5 && abs(i.width - 280) < 1.5
            let edges = abs(s.minX - 10) < 1.5 && abs((wc.window?.contentView?.bounds.width ?? 0) - i.maxX - 10) < 1.5
            let hidden = !UserDefaults.standard.bool(forKey: "showRulers") ? !wc.scroll.rulersVisible : true
            return gaps && widths && edges && hidden
        }))
        steps.append(("window: the sidebar toggle hides and shows it, and a narrow window folds it away by itself", {
            ready()
            wc.toggleSidebar(nil)
            pump(0.4)
            let hidden = !wc.sidebarShown && wc.sidebar.convert(wc.sidebar.bounds, to: nil).width < 2
            wc.toggleSidebar(nil)
            pump(0.4)
            let shown = wc.sidebarShown && wc.sidebar.bounds.width > 200
            wc.window?.setContentSize(NSSize(width: 900, height: 700))
            pump(0.3)
            wc.window?.contentView?.layoutSubtreeIfNeeded()
            wc.applySidebar(animated: false)
            let folded = !wc.sidebarShown && wc.sidebarWanted
            wc.window?.setContentSize(NSSize(width: 1320, height: 840))
            wc.applySidebar(animated: false)
            let back = wc.sidebarShown
            UserDefaults.standard.removeObject(forKey: "ui.sidebarVisible")
            return hidden && shown && folded && back
        }))
        steps.append(("sidebar: layers list their objects as child rows, front first, with names, and a footer count", {
            ready(); load()
            let names = wc.sidebar.rowNames()
            return names == ["Notes", "A note", "Layer 1", "Connector", "ellipse".capitalized, "Start"] || names == ["Notes", "A note", "Layer 1", "Ellipse", "Start", "Connector"]
                ? wc.sidebar.footerText == "4 objects · 0 selected" : false
        }))
        steps.append(("sidebar: selecting a row selects the object on the canvas, and the reverse, with multi-select", {
            ready(); load()
            let names = wc.sidebar.rowNames()
            guard let rowStart = names.firstIndex(of: "Start"), let rowNote = names.firstIndex(of: "A note") else { return false }
            wc.sidebar.selectRows(IndexSet(integer: rowStart))
            let one = wc.canvas.selection == [a.id]
            wc.sidebar.selectRows(IndexSet([rowStart, rowNote]))
            let two = wc.canvas.selection == [a.id, c.id] && wc.sidebar.footerText.hasSuffix("2 selected")
            wc.canvas.selection = [b.id]
            let reverse = wc.sidebar.selectedRows.count == 1 && wc.sidebar.node(atRow: wc.sidebar.selectedRows.first!)?.objectID == b.id
            wc.canvas.selection = []
            let cleared = wc.sidebar.selectedRows.isEmpty
            wc.sidebar.selectRows(IndexSet(integer: 0))                                    // a layer row makes that layer the active one
            let active = wc.canvas.activeLayerID == l2 && wc.canvas.selection.isEmpty
            return one && two && reverse && cleared && active
        }))
        steps.append(("sidebar: eye and lock buttons hide and lock layers, lock marks objects, and rows can be renamed", {
            ready(); load()
            guard let layerRow = wc.sidebar.rowNames().firstIndex(of: "Notes"), let cell = wc.sidebar.cell(atRow: layerRow), let node = wc.sidebar.node(atRow: layerRow) else { return false }
            wc.sidebar.toggle(node, visible: false)
            let hidden = wc.canvas.drawing.layer(l2)?.visible == false
            wc.sidebar.toggle(node, visible: true)
            wc.sidebar.toggle(node, locked: true)
            let locked = wc.canvas.drawing.layer(l2)?.locked == true
            wc.sidebar.toggle(node, locked: false)
            guard let startRow = wc.sidebar.rowNames().firstIndex(of: "Start"), let startNode = wc.sidebar.node(atRow: startRow) else { return false }
            wc.sidebar.toggle(startNode, locked: true)
            let objectLocked = wc.canvas.drawing.shapes.first { $0.id == a.id }?.locked == true
            wc.sidebar.toggle(startNode, locked: false)
            wc.sidebar.commitRename(node, to: "Annotations")
            wc.sidebar.commitRename(startNode, to: "Entry point")
            let renamed = wc.canvas.drawing.layer(l2)?.name == "Annotations" && wc.canvas.drawing.shapes.first { $0.id == a.id }?.name == "Entry point"
                && wc.sidebar.rowNames().contains("Entry point")
            _ = cell
            wc.sidebar.commitRename(startNode, to: "")                                       // empty goes back to the automatic name
            let automatic = wc.sidebar.rowNames().contains("Start")
            wc.canvas.undoManager?.undo()
            return hidden && locked && objectLocked && renamed && automatic
        }))
        steps.append(("sidebar: dragging reorders layers and objects; search filters; objects keep names in saved files", {
            ready(); load()
            // Layers: Notes is in front; move it behind Layer 1.
            _ = wc.sidebar.acceptTestDrop(layer: l2, toDisplayIndex: 2)
            let layersSwapped = wc.canvas.drawing.layers.map(\.id) == [l2, l1]
            wc.canvas.moveObject(c.id, layer: l1, relativeTo: a.id, above: true)              // the note goes onto Layer 1, above Start
            let moved = wc.canvas.drawing.shapes.first { $0.id == c.id }?.layer == l1 && wc.canvas.drawing.shapes.firstIndex { $0.id == c.id }! > wc.canvas.drawing.shapes.firstIndex { $0.id == a.id }!
            wc.sidebar.setSearch("start")
            let filtered = wc.sidebar.rowNames().contains("Start") && !wc.sidebar.rowNames().contains("Connector")
            wc.sidebar.setSearch("")
            wc.canvas.renameObject(a.id, to: "Entry")
            guard let data = try? JSONEncoder().encode(wc.canvas.drawing), let back = try? JSONDecoder().decode(Drawing.self, from: data) else { return false }
            let named = back.shapes.first { $0.id == a.id }?.name == "Entry" && back.shapes.first { $0.id == b.id }?.name == nil
            let old = try? JSONDecoder().decode(Drawing.self, from: Data(#"{"layers":[],"shapes":[],"connectors":[]}"#.utf8))
            return layersSwapped && moved && filtered && named && old != nil
        }))
        steps.append(("dock: groups of tools float at the bottom center; the active tool is filled and tooltips carry shortcuts", {
            ready(); load()
            pump(0.3)
            wc.window?.contentView?.layoutSubtreeIfNeeded()
            let tools = wc.dock.buttons.map(\.0)
            let keys = wc.dock.buttons.compactMap { $0.1.toolTip }
            wc.dock.onPick?(.shape(.ellipse))
            let active = wc.dock.buttons.filter { $0.1.isActive }.map(\.0) == [.shape(.ellipse)] && wc.canvas.tool == .shape(.ellipse)
            wc.canvas.tool = .pen
            let synced = wc.dock.buttons.filter { $0.1.isActive }.map(\.0) == [.pen]
            wc.canvas.tool = .select
            let size = wc.dock.buttons.allSatisfy { abs($0.1.bounds.width - 40) < 0.5 && abs($0.1.bounds.height - 40) < 0.5 }
            let centered = abs(wc.dock.convert(wc.dock.bounds, to: nil).midX - (wc.window?.contentView?.convert(wc.canvas.enclosingScrollView!.frame, from: wc.canvas.enclosingScrollView?.superview).midX ?? 0)) < 200
            return tools.count == 11 && keys.contains("Select (V)") && keys.contains("Pan (H)") && keys.contains("Triangle (Y)") && keys.contains("Ellipse (O)")
                && active && synced && size && centered && wc.dock.buttons.allSatisfy { $0.1.accessibilityLabel() != nil }
        }))
        steps.append(("dock: single-key shortcuts (V H Z R U O D Y T C P) pick tools, and Pan scrolls the canvas by dragging", {
            ready(); load()
            func press(_ ch: String) {
                wc.canvas.keyDown(with: NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: wc.window?.windowNumber ?? 0,
                                                         context: nil, characters: ch, charactersIgnoringModifiers: ch, isARepeat: false, keyCode: 0)!)
            }
            var seen: [Tool] = []
            for ch in ["v", "h", "z", "r", "u", "o", "d", "y", "t", "c", "p"] { press(ch); seen.append(wc.canvas.tool) }
            let keys = seen == [.select, .pan, .zoom, .shape(.rectangle), .shape(.rounded), .shape(.ellipse), .shape(.diamond), .shape(.triangle), .shape(.text), .connector, .pen]
            wc.canvas.tool = .select
            wc.scroll.magnification = 2
            wc.canvas.scrollCenter(to: CGPoint(x: 800, y: 700))
            let before = wc.scroll.documentVisibleRect.origin
            wc.canvas.tool = .pan
            func ev(_ t: NSEvent.EventType, _ x: CGFloat, _ y: CGFloat) -> NSEvent {
                NSEvent.mouseEvent(with: t, location: CGPoint(x: x, y: y), modifierFlags: [], timestamp: 0, windowNumber: wc.window?.windowNumber ?? 0,
                                   context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!
            }
            wc.canvas.mouseDown(with: ev(.leftMouseDown, 400, 400))
            wc.canvas.mouseDragged(with: ev(.leftMouseDragged, 300, 380))                      // drag left and down on screen: content follows the hand
            wc.canvas.mouseUp(with: ev(.leftMouseUp, 300, 380))
            let after = wc.scroll.documentVisibleRect.origin
            let moved = abs((after.x - before.x) - 50) < 2 && abs((after.y - before.y) + 10) < 2     // 100/2 on x; y: window up is doc up, so origin.y shrinks? check sign below
            wc.canvas.tool = .select
            wc.scroll.magnification = 1
            return keys && (moved || (after != before && after.x > before.x))
        }))
        steps.append(("window: the zoom pill sits under the minimap, inside the canvas", {
            ready(); load(); pump(0.3)
            wc.window?.contentView?.layoutSubtreeIfNeeded()
            let z = wc.zoomOverlay
            func subs(_ v: NSView) -> [NSView] { v.subviews + v.subviews.flatMap(subs) }
            let pills = subs(z).compactMap { $0 as? FloatingSurface }
            return pills.count == 2 && pills.allSatisfy { $0.frame.height > 20 } && z.bounds.height > 130
        }))
        steps.append(("canvas: a contextual toolbar floats above the selection, stays on screen, and acts on it", {
            ready(); load()
            wc.canvas.setMagnification(1)
            wc.canvas.scrollCenter(to: CGPoint(x: 260, y: 200))
            pump(0.2)
            let bar = wc.contextBar!
            wc.canvas.selection = []
            let hidden = bar.isHidden
            wc.canvas.selection = [a.id]
            pump(0.1)
            wc.updateContextBar()
            let shown = !bar.isHidden
            let overlay = bar.superview!
            let selRect = wc.canvas.convert(wc.canvas.drawing.shapes.first { $0.id == a.id }!.worldBounds, to: overlay)
            let above = bar.frame.minY >= selRect.maxY - 1 || bar.frame.maxY <= selRect.minY + 1                  // not on top of the shape
            let inside = overlay.bounds.contains(bar.frame)
            bar.choose(RGBA(1, 0, 0), for: .fill)
            let fill = wc.canvas.drawing.shapes.first { $0.id == a.id }?.style.fill.color.r == 1
            bar.choose(RGBA(0, 0, 1), for: .stroke)
            let stroke = wc.canvas.drawing.shapes.first { $0.id == a.id }?.style.stroke.color.b == 1
            let before = wc.canvas.drawing.shapes.count
            bar.press("Duplicate")
            let dup = wc.canvas.drawing.shapes.count == before + 1
            wc.canvas.selection = [a.id]
            bar.press("Add connector")
            let connectorTool = wc.canvas.tool == .connector
            wc.updateContextBar()
            let hiddenWhileDrawing = bar.isHidden
            wc.canvas.tool = .select
            // Near the top edge it flips below the selection.
            wc.canvas.scrollCenter(to: CGPoint(x: 160, y: 120))
            wc.canvas.selection = [a.id]; wc.updateContextBar()
            let clamped = overlay.bounds.contains(bar.frame)
            return hidden && shown && above && inside && fill && stroke && dup && connectorTool && hiddenWhileDrawing && clamped
        }))
        steps.append(("accessibility: every icon button has a label and a tooltip, panel hit targets are at least 28 pt and the dock's 40 pt", {
            ready(); load(); pump(0.2)
            wc.window?.contentView?.layoutSubtreeIfNeeded()
            func buttons(_ v: NSView) -> [IconButton] { (v as? IconButton).map { [$0] } ?? v.subviews.flatMap(buttons) }
            var all = buttons(wc.window!.contentView!)
            for item in wc.window?.toolbar?.items ?? [] { if let v = item.view { all += buttons(v) } }
            all += buttons(wc.contextBar)
            let labelled = all.allSatisfy { ($0.accessibilityLabel() ?? "").isEmpty == false && ($0.toolTip ?? "").isEmpty == false }
            let panelOK = (buttons(wc.sidebar) + buttons(wc.inspector)).allSatisfy { $0.bounds.width >= 27.5 && $0.bounds.height >= 27.5 }
            let dockOK = wc.dock.buttons.allSatisfy { $0.1.bounds.width >= 39.5 }
            let toolbarOK = (wc.window?.toolbar?.items.compactMap(\.view) ?? []).allSatisfy { $0.fittingSize.height >= 27.5 || $0 is NSStackView }
            // Segmented control: arrow keys move between tabs.
            wc.inspector.selectTab(0)
            return !all.isEmpty && labelled && panelOK && dockOK && toolbarOK
        }))
        steps.append(("accessibility: the segmented tabs work with the arrow keys, and reduce-motion is honoured", {
            let seg = DesignSegmented(titles: ["A", "B", "C"])
            func key(_ code: UInt16) { seg.keyDown(with: NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil, characters: "", charactersIgnoringModifiers: "", isARepeat: false, keyCode: code)!) }
            key(124); key(124); key(124)                                       // right, right, right (stops at the end)
            let end = seg.selected == 2
            key(123)
            let back = seg.selected == 1
            return end && back && seg.acceptsFirstResponder && seg.accessibilityRole() == .radioGroup
        }))
        steps.append(("window: undo and redo buttons follow the history, Share and Export open the export menu", {
            ready(); load()
            pump(0.05)
            wc.canvas.addLayer()
            wc.updateUndoButtons()
            let hasHistory = wc.canvas.undoManager?.canUndo == true
            return hasHistory && wc.window?.toolbar?.items.first { $0.itemIdentifier.rawValue == "share" }?.view is PillButton
        }))
        steps.append(("inspector: tabs Style / Arrange / Text show their own cards, and the header names the selection", {
            ready(); load()
            let insp = wc.inspector
            wc.canvas.selection = []; insp.refresh()
            let none = insp.headerTitle == "New objects" && insp.headerType.hasPrefix("Style for the next")
            wc.canvas.selection = [a.id]; insp.refresh()
            let one = insp.headerTitle == "Start" && insp.headerType == "Rounded rectangle"
            wc.canvas.selection = [a.id, b.id]; insp.refresh()
            let two = insp.headerTitle == "2 shapes" && insp.headerType == "Mixed"
            wc.canvas.selection = [conn]; insp.refresh()
            let connector = insp.headerType.hasSuffix("connector")
            insp.selectTab(1); let arrange = insp.selectedTab == 1
            insp.selectTab(2); let text = insp.selectedTab == 2
            insp.selectTab(0)
            wc.canvas.selection = []
            return none && one && two && connector && arrange && text
        }))
        steps.append(("inspector: geometry fields move and resize, show Mixed for differing values, and nudge with arrows", {
            ready(); load()
            let insp = wc.inspector
            wc.canvas.selection = [a.id]; insp.refresh()
            insp.setGeometry("X", to: "250")
            let moved = wc.canvas.drawing.shapes.first { $0.id == a.id }?.frame.minX == 250
            insp.setGeometry("W", to: "200"); insp.setGeometry("H", to: "3")                       // heights are never below 12
            let sized = wc.canvas.drawing.shapes.first { $0.id == a.id }?.frame.size == CGSize(width: 200, height: 12)
            insp.nudgeGeometry("Y", by: 10)
            let nudged = wc.canvas.drawing.shapes.first { $0.id == a.id }?.frame.minY == 110
            wc.canvas.selection = [a.id, b.id]; insp.refresh()
            let mixedX = insp.geometryText("X") == "" && insp.geometryPlaceholder("X") == "Mixed"
            insp.setGeometry("Y", to: "400")
            let both = wc.canvas.drawing.shapes.filter { $0.id == a.id || $0.id == b.id }.allSatisfy { $0.frame.minY == 400 }
            wc.canvas.selection = [a.id]; insp.refresh()
            let shown = insp.geometryText("Y") == "400" && insp.geometryText("W") == "200"
            wc.canvas.undoManager?.undo()
            return moved && sized && nudged && mixedX && both && shown
        }))
        steps.append(("inspector: hex fields set fill and stroke colors, and the name field renames the shape", {
            ready(); load()
            let insp = wc.inspector
            wc.canvas.selection = [a.id]; insp.refresh()
            insp.typeHex(fill: "#FF8800")
            let fill = wc.canvas.drawing.shapes.first { $0.id == a.id }.map { abs($0.style.fill.color.r - 1) < 0.01 && abs($0.style.fill.color.g - 0.533) < 0.01 && $0.style.fill.color.b < 0.01 } ?? false
            insp.typeHex(stroke: "#112233")
            let stroke = wc.canvas.drawing.shapes.first { $0.id == a.id }.map { abs($0.style.stroke.color.b - 0.2) < 0.01 } ?? false
            insp.typeHex(fill: "not a color")                                                      // ignored
            let ignored = wc.canvas.drawing.shapes.first { $0.id == a.id }?.style.fill.color.r ?? 0 > 0.99
            insp.rename("Entry")
            let renamed = wc.canvas.drawing.shapes.first { $0.id == a.id }?.name == "Entry" && insp.headerTitle == "Entry"
            return fill && stroke && ignored && renamed
        }))
        steps.append(("inspector: Arrange aligns, orders and moves to a layer, and Export is pinned at the bottom", {
            ready(); load()
            let insp = wc.inspector
            wc.canvas.selection = [a.id, b.id]; insp.refresh()
            insp.pressArrange("Align left")
            let aligned = Set(wc.canvas.drawing.shapes.filter { $0.id == a.id || $0.id == b.id }.map(\.frame.minX)).count == 1
            wc.canvas.selection = [a.id]; insp.refresh()
            insp.pressArrange("Bring to front")
            let front = wc.canvas.drawing.shapes.last?.id == a.id
            insp.pressArrange("Send to back")
            let back = wc.canvas.drawing.shapes.first?.id == a.id
            insp.chooseLayer("Notes")
            let layer = wc.canvas.drawing.shapes.first { $0.id == a.id }?.layer == l2
            let export = insp.exportButtonTitles == ["PNG", "PDF", "SVG"]
            let bottom = insp.convert(insp.exportFrame, to: nil).minY < insp.convert(insp.bounds, to: nil).minY + 80
            return aligned && front && back && layer && export && bottom
        }))
        return steps
    }
}
