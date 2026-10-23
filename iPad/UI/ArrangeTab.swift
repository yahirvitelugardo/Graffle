import SwiftUI

/// Geometry, alignment, order, grouping, locking and drafting tools for the selection.
struct ArrangeTab: View {
    @ObservedObject var model: EditorModel

    init(model: EditorModel) { self.model = model }

    private var canvas: CanvasView { model.canvas }

    var body: some View {
        let _ = model.revision
        let shapes = canvas.selectedShapes
        let count = shapes.count
        let unlocked = canvas.selectionHasUnlocked
        let hasSel = !canvas.selection.isEmpty
        let single = (count == 1 && canvas.selection.count == 1) ? shapes.first : nil

        ScrollView {
            VStack(spacing: 16) {
                if let s = single { geometrySection(s) }
                if count >= 2 { alignSection }
                orderSection(hasSel: hasSel, count: count, unlocked: unlocked)
                styleSection(hasSel: hasSel)
                draftingSection
            }
            .padding(12)
        }
        .scrollDismissesKeyboard(.interactively)
    }

    // MARK: Geometry

    private func geometrySection(_ s: Shape) -> some View {
        let id = s.id
        func frame(_ name: String, _ kp: WritableKeyPath<CGRect, CGFloat>, min: CGFloat? = nil) -> Binding<Double> {
            Binding(get: { Double(canvas.selectedShapes.first?.frame[keyPath: kp] ?? 0) },
                    set: { v in
                        let value = CGFloat(min.map { Swift.max(Double($0), v) } ?? v)
                        canvas.applyShapes(name) { if $0.id == id { $0.frame[keyPath: kp] = value } }
                    })
        }
        return InspectorSection("Object") {
            VStack(alignment: .leading, spacing: 2) {
                Text("Name").font(.system(size: 11)).foregroundStyle(Color(Tok.textSecondary))
                TextField(s.kind.rawValue.capitalized, text: Binding(
                    get: { canvas.selectedShapes.first?.name ?? "" },
                    set: { t in canvas.applyShapes("Rename") { $0.name = t.isEmpty ? nil : t } }))
                    .padding(.horizontal, 10).frame(minHeight: 44)
                    .background(RoundedRectangle(cornerRadius: Tok.Radius.field).fill(Color(Tok.fieldBG)))
            }
            HStack(spacing: 8) {
                InspectorNumber(title: "X", value: frame("Move", \.origin.x), decimals: 1, disabled: s.locked)
                InspectorNumber(title: "Y", value: frame("Move", \.origin.y), decimals: 1, disabled: s.locked)
            }
            HStack(spacing: 8) {
                InspectorNumber(title: "Width", value: frame("Resize", \.size.width, min: 1), decimals: 1, disabled: s.locked)
                InspectorNumber(title: "Height", value: frame("Resize", \.size.height, min: 1), decimals: 1, disabled: s.locked)
            }
            InspectorNumber(title: "Rotation", value: Binding(
                get: { canvas.selectedShapes.first?.rotation ?? 0 },
                set: { v in canvas.applyShapes("Rotate") { $0.rotation = v } }), suffix: "°", decimals: 1, disabled: s.locked)
            if s.locked {
                Text("Locked: unlock to move or resize.").font(.system(size: 12)).foregroundStyle(Color(Tok.textSecondary))
            }
        }
    }

    // MARK: Align

    private var alignSection: some View {
        let count = canvas.selectedShapes.count
        return InspectorSection("Align and Distribute") {
            HStack(spacing: 6) {
                alignButton("align.horizontal.left", "Align Left", 0)
                alignButton("align.horizontal.center", "Align Center", 1)
                alignButton("align.horizontal.right", "Align Right", 2)
                alignButton("align.vertical.top", "Align Top", 3)
                alignButton("align.vertical.center", "Align Middle", 4)
                alignButton("align.vertical.bottom", "Align Bottom", 5)
            }
            HStack(spacing: 6) {
                InspectorButton(title: "Distribute H", symbol: "distribute.horizontal.center", enabled: count >= 3) { canvas.distribute(horizontal: true) }
                InspectorButton(title: "Distribute V", symbol: "distribute.vertical.center", enabled: count >= 3) { canvas.distribute(horizontal: false) }
            }
            HStack(spacing: 6) {
                InspectorButton(title: "Same W") { canvas.matchSize(tag: 0) }
                InspectorButton(title: "Same H") { canvas.matchSize(tag: 1) }
                InspectorButton(title: "Same Size") { canvas.matchSize(tag: 2) }
            }
            Text("Sizes match the first object selected.").font(.system(size: 12)).foregroundStyle(Color(Tok.textSecondary))
        }
    }

