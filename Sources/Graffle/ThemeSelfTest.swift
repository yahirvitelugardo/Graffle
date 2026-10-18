import AppKit

/// Self-test steps for themes: the file format, importing, applying, the page, and the New Document window (run with `--selftest`).
extension AppDelegate {
    func themeSteps(cv: CanvasView, drag: @escaping (CGPoint, CGPoint) -> Void, bundled: Bool, tempDir: URL) -> [(String, () -> Bool)] {
        var steps: [(String, () -> Bool)] = []
        let fm = FileManager.default
        let scratch = tempDir.appendingPathComponent("themes")
        let savedFolder = ThemeLibrary.userFolder
        var shapeID = UUID(), textID = UUID()
        let strong = RGBA(0.85, 0.15, 0.2)                          // an outline that carries the color, with a pale fill
        func theme(_ id: String) -> ThemeDefinition { ThemeLibrary.theme(id: id)! }
        func seed() {
            var d = Drawing()
            var box = Shape(layer: d.layers[0].id, kind: .rounded, frame: CGRect(x: 300, y: 300, width: 160, height: 80), text: "A")
            box.style.fill.color = RGBA(0.98, 0.85, 0.86); box.style.stroke.color = strong
            var other = Shape(layer: d.layers[0].id, kind: .rounded, frame: CGRect(x: 540, y: 300, width: 160, height: 80), text: "B")
            other.style.fill.color = RGBA(0.8, 0.9, 1)
            var note = Shape(layer: d.layers[0].id, kind: .text, frame: CGRect(x: 300, y: 440, width: 160, height: 30), style: .textBox, text: "note")
            note.style.text.color = RGBA(0.35, 0.38, 0.45)
            shapeID = box.id; textID = note.id
            d.shapes = [box, other, note]
            d.connectors = [Connector(layer: d.layers[0].id, from: box.id, to: other.id)]
            cv.selection = []
            cv.load(d)
        }
        func box() -> Style { cv.drawing.shapes.first { $0.id == shapeID }!.style }
        func near(_ a: RGBA, _ b: RGBA, _ e: Double = 0.03) -> Bool { abs(a.r - b.r) < e && abs(a.g - b.g) < e && abs(a.b - b.b) < e }
        func pump(_ seconds: Double, until done: () -> Bool = { false }) {
            let end = Date().addingTimeInterval(seconds)
            repeat { RunLoop.main.run(until: Date().addingTimeInterval(0.01)) } while Date() < end && !done()
        }

        steps.append(("themes: the built-in themes are valid, unique and cover the reference looks", {
            let all = BuiltInThemes.all
            let ids = all.map(\.id)
            return all.count == BuiltInThemes.json.count && Set(ids).count == ids.count && all.allSatisfy { $0.problems().isEmpty }
                && ids.first == "clean"
                && Set(["soft-ui", "frost", "midnight", "neumorphic-violet", "aurora-glass", "sky-wireframe", "soft-blue", "marker-doodle",
                        "chalkboard", "green-chalk", "hud-neon", "cyber-cyan", "clay"]).isSubset(of: ids)
        }))
        steps.append(("themes: every theme restyles a drawing, draws, and exports without trouble", {
            for t in BuiltInThemes.all {
                seed()
                cv.applyTheme(t)
                if cv.pngData()?.isEmpty != false || cv.pdfData()?.isEmpty != false || cv.svgData()?.isEmpty != false { return false }
                if t.isClean != (cv.drawing.theme == nil) { return false }
            }
            seed()
            return true
        }))
        steps.append(("themes: a theme file is checked, and every problem is explained", {
            func decode(_ json: String) -> Error? { do { _ = try ThemeDefinition.decode(Data(json.utf8)); return nil } catch { return error } }
            let ok = decode(#"{"id":"mine","name":"Mine"}"#) == nil
            let badColor = decode(#"{"id":"mine","name":"Mine","gridColor":"red"}"#)?.localizedDescription.contains("gridColor") == true
            let badID = decode(#"{"id":"My Theme!","name":"Mine"}"#)?.localizedDescription.contains("id must be") == true
            let several = decode(#"{"id":"mine","name":" ","shape":{"effect":"sparkle","stroke":{"cap":"pointy"}}}"#)?.localizedDescription ?? ""
            let newer = decode(#"{"format":99,"id":"mine","name":"Mine"}"#)?.localizedDescription.contains("format 99") == true
            let garbage = decode("not json")?.localizedDescription.contains("isn't a Graffle theme") == true
            return ok && badColor && badID && several.contains("name is empty") && several.contains("shape.effect") && several.contains("shape.stroke.cap")
                && newer && garbage
        }))
        steps.append(("themes: importing copies a valid file into the library, refuses built-in ids, and ignores damaged files", {
            ThemeLibrary.userFolder = scratch.appendingPathComponent("library")
            try? fm.createDirectory(at: scratch, withIntermediateDirectories: true)
            let mine = scratch.appendingPathComponent("mine.graftheme")
            try? Data(##"{"format":1,"id":"my-theme","name":"My Theme","author":"Me","gridColor":"#10203040","shape":{"stroke":{"color":"#FFCC00"}}}"##.utf8).write(to: mine)
            var notified = false
            let token = NotificationCenter.default.addObserver(forName: .themesChanged, object: nil, queue: nil) { _ in notified = true }
            defer { NotificationCenter.default.removeObserver(token) }
            guard let imported = try? ThemeLibrary.importTheme(from: mine) else { return false }
            let found = ThemeLibrary.theme(id: "my-theme")
            let copied = fm.fileExists(atPath: ThemeLibrary.userFolder.appendingPathComponent("my-theme.graftheme").path)
            // The same id again replaces; a built-in id is refused; a damaged file in the folder is skipped.
            try? Data(#"{"id":"my-theme","name":"My Theme 2"}"#.utf8).write(to: mine)
            _ = try? ThemeLibrary.importTheme(from: mine)
            let replaced = ThemeLibrary.userThemes().filter { $0.id == "my-theme" }.map(\.name) == ["My Theme 2"]
            let clash = scratch.appendingPathComponent("clash.graftheme")
            try? Data(#"{"id":"midnight","name":"Fake"}"#.utf8).write(to: clash)
            var refused = false
            do { _ = try ThemeLibrary.importTheme(from: clash) } catch { refused = error.localizedDescription.contains("comes with Graffle") }
            try? Data("garbage".utf8).write(to: ThemeLibrary.userFolder.appendingPathComponent("broken.graftheme"))
            let tolerant = ThemeLibrary.all.count == BuiltInThemes.all.count + 1
            return imported.id == "my-theme" && found?.name == "My Theme" && copied && notified && replaced && refused && tolerant
        }))
        steps.append(("themes: a theme file round-trips, so users can start from a built-in one", {
            let original = theme("clay")
            let url = scratch.appendingPathComponent("clay-copy.graftheme")
            try? ThemeLibrary.export(original, to: url)
            return (try? ThemeDefinition.decode(Data(contentsOf: url))) == original
        }))
        steps.append(("themes: marker, chalk, glass and neumorphic themes set their own line, fill and effect", {
            seed(); cv.applyTheme(theme("marker-doodle"))
            let m = box()
            let marker = m.stroke.roughness > 0.5 && m.effect == .hatch && m.fill.kind == .solid && cv.drawing.connectors[0].style.stroke.roughness > 0
            seed(); cv.applyTheme(theme("chalkboard"))
            let c = box()
            let chalk = c.fill.kind == .solid && c.fill.color.luminance < 0.3 && c.stroke.roughness > 0 && c.stroke.color.luminance > 0.8
                && c.text.color == RGBA(hex: "#F4F1E8")
            seed(); cv.applyTheme(theme("frost"))
            let g = box()
            let glass = g.effect == .glass && g.fill.color.a < 0.8 && g.shadow.enabled
            seed(); cv.applyTheme(theme("neumorphic-violet"))
            let n = box()
            let neu = n.effect == .neumorphic && !n.stroke.visible
            seed(); cv.applyTheme(theme("clay"))
            let clay = box().effect == .clay && box().fill.kind == .linear
            return marker && chalk && glass && neu && clay
        }))
        steps.append(("themes: an accent pulls shapes toward one hue, and switching themes keeps each shape's own color", {
            seed(); cv.applyTheme(theme("cyber-cyan"))
            let teal = box().stroke.color.g > box().stroke.color.r + 0.3
            for id in ["material", "soft-blue", "marker-doodle", "hud-neon", "clay", "clean"] where ThemeLibrary.theme(id: id) != nil { cv.applyTheme(theme(id)) }
            let back = near(box().fill.color, strong) && box().effect == nil && box().stroke.roughness == 0 && cv.drawing.theme == nil
            return teal && back
        }))
        steps.append(("themes: free text stays dark on the white page, and Clean gives type and colors back", {
            seed(); cv.applyTheme(theme("midnight"))                                   // its lettering is light: right for dark shapes, wrong for loose text
            let note = { cv.drawing.shapes.first { $0.id == textID }! }
            let readable = (note().style.text.color?.luminance ?? 1) < 0.5 && (cv.drawing.connectors[0].style.text.color == nil)
            let shapeText = (box().text.color?.luminance ?? 0) > 0.7                    // while text inside the shapes is light
            // A caption sitting inside a shape takes the shape's lettering, not the page's.
            var d = cv.drawing
            d.shapes.append(Shape(layer: d.layers[0].id, kind: .text, frame: CGRect(x: 320, y: 340, width: 120, height: 24), style: .textBox, text: "caption"))
            ThemeLibrary.theme(id: "chalkboard")!.apply(to: &d)
            let caption = (d.shapes.last?.style.text.color?.luminance ?? 0) > 0.7
            seed(); cv.applyTheme(theme("marker-doodle"))
            let installed = ThemeDefinition.installedFont(from: ["Marker Felt", "Noteworthy", "Chalkboard SE"])
            let hand = installed == nil || note().style.text.font == installed
            cv.applyTheme(theme("clean"))
            return readable && shapeText && caption && hand && note().style.text.color == nil && note().style.text.font == "System" && note().text == "note"
        }))
        steps.append(("themes: applying one is a single undo step, and the drawing keeps the theme in the file", {
            seed()
            let before = cv.drawing
            cv.applyTheme(theme("aurora-glass"))
            let changed = cv.drawing != before && cv.drawing.theme?.id == "aurora-glass"
            guard let data = try? JSONEncoder().encode(cv.drawing), let back = try? JSONDecoder().decode(Drawing.self, from: data) else { return false }
            let embedded = back == cv.drawing && back.theme?.shape?.effect == "glass"                   // works without the theme installed
            cv.undoManager?.undo()
            let undone = cv.drawing == before
            cv.undoManager?.redo()
            let old = try? JSONDecoder().decode(Drawing.self, from: Data(#"{"layers":[],"shapes":[],"connectors":[]}"#.utf8))
            return changed && embedded && undone && cv.drawing.theme?.id == "aurora-glass" && old?.theme == nil
        }))
        steps.append(("themes: new shapes and connectors are drawn in the theme in use", {
            seed(); cv.applyTheme(theme("marker-doodle"))
            let before = cv.drawing.shapes.count
            cv.tool = .shape(.rectangle)
            drag(CGPoint(x: 300, y: 600), CGPoint(x: 440, y: 680))
            guard cv.drawing.shapes.count == before + 1, let made = cv.drawing.shapes.last else { return false }
            return made.style.stroke.roughness > 0 && made.style.effect == .hatch
        }))
        steps.append(("themes: the canvas page is never recolored; a theme may only recolor the grid", {
            seed(); cv.applyTheme(theme("hud-neon"))
            guard let png = cv.pngData(), let rep = NSBitmapImageRep(data: png), let corner = rep.colorAt(x: 2, y: 2)?.usingColorSpace(.sRGB) else { return false }
            let white = corner.redComponent > 0.97 && corner.greenComponent > 0.97 && corner.blueComponent > 0.97
            let bounds = cv.exportBounds() == cv.drawing.contentBounds?.insetBy(dx: -24, dy: -24)       // exports hug the diagram, no growing sheet
            let svg = cv.svgData().flatMap { String(data: $0, encoding: .utf8) } ?? ""
            let svgWhite = svg.contains("fill=\"#ffffff\"/>") && !svg.contains("page-bg")
            let grid = theme("hud-neon").gridColor.flatMap { RGBA(hex: $0) } != nil && theme("clean").gridColor == nil && theme("soft-ui").gridColor == nil
            // Files from before this change still open: their `page` section is ignored.
            let legacy = try? ThemeDefinition.decode(Data(##"{"id":"old","name":"Old","page":{"color":"#000000","frame":{"color":"#8A5A36"}}}"##.utf8))
            let ignored = legacy != nil && !String(decoding: legacy!.encoded(), as: UTF8.self).contains("page")
            seed(); cv.applyTheme(theme("clean"))
            return white && bounds && svgWhite && grid && ignored
        }))
        steps.append(("themes: Quick Look previews draw the theme's page", {
            seed(); cv.applyTheme(theme("hud-neon"))
            let result = DiagramPreview.render(cv.drawing)
            seed(); cv.applyTheme(theme("clean"))
            return !result.isEmpty && result.pdf.count > 500
        }))
        steps.append(("themes: crayon wobble is repeatable and stays near the true outline", {
            let rect = CGPath(rect: CGRect(x: 0, y: 0, width: 200, height: 100), transform: nil)
            let a = Render.roughened(rect, amount: 0.9, seed: 42), b = Render.roughened(rect, amount: 0.9, seed: 42)
            let c = Render.roughened(rect, amount: 0.9, seed: 43)
            let box = a.boundingBoxOfPath
            return a == b && a != c && box.minX > -4 && box.maxX < 204 && box.minY > -4 && box.maxY < 104 && box.width > 195
        }))
        steps.append(("themes: the New Document wizard goes from the gallery of diagrams to the themes, with a picture of each", {
            // Confirming remembers the choice; a test mustn't change what the real app opens with.
            let defaults = UserDefaults.standard
            let saved = ["newDocument.template", "newDocument.theme"].map { ($0, defaults.object(forKey: $0)) }
            defer { for (key, value) in saved { if let value { defaults.set(value, forKey: key) } else { defaults.removeObject(forKey: key) } } }
            var chosen: NewDocumentController.Choice?
            let window = NewDocumentController.presentNewDocument { chosen = $0 }
            let first = window.step == .template && window.templatesShown && !window.themesShown && window.primaryTitle == "Choose"
                && !window.backButtonShown && window.headingText == "Start a New Diagram"
            pump(3) { window.templatePreviewCount == DocumentTemplate.all.count - 1 }
            let galleryPictures = window.templatePreviewCount == DocumentTemplate.all.count - 1                           // blank is a white page; the other two have pictures
            window.select(template: DocumentTemplate.all[1])
            window.confirm()                                                                 // Choose: on to the themes, in the same window
            let ids = window.themeIDs
            let second = window.step == .theme && window.themesShown && !window.templatesShown && window.primaryTitle == "Create"
                && window.backButtonShown && window.headingText == "Choose a Theme" && chosen == nil
            pump(3) { window.themePreviewCount == ids.count }
            let pictures = window.themePreviewCount == ids.count && ids.count == ThemeLibrary.all.count
            window.goBack()
            let wentBack = window.step == .template && window.template.kind == .architecture
            window.confirm()
            window.select(theme: "chalkboard")
            window.confirm()
            let picked = chosen?.theme.id == "chalkboard" && chosen?.template.kind == .architecture
            let again = NewDocumentController.presentNewDocument { _ in }                     // the first one closed, so this is a fresh window
            let fresh = again !== window && again.step == .template && again.template.kind == .architecture    // remembering the last kind
            again.dismiss()
            return first && galleryPictures && second && ids.contains("clay") && pictures && wentBack && picked && fresh
                && Array(DocumentTemplate.all.prefix(3).map(\.kind)) == [.blank, .architecture, .classes]
                && DocumentTemplate.all.map(\.title) == ["Blank Diagram", "Software Architecture Diagram", "Classes Diagram", "UML Diagram", "Entity-Relationship Diagram",
                    "Conceptual Diagram", "Synoptic Diagram", "Pyramid Diagram", "Ishikawa Diagram", "Tree Diagram"]
        }))
        steps.append(("themes: an imported theme shows up in an open New Document window", {
            let window = NewDocumentController.presentNewDocument { _ in }
            let before = window.themeIDs.count
            let file = scratch.appendingPathComponent("late.graftheme")
            try? Data(#"{"id":"late-theme","name":"Late Theme","author":"Tester"}"#.utf8).write(to: file)
            _ = try? ThemeLibrary.importTheme(from: file)
            let added = window.themeIDs.count == before + 1 && window.themeIDs.contains("late-theme")
            window.dismiss()
            return added
        }))
        steps.append(("themes: launch and Dock behaviour go through the New Document window", {
            self.applicationShouldOpenUntitledFile(NSApp) == false
        }))
        steps.append(("themes: creating a blank document from the window opens it with the theme (and no stale undo)", {
            guard bundled else { print("      (skipped: needs the .app bundle)"); return true }
            let before = NSDocumentController.shared.documents.count
            self.createDocument(.init(template: DocumentTemplate.all[0], theme: theme("midnight")))
            let docs = NSDocumentController.shared.documents.compactMap { $0 as? GraffleDocument }
            guard NSDocumentController.shared.documents.count == before + 1, let doc = docs.last, let canvas = doc.canvas else { return false }
            let themed = canvas.drawing.theme?.id == "midnight" && canvas.drawing.shapes.isEmpty && !doc.isDocumentEdited && doc.fileURL == nil
            doc.close()
            return themed
        }))
        steps.append(("themes: the test library folder is put back", {
            ThemeLibrary.userFolder = savedFolder
            try? fm.removeItem(at: scratch)
            return ThemeLibrary.userThemes().allSatisfy { $0.id != "my-theme" && $0.id != "late-theme" } || savedFolder.path.contains("Application Support")
        }))
        return steps
    }
}
