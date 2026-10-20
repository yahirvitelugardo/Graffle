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
    l.font = Tok.Font.label()
    l.textColor = Tok.textSecondary
    l.widthAnchor.constraint(equalToConstant: 66).isActive = true
    return l
}

/// A card in the inspector: a titled group of controls on a rounded, outlined surface.
private final class DisclosureSection: NSStackView {
    let title: String
    private let body: NSStackView

    init(_ title: String, _ views: [NSView]) {
        self.title = title
        body = NSStackView(views: views)
        super.init(frame: .zero)

        body.orientation = .vertical
        body.alignment = .leading
        body.spacing = 8

        orientation = .vertical
        alignment = .leading
        spacing = 10
        edgeInsets = NSEdgeInsets(top: Tok.Space.cardPadding, left: Tok.Space.cardPadding, bottom: Tok.Space.cardPadding, right: Tok.Space.cardPadding)
        wantsLayer = true
        layer?.cornerRadius = Tok.Radius.card
        layer?.cornerCurve = .continuous
        layer?.borderWidth = 0.5
        updateCard()

        if !title.isEmpty {
            let label = NSTextField(labelWithString: title)
            label.font = Tok.Font.section()
            label.textColor = Tok.textPrimary
            label.setAccessibilityRole(.staticText)
            addArrangedSubview(label)
        }
        addArrangedSubview(body)
        widthAnchor.constraint(equalToConstant: 264).isActive = true
    }

    required init?(coder: NSCoder) { fatalError() }

    private func updateCard() {
        layer?.backgroundColor = Tok.resolve(Tok.cardBG, for: self)
        layer?.borderColor = Tok.resolve(Tok.cardOutline, for: self)
    }
    override func viewDidChangeEffectiveAppearance() { super.viewDidChangeEffectiveAppearance(); updateCard() }
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
        row.widthAnchor.constraint(equalToConstant: 240).isActive = true
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
        row.widthAnchor.constraint(equalToConstant: 240).isActive = true
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

final class InspectorView: NSView, NSTextFieldDelegate {
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
    private let header = NSTextField(labelWithString: "")
    private let topArea = NSView()

    // Sections (all live in one scrolling column)
    private var stylesSection: DisclosureSection!
    private var fillSection: DisclosureSection!
    /// The Navigator, above everything else in the sidebar.
    private var lineSection: DisclosureSection!
    private var shadowSection: DisclosureSection!
    private var objectSection: DisclosureSection!
    private var geometrySection: DisclosureSection!
    private var arrangeSection: DisclosureSection!

    // Header, tabs, geometry, hex fields, export
    private let tabs = DesignSegmented(titles: ["Style", "Arrange", "Text"])
    private var tabStacks: [NSStackView] = []
    private let tile = SurfaceView(frame: .zero)
    private let tileIcon = NSImageView()
    private let nameField = DesignField()
    private let typeLabel = NSTextField(labelWithString: "")
    private var geometryFields: [GeoField] = []
    private let fillHex = DesignField(), strokeHex = DesignField()
    private let paletteButton = IconButton(symbol: "paintpalette", label: "Color presets", tip: "Color presets", size: 28, pointSize: 13)
    private let presetsPopover = NSPopover()
    private let moveToLayer = NSPopUpButton()
    private var exportCard: DisclosureSection!
    var selectedTab: Int { tabs.selected }
    func selectTab(_ i: Int) { tabs.selected = i }
    var headerTitle: String { nameField.stringValue }
    var headerType: String { typeLabel.stringValue }
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
    private let opacity = SliderRow("Overall", 0, 1, suffix: "%", displayScale: 100)       // the whole object, fill and line
    private let fillOpacity = SliderRow("Opacity", 0, 1, suffix: "%", displayScale: 100)   // the fill only
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

