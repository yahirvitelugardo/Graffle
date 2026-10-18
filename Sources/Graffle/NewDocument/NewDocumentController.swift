import AppKit
import UniformTypeIdentifiers

/// A kind of document the user can start.
struct DocumentTemplate: Equatable {
    enum Kind: Equatable { case blank, architecture, classes, starter }
    let kind: Kind
    let title: String
    let subtitle: String
    /// For `.starter` templates: which ready-made diagram opens.
    var starter: Starter? = nil

    static let all: [DocumentTemplate] = [
        DocumentTemplate(kind: .blank, title: "Blank Diagram", subtitle: "An empty canvas to draw on."),
        DocumentTemplate(kind: .architecture, title: "Software Architecture Diagram",
                         subtitle: "Reverse engineer the modules of an Xcode, Swift, .NET or Android project and what depends on what."),
        DocumentTemplate(kind: .classes, title: "Classes Diagram",
                         subtitle: "Reverse engineer the classes, structs, enums and protocols of a project (Swift, C#, Kotlin, Java) with their members and relationships."),
    ] + Starter.allCases.map { DocumentTemplate(kind: .starter, title: $0.title, subtitle: $0.subtitle, starter: $0) }

    /// Which sample picture stands for this template.
    var sample: ThemePreview.Sample? {
        switch kind {
        case .blank: return nil
        case .architecture: return .architecture
        case .classes: return .classes
        case .starter: return starter.map { .starter($0) }
        }
    }
}

/// A rounded, clickable tile that can be selected; the building block of the galleries in the chooser.
final class SelectableCard: NSView {
    var isSelected = false { didSet { needsDisplay = true } }
    var onSelect: (() -> Void)?
    var onDoubleClick: (() -> Void)?

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    override func mouseDown(with event: NSEvent) {
        if event.clickCount >= 2 { onDoubleClick?() } else { onSelect?() }
    }
    override func accessibilityPerformPress() -> Bool { onSelect?(); return true }
    override func draw(_ dirtyRect: NSRect) {
        let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 1.5, dy: 1.5), xRadius: 10, yRadius: 10)
        NSColor.controlBackgroundColor.setFill()
        path.fill()
        (isSelected ? NSColor.controlAccentColor : NSColor.separatorColor).setStroke()
        path.lineWidth = isSelected ? 3 : 1
        path.stroke()
    }
}

/// Shows a picture on a small white page with rounded corners, scaled to fit with a little margin; with no picture it is a blank page.
private final class PreviewImageView: NSView {
    var image: NSImage? { didSet { needsDisplay = true } }
    var blankPage = false { didSet { needsDisplay = true } }
    override var isFlipped: Bool { true }
    override func draw(_ dirtyRect: NSRect) {
        let clip = NSBezierPath(roundedRect: bounds, xRadius: 7, yRadius: 7)
        (blankPage || image != nil ? NSColor.white : NSColor.quaternaryLabelColor).setFill()
        clip.fill()
        NSColor.separatorColor.setStroke()
        clip.lineWidth = 0.5
        clip.stroke()
        guard let image else { return }
        clip.addClip()
        let area = bounds.insetBy(dx: 5, dy: 5)
        let s = min(area.width / image.size.width, area.height / image.size.height)
        let w = image.size.width * s, h = image.size.height * s
        image.draw(in: NSRect(x: (bounds.width - w) / 2, y: (bounds.height - h) / 2, width: w, height: h), from: .zero, operation: .sourceOver,
                   fraction: 1, respectFlipped: true, hints: [.interpolation: NSImageInterpolation.high.rawValue])
    }
}

/// Cards laid out in a grid that reflows with the width.
private final class CardGridView: NSView {
    var cardSize = NSSize(width: 250, height: 188)
    var gap: CGFloat = 16
    var cards: [SelectableCard] = [] {
        didSet { oldValue.forEach { $0.removeFromSuperview() }; cards.forEach(addSubview); needsLayout = true }
    }
    override var isFlipped: Bool { true }
    override func layout() {
        super.layout()
        let columns = max(1, Int((bounds.width + gap) / (cardSize.width + gap)))
        for (i, card) in cards.enumerated() {
            card.frame = NSRect(x: CGFloat(i % columns) * (cardSize.width + gap), y: CGFloat(i / columns) * (cardSize.height + gap),
                                width: cardSize.width, height: cardSize.height)
        }
        let rows = (cards.count + columns - 1) / columns
        let height = CGFloat(rows) * (cardSize.height + gap)
        if abs(frame.height - height) > 0.5 { setFrameSize(NSSize(width: frame.width, height: height)) }
    }
}

