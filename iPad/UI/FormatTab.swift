import SwiftUI

/// Fill, stroke, shadow, text, effects (and connector options) for the selection, or for new objects when nothing is selected.
struct FormatTab: View {
    @ObservedObject var model: EditorModel

    init(model: EditorModel) { self.model = model }

    private var canvas: CanvasView { model.canvas }

    /// Binding into the current style, written through the canvas (one coalesced undo step per name).
    private func st<T>(_ kp: WritableKeyPath<Style, T>, _ name: String) -> Binding<T> {
        Binding(get: { canvas.currentStyle()[keyPath: kp] },
                set: { v in canvas.applyStyle(name) { $0[keyPath: kp] = v } })
    }

    private func color(_ kp: WritableKeyPath<Style, RGBA>, _ name: String) -> Binding<Color> {
        inspectorColor({ canvas.currentStyle()[keyPath: kp] }, { c in canvas.applyStyle(name) { $0[keyPath: kp] = c } })
    }

    private func dbl(_ kp: WritableKeyPath<Style, Double>, _ name: String) -> Binding<Double> { st(kp, name) }

    var body: some View {
        let _ = model.revision
        let style = canvas.currentStyle()
        let hasShapes = !canvas.selectedShapes.isEmpty
        let connectorsOnly = !canvas.selectedConnectors.isEmpty && !hasShapes
        let single = canvas.selection.count == 1
        let dimension = canvas.selectedDimension != nil

        ScrollView {
            VStack(spacing: 16) {
                header(hasShapes: hasShapes, connectorsOnly: connectorsOnly)
                if !connectorsOnly { fillSection(style) }
                strokeSection(style)
                if !connectorsOnly { cornerSection }
                opacitySection
                shadowSection(style)
                if !canvas.selectedConnectors.isEmpty { connectorSection(single: single, dimension: dimension) }
                textSection(style)
                if !connectorsOnly { effectSection(style) }
            }
            .padding(12)
        }
        .scrollDismissesKeyboard(.interactively)
    }

    // MARK: Header

    private func header(hasShapes: Bool, connectorsOnly: Bool) -> some View {
        let n = canvas.selection.count
        let text = n == 0 ? "New objects" : n == 1 ? (connectorsOnly ? "Connector" : "1 object") : "\(n) objects"
        return HStack {
            Text(text).font(.system(size: 15, weight: .semibold)).foregroundStyle(Color(Tok.textPrimary))
            Spacer()
            if n == 0 { Text("Default style").font(.system(size: 12)).foregroundStyle(Color(Tok.textSecondary)) }
        }
        .padding(.horizontal, 4)
    }

    // MARK: Fill

    private func fillSection(_ style: Style) -> some View {
        InspectorSection("Fill") {
            Picker("Type", selection: Binding(get: { canvas.currentStyle().fill.kind }, set: { k in
                canvas.applyStyle("Fill Type") {
                    if (k == .linear || k == .radial) && $0.fill.kind == .solid && !$0.fill.stops.isEmpty {
                        $0.fill.stops[0].color = $0.fill.color
                    }
                    $0.fill.kind = k
                }
            })) {
                ForEach(FillKind.allCases, id: \.self) { Text($0.title).tag($0) }
            }
            .pickerStyle(.menu)
            .frame(minHeight: 44)

            switch style.fill.kind {
            case .none:
                EmptyView()
            case .solid:
                InspectorRow("Color") {
                    ColorPicker("Fill color", selection: color(\.fill.color, "Fill Color"), supportsOpacity: false).labelsHidden()
                        .frame(minWidth: 44, minHeight: 44)
                }
                InspectorPresets(selected: style.fill.color) { c in
                    canvas.applyStyle("Fill Color") { $0.fill.color = RGBA(c.r, c.g, c.b, $0.fill.color.a) }
                }
                fillOpacity
            case .linear, .radial:
                gradientEditor(style)
            }
        }
    }

    private var fillOpacity: some View {
        InspectorSlider(title: "Fill opacity", value: Binding(
            get: { canvas.currentStyle().fill.color.a },
            set: { v in canvas.applyStyle("Fill Opacity") { st in
                st.fill.color.a = v
                for i in st.fill.stops.indices { st.fill.stops[i].color.a = v }
            } }), range: 0...1, suffix: "%", displayScale: 100)
    }

