import AppKit

private final class FlippedView: NSView {
    override var isFlipped: Bool { true }
}

/// Target object that forwards a control's action to a closure.
private final class Action: NSObject {
    let handler: (NSControl) -> Void
    init(_ handler: @escaping (NSControl) -> Void) { self.handler = handler }
    @objc func fire(_ sender: NSControl) { handler(sender) }
}

private func makeLabel(_ s: String) -> NSTextField {
    let l = NSTextField(labelWithString: s)
    l.font = .systemFont(ofSize: 11)
    l.textColor = .secondaryLabelColor
    l.widthAnchor.constraint(equalToConstant: 66).isActive = true
    return l
}

/// A section with a clickable header that folds its body away.
private final class DisclosureSection: NSStackView {
    let title: String
    private let body: NSStackView
    private let button = NSButton()
    private(set) var collapsed = false

    init(_ title: String, _ views: [NSView]) {
        self.title = title
        body = NSStackView(views: views)
        super.init(frame: .zero)

        body.orientation = .vertical
        body.alignment = .leading
        body.spacing = 8

        orientation = .vertical
        alignment = .leading
        spacing = 8

        button.isBordered = false
        button.imagePosition = .imageLeading
        button.alignment = .left
        button.attributedTitle = NSAttributedString(string: " " + title.uppercased(), attributes: [
            .font: NSFont.systemFont(ofSize: 10, weight: .semibold), .foregroundColor: NSColor.secondaryLabelColor,
        ])
        button.target = self
        button.action = #selector(toggle)
        // A hairline above every section; it hides with the section, so only visible sections are divided.
        let rule = NSBox()
        rule.boxType = .separator
        rule.widthAnchor.constraint(equalToConstant: 232).isActive = true
        addArrangedSubview(rule)
        addArrangedSubview(button)
        addArrangedSubview(body)
        updateChevron()
    }

    required init?(coder: NSCoder) { fatalError() }

    @objc private func toggle() {
        collapsed.toggle()
        body.isHidden = collapsed
        updateChevron()
    }

    private func updateChevron() {
        let img = NSImage(systemSymbolName: collapsed ? "chevron.right" : "chevron.down", accessibilityDescription: nil)
        button.image = img?.withSymbolConfiguration(.init(pointSize: 8, weight: .bold))
    }
}

/// A labelled slider with a field beside it that shows the value and lets you type an exact one.
final class SliderRow: NSObject {
    let row: NSStackView
    let slider: NSSlider
    let field = NSTextField()
    private let decimals: Int
    private let suffix: String
    private let displayScale: Double

    /// `displayScale` converts the slider's value into what is shown and typed (opacity 0...1 is shown as 0...100%).
    init(_ title: String, _ min: Double, _ max: Double, decimals: Int = 0, suffix: String = "", displayScale: Double = 1) {
        self.decimals = decimals
        self.suffix = suffix
        self.displayScale = displayScale
        slider = NSSlider(value: min, minValue: min, maxValue: max, target: nil, action: nil)
        slider.isContinuous = true
        slider.controlSize = .small
        slider.widthAnchor.constraint(greaterThanOrEqualToConstant: 60).isActive = true

        field.alignment = .right
        field.font = .monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        field.controlSize = .small
        field.focusRingType = .none
        field.widthAnchor.constraint(equalToConstant: 56).isActive = true

        row = NSStackView(views: [makeLabel(title), slider, field])
        row.orientation = .horizontal
        row.spacing = 6
        row.alignment = .centerY
        // Full column width (panel 260 - 2 x 14 margin), so every slider ends at the same place whatever its section holds.
        row.widthAnchor.constraint(equalToConstant: 232).isActive = true
        super.init()
        field.target = self
        field.action = #selector(fieldCommitted)
    }

    private func text(for v: Double) -> String { String(format: "%.\(decimals)f", v * displayScale) + suffix }

    func set(_ v: Double) {
        slider.doubleValue = v
        field.stringValue = text(for: v)
    }

    func refreshReadout() { field.stringValue = text(for: slider.doubleValue) }

    @objc private func fieldCommitted() { enter(field.stringValue) }

    /// Applies a typed value ("12.5", "80%"), clamped to the slider's range, through the slider's own action,
    /// so it behaves exactly like dragging. Anything that isn't a number puts the old value back.
    func enter(_ text: String) {
        var cleaned = text.trimmingCharacters(in: .whitespaces)
        if !suffix.isEmpty { cleaned = cleaned.replacingOccurrences(of: suffix, with: "").trimmingCharacters(in: .whitespaces) }
        guard let shown = Double(cleaned.replacingOccurrences(of: ",", with: ".")) else {
            refreshReadout()
            return
        }
        slider.doubleValue = min(max(shown / displayScale, slider.minValue), slider.maxValue)
        refreshReadout()
        slider.sendAction(slider.action, to: slider.target)
    }
}

/// A labelled round dial with a field for typing the exact angle.
final class AngleRow: NSObject {
    let row: NSStackView
    let dial = AngleDial()
    let field = NSTextField(string: "0°")

    /// Called when the user changes the angle by dragging the dial or typing a value.
    var onChange: ((Double) -> Void)?