    private func alignButton(_ symbol: String, _ label: String, _ tag: Int) -> some View {
        InspectorIconButton(symbol: symbol, label: label) { canvas.align(tag: tag) }
    }

    // MARK: Order, group, lock

    private func orderSection(hasSel: Bool, count: Int, unlocked: Bool) -> some View {
        let grouped = canvas.selectedShapes.contains { $0.group != nil }
        return InspectorSection("Order and Grouping") {
            HStack(spacing: 6) {
                InspectorButton(title: "To Front", symbol: "square.3.layers.3d.top.filled", enabled: hasSel) { canvas.bringToFront(nil) }
                InspectorButton(title: "To Back", symbol: "square.3.layers.3d.bottom.filled", enabled: hasSel) { canvas.sendToBack(nil) }
            }
            HStack(spacing: 6) {
                InspectorButton(title: "Group", symbol: "square.on.square", enabled: count >= 2) { canvas.group(nil) }
                InspectorButton(title: "Ungroup", symbol: "square.on.square.dashed", enabled: grouped) { canvas.ungroup(nil) }
            }
            HStack(spacing: 6) {
                InspectorButton(title: "Lock", symbol: "lock", enabled: hasSel && unlocked) { canvas.lockSelection(nil) }
                InspectorButton(title: "Unlock", symbol: "lock.open", enabled: canvas.selectionHasLocked) { canvas.unlockSelection(nil) }
            }
            HStack(spacing: 6) {
                InspectorButton(title: "Rotate Left", symbol: "rotate.left", enabled: count > 0) { canvas.rotateQuarter(clockwise: false) }
                InspectorButton(title: "Rotate Right", symbol: "rotate.right", enabled: count > 0) { canvas.rotateQuarter(clockwise: true) }
            }
        }
    }

    private func styleSection(hasSel: Bool) -> some View {
        InspectorSection("Style") {
            HStack(spacing: 6) {
                InspectorButton(title: "Copy Style", symbol: "doc.on.doc", enabled: hasSel) {
                    canvas.copyStyle(nil)
                    model.objectWillChange.send()
                }
                InspectorButton(title: "Paste Style", symbol: "doc.on.clipboard", enabled: canvas.hasStyleClip) { canvas.pasteStyle(nil) }
            }
        }
    }

    // MARK: Drafting

    private var draftingSection: some View {
        InspectorSection("Drafting") {
            ScaleEditor(model: model)
            Divider()
            Text("Add dimension").font(.system(size: 13, weight: .medium)).foregroundStyle(Color(Tok.textPrimary))
            HStack(spacing: 6) {
                ForEach(DimensionAxis.allCases, id: \.self) { axis in
                    InspectorButton(title: axis.title, symbol: axis == .horizontal ? "arrow.left.and.right" : axis == .vertical ? "arrow.up.and.down" : "arrow.up.left.and.arrow.down.right",
                                    enabled: canvas.canAddDimension) { canvas.addDimension(axis) }
                }
            }
            Text("Select one object to measure it, or two to measure the gap.")
                .font(.system(size: 12)).foregroundStyle(Color(Tok.textSecondary))
            if let c = canvas.selectedDimension, let spec = c.dimension {
                Divider()
                DimensionEditor(model: model, spec: spec, text: c.text).id(c.id)
            } else if let info = canvas.selectedLineInfo {
                Divider()
                LineEditor(model: model, length: info.length, angle: info.angle)
                    .id(canvas.selection.first?.uuidString ?? "")
            }
        }
    }
}

// MARK: - Drafting editors

private func trimmed(_ v: Double, _ digits: Double = 1000) -> Double { (v * digits).rounded() / digits }

/// Drawing scale: unit, "1 point equals" or printed ratio, decimals, wall thickness.
private struct ScaleEditor: View {
    @ObservedObject var model: EditorModel
    @State private var loaded = false
    @State private var unit: LengthUnit = .centimeter
    @State private var ratioMode = false
    @State private var value = 1.0
    @State private var decimals = -1      // -1 = automatic
    @State private var wall = 15.0

