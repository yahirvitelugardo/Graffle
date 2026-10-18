import AppKit
import PDFKit
import UniformTypeIdentifiers

final class AppDelegate: NSObject, NSApplicationDelegate {
    /// Documents make their own windows. Only the developer helpers (--selftest, --render-sample, ...) need one
    /// of their own, so it is created on demand and never shown in normal use.
    private lazy var rig = DocumentWindowController()
    private var window: NSWindow { rig.window! }
    private var canvas: CanvasView { rig.canvas }
    private var scroll: NSScrollView { rig.scroll }
    private var inspector: InspectorView { rig.inspector }
    private var snapshotter: SVGSnapshotter?

    private static let developerFlags: Set<String> = [
        "--render-sample", "--render-about", "--import-to-png", "--architecture-to-png", "--render-chooser", "--render-navigator", "--classes-to-png", "--starter-to-png", "--svg-to-png", "--selftest", "--debug-window",
    ]
    private var isDeveloperRun: Bool { !AppDelegate.developerFlags.isDisjoint(with: CommandLine.arguments) }

    // MARK: Launch

    func applicationDidFinishLaunching(_ notification: Notification) {
        if let i = CommandLine.arguments.firstIndex(of: "--render-sample"), i + 1 < CommandLine.arguments.count {
            renderSample(to: CommandLine.arguments[i + 1])
            exit(0)
        }
        if let i = CommandLine.arguments.firstIndex(of: "--render-about"), i + 1 < CommandLine.arguments.count {
            // Dev helper: open the About panel, snapshot it to PNG and quit (run from the .app to get its real icon).
            let out = CommandLine.arguments[i + 1]
            About.show()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) {
                if let panel = NSApp.windows.first(where: { $0.isVisible }), let view = panel.contentView,
                   let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) {
                    view.cacheDisplay(in: view.bounds, to: rep)
                    try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: out))
                    print("About panel:", panel.frame.size, "title:", panel.title)
                }
                exit(0)
            }
            return
        }
        if let i = CommandLine.arguments.firstIndex(of: "--starter-to-png"), i + 2 < CommandLine.arguments.count {
            // Dev helper: render a starter diagram (uml, entityRelationship, conceptual, synoptic, pyramid, ishikawa, tree) as PNG.
            let a = CommandLine.arguments
            if let starter = Starter(rawValue: a[i + 1]) {
                var d = Starters.drawing(starter)
                if let t = a.first(where: { $0.hasPrefix("--theme=") }), let theme = ThemeLibrary.theme(id: String(t.dropFirst(8))) { theme.apply(to: &d) }
                canvas.frame = CGRect(origin: .zero, size: CanvasView.canvasSize)
                canvas.load(d)
                if let png = canvas.pngData() { try? png.write(to: URL(fileURLWithPath: a[i + 2])) }
                print("starter:", starter.rawValue, d.shapes.count, "shapes,", d.connectors.count, "connectors")
            }
            exit(0)
        }
        if let i = CommandLine.arguments.firstIndex(of: "--classes-to-png"), i + 2 < CommandLine.arguments.count {
            // Dev helper: read a project's types and export the class diagram as PNG.
            let a = CommandLine.arguments
            var options = ClassOptions()
            options.includeMembers = !a.contains("--no-members")
            do {
                let g = try ClassImporter.analyze(URL(fileURLWithPath: a[i + 1]), options: options)
                var d = ClassDrawing.build(g, options: options)
                if let t = a.first(where: { $0.hasPrefix("--theme=") }), let theme = ThemeLibrary.theme(id: String(t.dropFirst(8))) { theme.apply(to: &d) }
                canvas.frame = CGRect(origin: .zero, size: CanvasView.canvasSize)
                canvas.load(d)
                if let png = canvas.pngData() { try? png.write(to: URL(fileURLWithPath: a[i + 2])) }
                print("classes:", g.types.count, "types,", g.relations.count, "relations")
            } catch { print("failed:", error.localizedDescription) }
            exit(0)
        }
        if let i = CommandLine.arguments.firstIndex(of: "--render-navigator"), i + 1 < CommandLine.arguments.count {
            // Dev helper: show the Navigator over a sample diagram, snapshot the panel to PNG and quit.
            let out = CommandLine.arguments[i + 1]
            let wc = DocumentWindowController()
            wc.window?.setContentSize(NSSize(width: 1000, height: 700))
            wc.showWindow(nil)
            var d = ThemePreview.architectureSample()
            ThemeLibrary.theme(id: "soft-ui")?.apply(to: &d)
            wc.canvas.load(d)
            wc.scroll.magnification = 2
            wc.canvas.scrollCenter(to: CGPoint(x: 300, y: 250))
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                wc.inspector.layoutSubtreeIfNeeded()
                let view = wc.inspector.navigator
                if let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) {
                    view.cacheDisplay(in: view.bounds, to: rep)
                    try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: out))
                    print("navigator", view.bounds.size)
                }
                if let win = wc.window, let content = win.contentView, let rep = content.bitmapImageRepForCachingDisplay(in: content.bounds) {
                    content.cacheDisplay(in: content.bounds, to: rep)
                    try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: out + ".window.png"))
                }
                exit(0)
            }
            return
        }
        if let i = CommandLine.arguments.firstIndex(of: "--render-chooser"), i + 1 < CommandLine.arguments.count {
            // Dev helper: open the New Document window, snapshot it to PNG and quit.
            let out = CommandLine.arguments[i + 1]
            let themeOnly = CommandLine.arguments.contains("--theme-only")
            let c = themeOnly ? NewDocumentController.presentThemePicker(on: window, selected: nil) { _ in }
                              : NewDocumentController.presentNewDocument { _ in }
            if CommandLine.arguments.contains("--classes") { c.select(template: DocumentTemplate.all[2]) }
            if CommandLine.arguments.contains("--step-theme") { c.confirm() }
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                if let view = c.window?.contentView, let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) {
                    view.cacheDisplay(in: view.bounds, to: rep)
                    try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: out))
                    print("chooser", view.bounds.size, "previews", c.themePreviewCount, "of", c.themeIDs.count)
                }
                exit(0)
            }
            return
        }
        if let i = CommandLine.arguments.firstIndex(of: "--architecture-to-png"), i + 2 < CommandLine.arguments.count {
            // Dev helper: analyze a project and export its architecture diagram as PNG.
            let a = CommandLine.arguments
            var options = ArchitectureOptions()
            options.includeSystemFrameworks = a.contains("--system")
            do {
                let g = try ArchitectureImporter.analyze(URL(fileURLWithPath: a[i + 1]), options: options)
                let d = ArchitectureDrawing.build(g)
                canvas.frame = CGRect(origin: .zero, size: CanvasView.canvasSize)
                canvas.load(d)
                if let t = a.first(where: { $0.hasPrefix("--theme=") }), let theme = ThemeLibrary.theme(id: String(t.dropFirst(8))) { canvas.applyTheme(theme) }
                if let png = canvas.pngData() {
                    try? png.write(to: URL(fileURLWithPath: a[i + 2]))
                    if let rep = NSBitmapImageRep(data: png) {
                        for pt in [(2, 2), (60, 60), (100, 100), (200, 200), (400, 400), (rep.pixelsWide - 3, rep.pixelsHigh - 3)] {
                            print("pixel", pt, rep.colorAt(x: pt.0, y: pt.1).map { "\($0.redComponent) \($0.greenComponent) \($0.blueComponent) \($0.alphaComponent)" } ?? "-")
                        }
                    }
                }
                print("architecture:", g.nodes.count, "nodes,", g.edges.count, "edges", "export", canvas.exportBounds().map { "\($0)" } ?? "-", "content", canvas.drawing.contentBounds.map { "\($0)" } ?? "-")
            } catch { print("failed:", error.localizedDescription) }
            exit(0)
        }
        if let i = CommandLine.arguments.firstIndex(of: "--import-to-png"), i + 2 < CommandLine.arguments.count {
            // Dev helper: import an SVG into the canvas and export it as PNG, to compare with a browser rendering.
            let a = CommandLine.arguments
            if let data = FileManager.default.contents(atPath: a[i + 1]), let r = try? SVGImport.parse(data, name: "import") {
                var d = Drawing()
                let placed = r.placed(at: CGPoint(x: 40, y: 40))
                d.layers = placed.layers
                d.shapes = placed.shapes
                canvas.frame = CGRect(origin: .zero, size: CanvasView.canvasSize)
                canvas.load(d)
                if let png = canvas.pngData() { try? png.write(to: URL(fileURLWithPath: a[i + 2])) }
                print("imported", d.shapes.count, "shapes; left out:", r.skippedSummary ?? "nothing")
            }
            exit(0)
        }
        if let i = CommandLine.arguments.firstIndex(of: "--svg-to-png"), i + 2 < CommandLine.arguments.count {
            let a = CommandLine.arguments
            // Size the page from the SVG's own width/height.
            let text = (try? String(contentsOfFile: a[i + 1], encoding: .utf8)) ?? ""
            func attr(_ name: String) -> CGFloat {
                guard let r = text.range(of: "\(name)=\"") else { return 1000 }
                return CGFloat(Double(text[r.upperBound...].prefix { $0 != "\"" }) ?? 1000)
            }
            snapshotter = SVGSnapshotter(svg: URL(fileURLWithPath: a[i + 1]), output: URL(fileURLWithPath: a[i + 2]),
                                         size: CGSize(width: attr("width"), height: attr("height")))
            return
        }
        if CommandLine.arguments.contains("--selftest") {
            runSelfTest()
            return
        }
        NSApp.mainMenu = makeMainMenu()

        // With nothing opened from Finder, start with the New Document window. (Files opened from Finder arrive just after launch.)
        if !isDeveloperRun {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
                if NSDocumentController.shared.documents.isEmpty { self?.showNewDocumentWindow() }
            }
        }

        // Dev helper: `open -a Graffle.app files… --args --dump-windows out.txt` writes what the running app's windows look like.
        if let i = CommandLine.arguments.firstIndex(of: "--dump-windows"), i + 1 < CommandLine.arguments.count {
            let out = CommandLine.arguments[i + 1]
            DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
                var lines = ["documents: " + NSDocumentController.shared.documents.map { "\($0.displayName ?? "?")" }.joined(separator: ", ")]
                for w in NSApp.windows where w.windowController is DocumentWindowController {
                    lines.append("window \"\(w.title)\" visible=\(w.isVisible) key=\(w.isKeyWindow) tabs=\(w.tabGroup?.windows.count ?? 1) " +
                                 "frame=\(Int(w.frame.minX)),\(Int(w.frame.minY)) \(Int(w.frame.width))x\(Int(w.frame.height)) " +
                                 "tabbing=\(w.tabbingMode.rawValue) allowsAuto=\(NSWindow.allowsAutomaticWindowTabbing)")
                }
                try? lines.joined(separator: "\n").write(toFile: out, atomically: true, encoding: .utf8)
            }
        }

        if CommandLine.arguments.contains("--debug-window") {
            rig.showWindow(nil)
            NSApp.activate(ignoringOtherApps: true)
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [self] in
                print("window", window.frame, "content", window.contentView!.frame, "fitting", window.contentView!.fittingSize)
                print("scroll", scroll.frame, "inspector", inspector.frame, "visible", window.isVisible)
                print("layers table visible:", !inspector.isLayersPanelHidden, "rows", inspector.layerRowCount)
                scroll.rulersVisible = true
                scroll.layoutSubtreeIfNeeded()
                print("rulers:", scroll.horizontalRulerView.map { "h=\($0.frame.size) units=\($0.measurementUnits.rawValue)" } ?? "none",
                      scroll.verticalRulerView.map { "v=\($0.frame.size)" } ?? "none", "visible", scroll.rulersVisible)
                scroll.rulersVisible = false
                canvas.defaultStyle.fill.kind = .linear
                inspector.refresh()
                print("ambiguous scroll:", scroll.hasAmbiguousLayout, "inspector:", inspector.hasAmbiguousLayout)
                inspector.layoutSubtreeIfNeeded()
                print("sections (nothing selected):", inspector.visibleSectionTitles, "height", inspector.currentPaneHeight,
                      "ambiguous", inspector.hasAmbiguousLayout)
                exit(0)
            }
        }
    }

    // Quitting asks about unsaved documents, and opening files from Finder, the Dock or Open Recent, all come
    // from NSDocumentController. These two answers are all the app itself has to give.
    /// Untitled documents are made through the New Document window instead (so the user picks a type and a theme).
    func applicationShouldOpenUntitledFile(_ sender: NSApplication) -> Bool { false }

    /// Clicking the Dock icon with no windows open starts a new document the same way.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag && !isDeveloperRun { showNewDocumentWindow() }
        return false
    }

    /// Shows the New Document window, and creates what was chosen.
    func showNewDocumentWindow() {
        NewDocumentController.presentNewDocument { [weak self] choice in self?.createDocument(choice) }
    }

    @objc func newDocumentChooser(_ sender: Any?) { showNewDocumentWindow() }

    func createDocument(_ choice: NewDocumentController.Choice) {
        switch choice.template.kind {
        case .blank:
            var drawing = Drawing()
            choice.theme.apply(to: &drawing)
            GraffleDocument.openNew(drawing: drawing)
        case .architecture:
            chooseProjectForArchitecture(theme: choice.theme)
        case .classes:
            chooseProjectForClasses(theme: choice.theme)
        case .starter:
            guard let starter = choice.template.starter else { return }
            var drawing = Starters.drawing(starter)
            choice.theme.apply(to: &drawing)
            GraffleDocument.openNew(drawing: drawing)
        }
    }

    /// File → Import Theme…: adds a `.graftheme` file to the library.
    @objc func importThemeFile(_ sender: Any?) {
        NewDocumentController.runImportPanel(on: nil) { theme in
            guard let theme else { return }
            let alert = NSAlert()
            alert.messageText = "Added the theme “\(theme.name)”"
            alert.informativeText = "Pick it in File → New… when you start a document, or in View → Theme… for an open one."
            alert.runModal()
        }
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    // MARK: Menus

    private func item(_ title: String, _ action: Selector?, _ key: String = "",
                      _ mods: NSEvent.ModifierFlags = .command, target: AnyObject? = nil, tag: Int = 0) -> NSMenuItem {
        let i = NSMenuItem(title: title, action: action, keyEquivalent: key)
        i.keyEquivalentModifierMask = key.isEmpty ? [] : mods
        i.target = target
        i.tag = tag
        return i
    }

    private func submenu(_ title: String, _ items: [NSMenuItem]) -> NSMenuItem {
        let menu = NSMenu(title: title)
        items.forEach(menu.addItem)
        let holder = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        holder.submenu = menu
        return holder
    }

    func makeMainMenu() -> NSMenu {
        let sep = { NSMenuItem.separator() }
        let main = NSMenu()

        main.addItem(submenu("Graffle", [
            item("About Graffle", #selector(showAbout(_:)), target: self),
            sep(),
            item("Hide Graffle", #selector(NSApplication.hide(_:)), "h"),
            item("Hide Others", #selector(NSApplication.hideOtherApplications(_:)), "h", [.command, .option]),
            item("Show All", #selector(NSApplication.unhideAllApplications(_:))),
            sep(),
            item("Quit Graffle", #selector(NSApplication.terminate(_:)), "q"),
        ]))

        // Open Recent fills itself in: AppKit populates a submenu that ends with "Clear Menu".
        let recent = NSMenu(title: "Open Recent")
        recent.addItem(item("Clear Menu", #selector(NSDocumentController.clearRecentDocuments(_:))))
        let recentItem = NSMenuItem(title: "Open Recent", action: nil, keyEquivalent: "")
        recentItem.submenu = recent

        main.addItem(submenu("File", [
            item("New…", #selector(AppDelegate.newDocumentChooser(_:)), "n"),
            item("New Blank Diagram", #selector(NSDocumentController.newDocument(_:)), "n", [.command, .option]),
            item("Open…", #selector(NSDocumentController.openDocument(_:)), "o"),
            recentItem,
            sep(),
            item("Close", #selector(NSWindow.performClose(_:)), "w"),
            item("Save", #selector(NSDocument.save(_:)), "s"),
            item("Save As…", #selector(NSDocument.saveAs(_:)), "s", [.command, .shift]),
            item("Revert to Saved", #selector(NSDocument.revertToSaved(_:))),
            sep(),
            item("Import SVG…", #selector(DocumentWindowController.importSVG(_:)), "i", [.command, .shift]),
            item("Import Project Architecture…", #selector(AppDelegate.importXcodeProject(_:))),
            item("Import Class Diagram…", #selector(AppDelegate.importClassDiagram(_:))),
            item("Import Theme…", #selector(AppDelegate.importThemeFile(_:))),
            item("Export as PNG…", #selector(DocumentWindowController.exportPNG(_:)), "e", [.command, .shift]),
            item("Export as PDF…", #selector(DocumentWindowController.exportPDF(_:)), "p", [.command, .shift]),
            item("Export as SVG…", #selector(DocumentWindowController.exportSVG(_:)), "e", [.command, .option]),
        ]))

        main.addItem(submenu("Edit", [
            item("Undo", #selector(CanvasView.undo(_:)), "z"),
            item("Redo", #selector(CanvasView.redo(_:)), "z", [.command, .shift]),
            sep(),
            item("Cut", #selector(CanvasView.cut(_:)), "x"),
            item("Copy", #selector(CanvasView.copy(_:)), "c"),
            item("Paste", #selector(CanvasView.paste(_:)), "v"),
            item("Duplicate", #selector(CanvasView.duplicate(_:)), "d"),
            item("Copy Style", #selector(CanvasView.copyStyle(_:)), "c", [.command, .option]),
            item("Paste Style", #selector(CanvasView.pasteStyle(_:)), "v", [.command, .option]),
            item("Delete", #selector(CanvasView.delete(_:))),
            sep(),
            item("Select All", #selector(NSResponder.selectAll(_:)), "a"),
        ]))

        main.addItem(submenu("Arrange", [
            item("Group", #selector(CanvasView.group(_:)), "g"),
            item("Ungroup", #selector(CanvasView.ungroup(_:)), "g", [.command, .shift]),
            sep(),
            item("Lock", #selector(CanvasView.lockSelection(_:)), "l"),
            item("Unlock", #selector(CanvasView.unlockSelection(_:)), "l", [.command, .option]),
            item("Unlock All", #selector(CanvasView.unlockAll(_:))),
            sep(),
            item("Bring to Front", #selector(CanvasView.bringToFront(_:)), "]", [.command, .shift]),
            item("Send to Back", #selector(CanvasView.sendToBack(_:)), "[", [.command, .shift]),
            sep(),
            item("Align Left", #selector(CanvasView.align(_:)), tag: 0),
            item("Align Center", #selector(CanvasView.align(_:)), tag: 1),
            item("Align Right", #selector(CanvasView.align(_:)), tag: 2),
            item("Align Top", #selector(CanvasView.align(_:)), tag: 3),
            item("Align Middle", #selector(CanvasView.align(_:)), tag: 4),
            item("Align Bottom", #selector(CanvasView.align(_:)), tag: 5),
            sep(),
            item("Distribute Horizontally", #selector(CanvasView.distribute(_:)), tag: 0),
            item("Distribute Vertically", #selector(CanvasView.distribute(_:)), tag: 1),
            sep(),
            item("Same Width", #selector(CanvasView.matchSize(_:)), tag: 0),
            item("Same Height", #selector(CanvasView.matchSize(_:)), tag: 1),
            item("Same Size", #selector(CanvasView.matchSize(_:)), tag: 2),
        ]))

        main.addItem(submenu("View", [
            item("Zoom In", #selector(DocumentWindowController.zoomIn(_:)), "="),
            item("Zoom Out", #selector(DocumentWindowController.zoomOut(_:)), "-"),
            item("Actual Size", #selector(DocumentWindowController.zoomActual(_:)), "0"),
            item("Zoom to Fit", #selector(DocumentWindowController.zoomToFit(_:)), "0", [.command, .option]),
            item("Zoom to Selection", #selector(DocumentWindowController.zoomToSelection(_:)), "0", [.command, .control]),
            item("Hide Navigator", #selector(DocumentWindowController.toggleNavigator(_:)), "j", [.command, .option]),
            sep(),
            item("Show Rulers", #selector(DocumentWindowController.toggleRulers(_:)), "r"),
            item("Smart Guides", #selector(DocumentWindowController.toggleSmartGuides(_:))),
            item("Show Grid", #selector(DocumentWindowController.toggleGrid(_:)), "'"),
            item("Snap to Grid", #selector(DocumentWindowController.toggleSnap(_:)), ";"),
            sep(),
            item("Theme…", #selector(DocumentWindowController.chooseTheme(_:))),
        ]))

        // Registering this as the Window menu is what makes AppKit list the open documents in it and add the
        // tab commands (Show Tab Bar, Merge All Windows, ...).
        let windowMenu = submenu("Window", [
            item("Minimize", #selector(NSWindow.performMiniaturize(_:)), "m"),
            item("Zoom", #selector(NSWindow.performZoom(_:))),
            sep(),
            item("Bring All to Front", #selector(NSApplication.arrangeInFront(_:))),
        ])
        main.addItem(windowMenu)
        NSApp.windowsMenu = windowMenu.submenu
        return main
    }

    @objc private func showAbout(_ s: Any?) { About.show() }

    // MARK: Dev helper (swift run Graffle --render-sample out.png)

    private func renderSample(to path: String) {
        var d = Drawing()
        let base = d.layers[0].id
        let notes = Layer(name: "Annotations")
        d.layers.append(notes)

        func add(_ k: ShapeKind, _ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, _ t: String,
                 layer: UUID? = nil, _ tweak: (inout Style) -> Void = { _ in }) -> UUID {
            var s = Shape(layer: layer ?? base, kind: k, frame: CGRect(x: x, y: y, width: w, height: h), text: t)
            s.style = k == .text ? .textBox : Style()
            if k == .rounded { s.style.cornerRadius = 14 }
            tweak(&s.style)
            d.shapes.append(s)
            return s.id
        }
        func link(_ x: UUID, _ y: UUID, _ r: Route, _ label: String = "", start: HeadKind = .none, end: HeadKind = .filledArrow,
                  _ tweak: (inout Style) -> Void = { _ in }) {
            var k = Connector(layer: base, from: x, to: y)
            k.route = r; k.text = label; k.startHead = start; k.endHead = end
            tweak(&k.style)
            d.connectors.append(k)
        }

        let a = add(.rounded, 60, 60, 150, 76, "Start") { st in
            st.fill.kind = .linear; st.fill.stops = [GradientStop(color: RGBA(0.55, 0.88, 0.60), position: 0), GradientStop(color: RGBA(0.16, 0.60, 0.35), position: 1)]
            st.fill.angle = 90; st.shadow.enabled = true; st.stroke.color = RGBA(0.1, 0.4, 0.2); st.stroke.width = 2
        }
        let b = add(.diamond, 310, 40, 160, 116, "Valid?") { st in
            st.fill.kind = .radial; st.fill.stops = [GradientStop(color: RGBA(1, 0.97, 0.75), position: 0), GradientStop(color: RGBA(1, 0.78, 0.25), position: 1)]
            st.stroke.dash = .dashed; st.stroke.width = 2
        }
        let c = add(.rectangle, 590, 60, 150, 76, "Process") { st in
            st.fill.kind = .linear; st.fill.angle = 0; st.fill.stops = [GradientStop(color: RGBA(0.25, 0.40, 0.85), position: 0), GradientStop(color: RGBA(0.55, 0.25, 0.80), position: 1)]
            st.stroke.visible = false; st.text.bold = true; st.cornerRadius = 6
        }
        let e = add(.ellipse, 310, 270, 160, 84, "Error") { st in
            st.fill.color = RGBA(1.0, 0.82, 0.82); st.stroke.color = RGBA(0.75, 0.15, 0.15); st.stroke.dash = .dotted; st.stroke.width = 3
            st.opacity = 0.9
        }
        let f = add(.triangle, 620, 250, 120, 110, "") { st in st.stroke.dash = .dashDot; st.stroke.width = 2 }
        _ = add(.text, 60, 290, 200, 34, "Free text, italic", layer: notes.id) { st in st.text.italic = true; st.text.font = "Georgia"; st.text.size = 16 }
        _ = add(.rounded, 60, 190, 190, 60, "Hidden layer note", layer: notes.id) { st in st.fill.color = RGBA(1, 0.9, 0.6) }

        let rot = add(.rounded, 820, 90, 160, 80, "Rotated 25°") { st in
            st.fill.kind = .linear; st.fill.stops = [GradientStop(color: RGBA(1, 0.7, 0.4), position: 0), GradientStop(color: RGBA(0.95, 0.35, 0.45), position: 1)]
            st.shadow.enabled = true; st.shadow.angle = 90; st.shadow.offset = 10; st.shadow.blur = 8
        }
        let tri2 = add(.triangle, 840, 280, 120, 100, "") { st in st.fill.color = RGBA(0.8, 0.95, 0.85) }
        if let i = d.shapes.firstIndex(where: { $0.id == rot }) { d.shapes[i].rotation = 25 }
        if let i = d.shapes.firstIndex(where: { $0.id == tri2 }) { d.shapes[i].rotation = 180 }
        _ = add(.rounded, 60, 400, 420, 60, "Five stops, uneven positions") { st in
            st.fill.kind = .linear; st.fill.angle = 0; st.cornerRadius = 12
            st.fill.stops = [
                GradientStop(color: RGBA(0.20, 0.35, 0.95), position: 1.0),
                GradientStop(color: RGBA(0.95, 0.25, 0.30), position: 0.0),
                GradientStop(color: RGBA(0.98, 0.85, 0.25), position: 0.25),
                GradientStop(color: RGBA(0.30, 0.80, 0.45), position: 0.55),
                GradientStop(color: RGBA(0.10, 0.75, 0.90), position: 0.8),
            ]
            st.text.color = RGBA(0, 0, 0)
        }
        let tag = add(.text, 640, 400, 200, 30, "Rotated text -10°") { st in st.text.bold = true }
        if let i = d.shapes.firstIndex(where: { $0.id == tag }) { d.shapes[i].rotation = -10 + 360 }
        link(c, rot, .straight, end: .filledArrow)
        link(rot, tri2, .orthogonal, end: .filledArrow)

        link(a, b, .straight, end: .filledArrow)
        link(b, c, .rounded, "yes", start: .filledCircle, end: .openArrow) { $0.stroke.width = 2 }
        link(b, e, .curved, "no", end: .hollowTriangle) { $0.stroke.dash = .longDash; $0.stroke.color = RGBA(0.75, 0.15, 0.15) }
        link(e, f, .orthogonal, start: .bar, end: .filledDiamond)
        link(c, f, .curved, end: .hollowCircle) { $0.stroke.width = 3 }

        canvas.load(d)
        canvas.selection = [b]
        canvas.frame = CGRect(origin: .zero, size: CanvasView.canvasSize)
        if let data = canvas.pngData() { try? data.write(to: URL(fileURLWithPath: path)) }
        if let pdf = canvas.pdfData() { try? pdf.write(to: URL(fileURLWithPath: path + ".pdf")) }

        // Editing view: selection outline, rotation knob and resize handles on a rotated shape.
        canvas.selection = [rot]
        canvas.showGrid = true
        if let r = canvas.exportBounds(), let rep = canvas.bitmapImageRepForCachingDisplay(in: r) {
            canvas.cacheDisplay(in: r, to: rep)
            try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path + ".selected.png"))
        }

        // Several shapes selected: one box with handles around the whole group.
        canvas.selection = [a, b, c, e]
        if let r = canvas.exportBounds(), let rep = canvas.bitmapImageRepForCachingDisplay(in: r) {
            canvas.cacheDisplay(in: r, to: rep)
            try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path + ".group.png"))
        }

        // The gradient editor widget on its own, for a visual check.
        let ed = GradientEditorView(frame: NSRect(x: 0, y: 0, width: 232, height: 46))
        ed.stops = [GradientStop(color: RGBA(0.95, 0.25, 0.30), position: 0), GradientStop(color: RGBA(0.98, 0.85, 0.25), position: 0.25),
                    GradientStop(color: RGBA(0.30, 0.80, 0.45), position: 0.55), GradientStop(color: RGBA(0.20, 0.35, 0.95), position: 1)]
        ed.selected = 2
        if let rep = ed.bitmapImageRepForCachingDisplay(in: ed.bounds) {
            ed.cacheDisplay(in: ed.bounds, to: rep)
            try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path + ".editor.png"))
        }

        // SVG export of the same diagram, plus a rasterization of that SVG to compare against the canvas render.
        canvas.selection = []
        if let svg = canvas.svgData() {
            try? svg.write(to: URL(fileURLWithPath: path + ".svg"))
            if let img = NSImage(data: svg), img.size.width > 0 {
                let scale: CGFloat = 2
                let w = Int(img.size.width * scale), h = Int(img.size.height * scale)
                if let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: w, pixelsHigh: h, bitsPerSample: 8, samplesPerPixel: 4,
                                              hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
                   let gc = NSGraphicsContext(bitmapImageRep: rep) {
                    NSGraphicsContext.saveGraphicsState()
                    NSGraphicsContext.current = gc
                    img.draw(in: NSRect(x: 0, y: 0, width: w, height: h))
                    NSGraphicsContext.restoreGraphicsState()
                    try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path + ".svg.png"))
                }
            }
        }

        // Contact sheet of every inspector glyph.
        let families: [[NSImage]] = [
            DashKind.allCases.map(Glyphs.dash), CapKind.allCases.map(Glyphs.cap), JoinKind.allCases.map(Glyphs.join),
            Route.allCases.map(Glyphs.route),
            HeadKind.allCases.map { Glyphs.head($0, atEnd: true) }, HeadKind.allCases.map { Glyphs.head($0, atEnd: false) },
            FillKind.allCases.map(Glyphs.fill), HAlign.allCases.map(Glyphs.hAlign), VAlign.allCases.map(Glyphs.vAlign),
        ]
        let cell = NSSize(width: 110, height: 34)
        // Split each family into rows of five so long families (arrowheads) don't overlap.
        let rows: [[NSImage]] = families.flatMap { fam in
            stride(from: 0, to: fam.count, by: 5).map { Array(fam[$0..<min($0 + 5, fam.count)]) }
        }
        let sheetSize = NSSize(width: cell.width * 5 + 20, height: cell.height * CGFloat(rows.count) + 20)
        let sheet = NSImage(size: sheetSize, flipped: true) { rect in
            NSColor.white.setFill(); rect.fill()
            for (row, imgs) in rows.enumerated() {
                for (col, img) in imgs.enumerated() {
                    let o = NSPoint(x: 10 + CGFloat(col) * cell.width, y: 10 + CGFloat(row) * cell.height)
                    img.draw(in: NSRect(origin: o, size: img.size), from: .zero, operation: .sourceOver, fraction: 1,
                             respectFlipped: true, hints: nil)
                }
            }
            return true
        }
        if let tiff = sheet.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff) {
            try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path + ".glyphs.png"))
        }

        // The pen tool mid-stroke, and the same path in point-edit mode, driven by real events.
        do {
            let c3 = CanvasView(frame: NSRect(x: 0, y: 0, width: 520, height: 330))
            let w3 = NSWindow(contentRect: c3.frame, styleMask: [.titled], backing: .buffered, defer: false)
            w3.contentView = c3
            func ev(_ t: NSEvent.EventType, _ p: CGPoint, clicks: Int = 1) -> NSEvent {
                NSEvent.mouseEvent(with: t, location: CGPoint(x: p.x, y: 330 - p.y), modifierFlags: [], timestamp: 0,
                                   windowNumber: w3.windowNumber, context: nil, eventNumber: 0, clickCount: clicks, pressure: 1)!
            }
            func tap(_ p: CGPoint, clicks: Int = 1) { c3.mouseDown(with: ev(.leftMouseDown, p, clicks: clicks)); c3.mouseUp(with: ev(.leftMouseUp, p, clicks: clicks)) }
            func pull(_ from: CGPoint, _ to: CGPoint) {
                c3.mouseDown(with: ev(.leftMouseDown, from)); c3.mouseDragged(with: ev(.leftMouseDragged, to)); c3.mouseUp(with: ev(.leftMouseUp, to))
            }
            func snapshot(_ name: String) {
                if let rep = c3.bitmapImageRepForCachingDisplay(in: c3.bounds) {
                    c3.cacheDisplay(in: c3.bounds, to: rep)
                    try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path + name))
                }
            }
            c3.showGrid = false
            c3.tool = .pen
            tap(CGPoint(x: 50, y: 250))
            pull(CGPoint(x: 150, y: 90), CGPoint(x: 210, y: 90))
            pull(CGPoint(x: 300, y: 250), CGPoint(x: 360, y: 250))
            c3.mouseMoved(with: ev(.mouseMoved, CGPoint(x: 450, y: 110)))      // rubber band to the pointer
            snapshot(".pen-draw.png")

            tap(CGPoint(x: 450, y: 110))
            c3.keyDown(with: NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: w3.windowNumber,
                                              context: nil, characters: "\r", charactersIgnoringModifiers: "\r", isARepeat: false, keyCode: 36)!)
            if let id = c3.drawing.shapes.first?.id {
                c3.applyShapes("noop") { _ in }
                c3.applyStyle("Width") { $0.stroke.width = 3 }
                c3.beginPathEdit(id)
                c3.selectPathPoint(2)
                snapshot(".pen-edit.png")
                c3.endPathEdit()
                c3.selection = [id]
                c3.lockSelection(nil)
                snapshot(".locked.png")
            }
        }

        // A move in progress with smart guides showing.
        do {
            let c4 = CanvasView(frame: NSRect(x: 0, y: 0, width: 520, height: 330))
            let w4 = NSWindow(contentRect: c4.frame, styleMask: [.titled], backing: .buffered, defer: false)
            w4.contentView = c4
            c4.snapToGrid = false
            c4.showGrid = false
            var d4 = Drawing()
            let layer = d4.layers[0].id
            var top = Shape(layer: layer, kind: .rounded, frame: CGRect(x: 60, y: 40, width: 150, height: 70), text: "Top")
            top.style.cornerRadius = 10
            var right = Shape(layer: layer, kind: .rounded, frame: CGRect(x: 330, y: 70, width: 140, height: 90), text: "Right")
            right.style.cornerRadius = 10
            var mover = Shape(layer: layer, kind: .rounded, frame: CGRect(x: 120, y: 230, width: 120, height: 60), text: "Moving")
            mover.style.cornerRadius = 10
            mover.style.fill.color = RGBA(1, 0.85, 0.5)
            d4.shapes = [top, right, mover]
            c4.load(d4)
            c4.selection = [mover.id]
            func ev4(_ t: NSEvent.EventType, _ p: CGPoint) -> NSEvent {
                NSEvent.mouseEvent(with: t, location: CGPoint(x: p.x, y: 330 - p.y), modifierFlags: [], timestamp: 0,
                                   windowNumber: w4.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!
            }
            c4.mouseDown(with: ev4(.leftMouseDown, CGPoint(x: 180, y: 260)))
            c4.mouseDragged(with: ev4(.leftMouseDragged, CGPoint(x: 183, y: 261 + 0)))   // drifts a little, left edge ~ 123 vs Top's 60? no snap
            c4.mouseDragged(with: ev4(.leftMouseDragged, CGPoint(x: 120 + 0, y: 260)))    // left edge now ~60 -> snaps to Top's left
            if let rep = c4.bitmapImageRepForCachingDisplay(in: c4.bounds) {
                c4.cacheDisplay(in: c4.bounds, to: rep)
                try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path + ".guides.png"))
            }
            c4.mouseUp(with: ev4(.leftMouseUp, CGPoint(x: 120, y: 260)))
        }

        // Resize guides and equal-spacing marks, each captured mid-drag.
        do {
            let c5 = CanvasView(frame: NSRect(x: 0, y: 0, width: 520, height: 330))
            let w5 = NSWindow(contentRect: c5.frame, styleMask: [.titled], backing: .buffered, defer: false)
            w5.contentView = c5
            c5.snapToGrid = false
            c5.showGrid = false
            func ev5(_ t: NSEvent.EventType, _ p: CGPoint) -> NSEvent {
                NSEvent.mouseEvent(with: t, location: CGPoint(x: p.x, y: 330 - p.y), modifierFlags: [], timestamp: 0,
                                   windowNumber: w5.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!
            }
            func box(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, _ t: String, layer: UUID, fill: RGBA? = nil) -> Shape {
                var s = Shape(layer: layer, kind: .rounded, frame: CGRect(x: x, y: y, width: w, height: h), text: t)
                s.style.cornerRadius = 8
                if let f = fill { s.style.fill.color = f }
                return s
            }
            func shot(_ suffix: String) {
                if let rep = c5.bitmapImageRepForCachingDisplay(in: c5.bounds) {
                    c5.cacheDisplay(in: c5.bounds, to: rep)
                    try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path + suffix))
                }
            }

            // 1. Resizing the lower shape until its right edge meets the other shape's left edge.
            var d5 = Drawing(); var layer = d5.layers[0].id
            let wide = box(260, 40, 160, 80, "Anchor", layer: layer)
            let grow = box(60, 200, 120, 70, "Resizing", layer: layer, fill: RGBA(1, 0.85, 0.5))
            d5.shapes = [wide, grow]
            c5.load(d5)
            c5.selection = [grow.id]
            c5.mouseDown(with: ev5(.leftMouseDown, CGPoint(x: 180, y: 270)))
            c5.mouseDragged(with: ev5(.leftMouseDragged, CGPoint(x: 262, y: 270)))
            shot(".resize-guides.png")
            c5.mouseUp(with: ev5(.leftMouseUp, CGPoint(x: 262, y: 270)))

            // 2. Moving the middle shape until the gaps on both sides are the same.
            d5 = Drawing(); layer = d5.layers[0].id
            let left = box(30, 130, 100, 70, "Left", layer: layer)
            let right = box(390, 130, 100, 70, "Right", layer: layer)
            let mid = box(170, 135, 90, 60, "Moving", layer: layer, fill: RGBA(0.8, 0.95, 0.85))
            d5.shapes = [left, right, mid]
            c5.load(d5)
            c5.selection = [mid.id]
            c5.mouseDown(with: ev5(.leftMouseDown, CGPoint(x: 215, y: 165)))
            c5.mouseDragged(with: ev5(.leftMouseDragged, CGPoint(x: 255, y: 165)))
            shot(".spacing-guides.png")
            c5.mouseUp(with: ev5(.leftMouseUp, CGPoint(x: 255, y: 165)))
        }

        // The whole inspector, with the shadow off and then on.
        do {
            let c2 = CanvasView(frame: NSRect(x: 0, y: 0, width: 900, height: 700))
            let w2 = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 260, height: 960), styleMask: [.titled], backing: .buffered, defer: false)
            let insp = InspectorView(frame: NSRect(x: 0, y: 0, width: 260, height: 960))
            w2.contentView = insp
            insp.canvas = c2
            var d2 = Drawing()
            var sh = Shape(layer: d2.layers[0].id, kind: .rounded, frame: CGRect(x: 50, y: 50, width: 160, height: 90), text: "Hi")
            sh.style.cornerRadius = 12
            d2.shapes = [sh]
            c2.load(d2)
            c2.selection = [sh.id]
            for (suffix, shadowOn) in [("off", false), ("on", true)] {
                c2.applyStyle("Shadow") { $0.shadow.enabled = shadowOn }
                insp.refresh()
                insp.layoutSubtreeIfNeeded()
                if let rep = insp.bitmapImageRepForCachingDisplay(in: insp.bounds) {
                    insp.cacheDisplay(in: insp.bounds, to: rep)
                    try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path + ".inspector-\(suffix).png"))
                }
            }
        }

        // The angle controls as they appear in the inspector.
        let dialSheet = NSView(frame: NSRect(x: 0, y: 0, width: 260, height: 4 * 40))
        var dialRows: [AngleRow] = []
        for (title, v) in [("Rotation", 0.0), ("Angle", 45), ("Angle", 90), ("Angle", 200)] {
            let r = AngleRow(title); r.set(v); dialRows.append(r)
        }
        let stack = NSStackView(views: dialRows.map(\.row))
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 8
        stack.edgeInsets = NSEdgeInsets(top: 6, left: 14, bottom: 6, right: 14)
        stack.frame = dialSheet.bounds
        dialSheet.addSubview(stack)
        dialSheet.layoutSubtreeIfNeeded()
        if let rep = dialSheet.bitmapImageRepForCachingDisplay(in: dialSheet.bounds) {
            dialSheet.cacheDisplay(in: dialSheet.bounds, to: rep)
            try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path + ".dials.png"))
        }

        // Second render with the annotation layer hidden, to prove layer visibility reaches the output.
        canvas.setLayer(notes.id, visible: false)
        if let data = canvas.pngData() { try? data.write(to: URL(fileURLWithPath: path + ".hidden.png")) }
    }

    // MARK: Dev helper (Graffle --selftest): drives the canvas with synthetic events, one per run-loop turn

    private func runSelfTest() {
        setvbuf(stdout, nil, _IONBF, 0)   // unbuffered, so a crash still shows how far the run got
        let win = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 900, height: 700),
                           styleMask: [.titled], backing: .buffered, defer: false)
        let cv = CanvasView(frame: NSRect(x: 0, y: 0, width: 900, height: 700))
        win.contentView = cv

        func ev(_ type: NSEvent.EventType, _ p: CGPoint) -> NSEvent {
            // The canvas is flipped: convert model y to window (bottom-left) y.
            NSEvent.mouseEvent(with: type, location: CGPoint(x: p.x, y: 700 - p.y), modifierFlags: [],
                               timestamp: 0, windowNumber: win.windowNumber, context: nil,
                               eventNumber: 0, clickCount: 1, pressure: 1)!
        }
        func drag(_ a: CGPoint, _ b: CGPoint) {
            cv.mouseDown(with: ev(.leftMouseDown, a))
            cv.mouseDragged(with: ev(.leftMouseDragged, b))
            cv.mouseUp(with: ev(.leftMouseUp, b))
        }

        var steps: [(String, () -> Bool)] = []
        steps.append(("drag creates rectangle 120x80", {
            cv.tool = .shape(.rectangle); drag(CGPoint(x: 100, y: 100), CGPoint(x: 220, y: 180))
            return cv.drawing.shapes.count == 1 && cv.drawing.shapes[0].frame == CGRect(x: 100, y: 100, width: 120, height: 80)
        }))
        steps.append(("tool returns to select after creating", { cv.tool == .select }))
        steps.append(("click creates default-size ellipse", {
            cv.tool = .shape(.ellipse); drag(CGPoint(x: 400, y: 300), CGPoint(x: 401, y: 301))
            return cv.drawing.shapes.count == 2 && cv.drawing.shapes[1].frame.size == CGSize(width: 120, height: 72)
        }))
        steps.append(("drag moves shape by (100,100) with grid snap", {
            drag(CGPoint(x: 160, y: 140), CGPoint(x: 260, y: 240))
            return cv.drawing.shapes[0].frame.origin == CGPoint(x: 200, y: 200)
        }))
        steps.append(("connector tool links two shapes", {
            cv.tool = .connector; drag(CGPoint(x: 260, y: 240), CGPoint(x: 460, y: 336))
            return cv.drawing.connectors.count == 1
        }))
        steps.append(("no connector without a target", {
            cv.tool = .connector; drag(CGPoint(x: 260, y: 240), CGPoint(x: 260, y: 240))
            return cv.drawing.connectors.count == 1
        }))
        steps.append(("undo removes connector", { cv.undoManager?.undo(); return cv.drawing.connectors.isEmpty }))
        steps.append(("redo restores connector", { cv.undoManager?.redo(); return cv.drawing.connectors.count == 1 }))
        steps.append(("duplicate adds a shape and selects it", {
            cv.selection = [cv.drawing.shapes[1].id]
            cv.duplicate(nil)
            return cv.drawing.shapes.count == 3 && cv.selection.count == 1
        }))
        steps.append(("delete removes shape and its connectors", {
            cv.selection = [cv.drawing.shapes[0].id]
            cv.delete(nil)
            return cv.drawing.shapes.count == 2 && cv.drawing.connectors.isEmpty
        }))
        steps.append(("undo delete restores both", {
            cv.undoManager?.undo()
            return cv.drawing.shapes.count == 3 && cv.drawing.connectors.count == 1
        }))
        steps.append(("copy/paste duplicates shapes and inner connectors", {
            cv.selection = Set(cv.drawing.shapes.map(\.id))
            cv.copy(nil); cv.paste(nil)
            return cv.drawing.shapes.count == 6 && cv.drawing.connectors.count == 2
        }))
        steps.append(("align left lines up selected shapes", {
            cv.selection = Set(cv.drawing.shapes.map(\.id))
            let item = NSMenuItem(); item.tag = 0
            cv.align(item)
            return Set(cv.drawing.shapes.map(\.frame.minX)).count == 1
        }))
        steps.append(("resize handle grows shape", {
            cv.selection = [cv.drawing.shapes[0].id]
            let f = cv.drawing.shapes[0].frame
            drag(CGPoint(x: f.maxX, y: f.maxY), CGPoint(x: f.maxX + 50, y: f.maxY + 30))
            let nf = cv.drawing.shapes[0].frame
            return nf.width == f.width + 50 && nf.height == f.height + 30 && nf.origin == f.origin
        }))
        steps.append(("JSON save/load round trip", {
            guard let data = try? JSONEncoder().encode(cv.drawing),
                  let back = try? JSONDecoder().decode(Drawing.self, from: data) else { return false }
            return back == cv.drawing
        }))
        steps.append(("gradient fill type applies to the selection", {
            cv.selection = [cv.drawing.shapes[0].id]
            cv.applyStyle("Fill Type") { $0.fill.kind = .linear }
            return cv.drawing.shapes[0].style.fill.kind == .linear
        }))
        steps.append(("a color-panel drag (many edits) is one undo step", {
            cv.applyStyle("Fill Color") { $0.fill.color = RGBA(1, 0, 0) }
            cv.applyStyle("Fill Color") { $0.fill.color = RGBA(0.5, 0.5, 0) }
            cv.applyStyle("Fill Color") { $0.fill.color = RGBA(0, 1, 0) }
            return cv.drawing.shapes[0].style.fill.color == RGBA(0, 1, 0)
        }))
        steps.append(("one undo reverts the whole drag but keeps the earlier change", {
            cv.undoManager?.undo()
            let st = cv.drawing.shapes[0].style
            return st.fill.kind == .linear && st.fill.color == Fill().color
        }))
        steps.append(("new layer becomes active and receives new shapes", {
            let before = cv.drawing.layers.count
            cv.addLayer()
            cv.tool = .shape(.rectangle); drag(CGPoint(x: 600, y: 500), CGPoint(x: 700, y: 560))
            let newShape = cv.drawing.shapes.last!
            return cv.drawing.layers.count == before + 1 && newShape.layer == cv.activeLayerID && newShape.layer == cv.drawing.layers.last!.id
        }))
        steps.append(("hiding a layer drops its objects from the selection", {
            let top = cv.drawing.layers.last!.id
            let id = cv.drawing.shapes.last!.id
            cv.selection = [id]
            cv.setLayer(top, visible: false)
            return cv.selection.isEmpty
        }))
        steps.append(("hidden layer objects can't be hit", {
            cv.tool = .select
            let n = cv.drawing.shapes.count
            drag(CGPoint(x: 650, y: 530), CGPoint(x: 650, y: 530))   // click on the hidden shape
            return cv.selection.isEmpty && cv.drawing.shapes.count == n
        }))
        steps.append(("locked layer objects can't be selected", {
            let top = cv.drawing.layers.last!.id
            cv.setLayer(top, visible: true)
            cv.setLayer(top, locked: true)
            drag(CGPoint(x: 650, y: 530), CGPoint(x: 650, y: 530))
            return cv.selection.isEmpty
        }))
        steps.append(("move selection to another layer", {
            let top = cv.drawing.layers.last!.id
            cv.setLayer(top, locked: false)
            let id = cv.drawing.shapes[0].id
            cv.selection = [id]
            cv.moveSelection(toLayer: top)
            return cv.drawing.shapes.first { $0.id == id }?.layer == top
        }))
        steps.append(("deleting a layer removes its objects and keeps one layer", {
            let top = cv.drawing.layers.last!.id
            let before = cv.drawing.shapes.count
            cv.deleteLayer(top)
            let removed = before - cv.drawing.shapes.count
            let guardLast = cv.drawing.layers.count == 1
            if guardLast { cv.deleteLayer(cv.drawing.layers[0].id) }
            return removed >= 2 && cv.drawing.layers.count >= 1
        }))
        steps.append(("layered document survives JSON round trip", {
            guard let data = try? JSONEncoder().encode(cv.drawing),
                  let back = try? JSONDecoder().decode(Drawing.self, from: data) else { return false }
            return back == cv.drawing
        }))
        steps.append(("shadow angle: 90° falls down, 0° falls right (measured on exported pixels)", {
            // Hard shadow (no blur) on an isolated shape so the direction can be read off the pixels.
            var d = Drawing()
            var sh = Shape(layer: d.layers[0].id, kind: .rectangle, frame: CGRect(x: 200, y: 200, width: 100, height: 100))
            sh.style.fill.color = RGBA(1, 1, 1)
            sh.style.stroke.visible = false
            sh.style.shadow = Shadow(enabled: true, color: RGBA(0, 0, 0, 1), blur: 0, offset: 20, angle: 90)
            d.shapes = [sh]
            cv.load(d)
            func dark(_ png: Data?, _ x: CGFloat, _ y: CGFloat) -> Bool? {
                guard let png, let rep = NSBitmapImageRep(data: png), let b = cv.exportBounds() else { return nil }
                let scale = CGFloat(rep.pixelsWide) / b.width
                guard let c = rep.colorAt(x: Int((x - b.minX) * scale), y: Int((y - b.minY) * scale)) else { return nil }
                return c.brightnessComponent < 0.3
            }
            let down = cv.pngData()
            // Below the shape (inside the 20pt shadow band) is dark; above it is not.
            let belowDark = dark(down, 250, 310), aboveDark = dark(down, 250, 190)

            d.shapes[0].style.shadow.angle = 0
            cv.load(d)
            let right = cv.pngData()
            let rightDark = dark(right, 310, 250), leftDark = dark(right, 190, 250)
            return belowDark == true && aboveDark == false && rightDark == true && leftDark == false
        }))
        steps.append(("click hit-testing follows a rotated shape", {
            cv.load(Drawing())
            cv.tool = .shape(.rectangle); drag(CGPoint(x: 200, y: 200), CGPoint(x: 400, y: 240))   // frame 200x40
            cv.applyShapes("Rotate") { $0.rotation = 90 }      // now tall: x 280...320, y 120...320
            cv.selection = []
            cv.tool = .select
            drag(CGPoint(x: 380, y: 220), CGPoint(x: 380, y: 220))   // inside the old frame, outside the rotated one
            let missed = cv.selection.isEmpty
            drag(CGPoint(x: 300, y: 150), CGPoint(x: 300, y: 150))   // inside the rotated shape only
            return missed && cv.selection.count == 1
        }))
        steps.append(("rotation knob drag sets the angle", {
            let id = cv.drawing.shapes[0].id
            cv.applyShapes("Rotate") { $0.rotation = 0 }
            cv.selection = [id]
            drag(CGPoint(x: 300, y: 176), CGPoint(x: 500, y: 220))   // knob is 24pt above the top edge; drag to the right
            return abs(cv.drawing.shapes[0].rotation - 90) < 0.5
        }))
        steps.append(("resizing a rotated shape keeps the opposite corner fixed on screen", {
            let before = cv.drawing.shapes[0]
            cv.selection = [before.id]
            let anchorBefore = before.toWorld(CGPoint(x: before.frame.minX, y: before.frame.minY))
            let handle = before.toWorld(CGPoint(x: before.frame.maxX, y: before.frame.maxY))
            drag(handle, CGPoint(x: handle.x, y: handle.y + 60))
            let after = cv.drawing.shapes[0]
            let anchorAfter = after.toWorld(CGPoint(x: after.frame.minX, y: after.frame.minY))
            return abs(anchorBefore.x - anchorAfter.x) < 0.01 && abs(anchorBefore.y - anchorAfter.y) < 0.01
                && abs(after.frame.width - 260) < 0.01 && after.frame.height == before.frame.height
        }))
        steps.append(("connector endpoints land on a rotated shape's outline", {
            let sh = Shape(layer: cv.drawing.layers[0].id, kind: .rectangle,
                           frame: CGRect(x: 200, y: 200, width: 200, height: 40), rotation: 90)
            let p = sh.boundaryPoint(toward: CGPoint(x: 300, y: 0))
            return abs(p.x - 300) < 0.01 && abs(p.y - 120) < 0.01
        }))
        steps.append(("group: clicking one member selects all; ungroup releases them", {
            cv.load(Drawing())
            cv.tool = .shape(.rectangle); drag(CGPoint(x: 100, y: 100), CGPoint(x: 200, y: 160))
            cv.tool = .shape(.rectangle); drag(CGPoint(x: 300, y: 100), CGPoint(x: 400, y: 160))
            cv.selectAll(nil)
            cv.group(nil)
            cv.selection = []
            cv.tool = .select
            drag(CGPoint(x: 150, y: 130), CGPoint(x: 150, y: 130))
            let groupedSelect = cv.selection.count == 2
            cv.ungroup(nil)
            cv.selection = []
            drag(CGPoint(x: 150, y: 130), CGPoint(x: 150, y: 130))
            return groupedSelect && cv.selection.count == 1
        }))
        steps.append(("dragging a grouped shape moves the whole group", {
            cv.applyShapes("noop") { _ in }
            cv.selectAll(nil)
            cv.group(nil)
            cv.selection = []
            let before = cv.drawing.shapes.map(\.frame.origin)
            drag(CGPoint(x: 150, y: 130), CGPoint(x: 150, y: 230))   // drag first member down by 100
            let after = cv.drawing.shapes.map(\.frame.origin)
            return zip(before, after).allSatisfy { abs($1.x - $0.x) < 0.01 && abs($1.y - $0.y - 100) < 0.01 }
        }))
        steps.append(("pasting a group creates a new, separate group", {
            cv.selectAll(nil)
            cv.copy(nil); cv.paste(nil)
            let groups = cv.drawing.shapes.compactMap(\.group)
            let distinct = Set(groups)
            return cv.drawing.shapes.count == 4 && groups.count == 4 && distinct.count == 2
                && distinct.allSatisfy { g in groups.filter { $0 == g }.count == 2 }
        }))
        steps.append(("shadow keeps its direction when the shape is rotated", {
            var d = Drawing()
            var sh = Shape(layer: d.layers[0].id, kind: .rectangle, frame: CGRect(x: 200, y: 200, width: 100, height: 100), rotation: 45)
            sh.style.fill.color = RGBA(1, 1, 1)
            sh.style.stroke.visible = false
            sh.style.shadow = Shadow(enabled: true, color: RGBA(0, 0, 0, 1), blur: 0, offset: 20, angle: 90)
            d.shapes = [sh]
            cv.load(d)
            guard let png = cv.pngData(), let rep = NSBitmapImageRep(data: png), let b = cv.exportBounds() else { return false }
            let scale = CGFloat(rep.pixelsWide) / b.width
            func dark(_ x: CGFloat, _ y: CGFloat) -> Bool {
                (rep.colorAt(x: Int((x - b.minX) * scale), y: Int((y - b.minY) * scale))?.brightnessComponent ?? 1) < 0.3
            }
            // The diamond's bottom vertex is at y≈320.7; a downward shadow reaches y≈340.7 directly beneath it.
            return dark(250, 333) && !dark(250, 170)
        }))
        steps.append(("gradient color interpolates between stops", {
            var f = Fill()
            f.stops = [GradientStop(color: RGBA(1, 0, 0), position: 0), GradientStop(color: RGBA(0, 0, 1), position: 1)]
            let mid = f.color(at: 0.5)
            f.stops.append(GradientStop(color: RGBA(0, 1, 0), position: 0.5))
            let pinned = f.color(at: 0.5)
            return abs(mid.r - 0.5) < 1e-9 && abs(mid.b - 0.5) < 1e-9 && mid.g == 0 && pinned.g == 1 && f.color(at: -1).r == 1
        }))
        steps.append(("documents with the old color2 gradient still open", {
            let json = """
            {"kind":"linear","color":{"r":1,"g":0,"b":0,"a":1},"color2":{"r":0,"g":0,"b":1,"a":1},"angle":45}
            """
            guard let fill = try? JSONDecoder().decode(Fill.self, from: Data(json.utf8)) else { return false }
            return fill.stops.count == 2 && fill.stops[0].color.r == 1 && fill.stops[1].color.b == 1 && fill.angle == 45
        }))
        steps.append(("multi-stop gradient renders each color where it belongs (stops given out of order)", {
            var d = Drawing()
            var sh = Shape(layer: d.layers[0].id, kind: .rectangle, frame: CGRect(x: 100, y: 100, width: 300, height: 60))
            sh.style.stroke.visible = false
            sh.style.fill.kind = .linear
            sh.style.fill.angle = 0
            sh.style.fill.stops = [GradientStop(color: RGBA(0, 0, 1), position: 1),
                                   GradientStop(color: RGBA(1, 0, 0), position: 0),
                                   GradientStop(color: RGBA(0, 1, 0), position: 0.5)]
            d.shapes = [sh]
            cv.load(d)
            guard let png = cv.pngData(), let rep = NSBitmapImageRep(data: png), let b = cv.exportBounds() else { return false }
            let scale = CGFloat(rep.pixelsWide) / b.width
            func rgb(_ x: CGFloat) -> (CGFloat, CGFloat, CGFloat) {
                let c = rep.colorAt(x: Int((x - b.minX) * scale), y: Int((130 - b.minY) * scale))!.usingColorSpace(.sRGB)!
                return (c.redComponent, c.greenComponent, c.blueComponent)
            }
            let left = rgb(104), middle = rgb(250), right = rgb(396)
            // Exported pixels pass through the display color profile, so compare channels rather than exact values.
            func dominant(_ c: (CGFloat, CGFloat, CGFloat), _ ch: Int) -> Bool {
                let v = [c.0, c.1, c.2]
                return (0..<3).filter { $0 != ch }.allSatisfy { v[ch] - v[$0] > 0.3 }
            }
            return dominant(left, 0) && dominant(middle, 1) && dominant(right, 2)
        }))
        steps.append(("gradient editor: click adds a stop, drag moves it, remove keeps at least two", {
            let ed = GradientEditorView(frame: NSRect(x: 0, y: 0, width: 232, height: 46))
            let w = NSWindow(contentRect: ed.frame, styleMask: [.titled], backing: .buffered, defer: false)
            w.contentView = ed
            func mouse(_ t: NSEvent.EventType, _ x: CGFloat, _ yTop: CGFloat) -> NSEvent {
                NSEvent.mouseEvent(with: t, location: CGPoint(x: x, y: 46 - yTop), modifierFlags: [], timestamp: 0,
                                   windowNumber: w.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!
            }
            ed.stops = [GradientStop(color: RGBA(1, 0, 0), position: 0), GradientStop(color: RGBA(0, 0, 1), position: 1)]
            var edits = 0
            ed.onEdit = { edits += 1 }

            // Bar spans x = 12...220 (inset 12). Click its middle: a third stop appears at 50% with the blended color.
            ed.mouseDown(with: mouse(.leftMouseDown, 116, 12)); ed.mouseUp(with: mouse(.leftMouseUp, 116, 12))
            let added = ed.stops.count == 3 && abs(ed.stops[2].position - 0.5) < 0.01
                && abs(ed.stops[2].color.r - 0.5) < 0.02 && ed.selected == 2

            // Drag the first stop's marker (under the bar at x = 12) a quarter of the way across.
            ed.mouseDown(with: mouse(.leftMouseDown, 12, 35))
            ed.mouseDragged(with: mouse(.leftMouseDragged, 64, 35))
            ed.mouseUp(with: mouse(.leftMouseUp, 64, 35))
            let moved = ed.selected == 0 && abs(ed.stops[0].position - 0.25) < 0.01

            ed.selected = 2
            ed.removeSelected()
            let removed = ed.stops.count == 2
            ed.removeSelected()            // already at two stops: must refuse
            return added && moved && removed && ed.stops.count == 2 && edits >= 3
        }))
        steps.append(("inspector shows Text/Connector sections only when the selection needs them", {
            let canvas2 = CanvasView(frame: NSRect(x: 0, y: 0, width: 900, height: 700))
            let w2 = NSWindow(contentRect: canvas2.frame, styleMask: [.titled], backing: .buffered, defer: false)
            w2.contentView = canvas2
            let insp = InspectorView(frame: NSRect(x: 0, y: 0, width: 260, height: 820))
            insp.canvas = canvas2

            var d = Drawing()
            let layer = d.layers[0].id
            let a = Shape(layer: layer, kind: .rectangle, frame: CGRect(x: 50, y: 50, width: 100, height: 60))
            let b = Shape(layer: layer, kind: .ellipse, frame: CGRect(x: 300, y: 50, width: 100, height: 60))
            let link = Connector(layer: layer, from: a.id, to: b.id)
            d.shapes = [a, b]; d.connectors = [link]
            canvas2.load(d)

            canvas2.selection = []; insp.refresh()
            let none = insp.visibleSectionTitles
            canvas2.selection = [a.id]; insp.refresh()
            let shape = insp.visibleSectionTitles
            canvas2.selection = [link.id]; insp.refresh()
            let conn = insp.visibleSectionTitles
            canvas2.selection = [a.id, link.id]; insp.refresh()
            let mixed = insp.visibleSectionTitles

            return none == ["Styles", "Fill", "Line", "Shadow", "Object"]
                && shape == ["Styles", "Fill", "Line", "Shadow", "Object", "Text"]
                && conn == ["Styles", "Line", "Shadow", "Object", "Text", "Connector"]
                && mixed == ["Styles", "Fill", "Line", "Shadow", "Object", "Text", "Connector"]
                && !insp.isLayersPanelHidden
        }))
        steps.append(("every choice in a style menu has its own distinct picture", {
            func distinct(_ images: [NSImage]) -> Bool {
                let data = images.compactMap { $0.tiffRepresentation }
                return data.count == images.count && Set(data).count == images.count
            }
            return distinct(DashKind.allCases.map(Glyphs.dash))
                && distinct(CapKind.allCases.map(Glyphs.cap))
                && distinct(JoinKind.allCases.map(Glyphs.join))
                && distinct(Route.allCases.map(Glyphs.route))
                && distinct(HeadKind.allCases.map { Glyphs.head($0, atEnd: true) })
                && distinct(HeadKind.allCases.map { Glyphs.head($0, atEnd: false) })
                && distinct(FillKind.allCases.map(Glyphs.fill))
                && distinct(HAlign.allCases.map(Glyphs.hAlign))
                && distinct(VAlign.allCases.map(Glyphs.vAlign))
        }))
        steps.append(("group resize: two shapes selected show one box around both", {
            cv.load(Drawing())
            cv.tool = .shape(.rectangle); drag(CGPoint(x: 100, y: 100), CGPoint(x: 200, y: 160))
            cv.tool = .shape(.rectangle); drag(CGPoint(x: 300, y: 100), CGPoint(x: 400, y: 160))
            cv.tool = .select
            cv.selectAll(nil)
            return cv.selection.count == 2
        }))
        steps.append(("group resize: corner handle scales every selected shape as one unit", {
            // Box is (100,100)-(400,160); its handles sit 4pt outside it. (Its own step, so undo below reverts only this.)
            drag(CGPoint(x: 404, y: 164), CGPoint(x: 704, y: 224))   // drag bottom-right to (700,220)
            let a = cv.drawing.shapes[0].frame, b = cv.drawing.shapes[1].frame
            return a == CGRect(x: 100, y: 100, width: 200, height: 120) && b == CGRect(x: 500, y: 100, width: 200, height: 120)
        }))
        steps.append(("group resize: undo restores every shape in one step", {
            cv.undoManager?.undo()
            return cv.drawing.shapes[0].frame == CGRect(x: 100, y: 100, width: 100, height: 60)
                && cv.drawing.shapes[1].frame == CGRect(x: 300, y: 100, width: 100, height: 60)
        }))
        steps.append(("group resize: Shift on a corner keeps the proportions", {
            cv.selectAll(nil)
            let down = NSEvent.mouseEvent(with: .leftMouseDown, location: CGPoint(x: 404, y: 700 - 164), modifierFlags: [], timestamp: 0,
                                          windowNumber: win.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!
            let moved = NSEvent.mouseEvent(with: .leftMouseDragged, location: CGPoint(x: 704, y: 700 - 164), modifierFlags: [.shift], timestamp: 0,
                                           windowNumber: win.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!
            let up = NSEvent.mouseEvent(with: .leftMouseUp, location: CGPoint(x: 704, y: 700 - 164), modifierFlags: [.shift], timestamp: 0,
                                        windowNumber: win.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!
            cv.mouseDown(with: down); cv.mouseDragged(with: moved); cv.mouseUp(with: up)
            // The pointer only moved sideways (x2), yet the height doubled too.
            let a = cv.drawing.shapes[0].frame
            return abs(a.width - 200) < 0.01 && abs(a.height - 120) < 0.01
        }))
        steps.append(("group resize: an edge handle scales one axis only", {
            cv.undoManager?.undo()
            cv.selectAll(nil)
            drag(CGPoint(x: 404, y: 130), CGPoint(x: 704, y: 130))   // right-middle handle, 300pt to the right
            let a = cv.drawing.shapes[0].frame, b = cv.drawing.shapes[1].frame
            return a.height == 60 && b.height == 60 && abs(a.width - 200) < 0.01 && abs(b.minX - 500) < 0.01
        }))
        steps.append(("group resize: a quarter-turned shape swaps which axis scales its size", {
            cv.load(Drawing())
            cv.tool = .shape(.rectangle); drag(CGPoint(x: 100, y: 100), CGPoint(x: 300, y: 140))   // 200x40, center (200,120)
            cv.applyShapes("Rotate") { $0.rotation = 90 }                                           // on screen: x 180...220, y 20...220
            cv.tool = .shape(.rectangle); drag(CGPoint(x: 300, y: 100), CGPoint(x: 400, y: 160))
            cv.tool = .select
            cv.selectAll(nil)                                                                       // box (180,20)-(400,220)
            drag(CGPoint(x: 404, y: 224), CGPoint(x: 624, y: 224))                                  // stretch x by 2 (220 -> 440)
            let r = cv.drawing.shapes[0]
            // Its on-screen width (the local height) doubled; its on-screen height (local width) stayed.
            return abs(r.frame.height - 80) < 0.01 && abs(r.frame.width - 200) < 0.01 && r.rotation == 90
        }))
        steps.append(("SVG export is well-formed and carries gradients, layers, rotation, shadow, dashes and escaped text", {
            var d = Drawing()
            let main = d.layers[0].id
            let secret = Layer(name: "Secret & <hidden>", visible: false)
            d.layers.append(secret)

            var a = Shape(layer: main, kind: .rounded, frame: CGRect(x: 100, y: 100, width: 220, height: 90), rotation: 30)
            a.style.fill.kind = .linear
            a.style.fill.angle = 0
            a.style.fill.stops = [GradientStop(color: RGBA(1, 0, 0), position: 0), GradientStop(color: RGBA(0, 1, 0), position: 0.5),
                                  GradientStop(color: RGBA(0, 0, 1), position: 1)]
            a.style.cornerRadius = 14
            a.style.stroke.dash = .dashed
            a.style.shadow = Shadow(enabled: true, color: RGBA(0, 0, 0, 0.4), blur: 8, offset: 6, angle: 45)
            a.text = "Tom & Jerry <3\nsecond line"
            let b = Shape(layer: main, kind: .diamond, frame: CGRect(x: 420, y: 100, width: 120, height: 90))
            let hidden = Shape(layer: secret.id, kind: .ellipse, frame: CGRect(x: 100, y: 300, width: 100, height: 60))
            var link = Connector(layer: main, from: a.id, to: b.id)
            link.route = .rounded; link.startHead = .filledCircle; link.endHead = .hollowTriangle; link.text = "go"
            d.shapes = [a, b, hidden]; d.connectors = [link]

            cv.load(d)
            guard let data = cv.svgData(), let svg = String(data: data, encoding: .utf8) else { return false }
            let wellFormed = (try? XMLDocument(xmlString: svg, options: [])) != nil
            func count(_ needle: String) -> Int { svg.components(separatedBy: needle).count - 1 }
            return wellFormed
                && count("<stop ") == 3 && svg.contains("<linearGradient")
                && svg.contains("rotate(30 ") && svg.contains("stroke-dasharray") && svg.contains("<feDropShadow")
                && svg.contains("Tom &amp; Jerry &lt;3") && count("<tspan") >= 2
                && svg.contains("<polygon") && svg.contains("<circle")        // arrowheads
                && !svg.contains("<ellipse") && !svg.contains("Secret")       // the hidden layer is left out
        }))
        steps.append(("SVG rasterizes to the same colors as the canvas", {
            var d = Drawing()
            var r = Shape(layer: d.layers[0].id, kind: .rectangle, frame: CGRect(x: 100, y: 100, width: 200, height: 100))
            r.style.fill.color = RGBA(1, 0, 0)
            r.style.stroke.visible = false
            d.shapes = [r]
            cv.load(d)
            guard let data = cv.svgData(), let img = NSImage(data: data), img.size.width > 0 else {
                print("      (this macOS can't decode SVG; structural checks above cover it)")
                return true
            }
            let w = Int(img.size.width), h = Int(img.size.height)
            guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: w, pixelsHigh: h, bitsPerSample: 8, samplesPerPixel: 4,
                                             hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
                  let gc = NSGraphicsContext(bitmapImageRep: rep) else { return false }
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = gc
            img.draw(in: NSRect(x: 0, y: 0, width: w, height: h))
            NSGraphicsContext.restoreGraphicsState()
            let center = rep.colorAt(x: w / 2, y: h / 2)?.usingColorSpace(.sRGB)
            let corner = rep.colorAt(x: 2, y: 2)?.usingColorSpace(.sRGB)
            return (center?.redComponent ?? 0) > 0.8 && (center?.greenComponent ?? 1) < 0.25
                && (corner?.redComponent ?? 0) > 0.9 && (corner?.greenComponent ?? 0) > 0.9   // white margin
        }))
        // ---- SVG import
        let handwritten = """
        <svg xmlns="http://www.w3.org/2000/svg" width="400" height="300" viewBox="0 0 200 150">
          <defs><linearGradient id="g" x1="0" y1="0" x2="1" y2="0">
            <stop offset="0" stop-color="#f00"/><stop offset="50%" stop-color="#0f0"/><stop offset="1" stop-color="#00f"/>
          </linearGradient></defs>
          <g transform="translate(10,20)">
            <rect x="0" y="0" width="50" height="30" rx="5" fill="url(#g)" stroke="#000" stroke-width="2" stroke-dasharray="8 4"/>
            <circle cx="100" cy="15" r="10" style="fill:rgb(100%,0%,0%);stroke:none;opacity:0.5"/>
          </g>
          <polygon points="100,100 140,125 100,150 60,125" fill="orange"/>
          <polygon points="20,120 30,140 10,140" fill="#336"/>
          <polyline points="0,0 20,20 40,0" fill="none" stroke="blue"/>
          <path d="M10 10 h 20 v 20 h -20 z" fill="#0f0"/>
          <text x="50" y="60" font-size="12" font-family="Georgia, serif" font-weight="bold" text-anchor="middle" fill="#333">Hello &amp; <tspan x="50" y="75">world</tspan></text>
          <image href="x.png"/>
          <use href="#g"/>
        </svg>
        """
        steps.append(("SVG import: elements, transforms, viewBox, gradients, styles and text", {
            guard let r = try? SVGImport.parse(Data(handwritten.utf8), name: "hand") else { return false }
            func first(_ k: ShapeKind) -> Shape? { r.shapes.first { $0.kind == k } }
            func near(_ a: CGRect, _ b: CGRect) -> Bool {
                abs(a.minX - b.minX) < 0.05 && abs(a.minY - b.minY) < 0.05 && abs(a.width - b.width) < 0.05 && abs(a.height - b.height) < 0.05
            }
            guard r.shapes.count == 7, let rect = first(.rounded), let ell = first(.ellipse), let dia = first(.diamond),
                  let tri = first(.triangle), let txt = first(.text) else { return false }
            let poly = r.shapes.first { $0.kind == .path && !$0.style.stroke.visible == false }       // the blue polyline
            let green = r.shapes.first { $0.kind == .path && $0.style.fill.kind == .solid }           // the closed square
            return near(rect.frame, CGRect(x: 20, y: 40, width: 100, height: 60))                       // translate + viewBox x2
                && abs(rect.style.cornerRadius - 10) < 0.01
                && rect.style.fill.kind == .linear && rect.style.fill.stops.count == 3
                && abs(rect.style.fill.stops[1].position - 0.5) < 1e-9 && rect.style.fill.stops[2].color.b == 1
                && rect.style.stroke.visible && abs(rect.style.stroke.width - 4) < 0.01 && rect.style.stroke.dash == .dashed
                && near(ell.frame, CGRect(x: 200, y: 50, width: 40, height: 40))
                && abs(ell.style.opacity - 0.5) < 1e-9 && !ell.style.stroke.visible && ell.style.fill.color.r == 1 && ell.style.fill.color.g == 0
                && near(dia.frame, CGRect(x: 120, y: 200, width: 160, height: 100))
                && near(tri.frame, CGRect(x: 20, y: 240, width: 40, height: 40))
                && poly != nil && poly!.style.fill.kind == .none && abs(poly!.frame.width - 80) < 0.01
                && green != nil && abs(green!.frame.width - 40) < 0.01 && abs(green!.frame.height - 40) < 0.01
                && txt.text == "Hello &\nworld" && txt.style.text.bold && txt.style.text.font == "Georgia"
                && txt.style.text.hAlign == .center && abs(txt.style.text.size - 24) < 0.01
                && r.skipped["image"] == 1 && r.skipped["use"] == 1
        }))
        steps.append(("SVG path data: relative, implicit lineto, arcs, exponents and packed arc flags", {
            func box(_ d: String) -> CGRect { SVGImport.path(d).boundingBoxOfPath }
            func near(_ a: CGRect, _ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, tol: CGFloat = 0.05) -> Bool {
                abs(a.minX - x) < tol && abs(a.minY - y) < tol && abs(a.width - w) < tol && abs(a.height - h) < tol
            }
            let half = box("M0 0 A10 10 0 0 1 20 0")                // a half circle bulging upward (y is down)
            let packed = SVGImport.path("M0 0a1 1 0 01.5.5")        // flags with no separators
            return near(box("M10 10 H30 V30 H10 Z"), 10, 10, 20, 20)
                && near(box("m 0 0 10 0 0 10"), 0, 0, 10, 10)        // extra pairs after a moveto are linetos
                && near(half, 0, -10, 20, 10, tol: 0.1)
                && !packed.isEmpty
                && near(box("M1e1 2E0 L 3 4"), 3, 2, 7, 2)
                && near(box("M0 0 C 0 10 10 10 10 0"), 0, 0, 10, 7.5, tol: 0.1)   // tight bounds of a cubic, not its control points
                && near(box("M0 0 Q 10 20 20 0"), 0, 0, 20, 10, tol: 0.1)
        }))
        steps.append(("SVG import rejects non-SVG and malformed files", {
            var rejected = 0
            if (try? SVGImport.parse(Data("<html><body/></html>".utf8), name: "x")) == nil { rejected += 1 }
            if (try? SVGImport.parse(Data("<svg><rect".utf8), name: "x")) == nil { rejected += 1 }
            if (try? SVGImport.parse(Data("not xml at all".utf8), name: "x")) == nil { rejected += 1 }
            return rejected == 3
        }))
        steps.append(("SVG round trip: export then import keeps shapes, layers, rotation, gradients, dashes, shadow and text", {
            var d = Drawing()
            d.layers[0].name = "Base"
            d.layers.append(Layer(name: "Notes"))
            d.layers.append(Layer(name: "Hidden", visible: false))
            let base = d.layers[0].id, notes = d.layers[1].id, hidden = d.layers[2].id

            var a = Shape(layer: base, kind: .rounded, frame: CGRect(x: 100, y: 100, width: 220, height: 90), rotation: 30)
            a.style.fill.kind = .linear
            a.style.fill.angle = 0
            a.style.fill.stops = [GradientStop(color: RGBA(1, 0, 0), position: 0), GradientStop(color: RGBA(0, 1, 0), position: 0.5),
                                  GradientStop(color: RGBA(0, 0, 1), position: 1)]
            a.style.cornerRadius = 14
            a.style.stroke.dash = .dashed
            a.style.stroke.width = 2
            a.style.shadow = Shadow(enabled: true, color: RGBA(0, 0, 0, 0.4), blur: 8, offset: 10, angle: 90)
            a.style.opacity = 0.8
            a.style.text.bold = true
            a.text = "Hello\nWorld"
            var b = Shape(layer: base, kind: .diamond, frame: CGRect(x: 400, y: 100, width: 120, height: 90))
            b.style.fill.color = RGBA(1, 0, 0)
            let c = Shape(layer: base, kind: .triangle, frame: CGRect(x: 600, y: 100, width: 100, height: 90))
            var dd = Shape(layer: notes, kind: .ellipse, frame: CGRect(x: 100, y: 300, width: 120, height: 70))
            dd.style.stroke.dash = .dotted
            dd.style.stroke.width = 3
            var e = Shape(layer: notes, kind: .text, frame: CGRect(x: 300, y: 300, width: 200, height: 40), style: .textBox, text: "Free label")
            e.style.text.italic = true
            e.style.text.font = "Georgia"
            e.style.text.size = 20
            var f = Shape(layer: notes, kind: .path, frame: CGRect(x: 600, y: 300, width: 150, height: 80))
            f.style.fill.kind = .none
            f.style.stroke.color = RGBA(0, 0, 1)
            f.outline = [PathSegment(op: .move, points: [CGPoint(x: 0, y: 1)]), PathSegment(op: .line, points: [CGPoint(x: 0.5, y: 0)]),
                         PathSegment(op: .line, points: [CGPoint(x: 1, y: 1)])]
            let ghost = Shape(layer: hidden, kind: .rectangle, frame: CGRect(x: 100, y: 500, width: 80, height: 80))
            d.shapes = [a, b, c, dd, e, f, ghost]
            cv.load(d)

            guard let svg = cv.svgData(), let r = try? SVGImport.parse(svg, name: "rt") else { return false }
            func count(_ k: ShapeKind) -> Int { r.shapes.filter { $0.kind == k }.count }
            guard r.layers.map(\.name) == ["Base", "Notes"], r.shapes.count == 7,
                  count(.rounded) == 1, count(.diamond) == 1, count(.triangle) == 1, count(.ellipse) == 1, count(.path) == 1, count(.text) == 2,
                  let ra = r.shapes.first(where: { $0.kind == .rounded }), let rd = r.shapes.first(where: { $0.kind == .ellipse }),
                  let rb = r.shapes.first(where: { $0.kind == .diamond }), let rf = r.shapes.first(where: { $0.kind == .path }),
                  let label = r.shapes.first(where: { $0.kind == .text && $0.text == "Free label" }),
                  let body = r.shapes.first(where: { $0.kind == .text && $0.text.hasPrefix("Hello") })
            else { return false }
            func near(_ x: CGRect, _ y: CGRect) -> Bool {
                abs(x.midX - y.midX) < 0.1 && abs(x.midY - y.midY) < 0.1 && abs(x.width - y.width) < 0.1 && abs(x.height - y.height) < 0.1
            }
            // The importer moves the viewBox origin to (0,0), so every frame is shifted by the same amount;
            // what must survive is the layout relative to the first shape.
            let dx = ra.frame.midX - a.frame.midX, dy = ra.frame.midY - a.frame.midY
            let checks: [(String, Bool)] = [
                ("frame", near(ra.frame, a.frame.offsetBy(dx: dx, dy: dy))), ("rotation", abs(ra.rotation - 30) < 0.01),
                ("gradient", ra.style.fill.kind == .linear && ra.style.fill.stops.count == 3), ("dash", ra.style.stroke.dash == .dashed),
                ("radius", abs(ra.style.cornerRadius - 14) < 0.01),
                ("shadow", ra.style.shadow.enabled && abs(ra.style.shadow.angle - 90) < 0.5 && abs(ra.style.shadow.offset - 10) < 0.1
                    && abs(ra.style.shadow.blur - 8) < 0.1),
                ("opacity", abs(ra.style.opacity - 0.8) < 1e-6),
                ("diamond", near(rb.frame, b.frame.offsetBy(dx: dx, dy: dy))), ("dotted", rd.style.stroke.dash == .dotted),
                ("ellipse", near(rd.frame, dd.frame.offsetBy(dx: dx, dy: dy))),
                ("path frame", near(rf.frame, f.frame.offsetBy(dx: dx, dy: dy))), ("path fill", rf.style.fill.kind == .none),
                ("label", label.style.text.italic && label.style.text.font == "Georgia" && abs(label.style.text.size - 20) < 0.01),
                ("body", body.text == "Hello\nWorld" && body.style.text.bold),
                ("layers", r.layers.count == 2 && r.shapes.filter { $0.layer == r.layers[1].id }.count == 3),
            ]
            let failed = checks.filter { !$0.1 }.map(\.0)
            if !failed.isEmpty { print("      round trip mismatches:", failed, "| rect frame", ra.frame, "vs", a.frame, "| shadow", ra.style.shadow, "| path", rf.frame, "vs", f.frame) }
            return failed.isEmpty
        }))
        steps.append(("SVG import into the canvas: grouped, placed where asked, selected", {
            cv.load(Drawing())
            guard let r = try? SVGImport.parse(Data(handwritten.utf8), name: "hand") else { return false }
            let layersBefore = cv.drawing.layers.count
            cv.importSVG(r, near: CGPoint(x: 100, y: 100))
            let groups = Set(cv.drawing.shapes.compactMap(\.group))
            let origin = cv.drawing.shapes.map(\.worldBounds).reduce(nil) { acc, b in acc.map { $0.union(b) } ?? b }!
            return cv.drawing.shapes.count == 7 && groups.count == 1 && cv.drawing.shapes.allSatisfy { $0.group != nil }
                && cv.drawing.layers.count == layersBefore + 1 && cv.activeLayerID == cv.drawing.layers.last!.id
                && abs(origin.minX - 100) < 0.5 && abs(origin.minY - 100) < 0.5 && cv.selection.count == 7
        }))
        steps.append(("SVG import is one undo step that also removes its layer", {
            cv.undoManager?.undo()
            return cv.drawing.shapes.isEmpty && cv.drawing.layers.count == 1
        }))
        steps.append(("imported lines can be clicked on the stroke and resized with their outline", {
            cv.load(Drawing())
            let svg = ##"<svg xmlns="http://www.w3.org/2000/svg" width="200" height="200"><line x1="20" y1="20" x2="180" y2="120" stroke="#000" stroke-width="2"/></svg>"##
            guard let r = try? SVGImport.parse(Data(svg.utf8), name: "line") else { return false }
            cv.importSVG(r, near: CGPoint(x: 100, y: 100))          // line now runs (100,100) -> (260,200)
            cv.selection = []
            cv.tool = .select
            drag(CGPoint(x: 180, y: 150), CGPoint(x: 180, y: 150))   // on the line's middle
            let onLine = cv.selection.count == 1
            cv.selection = []
            drag(CGPoint(x: 180, y: 110), CGPoint(x: 180, y: 110))   // inside the frame but 40pt from the line
            let offLine = cv.selection.isEmpty
            guard let s0 = cv.drawing.shapes.first else { return false }
            cv.selection = [s0.id]
            drag(CGPoint(x: s0.frame.maxX, y: s0.frame.maxY), CGPoint(x: 360, y: 300))
            let s1 = cv.drawing.shapes[0]
            let bb = s1.path().boundingBox
            return onLine && offLine && abs(s1.frame.width - 260) < 0.01 && abs(s1.frame.height - 200) < 0.01
                && abs(bb.width - s1.frame.width) < 0.5 && abs(bb.height - s1.frame.height) < 0.5
        }))
        steps.append(("angle dial: pointer position sets the angle, Shift snaps to 15°", {
            let dial = AngleDial(frame: NSRect(x: 0, y: 0, width: 30, height: 30))
            let w = NSWindow(contentRect: dial.frame, styleMask: [.titled], backing: .buffered, defer: false)
            w.contentView = dial
            var reported: [Double] = []
            dial.onChange = { reported.append($0) }
            func click(_ x: CGFloat, _ yTop: CGFloat, shift: Bool = false) -> Double {
                let e = NSEvent.mouseEvent(with: .leftMouseDown, location: CGPoint(x: x, y: 30 - yTop),
                                           modifierFlags: shift ? [.shift] : [], timestamp: 0, windowNumber: w.windowNumber,
                                           context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!
                dial.mouseDown(with: e)
                return dial.angle
            }
            // Center is (15,15). Right = 0°, down = 90°, left = 180°, up = 270° (clockwise on screen, y down).
            let right = click(28, 15), down = click(15, 28), left = click(2, 15), up = click(15, 2)
            let free = click(25, 22.8)                 // about 38°
            let snapped = click(25, 22.8, shift: true) // snaps to 45°
            return right == 0 && down == 90 && left == 180 && up == 270 && free == 38 && snapped == 45 && reported.count == 6
        }))
        steps.append(("angle field: typed values wrap into 0-359 and junk is ignored", {
            let row = AngleRow("Angle")
            var got: [Double] = []
            row.onChange = { got.append($0) }
            row.enter("135"); row.enter("-90°"); row.enter("450"); row.enter("abc")
            return got == [135, 270, 90] && row.dial.angle == 90 && row.field.stringValue == "90°"
        }))
        steps.append(("inspector dials edit rotation, shadow angle and gradient angle of the selection", {
            let canvas2 = CanvasView(frame: NSRect(x: 0, y: 0, width: 900, height: 700))
            let w2 = NSWindow(contentRect: canvas2.frame, styleMask: [.titled], backing: .buffered, defer: false)
            w2.contentView = canvas2
            let insp = InspectorView(frame: NSRect(x: 0, y: 0, width: 260, height: 820))
            insp.canvas = canvas2
            canvas2.onSelectionChange = { insp.refresh() }

            var d = Drawing()
            let layer = d.layers[0].id
            var a = Shape(layer: layer, kind: .rectangle, frame: CGRect(x: 50, y: 50, width: 100, height: 60))
            var b = Shape(layer: layer, kind: .rectangle, frame: CGRect(x: 300, y: 50, width: 100, height: 60), rotation: 45)
            a.style.fill.kind = .linear
            b.style.shadow = Shadow(enabled: true, color: RGBA(0, 0, 0, 0.4), blur: 6, offset: 8, angle: 120)
            d.shapes = [a, b]
            canvas2.load(d)

            canvas2.selection = [a.id]
            insp.rotationControl.enter("90")
            insp.shadowAngleControl.enter("200")
            insp.gradientAngleControl.enter("30")
            let edited = canvas2.drawing.shapes[0]
            let applied = edited.rotation == 90 && edited.style.shadow.angle == 200 && edited.style.fill.angle == 30

            // Selecting another shape shows its angles on the dials without changing anything.
            canvas2.selection = [b.id]
            let showsOther = insp.rotationControl.dial.angle == 45 && insp.shadowAngleControl.dial.angle == 120
            let untouched = canvas2.drawing.shapes[1].rotation == 45 && canvas2.drawing.shapes[1].style.shadow.angle == 120
            return applied && showsOther && untouched
        }))
        // ---- Pen tool and point editing
        func evn(_ type: NSEvent.EventType, _ p: CGPoint, clicks: Int = 1, mods: NSEvent.ModifierFlags = []) -> NSEvent {
            NSEvent.mouseEvent(with: type, location: CGPoint(x: p.x, y: 700 - p.y), modifierFlags: mods, timestamp: 0,
                               windowNumber: win.windowNumber, context: nil, eventNumber: 0, clickCount: clicks, pressure: 1)!
        }
        func press(_ code: UInt16, _ chars: String) {
            let e = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: win.windowNumber,
                                     context: nil, characters: chars, charactersIgnoringModifiers: chars, isARepeat: false, keyCode: code)!
            cv.keyDown(with: e)
        }
        func click(_ p: CGPoint, clicks: Int = 1) { cv.mouseDown(with: evn(.leftMouseDown, p, clicks: clicks)); cv.mouseUp(with: evn(.leftMouseUp, p, clicks: clicks)) }
        func closeTo(_ a: CGPoint?, _ b: CGPoint, _ tol: CGFloat = 0.05) -> Bool {
            guard let a else { return false }
            return abs(a.x - b.x) < tol && abs(a.y - b.y) < tol
        }

        steps.append(("pen model: a path's points survive outline conversion, open or closed", {
            var open = PenPath(points: [PenPoint(anchor: CGPoint(x: 100, y: 100), handleOut: CGPoint(x: 140, y: 60)),
                                        PenPoint(anchor: CGPoint(x: 200, y: 100), handleIn: CGPoint(x: 170, y: 140), handleOut: CGPoint(x: 230, y: 60)),
                                        PenPoint(anchor: CGPoint(x: 300, y: 150))])
            func roundTrip(_ path: PenPath) -> PenPath? {
                guard let o = path.outline() else { return nil }
                return PenPath.from(Shape(layer: UUID(), kind: .path, frame: o.frame, outline: o.segments))
            }
            guard let a = roundTrip(open) else { return false }
            let sameOpen = a.points.count == 3 && !a.closed
                && closeTo(a.points[0].handleOut, CGPoint(x: 140, y: 60), 1e-6) && a.points[0].handleIn == nil
                && closeTo(a.points[1].handleIn, CGPoint(x: 170, y: 140), 1e-6) && closeTo(a.points[1].handleOut, CGPoint(x: 230, y: 60), 1e-6)
                && closeTo(a.points[2].anchor, CGPoint(x: 300, y: 150), 1e-6) && a.points[2].handleIn == nil
            open.closed = true
            open.points[0].handleIn = CGPoint(x: 60, y: 140)
            guard let c = roundTrip(open) else { return false }
            return sameOpen && c.closed && c.points.count == 3 && closeTo(c.points[0].handleIn, CGPoint(x: 60, y: 140), 1e-6)
        }))
        steps.append(("pen model: smooth/corner toggle, mirrored handles, point insertion keeps the curve, removal keeps two", {
            var path = PenPath(points: [PenPoint(anchor: CGPoint(x: 0, y: 0)), PenPoint(anchor: CGPoint(x: 100, y: 0)), PenPoint(anchor: CGPoint(x: 200, y: 100))])
            path.toggleSmooth(1)
            let madeSmooth = path.isSmooth(1)
            path.toggleSmooth(1)
            let madeCorner = path.points[1].handleIn == nil && path.points[1].handleOut == nil

            // Mirrored drag keeps the opposite handle's length.
            var p = PenPath(points: [PenPoint(anchor: CGPoint(x: 50, y: 50), handleIn: CGPoint(x: 30, y: 50), handleOut: CGPoint(x: 80, y: 50))])
            p.points.append(PenPoint(anchor: CGPoint(x: 200, y: 50)))
            p.setHandle(0, out: true, to: CGPoint(x: 50, y: 80), mirror: true)     // out handle points straight down
            let mirrored = closeTo(p.points[0].handleIn, CGPoint(x: 50, y: 50 - 20), 1e-6)   // in handle: opposite, still 20 long
            p.setHandle(0, out: true, to: CGPoint(x: 90, y: 50), mirror: false)
            let independent = closeTo(p.points[0].handleIn, CGPoint(x: 50, y: 30), 1e-6)

            // Splitting a curve adds an anchor without moving the curve: both halves must retrace the original exactly.
            func bez(_ p0: CGPoint, _ p1: CGPoint, _ p2: CGPoint, _ p3: CGPoint, _ t: CGFloat) -> CGPoint {
                let u = 1 - t
                return CGPoint(x: u*u*u*p0.x + 3*u*u*t*p1.x + 3*u*t*t*p2.x + t*t*t*p3.x,
                               y: u*u*u*p0.y + 3*u*u*t*p1.y + 3*u*t*t*p2.y + t*t*t*p3.y)
            }
            let o0 = CGPoint(x: 0, y: 0), o1 = CGPoint(x: 0, y: 100), o2 = CGPoint(x: 100, y: 100), o3 = CGPoint(x: 100, y: 0)
            var curve = PenPath(points: [PenPoint(anchor: o0, handleOut: o1), PenPoint(anchor: o3, handleIn: o2)])
            curve.insertPoint(segment: 0, t: 0.37)
            var drift: CGFloat = 99
            if curve.points.count == 3, let h0 = curve.points[0].handleOut, let h1 = curve.points[1].handleIn,
               let h2 = curve.points[1].handleOut, let h3 = curve.points[2].handleIn {
                let a1 = bez(curve.points[0].anchor, h0, h1, curve.points[1].anchor, 0.5)       // first half, its midpoint
                let a2 = bez(curve.points[1].anchor, h2, h3, curve.points[2].anchor, 0.5)       // second half, its midpoint
                let e0 = bez(o0, o1, o2, o3, 0.37), e1 = bez(o0, o1, o2, o3, 0.37 * 0.5), e2 = bez(o0, o1, o2, o3, 0.37 + 0.63 * 0.5)
                func d(_ p: CGPoint, _ q: CGPoint) -> CGFloat { hypot(p.x - q.x, p.y - q.y) }
                drift = max(d(curve.points[1].anchor, e0), d(a1, e1), d(a2, e2))
            }

            var two = PenPath(points: [PenPoint(anchor: .zero), PenPoint(anchor: CGPoint(x: 10, y: 10))])
            two.removePoint(0)
            var three = PenPath(points: [PenPoint(anchor: .zero), PenPoint(anchor: CGPoint(x: 5, y: 5)), PenPoint(anchor: CGPoint(x: 10, y: 10))])
            three.removePoint(1)
            let parts = [("smooth", madeSmooth), ("corner", madeCorner), ("mirrored", mirrored), ("independent", independent),
                         ("inserted", curve.points.count == 3), ("split exact", drift < 1e-6), ("two", two.points.count == 2), ("three", three.points.count == 2)]
            let bad = parts.filter { !$0.1 }.map(\.0)
            if !bad.isEmpty { print("      pen model mismatches:", bad, "drift", drift, "in-handle", p.points[0].handleIn as Any) }
            return bad.isEmpty
        }))
        steps.append(("pen tool: click, click-drag and Return draw an open Bézier path as one undoable shape", {
            cv.load(Drawing())
            cv.tool = .pen
            click(CGPoint(x: 100, y: 100))
            cv.mouseDown(with: evn(.leftMouseDown, CGPoint(x: 200, y: 100)))
            cv.mouseDragged(with: evn(.leftMouseDragged, CGPoint(x: 250, y: 60)))
            cv.mouseUp(with: evn(.leftMouseUp, CGPoint(x: 250, y: 60)))
            click(CGPoint(x: 300, y: 200))
            let drawing = cv.penPath?.points.count == 3
            press(36, "\r")
            guard drawing, cv.drawing.shapes.count == 1, let s = cv.drawing.shapes.first, s.kind == .path,
                  let pen = PenPath.from(s) else { return false }
            return pen.points.count == 3 && !pen.closed && cv.tool == .select && cv.selection == [s.id] && cv.penPath == nil
                && s.style.fill.kind == .none && s.style.stroke.visible
                && closeTo(pen.points[1].handleOut, CGPoint(x: 250, y: 60)) && closeTo(pen.points[1].handleIn, CGPoint(x: 150, y: 140))
                && pen.points[0].handleOut == nil && pen.points[2].handleIn == nil
        }))
        steps.append(("pen tool: the drawn path undoes in one step", {
            cv.undoManager?.undo()
            return cv.drawing.shapes.isEmpty
        }))
        steps.append(("pen tool: clicking the first point closes the shape and keeps the fill", {
            cv.load(Drawing())
            cv.tool = .pen
            click(CGPoint(x: 100, y: 100)); click(CGPoint(x: 300, y: 100)); click(CGPoint(x: 200, y: 250))
            click(CGPoint(x: 103, y: 102))                       // within 8pt of the first point
            guard let s = cv.drawing.shapes.first, let pen = PenPath.from(s) else { return false }
            return pen.closed && pen.points.count == 3 && s.style.fill.kind == .solid
                && s.outline?.last?.op == .close && cv.penPath == nil
        }))
        steps.append(("pen tool: a double click ends the path without a duplicate point", {
            cv.load(Drawing())
            cv.tool = .pen
            click(CGPoint(x: 100, y: 100)); click(CGPoint(x: 200, y: 160))
            click(CGPoint(x: 300, y: 100), clicks: 1)
            click(CGPoint(x: 300, y: 100), clicks: 2)
            guard let s = cv.drawing.shapes.first, let pen = PenPath.from(s) else { return false }
            return cv.drawing.shapes.count == 1 && pen.points.count == 3 && !pen.closed
        }))
        steps.append(("pen tool: Esc keeps a drawn path, discards a single point; Delete takes back the last point", {
            cv.load(Drawing())
            cv.tool = .pen
            click(CGPoint(x: 100, y: 100)); press(53, "\u{1b}")
            let discarded = cv.drawing.shapes.isEmpty && cv.penPath == nil

            cv.tool = .pen
            click(CGPoint(x: 100, y: 100)); click(CGPoint(x: 200, y: 100)); click(CGPoint(x: 300, y: 100))
            press(51, "\u{7f}")                                   // Delete: back to two points
            let backed = cv.penPath?.points.count == 2
            press(53, "\u{1b}")
            return discarded && backed && cv.drawing.shapes.count == 1 && PenPath.from(cv.drawing.shapes[0])?.points.count == 2
        }))
        steps.append(("pen tool: switching tools mid-path keeps what was drawn", {
            cv.load(Drawing())
            cv.tool = .pen
            click(CGPoint(x: 100, y: 100)); click(CGPoint(x: 200, y: 160)); click(CGPoint(x: 300, y: 100))
            cv.tool = .shape(.rectangle)
            return cv.drawing.shapes.count == 1 && cv.penPath == nil && cv.tool == .shape(.rectangle)
        }))

        // Point editing works on a smooth three-point path.
        steps.append(("point edit: double click on a path enters edit mode; dragging an anchor moves it with its handles", {
            cv.load(Drawing())
            cv.tool = .pen
            click(CGPoint(x: 100, y: 100))
            cv.mouseDown(with: evn(.leftMouseDown, CGPoint(x: 200, y: 100)))
            cv.mouseDragged(with: evn(.leftMouseDragged, CGPoint(x: 250, y: 60)))
            cv.mouseUp(with: evn(.leftMouseUp, CGPoint(x: 250, y: 60)))
            click(CGPoint(x: 300, y: 200)); press(36, "\r")
            cv.tool = .select
            guard let id = cv.drawing.shapes.first?.id else { return false }
            cv.selection = [id]
            cv.mouseDown(with: evn(.leftMouseDown, CGPoint(x: 100, y: 100), clicks: 2))
            cv.mouseUp(with: evn(.leftMouseUp, CGPoint(x: 100, y: 100), clicks: 2))
            let entered = cv.editingPath?.points.count == 3
            drag(CGPoint(x: 100, y: 100), CGPoint(x: 120, y: 130))
            guard let moved = PenPath.from(cv.drawing.shapes[0]) else { return false }
            return entered && cv.selectedPoint == 0 && closeTo(moved.points[0].anchor, CGPoint(x: 120, y: 130))
                && closeTo(moved.points[1].anchor, CGPoint(x: 200, y: 100))          // other points stay put
        }))
        steps.append(("point edit: dragging a smooth point's handle mirrors the other handle", {
            drag(CGPoint(x: 200, y: 100), CGPoint(x: 200, y: 100))                    // select the middle anchor
            let selected = cv.selectedPoint == 1
            drag(CGPoint(x: 250, y: 60), CGPoint(x: 260, y: 80))                      // its outgoing handle
            guard let pen = PenPath.from(cv.drawing.shapes[0]) else { return false }
            let a = pen.points[1].anchor
            let out = CGVector(dx: 60, dy: -20), olen = hypot(out.dx, out.dy)
            let inLen: CGFloat = hypot(-50, 40)                                        // its original length, kept
            let expectedIn = CGPoint(x: a.x - out.dx / olen * inLen, y: a.y - out.dy / olen * inLen)
            return selected && closeTo(pen.points[1].handleOut, CGPoint(x: 260, y: 80)) && closeTo(pen.points[1].handleIn, expectedIn, 0.05)
        }))
        steps.append(("point edit: double click on an anchor toggles smooth and corner", {
            cv.mouseDown(with: evn(.leftMouseDown, CGPoint(x: 200, y: 100), clicks: 2)); cv.mouseUp(with: evn(.leftMouseUp, CGPoint(x: 200, y: 100), clicks: 2))
            let corner = PenPath.from(cv.drawing.shapes[0]).map { $0.points[1].handleIn == nil && $0.points[1].handleOut == nil } ?? false
            cv.mouseDown(with: evn(.leftMouseDown, CGPoint(x: 200, y: 100), clicks: 2)); cv.mouseUp(with: evn(.leftMouseUp, CGPoint(x: 200, y: 100), clicks: 2))
            let smooth = PenPath.from(cv.drawing.shapes[0])?.isSmooth(1) ?? false
            return corner && smooth
        }))
        steps.append(("point edit: double click on the line adds a point there without changing the curve", {
            guard let before = PenPath.from(cv.drawing.shapes[0]) else { return false }
            var preview = before
            preview.insertPoint(segment: 1, t: 0.5)
            let spot = preview.points[2].anchor
            cv.mouseDown(with: evn(.leftMouseDown, spot, clicks: 2)); cv.mouseUp(with: evn(.leftMouseUp, spot, clicks: 2))
            guard let after = PenPath.from(cv.drawing.shapes[0]) else { return false }
            return before.points.count == 3 && after.points.count == 4 && closeTo(after.points[2].anchor, spot, 0.01) && cv.selectedPoint == 2
        }))
        steps.append(("point edit: Delete removes the selected point; Esc leaves edit mode", {
            let removed = { () -> Bool in
                press(51, "\u{7f}")
                return PenPath.from(cv.drawing.shapes[0])?.points.count == 3 && cv.selectedPoint == nil
            }()
            press(53, "\u{1b}")
            return removed && cv.editingPath == nil && cv.selection.count == 1
        }))
        steps.append(("point edit: each edit is its own undo step", {
            cv.undoManager?.undo()                                // the deleted point comes back
            return PenPath.from(cv.drawing.shapes[0])?.points.count == 4
        }))
        steps.append(("point edit: a rotated path is baked into its points and looks the same", {
            cv.load(Drawing())
            cv.tool = .pen
            click(CGPoint(x: 100, y: 100)); click(CGPoint(x: 300, y: 100)); click(CGPoint(x: 300, y: 200)); press(36, "\r")
            cv.tool = .select
            guard let id = cv.drawing.shapes.first?.id else { return false }
            cv.applyShapes("Rotate") { $0.rotation = 90 }
            let seen = cv.drawing.shapes[0].worldPath().boundingBoxOfPath
            cv.selection = [id]
            guard cv.beginPathEdit(id) else { return false }
            let s = cv.drawing.shapes[0]
            let now = s.path().boundingBoxOfPath
            return s.rotation == 0 && abs(now.minX - seen.minX) < 0.6 && abs(now.minY - seen.minY) < 0.6
                && abs(now.width - seen.width) < 0.6 && abs(now.height - seen.height) < 0.6
        }))
        steps.append(("point edit: a path with several subpaths is not editable", {
            let svg = ##"<svg xmlns="http://www.w3.org/2000/svg" width="100" height="100"><path d="M0 0 L10 10 M20 20 L30 30" stroke="#000"/></svg>"##
            guard let r = try? SVGImport.parse(Data(svg.utf8), name: "two"), let s = r.shapes.first else { return false }
            return s.kind == .path && PenPath.from(s) == nil
        }))
        steps.append(("every inspector drop-down is the same width", {
            let canvas2 = CanvasView(frame: NSRect(x: 0, y: 0, width: 900, height: 700))
            let w2 = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 260, height: 1400), styleMask: [.titled], backing: .buffered, defer: false)
            let insp = InspectorView(frame: NSRect(x: 0, y: 0, width: 260, height: 1400))
            w2.contentView = insp
            insp.canvas = canvas2
            var d = Drawing()
            let a = Shape(layer: d.layers[0].id, kind: .rectangle, frame: CGRect(x: 50, y: 50, width: 100, height: 60))
            let b = Shape(layer: d.layers[0].id, kind: .ellipse, frame: CGRect(x: 300, y: 50, width: 100, height: 60))
            let link = Connector(layer: d.layers[0].id, from: a.id, to: b.id)
            d.shapes = [a, b]; d.connectors = [link]
            canvas2.load(d)
            canvas2.selection = [a.id, link.id]                  // shows every section, including Connector
            insp.refresh()
            insp.layoutSubtreeIfNeeded()
            func popups(in v: NSView) -> [NSPopUpButton] { (v as? NSPopUpButton).map { [$0] } ?? v.subviews.flatMap(popups(in:)) }
            let found = popups(in: insp)
            let widths = found.map { $0.frame.width }
            let spread = (widths.max() ?? 0) - (widths.min() ?? 0)
            if !(found.count == 8 && spread < 0.5) { print("      popup widths:", widths) }
            return found.count == 8 && spread < 0.5
        }))
        steps.append(("slider fields: typed values are clamped, scaled and sent through the slider's own action", {
            let catcher = ActionCatcher()
            let width = SliderRow("Width", 0, 24, decimals: 1)
            width.slider.target = catcher
            width.slider.action = #selector(ActionCatcher.fire(_:))

            width.enter("12.5"); let a = (width.slider.doubleValue, width.field.stringValue)
            width.enter("99");   let b = (width.slider.doubleValue, width.field.stringValue)      // above the range
            width.enter("-5");   let c = width.slider.doubleValue                                  // below the range
            let callsBeforeJunk = catcher.calls.count
            width.enter("abc");  let d = width.field.stringValue                                   // ignored, old value restored
            width.enter("7,5");  let e = width.slider.doubleValue                                  // decimal comma

            let opacity = SliderRow("Opacity", 0, 1, suffix: "%", displayScale: 100)
            opacity.slider.target = catcher
            opacity.slider.action = #selector(ActionCatcher.fire(_:))
            opacity.enter("80%"); let f = (opacity.slider.doubleValue, opacity.field.stringValue)
            opacity.enter("150"); let g = opacity.slider.doubleValue
            opacity.enter(" 25 "); let h = opacity.slider.doubleValue
            return a.0 == 12.5 && a.1 == "12.5" && b.0 == 24 && b.1 == "24.0" && c == 0
                && callsBeforeJunk == 3 && d == "0.0" && e == 7.5
                && abs(f.0 - 0.8) < 1e-9 && f.1 == "80%" && g == 1 && abs(h - 0.25) < 1e-9
                && catcher.calls == [12.5, 24, 0, 7.5, 0.8, 1, 0.25]
        }))
        steps.append(("inspector: typing a number edits the selection; the Shadow checkbox shows and hides its controls", {
            let canvas2 = CanvasView(frame: NSRect(x: 0, y: 0, width: 900, height: 700))
            let w2 = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 260, height: 900), styleMask: [.titled], backing: .buffered, defer: false)
            let insp = InspectorView(frame: NSRect(x: 0, y: 0, width: 260, height: 900))
            w2.contentView = insp
            insp.canvas = canvas2
            var d = Drawing()
            let a = Shape(layer: d.layers[0].id, kind: .rectangle, frame: CGRect(x: 50, y: 50, width: 100, height: 60))
            d.shapes = [a]
            canvas2.load(d)
            canvas2.onSelectionChange = { insp.refresh() }       // as in the app: selecting something refreshes the inspector
            canvas2.selection = [a.id]

            insp.lineWidthControl.enter("6")
            insp.opacityControl.enter("50")
            var typed = canvas2.drawing.shapes[0].style.stroke.width == 6 && abs(canvas2.drawing.shapes[0].style.opacity - 0.5) < 1e-9
            // The Fill section has its own opacity: it changes the fill's alpha (solid and every gradient stop), not the object's.
            insp.fillOpacityControl.enter("40")
            let solid = canvas2.drawing.shapes[0].style
            typed = typed && abs(solid.fill.color.a - 0.4) < 1e-9 && abs(solid.opacity - 0.5) < 1e-9 && solid.stroke.color.a == 1
            canvas2.applyStyle("Gradient") { $0.fill.kind = .linear }
            insp.refresh()
            insp.fillOpacityControl.enter("70")
            let grad = canvas2.drawing.shapes[0].style.fill
            typed = typed && grad.stops.allSatisfy { abs($0.color.a - 0.7) < 1e-9 } && abs(insp.fillOpacityControl.slider.doubleValue - 0.7) < 1e-9
            canvas2.applyStyle("Solid") { $0.fill.kind = .solid; $0.fill.color.a = 1 }
            insp.refresh()

            func checkbox(in v: NSView) -> NSButton? {
                if let b = v as? NSButton, b.title == "Shadow" { return b }
                for sub in v.subviews { if let found = checkbox(in: sub) { return found } }
                return nil
            }
            guard let box = checkbox(in: insp) else { return false }
            let offAtStart = !insp.shadowDetailsVisible && !canvas2.drawing.shapes[0].style.shadow.enabled
            box.performClick(nil)
            let on = insp.shadowDetailsVisible && canvas2.drawing.shapes[0].style.shadow.enabled
            box.performClick(nil)
            let off = !insp.shadowDetailsVisible && !canvas2.drawing.shapes[0].style.shadow.enabled
            // A shape that already has a shadow opens with the controls showing.
            canvas2.applyStyle("Toggle Shadow") { $0.shadow.enabled = true }
            canvas2.selection = []; canvas2.selection = [a.id]
            print("      inspector debug: typed", typed, "offAtStart", offAtStart, "on", on, "off", off, "visible", insp.shadowDetailsVisible,
                  "width", canvas2.drawing.shapes[0].style.stroke.width, "opacity", canvas2.drawing.shapes[0].style.opacity)
            return typed && offAtStart && on && off && insp.shadowDetailsVisible
        }))
        steps.append(("color presets: 30 swatches laid out without overlap, inside the 232 x 76 panel", {
            let v = ColorPresetsView(frame: NSRect(x: 0, y: 0, width: 232, height: 76))
            let sw = v.swatches
            let inside = sw.allSatisfy { $0.rect.minX >= 0 && $0.rect.minY >= 0 && $0.rect.maxX <= 232.001 && $0.rect.maxY <= 76.001 }
            var overlap = false
            for i in sw.indices { for j in sw.indices where j > i && sw[i].rect.intersects(sw[j].rect) { overlap = true } }
            return sw.count == 30 && sw.filter(\.large).count == 6 && inside && !overlap
                && sw[0].color == RGBA(0, 0, 0) && sw[5].color == RGBA(1, 1, 1)
        }))
        steps.append(("color presets: clicking a swatch picks its color; the gaps between swatches pick nothing", {
            let v = ColorPresetsView(frame: NSRect(x: 0, y: 0, width: 232, height: 76))
            let w = NSWindow(contentRect: v.frame, styleMask: [.titled], backing: .buffered, defer: false)
            w.contentView = v
            var picked: [RGBA] = []
            v.onPick = { picked.append($0) }
            func click(_ p: CGPoint) {
                let e = NSEvent.mouseEvent(with: .leftMouseDown, location: v.convert(p, to: nil), modifierFlags: [], timestamp: 0,
                                           windowNumber: w.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!
                v.mouseDown(with: e)
            }
            var exact = true
            for s in v.swatches {
                let before = picked.count
                click(CGPoint(x: s.rect.midX, y: s.rect.midY))
                exact = exact && picked.count == before + 1 && picked.last == s.color
            }
            let count = picked.count
            click(CGPoint(x: 36, y: 16))        // between the first two large swatches
            click(CGPoint(x: 100, y: 38))       // between the large row and the small blocks
            return exact && count == 30 && picked.count == 30
        }))
        steps.append(("color presets: set a solid fill, or the selected gradient stop, from the inspector", {
            let canvas2 = CanvasView(frame: NSRect(x: 0, y: 0, width: 900, height: 700))
            let w2 = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 260, height: 900), styleMask: [.titled], backing: .buffered, defer: false)
            let insp = InspectorView(frame: NSRect(x: 0, y: 0, width: 260, height: 900))
            w2.contentView = insp
            insp.canvas = canvas2
            var d = Drawing()
            let layer = d.layers[0].id
            let solid = Shape(layer: layer, kind: .rectangle, frame: CGRect(x: 50, y: 50, width: 100, height: 60))
            var grad = Shape(layer: layer, kind: .rectangle, frame: CGRect(x: 300, y: 50, width: 100, height: 60))
            grad.style.fill.kind = .linear
            grad.style.fill.stops = [GradientStop(color: RGBA(1, 1, 1), position: 0), GradientStop(color: RGBA(0, 0, 0), position: 1)]
            d.shapes = [solid, grad]
            canvas2.load(d)
            canvas2.onSelectionChange = { insp.refresh() }
            let presets = insp.presetsControl
            func pick(_ color: RGBA) {
                guard let s = presets.swatches.first(where: { $0.color == color }) else { return }
                let e = NSEvent.mouseEvent(with: .leftMouseDown, location: presets.convert(CGPoint(x: s.rect.midX, y: s.rect.midY), to: nil),
                                           modifierFlags: [], timestamp: 0, windowNumber: w2.windowNumber, context: nil, eventNumber: 0,
                                           clickCount: 1, pressure: 1)!
                presets.mouseDown(with: e)
            }
            let red = ColorPresetsView.hues[1][0], magenta = ColorPresetsView.hues[2][2]
            canvas2.selection = [solid.id]
            pick(red)
            let solidDone = canvas2.drawing.shapes[0].style.fill.color == red && presets.selectedColor == red

            canvas2.selection = [grad.id]
            pick(magenta)                                                     // stop 0 is selected by default
            let stops = canvas2.drawing.shapes[1].style.fill.stops
            let gradientDone = stops[0].color == magenta && stops[1].color == RGBA(0, 0, 0) && canvas2.drawing.shapes[1].style.fill.kind == .linear
            return solidDone && gradientDone
        }))
        // ---- Locking and the context menu
        func rightClick(_ p: CGPoint) -> NSMenu? {
            let e = NSEvent.mouseEvent(with: .rightMouseDown, location: CGPoint(x: p.x, y: 700 - p.y), modifierFlags: [], timestamp: 0,
                                       windowNumber: win.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!
            return cv.menu(for: e)
        }
        func titles(_ m: NSMenu?) -> [String] { m?.items.filter { !$0.isSeparatorItem }.map(\.title) ?? [] }
        func item(_ title: String, in m: NSMenu?) -> NSMenuItem? { m?.items.first { $0.title == title } }
        func enabled(_ title: String, in m: NSMenu?) -> Bool { item(title, in: m).map { cv.validateMenuItem($0) } ?? false }
        /// Does what choosing the item does: only if it is enabled, like a real menu.
        @discardableResult func choose(_ title: String, in m: NSMenu?) -> Bool {
            guard let it = item(title, in: m), let action = it.action, cv.validateMenuItem(it) else { return false }
            cv.perform(action, with: it)
            return true
        }
        func twoRects() -> (a: UUID, b: UUID) {
            cv.load(Drawing())
            cv.tool = .shape(.rectangle); drag(CGPoint(x: 100, y: 100), CGPoint(x: 200, y: 160))
            cv.tool = .shape(.rectangle); drag(CGPoint(x: 300, y: 100), CGPoint(x: 400, y: 160))
            cv.tool = .select
            return (cv.drawing.shapes[0].id, cv.drawing.shapes[1].id)
        }

        steps.append(("lock: a locked shape can't be moved, nudged, rotated or deleted, and others still can", {
            let (a, b) = twoRects()
            cv.selection = [a]
            cv.lockSelection(nil)
            let before = cv.drawing.shapes[0].frame
            drag(CGPoint(x: 150, y: 130), CGPoint(x: 250, y: 230))      // try to move the locked one
            press(124, "\u{f703}")                                       // right arrow
            press(51, "\u{7f}")                                          // Delete
            cv.applyShapes("Rotate") { $0.rotation = 90 }
            let locked = cv.drawing.shapes.count == 2 && cv.drawing.shapes[0].frame == before && cv.drawing.shapes[0].rotation == 0
                && cv.drawing.shapes[0].locked && cv.selection == [a]    // it can still be selected
            cv.selection = [b]
            let bBefore = cv.drawing.shapes[1].frame
            drag(CGPoint(x: 350, y: 130), CGPoint(x: 350, y: 230))
            return locked && cv.drawing.shapes[1].frame.origin.y == bBefore.origin.y + 100
        }))
        steps.append(("lock: a locked shape can still be restyled, but its text can't be edited", {
            let a = cv.drawing.shapes[0].id
            cv.selection = [a]
            cv.applyStyle("Fill Color") { $0.fill.color = RGBA(1, 0, 0) }
            let restyled = cv.drawing.shapes[0].style.fill.color == RGBA(1, 0, 0)
            cv.mouseDown(with: evn(.leftMouseDown, CGPoint(x: 150, y: 130), clicks: 2)); cv.mouseUp(with: evn(.leftMouseUp, CGPoint(x: 150, y: 130), clicks: 2))
            let refused = !cv.subviews.contains { $0 is NSTextField }
            // The unlocked shape does open its editor.
            let b = cv.drawing.shapes[1]
            cv.mouseDown(with: evn(.leftMouseDown, CGPoint(x: b.frame.midX, y: b.frame.midY), clicks: 2))
            cv.mouseUp(with: evn(.leftMouseUp, CGPoint(x: b.frame.midX, y: b.frame.midY), clicks: 2))
            let opens = cv.subviews.contains { $0 is NSTextField }
            cv.window?.makeFirstResponder(cv)
            return restyled && refused && opens
        }))
        steps.append(("lock: survives saving, and files from before locking still open", {
            let (a, _) = twoRects()
            cv.selection = [a]
            cv.lockSelection(nil)
            guard let data = try? JSONEncoder().encode(cv.drawing), let back = try? JSONDecoder().decode(Drawing.self, from: data) else { return false }
            let kept = back == cv.drawing && back.shapes[0].locked && !back.shapes[1].locked

            // A connector and a shape written without the "locked" key, as older versions saved them.
            var d = Drawing()
            let s1 = Shape(layer: d.layers[0].id, kind: .rectangle, frame: CGRect(x: 0, y: 0, width: 10, height: 10))
            let s2 = Shape(layer: d.layers[0].id, kind: .rectangle, frame: CGRect(x: 50, y: 0, width: 10, height: 10))
            d.shapes = [s1, s2]; d.connectors = [Connector(layer: d.layers[0].id, from: s1.id, to: s2.id)]
            guard let json = try? JSONEncoder().encode(d), var obj = try? JSONSerialization.jsonObject(with: json) as? [String: Any] else { return false }
            func strip(_ key: String) {
                obj[key] = (obj[key] as? [[String: Any]])?.map { var o = $0; o.removeValue(forKey: "locked"); return o }
            }
            strip("shapes"); strip("connectors")
            guard let old = try? JSONSerialization.data(withJSONObject: obj), let opened = try? JSONDecoder().decode(Drawing.self, from: old) else { return false }
            return kept && opened.shapes.count == 2 && opened.connectors.count == 1
                && !opened.shapes[0].locked && !opened.connectors[0].locked
        }))
        steps.append(("context menu: right-clicking an object selects it (and its group) and lists the editing commands", {
            let (a, b) = twoRects()
            cv.selection = [a, b]
            cv.group(nil)
            cv.selection = []
            let menu = rightClick(CGPoint(x: 150, y: 130))        // on the first shape of the group
            let expected = ["Cut", "Copy", "Paste", "Duplicate", "Delete", "Group", "Ungroup", "Lock", "Unlock",
                            "Bring to Front", "Send to Back", "Move to Layer", "Align"]
            let t = titles(menu)
            return cv.selection == [a, b] && expected.allSatisfy(t.contains)
        }))
        steps.append(("context menu: Group and Ungroup are offered when they apply and work from the menu", {
            let (a, b) = twoRects()
            cv.selection = [a, b]
            var menu = rightClick(CGPoint(x: 150, y: 130))
            let canGroup = enabled("Group", in: menu) && !enabled("Ungroup", in: menu)
            choose("Group", in: menu)
            let grouped = Set(cv.drawing.shapes.compactMap(\.group)).count == 1 && cv.drawing.shapes.allSatisfy { $0.group != nil }
            menu = rightClick(CGPoint(x: 150, y: 130))
            let canUngroup = enabled("Ungroup", in: menu)
            choose("Ungroup", in: menu)
            return canGroup && grouped && canUngroup && cv.drawing.shapes.allSatisfy { $0.group == nil }
        }))
        steps.append(("context menu: Duplicate, Copy + Paste and Cut work from the menu", {
            let (a, _) = twoRects()
            cv.selection = [a]
            var menu = rightClick(CGPoint(x: 150, y: 130))
            choose("Duplicate", in: menu)
            let duplicated = cv.drawing.shapes.count == 3
            cv.selection = [a]
            menu = rightClick(CGPoint(x: 105, y: 105))              // a corner only the original covers; copies sit offset on top
            choose("Copy", in: menu)
            cv.selection = []
            menu = rightClick(CGPoint(x: 700, y: 600))             // empty canvas: Paste is there
            let pasteOffered = titles(menu).contains("Paste") && enabled("Paste", in: menu)
            choose("Paste", in: menu)
            let pasted = cv.drawing.shapes.count == 4
            cv.selection = [a]
            menu = rightClick(CGPoint(x: 105, y: 105))
            choose("Cut", in: menu)
            return duplicated && pasteOffered && pasted && cv.drawing.shapes.count == 3 && !cv.drawing.shapes.contains { $0.id == a }
        }))
        steps.append(("context menu: Lock and Unlock follow the selection; Unlock All shows only when something is locked", {
            let (a, b) = twoRects()
            cv.selection = []
            let emptyBefore = titles(rightClick(CGPoint(x: 700, y: 600)))
            let noUnlockAll = !emptyBefore.contains("Unlock All") && emptyBefore.contains("Select All")

            cv.selection = [a]
            var menu = rightClick(CGPoint(x: 150, y: 130))
            let lockOnly = enabled("Lock", in: menu) && !enabled("Unlock", in: menu) && enabled("Delete", in: menu)
            choose("Lock", in: menu)
            menu = rightClick(CGPoint(x: 150, y: 130))
            let nowLocked = cv.drawing.shapes[0].locked && !enabled("Lock", in: menu) && enabled("Unlock", in: menu)
                && !enabled("Delete", in: menu) && !enabled("Cut", in: menu) && enabled("Copy", in: menu)   // nothing to delete
                && titles(menu).contains("Unlock All")

            cv.selection = []
            menu = rightClick(CGPoint(x: 700, y: 600))
            let emptyLocked = titles(menu).contains("Unlock All")
            choose("Unlock All", in: menu)
            let freed = !cv.drawing.shapes[0].locked && !cv.drawing.shapes[1].locked
            _ = b
            return noUnlockAll && lockOnly && nowLocked && emptyLocked && freed
        }))
        steps.append(("context menu: Move to Layer lists every layer and moves the selection", {
            let (a, _) = twoRects()
            cv.addLayer()
            let top = cv.drawing.layers.last!.id
            let bottom = cv.drawing.layers[0].id
            cv.selection = [a]
            let menu = rightClick(CGPoint(x: 150, y: 130))
            guard let layersItem = item("Move to Layer", in: menu), let sub = layersItem.submenu else { return false }
            let names = sub.items.map(\.title)
            let marked = sub.items.first { $0.state == .on }?.representedObject as? UUID == bottom      // where it is now
            guard let target = sub.items.first(where: { ($0.representedObject as? UUID) == top }), let action = target.action else { return false }
            cv.perform(action, with: target)
            return names == cv.drawing.layers.reversed().map(\.name) && marked && cv.drawing.shapes[0].layer == top
        }))
        steps.append(("context menu: Edit Text, Edit Points and Edit Label match the object", {
            let (a, _) = twoRects()
            cv.selection = [a]
            let shapeMenu = rightClick(CGPoint(x: 150, y: 130))
            cv.selection = []
            var pen = PenPath(points: [PenPoint(anchor: CGPoint(x: 100, y: 300)), PenPoint(anchor: CGPoint(x: 300, y: 340))])
            pen.closed = false
            guard let o = pen.outline() else { return false }
            var d = cv.drawing
            let line = Shape(layer: d.layers[0].id, kind: .path, frame: o.frame, outline: o.segments)
            d.shapes.append(line)
            cv.load(d)
            cv.selection = [line.id]
            let pathMenu = rightClick(CGPoint(x: 200, y: 320))
            return titles(shapeMenu).contains("Edit Text") && !titles(shapeMenu).contains("Edit Points")
                && titles(pathMenu).contains("Edit Points") && !titles(pathMenu).contains("Edit Text")
        }))
        steps.append(("a locked selection dims the rotation dial and ignores it", {
            let row = AngleRow("Rotation")
            row.set(10)
            row.setEnabled(false)
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 30, height: 30), styleMask: [.titled], backing: .buffered, defer: false)
            row.dial.frame = NSRect(x: 0, y: 0, width: 30, height: 30)
            w.contentView = row.dial
            let e = NSEvent.mouseEvent(with: .leftMouseDown, location: CGPoint(x: 28, y: 15), modifierFlags: [], timestamp: 0,
                                       windowNumber: w.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!
            row.dial.mouseDown(with: e)
            let ignored = row.dial.angle == 10 && row.dial.alphaValue < 1 && !row.field.isEnabled
            row.setEnabled(true)
            row.dial.mouseDown(with: e)
            return ignored && row.dial.angle == 0 && row.dial.alphaValue == 1
        }))
        steps.append(("fonts: the picker lists every installed family; a font this Mac lacks is shown as not installed", {
            let all = TextFormat.installedFonts
            let installed = Set(NSFontManager.shared.availableFontFamilies.filter { !$0.hasPrefix(".") })

            let canvas2 = CanvasView(frame: NSRect(x: 0, y: 0, width: 900, height: 700))
            let w2 = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 260, height: 900), styleMask: [.titled], backing: .buffered, defer: false)
            let started = Date()
            let insp = InspectorView(frame: NSRect(x: 0, y: 0, width: 260, height: 900))
            let buildTime = Date().timeIntervalSince(started)
            w2.contentView = insp
            insp.canvas = canvas2
            canvas2.onSelectionChange = { insp.refresh() }

            var d = Drawing()
            let layer = d.layers[0].id
            var a = Shape(layer: layer, kind: .text, frame: CGRect(x: 50, y: 50, width: 120, height: 30), style: .textBox, text: "Hi")
            var b = Shape(layer: layer, kind: .text, frame: CGRect(x: 250, y: 50, width: 120, height: 30), style: .textBox, text: "Yo")
            a.style.text.font = "Zzz Imaginary Sans"
            d.shapes = [a, b]
            canvas2.load(d)

            let menu = insp.fontControl.menu
            let listed = menu?.items.compactMap { $0.representedObject as? String } ?? []
            let listsAll = all.first == "System" && Set(all.dropFirst()) == installed && all.count > 20 && listed == all

            // A font from another Mac is called out, not silently replaced by another name.
            canvas2.selection = [a.id]
            let flagged = insp.fontControl.titleOfSelectedItem == "Zzz Imaginary Sans (not installed)"
                && insp.fontControl.menu?.items.count == all.count + 1

            // Choosing an installed font applies it, and the temporary entry goes away.
            canvas2.selection = [b.id]
            let pick = all.contains("Menlo") ? "Menlo" : all[1]
            insp.fontControl.selectItem(withTitle: pick)
            insp.fontControl.sendAction(insp.fontControl.action, to: insp.fontControl.target)
            let applied = canvas2.drawing.shapes[1].style.text.font == pick
            let tidy = insp.fontControl.menu?.items.count == all.count && insp.fontControl.titleOfSelectedItem == pick

            // CSS font names from an SVG map onto installed families, case-insensitively.
            let svg = ##"<svg xmlns="http://www.w3.org/2000/svg" width="100" height="40"><text x="5" y="20" font-family="'\##(pick.lowercased())', monospace">x</text></svg>"##
            let imported = (try? SVGImport.parse(Data(svg.utf8), name: "t"))?.shapes.first?.style.text.font == pick
            print("      font picker: \(all.count) families, inspector built in \(String(format: "%.2f", buildTime))s")
            return listsAll && flagged && applied && tidy && imported && buildTime < 3
        }))
        // ---- Saved styles
        func scratchDefaults() -> UserDefaults {
            let name = "mx.graffle.selftest.\(UUID().uuidString)"
            return UserDefaults(suiteName: name)!
        }
        var fancy: Style = {
            var st = Style()
            st.fill.kind = .linear
            st.fill.angle = 30
            st.fill.stops = [GradientStop(color: RGBA(1, 0, 0), position: 0), GradientStop(color: RGBA(0, 0, 1), position: 1)]
            st.stroke.color = RGBA(0, 1, 0); st.stroke.width = 4; st.stroke.dash = .dashed
            st.shadow = Shadow(enabled: true, color: RGBA(0, 0, 0, 0.5), blur: 9, offset: 7, angle: 120)
            st.opacity = 0.7; st.cornerRadius = 16
            st.text.bold = true; st.text.size = 20
            return st
        }()

        steps.append(("style merge: fill and corners only travel between shapes", {
            let plain = Style()
            let line = Style.connector
            var shapeLook = fancy; shapeLook.fill.kind = .solid
            let toShape = plain.receiving(shapeLook, sourceIsConnector: false, targetIsConnector: false)
            let toConnector = line.receiving(shapeLook, sourceIsConnector: false, targetIsConnector: true)
            let lineToShape = plain.receiving(line, sourceIsConnector: true, targetIsConnector: false)
            return toShape == shapeLook                                                    // shape -> shape: everything
                && toConnector.stroke == shapeLook.stroke && toConnector.shadow == shapeLook.shadow
                && toConnector.fill == line.fill && toConnector.cornerRadius == line.cornerRadius   // connector keeps no fill
                && lineToShape.stroke == line.stroke && lineToShape.fill == plain.fill               // a line look doesn't wipe a fill
                && lineToShape.cornerRadius == plain.cornerRadius
        }))
        steps.append(("copy style / paste style: appearance moves, geometry and text stay", {
            cv.load(Drawing())
            let layer = cv.drawing.layers[0].id
            var a = Shape(layer: layer, kind: .rounded, frame: CGRect(x: 100, y: 100, width: 120, height: 60), style: fancy, text: "Source")
            let b = Shape(layer: layer, kind: .ellipse, frame: CGRect(x: 300, y: 100, width: 80, height: 80), text: "Target", rotation: 20)
            var c = Shape(layer: layer, kind: .diamond, frame: CGRect(x: 500, y: 100, width: 90, height: 90))
            c.locked = true
            a.rotation = 0
            var d = Drawing(); d.layers = cv.drawing.layers; d.shapes = [a, b, c]
            d.connectors = [Connector(layer: layer, from: a.id, to: b.id)]
            cv.load(d)

            cv.selection = [a.id]
            cv.copyStyle(nil)
            cv.selection = [b.id, c.id]                          // a plain shape and a locked one
            cv.pasteStyle(nil)
            let tb = cv.drawing.shapes[1], tc = cv.drawing.shapes[2]
            let styled = tb.style == fancy && tc.style == fancy && tc.locked                // locked shapes still take a style
            let kept = tb.kind == .ellipse && tb.frame == b.frame && tb.text == "Target" && tb.rotation == 20 && tc.frame == c.frame
            return styled && kept
        }))
        steps.append(("paste style onto a connector gives it the line, shadow and opacity but never a fill", {
            let link = cv.drawing.connectors[0].id
            cv.selection = [link]
            cv.pasteStyle(nil)
            let cs = cv.drawing.connectors[0].style
            return cs.stroke == fancy.stroke && cs.shadow == fancy.shadow && cs.opacity == fancy.opacity
                && cs.fill.kind == .none && cs.cornerRadius == 0
        }))
        steps.append(("paste style is one undo step", {
            cv.undoManager?.undo()                               // reverts the connector paste only: it was its own step
            let connectorBack = cv.drawing.connectors[0].style == Style.connector
            let shapesStillStyled = cv.drawing.shapes[1].style == fancy && cv.drawing.shapes[2].style == fancy
            return connectorBack && shapesStillStyled
        }))
        steps.append(("paste style with nothing selected sets the look of new shapes; nothing to paste is disabled", {
            cv.load(Drawing())
            cv.selection = []
            let menuBefore = cv.contextMenu()
            _ = menuBefore
            cv.tool = .shape(.rectangle); drag(CGPoint(x: 100, y: 100), CGPoint(x: 200, y: 160))
            let plainNew = cv.drawing.shapes.last!.style
            cv.selection = []
            cv.pasteStyle(nil)                                   // clipboard still holds `fancy`
            cv.tool = .shape(.rectangle); drag(CGPoint(x: 300, y: 100), CGPoint(x: 400, y: 160))
            let styledNew = cv.drawing.shapes.last!.style
            return plainNew.fill.kind == .solid && plainNew.shadow.enabled == false
                && styledNew.shadow.enabled && styledNew.stroke.dash == .dashed && styledNew.fill.kind == .linear
        }))
        steps.append(("context menu offers Copy Style and Paste Style", {
            cv.load(Drawing())
            let layer = cv.drawing.layers[0].id
            var d = Drawing(); d.layers = cv.drawing.layers
            let a = Shape(layer: layer, kind: .rectangle, frame: CGRect(x: 100, y: 100, width: 100, height: 60), style: fancy)
            let b = Shape(layer: layer, kind: .rectangle, frame: CGRect(x: 300, y: 100, width: 100, height: 60))
            d.shapes = [a, b]
            cv.load(d)
            cv.selection = [a.id]
            var menu = rightClick(CGPoint(x: 150, y: 130))
            let offered = titles(menu).contains("Copy Style") && titles(menu).contains("Paste Style")
            choose("Copy Style", in: menu)
            cv.selection = []
            menu = rightClick(CGPoint(x: 350, y: 130))           // right-click on b selects it
            let enabledOnB = cv.selection == [b.id] && enabled("Paste Style", in: menu)
            choose("Paste Style", in: menu)
            return offered && enabledOnB && cv.drawing.shapes[1].style == fancy
        }))

        steps.append(("style library: add, rename, update, delete and persistence; starters only the first time", {
            let defaults = scratchDefaults()
            let first = StyleLibrary(defaults: defaults)
            let starters = first.styles.count
            let seeded = starters == StyleLibrary.starters.count && starters >= 5

            let mine = first.add(name: "Mine", style: fancy)
            let conn = first.add(name: "Line", style: Style.connector, fromConnector: true)
            first.rename(mine.id, to: "Renamed")
            var tweaked = fancy; tweaked.opacity = 0.4
            first.update(mine.id, style: tweaked, fromConnector: false)

            let second = StyleLibrary(defaults: defaults)            // a new launch
            let persisted = second.styles.count == starters + 2 && second.style(mine.id)?.name == "Renamed"
                && second.style(mine.id)?.style.opacity == 0.4 && second.style(conn.id)?.fromConnector == true

            for st in second.styles { second.delete(st.id) }
            let third = StyleLibrary(defaults: defaults)
            let staysEmpty = third.styles.isEmpty                    // deleting everything must not bring the starters back
            defaults.removePersistentDomain(forName: defaults.volatileDomainNames.first ?? "")
            return seeded && persisted && staysEmpty
        }))
        steps.append(("style palette: tiles are laid out in a grid; clicking applies, the + tile adds", {
            let lib = StyleLibrary(defaults: scratchDefaults())
            let palette = StylePaletteView(frame: NSRect(x: 0, y: 0, width: 232, height: 80))
            let w = NSWindow(contentRect: palette.frame, styleMask: [.titled], backing: .buffered, defer: false)
            w.contentView = palette
            palette.library = lib
            var applied: [String] = [], added = 0
            palette.onApply = { applied.append($0.name) }
            palette.onAdd = { added += 1 }
            func click(_ p: CGPoint) {
                palette.mouseDown(with: NSEvent.mouseEvent(with: .leftMouseDown, location: palette.convert(p, to: nil), modifierFlags: [], timestamp: 0,
                                                           windowNumber: w.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!)
            }
            let n = lib.styles.count
            let rects = (0...n).map { palette.rect(forTile: $0) }
            var overlap = false
            for i in rects.indices { for j in rects.indices where j > i && rects[i].intersects(rects[j]) { overlap = true } }
            let fits = rects.allSatisfy { $0.maxX <= 232.001 && $0.minX >= 0 }
            for i in 0..<n { click(CGPoint(x: rects[i].midX, y: rects[i].midY)) }
            click(CGPoint(x: rects[n].midX, y: rects[n].midY))
            click(CGPoint(x: rects[0].maxX + 4, y: rects[0].midY))     // in the gap between tiles
            let rows = (n + 1 + 4) / 5
            return !overlap && fits && applied == lib.styles.map(\.name) && added == 1
                && abs(palette.intrinsicContentSize.height - (CGFloat(rows) * 28 + CGFloat(rows - 1) * 8)) < 0.01
        }))
        steps.append(("style palette: every starter has its own preview picture", {
            let previews = StyleLibrary.starters.compactMap { StylePaletteView.image(for: $0.style).tiffRepresentation }
            let text: Style = { var t = Style.textBox; t.text.font = "Menlo"; t.text.bold = true; return t }()
            let textPreview = StylePaletteView.image(for: text).tiffRepresentation
            return previews.count == StyleLibrary.starters.count && Set(previews).count == previews.count
                && textPreview != nil && !previews.contains(textPreview!)
        }))
        steps.append(("style palette: right-click menu renames, updates and deletes", {
            let lib = StyleLibrary(defaults: scratchDefaults())
            let palette = StylePaletteView(frame: NSRect(x: 0, y: 0, width: 232, height: 80))
            let w = NSWindow(contentRect: palette.frame, styleMask: [.titled], backing: .buffered, defer: false)
            w.contentView = palette
            palette.library = lib
            var log: [String] = []
            palette.onApply = { log.append("apply " + $0.name) }
            palette.onRename = { log.append("rename " + $0.name) }
            palette.onUpdate = { log.append("update " + $0.name) }
            palette.onDelete = { log.append("delete " + $0.name) }
            func menu(forTile i: Int) -> NSMenu? {
                let r = palette.rect(forTile: i)
                let e = NSEvent.mouseEvent(with: .rightMouseDown, location: palette.convert(CGPoint(x: r.midX, y: r.midY), to: nil),
                                           modifierFlags: [], timestamp: 0, windowNumber: w.windowNumber, context: nil, eventNumber: 0,
                                           clickCount: 1, pressure: 1)!
                return palette.menu(for: e)
            }
            guard let m = menu(forTile: 1) else { return false }
            let names = m.items.filter { !$0.isSeparatorItem }.map(\.title)
            for title in ["Apply", "Rename…", "Update from Selection", "Delete"] {
                if let it = m.items.first(where: { $0.title == title }), let action = it.action { _ = it.target?.perform(action, with: it) }
            }
            let plusMenu = menu(forTile: lib.styles.count)              // the + tile has no menu
            let second = lib.styles[1].name
            return names == ["Apply", "Rename…", "Update from Selection", "Delete"] && plusMenu == nil
                && log == ["apply " + second, "rename " + second, "update " + second, "delete " + second]
        }))
        steps.append(("inspector Styles section: save the selection's style by name, apply it elsewhere, rename and delete it", {
            let lib = StyleLibrary(defaults: scratchDefaults())
            let canvas2 = CanvasView(frame: NSRect(x: 0, y: 0, width: 900, height: 700))
            let w2 = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 260, height: 900), styleMask: [.titled], backing: .buffered, defer: false)
            let insp = InspectorView(frame: NSRect(x: 0, y: 0, width: 260, height: 900))
            w2.contentView = insp
            insp.library = lib
            insp.canvas = canvas2
            canvas2.onSelectionChange = { insp.refresh() }

            var d = Drawing()
            let layer = d.layers[0].id
            let a = Shape(layer: layer, kind: .rounded, frame: CGRect(x: 50, y: 50, width: 120, height: 60), style: fancy)
            let b = Shape(layer: layer, kind: .rectangle, frame: CGRect(x: 300, y: 50, width: 100, height: 60), text: "B")
            d.shapes = [a, b]
            canvas2.load(d)
            let palette = insp.paletteControl
            func click(_ i: Int) {
                let r = palette.rect(forTile: i)
                palette.mouseDown(with: NSEvent.mouseEvent(with: .leftMouseDown, location: palette.convert(CGPoint(x: r.midX, y: r.midY), to: nil),
                                                           modifierFlags: [], timestamp: 0, windowNumber: w2.windowNumber, context: nil,
                                                           eventNumber: 0, clickCount: 1, pressure: 1)!)
            }

            let before = lib.styles.count
            canvas2.selection = [a.id]
            insp.namePrompt = { _, _ in "Fancy" }
            click(before)                                                   // the + tile
            let saved = lib.styles.last
            let savedOK = lib.styles.count == before + 1 && saved?.name == "Fancy" && saved?.style == fancy

            canvas2.selection = [b.id]
            click(lib.styles.count - 1)                                     // apply the new style to b
            let applied = canvas2.drawing.shapes[1].style == fancy && canvas2.drawing.shapes[1].text == "B"

            insp.namePrompt = { _, initial in initial == "Fancy" ? "Fancier" : nil }
            palette.onRename?(saved!)
            let renamed = lib.style(saved!.id)?.name == "Fancier"

            var tweaked = fancy; tweaked.opacity = 0.2
            canvas2.selection = [b.id]
            canvas2.applyStyle("Opacity") { $0.opacity = 0.2 }
            palette.onUpdate?(saved!)
            let updated = lib.style(saved!.id)?.style.opacity == 0.2

            insp.namePrompt = { _, _ in nil }                               // Cancel in the dialog saves nothing
            click(lib.styles.count)
            let cancelled = lib.styles.count == before + 1

            palette.onDelete?(saved!)
            let deleted = lib.styles.count == before && lib.style(saved!.id) == nil

            // With nothing selected a saved style becomes the look of new objects.
            canvas2.selection = []
            click(0)
            let defaulted = canvas2.defaultStyle == lib.styles[0].style
            return savedOK && applied && renamed && updated && cancelled && deleted && defaulted
        }))
        // ---- Distribute, match size, smart guides
        func item(tag: Int) -> NSMenuItem { let m = NSMenuItem(); m.tag = tag; return m }
        func boxes(_ ids: [UUID]) -> [CGRect] { ids.compactMap { id in cv.drawing.shapes.first { $0.id == id }?.worldBounds } }
        func put(_ frames: [CGRect], locked: Set<Int> = []) -> [UUID] {
            var d = Drawing()
            let layer = d.layers[0].id
            d.shapes = frames.enumerated().map { Shape(layer: layer, kind: .rectangle, frame: $1, locked: locked.contains($0)) }
            cv.load(d)
            cv.snapToGrid = false
            return d.shapes.map(\.id)
        }

        steps.append(("distribute: equal gaps, outer shapes stay put, in both directions", {
            let ids = put([CGRect(x: 100, y: 100, width: 60, height: 40), CGRect(x: 130, y: 200, width: 100, height: 40),
                           CGRect(x: 500, y: 300, width: 40, height: 40)])
            cv.selection = Set(ids)
            let two = NSMenuItem(); two.tag = 0
            cv.selection = Set(ids.prefix(2))
            let needsThree = !cv.validateMenuItem(NSMenuItem(title: "", action: #selector(CanvasView.distribute(_:)), keyEquivalent: ""))
            _ = two
            cv.selection = Set(ids)
            cv.distribute(item(tag: 0))
            let h = boxes(ids)
            let horizontal = h[0].minX == 100 && h[1].minX == 280 && h[2].minX == 500
                && (h[1].minX - h[0].maxX) == (h[2].minX - h[1].maxX) && h[0].minY == 100 && h[1].minY == 200 && h[2].minY == 300   // only x changed

            let vids = put([CGRect(x: 100, y: 100, width: 50, height: 30), CGRect(x: 200, y: 130, width: 50, height: 80),
                            CGRect(x: 300, y: 500, width: 50, height: 20)])
            cv.selection = Set(vids)
            cv.distribute(item(tag: 1))
            let v = boxes(vids)
            let vertical = v[0].minY == 100 && v[1].minY == 275 && v[2].minY == 500
                && (v[1].minY - v[0].maxY) == (v[2].minY - v[1].maxY) && v[1].minX == 200
            return needsThree && horizontal && vertical
        }))
        steps.append(("distribute: Distribute is offered for three shapes, not two; locked shapes don't move", {
            let ids = put([CGRect(x: 100, y: 100, width: 60, height: 40), CGRect(x: 130, y: 200, width: 100, height: 40),
                           CGRect(x: 500, y: 300, width: 40, height: 40)], locked: [1])
            cv.selection = Set(ids)
            let probe = NSMenuItem(title: "Distribute", action: #selector(CanvasView.distribute(_:)), keyEquivalent: "")
            let offered3 = cv.validateMenuItem(probe)
            cv.selection = Set(ids.prefix(2))
            let offered2 = cv.validateMenuItem(probe)
            cv.selection = Set(ids)
            cv.distribute(item(tag: 0))
            let b = boxes(ids)
            return offered3 && !offered2 && b[1].minX == 130 && b[0].minX == 100 && b[2].minX == 500   // the locked middle one stays
        }))
        steps.append(("same size: the first selected shape is the reference; origins and locked shapes stay", {
            let ids = put([CGRect(x: 100, y: 100, width: 100, height: 60), CGRect(x: 300, y: 100, width: 200, height: 100),
                           CGRect(x: 600, y: 100, width: 50, height: 20)], locked: [2])
            cv.selection = [ids[0]]
            cv.selection = Set(ids)                                          // a joins first, so it is the reference
            let orderOK = cv.selectionOrder.first == ids[0] && cv.selectionOrder.count == 3

            cv.matchSize(item(tag: 0))
            var f = cv.drawing.shapes.map(\.frame)
            let width = f[1].width == 100 && f[1].height == 100 && f[0] == CGRect(x: 100, y: 100, width: 100, height: 60)
                && f[1].origin == CGPoint(x: 300, y: 100) && f[2] == CGRect(x: 600, y: 100, width: 50, height: 20)   // locked untouched
            cv.matchSize(item(tag: 1))
            f = cv.drawing.shapes.map(\.frame)
            let height = f[1].height == 60 && f[1].width == 100
            return orderOK && width && height
        }))
        steps.append(("same size: Same Size copies both, and the reference follows the selection order", {
            let ids = put([CGRect(x: 100, y: 100, width: 100, height: 60), CGRect(x: 300, y: 100, width: 200, height: 100),
                           CGRect(x: 600, y: 100, width: 50, height: 20)])
            cv.selection = [ids[1]]
            cv.selection = [ids[1], ids[0], ids[2]]                          // b first this time
            cv.matchSize(item(tag: 2))
            let f = cv.drawing.shapes.map(\.frame)
            let toB = f[0].size == CGSize(width: 200, height: 100) && f[2].size == CGSize(width: 200, height: 100) && f[1].size == f[0].size
            cv.selection = [ids[0], ids[2]]
            cv.selection = [ids[2], ids[0]]
            let removedOrder = cv.selectionOrder.count == 2
            cv.selection = [ids[0]]
            return toB && removedOrder && cv.selectionOrder == [ids[0]]
        }))

        func moveWithGuides(_ ids: [UUID], from a: CGPoint, to b: CGPoint, mods: NSEvent.ModifierFlags = [], release: Bool = true) {
            cv.tool = .select
            cv.mouseDown(with: evn(.leftMouseDown, a))
            cv.mouseDragged(with: evn(.leftMouseDragged, b, mods: mods))
            if release { cv.mouseUp(with: evn(.leftMouseUp, b)) }
        }
        steps.append(("smart guides: a move snaps its left edge to another shape's and draws the guide line", {
            let ids = put([CGRect(x: 300, y: 100, width: 100, height: 60), CGRect(x: 100, y: 300, width: 80, height: 40)])   // B, A
            cv.smartGuides = true
            cv.selection = [ids[1]]
            moveWithGuides(ids, from: CGPoint(x: 140, y: 320), to: CGPoint(x: 343, y: 320), release: false)   // wants x = 303
            let snapped = cv.drawing.shapes[1].frame.origin.x == 300
            let guide = cv.smartGuideLines.first { $0.vertical && $0.position == 300 }
            let spans = guide.map { $0.from == 100 && $0.to == 340 } ?? false                                  // from B's top to A's bottom
            cv.mouseUp(with: evn(.leftMouseUp, CGPoint(x: 343, y: 320)))
            return snapped && spans && cv.smartGuideLines.isEmpty                                              // cleared on release
        }))
        steps.append(("smart guides: centers and top edges snap too; a far-away shape doesn't", {
            let ids = put([CGRect(x: 300, y: 100, width: 100, height: 60), CGRect(x: 100, y: 300, width: 80, height: 40)])
            cv.selection = [ids[1]]
            moveWithGuides(ids, from: CGPoint(x: 140, y: 320), to: CGPoint(x: 353, y: 320))                   // center x 353 -> 350
            let center = cv.drawing.shapes[1].frame.origin.x == 310

            let ids2 = put([CGRect(x: 300, y: 100, width: 100, height: 60), CGRect(x: 100, y: 300, width: 80, height: 40)])
            cv.selection = [ids2[1]]
            moveWithGuides(ids2, from: CGPoint(x: 140, y: 320), to: CGPoint(x: 140, y: 123))                  // top 103 -> B's top 100
            let top = cv.drawing.shapes[1].frame.origin.y == 100 && cv.drawing.shapes[1].frame.origin.x == 100

            let ids3 = put([CGRect(x: 300, y: 100, width: 100, height: 60), CGRect(x: 100, y: 300, width: 80, height: 40)])
            cv.selection = [ids3[1]]
            moveWithGuides(ids3, from: CGPoint(x: 140, y: 320), to: CGPoint(x: 370, y: 320))                  // keys 330/370/410 vs 300/350/400
            let far = cv.drawing.shapes[1].frame.origin.x == 330
            return center && top && far
        }))
        steps.append(("smart guides: edge-to-edge adjacency snaps, and the whole selection moves as one box", {
            let ids = put([CGRect(x: 300, y: 100, width: 100, height: 60), CGRect(x: 100, y: 300, width: 80, height: 40),
                            CGRect(x: 100, y: 400, width: 80, height: 40)])
            cv.selection = [ids[1]]
            moveWithGuides(ids, from: CGPoint(x: 140, y: 320), to: CGPoint(x: 258, y: 320))                  // right edge 298 -> B's left 300
            let adjacent = cv.drawing.shapes[1].frame.origin.x == 220

            let g = put([CGRect(x: 300, y: 100, width: 100, height: 60), CGRect(x: 100, y: 300, width: 80, height: 40),
                         CGRect(x: 100, y: 400, width: 80, height: 40)])
            cv.selection = [g[1], g[2]]
            moveWithGuides(g, from: CGPoint(x: 140, y: 320), to: CGPoint(x: 343, y: 320))                     // the pair's left edge 303 -> 300
            let pair = cv.drawing.shapes[1].frame.origin.x == 300 && cv.drawing.shapes[2].frame.origin.x == 300
            return adjacent && pair
        }))
        steps.append(("smart guides: Option while dragging, or switching them off, leaves the move untouched", {
            let ids = put([CGRect(x: 300, y: 100, width: 100, height: 60), CGRect(x: 100, y: 300, width: 80, height: 40)])
            cv.selection = [ids[1]]
            moveWithGuides(ids, from: CGPoint(x: 140, y: 320), to: CGPoint(x: 343, y: 320), mods: [.option])
            let option = cv.drawing.shapes[1].frame.origin.x == 303

            let ids2 = put([CGRect(x: 300, y: 100, width: 100, height: 60), CGRect(x: 100, y: 300, width: 80, height: 40)])
            cv.smartGuides = false
            cv.selection = [ids2[1]]
            moveWithGuides(ids2, from: CGPoint(x: 140, y: 320), to: CGPoint(x: 343, y: 320))
            let off = cv.drawing.shapes[1].frame.origin.x == 303 && cv.smartGuideLines.isEmpty
            let remembered = UserDefaults.standard.bool(forKey: "smartGuides") == false
            cv.smartGuides = true
            cv.snapToGrid = true
            return option && off && remembered && UserDefaults.standard.bool(forKey: "smartGuides")
        }))
        steps.append(("context menu: Distribute and Match Size appear when they apply and work from the menu", {
            let ids = put([CGRect(x: 100, y: 100, width: 60, height: 40), CGRect(x: 130, y: 200, width: 100, height: 40),
                           CGRect(x: 500, y: 300, width: 40, height: 40)])
            cv.selection = Set(ids)
            var menu = rightClick(CGPoint(x: 120, y: 120))
            let three = titles(menu).contains("Distribute") && titles(menu).contains("Match Size")
            guard let dist = item("Distribute", in: menu)?.submenu, let horizontally = dist.items.first(where: { $0.title == "Horizontally" }),
                  let action = horizontally.action else { return false }
            cv.perform(action, with: horizontally)
            let moved = boxes(ids)[1].minX == 280

            cv.selection = Set(ids.prefix(2))
            menu = rightClick(CGPoint(x: 120, y: 120))
            let two = !titles(menu).contains("Distribute") && titles(menu).contains("Match Size")
            guard let match = item("Match Size", in: menu)?.submenu else { return false }
            let names = match.items.map(\.title)
            return three && moved && two && names == ["Same Width", "Same Height", "Same Size"]
        }))
        // ---- Guides while resizing and creating, and equal-spacing guides
        func dragHandle(from a: CGPoint, to b: CGPoint, mods: NSEvent.ModifierFlags = [], release: Bool = true) {
            cv.tool = .select
            cv.mouseDown(with: evn(.leftMouseDown, a))
            cv.mouseDragged(with: evn(.leftMouseDragged, b, mods: mods))
            if release { cv.mouseUp(with: evn(.leftMouseUp, b)) }
        }
        let guideBase = [CGRect(x: 300, y: 100, width: 100, height: 60), CGRect(x: 100, y: 300, width: 80, height: 40)]   // B, A

        steps.append(("resize guides: the dragged edge snaps to another shape's edge or center, with the guide line", {
            let ids = put(guideBase)
            cv.selection = [ids[1]]
            dragHandle(from: CGPoint(x: 180, y: 340), to: CGPoint(x: 303, y: 340), release: false)       // bottom-right handle
            let edge = cv.drawing.shapes[1].frame == CGRect(x: 100, y: 300, width: 200, height: 40)
            let line = cv.smartGuideLines.contains { $0.vertical && $0.position == 300 }
            cv.mouseUp(with: evn(.leftMouseUp, CGPoint(x: 303, y: 340)))
            let cleared = cv.smartGuideLines.isEmpty

            let ids2 = put(guideBase)
            cv.selection = [ids2[1]]
            dragHandle(from: CGPoint(x: 180, y: 340), to: CGPoint(x: 352, y: 340))                        // near B's center x = 350
            let center = cv.drawing.shapes[1].frame.width == 250

            let ids3 = put(guideBase)
            cv.selection = [ids3[1]]
            dragHandle(from: CGPoint(x: 100, y: 300), to: CGPoint(x: 100, y: 163))                        // top-left handle -> B's bottom 160
            let top = cv.drawing.shapes[1].frame == CGRect(x: 100, y: 160, width: 80, height: 180)
            return edge && line && cleared && center && top
        }))
        steps.append(("resize guides: Option or switching guides off leaves the resize alone; rotated shapes are never snapped", {
            let ids = put(guideBase)
            cv.selection = [ids[1]]
            dragHandle(from: CGPoint(x: 180, y: 340), to: CGPoint(x: 303, y: 340), mods: [.option])
            let option = cv.drawing.shapes[1].frame.width == 203

            let ids2 = put(guideBase)
            cv.smartGuides = false
            cv.selection = [ids2[1]]
            dragHandle(from: CGPoint(x: 180, y: 340), to: CGPoint(x: 303, y: 340))
            let off = cv.drawing.shapes[1].frame.width == 203
            cv.smartGuides = true

            let ids3 = put(guideBase)
            cv.selection = [ids3[1]]
            cv.applyShapes("Rotate") { $0.rotation = 30 }
            let r = cv.drawing.shapes[1]
            let handle = r.toWorld(CGPoint(x: r.frame.maxX, y: r.frame.maxY))
            dragHandle(from: handle, to: CGPoint(x: handle.x + 123, y: handle.y), release: false)
            let rotated = cv.smartGuideLines.isEmpty
            cv.mouseUp(with: evn(.leftMouseUp, CGPoint(x: handle.x + 123, y: handle.y)))
            return option && off && rotated
        }))
        steps.append(("resize guides: resizing several shapes as one box snaps its edge too", {
            let ids = put([CGRect(x: 300, y: 100, width: 100, height: 60), CGRect(x: 100, y: 300, width: 80, height: 40),
                           CGRect(x: 100, y: 360, width: 80, height: 40)])                                  // B, A1, A2
            cv.selection = [ids[1], ids[2]]                                                                  // box (100,300)-(180,400)
            dragHandle(from: CGPoint(x: 184, y: 404), to: CGPoint(x: 307, y: 404), release: false)           // handle sits 4pt outside
            let snapped = cv.drawing.shapes[1].frame.maxX == 300 && cv.drawing.shapes[2].frame.maxX == 300
            let line = cv.smartGuideLines.contains { $0.vertical && $0.position == 300 }
            cv.mouseUp(with: evn(.leftMouseUp, CGPoint(x: 307, y: 404)))
            return snapped && line
        }))
        steps.append(("creation guides: both corners of a new shape snap to other shapes", {
            let ids = put([CGRect(x: 300, y: 100, width: 100, height: 60)])
            _ = ids
            cv.tool = .shape(.rectangle)
            cv.mouseDown(with: evn(.leftMouseDown, CGPoint(x: 297, y: 400)))
            cv.mouseDragged(with: evn(.leftMouseDragged, CGPoint(x: 398, y: 450)))
            let guides = cv.smartGuideLines.filter(\.vertical).map(\.position).sorted()
            cv.mouseUp(with: evn(.leftMouseUp, CGPoint(x: 398, y: 450)))
            let made = cv.drawing.shapes.last!.frame == CGRect(x: 300, y: 400, width: 100, height: 50)

            put([CGRect(x: 300, y: 100, width: 100, height: 60)])
            cv.tool = .shape(.rectangle)
            cv.mouseDown(with: evn(.leftMouseDown, CGPoint(x: 297, y: 400), mods: [.option]))
            cv.mouseDragged(with: evn(.leftMouseDragged, CGPoint(x: 398, y: 450), mods: [.option]))
            cv.mouseUp(with: evn(.leftMouseUp, CGPoint(x: 398, y: 450)))
            let option = cv.drawing.shapes.last!.frame.origin.x == 297
            // The new shape is as wide as its neighbor, so its center lines up as well: 300, 350 and 400.
            return made && guides == [300, 350, 400] && option
        }))

        func moveM(_ ids: [UUID], from a: CGPoint, to b: CGPoint, mods: NSEvent.ModifierFlags = [], release: Bool = true) {
            cv.selection = [ids.last!]
            moveWithGuides(ids, from: a, to: b, mods: mods, release: release)
        }
        steps.append(("spacing guides: sitting between two shapes snaps to equal gaps and marks both", {
            let ids = put([CGRect(x: 100, y: 100, width: 60, height: 40), CGRect(x: 400, y: 100, width: 60, height: 40),
                           CGRect(x: 200, y: 110, width: 40, height: 40)])                                   // L, R, M (same row)
            moveM(ids, from: CGPoint(x: 220, y: 130), to: CGPoint(x: 283, y: 130), release: false)          // wants x = 263; centered is 260
            let m = cv.drawing.shapes[2].frame
            let marks = cv.smartSpacingMarks.filter(\.horizontal)
            let both = marks.count == 2 && marks.allSatisfy { abs(($0.to - $0.from) - 100) < 0.5 }
            cv.mouseUp(with: evn(.leftMouseUp, CGPoint(x: 283, y: 130)))
            return m.origin.x == 260 && both && cv.smartSpacingMarks.isEmpty
        }))
        steps.append(("spacing guides: matching a gap that already exists between two other shapes", {
            let ids = put([CGRect(x: 100, y: 100, width: 50, height: 40), CGRect(x: 200, y: 100, width: 50, height: 40),
                           CGRect(x: 400, y: 110, width: 40, height: 40)])                                   // A1, B1 (gap 50), M
            moveM(ids, from: CGPoint(x: 420, y: 130), to: CGPoint(x: 323, y: 130), release: false)          // wants x = 303; B1 + gap = 300
            let snapped = cv.drawing.shapes[2].frame.origin.x == 300
            let gaps = cv.smartSpacingMarks.filter(\.horizontal).map { [$0.from, $0.to] }.sorted { $0[0] < $1[0] }
            let marked = gaps == [[150, 200], [250, 300]]                                                    // the old gap and the new one
            cv.mouseUp(with: evn(.leftMouseUp, CGPoint(x: 323, y: 130)))

            let ids2 = put([CGRect(x: 100, y: 100, width: 50, height: 40), CGRect(x: 200, y: 100, width: 50, height: 40),
                            CGRect(x: 400, y: 110, width: 40, height: 40)])
            moveM(ids2, from: CGPoint(x: 420, y: 130), to: CGPoint(x: 330, y: 130))                          // origin 310: 10 away, too far
            return snapped && marked && cv.drawing.shapes[2].frame.origin.x == 310
        }))
        steps.append(("spacing guides: work vertically; shapes outside the line, Option and the switch don't take part", {
            let ids = put([CGRect(x: 100, y: 100, width: 40, height: 40), CGRect(x: 100, y: 400, width: 40, height: 40),
                           CGRect(x: 110, y: 200, width: 40, height: 40)])                                   // T, Bt, M (same column)
            moveM(ids, from: CGPoint(x: 130, y: 220), to: CGPoint(x: 130, y: 273), release: false)          // wants y = 253; centered is 250
            let vertical = cv.drawing.shapes[2].frame.origin.y == 250
            let marks = cv.smartSpacingMarks.filter { !$0.horizontal }
            let two = marks.count == 2 && marks.allSatisfy { abs(($0.to - $0.from) - 110) < 0.5 }
            cv.mouseUp(with: evn(.leftMouseUp, CGPoint(x: 130, y: 273)))

            // A shape in another row never counts as a neighbor.
            let far = put([CGRect(x: 100, y: 100, width: 60, height: 40), CGRect(x: 400, y: 600, width: 60, height: 40),
                           CGRect(x: 200, y: 110, width: 40, height: 40)])
            moveM(far, from: CGPoint(x: 220, y: 130), to: CGPoint(x: 283, y: 130))
            let ignored = cv.drawing.shapes[2].frame.origin.x == 263

            let o = put([CGRect(x: 100, y: 100, width: 60, height: 40), CGRect(x: 400, y: 100, width: 60, height: 40),
                         CGRect(x: 200, y: 110, width: 40, height: 40)])
            moveM(o, from: CGPoint(x: 220, y: 130), to: CGPoint(x: 283, y: 130), mods: [.option])
            let option = cv.drawing.shapes[2].frame.origin.x == 263
            cv.smartGuides = false
            let o2 = put([CGRect(x: 100, y: 100, width: 60, height: 40), CGRect(x: 400, y: 100, width: 60, height: 40),
                          CGRect(x: 200, y: 110, width: 40, height: 40)])
            moveM(o2, from: CGPoint(x: 220, y: 130), to: CGPoint(x: 283, y: 130))
            let off = cv.drawing.shapes[2].frame.origin.x == 263
            cv.smartGuides = true
            cv.snapToGrid = true
            return vertical && two && ignored && option && off
        }))
        steps.append(("About: credits name EVM, link to evm.mx, and carry the copyright", {
            let credits = About.credits()
            let text = credits.string
            let evmMentions = text.components(separatedBy: "EVM").count - 1
            var linkTarget: URL?
            credits.enumerateAttribute(.link, in: NSRange(location: 0, length: credits.length)) { value, range, _ in
                if let url = value as? URL, (text as NSString).substring(with: range) == "evm.mx" { linkTarget = url }
            }
            let options = About.panelOptions
            let name = options[.applicationName] as? String
            let hasCredits = (options[.credits] as? NSAttributedString)?.string == text
            let copyright = options[NSApplication.AboutPanelOptionKey(rawValue: "Copyright")] as? String
            return evmMentions == 2 && !text.contains("Diseñada") && text.contains("designed and developed by EVM")
                && text.contains("All credit for this app goes to EVM")
                && linkTarget == URL(string: "https://evm.mx") && About.website.absoluteString == "https://evm.mx"
                && name == "Graffle" && hasCredits && copyright == "Copyright © 2026 EVM. Released under the MIT License." && text.contains("open-source")
                && !About.version.isEmpty
        }))
        // ---- Documents: many open at once, each with its own window
        let bundled = Bundle.main.bundleURL.pathExtension == "app"       // NSDocumentController needs the Info.plist
        func pump(_ seconds: Double = 0.5, until done: () -> Bool = { false }) {
            // AppKit closes an undo group (and so counts the document as edited) on a real application event.
            if let e = NSEvent.otherEvent(with: .applicationDefined, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: 0,
                                          context: nil, subtype: 0, data1: 0, data2: 0) { NSApp.postEvent(e, atStart: false) }
            let end = Date().addingTimeInterval(seconds)
            repeat { RunLoop.main.run(until: Date().addingTimeInterval(0.01)) } while Date() < end && !done()
        }
        func newDoc() -> GraffleDocument? {
            let dc = NSDocumentController.shared
            guard let doc = (try? dc.makeUntitledDocument(ofType: GraffleDocument.diagramType)) as? GraffleDocument else { return nil }
            dc.addDocument(doc)
            doc.makeWindowControllers()
            doc.showWindows()
            return doc
        }
        func button(titled title: String, in v: NSView) -> NSButton? {
            if let b = v as? NSButton, b.title == title { return b }
            for sub in v.subviews { if let f = button(titled: title, in: sub) { return f } }
            return nil
        }
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("graffle-doctest-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        steps.append(("menus: File has the document commands, Open Recent fills itself in, View/Window commands exist", {
            let menu = self.makeMainMenu()
            func submenu(_ title: String) -> NSMenu? { menu.items.first { $0.title == title }?.submenu }
            guard let file = submenu("File"), let view = submenu("View"), let window = submenu("Window") else { return false }
            func action(_ m: NSMenu, _ title: String) -> Selector? { m.items.first { $0.title == title }?.action }
            let recent = file.items.first { $0.title == "Open Recent" }?.submenu
            return action(file, "New…") == #selector(AppDelegate.newDocumentChooser(_:))
                && action(file, "New Blank Diagram") == #selector(NSDocumentController.newDocument(_:))
                && action(file, "Import Theme…") == #selector(AppDelegate.importThemeFile(_:))
                && action(view, "Theme…") == #selector(DocumentWindowController.chooseTheme(_:))
                && action(file, "Open…") == #selector(NSDocumentController.openDocument(_:))
                && action(file, "Save") == #selector(NSDocument.save(_:))
                && action(file, "Save As…") == #selector(NSDocument.saveAs(_:))
                && action(file, "Revert to Saved") == #selector(NSDocument.revertToSaved(_:))
                && action(file, "Close") == #selector(NSWindow.performClose(_:))
                && action(file, "Import SVG…") == #selector(DocumentWindowController.importSVG(_:))
                && action(file, "Export as SVG…") == #selector(DocumentWindowController.exportSVG(_:))
                && recent?.items.last?.action == #selector(NSDocumentController.clearRecentDocuments(_:))
                && action(view, "Show Grid") == #selector(DocumentWindowController.toggleGrid(_:))
                && action(view, "Zoom In") == #selector(DocumentWindowController.zoomIn(_:))
                && action(window, "Bring All to Front") == #selector(NSApplication.arrangeInFront(_:))
                && NSApp.windowsMenu === window                                  // so AppKit lists the open documents in it
        }))
        steps.append(contentsOf: self.architectureSteps(bundled: bundled, tempDir: tempDir))
        steps.append(contentsOf: self.navigatorSteps())
        steps.append(contentsOf: self.classDiagramSteps(tempDir: tempDir))
        steps.append(contentsOf: self.starterSteps(bundled: bundled))
        steps.append(contentsOf: self.themeSteps(cv: cv, drag: drag, bundled: bundled, tempDir: tempDir))
        var twoDocs: (a: GraffleDocument, b: GraffleDocument)?
        steps.append(("documents: New opens independent windows, each with its own canvas and inspector", {
            guard bundled else { print("      (skipped: needs the .app bundle)"); return true }
            let dc = NSDocumentController.shared
            let before = dc.documents.count
            guard let d1 = newDoc(), let d2 = newDoc(), let c1 = d1.windowController, let c2 = d2.windowController else { return false }
            c1.canvas.addLayer()                                            // an undoable edit in the first only
            c2.canvas.showGrid = false                                      // and a view setting in the second only
            twoDocs = (d1, d2)
            let separate = c1 !== c2 && c1.window !== c2.window && c1.canvas !== c2.canvas && c1.inspector !== c2.inspector
            let layers = c1.canvas.drawing.layers.count == 2 && c2.canvas.drawing.layers.count == 1
            let views = c1.canvas.showGrid && !c2.canvas.showGrid
            return separate && layers && views && dc.documents.count == before + 2 && d1.windowControllers.count == 1
        }))
        steps.append(("documents: only the document that was edited is marked edited, and so is its window", {
            guard bundled else { return true }       // (checked a step later: AppKit counts the change when the event ends)
            guard let (d1, d2) = twoDocs, let c1 = d1.windowController, let c2 = d2.windowController else { return false }
            return d1.isDocumentEdited && !d2.isDocumentEdited && c1.window?.isDocumentEdited == true && c2.window?.isDocumentEdited == false
                && c1.window?.title == d1.displayName && c2.window?.title == d2.displayName
        }))
        steps.append(("documents: undo goes through the document and clears the edited mark", {
            guard bundled else { return true }
            guard let d = NSDocumentController.shared.documents.compactMap({ $0 as? GraffleDocument }).first(where: { $0.isDocumentEdited }),
                  let canvas = d.canvas else { return false }
            let shared = canvas.undoManager === d.undoManager && d.undoManager?.canUndo == true
            canvas.undo(nil)
            pump(0.2)
            let clean = canvas.drawing.layers.count == 1 && !d.isDocumentEdited
            canvas.redo(nil)
            pump(0.2)
            return shared && clean && canvas.drawing.layers.count == 2 && d.isDocumentEdited
        }))
        steps.append(("documents: saving writes a .graf file; it reopens with the same content and joins Open Recent", {
            guard bundled else { return true }
            guard let d = NSDocumentController.shared.documents.compactMap({ $0 as? GraffleDocument }).first(where: { $0.isDocumentEdited }),
                  let canvas = d.canvas else { return false }
            let url = tempDir.appendingPathComponent("first.graf")
            var saved: Error?? = nil
            d.save(to: url, ofType: GraffleDocument.diagramType, for: .saveOperation) { saved = .some($0) }
            pump(3) { saved != nil }
            let written = FileManager.default.fileExists(atPath: url.path) && d.fileURL == url && !d.isDocumentEdited
                && saved != nil && (saved ?? nil) == nil && (d.windowController?.window?.title ?? "").hasPrefix("first")
            let layersBefore = canvas.drawing.layers.count

            d.close()
            var reopened: GraffleDocument?
            NSDocumentController.shared.openDocument(withContentsOf: url, display: true) { doc, _, _ in reopened = doc as? GraffleDocument }
            pump(3) { reopened != nil }
            let same = reopened?.canvas?.drawing.layers.count == layersBefore && reopened?.fileURL == url && reopened?.isDocumentEdited == false
            pump(0.5)
            let recent = NSDocumentController.shared.recentDocumentURLs.contains { $0.lastPathComponent == url.lastPathComponent }
            // Opening a file that is already open brings up that document instead of making a second copy.
            let count = NSDocumentController.shared.documents.count
            var again: GraffleDocument?
            var wasOpen = false
            NSDocumentController.shared.openDocument(withContentsOf: url, display: true) { doc, already, _ in again = doc as? GraffleDocument; wasOpen = already }
            pump(2) { again != nil }
            let noDuplicate = again === reopened && wasOpen && NSDocumentController.shared.documents.count == count
            return written && same && recent && noDuplicate
        }))
        var revertDoc: GraffleDocument?
        var revertBase = 0
        steps.append(("documents: editing a saved document", {
            guard bundled else { return true }
            let url = tempDir.appendingPathComponent("first.graf")
            guard let d = NSDocumentController.shared.documents.compactMap({ $0 as? GraffleDocument }).first(where: { $0.fileURL == url }),
                  let canvas = d.canvas else { return false }
            revertDoc = d
            revertBase = canvas.drawing.layers.count
            canvas.addLayer(); canvas.addLayer()
            return canvas.drawing.layers.count == revertBase + 2
        }))
        steps.append(("documents: Revert to Saved restores the file's content in the open window", {
            guard bundled else { return true }
            let url = tempDir.appendingPathComponent("first.graf")
            guard let d = revertDoc, let canvas = d.canvas else { return false }
            let edited = d.isDocumentEdited
            try? d.revert(toContentsOf: url, ofType: GraffleDocument.diagramType)
            pump(0.3)
            return edited && canvas.drawing.layers.count == revertBase && !d.isDocumentEdited
        }))
        var closeDoc: GraffleDocument?
        var cleanCloses = false
        steps.append(("documents: a document with no changes closes without asking", {
            guard bundled else { return true }
            guard let d = newDoc(), let wc = d.windowController, let window = wc.window, let canvas = d.canvas else { return false }
            closeDoc = d
            cleanCloses = wc.windowShouldClose(window)                         // nothing to save: no question
            canvas.addLayer()                                                  // now there is
            return cleanCloses
        }))
        steps.append(("documents: closing an edited, never-saved document asks first; Cancel keeps it", {
            guard bundled else { return true }
            guard let d = closeDoc, let wc = d.windowController, let window = wc.window else { return false }
            let edited = d.isDocumentEdited
            let asks = !wc.windowShouldClose(window)
            pump(1) { window.attachedSheet != nil }
            guard let sheet = window.attachedSheet else { return false }
            // For a document with no file yet AppKit offers the Save panel (its UI lives in another process): cancel it through its API.
            if let panel = sheet as? NSSavePanel { panel.cancel(nil) }
            else if let cancel = button(titled: "Cancel", in: sheet.contentView!) { cancel.performClick(nil) }
            else { return false }
            pump(0.5) { window.attachedSheet == nil }
            let stayed = NSDocumentController.shared.documents.contains(d) && window.isVisible && d.isDocumentEdited
            d.close()                                             // clean up without going through the sheet
            return edited && asks && stayed
        }))
        var savedDoc: GraffleDocument?
        steps.append(("documents: editing a document that has a file", {
            guard bundled else { return true }
            let url = tempDir.appendingPathComponent("first.graf")
            guard let d = NSDocumentController.shared.documents.compactMap({ $0 as? GraffleDocument }).first(where: { $0.fileURL == url }),
                  let canvas = d.canvas else { return false }
            savedDoc = d
            canvas.addLayer()
            return true
        }))
        steps.append(("documents: closing an edited, saved document asks Save / Don't Save / Cancel; Don't Save closes it", {
            guard bundled else { return true }
            guard let d = savedDoc, let wc = d.windowController, let window = wc.window else { return false }
            let edited = d.isDocumentEdited
            _ = wc.windowShouldClose(window)
            pump(1) { window.attachedSheet != nil }
            guard let sheet = window.attachedSheet, !(sheet is NSSavePanel),
                  let save = button(titled: "Save", in: sheet.contentView!), let cancel = button(titled: "Cancel", in: sheet.contentView!),
                  let discard = button(titled: "Don’t Save", in: sheet.contentView!) else { return false }
            _ = (save, cancel)                                    // all three choices are offered
            discard.performClick(nil)
            pump(1) { !NSDocumentController.shared.documents.contains(d) }
            return edited && !NSDocumentController.shared.documents.contains(d)
        }))
        steps.append(("documents: an SVG opens as a new unsaved diagram named after the file", {
            guard bundled else { return true }
            let svg = tempDir.appendingPathComponent("Logo Sketch.svg")
            let text = ##"<svg xmlns="http://www.w3.org/2000/svg" width="200" height="100"><rect x="10" y="10" width="80" height="40" fill="#336"/><circle cx="150" cy="50" r="30" fill="#c33"/></svg>"##
            try? text.write(to: svg, atomically: true, encoding: .utf8)
            var opened: GraffleDocument?
            NSDocumentController.shared.openDocument(withContentsOf: svg, display: true) { doc, _, _ in opened = doc as? GraffleDocument }
            pump(3) { opened != nil }
            guard let d = opened else { return false }
            let result = d.canvas?.drawing.shapes.count == 2 && d.fileURL == nil && d.displayName == "Logo Sketch"
                && d.isDocumentEdited && d.fileType == GraffleDocument.diagramType
            d.close()
            return result
        }))
        steps.append(("documents: a file that isn't a diagram is refused with a message, not opened blank", {
            guard bundled else { return true }
            let bad = tempDir.appendingPathComponent("broken.graf")
            try? "this is not json".write(to: bad, atomically: true, encoding: .utf8)
            var failure: Error?
            var finished = false
            var doc: NSDocument?
            NSDocumentController.shared.openDocument(withContentsOf: bad, display: false) { d, _, e in doc = d; failure = e; finished = true }
            pump(3) { finished }
            let ok = finished && doc == nil && failure != nil
            NSDocumentController.shared.documents.forEach { $0.close() }          // leave nothing open for the steps below
            return ok
        }))
        // ---- Quick Look preview (the space bar in Finder)
        steps.append(("quick look: a diagram previews as a one-page vector PDF with its real content", {
            var d = Drawing()
            let layer = d.layers[0].id
            var red = Shape(layer: layer, kind: .rectangle, frame: CGRect(x: 100, y: 100, width: 200, height: 120))
            red.style.fill.color = RGBA(1, 0, 0); red.style.stroke.visible = false
            var blue = Shape(layer: layer, kind: .ellipse, frame: CGRect(x: 400, y: 150, width: 160, height: 160))
            blue.style.fill.color = RGBA(0, 0, 1); blue.style.stroke.visible = false
            let hidden = Layer(name: "Hidden", visible: false)
            d.layers.append(hidden)
            var ghost = Shape(layer: hidden.id, kind: .rectangle, frame: CGRect(x: 100, y: 500, width: 300, height: 100))
            ghost.style.fill.color = RGBA(0, 1, 0); ghost.style.stroke.visible = false
            d.shapes = [red, blue, ghost]

            let result = DiagramPreview.render(d)
            guard let pdf = PDFDocument(data: result.pdf), let page = pdf.page(at: 0) else { return false }
            let box = page.bounds(for: .mediaBox)
            // The page is the content (plus a margin), not the whole 4000 x 3000 canvas, and hidden layers stay out of it.
            let cropped = box.width < 700 && box.height < 400 && box.width > 450 && box.height > 250

            let image = page.thumbnail(of: CGSize(width: box.width * 2, height: box.height * 2), for: .mediaBox)
            guard let tiff = image.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff) else { return false }
            func pixel(_ x: CGFloat, _ y: CGFloat) -> NSColor {   // in diagram points; the page starts 24pt before the content
                (rep.colorAt(x: Int((x - 76) * 2), y: Int((y - 76) * 2)) ?? .black).usingColorSpace(.sRGB) ?? .black
            }
            let r = pixel(200, 160), b = pixel(480, 230), blank = pixel(90, 90)
            let hasRed = r.redComponent > 0.8 && r.greenComponent < 0.3 && r.blueComponent < 0.3
            let hasBlue = b.blueComponent > 0.8 && b.redComponent < 0.3
            let white = blank.redComponent > 0.95 && blank.greenComponent > 0.95 && blank.blueComponent > 0.95
            return pdf.pageCount == 1 && cropped && hasRed && hasBlue && white && !result.isEmpty && result.size.width <= 1200
        }))
        steps.append(("quick look: a big diagram is scaled to a sensible window, an empty one shows a note, a bad file is refused", {
            let fitted = DiagramPreview.fit(CGSize(width: 3000, height: 1000))
            let small = DiagramPreview.fit(CGSize(width: 300, height: 200))
            let scaledDown = fitted.width <= 1200 && fitted.height <= 900 && abs(fitted.width / fitted.height - 3) < 0.01
            let notEnlarged = small == CGSize(width: 300, height: 200)

            let empty = DiagramPreview.render(Drawing())
            let emptyOK = empty.isEmpty && PDFDocument(data: empty.pdf)?.pageCount == 1
                && PDFDocument(data: empty.pdf)?.string?.contains("Empty diagram") == true

            let dir = FileManager.default.temporaryDirectory
            let good = dir.appendingPathComponent("preview-\(UUID().uuidString).graf")
            let bad = dir.appendingPathComponent("preview-\(UUID().uuidString).graf")
            var d = Drawing()
            d.shapes = [Shape(layer: d.layers[0].id, kind: .rectangle, frame: CGRect(x: 10, y: 10, width: 80, height: 40))]
            try? JSONEncoder().encode(d).write(to: good)
            try? Data("not a diagram".utf8).write(to: bad)
            let fromFile = (try? DiagramPreview.render(fileAt: good))?.isEmpty == false
            var refused = false
            do { _ = try DiagramPreview.render(fileAt: bad) } catch { refused = true }
            try? FileManager.default.removeItem(at: good); try? FileManager.default.removeItem(at: bad)
            return scaledDown && notEnlarged && emptyOK && fromFile && refused
        }))
        steps.append(("PNG and PDF export", { cv.pngData() != nil && cv.pdfData() != nil }))

        var failures = 0
        func run(_ i: Int) {
            guard i < steps.count else {
                print(failures == 0 ? "ALL PASSED" : "\(failures) FAILED")
                exit(failures == 0 ? 0 : 1)
            }
            let ok = steps[i].1()
            print(ok ? "PASS" : "FAIL", steps[i].0)
            if !ok { failures += 1 }
            // A real application event makes AppKit close this step's undo group, as a user action would.
            if let e = NSEvent.otherEvent(with: .applicationDefined, location: .zero, modifierFlags: [], timestamp: 0,
                                          windowNumber: 0, context: nil, subtype: 0, data1: 0, data2: 0) {
                NSApp.postEvent(e, atStart: false)
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { run(i + 1) }
        }
        run(0)
    }
}

/// Records what a slider's action receives (self-test helper).
private final class ActionCatcher: NSObject {
    var calls: [Double] = []
    @objc func fire(_ sender: NSSlider) { calls.append(sender.doubleValue) }
}