/// The New Document window: a two-step wizard in one window. Step 1 shows the kinds of diagram to start (Blank, Software
/// Architecture, Classes) as a gallery; step 2 shows the themes, drawn on a sample of what was chosen. As a sheet, with only
/// the themes step, it is View → Theme….
final class NewDocumentController: NSWindowController, NSWindowDelegate {
    enum Mode { case newDocument, themeOnly }
    enum Step { case template, theme }

    /// What the user picked.
    struct Choice {
        var template: DocumentTemplate
        var theme: ThemeDefinition
    }

    private static let lastTemplateKey = "newDocument.template", lastThemeKey = "newDocument.theme"
    nonisolated(unsafe) private static var current: NewDocumentController?

    private let mode: Mode
    private let onChoose: (Choice) -> Void
    private(set) var step: Step
    private var themes: [ThemeDefinition] = []
    private var themeCards: [String: SelectableCard] = [:]
    private var themePreviews: [String: PreviewImageView] = [:]
    private var templateCards: [SelectableCard] = []
    private var templateCaptions: [NSTextField] = []
    private var templatePreviews: [PreviewImageView] = []
    private(set) var template = DocumentTemplate.all[0]
    private(set) var selectedTheme = ThemeLibrary.clean
    private let templateGrid = CardGridView()
    private let themeGrid = CardGridView()
    private var templateScroll: NSScrollView!
    private var themeScroll: NSScrollView!
    private let heading = NSTextField(labelWithString: "")
    private let hint = NSTextField(labelWithString: "")
    private let detail = NSTextField(wrappingLabelWithString: "")
    private var primaryButton: NSButton!
    private var backButton: NSButton!
    private var importButton: NSButton!
    private var renderTimers: [Timer] = []

    // MARK: Presenting

