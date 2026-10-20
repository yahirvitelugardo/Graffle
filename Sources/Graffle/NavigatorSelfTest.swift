import AppKit

/// Self-test steps for the zoom tool, the zoom commands and the Navigator panel (run with `--selftest`).
extension AppDelegate {
    func navigatorSteps() -> [(String, () -> Bool)] {
        var steps: [(String, () -> Bool)] = []
        let wc = DocumentWindowController()
        var ready = false
        func prepare() {
            guard !ready else { return }
            ready = true
            wc.window?.setContentSize(NSSize(width: 1000, height: 700))
            wc.window?.orderFront(nil)
            wc.window?.layoutIfNeeded()
            var d = Drawing()
            let layer = d.layers[0].id
            d.shapes = [Shape(layer: layer, kind: .rounded, frame: CGRect(x: 600, y: 500, width: 200, height: 100), text: "A"),
                        Shape(layer: layer, kind: .rounded, frame: CGRect(x: 1400, y: 900, width: 200, height: 100), text: "B")]
            wc.canvas.load(d)
            wc.scroll.magnification = 1
            wc.canvas.scrollCenter(to: CGPoint(x: 700, y: 550))
        }
        func event(_ type: NSEvent.EventType, _ p: CGPoint, flags: NSEvent.ModifierFlags = []) -> NSEvent {
            NSEvent.mouseEvent(with: type, location: wc.canvas.convert(p, to: nil), modifierFlags: flags, timestamp: 0,
                               windowNumber: wc.window?.windowNumber ?? 0, context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!
        }
        func visible() -> CGRect { wc.scroll.documentVisibleRect }
        func near(_ a: CGFloat, _ b: CGFloat, _ e: CGFloat = 2) -> Bool { abs(a - b) <= e }
        func pump(_ seconds: Double) { RunLoop.main.run(until: Date().addingTimeInterval(seconds)) }

        steps.append(("zoom: the Z tool zooms in on click, out on Option-click, and to a dragged area", {
            prepare()
            wc.canvas.tool = .select
            wc.canvas.keyDown(with: NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: wc.window?.windowNumber ?? 0,
                                                     context: nil, characters: "z", charactersIgnoringModifiers: "z", isARepeat: false, keyCode: 6)!)
            let keyed = wc.canvas.tool == .zoom
            let start = wc.scroll.magnification
            let p = CGPoint(x: 700, y: 550)
            wc.canvas.mouseDown(with: event(.leftMouseDown, p)); wc.canvas.mouseUp(with: event(.leftMouseUp, p))
            let zoomedIn = near(wc.scroll.magnification, start * 2, 0.01)
            wc.canvas.mouseDown(with: event(.leftMouseDown, p, flags: .option)); wc.canvas.mouseUp(with: event(.leftMouseUp, p, flags: .option))
            let zoomedOut = near(wc.scroll.magnification, start, 0.01)
            let a = CGPoint(x: 600, y: 500), b = CGPoint(x: 800, y: 600)
            wc.canvas.mouseDown(with: event(.leftMouseDown, a))
            wc.canvas.mouseDragged(with: event(.leftMouseDragged, b))
            wc.canvas.mouseUp(with: event(.leftMouseUp, b))
            let boxed = wc.scroll.magnification > 2 && visible().insetBy(dx: -4, dy: -4).contains(CGRect(x: 600, y: 500, width: 200, height: 100))
            let drewNothing = wc.canvas.drawing.shapes.count == 2 && wc.canvas.selection.isEmpty        // a zoom tool never edits
            wc.canvas.tool = .select
            return keyed && zoomedIn && zoomedOut && boxed && drewNothing
        }))
        steps.append(("zoom: Command + scroll zooms around the pointer, plain scroll does not", {
            prepare()
            wc.scroll.magnification = 1
            wc.canvas.scrollCenter(to: CGPoint(x: 700, y: 550))
            func wheel(_ dy: Int32, _ flags: NSEvent.ModifierFlags) -> NSEvent {
                let cg = CGEvent(scrollWheelEvent2Source: nil, units: .line, wheelCount: 1, wheel1: dy, wheel2: 0, wheel3: 0)!
                cg.flags = CGEventFlags(rawValue: UInt64(flags.rawValue))
                return NSEvent(cgEvent: cg)!
            }
            let p = CGPoint(x: 700, y: 550)
            let anchorBefore = wc.canvas.convert(p, to: wc.scroll.contentView)
            wc.canvas.scrollWheel(with: wheel(2, .command))
            let zoomedIn = wc.scroll.magnification > 1.2
            wc.canvas.scrollWheel(with: wheel(-2, .command))
            let back = abs(wc.scroll.magnification - 1) < 0.2
            let before = wc.scroll.magnification
            wc.canvas.scrollWheel(with: wheel(3, []))
            let plain = abs(wc.scroll.magnification - before) < 0.001
            _ = anchorBefore
            wc.scroll.magnification = 1
            return zoomedIn && back && plain
        }))
        steps.append(("zoom: Fit and Zoom to Selection frame the diagram or the selection; zoom stays within 10%…800%", {
            prepare()
            wc.canvas.zoomToFitDiagram()
            let all = CGRect(x: 600, y: 500, width: 1000, height: 500)
            let fitsAll = visible().insetBy(dx: -1, dy: -1).contains(all)
            wc.canvas.selection = [wc.canvas.drawing.shapes[1].id]
            let before = wc.scroll.magnification
            wc.canvas.zoomToFitSelection()
            let fitsOne = visible().insetBy(dx: -1, dy: -1).contains(wc.canvas.drawing.shapes[1].frame) && wc.scroll.magnification > before
            wc.canvas.selection = []
            wc.canvas.setMagnification(500)
            let top = wc.scroll.magnification
            wc.canvas.setMagnification(0.0001)
            let bottom = wc.scroll.magnification
            var empty = Drawing(); empty.shapes = []
            let kept = wc.canvas.drawing
            wc.canvas.load(empty); wc.canvas.zoomToFitDiagram()
            let reset = near(wc.scroll.magnification, 1, 0.01)
            wc.canvas.load(kept)
            return fitsAll && fitsOne && near(top, 8, 0.01) && near(bottom, 0.1, 0.001) && reset
        }))
        steps.append(("zoom: the palette has a Zoom tool, and View has Fit, Selection and Navigator commands", {
            func buttons(in v: NSView) -> [NSButton] { (v as? NSButton).map { [$0] } ?? v.subviews.flatMap(buttons) }
            let hasButton = wc.window?.contentView.map { buttons(in: $0).contains { $0.toolTip?.hasPrefix("Zoom (Z)") == true } } ?? false
            let view = self.makeMainMenu().items.first { $0.title == "View" }?.submenu
            func action(_ t: String) -> Selector? { view?.items.first { $0.title == t }?.action }
            return hasButton && action("Zoom to Fit") == #selector(DocumentWindowController.zoomToFit(_:))
                && action("Zoom to Selection") == #selector(DocumentWindowController.zoomToSelection(_:))
                && action("Hide Navigator") == #selector(DocumentWindowController.toggleNavigator(_:))
        }))
        var wasVisible = true
        steps.append(("navigator: the minimap floats over the canvas and shows what is visible", {
            prepare()
            wasVisible = NavigatorPrefs.isVisible
            NavigatorPrefs.isVisible = true
            wc.window?.contentView?.layoutSubtreeIfNeeded()
            let zo = wc.zoomOverlay
            wc.scroll.magnification = 1
            wc.canvas.scrollCenter(to: CGPoint(x: 1000, y: 800))
            zo.refresh()
            let box = zo.map.viewportRect
            let v = visible()
            let sameShape = box.width > 5 && near(box.width / box.height, v.width / v.height, 0.05)
            let sameSpot = near(zo.map.canvasPoint(CGPoint(x: box.midX, y: box.midY)).x, v.midX, 4)
            let size = zo.map.bounds.size
            let insideCanvas = wc.zoomOverlay.convert(wc.zoomOverlay.bounds, to: nil).maxX <= (wc.window?.contentView?.bounds.width ?? 0)
            return !zo.isHidden && sameShape && sameSpot && near(size.width, 168, 1) && near(size.height, 104, 1) && insideCanvas && zo.percentText == "100%"
        }))
        steps.append(("navigator: the zoom pill zooms out and in around the center, and the percentage fits the diagram", {
            let zo = wc.zoomOverlay
            wc.scroll.magnification = 1
            wc.canvas.scrollCenter(to: CGPoint(x: 1000, y: 800))
            let center = CGPoint(x: visible().midX, y: visible().midY)
            zo.pressZoomIn()
            let zin = near(wc.scroll.magnification, 2, 0.01) && near(visible().midX, center.x, 3) && zo.percentText == "200%"
            zo.pressZoomOut(); zo.pressZoomOut()
            let zout = near(wc.scroll.magnification, 0.5, 0.01) && zo.percentText == "50%"
            zo.pressPercent()
            let fitted = visible().insetBy(dx: -1, dy: -1).contains(CGRect(x: 600, y: 500, width: 1000, height: 500))
            wc.scroll.magnification = 1
            return zin && zout && fitted
        }))
        steps.append(("navigator: clicking or dragging the minimap scrolls the document there", {
            let zo = wc.zoomOverlay
            wc.window?.contentView?.layoutSubtreeIfNeeded()
            wc.scroll.magnification = 2
            wc.canvas.scrollCenter(to: CGPoint(x: 700, y: 600))
            zo.refresh()
            func click(_ p: CGPoint, drag: Bool = false) -> NSEvent {
                NSEvent.mouseEvent(with: drag ? .leftMouseDragged : .leftMouseDown, location: zo.map.convert(p, to: nil), modifierFlags: [], timestamp: 0,
                                   windowNumber: wc.window?.windowNumber ?? 0, context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!
            }
            zo.map.mouseDown(with: click(zo.map.mapRect(CGRect(x: 1500, y: 1000, width: 0, height: 0)).origin))
            let jumped = near(visible().midX, 1500, 4) && near(visible().midY, 1000, 4)
            zo.map.mouseDragged(with: click(zo.map.mapRect(CGRect(x: 900, y: 700, width: 0, height: 0)).origin, drag: true))
            let dragged = near(visible().midX, 900, 4) && near(visible().midY, 700, 4)
            wc.scroll.magnification = 1
            return jumped && dragged
        }))
        steps.append(("navigator: View hides or shows it in every window", {
            let menu = NSMenuItem(title: "", action: #selector(DocumentWindowController.toggleNavigator(_:)), keyEquivalent: "")
            _ = wc.validateMenuItem(menu)
            let hideTitle = menu.title == "Hide Navigator"
            wc.toggleNavigator(nil)
            let hidden = wc.zoomOverlay.isHidden
            _ = wc.validateMenuItem(menu)
            let showTitle = menu.title == "Show Navigator"
            wc.toggleNavigator(nil)
            let shown = !wc.zoomOverlay.isHidden
            NavigatorPrefs.isVisible = wasVisible
            wc.window?.orderOut(nil)
            return hideTitle && hidden && showTitle && shown
        }))
        return steps
    }
}
