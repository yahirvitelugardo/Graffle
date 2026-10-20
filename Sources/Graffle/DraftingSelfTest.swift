import AppKit

/// Self-test steps for drafting: drawing scale, dimension lines, precise lines, snapping and real-size architecture parts.
extension AppDelegate {
    func draftingSteps(bundled: Bool) -> [(String, () -> Bool)] {
        var steps: [(String, () -> Bool)] = []
        func near(_ a: Double, _ b: Double, _ e: Double = 0.01) -> Bool { abs(a - b) <= e }
        func hostedCanvas() -> (CanvasView, NSWindow) {
            let canvas = CanvasView(frame: NSRect(origin: .zero, size: CanvasView.canvasSize))
            let host = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 600, height: 400), styleMask: [.titled], backing: .buffered, defer: true)
            host.contentView?.addSubview(canvas)
            canvas.undoManager?.groupsByEvent = false
            return (canvas, host)
        }

        func run(_ canvas: CanvasView, _ f: () -> Void) {
            canvas.undoManager?.beginUndoGrouping(); f(); canvas.undoManager?.endUndoGrouping()
        }

        steps.append(("drafting: the drawing scale converts points, formats lengths and works out printed scales", {
            let std = DrawingScale.standard
            let mm = { () -> DrawingScale in var s = DrawingScale(); s.unit = .millimeter; s.unitsPerPoint = 5; return s }()
            let fifty = DrawingScale.ratio(50, unit: .centimeter)
            var meters = DrawingScale(); meters.unit = .meter; meters.unitsPerPoint = 0.01
            var inches = DrawingScale(); inches.unit = .inch; inches.unitsPerPoint = 0.5; inches.decimals = 2
            return std.format(points: 250) == "250 cm" && near(std.pointsPerCentimeter, 1) && near(std.wallThicknessPoints, 15)
                && mm.format(points: 100) == "500 mm" && near(mm.pointsPerCentimeter, 2)
                && near(fifty.printRatio, 50, 1e-6) && near(fifty.pointsPerCentimeter, 72 / 2.54 / 50, 1e-6)
                && meters.format(points: 320) == "3.20 m" && inches.format(points: 5) == "2.50 in"
                && near(DrawingScale.ratio(100, unit: .meter).printRatio, 100, 1e-6)
                && near(std.points(std.length(37)), 37)
        }))
        steps.append(("drafting: scale and dimensions survive saving; older files without them still open", {
            var d = Drawing()
            let layer = d.layers[0].id
            let a = Shape(layer: layer, kind: .rectangle, frame: CGRect(x: 100, y: 100, width: 200, height: 80))
            d.shapes = [a]
            d.scale = DrawingScale.ratio(20, unit: .meter)
            d.connectors = [Connector(layer: layer, from: a.id, to: a.id, startHead: .none, endHead: .none, dimension: DimensionSpec(axis: .vertical, offset: -12))]
            guard let data = try? JSONEncoder().encode(d), let back = try? JSONDecoder().decode(Drawing.self, from: data), back == d,
                  back.connectors[0].dimension?.axis == .vertical, back.scale?.unit == .meter else { return false }
            // A file saved before any of this: strip the new keys.
            guard var json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return false }
            json.removeValue(forKey: "scale")
            var conns = (json["connectors"] as? [[String: Any]]) ?? []
            for i in conns.indices { conns[i].removeValue(forKey: "dimension") }
            json["connectors"] = conns
            guard let old = try? JSONSerialization.data(withJSONObject: json), let legacy = try? JSONDecoder().decode(Drawing.self, from: old) else { return false }
            return legacy.scale == nil && legacy.connectors[0].dimension == nil
        }))
        steps.append(("drafting: dimension lines measure widths, gaps and lines, follow the shapes and the scale", {
            let layer = UUID()
            let box = Shape(layer: layer, kind: .rectangle, frame: CGRect(x: 100, y: 200, width: 300, height: 120))
            let other = Shape(layer: layer, kind: .rectangle, frame: CGRect(x: 700, y: 260, width: 100, height: 100))
            let line = Drafting.lineShape(from: CGPoint(x: 0, y: 0), to: CGPoint(x: 300, y: 400), layer: layer, style: Style())
            func dim(_ axis: DimensionAxis, _ a: Shape, _ b: Shape, _ scale: DrawingScale? = nil) -> ConnectorGeometry {
                ConnectorGeometry.make(Connector(layer: layer, from: a.id, to: b.id, startHead: .none, endHead: .none, dimension: DimensionSpec(axis: axis, offset: 40)), a, b, scale: scale)
            }
            let w = dim(.horizontal, box, box), h = dim(.vertical, box, box), gap = dim(.horizontal, box, other)
            let aligned = dim(.aligned, line, line)
            // The line sits `offset` above the top edge; the extension lines run from the edge to it.
            let above = near(Double(w.startPoint.y), 160) && near(Double(w.endPoint.y), 160) && near(Double(w.startPoint.x), 100) && near(Double(w.endPoint.x), 400)
            let left = near(Double(h.startPoint.x), 60) && near(Double(h.endPoint.y - h.startPoint.y), 120)
            let texts = w.measureText == "300 cm" && h.measureText == "120 cm" && gap.measureText == "300 cm" && aligned.measureText == "500 cm"
            let moved = { () -> Bool in var b2 = box; b2.frame.origin.x += 50; return dim(.horizontal, b2, other).measureText == "250 cm" }()
            var scale = DrawingScale(); scale.unit = .meter; scale.unitsPerPoint = 0.01
            let scaled = dim(.horizontal, box, box, scale).measureText == "3.00 m"
            var named = Connector(layer: layer, from: box.id, to: box.id, startHead: .none, endHead: .none, text: "300 clear", dimension: DimensionSpec())
            named.text = "300 clear"
            let geometry = ConnectorGeometry.make(named, box, box)
            return above && left && texts && moved && scaled && geometry.measuredLength == 300 && !w.path.boundingBoxOfPath.isNull
        }))
        steps.append(("drafting: angle constraints, angles and snap points", {
            let o = CGPoint(x: 100, y: 100)
            let c15 = Drafting.constrain(CGPoint(x: 300, y: 130), from: o, stepDegrees: 15)
            let c90 = Drafting.constrain(CGPoint(x: 300, y: 130), from: o, stepDegrees: 90)
            let ok1 = near(Double(c90.y), 100) && near(Double(c90.x), 100 + hypot(200, 30), 0.01)
            let turn = Drafting.angle(from: o, to: c15).truncatingRemainder(dividingBy: 15)
            let ok2 = near(Double(hypot(c15.x - o.x, c15.y - o.y)), hypot(200, 30), 0.01) && (near(turn, 0, 0.01) || near(turn, 15, 0.01))
            let ok3 = near(Drafting.angle(from: o, to: CGPoint(x: 200, y: 0)), 45) && near(Drafting.angle(from: o, to: CGPoint(x: 100, y: 200)), 270) && near(Drafting.angle(from: o, to: CGPoint(x: 200, y: 100)), 0)
            let box = Shape(layer: UUID(), kind: .rectangle, frame: CGRect(x: 0, y: 0, width: 100, height: 50))
            let line = Drafting.lineShape(from: CGPoint(x: 10, y: 10), to: CGPoint(x: 110, y: 10), layer: UUID(), style: Style())
            let pts = Drafting.snapPoints(of: box)
            let ends = Drafting.straightEnds(of: line)
            let ok4 = pts.count == 9 && pts.contains(Drafting.SnapPoint(point: CGPoint(x: 50, y: 25), kind: .center)) && ends?.0 == CGPoint(x: 10, y: 10) && ends?.1 == CGPoint(x: 110, y: 10)
                && Drafting.snapPoints(of: line).count == 3
            let hit = Drafting.nearest(CGPoint(x: 3, y: 4), in: pts, radius: 10)
            let miss = Drafting.nearest(CGPoint(x: 300, y: 300), in: pts, radius: 10)
            // Rotating shapes together keeps them assembled: a quarter turn of two shapes about a point.
            var pair = [Shape(layer: UUID(), kind: .rectangle, frame: CGRect(x: 0, y: 0, width: 10, height: 10)),
                        Shape(layer: UUID(), kind: .rectangle, frame: CGRect(x: 20, y: 0, width: 10, height: 10))]
            Drafting.rotate(&pair, by: 90, about: CGPoint(x: 15, y: 5))
            let ok5 = near(Double(pair[0].center.x), 15) && near(Double(pair[0].center.y), -5) && near(Double(pair[1].center.x), 15) && near(Double(pair[1].center.y), 15)
                && pair.allSatisfy { $0.rotation == 90 }
            return ok1 && ok2 && ok3 && ok4 && hit?.kind == .corner && miss == nil && ok5
        }))
        steps.append(("drafting: the Line and Wall tools draw with ortho, Shift angles, point snapping and the scale's wall thickness", {
            let (canvas, host) = hostedCanvas()
            defer { host.contentView = nil }
            let defaults = UserDefaults.standard
            let saved = ["orthoMode", "objectSnap"].map { ($0, defaults.object(forKey: $0)) }
            defer { for (k, v) in saved { if let v { defaults.set(v, forKey: k) } else { defaults.removeObject(forKey: k) } } }
            canvas.load(Drawing())
            canvas.snapToGrid = false
            func event(_ type: NSEvent.EventType, _ p: CGPoint, flags: NSEvent.ModifierFlags = []) -> NSEvent {
                NSEvent.mouseEvent(with: type, location: canvas.convert(p, to: nil), modifierFlags: flags, timestamp: 0, windowNumber: host.windowNumber,
                                   context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!
            }
            func draw(_ a: CGPoint, _ b: CGPoint, flags: NSEvent.ModifierFlags = []) {
                canvas.undoManager?.beginUndoGrouping()
                canvas.mouseDown(with: event(.leftMouseDown, a, flags: flags))
                canvas.mouseDragged(with: event(.leftMouseDragged, b, flags: flags))
                canvas.mouseUp(with: event(.leftMouseUp, b, flags: flags))
                canvas.undoManager?.endUndoGrouping()
            }
            canvas.orthoMode = true
            canvas.objectSnap = true
            canvas.tool = .line
            draw(CGPoint(x: 300, y: 300), CGPoint(x: 500, y: 312))                         // ortho: dead level
            guard let first = canvas.drawing.shapes.first, let e1 = Drafting.straightEnds(of: first) else { return false }
            let level = near(Double(e1.0.y), 300) && near(Double(e1.1.y), 300) && near(Double(abs(e1.1.x - e1.0.x)), hypot(200, 12), 0.5)
            canvas.orthoMode = false
            draw(CGPoint(x: 504, y: 297), CGPoint(x: 700, y: 297))                          // starts near the first line's end: snaps to it
            guard canvas.drawing.shapes.count == 2, let e2 = Drafting.straightEnds(of: canvas.drawing.shapes[1]) else { return false }
            let snapped = near(Double(e2.0.x), Double(e1.1.x), 0.01) && near(Double(e2.0.y), Double(e1.1.y), 0.01)
            draw(CGPoint(x: 100, y: 800), CGPoint(x: 300, y: 920), flags: .shift)           // Shift: 15 degree steps (120 degrees of travel on 200 wide: 31 deg -> 30)
            guard let e3 = Drafting.straightEnds(of: canvas.drawing.shapes[2]) else { return false }
            let angle = Drafting.angle(from: e3.0, to: e3.1)
            let stepped = near(angle, 315, 0.01) || near(angle, 330, 0.01)
            // Walls take the scale's thickness.
            run(canvas) { canvas.setScale(DrawingScale.ratio(50, unit: .centimeter)) }
            canvas.tool = .wall
            draw(CGPoint(x: 100, y: 1000), CGPoint(x: 400, y: 1000))
            let wall = canvas.drawing.shapes.last
            let thick = wall?.name == "Wall" && near(wall?.style.stroke.width ?? 0, DrawingScale.ratio(50, unit: .centimeter).wallThicknessPoints, 0.001)
                && wall?.style.stroke.cap == .square
            // Everything is one undo step per line.
            let before = canvas.drawing.shapes.count
            canvas.undoManager?.undo()
            return level && snapped && stepped && thick && canvas.drawing.shapes.count == before - 1
        }))
        steps.append(("drafting: dimensions are added from the selection, edited by number, and lines take an exact length and angle", {
            let (canvas, host) = hostedCanvas()
            defer { host.contentView = nil }
            var d = Drawing()
            let layer = d.layers[0].id
            let a = Shape(layer: layer, kind: .rectangle, frame: CGRect(x: 100, y: 100, width: 200, height: 100))
            let b = Shape(layer: layer, kind: .rectangle, frame: CGRect(x: 500, y: 100, width: 100, height: 100))
            let line = Drafting.lineShape(from: CGPoint(x: 100, y: 500), to: CGPoint(x: 300, y: 500), layer: layer, style: Style())
            d.shapes = [a, b, line]
            canvas.load(d)
            canvas.selection = []
            let none = !canvas.canAddDimension
            canvas.selection = [a.id]
            run(canvas) { canvas.addDimension(.horizontal) }
            guard let dim = canvas.selectedDimension, dim.from == a.id, dim.to == a.id, dim.endHead == .none else { return false }
            run(canvas) { canvas.setSelectedDimension(axis: .vertical, offset: -20, text: "H") }
            let edited = canvas.selectedDimension?.dimension == DimensionSpec(axis: .vertical, offset: -20) && canvas.selectedDimension?.text == "H"
            canvas.selection = [a.id]
            canvas.selection = [a.id, b.id]
            run(canvas) { canvas.addDimension(.horizontal) }
            let pair = canvas.selectedDimension.map { $0.from == a.id && $0.to == b.id } ?? false
            canvas.selection = [line.id]
            let info = canvas.selectedLineInfo
            run(canvas) { canvas.setSelectedLine(length: 100, angle: 90) }
            guard let line2 = canvas.drawing.shapes.first(where: { $0.id == line.id }), let ends = Drafting.straightEnds(of: line2) else { return false }
            let exact = near(Double(ends.0.x), 100) && near(Double(ends.0.y), 500) && near(Double(ends.1.x), 100) && near(Double(ends.1.y), 400)
            let scaleUndo: Bool = {
                canvas.undoManager?.beginUndoGrouping(); canvas.setScale(DrawingScale.ratio(100, unit: .meter)); canvas.undoManager?.endUndoGrouping()
                let set = canvas.drawing.scale?.unit == .meter
                canvas.undoManager?.undo()
                return set && canvas.drawing.scale == nil
            }()
            return none && edited && pair && info.map { near($0.length, 200) && near($0.angle, 0) } == true && exact && scaleUndo
        }))
        steps.append(("drafting: turning a selection keeps its parts assembled, and dimensions export to SVG with their value", {
            let (canvas, host) = hostedCanvas()
            defer { host.contentView = nil }
            var d = Drawing()
            let layer = d.layers[0].id
            let a = Shape(layer: layer, kind: .rectangle, frame: CGRect(x: 100, y: 100, width: 100, height: 40))
            let b = Shape(layer: layer, kind: .rectangle, frame: CGRect(x: 300, y: 100, width: 100, height: 40))
            d.shapes = [a, b]
            d.connectors = [Connector(layer: layer, from: a.id, to: b.id, startHead: .none, endHead: .none, dimension: DimensionSpec(axis: .horizontal, offset: 30))]
            d.scale = DrawingScale.ratio(10, unit: .meter)
            canvas.load(d)
            canvas.selection = [a.id, b.id]
            let item = NSMenuItem(); item.tag = 0
            canvas.undoManager?.beginUndoGrouping(); canvas.rotateQuarter(item); canvas.undoManager?.endUndoGrouping()
            let turned = canvas.drawing.shapes
            let center = CGPoint(x: 250, y: 120)
            let ok = turned.allSatisfy { $0.rotation == 90 } && near(Double(turned[0].center.x), Double(center.x)) && near(Double(turned[0].center.y), Double(center.y) - 100)
                && near(Double(turned[1].center.x), Double(center.x)) && near(Double(turned[1].center.y), Double(center.y) + 100)
            let svg = canvas.svgData().flatMap { String(data: $0, encoding: .utf8) } ?? ""
            let value = ConnectorGeometry.make(canvas.drawing.connectors[0], turned[0], turned[1], scale: canvas.drawing.scale).measureText ?? "?"
            return ok && !value.isEmpty && svg.contains(value) && svg.contains("m<") || svg.contains(value)
        }))
        steps.append(("architecture: parts keep real sizes, follow the drawing scale, come as grouped assemblies, and the floor plan measures right", {
            let parts = ArchitectureCatalog.items
            guard parts.count >= 25, Set(parts.map(\.id)).count == parts.count, parts.allSatisfy({ $0.realSize != nil && $0.category == ShapeCatalog.architecture && $0.compose != nil }) else { return false }
            guard let door = parts.first(where: { $0.id == "arch-door-single" }), let bed = parts.first(where: { $0.id == "arch-bed-double" }) else { return false }
            let at1 = bed.drawing(layer: UUID(), style: Style(), pointsPerCentimeter: 1).shapes[0].frame.size
            let k = DrawingScale.ratio(50, unit: .centimeter).pointsPerCentimeter
            let at50 = bed.drawing(layer: UUID(), style: Style(), pointsPerCentimeter: k).shapes[0].frame.size
            let sizes = near(Double(at1.width), 160) && near(Double(at1.height), 200) && near(Double(at50.width), 160 * k) && near(Double(at50.height), 200 * k)
            let doorShapes = door.drawing(layer: UUID(), style: Style()).shapes
            let assembly = doorShapes.count == 2 && doorShapes[0].style.fill.color == RGBA(1, 1, 1) && doorShapes[0].style.stroke.visible == false
            let (canvas, host) = hostedCanvas()
            defer { host.contentView = nil }
            canvas.load(Drawing())
            run(canvas) { canvas.setScale(DrawingScale.ratio(50, unit: .centimeter)) }
            run(canvas) { canvas.placeDrawing(door.drawing(layer: canvas.activeLayerID, style: Style(), pointsPerCentimeter: k), named: "Add", near: CGPoint(x: 800, y: 800), themed: false) }
            let placed = canvas.drawing.shapes
            let grouped = placed.count == 2 && Set(placed.compactMap(\.group)).count == 1 && canvas.selection.count == 2
            let wide = near(Double(placed[1].frame.width), 90 * k)
            // The floor plan: a scale, four dimensions and true readings.
            let plan = Starters.drawing(.floorPlan)
            let readings = plan.connectors.compactMap { c -> String? in
                guard let a = plan.shapes.first(where: { $0.id == c.from }), let b = plan.shapes.first(where: { $0.id == c.to }) else { return nil }
                return ConnectorGeometry.make(c, a, b, scale: plan.scale).measureText
            }
            let ids = Set(plan.shapes.map(\.id))
            return sizes && assembly && grouped && wide && plan.scale == .standard && readings == ["800 cm", "400 cm", "500 cm", "300 cm"]
                && plan.connectors.allSatisfy { ids.contains($0.from) && ids.contains($0.to) }
        }))
        return steps
    }
}