    init(_ title: String) {
        field.alignment = .right
        field.font = .monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        field.controlSize = .small
        field.focusRingType = .none
        field.widthAnchor.constraint(equalToConstant: 48).isActive = true
        dial.widthAnchor.constraint(equalToConstant: 30).isActive = true
        dial.heightAnchor.constraint(equalToConstant: 30).isActive = true
        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        row = NSStackView(views: [makeLabel(title), dial, field, spacer])
        row.orientation = .horizontal
        row.spacing = 8
        row.alignment = .centerY
        row.widthAnchor.constraint(equalToConstant: 232).isActive = true
        super.init()
        dial.onChange = { [weak self] v in
            self?.field.stringValue = AngleRow.text(v)
            self?.onChange?(v)
        }
        field.target = self
        field.action = #selector(fieldCommitted)
    }

    static func text(_ v: Double) -> String { "\(Int(v.rounded()))°" }

    /// A disabled row is dimmed and ignores the dial and the field (used for locked shapes).
    func setEnabled(_ on: Bool) {
        dial.isEnabled = on
        dial.alphaValue = on ? 1 : 0.4
        field.isEnabled = on
    }

    /// Sets the angle from code; does not call `onChange`.
    func set(_ v: Double) {
        dial.angle = v
        field.stringValue = AngleRow.text(v)
    }

    @objc private func fieldCommitted() { enter(field.stringValue) }

    /// Applies a typed angle ("135", "-90°", "450" -> 90). Anything that isn't a number is ignored.
    func enter(_ text: String) {
        let digits = text.replacingOccurrences(of: "°", with: "").trimmingCharacters(in: .whitespaces)
        guard let v = Double(digits) else {
            field.stringValue = AngleRow.text(dial.angle)
            return
        }
        let angle = AngleDial.normalized(v.rounded())
        set(angle)
        onChange?(angle)
    }
}

final class InspectorView: NSView, NSTableViewDataSource, NSTableViewDelegate, NSTextFieldDelegate {
    weak var canvas: CanvasView?

    /// The saved styles shown in the Styles section (the app-wide library unless a test supplies its own).
    var library: StyleLibrary = .shared {
        didSet { stylePalette.library = library }
    }

    /// Asks the user for a style name (title, suggested name). Replaceable so tests don't open a dialog.
    var namePrompt: (_ title: String, _ initial: String) -> String? = InspectorView.askForName

