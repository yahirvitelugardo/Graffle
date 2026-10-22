import AppKit

/// Self-test steps for importing STL files and drawing their views.
extension AppDelegate {
    func meshSteps(bundled: Bool) -> [(String, () -> Bool)] {
        var steps: [(String, () -> Bool)] = []
        func near(_ a: Double, _ b: Double, _ e: Double = 0.01) -> Bool { abs(a - b) <= e }
        func cube(_ s: Double = 10) -> Mesh { MeshSamples.voxels([[0, 0, 0]], size: s) }
        func length(_ segs: [Segment2D]) -> Double { segs.reduce(0) { $0 + Double(hypot($1.1.x - $1.0.x, $1.1.y - $1.0.y)) } }
        func sphere(rings: Int = 16, segments: Int = 24, r: Double = 10) -> Mesh { MeshSamples.sphere(rings: rings, segments: segments, radius: r) }

        steps.append(("stl: binary and ASCII files are read, bad ones are refused", {
            let mesh = MeshSamples.bracket()
            guard let back = try? STLParser.parse(STLParser.binary(mesh)), back.triangles.count == mesh.triangles.count,
                  near(back.bounds!.max.x, 50), near(back.bounds!.max.y, 30), near(back.bounds!.max.z, 40) else { return false }
            let ascii = """
            solid part
              facet normal 0 0 1
                outer loop
                  vertex 0 0 0
                  vertex 10.5 0 0
                  vertex 0 20 0
                endloop
              endfacet
              facet normal 0 0 1
                outer loop
                  vertex 1 1 1
                  vertex 2 1 1
                  vertex 1 2 1
                endloop
              endfacet
            endsolid part
            """
            guard let a = try? STLParser.parse(Data(ascii.utf8)), a.triangles.count == 2, near(a.bounds!.max.x, 10.5), near(a.bounds!.max.y, 20) else { return false }
            let junk = (try? STLParser.parse(Data("not a model at all".utf8))) == nil
            let empty = (try? STLParser.parse(Data("solid x\nendsolid x".utf8))) == nil
            let truncated = { () -> Bool in var d = STLParser.binary(mesh); d.removeLast(10); return (try? STLParser.parse(d)) == nil }()
            return junk && empty && truncated
        }))
        steps.append(("stl: a cube's views are squares with solid front edges and dashed rear edges", {
            let p = MeshProjector(mesh: cube(), crease: 30)
            let front = p.project(.front), top = p.project(.top)
            let iso = p.project(.isometric)
            return near(Double(front.bounds.width), 10) && near(Double(front.bounds.height), 10) && near(length(front.visible), 40, 0.5) && near(length(front.hidden), 40, 0.5)
                && near(Double(top.bounds.width), 10) && near(length(top.visible), 40, 0.5)
                && near(Double(iso.bounds.width), 10 * sqrt(2), 0.01) && length(iso.visible) > 50 && length(iso.hidden) > 10
                && p.project(.front, hiddenLines: false).hidden.isEmpty
        }))
        steps.append(("stl: a bracket shows its inner base as a dashed line from the side, and flat faces make no lines", {
            let p = MeshProjector(mesh: MeshSamples.bracket(), crease: 30)
            let front = p.project(.front), side = p.project(.left), top = p.project(.top)
            let u = near(length(front.visible), 240, 1.5)                                    // the U's outline: 50 + 2 x 40 + 2 x 10 + 30 + 2 x 30
            // From the side the near wall hides the base's inner top: a dashed line 10 high, as deep as the part (30).
            let dashed = side.hidden.contains { abs(Double($0.0.y) - 10) < 0.6 && abs(Double($0.1.y) - 10) < 0.6 && abs(Double(abs($0.1.x - $0.0.x)) - 30) < 1.5 }
                && !side.visible.contains { abs(Double($0.0.y) - 10) < 0.6 && abs(Double($0.1.y) - 10) < 0.6 && abs(Double($0.1.x - $0.0.x)) > 1.5 }
            // The base is five coplanar cubes: their joins must not be drawn.
            return u && dashed && top.visible.count < 12 && near(Double(side.bounds.width), 30) && near(Double(side.bounds.height), 40)
        }))
        steps.append(("stl: a smooth sphere draws only its outline, whatever the facets", {
            let p = MeshProjector(mesh: sphere(), crease: 30)
            let v = p.project(.front)
            let circumference = 2 * Double.pi * 10
            return v.hidden.isEmpty && !v.visible.isEmpty && length(v.visible) > circumference * 0.9 && length(v.visible) < circumference * 1.15
                && near(Double(v.bounds.width), 20, 0.5)
        }))
        steps.append(("stl: views are laid out as European or American sheets, at one scale, with dimensions that read in the file's unit", {
            var o = MeshViewOptions()
            let eu = MeshDrawing.build(MeshSamples.bracket(), options: o)
            o.system = .american
            let us = MeshDrawing.build(MeshSamples.bracket(), options: o)
            func box(_ d: Drawing, _ name: String) -> CGRect? { d.shapes.first { $0.name == name }?.frame }
            guard let ef = box(eu, "Front"), let et = box(eu, "Top"), let es = box(eu, "Left side"),
                  let uf = box(us, "Front"), let ut = box(us, "Top"), let ei = box(eu, "Isometric") else { return false }
            let european = et.minY > ef.maxY && es.minX > ef.maxX && abs(et.midX - ef.midX) < 1 && abs(es.midY - ef.midY) < 1
            let american = ut.maxY < uf.minY && abs(ut.midX - uf.midX) < 1
            let corner = ei.minX > ef.maxX && ei.minY > ef.maxY
            // One scale: the front is 50 mm wide and the side 30 mm deep.
            let scale = eu.scale?.pointsPerCentimeter ?? 0
            let sameScale = near(Double(ef.width) / 50, Double(es.width) / 30, 1e-6) && eu.scale?.unit == .millimeter && scale > 0
            let readings = eu.connectors.compactMap { c -> String? in
                guard let a = eu.shapes.first(where: { $0.id == c.from }), let b = eu.shapes.first(where: { $0.id == c.to }) else { return nil }
                return ConnectorGeometry.make(c, a, b, scale: eu.scale).measureText
            }
            let dims = readings == ["50 mm", "40 mm", "30 mm", "30 mm"]
            // Each view is one group of its box, lines, hidden lines and name; the isometric hides its dashes unless asked.
            let groups = Dictionary(grouping: eu.shapes.compactMap { s -> (UUID, String)? in s.group.map { ($0, s.name ?? "") } }, by: \.0)
            let isoNoDash = !eu.shapes.contains { $0.name == "Isometric (hidden)" }
            var withIso = MeshViewOptions(); withIso.hiddenInIsometric = true
            let isoDash = MeshDrawing.build(MeshSamples.bracket(), options: withIso).shapes.contains { $0.name == "Isometric (hidden)" }
            var none = MeshViewOptions(); none.hiddenLines = false; none.dimensions = false
            let plain = MeshDrawing.build(MeshSamples.bracket(), options: none)
            let canvas = CanvasView(frame: NSRect(origin: .zero, size: CanvasView.canvasSize))
            canvas.load(eu)
            let inside = eu.contentBounds.map { $0.minX >= 0 && $0.minY >= 0 && $0.maxX < CanvasView.canvasSize.width && $0.maxY < CanvasView.canvasSize.height } ?? false
            let saved = (try? JSONDecoder().decode(Drawing.self, from: JSONEncoder().encode(eu))) == eu
            return european && american && corner && sameScale && dims && groups.count == 4 && groups.values.allSatisfy { $0.count >= 3 }
                && isoNoDash && isoDash && !plain.shapes.contains { $0.name?.hasSuffix("(hidden)") == true } && plain.connectors.isEmpty
                && inside && saved && canvas.pngData()?.isEmpty == false && canvas.svgData().flatMap({ String(data: $0, encoding: .utf8) })?.contains("50 mm") == true
        }))
        steps.append(("stl: the File menu has Import STL as Views…, and a bigger mesh is drawn in reasonable time", {
            let menu = self.makeMainMenu().items.first { $0.title == "File" }?.submenu
            let has = menu?.items.contains { $0.title == "Import STL as Views…" && $0.action == #selector(AppDelegate.importSTL(_:)) } ?? false
            let started = Date()
            let d = MeshDrawing.build(sphere(rings: 60, segments: 90, r: 25), options: MeshViewOptions())
            let seconds = Date().timeIntervalSince(started)
            return has && d.shapes.count >= 8 && seconds < (bundled ? 8 : 40)
        }))
        return steps
    }
}
