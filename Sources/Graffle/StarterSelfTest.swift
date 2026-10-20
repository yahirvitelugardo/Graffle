import AppKit

/// Self-test steps for the ready-made diagram types and the entity-relationship line ends.
extension AppDelegate {
    func starterSteps(bundled: Bool) -> [(String, () -> Bool)] {
        var steps: [(String, () -> Bool)] = []
        steps.append(("starters: every ready-made diagram builds, draws, exports and survives saving", {
            for starter in Starter.allCases {
                let d = Starters.drawing(starter)
                guard !d.shapes.isEmpty, let data = try? JSONEncoder().encode(d), (try? JSONDecoder().decode(Drawing.self, from: data)) == d else { return false }
                // Every connector joins shapes that exist, and nothing sits off the canvas.
                let ids = Set(d.shapes.map(\.id))
                if !d.connectors.allSatisfy({ ids.contains($0.from) && ids.contains($0.to) }) { return false }
                if let b = d.contentBounds, b.minX < 0 || b.minY < 0 || b.maxX > CanvasView.canvasSize.width || b.maxY > CanvasView.canvasSize.height { return false }
                let canvas = CanvasView(frame: NSRect(origin: .zero, size: CanvasView.canvasSize))
                canvas.load(d)
                if canvas.pngData()?.isEmpty != false || canvas.svgData()?.isEmpty != false { return false }
            }
            return Starter.allCases.count == 9
        }))
        steps.append(("starters: each has its distinctive parts (braces, crow's feet, fishbone ribs, pyramid levels, tree leaves, UML boxes)", {
            func d(_ s: Starter) -> Drawing { Starters.drawing(s) }
            let ends = Set(d(.entityRelationship).connectors.flatMap { [$0.startHead, $0.endHead] })
            let er = d(.entityRelationship).shapes.filter { $0.text == "Customer" || $0.text == "Order" }.count == 2 && ends.isSuperset(of: [.doubleBar, .crowFootCircle, .crowFootBar])
            let braces = d(.synoptic).shapes.filter { $0.kind == .path && $0.outline?.contains { $0.op == .curve } == true }.count == 7
            let fish = d(.ishikawa).shapes.filter { $0.kind == .path }.count == 1 + 6 + 18 && d(.ishikawa).shapes.contains { $0.text.hasPrefix("Problem") }
            let pyr = d(.pyramid).shapes.filter { $0.kind == .path && $0.style.fill.kind != .none }.count == 6
            let tree = d(.tree).shapes.filter { $0.kind == .triangle }.count == 9 && d(.tree).connectors.count == 12
            let uml = d(.uml).connectors.count == 5 && d(.uml).shapes.contains { $0.text == "«interface»" } && d(.uml).connectors.contains { $0.endHead == .hollowTriangle }
            let concept = d(.conceptual).shapes.filter { $0.kind == .ellipse }.count == 10 && d(.conceptual).connectors.contains { !$0.text.isEmpty }
            return er && braces && fish && pyr && tree && uml && concept
        }))
        steps.append(("circuit: every symbol builds with pins, wires attach at the pins (also when rotated), and the starter has its parts", {
            for part in CircuitPart.allCases {
                let s = part.makeShape(layer: UUID(), at: .zero, number: 1)
                if part != .junction, (s.pins ?? []).isEmpty || s.outline?.isEmpty != false { return false }
            }
            let layer = UUID()
            let a = CircuitPart.resistor.makeShape(layer: layer, at: CGPoint(x: 100, y: 100), number: 1)
            let b = CircuitPart.ground.makeShape(layer: layer, at: CGPoint(x: 300, y: 300), number: 1)
            var rotated = CircuitPart.battery.makeShape(layer: layer, at: CGPoint(x: 100, y: 400), number: 1, rotation: 90)
            let c = Connector(layer: layer, from: a.id, to: b.id, route: .orthogonal)
            guard let g = ConnectorGeometry.make(c, a, b) as ConnectorGeometry? else { return false }
            let ends = abs(g.startPoint.x - a.frame.maxX) < 0.5 && abs(g.startPoint.y - a.frame.midY) < 0.5
                && abs(g.endPoint.x - b.frame.midX) < 0.5 && abs(g.endPoint.y - b.frame.minY) < 0.5
            // A battery turned a quarter turn has its leads at the top and bottom of its frame's center.
            let top = rotated.pinFacing(CGPoint(x: rotated.center.x, y: -1000))
            rotated.rotation = 0
            let d = Starters.drawing(.circuit)
            let ok = d.shapes.filter { $0.pins != nil }.count == 13 && d.connectors.count == 12
                && d.shapes.contains { $0.name == "Transistor" || $0.name == "NPN Transistor" }
            guard let t = top else { return false }
            return ends && abs(t.point.x - rotated.center.x) < 0.5 && abs(t.point.y - (rotated.center.y - 40)) < 0.5 && ok
        }))
        steps.append(("starters: crow's-foot ends draw on the canvas and in SVG, and appear in the connector menus", {
            let kinds: [HeadKind] = [.crowFoot, .crowFootBar, .crowFootCircle, .doubleBar, .circleBar]
            func ink(_ k: HeadKind) -> Int {
                let image = Glyphs.head(k, atEnd: true)
                guard let tiff = image.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff) else { return -1 }
                var n = 0
                for y in 0..<rep.pixelsHigh { for x in 0..<rep.pixelsWide where (rep.colorAt(x: x, y: y)?.alphaComponent ?? 0) > 0.3 { n += 1 } }
                return n
            }
            let plain = ink(.none)
            let glyphs = kinds.allSatisfy { ink($0) > plain }
            var d = Drawing()
            let a = Shape(layer: d.layers[0].id, kind: .rectangle, frame: CGRect(x: 100, y: 100, width: 100, height: 60))
            let b = Shape(layer: d.layers[0].id, kind: .rectangle, frame: CGRect(x: 400, y: 100, width: 100, height: 60))
            d.shapes = [a, b]
            d.connectors = [Connector(layer: d.layers[0].id, from: a.id, to: b.id, startHead: .doubleBar, endHead: .crowFootCircle)]
            let canvas = CanvasView(frame: NSRect(origin: .zero, size: CanvasView.canvasSize))
            canvas.load(d)
            let svg = canvas.svgData().flatMap { String(data: $0, encoding: .utf8) } ?? ""
            let titles = kinds.map(\.title) == ["Many", "One or Many", "Zero or Many", "Exactly One", "Zero or One"] && HeadKind.allCases.count == 14
            return glyphs && svg.contains("<circle") && svg.components(separatedBy: "<line").count > 5 && titles
        }))
        steps.append(("starters: unfilled lines and braces take the theme's line look; filled shapes stay filled; Clean restores", {
            var d = Starters.drawing(.synoptic)
            let before = d.shapes.filter { $0.kind == .path }.map(\.style.stroke.color)
            ThemeLibrary.theme(id: "hud-neon")?.apply(to: &d)
            let braces = d.shapes.filter { $0.kind == .path }
            let themed = braces.allSatisfy { $0.style.fill.kind == .none } && braces.allSatisfy { $0.style.stroke.color != before[0] }
            ThemeLibrary.clean.apply(to: &d)
            let restored = d.shapes.filter { $0.kind == .path }.map(\.style.stroke.color) == before
            var p = Starters.drawing(.pyramid)
            ThemeLibrary.theme(id: "soft-ui")?.apply(to: &p)
            let filled = p.shapes.filter { $0.kind == .path && $0.text.isEmpty }.contains { $0.style.fill.kind != .none }
            return themed && restored && filled
        }))
        steps.append(("starters: the wizard lists them after Blank, Architecture and Classes, and Create opens an editable document", {
            guard bundled else { print("      (skipped: needs the .app bundle)"); return true }
            let defaults = UserDefaults.standard
            let saved = ["newDocument.template", "newDocument.theme"].map { ($0, defaults.object(forKey: $0)) }
            defer { for (key, value) in saved { if let value { defaults.set(value, forKey: key) } else { defaults.removeObject(forKey: key) } } }
            let before = NSDocumentController.shared.documents.count
            let template = DocumentTemplate.all.first { $0.starter == .ishikawa }!
            self.createDocument(.init(template: template, theme: ThemeLibrary.clean))
            let docs = NSDocumentController.shared.documents.compactMap { $0 as? GraffleDocument }
            guard NSDocumentController.shared.documents.count == before + 1, let doc = docs.last, let canvas = doc.canvas else { return false }
            let ok = canvas.drawing.shapes.contains { $0.text.hasPrefix("Problem") } && doc.fileURL == nil
            doc.close()
            return ok && template.kind == .starter
        }))
        return steps
    }
}