    /// A smaller copy of a menu picture with empty margin around it, so it doesn't touch the edges of the pop-up or its menu rows.
    private static func inset(_ image: NSImage, scale: CGFloat = 0.72, margin: CGFloat = 5) -> NSImage {
        let drawn = NSSize(width: (image.size.width * scale).rounded(), height: (image.size.height * scale).rounded())
        let out = NSImage(size: NSSize(width: drawn.width + margin * 2, height: drawn.height + margin * 2), flipped: false) { _ in
            image.draw(in: NSRect(x: margin, y: margin, width: drawn.width, height: drawn.height), from: .zero, operation: .sourceOver, fraction: 1)
            return true
        }
        out.isTemplate = image.isTemplate
        return out
    }

    /// A pop-up whose items are pictures; the name is only a tooltip.
    private func fillImages(_ popup: NSPopUpButton, _ images: [NSImage], tips: [String]) {
        popup.removeAllItems()
        for (img, tip) in zip(images, tips) {
            let item = NSMenuItem(title: "", action: nil, keyEquivalent: "")
            item.image = InspectorView.inset(img)
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
        configureHexField(fillHex) { [unowned self] c in
            canvas?.applyStyle("Fill Color") { $0.fill.kind = $0.fill.kind == .none ? .solid : $0.fill.kind
                if $0.fill.kind == .solid { $0.fill.color = RGBA(c.r, c.g, c.b, $0.fill.color.a) } }
        }
        configureHexField(strokeHex) { [unowned self] c in
            canvas?.applyStyle("Line Color") { $0.stroke.color = RGBA(c.r, c.g, c.b, $0.stroke.color.a) }
        }
        paletteButton.target = self; paletteButton.action = #selector(showPresets(_:))
        presetsPopover.behavior = .transient
        let popContent = NSViewController()
        let popHolder = NSView(frame: NSRect(x: 0, y: 0, width: 264, height: 100))
        colorPresets.translatesAutoresizingMaskIntoConstraints = false
        popHolder.addSubview(colorPresets)
        NSLayoutConstraint.activate([
            colorPresets.leadingAnchor.constraint(equalTo: popHolder.leadingAnchor, constant: 12), colorPresets.topAnchor.constraint(equalTo: popHolder.topAnchor, constant: 12),
            popHolder.widthAnchor.constraint(equalToConstant: 264), popHolder.heightAnchor.constraint(equalToConstant: 100),
        ])
        popContent.view = popHolder
        presetsPopover.contentViewController = popContent
        let fillSwatchRow = NSStackView(views: [fillColor, fillHex, paletteButton])
        fillSwatchRow.spacing = 8; fillSwatchRow.alignment = .centerY
        fillHex.widthAnchor.constraint(equalToConstant: 96).isActive = true
        fillColorRow = row("Color", fillSwatchRow)
        gradientEditor.widthAnchor.constraint(equalToConstant: 240).isActive = true
        gradientEditor.heightAnchor.constraint(equalToConstant: 46).isActive = true
        gradientEditor.toolTip = "Click the bar to add a color stop. Drag a marker to move it (Shift = 5% steps). Delete removes the selected stop."
        for b in [removeStopBtn, reverseBtn] { b.bezelStyle = .texturedRounded; b.controlSize = .small }
        let stopColorRow = row("Stop color", stopColor)
        let stopButtons = NSStackView(views: [removeStopBtn, reverseBtn])
        stopButtons.spacing = 6
        gradientRows = [gradientEditor, stopColorRow, stopPosition.row, stopButtons]

        colorPresets.widthAnchor.constraint(equalToConstant: 240).isActive = true
        colorPresets.heightAnchor.constraint(equalToConstant: 76).isActive = true
        strokeColor.setContentHuggingPriority(.required, for: .horizontal)
        stylePalette.widthAnchor.constraint(equalToConstant: 240).isActive = true
        stylePalette.library = library
        stylesSection = DisclosureSection("Styles", [stylePalette])
        fillSection = DisclosureSection("Fill", [row("Type", fillKind), fillColorRow,
                                                 gradientEditor, stopColorRow, stopPosition.row, stopButtons, fillAngle.row, fillOpacity.row])
        strokeHex.widthAnchor.constraint(equalToConstant: 96).isActive = true
        let strokeSwatchRow = NSStackView(views: [strokeColor, strokeHex]); strokeSwatchRow.spacing = 8; strokeSwatchRow.alignment = .centerY
        lineSection = DisclosureSection("Stroke", [strokeOn, row("Color", strokeSwatchRow), strokeWidth.row,
                                                 row("Pattern", dashPopup), row("Cap", capPopup), row("Corner", joinPopup)])
        // Only the checkbox is always there; the rest appear while the shadow is on.
        shadowDetailRows = [row("Color", shadowColor), shadowAngle.row, shadowBlur.row, shadowOffset.row]
        shadowSection = DisclosureSection("Opacity & Shadow", [opacity.row, shadowOn] + shadowDetailRows)
        buildGeometry()
        objectSection = DisclosureSection("", [])                                 // (kept so older code paths find a hidden section)
        objectSection.isHidden = true
        buildArrange()

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

        // The three tabs.
        func stack(_ views: [NSView]) -> NSStackView {
            let st = NSStackView(views: views)
            st.orientation = .vertical; st.alignment = .leading; st.spacing = Tok.Space.cardGap
            return st
        }
        tabStacks = [stack([geometrySection, stylesSection, fillSection, lineSection, shadowSection, connectorSection]), stack([arrangeSection]), stack([textSection])]
        let column = NSStackView(views: tabStacks)
        column.orientation = .vertical
        column.alignment = .leading
        column.spacing = 0
        column.edgeInsets = NSEdgeInsets(top: 4, left: 8, bottom: 12, right: 8)
        column.translatesAutoresizingMaskIntoConstraints = false
        tabs.onChange = { [unowned self] i in showTab(i) }
        showTab(0)
        buildHeader()
        buildExport()

        container.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(column)
        addSubview(topArea)
        addSubview(exportCard)
        exportCard.translatesAutoresizingMaskIntoConstraints = false
        scroll.documentView = container
        scroll.hasVerticalScroller = true
        scroll.scrollerStyle = .overlay
        scroll.drawsBackground = false
        scroll.translatesAutoresizingMaskIntoConstraints = false

        addSubview(scroll)
        NSLayoutConstraint.activate([
            column.topAnchor.constraint(equalTo: container.topAnchor),
            column.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            column.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            column.bottomAnchor.constraint(equalTo: container.bottomAnchor),

            topArea.topAnchor.constraint(equalTo: topAnchor), topArea.leadingAnchor.constraint(equalTo: leadingAnchor),
            topArea.trailingAnchor.constraint(equalTo: trailingAnchor),
            scroll.topAnchor.constraint(equalTo: topArea.bottomAnchor),
            scroll.leadingAnchor.constraint(equalTo: leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: trailingAnchor),
            scroll.bottomAnchor.constraint(equalTo: exportCard.topAnchor, constant: -Tok.Space.cardGap),
            container.widthAnchor.constraint(equalTo: scroll.contentView.widthAnchor),
            exportCard.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8), exportCard.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -8),
        ])
    }

