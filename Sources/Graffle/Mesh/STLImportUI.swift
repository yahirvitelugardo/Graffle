import AppKit
import UniformTypeIdentifiers

/// File -> Import STL as Views…
extension AppDelegate {
    @objc func importSTL(_ sender: Any?) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "stl") ?? .data]
        panel.message = "Choose an STL file to draw its views"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let mesh: Mesh
        do { mesh = try STLParser.parse(Data(contentsOf: url)) } catch {
            let alert = NSAlert(error: error)
            alert.messageText = "Could not read “\(url.lastPathComponent)”"
            alert.runModal()
            return
        }
        guard let options = askMeshOptions(for: mesh, name: url.lastPathComponent) else { return }

        let busy = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 280, height: 90), styleMask: [.titled], backing: .buffered, defer: false)
        busy.title = "Drawing the views"
        let label = NSTextField(labelWithString: "Working out \(mesh.triangles.count.formatted()) triangles…")
        let spinner = NSProgressIndicator()
        spinner.style = .bar; spinner.isIndeterminate = true; spinner.startAnimation(nil)
        let stack = NSStackView(views: [label, spinner])
        stack.orientation = .vertical; stack.spacing = 10
        stack.edgeInsets = NSEdgeInsets(top: 16, left: 20, bottom: 16, right: 20)
        busy.contentView = stack
        busy.center(); busy.makeKeyAndOrderFront(nil)

        DispatchQueue.global(qos: .userInitiated).async {
            let drawing = MeshDrawing.build(mesh, options: options)
            DispatchQueue.main.async {
                busy.orderOut(nil)
                GraffleDocument.openNew(drawing: drawing)
            }
        }
    }

    private func askMeshOptions(for mesh: Mesh, name: String) -> MeshViewOptions? {
        var options = MeshViewOptions()
        let unit = NSPopUpButton(frame: .zero, pullsDown: false)
        unit.addItems(withTitles: LengthUnit.allCases.map(\.title))
        unit.selectItem(at: LengthUnit.allCases.firstIndex(of: options.unit) ?? 0)
        let system = NSPopUpButton(frame: .zero, pullsDown: false)
        system.addItems(withTitles: ProjectionSystem.allCases.map(\.title))
        var boxes: [(ViewKind, NSButton)] = ViewKind.allCases.map { kind in
            let b = NSButton(checkboxWithTitle: kind.title, target: nil, action: nil)
            b.state = options.views.contains(kind) ? .on : .off
            return (kind, b)
        }
        let crease = NSTextField(string: "30")
        crease.alignment = .right
        let hidden = NSButton(checkboxWithTitle: "Dashed hidden lines", target: nil, action: nil); hidden.state = .on
        let isoHidden = NSButton(checkboxWithTitle: "Also in the isometric view", target: nil, action: nil); isoHidden.state = .off
        let dims = NSButton(checkboxWithTitle: "Overall dimensions", target: nil, action: nil); dims.state = .on

        func row(_ title: String, _ control: NSView, width: CGFloat) -> NSStackView {
            let label = NSTextField(labelWithString: title)
            label.alignment = .right
            label.widthAnchor.constraint(equalToConstant: 110).isActive = true
            control.translatesAutoresizingMaskIntoConstraints = false
            control.widthAnchor.constraint(equalToConstant: width).isActive = true
            let r = NSStackView(views: [label, control]); r.spacing = 8
            return r
        }
        let grid = NSStackView(views: stride(from: 0, to: boxes.count, by: 2).map { i in
            NSStackView(views: boxes[i..<min(i + 2, boxes.count)].map { $0.1 }).then { $0.distribution = .fillEqually; $0.spacing = 12 }
        })
        grid.orientation = .vertical; grid.alignment = .leading; grid.spacing = 4
        let form = NSStackView(views: [row("File units", unit, width: 170), row("Projection", system, width: 250), row("Views", grid, width: 250),
                                       row("Crease angle (°)", crease, width: 60), row("", hidden, width: 200), row("", isoHidden, width: 200), row("", dims, width: 200)])
        form.orientation = .vertical; form.alignment = .leading; form.spacing = 8
        form.frame = NSRect(x: 0, y: 0, width: 380, height: 280)

        let alert = NSAlert()
        alert.messageText = "Views of “\(name)”"
        alert.informativeText = "\(mesh.triangles.count.formatted()) triangles. STL files carry no units: say what the file is measured in so dimensions read correctly."
        alert.accessoryView = form
        alert.addButton(withTitle: "Draw Views")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return nil }
        options.unit = LengthUnit.allCases[max(unit.indexOfSelectedItem, 0)]
        options.system = ProjectionSystem.allCases[max(system.indexOfSelectedItem, 0)]
        options.views = boxes.filter { $0.1.state == .on }.map(\.0)
        if options.views.isEmpty { options.views = [.front] }
        options.creaseDegrees = min(max(Double(crease.stringValue.replacingOccurrences(of: ",", with: ".")) ?? 30, 1), 89)
        options.hiddenLines = hidden.state == .on
        options.hiddenInIsometric = isoHidden.state == .on
        options.dimensions = dims.state == .on
        boxes.removeAll()
        return options
    }
}

private extension NSStackView {
    func then(_ f: (NSStackView) -> Void) -> NSStackView { f(self); return self }
}