    /// File → New: choose what to start, then a theme.
    @discardableResult
    static func presentNewDocument(onChoose: @escaping (Choice) -> Void) -> NewDocumentController {
        if let existing = current { existing.window?.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true); return existing }
        let c = NewDocumentController(mode: .newDocument, selected: nil, onChoose: onChoose)
        current = c
        c.showWindow(nil)
        c.window?.center()
        NSApp.activate(ignoringOtherApps: true)
        return c
    }

    /// View → Theme…: a sheet on a document window that picks a theme for it.
    @discardableResult
    static func presentThemePicker(on parent: NSWindow, selected: ThemeDefinition?, onChoose: @escaping (ThemeDefinition) -> Void) -> NewDocumentController {
        let c = NewDocumentController(mode: .themeOnly, selected: selected) { onChoose($0.theme) }
        current = c
        parent.beginSheet(c.window!) { _ in current = nil }
        return c
    }

    private init(mode: Mode, selected: ThemeDefinition?, onChoose: @escaping (Choice) -> Void) {
        self.mode = mode
        self.onChoose = onChoose
        self.step = mode == .newDocument ? .template : .theme
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: mode == .newDocument ? 1020 : 880, height: 660),
                              styleMask: mode == .newDocument ? [.titled, .closable, .resizable] : [.titled, .resizable],
                              backing: .buffered, defer: false)
        window.title = mode == .newDocument ? "New Document" : "Choose Theme"
        window.minSize = NSSize(width: 620, height: 460)
        window.isReleasedWhenClosed = false
        super.init(window: window)
        window.delegate = self
        themes = ThemeLibrary.all
        if let selected, themes.contains(where: { $0.id == selected.id }) { selectedTheme = selected }
        else if let id = UserDefaults.standard.string(forKey: Self.lastThemeKey), mode == .newDocument,
                let remembered = themes.first(where: { $0.id == id }) { selectedTheme = remembered }
        else { selectedTheme = themes.first { $0.isClean } ?? ThemeLibrary.clean }
        if mode == .newDocument, let raw = UserDefaults.standard.string(forKey: Self.lastTemplateKey),
           let t = DocumentTemplate.all.first(where: { $0.title == raw }) { template = t }
        build()
        refresh()
        NotificationCenter.default.addObserver(self, selector: #selector(themesChanged), name: .themesChanged, object: nil)
        renderTemplatePreviews()
        if step == .theme { renderThemePreviews() }
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    // MARK: Building the window

    private func label(_ text: String, size: CGFloat, weight: NSFont.Weight = .regular, color: NSColor = .labelColor) -> NSTextField {
        let l = NSTextField(labelWithString: text)
        l.font = .systemFont(ofSize: size, weight: weight)
        l.textColor = color
        l.lineBreakMode = .byTruncatingTail
        return l
    }

    private func build() {
        guard let content = window?.contentView else { return }
        heading.font = .systemFont(ofSize: 22, weight: .semibold)
        hint.font = .systemFont(ofSize: 12)
        hint.textColor = .secondaryLabelColor
        [heading, hint].forEach { $0.translatesAutoresizingMaskIntoConstraints = false; $0.lineBreakMode = .byTruncatingTail; content.addSubview($0) }

        // Step 1: the gallery of what to start.
        templateGrid.cardSize = NSSize(width: 270, height: 232)
        templateGrid.gap = 22
        templateScroll = scrollView(containing: templateGrid)
        buildTemplateCards()

        // Step 2: the gallery of themes.
        themeGrid.cardSize = NSSize(width: 250, height: 188)
        themeScroll = scrollView(containing: themeGrid)
        buildThemeCards()

        detail.font = .systemFont(ofSize: 12)
        detail.textColor = .secondaryLabelColor
        detail.maximumNumberOfLines = 2
        detail.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(detail)

        importButton = NSButton(title: "Import Theme…", target: self, action: #selector(importTheme(_:)))
        backButton = NSButton(title: "Back", target: self, action: #selector(back(_:)))
        let cancel = NSButton(title: "Cancel", target: self, action: #selector(cancel(_:)))
        cancel.keyEquivalent = "\u{1b}"
        primaryButton = NSButton(title: "Choose", target: self, action: #selector(primary(_:)))
        primaryButton.keyEquivalent = "\r"
        [importButton, backButton, cancel, primaryButton].forEach { $0.translatesAutoresizingMaskIntoConstraints = false; content.addSubview($0) }

        NSLayoutConstraint.activate([
            heading.topAnchor.constraint(equalTo: content.topAnchor, constant: 22), heading.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 28),
            heading.trailingAnchor.constraint(lessThanOrEqualTo: content.trailingAnchor, constant: -28),
            hint.topAnchor.constraint(equalTo: heading.bottomAnchor, constant: 4), hint.leadingAnchor.constraint(equalTo: heading.leadingAnchor),
            hint.trailingAnchor.constraint(lessThanOrEqualTo: content.trailingAnchor, constant: -28),
            detail.leadingAnchor.constraint(equalTo: heading.leadingAnchor), detail.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -28),
            detail.bottomAnchor.constraint(equalTo: primaryButton.topAnchor, constant: -14),
            primaryButton.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -22), primaryButton.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -18),
            cancel.trailingAnchor.constraint(equalTo: primaryButton.leadingAnchor, constant: -10), cancel.centerYAnchor.constraint(equalTo: primaryButton.centerYAnchor),
            backButton.trailingAnchor.constraint(equalTo: cancel.leadingAnchor, constant: -10), backButton.centerYAnchor.constraint(equalTo: primaryButton.centerYAnchor),
            importButton.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 22), importButton.centerYAnchor.constraint(equalTo: primaryButton.centerYAnchor),
            primaryButton.widthAnchor.constraint(greaterThanOrEqualToConstant: 90), cancel.widthAnchor.constraint(greaterThanOrEqualToConstant: 80),
            backButton.widthAnchor.constraint(greaterThanOrEqualToConstant: 80),
        ])
        for scroll in [templateScroll!, themeScroll!] {
            NSLayoutConstraint.activate([
                scroll.topAnchor.constraint(equalTo: hint.bottomAnchor, constant: 18),
                scroll.leadingAnchor.constraint(equalTo: heading.leadingAnchor),
                scroll.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -22),
                scroll.bottomAnchor.constraint(equalTo: detail.topAnchor, constant: -10),
            ])
        }
        window?.defaultButtonCell = primaryButton.cell as? NSButtonCell
        content.layoutSubtreeIfNeeded()
        for (scroll, grid) in [(templateScroll!, templateGrid), (themeScroll!, themeGrid)] {      // then each follows its scroll view
            grid.setFrameSize(NSSize(width: scroll.contentSize.width, height: grid.frame.height))
        }
    }

    private func scrollView(containing grid: CardGridView) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.drawsBackground = false
        scroll.borderType = .noBorder
        scroll.translatesAutoresizingMaskIntoConstraints = false
        grid.autoresizingMask = [.width]
        scroll.documentView = grid
        window?.contentView?.addSubview(scroll)
        return scroll
    }

    /// One tall card per kind of diagram: a picture of the page, and its name underneath.
    private func buildTemplateCards() {
        templateCards = []; templateCaptions = []; templatePreviews = []
        for t in DocumentTemplate.all {
            let card = SelectableCard(frame: NSRect(origin: .zero, size: templateGrid.cardSize))
            let preview = PreviewImageView(frame: NSRect(x: 12, y: 12, width: templateGrid.cardSize.width - 24, height: 168))
            preview.blankPage = t.kind == .blank
            let caption = NSTextField(labelWithString: t.title)
            caption.font = .systemFont(ofSize: 13, weight: .medium)
            caption.alignment = .center
            caption.lineBreakMode = .byTruncatingTail
            caption.wantsLayer = true
            caption.layer?.cornerRadius = 5
            caption.frame = NSRect(x: 12, y: 192, width: templateGrid.cardSize.width - 24, height: 22)
            [preview, caption].forEach(card.addSubview)
            card.onSelect = { [weak self] in self?.template = t; self?.refresh() }
            card.onDoubleClick = { [weak self] in self?.template = t; self?.next() }
            card.setAccessibilityLabel(t.title)
            templateCards.append(card); templateCaptions.append(caption); templatePreviews.append(preview)
        }
        templateGrid.cards = templateCards
    }

    private func buildThemeCards() {
        themeCards = [:]
        themePreviews = [:]
        var cards: [SelectableCard] = []
        for theme in themes {
            let card = SelectableCard(frame: NSRect(origin: .zero, size: themeGrid.cardSize))
            let preview = PreviewImageView(frame: NSRect(x: 8, y: 8, width: themeGrid.cardSize.width - 16, height: 138))
            let name = label(theme.name, size: 13, weight: .semibold)
            name.frame = NSRect(x: 12, y: 150, width: themeGrid.cardSize.width - 24, height: 18)
            let by = label(theme.author.map { "by \($0)" } ?? "Imported theme", size: 11, color: .secondaryLabelColor)
            by.frame = NSRect(x: 12, y: 167, width: themeGrid.cardSize.width - 24, height: 16)
            [preview, name, by].forEach(card.addSubview)
            card.onSelect = { [weak self] in self?.selectedTheme = theme; self?.refresh() }
            card.onDoubleClick = { [weak self] in self?.selectedTheme = theme; self?.choose() }
            card.setAccessibilityLabel("\(theme.name) theme")
            themeCards[theme.id] = card
            themePreviews[theme.id] = preview
            cards.append(card)
        }
        themeGrid.cards = cards
    }

    /// Pictures take a moment each, so they appear one after another instead of holding up the window.
    private func schedule(_ count: Int, _ work: @escaping (Int) -> Void) {
        for i in 0..<count {
            let timer = Timer(timeInterval: 0.02 * Double(i), repeats: false) { _ in work(i) }
            RunLoop.main.add(timer, forMode: .common)
            renderTimers.append(timer)
        }
    }

    private func renderTemplatePreviews() {
        schedule(DocumentTemplate.all.count) { [weak self] i in
            guard let self, i < self.templatePreviews.count else { return }
            let t = DocumentTemplate.all[i]
            if let sample = t.sample { self.templatePreviews[i].image = ThemePreview.image(for: ThemeLibrary.clean, sample: sample) }
        }
    }

    /// The theme pictures show the kind of diagram that was chosen (a blank diagram uses the architecture sample).
    private func renderThemePreviews() {
        renderTimers.forEach { $0.invalidate() }
        renderTimers = []
        let sample = template.sample ?? .architecture
        for theme in themes { themePreviews[theme.id]?.image = nil }
        let snapshot = themes
        schedule(snapshot.count) { [weak self] i in
            guard let self, self.step == .theme, let view = self.themePreviews[snapshot[i].id], view.image == nil else { return }
            view.image = ThemePreview.image(for: snapshot[i], sample: sample)
        }
    }

    // MARK: Showing the right step

    private func refresh() {
        let onTemplates = step == .template
        templateScroll.isHidden = !onTemplates
        themeScroll.isHidden = onTemplates
        backButton.isHidden = onTemplates || mode == .themeOnly
        importButton.isHidden = onTemplates
        primaryButton.title = onTemplates ? "Choose" : (mode == .newDocument ? "Create" : "Apply")
        if onTemplates {
            heading.stringValue = "Start a New Diagram"
            hint.stringValue = "Step 1 of 2 — choose what you want to create"
            detail.stringValue = template.subtitle
        } else {
            heading.stringValue = "Choose a Theme"
            hint.stringValue = mode == .newDocument ? "Step 2 of 2 — for your \(template.title)" : "The theme restyles everything in the diagram and is used for what you draw next."
            let by = selectedTheme.author.map { " — by \($0)" } ?? ""
            detail.stringValue = "\(selectedTheme.name)\(by). \(selectedTheme.summary ?? "")"
        }
        for (i, t) in DocumentTemplate.all.enumerated() where i < templateCards.count {
            let selected = t == template
            templateCards[i].isSelected = selected
            templateCaptions[i].drawsBackground = false
            templateCaptions[i].layer?.backgroundColor = selected ? NSColor.controlAccentColor.cgColor : NSColor.clear.cgColor
            templateCaptions[i].textColor = selected ? .white : .labelColor
        }
        for (id, card) in themeCards { card.isSelected = id == selectedTheme.id }
        if !onTemplates, let card = themeCards[selectedTheme.id] { themeGrid.scrollToVisible(card.frame.insetBy(dx: -4, dy: -4)) }
    }

    // MARK: Actions

    /// Step 1 -> step 2.
    private func next() {
        guard step == .template else { return }
        step = .theme
        refresh()
        renderThemePreviews()
    }

    @objc private func back(_ sender: Any?) {
        guard step == .theme, mode == .newDocument else { return }
        step = .template
        refresh()
    }

    @objc private func primary(_ sender: Any?) { step == .template ? next() : choose() }

    @objc private func themesChanged() {
        themes = ThemeLibrary.all
        buildThemeCards()
        refresh()
        if step == .theme { renderThemePreviews() }
    }

    @objc private func importTheme(_ sender: Any?) {
        guard let window else { return }
        NewDocumentController.runImportPanel(on: window) { [weak self] theme in
            guard let self, let theme else { return }
            self.themes = ThemeLibrary.all
            self.selectedTheme = theme
            self.buildThemeCards()
            self.refresh()
            self.renderThemePreviews()
        }
    }

    /// Asks for a `.graftheme` file and adds it to the library, reporting problems in plain words.
    static func runImportPanel(on window: NSWindow?, done: @escaping (ThemeDefinition?) -> Void) {
        let panel = NSOpenPanel()
        panel.title = "Import Theme"
        panel.message = "Choose a Graffle theme file (.\(ThemeLibrary.fileExtension))"
        panel.allowedContentTypes = [UTType(filenameExtension: ThemeLibrary.fileExtension), .json].compactMap { $0 }
        panel.allowsMultipleSelection = false
        let handle: (NSApplication.ModalResponse) -> Void = { response in
            guard response == .OK, let url = panel.url else { done(nil); return }
            do {
                let theme = try ThemeLibrary.importTheme(from: url)
                done(theme)
            } catch {
                let alert = NSAlert()
                alert.alertStyle = .warning
                alert.messageText = "This theme couldn't be imported"
                alert.informativeText = error.localizedDescription
                if let window { alert.beginSheetModal(for: window) { _ in done(nil) } } else { alert.runModal(); done(nil) }
            }
        }
        if let window { panel.beginSheetModal(for: window, completionHandler: handle) } else { handle(panel.runModal()) }
    }

    @objc private func cancel(_ sender: Any?) { closeWindow() }

    private func choose() {
        if mode == .newDocument {
            UserDefaults.standard.set(template.title, forKey: Self.lastTemplateKey)
            UserDefaults.standard.set(selectedTheme.id, forKey: Self.lastThemeKey)
        }
        let choice = Choice(template: template, theme: selectedTheme)
        closeWindow()
        onChoose(choice)
    }

    private func closeWindow() {
        NotificationCenter.default.removeObserver(self)
        renderTimers.forEach { $0.invalidate() }
        if let sheetParent = window?.sheetParent { sheetParent.endSheet(window!) }
        else { window?.orderOut(nil) }
        if NewDocumentController.current === self { NewDocumentController.current = nil }
    }

    func windowWillClose(_ notification: Notification) {
        renderTimers.forEach { $0.invalidate() }
        if NewDocumentController.current === self { NewDocumentController.current = nil }
    }

    // MARK: For tests

    var themeIDs: [String] { themes.map(\.id) }
    func select(theme id: String) { if let t = themes.first(where: { $0.id == id }) { selectedTheme = t; refresh() } }
    func select(template t: DocumentTemplate) { template = t; refresh() }
    /// The primary button: from the gallery to the themes, then from the themes to the document.
    func confirm() { step == .template ? next() : choose() }
    func goBack() { back(nil) }
    func dismiss() { cancel(nil) }
    var themePreviewCount: Int { themePreviews.values.filter { $0.image != nil }.count }
    var templatePreviewCount: Int { templatePreviews.filter { $0.image != nil }.count }
    var primaryTitle: String { primaryButton.title }
    var backButtonShown: Bool { !backButton.isHidden }
    var themesShown: Bool { !themeScroll.isHidden }
    var templatesShown: Bool { !templateScroll.isHidden }
    var headingText: String { heading.stringValue }
}