    private func stopsBinding() -> Binding<[GradientStop]> {
        Binding(get: { canvas.currentStyle().fill.stops }, set: { s in canvas.applyStyle("Gradient Stops") { $0.fill.stops = s } })
    }

    private func gradientEditor(_ style: Style) -> some View {
        let stops = style.fill.stops
        return VStack(alignment: .leading, spacing: 10) {
            RoundedRectangle(cornerRadius: 8)
                .fill(LinearGradient(stops: style.fill.sortedStops.map {
                    .init(color: Color(uiColor: $0.color.ns), location: CGFloat(min(max($0.position, 0), 1)))
                }, startPoint: .leading, endPoint: .trailing))
                .frame(height: 28)
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color(Tok.divider), lineWidth: 0.5))
            ForEach(Array(stops.indices), id: \.self) { i in
                HStack(spacing: 8) {
                    ColorPicker("Stop color", selection: inspectorColor(
                        { canvas.currentStyle().fill.stops.indices.contains(i) ? canvas.currentStyle().fill.stops[i].color : RGBA(0, 0, 0) },
                        { c in canvas.applyStyle("Gradient Stops") { if $0.fill.stops.indices.contains(i) { $0.fill.stops[i].color = c } } }),
                        supportsOpacity: true).labelsHidden().frame(minWidth: 44, minHeight: 44)
                    Slider(value: Binding(
                        get: { canvas.currentStyle().fill.stops.indices.contains(i) ? canvas.currentStyle().fill.stops[i].position : 0 },
                        set: { v in canvas.applyStyle("Gradient Stops") { if $0.fill.stops.indices.contains(i) { $0.fill.stops[i].position = v } } }),
                           in: 0...1)
                    Text("\(Int((stops[i].position * 100).rounded()))%")
                        .font(.system(size: 12).monospacedDigit()).foregroundStyle(Color(Tok.textSecondary)).frame(width: 40, alignment: .trailing)
                    Button {
                        canvas.applyStyle("Gradient Stops") { if $0.fill.stops.count > 2, $0.fill.stops.indices.contains(i) { $0.fill.stops.remove(at: i) } }
                    } label: {
                        Image(systemName: "minus.circle").frame(width: 44, height: 44)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Color(Tok.iconDefault))
                    .disabled(stops.count <= 2)
                    .opacity(stops.count <= 2 ? 0.3 : 1)
                    .accessibilityLabel("Remove stop")
                }
            }
            InspectorButton(title: "Add Stop", symbol: "plus") {
                canvas.applyStyle("Gradient Stops") { s in
                    let sorted = s.fill.sortedStops
                    // Put the new stop in the widest gap.
                    var best = (start: 0.0, end: 1.0)
                    var pts = [0.0] + sorted.map(\.position) + [1.0]
                    pts = pts.map { min(max($0, 0), 1) }.sorted()
                    for k in 1..<pts.count where pts[k] - pts[k - 1] > best.end - best.start { best = (pts[k - 1], pts[k]) }
                    let t = (best.start + best.end) / 2
                    s.fill.stops.append(GradientStop(color: s.fill.color(at: t), position: t))
                }
            }
            if style.fill.kind == .linear {
                InspectorSlider(title: "Angle", value: dbl(\.fill.angle, "Gradient Angle"), range: 0...360, suffix: "°")
            }
            fillOpacity
        }
    }

    // MARK: Stroke

    private func strokeSection(_ style: Style) -> some View {
        InspectorSection("Stroke") {
            Toggle("Visible", isOn: st(\.stroke.visible, "Toggle Line")).frame(minHeight: 44)
            if style.stroke.visible {
                InspectorRow("Color") {
                    ColorPicker("Stroke color", selection: color(\.stroke.color, "Line Color"), supportsOpacity: false).labelsHidden()
                        .frame(minWidth: 44, minHeight: 44)
                }
                InspectorSlider(title: "Width", value: dbl(\.stroke.width, "Line Width"), range: 0...24, decimals: 1)
                InspectorRow("Pattern") {
                    Picker("Pattern", selection: st(\.stroke.dash, "Line Pattern")) {
                        ForEach(DashKind.allCases, id: \.self) { Text($0.title).tag($0) }
                    }.pickerStyle(.menu)
                }
                InspectorRow("Cap") {
                    Picker("Cap", selection: st(\.stroke.cap, "Line Cap")) {
                        ForEach(CapKind.allCases, id: \.self) { Text($0.title).tag($0) }
                    }.pickerStyle(.segmented).frame(maxWidth: 200)
                }
                InspectorRow("Corner") {
                    Picker("Corner", selection: st(\.stroke.join, "Line Corner")) {
                        ForEach(JoinKind.allCases, id: \.self) { Text($0.title).tag($0) }
                    }.pickerStyle(.segmented).frame(maxWidth: 200)
                }
                InspectorSlider(title: "Roughness", value: Binding(
                    get: { canvas.currentStyle().stroke.roughness },
                    set: { v in canvas.applyStyle("Roughness") { $0.stroke.rough = v > 0 ? v : nil } }),
                                range: 0...1, suffix: "%", displayScale: 100)
            }
        }
    }

    private var cornerSection: some View {
        InspectorSection("Corner Radius") {
            InspectorSlider(title: "Corners", value: Binding(
                get: { canvas.currentStyle().cornerRadius },
                set: { v in canvas.applyStyle("Corner Radius") { $0.cornerRadius = v.rounded() } }), range: 0...80)
        }
    }

    private var opacitySection: some View {
        InspectorSection("Opacity") {
            InspectorSlider(title: "Overall", value: dbl(\.opacity, "Opacity"), range: 0...1, suffix: "%", displayScale: 100)
        }
    }

    // MARK: Shadow

    private func shadowSection(_ style: Style) -> some View {
        InspectorSection("Shadow") {
            Toggle("Shadow", isOn: st(\.shadow.enabled, "Toggle Shadow")).frame(minHeight: 44)
            if style.shadow.enabled {
                InspectorRow("Color") {
                    ColorPicker("Shadow color", selection: color(\.shadow.color, "Shadow Color"), supportsOpacity: true).labelsHidden()
                        .frame(minWidth: 44, minHeight: 44)
                }
                InspectorSlider(title: "Blur", value: dbl(\.shadow.blur, "Shadow Blur"), range: 0...40)
                InspectorSlider(title: "Distance", value: dbl(\.shadow.offset, "Shadow Distance"), range: 0...30)
                InspectorSlider(title: "Angle", value: dbl(\.shadow.angle, "Shadow Angle"), range: 0...360, suffix: "°")
            }
        }
    }

    // MARK: Connector

    private func connectorSection(single: Bool, dimension: Bool) -> some View {
        let c = canvas.selectedConnectors.first
        return InspectorSection("Connector") {
            if dimension {
                Text("Dimension lines are edited in the Arrange tab.")
                    .font(.system(size: 12)).foregroundStyle(Color(Tok.textSecondary))
            } else {
                InspectorRow("Route") {
                    Picker("Route", selection: Binding(get: { canvas.selectedConnectors.first?.route ?? .straight },
                                                       set: { r in canvas.applyConnector("Connector Type") { $0.route = r } })) {
                        ForEach(Route.allCases, id: \.self) { Text($0.title).tag($0) }
                    }.pickerStyle(.menu)
                }
                InspectorRow("Start") { headPicker(start: true) }
                InspectorRow("End") { headPicker(start: false) }
                InspectorSlider(title: "Head size", value: Binding(
                    get: { canvas.selectedConnectors.first?.headScale ?? 1 },
                    set: { v in canvas.applyConnector("Arrowhead Size") { $0.headScale = v } }),
                                range: 0.5...3, decimals: 1, suffix: "×")
                if single {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Label").font(.system(size: 11)).foregroundStyle(Color(Tok.textSecondary))
                        TextField("Label", text: Binding(
                            get: { canvas.selectedConnectors.first?.text ?? "" },
                            set: { t in canvas.applyConnector("Connector Label") { $0.text = t } }))
                            .padding(.horizontal, 10).frame(minHeight: 44)
                            .background(RoundedRectangle(cornerRadius: Tok.Radius.field).fill(Color(Tok.fieldBG)))
                            .disabled(c?.locked ?? false)
                    }
                }
            }
        }
    }

    private func headPicker(start: Bool) -> some View {
        Picker(start ? "Start" : "End", selection: Binding(
            get: { (start ? canvas.selectedConnectors.first?.startHead : canvas.selectedConnectors.first?.endHead) ?? .none },
            set: { k in canvas.applyConnector(start ? "Start Arrowhead" : "End Arrowhead") { if start { $0.startHead = k } else { $0.endHead = k } } })) {
            ForEach(HeadKind.allCases, id: \.self) { Text($0.title).tag($0) }
        }.pickerStyle(.menu)
    }

    // MARK: Text

    private func textSection(_ style: Style) -> some View {
        InspectorSection("Text") {
            InspectorRow("Font") {
                Picker("Font", selection: st(\.text.font, "Font")) {
                    ForEach(TextFormat.installedFonts, id: \.self) { Text($0).tag($0) }
                }.pickerStyle(.menu)
            }
            InspectorSlider(title: "Size", value: dbl(\.text.size, "Font Size"), range: 6...96)
            HStack(spacing: 6) {
                InspectorIconButton(symbol: "bold", label: "Bold", selected: style.text.bold) {
                    canvas.applyStyle("Bold") { $0.text.bold.toggle() }
                }
                InspectorIconButton(symbol: "italic", label: "Italic", selected: style.text.italic) {
                    canvas.applyStyle("Italic") { $0.text.italic.toggle() }
                }
                InspectorIconButton(symbol: "underline", label: "Underline", selected: style.text.underline) {
                    canvas.applyStyle("Underline") { $0.text.underline.toggle() }
                }
            }
            HStack(spacing: 6) {
                ForEach(HAlign.allCases, id: \.self) { a in
                    InspectorIconButton(symbol: a == .left ? "text.alignleft" : a == .center ? "text.aligncenter" : "text.alignright",
                                        label: "Align \(a.rawValue)", selected: style.text.hAlign == a) {
                        canvas.applyStyle("Align Text") { $0.text.hAlign = a }
                    }
                }
            }
            HStack(spacing: 6) {
                ForEach(VAlign.allCases, id: \.self) { a in
                    InspectorIconButton(symbol: a == .top ? "align.vertical.top" : a == .middle ? "align.vertical.center" : "align.vertical.bottom",
                                        label: "Align \(a.rawValue)", selected: style.text.vAlign == a) {
                        canvas.applyStyle("Align Text") { $0.text.vAlign = a }
                    }
                }
            }
            Toggle("Automatic color", isOn: Binding(get: { canvas.currentStyle().text.color == nil }, set: { auto in
                canvas.applyStyle("Text Color") { $0.text.color = auto ? nil : ($0.text.color ?? RGBA(0, 0, 0)) }
            })).frame(minHeight: 44)
            if let tc = style.text.color {
                InspectorRow("Color") {
                    ColorPicker("Text color", selection: inspectorColor({ canvas.currentStyle().text.color ?? tc },
                                                                       { c in canvas.applyStyle("Text Color") { $0.text.color = c } }),
                                supportsOpacity: false).labelsHidden().frame(minWidth: 44, minHeight: 44)
                }
            }
        }
    }

    // MARK: Effects

    private static let effects: [(Effect?, String)] = [(nil, "None"), (.neumorphic, "Neumorphic"), (.crystal, "Crystal"),
                                                       (.glass, "Glass"), (.hatch, "Hatch"), (.clay, "Clay")]

    private func effectSection(_ style: Style) -> some View {
        InspectorSection("Effect") {
            Picker("Effect", selection: Binding<Effect?>(get: { canvas.currentStyle().effect }, set: { e in
                canvas.applyStyle("Effect") { $0.effect = e }
            })) {
                ForEach(Array(Self.effects.enumerated()), id: \.offset) { _, e in Text(e.1).tag(e.0) }
            }
            .pickerStyle(.menu)
            .frame(minHeight: 44)
        }
    }
}