    private var current: DrawingScale? { model.canvas.drawing.scale }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Drawing scale").font(.system(size: 13, weight: .medium)).foregroundStyle(Color(Tok.textPrimary))
                Spacer()
                Text(current.map { "1 pt = \(trimmed($0.unitsPerPoint)) \($0.unit.symbol)" } ?? "Not set")
                    .font(.system(size: 12)).foregroundStyle(Color(Tok.textSecondary))
            }
            InspectorRow("Measure in") {
                Picker("Unit", selection: $unit) { ForEach(LengthUnit.allCases, id: \.self) { Text($0.title).tag($0) } }.pickerStyle(.menu)
            }
            Picker("Mode", selection: $ratioMode) {
                Text("1 point equals").tag(false)
                Text("Printed 1 : N").tag(true)
            }.pickerStyle(.segmented)
            InspectorNumber(title: ratioMode ? "Ratio N (1 : N)" : "Units per point (\(unit.symbol))", value: $value, decimals: 3)
            InspectorRow("Decimals") {
                Picker("Decimals", selection: $decimals) {
                    Text("Automatic").tag(-1)
                    ForEach(0...3, id: \.self) { Text("\($0)").tag($0) }
                }.pickerStyle(.menu)
            }
            InspectorNumber(title: "Wall thickness (\(unit.symbol))", value: $wall, decimals: 3)
            HStack(spacing: 6) {
                InspectorButton(title: "Set Scale", symbol: "ruler", enabled: value > 0) { apply() }
                InspectorButton(title: "Remove", enabled: current != nil, destructive: true) {
                    model.canvas.setScale(nil)
                    load(.standard)
                }
            }
        }
        .onAppear { if !loaded { loaded = true; load(current ?? .standard) } }
    }

    private func load(_ s: DrawingScale) {
        unit = s.unit
        ratioMode = false
        value = trimmed(s.unitsPerPoint)
        decimals = s.decimals.map { min($0, 3) } ?? -1
        wall = trimmed(s.wallThickness ?? s.unit.defaultWall)
    }

    private func apply() {
        guard value > 0 else { return }
        var s = ratioMode ? DrawingScale.ratio(value, unit: unit) : { var x = DrawingScale(); x.unit = unit; x.unitsPerPoint = value; return x }()
        s.decimals = decimals < 0 ? nil : decimals
        if wall > 0, abs(wall - unit.defaultWall) > 1e-9 { s.wallThickness = wall }
        model.canvas.setScale(s)
        load(s)
    }
}

private struct DimensionEditor: View {
    @ObservedObject var model: EditorModel
    let spec: DimensionSpec
    @State private var axis: DimensionAxis
    @State private var distance: Double
    @State private var text: String

    init(model: EditorModel, spec: DimensionSpec, text: String) {
        self.model = model
        self.spec = spec
        let scale = model.canvas.drawing.scale ?? .standard
        _axis = State(initialValue: spec.axis)
        _distance = State(initialValue: trimmed(scale.length(spec.offset), 100))
        _text = State(initialValue: text)
    }

    var body: some View {
        let scale = model.canvas.drawing.scale ?? .standard
        VStack(alignment: .leading, spacing: 8) {
            Text("Edit dimension").font(.system(size: 13, weight: .medium)).foregroundStyle(Color(Tok.textPrimary))
            Picker("Measures", selection: $axis) { ForEach(DimensionAxis.allCases, id: \.self) { Text($0.title).tag($0) } }.pickerStyle(.segmented)
            InspectorNumber(title: "Distance (\(scale.unit.symbol)); negative = other side", value: $distance, decimals: 2)
            VStack(alignment: .leading, spacing: 2) {
                Text("Text").font(.system(size: 11)).foregroundStyle(Color(Tok.textSecondary))
                TextField("Measured automatically", text: $text)
                    .padding(.horizontal, 10).frame(minHeight: 44)
                    .background(RoundedRectangle(cornerRadius: Tok.Radius.field).fill(Color(Tok.fieldBG)))
            }
            InspectorButton(title: "Apply", symbol: "checkmark") {
                model.canvas.setSelectedDimension(axis: axis, offset: scale.points(distance),
                                                  text: text.trimmingCharacters(in: .whitespaces))
            }
        }
    }
}

private struct LineEditor: View {
    @ObservedObject var model: EditorModel
    @State private var length: Double
    @State private var angle: Double

    init(model: EditorModel, length: Double, angle: Double) {
        self.model = model
        let scale = model.canvas.drawing.scale ?? .standard
        _length = State(initialValue: trimmed(scale.length(length)))
        _angle = State(initialValue: trimmed(angle, 100))
    }

    var body: some View {
        let scale = model.canvas.drawing.scale ?? .standard
        VStack(alignment: .leading, spacing: 8) {
            Text("Edit line").font(.system(size: 13, weight: .medium)).foregroundStyle(Color(Tok.textPrimary))
            HStack(spacing: 8) {
                InspectorNumber(title: "Length (\(scale.unit.symbol))", value: $length, decimals: 3)
                InspectorNumber(title: "Angle (0° right, 90° up)", value: $angle, suffix: "°", decimals: 2)
            }
            InspectorButton(title: "Apply", symbol: "checkmark", enabled: length > 0) {
                model.canvas.setSelectedLine(length: scale.points(length), angle: angle)
            }
        }
    }
}
