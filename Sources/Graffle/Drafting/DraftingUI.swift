import AppKit

/// Drafting menu actions: the drawing scale, dimension lines, exact line lengths and the snapping switches.
extension DocumentWindowController {
    private func number(_ field: NSTextField) -> Double? {
        Double(field.stringValue.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: "."))
    }

    private func labelled(_ title: String, _ control: NSView, width: CGFloat = 130) -> NSStackView {
        let label = NSTextField(labelWithString: title)
        label.alignment = .right
        label.widthAnchor.constraint(equalToConstant: 150).isActive = true
        control.translatesAutoresizingMaskIntoConstraints = false
        control.widthAnchor.constraint(equalToConstant: width).isActive = true
        let row = NSStackView(views: [label, control])
        row.spacing = 8
        return row
    }

    private func form(_ rows: [NSView]) -> NSView {
        let stack = NSStackView(views: rows)
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 8
        stack.frame = NSRect(x: 0, y: 0, width: 300, height: CGFloat(rows.count) * 30)
        return stack
    }

    // MARK: Drawing scale

    /// Drafting -> Drawing Scale…
    @objc func showDrawingScale(_ sender: Any?) {
        guard let window else { return }
        let current = canvas.drawing.scale ?? .standard
        let unit = NSPopUpButton(frame: .zero, pullsDown: false)
        unit.addItems(withTitles: LengthUnit.allCases.map(\.title))
        unit.selectItem(at: LengthUnit.allCases.firstIndex(of: current.unit) ?? 1)
        let mode = NSPopUpButton(frame: .zero, pullsDown: false)
        mode.addItems(withTitles: ["1 point equals", "Printed scale 1 :"])
        let value = NSTextField(string: "")
        let decimals = NSPopUpButton(frame: .zero, pullsDown: false)
        decimals.addItems(withTitles: ["Automatic", "0", "1", "2", "3"])
        decimals.selectItem(at: current.decimals.map { min($0, 3) + 1 } ?? 0)
        let wall = NSTextField(string: "")

        func fill(_ s: DrawingScale) {
            value.stringValue = mode.indexOfSelectedItem == 0 ? String(format: "%g", (s.unitsPerPoint * 1000).rounded() / 1000)
                                                              : String(format: "%g", (s.printRatio * 100).rounded() / 100)
            wall.stringValue = String(format: "%g", ((s.wallThickness ?? s.unit.defaultWall) * 1000).rounded() / 1000)
        }
        fill(current)
        let alert = NSAlert()
        alert.messageText = "Drawing Scale"
        alert.informativeText = "What the drawing stands for in the real world. Dimensions, walls and real-size library items follow it. A printed scale assumes 72 points to an inch of paper."
        alert.accessoryView = form([labelled("Measure in", unit), labelled("Scale", mode), labelled("", value), labelled("Decimals", decimals),
                                    labelled("Wall thickness", wall)])
        alert.addButton(withTitle: "Set")
        alert.addButton(withTitle: "Cancel")
        alert.addButton(withTitle: "Remove Scale")
        alert.beginSheetModal(for: window) { [weak self] response in
            guard let self else { return }
            if response == .alertThirdButtonReturn { self.canvas.setScale(nil); return }
            guard response == .alertFirstButtonReturn else { return }
            let u = LengthUnit.allCases[max(unit.indexOfSelectedItem, 0)]
            guard let v = self.number(value), v > 0 else { NSSound.beep(); return }
            var s = mode.indexOfSelectedItem == 0 ? { var x = DrawingScale(); x.unit = u; x.unitsPerPoint = v; return x }() : DrawingScale.ratio(v, unit: u)
            s.decimals = decimals.indexOfSelectedItem == 0 ? nil : decimals.indexOfSelectedItem - 1
            if let w = self.number(wall), w > 0, abs(w - u.defaultWall) > 1e-9 { s.wallThickness = w }
            self.canvas.setScale(s)
            self.window?.makeFirstResponder(self.canvas)
        }
        alert.window.makeFirstResponder(value)
    }

    // MARK: Dimensions and lines

    @objc func addDimension(_ sender: NSMenuItem) {
        canvas.addDimension(DimensionAxis.allCases[min(max(sender.tag, 0), 2)])
        window?.makeFirstResponder(canvas)
    }

    /// Drafting -> Edit Dimension or Line…
    @objc func editMeasurement(_ sender: Any?) {
        guard let window else { return }
        let scale = canvas.drawing.scale ?? .standard
        if let c = canvas.selectedDimension, let spec = c.dimension {
            let axis = NSPopUpButton(frame: .zero, pullsDown: false)
            axis.addItems(withTitles: DimensionAxis.allCases.map(\.title))
            axis.selectItem(at: DimensionAxis.allCases.firstIndex(of: spec.axis) ?? 0)
            let offset = NSTextField(string: String(format: "%g", (scale.length(spec.offset) * 100).rounded() / 100))
            let text = NSTextField(string: c.text)
            text.placeholderString = "Measured automatically"
            let alert = NSAlert()
            alert.messageText = "Dimension"
            alert.informativeText = "The line sits “distance” \(scale.unit.symbol) above or to the left of what it measures (negative: the other side)."
            alert.accessoryView = form([labelled("Measures", axis), labelled("Distance (\(scale.unit.symbol))", offset), labelled("Text", text, width: 150)])
            alert.addButton(withTitle: "Apply")
            alert.addButton(withTitle: "Cancel")
            alert.beginSheetModal(for: window) { [weak self] response in
                guard let self, response == .alertFirstButtonReturn, let o = self.number(offset) else { return }
                self.canvas.setSelectedDimension(axis: DimensionAxis.allCases[max(axis.indexOfSelectedItem, 0)], offset: scale.points(o),
                                                 text: text.stringValue.trimmingCharacters(in: .whitespaces))
            }
            alert.window.makeFirstResponder(offset)
        } else if let info = canvas.selectedLineInfo {
            let length = NSTextField(string: String(format: "%g", (scale.length(info.length) * 1000).rounded() / 1000))
            let angle = NSTextField(string: String(format: "%g", (info.angle * 100).rounded() / 100))
            let alert = NSAlert()
            alert.messageText = "Line"
            alert.informativeText = "Type an exact length and angle. The line keeps its start point; 0° points right, 90° up."
            alert.accessoryView = form([labelled("Length (\(scale.unit.symbol))", length), labelled("Angle (°)", angle)])
            alert.addButton(withTitle: "Apply")
            alert.addButton(withTitle: "Cancel")
            alert.beginSheetModal(for: window) { [weak self] response in
                guard let self, response == .alertFirstButtonReturn, let l = self.number(length), l > 0, let a = self.number(angle) else { return }
                self.canvas.setSelectedLine(length: scale.points(l), angle: a)
            }
            alert.window.makeFirstResponder(length)
        } else {
            NSSound.beep()
        }
    }

    @objc func toggleOrtho(_ sender: Any?) { canvas.orthoMode.toggle() }
    @objc func toggleObjectSnap(_ sender: Any?) { canvas.objectSnap.toggle() }
    @objc func chooseLineTool(_ sender: NSMenuItem) { canvas.tool = sender.tag == 0 ? .line : .wall; window?.makeFirstResponder(canvas) }
}