    /// Titles of the sections currently on screen (used by the self-test).
    var visibleSectionTitles: [String] {
        [geometrySection, stylesSection, fillSection, lineSection, shadowSection, arrangeSection, textSection, connectorSection]
            .compactMap { $0 }.filter { !$0.isHidden && !$0.title.isEmpty }.map(\.title)
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
    var fillOpacityControl: SliderRow { fillOpacity }


    /// Height the scrolling column wants (used by the layout self-check).
    var currentPaneHeight: CGFloat { container.fittingSize.height }

    // MARK: Header, tabs, geometry, arrange, export

    private func showTab(_ i: Int) {
        for (n, st) in tabStacks.enumerated() { st.isHidden = n != i }
    }

    private func buildHeader() {
        tile.fill = Tok.hoverFill; tile.outline = nil; tile.radius = 10
        tile.translatesAutoresizingMaskIntoConstraints = false
        tileIcon.translatesAutoresizingMaskIntoConstraints = false
        tileIcon.contentTintColor = Tok.accent
        tile.addSubview(tileIcon)
        nameField.font = Tok.Font.title()
        nameField.textColor = Tok.textPrimary
        nameField.heightAnchor.constraint(equalToConstant: 26).isActive = true
        nameField.widthAnchor.constraint(greaterThanOrEqualToConstant: 170).isActive = true
        nameField.delegate = self
        nameField.setAccessibilityLabel("Object name")
        typeLabel.font = .systemFont(ofSize: 12); typeLabel.textColor = Tok.textSecondary
        let names = NSStackView(views: [nameField, typeLabel])
        names.orientation = .vertical; names.alignment = .leading; names.spacing = 1
        let headerRow = NSStackView(views: [tile, names])
        headerRow.orientation = .horizontal; headerRow.spacing = 11; headerRow.alignment = .centerY
        headerRow.translatesAutoresizingMaskIntoConstraints = false
        tabs.translatesAutoresizingMaskIntoConstraints = false
        topArea.translatesAutoresizingMaskIntoConstraints = false
        topArea.addSubview(tabs)
        topArea.addSubview(headerRow)
        NSLayoutConstraint.activate([
            tabs.topAnchor.constraint(equalTo: topArea.topAnchor, constant: 12), tabs.leadingAnchor.constraint(equalTo: topArea.leadingAnchor, constant: 12),
            tabs.trailingAnchor.constraint(equalTo: topArea.trailingAnchor, constant: -12),
            headerRow.topAnchor.constraint(equalTo: tabs.bottomAnchor, constant: 12), headerRow.leadingAnchor.constraint(equalTo: topArea.leadingAnchor, constant: 16),
            headerRow.trailingAnchor.constraint(equalTo: topArea.trailingAnchor, constant: -12), headerRow.bottomAnchor.constraint(equalTo: topArea.bottomAnchor, constant: -10),
            tile.widthAnchor.constraint(equalToConstant: 36), tile.heightAnchor.constraint(equalToConstant: 36),
            tileIcon.centerXAnchor.constraint(equalTo: tile.centerXAnchor), tileIcon.centerYAnchor.constraint(equalTo: tile.centerYAnchor),
        ])
    }

    private func buildExport() {
        func button(_ title: String, _ action: Selector) -> NSButton {
            let b = NSButton(title: title, target: nil, action: action)
            b.bezelStyle = .rounded; b.controlSize = .regular
            b.setAccessibilityLabel("Export as \(title)")
            b.toolTip = "Export as \(title)"
            return b
        }
        let row = NSStackView(views: [button("PNG", #selector(DocumentWindowController.exportPNG(_:))), button("PDF", #selector(DocumentWindowController.exportPDF(_:))),
                                      button("SVG", #selector(DocumentWindowController.exportSVG(_:)))])
        row.distribution = .fillEqually
        row.spacing = 8
        row.widthAnchor.constraint(equalToConstant: 240).isActive = true
        exportCard = DisclosureSection("Export", [row])
    }

    private func buildGeometry() {
        func field(_ title: String, _ apply: @escaping ([Shape], Double) -> Void, _ read: @escaping (Shape) -> Double) -> GeoField {
            let f = GeoField(title: title, apply: { [unowned self] v in
                guard let canvas, !canvas.selectedShapes.isEmpty else { return }
                apply(canvas.selectedShapes, v)
            }, read: read)
            f.field.delegate = self
            geometryFields.append(f)
            return f
        }
        func set(_ name: String, _ change: @escaping (inout Shape, Double) -> Void) -> ([Shape], Double) -> Void {
            { [unowned self] _, v in canvas?.applyShapes(name) { change(&$0, v) } }
        }
        let x = field("X", set("Move") { $0.frame.origin.x = $1 }) { $0.frame.minX }
        let y = field("Y", set("Move") { $0.frame.origin.y = $1 }) { $0.frame.minY }
        let w = field("W", set("Resize") { $0.frame.size.width = max(12, $1) }) { $0.frame.width }
        let h = field("H", set("Resize") { $0.frame.size.height = max(12, $1) }) { $0.frame.height }
        let top = NSStackView(views: [x.view, y.view]); top.spacing = 8; top.distribution = .fillEqually
        let bottom = NSStackView(views: [w.view, h.view]); bottom.spacing = 8; bottom.distribution = .fillEqually
        for r in [top, bottom] { r.widthAnchor.constraint(equalToConstant: 240).isActive = true }
        geometrySection = DisclosureSection("Geometry", [top, bottom, rotation.row, radius.row])
    }

    private func buildArrange() {
        func segmentButton(_ symbol: String, _ label: String, _ action: @escaping () -> Void) -> IconButton {
            let b = IconButton(symbol: symbol, label: label, tip: label, size: 36, pointSize: 14)
            b.target = self
            let a = Action { _ in action() }
            actions.append(a)
            b.target = a; b.action = #selector(Action.fire(_:))
            return b
        }
        func align(_ tag: Int) -> () -> Void { { [unowned self] in let item = NSMenuItem(); item.tag = tag; canvas?.align(item) } }
        let alignRow = NSStackView(views: [
            segmentButton("align.horizontal.left", "Align left", align(0)), segmentButton("align.horizontal.center", "Align center", align(1)),
            segmentButton("align.horizontal.right", "Align right", align(2)), segmentButton("align.vertical.top", "Align top", align(3)),
            segmentButton("align.vertical.center", "Align middle", align(4)), segmentButton("align.vertical.bottom", "Align bottom", align(5)),
        ])
        alignRow.spacing = 0; alignRow.distribution = .fillEqually
        alignRow.widthAnchor.constraint(equalToConstant: 240).isActive = true
        let distribute: (Int) -> () -> Void = { tag in { [unowned self] in let item = NSMenuItem(); item.tag = tag; canvas?.distribute(item) } }
        let match: (Int) -> () -> Void = { tag in { [unowned self] in let item = NSMenuItem(); item.tag = tag; canvas?.matchSize(item) } }
        let spread = NSStackView(views: [segmentButton("distribute.horizontal.center", "Distribute horizontally", distribute(0)),
                                         segmentButton("distribute.vertical.center", "Distribute vertically", distribute(1)),
                                         segmentButton("arrow.left.and.right", "Same width", match(0)), segmentButton("arrow.up.and.down", "Same height", match(1)),
                                         segmentButton("square.on.square", "Same size", match(2))])
        spread.spacing = 0; spread.distribution = .fillEqually
        spread.widthAnchor.constraint(equalToConstant: 240).isActive = true
        let order = NSStackView(views: [segmentButton("square.3.layers.3d.top.filled", "Bring to front", { [unowned self] in canvas?.bringToFront(nil) }),
                                        segmentButton("square.3.layers.3d.bottom.filled", "Send to back", { [unowned self] in canvas?.sendToBack(nil) })])
        order.spacing = 6; order.distribution = .fillEqually
        order.widthAnchor.constraint(equalToConstant: 240).isActive = true
        moveToLayer.controlSize = .small
        moveToLayer.widthAnchor.constraint(equalToConstant: InspectorView.popupWidth).isActive = true
        moveToLayer.target = self; moveToLayer.action = #selector(moveToLayerPicked(_:))
        moveToLayer.setAccessibilityLabel("Move to layer")
        let alignTitle = NSTextField(labelWithString: "Align"), orderTitle = NSTextField(labelWithString: "Order")
        for t in [alignTitle, orderTitle] { t.font = Tok.Font.label(); t.textColor = Tok.textSecondary }
        arrangeSection = DisclosureSection("Arrange", [alignTitle, alignRow, spread, orderTitle, order, row("Move to layer", moveToLayer)])
    }

    @objc private func moveToLayerPicked(_ s: NSPopUpButton) {
        guard let id = s.selectedItem?.representedObject as? UUID else { return }
        canvas?.moveSelection(toLayer: id)
    }

    @objc private func showPresets(_ s: NSButton) { presetsPopover.show(relativeTo: s.bounds, of: s, preferredEdge: .maxY) }

    /// A hex field ("#RRGGBB") that applies a color when it is committed.
    private func configureHexField(_ field: DesignField, _ apply: @escaping (RGBA) -> Void) {
        field.placeholderString = "#RRGGBB"
        field.setAccessibilityLabel("Hex color")
        let a = Action { sender in
            let text = (sender as? NSTextField)?.stringValue ?? ""
            if let c = RGBA(hex: text) { apply(c) }
        }
        actions.append(a)
        field.target = a; field.action = #selector(Action.fire(_:))
    }

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
        bind(fillOpacity.slider) { [unowned self] s in
            fillOpacity.refreshReadout()
            let v = s.doubleValue
            canvas?.applyStyle("Fill Opacity") { st in
                st.fill.color.a = v
                for i in st.fill.stops.indices { st.fill.stops[i].color.a = v }
            }
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
        switch st.fill.kind {
        case .none, .solid: fillOpacity.set(st.fill.color.a)
        case .linear, .radial:
            let alphas = st.fill.stops.map(\.color.a)
            fillOpacity.set(alphas.isEmpty ? 1 : alphas.reduce(0, +) / Double(alphas.count))
        }

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
        fillOpacity.row.isHidden = kind == .none
        if kind == .solid { colorPresets.selectedColor = st.fill.color }
        else if st.fill.stops.indices.contains(gradientEditor.selected) { colorPresets.selectedColor = st.fill.stops[gradientEditor.selected].color }
        else { colorPresets.selectedColor = nil }
        for v in gradientRows { v.isHidden = !isGradient }
        fillAngle.row.isHidden = kind != .linear
        for v in shadowDetailRows { v.isHidden = !st.shadow.enabled }
        radius.row.isHidden = onlyConnectors
        rotation.row.isHidden = shapes.isEmpty

        // The header: what is selected.
        var title: String, type: String, symbol: String
        switch (shapes.count, conns.count) {
        case (0, 0): title = "New objects"; type = "Style for the next shape you draw"; symbol = "plus.square.dashed"
        case (1, 0): title = shapes[0].displayName; type = shapes[0].kind.title; symbol = SidebarView.symbol(for: shapes[0].kind)
        case (let n, 0):
            title = "\(n) shapes"; symbol = "square.on.square"
            let kinds = Set(shapes.map(\.kind))
            type = kinds.count == 1 ? kinds.first!.title + "s" : "Mixed"
        case (0, 1): title = conns[0].displayName; type = conns[0].route.title + " connector"; symbol = "arrow.up.right"
        case (0, let c): title = "\(c) connectors"; type = "Connectors"; symbol = "arrow.up.right"
        default: title = "\(shapes.count + conns.count) objects"; type = "Mixed"; symbol = "square.on.square"
        }
        // Locked objects keep their geometry, so rotation is unavailable when everything selected is locked.
        let everythingLocked = hasSelection && shapes.allSatisfy(\.locked) && conns.allSatisfy(\.locked)
        if everythingLocked { type += " · locked" }
        if !nameField.isEditing { nameField.stringValue = title }
        nameField.isEditable = shapes.count == 1 && conns.isEmpty
        typeLabel.stringValue = type
        tileIcon.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)?.withSymbolConfiguration(.init(pointSize: 16, weight: .regular))
        header.stringValue = title
        for g in geometryFields { g.show(shapes) }
        geometrySection.isHidden = shapes.isEmpty
        arrangeSection.isHidden = !hasSelection
        fillHex.stringValue = st.fill.kind == .solid ? st.fill.color.hex.replacingOccurrences(of: "#", with: "#").prefix(7).description : ""
        strokeHex.stringValue = String(st.stroke.color.hex.prefix(7))
        paletteButton.isHidden = kind == .none
        if let layers = canvas.drawing.layers as [Layer]? {
            let ids = layers.map(\.id)
            if moveToLayer.itemArray.map({ $0.representedObject as? UUID }) != ids.reversed().map({ Optional($0) }) {
                moveToLayer.removeAllItems()
                for l in layers.reversed() { let it = NSMenuItem(title: l.name, action: nil, keyEquivalent: ""); it.representedObject = l.id; moveToLayer.menu?.addItem(it) }
            }
            if let i = moveToLayer.itemArray.firstIndex(where: { ($0.representedObject as? UUID) == canvas.activeLayerID }) { moveToLayer.selectItem(at: i) }
        }
        rotation.setEnabled(!(shapes.allSatisfy(\.locked) && !shapes.isEmpty))

    }

    // MARK: Layers pane

    // MARK: For tests

    private func geo(_ title: String) -> GeoField? { geometryFields.first { $0.field.accessibilityLabel() == title } }
    func setGeometry(_ title: String, to text: String) { geo(title)?.field.stringValue = text; geo(title)?.commit(); refresh() }
    func nudgeGeometry(_ title: String, by v: Double) { geo(title)?.nudge(v); refresh() }
    func geometryText(_ title: String) -> String { geo(title)?.field.stringValue ?? "?" }
    func geometryPlaceholder(_ title: String) -> String { geo(title)?.field.placeholderString ?? "" }
    func typeHex(fill text: String) { fillHex.stringValue = text; (fillHex.target as AnyObject).perform(fillHex.action, with: fillHex); refresh() }
    func typeHex(stroke text: String) { strokeHex.stringValue = text; (strokeHex.target as AnyObject).perform(strokeHex.action, with: strokeHex); refresh() }
    func rename(_ name: String) { nameField.stringValue = name; controlTextDidEndEditing(Notification(name: NSControl.textDidEndEditingNotification, object: nameField)) }
    func pressArrange(_ label: String) {
        func find(_ v: NSView) -> IconButton? { (v as? IconButton).flatMap { $0.accessibilityLabel() == label ? $0 : nil } ?? v.subviews.lazy.compactMap(find).first }
        if let b = find(arrangeSection) { _ = b.target?.perform(b.action, with: b) }
    }
    func chooseLayer(_ name: String) {
        if let i = moveToLayer.itemArray.firstIndex(where: { $0.title == name }) { moveToLayer.selectItem(at: i); moveToLayerPicked(moveToLayer) }
    }
    var exportButtonTitles: [String] {
        func buttons(_ v: NSView) -> [NSButton] { (v as? NSButton).map { [$0] } ?? v.subviews.flatMap(buttons) }
        return buttons(exportCard).map(\.title)
    }
    var exportFrame: CGRect { exportCard.frame }

    // MARK: Name and geometry fields

    func controlTextDidEndEditing(_ obj: Notification) {
        guard let field = obj.object as? NSTextField, !updating else { return }
        if field === nameField {
            if let canvas, canvas.selectedShapes.count == 1, canvas.selectedConnectors.isEmpty, let id = canvas.selectedShapes.first?.id { canvas.renameObject(id, to: field.stringValue) }
            refresh()
        } else if let g = geometryFields.first(where: { $0.field === field }) {
            g.commit()
            refresh()
        }
    }

    /// Up and down arrows nudge a number field by 1 (10 with Shift).
    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        guard let g = geometryFields.first(where: { $0.field === control }) else { return false }
        let step: Double = NSApp.currentEvent?.modifierFlags.contains(.shift) == true ? 10 : 1
        if commandSelector == #selector(NSResponder.moveUp(_:)) { g.nudge(step); refresh(); return true }
        if commandSelector == #selector(NSResponder.moveDown(_:)) { g.nudge(-step); refresh(); return true }
        return false
    }
}

/// A numeric field with a label that can be dragged to scrub the value.
final class GeoField: NSObject {
    let field = DesignField()
    let view = NSStackView()
    private let label = ScrubLabel()
    private let apply: (Double) -> Void
    private let read: (Shape) -> Double
    private(set) var current: Double?
    private(set) var isMixed = false

    init(title: String, apply: @escaping (Double) -> Void, read: @escaping (Shape) -> Double) {
        self.apply = apply; self.read = read
        super.init()
        label.stringValue = title
        label.font = Tok.Font.label(); label.textColor = Tok.textSecondary
        label.widthAnchor.constraint(equalToConstant: 14).isActive = true
        label.toolTip = "Drag to change"
        label.onScrub = { [weak self] delta in self?.scrub(by: delta) }
        field.alignment = .left
        field.font = Tok.Font.number()
        field.setAccessibilityLabel(title)
        field.target = self; field.action = #selector(committed(_:))
        view.setViews([label, field], in: .leading)
        view.orientation = .horizontal; view.spacing = 6; view.alignment = .centerY
    }

    /// Shows the shared value of `shapes`, or "Mixed".
    func show(_ shapes: [Shape]) {
        let values = shapes.map(read)
        guard let first = values.first else { current = nil; isMixed = false; field.stringValue = ""; field.isEnabled = false; return }
        field.isEnabled = true
        if values.allSatisfy({ abs($0 - first) < 0.01 }) { current = first; isMixed = false; field.stringValue = GeoField.format(first) }
        else { current = nil; isMixed = true; field.stringValue = ""; field.placeholderString = "Mixed" }
    }

    static func format(_ v: Double) -> String { v.rounded() == v ? String(Int(v)) : String(format: "%.1f", v) }

    @objc private func committed(_ s: Any?) { commit() }
    func commit() {
        let text = field.stringValue.trimmingCharacters(in: .whitespaces)
        guard let v = Double(text.replacingOccurrences(of: ",", with: ".")) else { return }
        apply(v)
    }
    func nudge(_ by: Double) { apply((current ?? Double(field.stringValue) ?? 0) + by) }
    private var scrubStart: Double = 0
    private func scrub(by delta: Double) {
        if delta == .infinity { scrubStart = current ?? Double(field.stringValue) ?? 0; return }
        apply((scrubStart + delta).rounded())
    }
}

/// A label whose horizontal drag reports a distance, to scrub the number next to it.
final class ScrubLabel: NSTextField {
    var onScrub: ((Double) -> Void)?
    private var startX: CGFloat = 0
    convenience init() { self.init(frame: .zero); isEditable = false; isBordered = false; drawsBackground = false }
    override init(frame frameRect: NSRect) { super.init(frame: frameRect); isEditable = false; isBordered = false; drawsBackground = false; isSelectable = false }
    required init?(coder: NSCoder) { fatalError("not used") }
    override func resetCursorRects() { addCursorRect(bounds, cursor: .resizeLeftRight) }
    override func mouseDown(with event: NSEvent) { startX = event.locationInWindow.x; onScrub?(.infinity) }
    override func mouseDragged(with event: NSEvent) {
        let scale: Double = event.modifierFlags.contains(.shift) ? 10 : 1
        onScrub?(Double(event.locationInWindow.x - startX) / 2 * scale)
    }
}
