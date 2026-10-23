import SwiftUI
import UniformTypeIdentifiers

/// A kind of document the user can start.
struct TemplateEntry: Identifiable, Equatable {
    enum Kind: Hashable { case blank, architecture, classes, database, starter(Starter) }
    let kind: Kind
    let title: String
    let subtitle: String
    var id: String { title }

    var sample: TemplateSample? {
        switch kind {
        case .blank: return nil
        case .architecture: return .architecture
        case .classes: return .classes
        case .database: return .starter(.entityRelationship)
        case .starter(let s): return .starter(s)
        }
    }

    static let all: [TemplateEntry] = [
        TemplateEntry(kind: .blank, title: "Blank Diagram", subtitle: "An empty canvas to draw on."),
        TemplateEntry(kind: .architecture, title: "Software Architecture Diagram",
                      subtitle: "Reverse engineer the modules of an Xcode, .NET or Android project in a folder, and what depends on what."),
        TemplateEntry(kind: .classes, title: "Classes Diagram",
                      subtitle: "Reverse engineer the classes, structs, enums and protocols of a project (Swift, C#, Kotlin, Java) with their members and relationships."),
        TemplateEntry(kind: .database, title: "ER Diagram from a Database",
                      subtitle: "Read the tables and foreign keys of a SQLite file or a .sql script and draw them as an entity-relationship diagram."),
    ] + Starter.allCases.map { TemplateEntry(kind: .starter($0), title: $0.title, subtitle: $0.subtitle) }
}

/// The New Document wizard: step 1 picks what to start, step 2 picks a theme, then the result opens on the canvas.
struct TemplatesSheet: View {
    @ObservedObject var model: EditorModel
    @Environment(\.dismiss) private var dismiss
    @StateObject private var flow: ImportFlow

    private enum Step { case template, theme }
    private static let lastTemplateKey = "newDocument.template", lastThemeKey = "newDocument.theme"

    @State private var step = Step.template
    @State private var template = TemplateEntry.all[0]
    @State private var themes = ThemeLibrary.all
    @State private var selectedTheme = ThemeLibrary.clean
    @State private var importingTheme = false
    @State private var themeProblem: String?

    init(model: EditorModel) {
        self.model = model
        _flow = StateObject(wrappedValue: ImportFlow(model: model))
        let d = UserDefaults.standard
        if let raw = d.string(forKey: Self.lastTemplateKey), let t = TemplateEntry.all.first(where: { $0.title == raw }) { _template = State(initialValue: t) }
        if let id = d.string(forKey: Self.lastThemeKey), let t = ThemeLibrary.theme(id: id) { _selectedTheme = State(initialValue: t) }
    }