    static func askForName(_ title: String, _ initial: String) -> String? {
        let alert = NSAlert()
        alert.messageText = title
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Cancel")
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 240, height: 24))
        field.stringValue = initial
        alert.accessoryView = field
        alert.window.initialFirstResponder = field
        guard alert.runModal() == .alertFirstButtonReturn else { return nil }
        let name = field.stringValue.trimmingCharacters(in: .whitespaces)
        return name.isEmpty ? nil : name
    }

    private var updating = false
    private var actions: [Action] = []

    private let scroll = NSScrollView()
    private let container = FlippedView()
    private var layersPane: NSView!
    private let header = NSTextField(labelWithString: "")

    // Sections (all live in one scrolling column)
    private var stylesSection: DisclosureSection!
    private var fillSection: DisclosureSection!
    private var lineSection: DisclosureSection!
    private var shadowSection: DisclosureSection!
    private var objectSection: DisclosureSection!
    private var textSection: DisclosureSection!
    private var connectorSection: DisclosureSection!

    // Fill
    private let fillKind = NSPopUpButton(frame: .zero, pullsDown: false)
    private let fillColor = NSColorWell()
    private let fillAngle = AngleRow("Angle")
    private let stylePalette = StylePaletteView()
    private let colorPresets = ColorPresetsView()
    private let gradientEditor = GradientEditorView()
    private let stopColor = NSColorWell()
    private let stopPosition = SliderRow("Position", 0, 100, suffix: "%")
    private let removeStopBtn = NSButton(title: "Remove Stop", target: nil, action: nil)
    private let reverseBtn = NSButton(title: "Reverse", target: nil, action: nil)
    private var shadowDetailRows: [NSView] = []
    private var fillColorRow: NSView!
    private var gradientRows: [NSView] = []

    // Line
    private let strokeOn = NSButton(checkboxWithTitle: "Show line", target: nil, action: nil)
    private let strokeColor = NSColorWell()
    private let strokeWidth = SliderRow("Width", 0, 24, decimals: 1)
    private let dashPopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let capPopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let joinPopup = NSPopUpButton(frame: .zero, pullsDown: false)

    // Shadow
    private let shadowOn = NSButton(checkboxWithTitle: "Shadow", target: nil, action: nil)
    private let shadowColor = NSColorWell()
    private let shadowAngle = AngleRow("Angle")
    private let shadowBlur = SliderRow("Blur", 0, 40)
    private let shadowOffset = SliderRow("Distance", 0, 30)

    // Object
    private let opacity = SliderRow("Opacity", 0, 1, suffix: "%", displayScale: 100)
    private let radius = SliderRow("Corners", 0, 80)
    private let rotation = AngleRow("Rotation")

    // Text
    private let fontPopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let fontSize = SliderRow("Size", 6, 96)
    private let boldBtn = NSButton(title: "B", target: nil, action: nil)
    private let italicBtn = NSButton(title: "I", target: nil, action: nil)
    private let underlineBtn = NSButton(title: "U", target: nil, action: nil)
    private let hAlign = NSSegmentedControl(images: HAlign.allCases.map(Glyphs.hAlign), trackingMode: .selectOne, target: nil, action: nil)
    private let vAlign = NSSegmentedControl(images: VAlign.allCases.map(Glyphs.vAlign), trackingMode: .selectOne, target: nil, action: nil)
    private let autoTextColor = NSButton(checkboxWithTitle: "Auto color", target: nil, action: nil)
    private let textColor = NSColorWell()

    // Connector
    private let routePopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let startHead = NSPopUpButton(frame: .zero, pullsDown: false)
    private let endHead = NSPopUpButton(frame: .zero, pullsDown: false)
    private let headSize = SliderRow("Head size", 0.5, 3, decimals: 1, suffix: "×")

    // Layers
    private let layerTable = NSTableView()
    private var layersCache: [Layer] = []

    override init(frame: NSRect) {
        super.init(frame: frame)
        build()
    }

    required init?(coder: NSCoder) { fatalError() }

    // MARK: Building

    @discardableResult
    private func bind<T: NSControl>(_ control: T, _ handler: @escaping (T) -> Void) -> T {
        let a = Action { [weak self] sender in
            guard let self, !self.updating, let typed = sender as? T else { return }
            handler(typed)
        }
        actions.append(a)
        control.target = a
        control.action = #selector(Action.fire(_:))
        return control
    }

    private func row(_ title: String, _ control: NSView) -> NSStackView {
        let r = NSStackView(views: [makeLabel(title), control])
        r.orientation = .horizontal
        r.spacing = 8
        r.alignment = .centerY
        return r
    }

    private func sectionTitle(_ s: String) -> NSTextField {
        let l = NSTextField(labelWithString: s.uppercased())
        l.font = .systemFont(ofSize: 10, weight: .semibold)
        l.textColor = .tertiaryLabelColor
        return l
    }

    private func prepare(_ well: NSColorWell) {
        well.widthAnchor.constraint(equalToConstant: 44).isActive = true
        well.heightAnchor.constraint(equalToConstant: 22).isActive = true
    }

    /// Every drop-down in the inspector is this wide, whatever its pictures measure, so the column looks even.
    private static let popupWidth: CGFloat = 132

    /// A pop-up whose items are pictures; the name is only a tooltip.
    private func fillImages(_ popup: NSPopUpButton, _ images: [NSImage], tips: [String]) {
        popup.removeAllItems()
        for (img, tip) in zip(images, tips) {
            let item = NSMenuItem(title: "", action: nil, keyEquivalent: "")
            item.image = img
            item.toolTip = tip
            popup.menu?.addItem(item)
        }
        popup.controlSize = .small
        popup.setContentHuggingPriority(.defaultLow, for: .horizontal)
        popup.widthAnchor.constraint(equalToConstant: InspectorView.popupWidth).isActive = true
    }

    /// Every installed font family, each name set in its own typeface. The family is kept on the item,
    /// so the popup can also carry a temporary entry for a font this Mac doesn't have.
    private func fillFonts(_ popup: NSPopUpButton) {
        popup.removeAllItems()
        for name in TextFormat.installedFonts {
            let item = NSMenuItem(title: name, action: nil, keyEquivalent: "")
            item.representedObject = name
            let f: NSFont
            if name == "System" { f = .systemFont(ofSize: 13) }
            else { f = NSFont(descriptor: NSFontDescriptor(fontAttributes: [.family: name]), size: 13) ?? .systemFont(ofSize: 13) }
            item.attributedTitle = NSAttributedString(string: name, attributes: [.font: f])   // each name in its own typeface
            popup.menu?.addItem(item)
        }
        popup.controlSize = .small
        popup.setContentHuggingPriority(.defaultLow, for: .horizontal)
        popup.widthAnchor.constraint(equalToConstant: InspectorView.popupWidth).isActive = true
    }

    private func build() {
        header.font = .systemFont(ofSize: 13, weight: .semibold)

        for w in [fillColor, stopColor, strokeColor, shadowColor, textColor] { prepare(w) }
        for b in [boldBtn, italicBtn, underlineBtn] {
            b.setButtonType(.pushOnPushOff)
            b.bezelStyle = .texturedRounded
            b.controlSize = .small
            b.widthAnchor.constraint(equalToConstant: 34).isActive = true
        }
        boldBtn.font = .boldSystemFont(ofSize: 12)
        italicBtn.font = NSFontManager.shared.convert(.systemFont(ofSize: 12), toHaveTrait: .italicFontMask)
        underlineBtn.attributedTitle = NSAttributedString(string: "U", attributes: [
            .underlineStyle: NSUnderlineStyle.single.rawValue, .font: NSFont.systemFont(ofSize: 12),
        ])
        for s in [hAlign, vAlign] {
            s.controlSize = .small
            s.segmentStyle = .rounded
            for i in 0..<s.segmentCount { s.setWidth(34, forSegment: i); s.setImageScaling(.scaleNone, forSegment: i) }
        }
        hAlign.toolTip = "Horizontal alignment"
        vAlign.toolTip = "Vertical alignment"

        fillImages(fillKind, FillKind.allCases.map(Glyphs.fill), tips: FillKind.allCases.map(\.title))
        fillImages(dashPopup, DashKind.allCases.map(Glyphs.dash), tips: DashKind.allCases.map(\.title))
        fillImages(capPopup, CapKind.allCases.map(Glyphs.cap), tips: CapKind.allCases.map { $0.title + " cap" })
        fillImages(joinPopup, JoinKind.allCases.map(Glyphs.join), tips: JoinKind.allCases.map { $0.title + " corner" })
        fillImages(routePopup, Route.allCases.map(Glyphs.route), tips: Route.allCases.map(\.title))
        fillImages(startHead, HeadKind.allCases.map { Glyphs.head($0, atEnd: false) }, tips: HeadKind.allCases.map(\.title))
        fillImages(endHead, HeadKind.allCases.map { Glyphs.head($0, atEnd: true) }, tips: HeadKind.allCases.map(\.title))
        fillFonts(fontPopup)

        bindStyleControls()
        bindTextControls()
        bindConnectorControls()

        // ----- Sections
        fillColorRow = row("Color", fillColor)
        gradientEditor.widthAnchor.constraint(equalToConstant: 232).isActive = true
        gradientEditor.heightAnchor.constraint(equalToConstant: 46).isActive = true
        gradientEditor.toolTip = "Click the bar to add a color stop. Drag a marker to move it (Shift = 5% steps). Delete removes the selected stop."
        for b in [removeStopBtn, reverseBtn] { b.bezelStyle = .texturedRounded; b.controlSize = .small }
        let stopColorRow = row("Stop color", stopColor)
        let stopButtons = NSStackView(views: [removeStopBtn, reverseBtn])
        stopButtons.spacing = 6
        gradientRows = [gradientEditor, stopColorRow, stopPosition.row, stopButtons]

        colorPresets.widthAnchor.constraint(equalToConstant: 232).isActive = true
        colorPresets.heightAnchor.constraint(equalToConstant: 76).isActive = true
        stylePalette.widthAnchor.constraint(equalToConstant: 232).isActive = true
        stylePalette.library = library
        stylesSection = DisclosureSection("Styles", [stylePalette])
        fillSection = DisclosureSection("Fill", [row("Type", fillKind), colorPresets, fillColorRow,
                                                 gradientEditor, stopColorRow, stopPosition.row, stopButtons, fillAngle.row])
        lineSection = DisclosureSection("Line", [strokeOn, row("Color", strokeColor), strokeWidth.row,
                                                 row("Pattern", dashPopup), row("Cap", capPopup), row("Corner", joinPopup)])
        // Only the checkbox is always there; the rest appear while the shadow is on.
        shadowDetailRows = [row("Color", shadowColor), shadowAngle.row, shadowBlur.row, shadowOffset.row]
        shadowSection = DisclosureSection("Shadow", [shadowOn] + shadowDetailRows)
        objectSection = DisclosureSection("Object", [opacity.row, radius.row, rotation.row])

        let styleRow = NSStackView(views: [boldBtn, italicBtn, underlineBtn])
        styleRow.spacing = 6
        textSection = DisclosureSection("Text", [row("Font", fontPopup), fontSize.row, row("Style", styleRow),
                                                 row("Horizontal", hAlign), row("Vertical", vAlign),
                                                 autoTextColor, row("Color", textColor)])

        let note = NSTextField(wrappingLabelWithString: "Line color, width, pattern and shadow are in the sections above.")
        note.font = .systemFont(ofSize: 10)
        note.textColor = .tertiaryLabelColor
        note.preferredMaxLayoutWidth = 220
        connectorSection = DisclosureSection("Connector", [row("Type", routePopup), row("Start", startHead),
                                                           row("End", endHead), headSize.row, note])

        let column = NSStackView(views: [header, stylesSection, fillSection, lineSection, shadowSection, objectSection,
                                         textSection, connectorSection])
        column.orientation = .vertical
        column.alignment = .leading
        column.spacing = 12
        column.edgeInsets = NSEdgeInsets(top: 14, left: 14, bottom: 18, right: 14)
        column.translatesAutoresizingMaskIntoConstraints = false

        layersPane = buildLayersPane()

        container.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(column)
        scroll.documentView = container
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        scroll.translatesAutoresizingMaskIntoConstraints = false

        let divider = NSBox()
        divider.boxType = .separator
        divider.translatesAutoresizingMaskIntoConstraints = false

        addSubview(scroll)
        addSubview(divider)
        addSubview(layersPane)
        NSLayoutConstraint.activate([
            column.topAnchor.constraint(equalTo: container.topAnchor),
            column.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            column.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            column.bottomAnchor.constraint(equalTo: container.bottomAnchor),

            scroll.topAnchor.constraint(equalTo: topAnchor),
            scroll.leadingAnchor.constraint(equalTo: leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: trailingAnchor),
            scroll.bottomAnchor.constraint(equalTo: divider.topAnchor),
            container.widthAnchor.constraint(equalTo: scroll.contentView.widthAnchor),

            divider.leadingAnchor.constraint(equalTo: leadingAnchor),
            divider.trailingAnchor.constraint(equalTo: trailingAnchor),
            divider.bottomAnchor.constraint(equalTo: layersPane.topAnchor),
            // The layers panel is always on screen, below whatever sections the selection needs.
            layersPane.leadingAnchor.constraint(equalTo: leadingAnchor),
            layersPane.trailingAnchor.constraint(equalTo: trailingAnchor),
            layersPane.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    /// Titles of the sections currently on screen (used by the self-test).
    var visibleSectionTitles: [String] {
        [stylesSection, fillSection, lineSection, shadowSection, objectSection, textSection, connectorSection]
            .compactMap { $0 }.filter { !$0.isHidden }.map(\.title)
    }

    /// The angle controls, exposed so tests can drive them like a user would.
    var rotationControl: AngleRow { rotation }
    var shadowAngleControl: AngleRow { shadowAngle }
    var gradientAngleControl: AngleRow { fillAngle }

    /// True while the shadow's color/angle/blur/distance rows are on screen.
    var shadowDetailsVisible: Bool { shadowDetailRows.first.map { !$0.isHidden } ?? false }
    var presetsControl: ColorPresetsView { colorPresets }
    var paletteControl: StylePaletteView { stylePalette }
    var fontControl: NSPopUpButton { fontPopup }
    var lineWidthControl: SliderRow { strokeWidth }
    var opacityControl: SliderRow { opacity }

    var isLayersPanelHidden: Bool { layersPane.isHidden || layersPane.superview == nil }
    var layerRowCount: Int { layerTable.numberOfRows }

    /// Height the scrolling column wants (used by the layout self-check).
    var currentPaneHeight: CGFloat { container.fittingSize.height }

    // MARK: Bindings

    private func bindStyleControls() {
        stylePalette.onApply = { [unowned self] saved in
            canvas?.applyLook(saved.style, fromConnector: saved.fromConnector, name: "Apply Style")
            refresh()
        }
        stylePalette.onAdd = { [unowned self] in
            guard let source = canvas?.styleForSaving(),
                  let name = namePrompt("Save Style", "Style \(library.styles.count + 1)") else { return }
            library.add(name: name, style: source.style, fromConnector: source.fromConnector)
        }
        stylePalette.onRename = { [unowned self] saved in
            if let name = namePrompt("Rename Style", saved.name) { library.rename(saved.id, to: name) }
        }
        stylePalette.onUpdate = { [unowned self] saved in
            guard let source = canvas?.styleForSaving() else { return }
            library.update(saved.id, style: source.style, fromConnector: source.fromConnector)
        }
        stylePalette.onDelete = { [unowned self] saved in library.delete(saved.id) }

        bind(fillKind) { [unowned self] p in
            let k = FillKind.allCases[p.indexOfSelectedItem]
            canvas?.applyStyle("Fill Type") {
                // Starting a gradient from a solid fill: begin at the color the user already had.
                if (k == .linear || k == .radial) && $0.fill.kind == .solid && !$0.fill.stops.isEmpty {
                    $0.fill.stops[0].color = $0.fill.color
                }
                $0.fill.kind = k
            }
            refresh()
        }
        bind(fillColor) { [unowned self] w in let c = RGBA(w.color); canvas?.applyStyle("Fill Color") { $0.fill.color = c } }
        colorPresets.onPick = { [unowned self] c in
            guard !updating else { return }
            let kind = FillKind.allCases[max(fillKind.indexOfSelectedItem, 0)]
            if kind == .linear || kind == .radial {
                // A gradient takes the preset on the stop that is selected in the editor.
                guard gradientEditor.stops.indices.contains(gradientEditor.selected) else { return }
                gradientEditor.stops[gradientEditor.selected].color = c
                pushStops()
            } else {
                canvas?.applyStyle("Fill Color") { $0.fill.color = c }
            }
            refresh()
        }
        bind(stopColor) { [unowned self] w in
            guard gradientEditor.stops.indices.contains(gradientEditor.selected) else { return }
            gradientEditor.stops[gradientEditor.selected].color = RGBA(w.color)
            pushStops()
        }
        bind(stopPosition.slider) { [unowned self] s in
            stopPosition.refreshReadout()
            guard gradientEditor.stops.indices.contains(gradientEditor.selected) else { return }
            gradientEditor.stops[gradientEditor.selected].position = min(max(s.doubleValue / 100, 0), 1)
            pushStops()
        }
        bind(removeStopBtn) { [unowned self] _ in gradientEditor.removeSelected() }
        bind(reverseBtn) { [unowned self] _ in gradientEditor.reverse() }
        gradientEditor.onSelect = { [unowned self] in syncStopControls() }
        gradientEditor.onEdit = { [unowned self] in
            pushStops()
            syncStopControls()
        }
        fillAngle.onChange = { [unowned self] v in
            guard !updating else { return }
            canvas?.applyStyle("Gradient Angle") { $0.fill.angle = v }
        }

        bind(strokeOn) { [unowned self] b in let on = b.state == .on; canvas?.applyStyle("Toggle Line") { $0.stroke.visible = on } }
        bind(strokeColor) { [unowned self] w in let c = RGBA(w.color); canvas?.applyStyle("Line Color") { $0.stroke.color = c } }
        bind(strokeWidth.slider) { [unowned self] s in
            strokeWidth.refreshReadout()
            let v = (s.doubleValue * 2).rounded() / 2
            canvas?.applyStyle("Line Width") { $0.stroke.width = v }
        }
        bind(dashPopup) { [unowned self] p in let k = DashKind.allCases[p.indexOfSelectedItem]; canvas?.applyStyle("Line Pattern") { $0.stroke.dash = k } }
        bind(capPopup) { [unowned self] p in let k = CapKind.allCases[p.indexOfSelectedItem]; canvas?.applyStyle("Line Cap") { $0.stroke.cap = k } }
        bind(joinPopup) { [unowned self] p in let k = JoinKind.allCases[p.indexOfSelectedItem]; canvas?.applyStyle("Line Corner") { $0.stroke.join = k } }

        bind(shadowOn) { [unowned self] b in
            let on = b.state == .on
            canvas?.applyStyle("Toggle Shadow") { $0.shadow.enabled = on }
            refresh()
        }
        bind(shadowColor) { [unowned self] w in let c = RGBA(w.color); canvas?.applyStyle("Shadow Color") { $0.shadow.color = c } }
        shadowAngle.onChange = { [unowned self] v in
            guard !updating else { return }
            canvas?.applyStyle("Shadow Angle") { $0.shadow.angle = v }
        }
        bind(shadowBlur.slider) { [unowned self] s in
            shadowBlur.refreshReadout()
            let v = s.doubleValue.rounded()
            canvas?.applyStyle("Shadow Blur") { $0.shadow.blur = v }
        }
        bind(shadowOffset.slider) { [unowned self] s in
            shadowOffset.refreshReadout()
            let v = s.doubleValue.rounded()
            canvas?.applyStyle("Shadow Distance") { $0.shadow.offset = v }
        }
        bind(opacity.slider) { [unowned self] s in
            opacity.refreshReadout()
            let v = s.doubleValue
            canvas?.applyStyle("Opacity") { $0.opacity = v }
        }
        rotation.onChange = { [unowned self] v in
            guard !updating else { return }
            canvas?.applyShapes("Rotate") { $0.rotation = v }
        }
        bind(radius.slider) { [unowned self] s in
            radius.refreshReadout()
            let v = s.doubleValue.rounded()
            canvas?.applyStyle("Corner Radius") { $0.cornerRadius = v }
        }
    }

    private func bindTextControls() {
        bind(fontPopup) { [unowned self] p in
            guard let name = p.selectedItem?.representedObject as? String else { return }
            canvas?.applyStyle("Font") { $0.text.font = name }
        }
        bind(fontSize.slider) { [unowned self] s in
            fontSize.refreshReadout()
            let v = s.doubleValue.rounded()
            canvas?.applyStyle("Font Size") { $0.text.size = v }
        }
        bind(boldBtn) { [unowned self] b in let on = b.state == .on; canvas?.applyStyle("Bold") { $0.text.bold = on } }
        bind(italicBtn) { [unowned self] b in let on = b.state == .on; canvas?.applyStyle("Italic") { $0.text.italic = on } }
        bind(underlineBtn) { [unowned self] b in let on = b.state == .on; canvas?.applyStyle("Underline") { $0.text.underline = on } }
        bind(hAlign) { [unowned self] s in let a = HAlign.allCases[s.selectedSegment]; canvas?.applyStyle("Align Text") { $0.text.hAlign = a } }
        bind(vAlign) { [unowned self] s in let a = VAlign.allCases[s.selectedSegment]; canvas?.applyStyle("Align Text") { $0.text.vAlign = a } }
        bind(autoTextColor) { [unowned self] b in
            let auto = b.state == .on
            let c = RGBA(textColor.color)
            canvas?.applyStyle("Text Color") { $0.text.color = auto ? nil : c }
            refresh()
        }
        bind(textColor) { [unowned self] w in
            let c = RGBA(w.color)
            canvas?.applyStyle("Text Color") { $0.text.color = c }
            autoTextColor.state = .off
        }
    }

    private func bindConnectorControls() {
        bind(routePopup) { [unowned self] p in
            let r = Route.allCases[p.indexOfSelectedItem]
            canvas?.applyConnector("Connector Type") { $0.route = r }
        }
        bind(startHead) { [unowned self] p in
            let k = HeadKind.allCases[p.indexOfSelectedItem]
            canvas?.applyConnector("Start Arrowhead") { $0.startHead = k }
        }
        bind(endHead) { [unowned self] p in
            let k = HeadKind.allCases[p.indexOfSelectedItem]
            canvas?.applyConnector("End Arrowhead") { $0.endHead = k }
        }
        bind(headSize.slider) { [unowned self] s in
            headSize.refreshReadout()
            let v = (s.doubleValue * 10).rounded() / 10
            canvas?.applyConnector("Arrowhead Size") { $0.headScale = v }
        }
    }

    // MARK: Fonts

    /// Shows `name` in the font popup. A document can use a font that isn't installed here (it was made on
    /// another Mac): it appears as its own entry marked "not installed" instead of silently showing another font.
    private func selectFont(_ name: String) {
        if let stale = fontPopup.menu?.items.first(where: { $0.tag == InspectorView.missingFontTag }) {
            fontPopup.menu?.removeItem(stale)
        }
        if let i = fontPopup.menu?.items.firstIndex(where: { ($0.representedObject as? String) == name }) {
            fontPopup.selectItem(at: i)
            return
        }
        let item = NSMenuItem(title: "\(name) (not installed)", action: nil, keyEquivalent: "")
        item.representedObject = name
        item.tag = InspectorView.missingFontTag
        fontPopup.menu?.insertItem(item, at: 0)
        fontPopup.selectItem(at: 0)
    }

    private static let missingFontTag = 7_001

    // MARK: Gradient stops

    private func pushStops() {
        let stops = gradientEditor.stops
        canvas?.applyStyle("Gradient Stops") { $0.fill.stops = stops }
    }

    /// Shows the selected stop's color and position in the controls below the bar.
    private func syncStopControls() {
        let wasUpdating = updating
        updating = true
        defer { updating = wasUpdating }
        guard gradientEditor.stops.indices.contains(gradientEditor.selected) else { return }
        let s = gradientEditor.stops[gradientEditor.selected]
        stopColor.color = s.color.ns
        colorPresets.selectedColor = s.color
        stopPosition.set(s.position * 100)
        removeStopBtn.isEnabled = gradientEditor.stops.count > 2
    }

    // MARK: Refresh

    func refresh() {
        guard let canvas else { return }
        updating = true
        defer { updating = false }

        let st = canvas.currentStyle()
        let shapes = canvas.selectedShapes
        let conns = canvas.selectedConnectors

        fillKind.selectItem(at: FillKind.allCases.firstIndex(of: st.fill.kind) ?? 0)
        fillColor.color = st.fill.color.ns
        gradientEditor.stops = st.fill.stops
        gradientEditor.selected = min(gradientEditor.selected, max(st.fill.stops.count - 1, 0))
        syncStopControls()
        fillAngle.set(st.fill.angle)

        strokeOn.state = st.stroke.visible ? .on : .off
        strokeColor.color = st.stroke.color.ns
        strokeWidth.set(st.stroke.width)
        dashPopup.selectItem(at: DashKind.allCases.firstIndex(of: st.stroke.dash) ?? 0)
        capPopup.selectItem(at: CapKind.allCases.firstIndex(of: st.stroke.cap) ?? 0)
        joinPopup.selectItem(at: JoinKind.allCases.firstIndex(of: st.stroke.join) ?? 0)

        shadowOn.state = st.shadow.enabled ? .on : .off
        shadowColor.color = st.shadow.color.ns
        shadowAngle.set(st.shadow.angle)
        shadowBlur.set(st.shadow.blur)
        shadowOffset.set(st.shadow.offset)
        opacity.set(st.opacity)
        radius.set(st.cornerRadius)
        rotation.set(shapes.first?.rotation ?? 0)

        selectFont(st.text.font)
        fontSize.set(st.text.size)
        boldBtn.state = st.text.bold ? .on : .off
        italicBtn.state = st.text.italic ? .on : .off
        underlineBtn.state = st.text.underline ? .on : .off
        hAlign.selectedSegment = HAlign.allCases.firstIndex(of: st.text.hAlign) ?? 1
        vAlign.selectedSegment = VAlign.allCases.firstIndex(of: st.text.vAlign) ?? 1
        autoTextColor.state = st.text.color == nil ? .on : .off
        textColor.color = (st.text.color ?? RGBA(0, 0, 0)).ns
        textColor.isEnabled = st.text.color != nil

        if let c = conns.first {
            routePopup.selectItem(at: Route.allCases.firstIndex(of: c.route) ?? 0)
            startHead.selectItem(at: HeadKind.allCases.firstIndex(of: c.startHead) ?? 0)
            endHead.selectItem(at: HeadKind.allCases.firstIndex(of: c.endHead) ?? 0)
            headSize.set(c.headScale)
        }

        // What each selection needs:
        //  nothing selected -> style defaults for new objects (no text, no connector options)
        //  shapes           -> fill, line, shadow, object, text
        //  connectors       -> line, shadow, object, text (labels) and connector options; no fill
        let onlyConnectors = shapes.isEmpty && !conns.isEmpty
        let hasSelection = !shapes.isEmpty || !conns.isEmpty
        fillSection.isHidden = onlyConnectors
        textSection.isHidden = !hasSelection
        connectorSection.isHidden = conns.isEmpty

        let kind = st.fill.kind
        let isGradient = kind == .linear || kind == .radial
        fillColorRow.isHidden = kind != .solid
        colorPresets.isHidden = kind == .none
        if kind == .solid { colorPresets.selectedColor = st.fill.color }
        else if st.fill.stops.indices.contains(gradientEditor.selected) { colorPresets.selectedColor = st.fill.stops[gradientEditor.selected].color }
        else { colorPresets.selectedColor = nil }
        for v in gradientRows { v.isHidden = !isGradient }
        fillAngle.row.isHidden = kind != .linear
        for v in shadowDetailRows { v.isHidden = !st.shadow.enabled }
        radius.row.isHidden = onlyConnectors
        rotation.row.isHidden = shapes.isEmpty

        switch (shapes.count, conns.count) {
        case (0, 0): header.stringValue = "New objects"
        case (let s, 0): header.stringValue = s == 1 ? "Shape" : "\(s) shapes"
        case (0, let c): header.stringValue = c == 1 ? "Connector" : "\(c) connectors"
        default: header.stringValue = "\(shapes.count + conns.count) objects"
        }
        // Locked objects keep their geometry, so rotation is unavailable when everything selected is locked.
        let everythingLocked = hasSelection && shapes.allSatisfy(\.locked) && conns.allSatisfy(\.locked)
        if everythingLocked { header.stringValue += " (locked)" }
        rotation.setEnabled(!(shapes.allSatisfy(\.locked) && !shapes.isEmpty))

        refreshLayers()
    }

    // MARK: Layers pane

    private func buildLayersPane() -> NSView {
        func column(_ id: String, _ title: String, _ width: CGFloat) -> NSTableColumn {
            let c = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(id))
            c.title = title
            c.width = width
            if id != "name" { c.minWidth = width; c.maxWidth = width }
            return c
        }
        layerTable.addTableColumn(column("vis", "Show", 40))
        layerTable.addTableColumn(column("lock", "Lock", 40))
        layerTable.addTableColumn(column("name", "Layer", 120))
        layerTable.dataSource = self
        layerTable.delegate = self
        layerTable.rowHeight = 24
        layerTable.usesAlternatingRowBackgroundColors = true
        layerTable.allowsEmptySelection = false

        let tableScroll = NSScrollView()
        tableScroll.documentView = layerTable
        tableScroll.hasVerticalScroller = true
        tableScroll.borderType = .bezelBorder
        tableScroll.translatesAutoresizingMaskIntoConstraints = false
        tableScroll.heightAnchor.constraint(equalToConstant: 150).isActive = true
        tableScroll.widthAnchor.constraint(equalToConstant: 232).isActive = true

        func button(_ title: String, tip: String, _ handler: @escaping () -> Void) -> NSButton {
            let b = NSButton(title: title, target: nil, action: nil)
            b.bezelStyle = .texturedRounded
            b.controlSize = .small
            b.toolTip = tip
            bind(b) { _ in handler() }
            return b
        }
        let buttons = NSStackView(views: [
            button("+", tip: "New layer above the active one") { [unowned self] in canvas?.addLayer() },
            button("−", tip: "Delete the active layer and its objects") { [unowned self] in
                if let id = canvas?.activeLayerID { canvas?.deleteLayer(id) }
            },
            button("▲", tip: "Bring layer forward") { [unowned self] in
                if let id = canvas?.activeLayerID { canvas?.moveLayer(id, up: true) }
            },
            button("▼", tip: "Send layer backward") { [unowned self] in
                if let id = canvas?.activeLayerID { canvas?.moveLayer(id, up: false) }
            },
        ])
        buttons.spacing = 6

        let moveBtn = button("Move Selection to This Layer", tip: "Move selected objects onto the active layer") { [unowned self] in
            if let id = canvas?.activeLayerID { canvas?.moveSelection(toLayer: id) }
        }

        let box = NSStackView(views: [sectionTitle("Layers (top = front)"), tableScroll, buttons, moveBtn])
        box.orientation = .vertical
        box.alignment = .leading
        box.spacing = 9
        box.edgeInsets = NSEdgeInsets(top: 10, left: 14, bottom: 14, right: 14)
        box.translatesAutoresizingMaskIntoConstraints = false
        box.toolTip = "New objects are created on the highlighted layer. Hidden or locked layers can't be selected."
        return box
    }

    private func layer(atRow row: Int) -> Layer? {
        guard let layers = canvas?.drawing.layers, row >= 0, row < layers.count else { return nil }
        return layers[layers.count - 1 - row]   // top layer first
    }

    func refreshLayers(force: Bool = false) {
        guard let canvas else { return }
        let layers = canvas.drawing.layers
        updating = true
        defer { updating = false }
        if force || layers != layersCache {
            layersCache = layers
            layerTable.reloadData()
        }
        if let active = layers.firstIndex(where: { $0.id == canvas.activeLayerID }) {
            let row = layers.count - 1 - active
            if layerTable.selectedRow != row { layerTable.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false) }
        }
    }

    func numberOfRows(in tableView: NSTableView) -> Int { canvas?.drawing.layers.count ?? 0 }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard let l = layer(atRow: row), let id = tableColumn?.identifier.rawValue else { return nil }
        switch id {
        case "vis", "lock":
            let b = NSButton(checkboxWithTitle: "", target: self, action: #selector(layerFlagToggled(_:)))
            b.identifier = NSUserInterfaceItemIdentifier(id)
            b.state = (id == "vis" ? l.visible : l.locked) ? .on : .off
            return b
        default:
            let f = NSTextField(string: l.name)
            f.isBordered = false
            f.drawsBackground = false
            f.isEditable = true
            f.font = .systemFont(ofSize: 12)
            f.delegate = self
            return f
        }
    }

    @objc private func layerFlagToggled(_ sender: NSButton) {
        let row = layerTable.row(for: sender)
        guard let l = layer(atRow: row) else { return }
        if sender.identifier?.rawValue == "vis" {
            canvas?.setLayer(l.id, visible: sender.state == .on)
        } else {
            canvas?.setLayer(l.id, locked: sender.state == .on)
        }
    }

    func controlTextDidEndEditing(_ obj: Notification) {
        guard let field = obj.object as? NSTextField else { return }
        let row = layerTable.row(for: field)
        if let l = layer(atRow: row) { canvas?.renameLayer(l.id, to: field.stringValue) }
        layerTable.reloadData()
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        guard !updating, let l = layer(atRow: layerTable.selectedRow) else { return }
        canvas?.setActiveLayer(l.id)
    }
}