    var body: some View {
        NavigationStack {
            Group {
                switch step {
                case .template: templateGrid
                case .theme: themeGrid
                }
            }
            .background(Color(Tok.windowBG))
            .safeAreaInset(edge: .bottom) { detailBar }
            .navigationTitle(step == .template ? "Start a New Diagram" : "Choose a Theme")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbar }
        }
        .importFlow(flow)
        .onAppear { flow.onDelivered = { dismiss() } }
        .fileImporter(isPresented: $importingTheme,
                      allowedContentTypes: [UTType(filenameExtension: ThemeLibrary.fileExtension), .json].compactMap { $0 }) { result in
            guard case .success(let url) = result else { return }
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            do {
                let theme = try ThemeLibrary.importTheme(from: url)
                themes = ThemeLibrary.all
                selectedTheme = theme
            } catch { themeProblem = error.localizedDescription }
        }
        .alert("This theme couldn't be imported", isPresented: Binding(get: { themeProblem != nil }, set: { if !$0 { themeProblem = nil } })) {
            Button("OK", role: .cancel) {}
        } message: { Text(themeProblem ?? "") }
    }

    // MARK: Toolbar

    @ToolbarContentBuilder private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            if step == .theme {
                Button { step = .template } label: { Label("Back", systemImage: "chevron.backward") }
            } else {
                Button("Cancel") { dismiss() }
            }
        }
        if step == .theme {
            ToolbarItem(placement: .secondaryAction) {
                Button("Import Theme…", systemImage: "square.and.arrow.down") { importingTheme = true }
            }
        }
        ToolbarItem(placement: .confirmationAction) {
            Button(step == .template ? "Next" : "Create") { step == .template ? (step = .theme) : create() }
                .fontWeight(.semibold)
        }
    }

    // MARK: Step 1

    private let columns = [GridItem(.adaptive(minimum: 200, maximum: 300), spacing: 16)]

    private var templateGrid: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 16) {
                ForEach(TemplateEntry.all) { t in
                    card(selected: t == template, title: t.title, subtitle: nil, a11y: t.title) {
                        TemplatePreviewView(theme: ThemeLibrary.clean, sample: t.sample)
                    } onTap: { template = t } onDouble: { template = t; step = .theme }
                }
            }
            .padding(20)
        }
    }

    // MARK: Step 2

    private var themeGrid: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 16) {
                ForEach(themes) { theme in
                    card(selected: theme.id == selectedTheme.id, title: theme.name, subtitle: theme.author.map { "by \($0)" } ?? "Imported theme",
                         a11y: "\(theme.name) theme") {
                        TemplatePreviewView(theme: theme, sample: template.sample ?? .architecture)
                    } onTap: { selectedTheme = theme } onDouble: { selectedTheme = theme; create() }
                }
            }
            .padding(20)
        }
    }

    private func card<Preview: View>(selected: Bool, title: String, subtitle: String?, a11y: String,
                                     @ViewBuilder preview: () -> Preview, onTap: @escaping () -> Void, onDouble: @escaping () -> Void) -> some View {
        VStack(spacing: 8) {
            preview()
            VStack(spacing: 2) {
                Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(Color(Tok.textPrimary)).lineLimit(2).multilineTextAlignment(.center)
                if let subtitle { Text(subtitle).font(.caption).foregroundStyle(Color(Tok.textSecondary)) }
            }
            .frame(maxWidth: .infinity, minHeight: 36)
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: Tok.Radius.card).fill(Color(Tok.cardBG)))
        .overlay(RoundedRectangle(cornerRadius: Tok.Radius.card).stroke(selected ? Color(Tok.accent) : Color(Tok.cardOutline), lineWidth: selected ? 3 : 1))
        .contentShape(RoundedRectangle(cornerRadius: Tok.Radius.card))
        .onTapGesture(count: 2, perform: onDouble)
        .onTapGesture(perform: onTap)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(a11y)
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
        .accessibilityAction { onTap() }
    }

    private var detailBar: some View {
        VStack(alignment: .leading, spacing: 2) {
            if step == .template {
                Text(template.subtitle)
            } else {
                Text("\(selectedTheme.name)" + (selectedTheme.author.map { " — by \($0)" } ?? "") + ". " + (selectedTheme.summary ?? ""))
            }
        }
        .font(.footnote).foregroundStyle(Color(Tok.textSecondary))
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 20).padding(.vertical, 12)
        .background(.bar)
    }

    // MARK: Creating

    private func create() {
        let d = UserDefaults.standard
        d.set(template.title, forKey: Self.lastTemplateKey)
        d.set(selectedTheme.id, forKey: Self.lastThemeKey)
        let theme = selectedTheme
        switch template.kind {
        case .blank:
            var drawing = Drawing()
            theme.apply(to: &drawing)
            flow.deliver(drawing, name: "Blank Diagram")
        case .starter(let starter):
            var drawing = Starters.drawing(starter)
            theme.apply(to: &drawing)
            flow.deliver(drawing, name: starter.title)
        case .architecture: flow.start(.architecture, theme: theme)
        case .classes: flow.start(.classes, theme: theme)
        case .database: flow.start(.database, theme: theme)
        }
    }
}
