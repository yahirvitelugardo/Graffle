import SwiftUI
import UniformTypeIdentifiers

/// What the user is picking a file or folder for.
enum ImportKind { case svg, stl, architecture, classes, database }

struct STLRequest { var mesh: Mesh; var name: String }
struct DBRequest { var schema: DBSchema; var name: String }
struct CodeGenRequest { var source: DiagramSource; var choices: [CodeGenOption]; var name: String }
struct ImportDelivery { var drawing: Drawing; var name: String }

extension Drawing {
    /// True when nothing is drawn yet, so a new diagram can simply take the canvas.
    var isBlankCanvas: Bool { shapes.isEmpty && connectors.isEmpty }
}

extension EditorModel {
    /// Fits the whole diagram in view, never magnified past 100%.
    func fitAfterImport() {
        let c = canvas
        guard let b = c.drawing.contentBounds else { c.zoomToFitDiagram(); return }
        c.zoom(toFit: b.insetBy(dx: -60, dy: -60))
        if c.zoom > 1 {
            c.zoom = 1
            c.scrollCenter(to: CGPoint(x: b.midX, y: b.midY))
        }
    }
}

/// Runs the imports (SVG, STL, project folders, databases) and code generation, and puts the result on the canvas.
/// One flow owns one presented sheet; its stages swap inside that sheet.
@MainActor
final class ImportFlow: ObservableObject {
    enum Stage {
        case stl(STLRequest)
        case architecture(URL)
        case classes(URL)
        case database(DBRequest)
        case codeGen(CodeGenRequest)
        case busy
        case confirm(ImportDelivery)
        case message(title: String, text: String)
    }

    let model: EditorModel
    @Published var stage: Stage?
    @Published var busyMessage = ""
    @Published var picking = false
    private(set) var pickingKind = ImportKind.svg
    /// Called when a new diagram has been put on the canvas (the Templates sheet closes itself then).
    var onDelivered: (() -> Void)?

    private var pendingTheme: ThemeDefinition?
    private var scopedURL: URL?

    init(model: EditorModel) { self.model = model }

    // MARK: Picking

    var allowedTypes: [UTType] {
        switch pickingKind {
        case .svg: return [.svg]
        case .stl: return [UTType(filenameExtension: "stl"), .data].compactMap { $0 }
        case .architecture, .classes: return [.folder]
        case .database: return [.item]
        }
    }

    /// The theme new diagrams are drawn in: the one chosen in the wizard, else the canvas's own.
    private var theme: ThemeDefinition { pendingTheme ?? model.canvas.drawing.theme ?? ThemeLibrary.clean }

    func start(_ kind: ImportKind, theme: ThemeDefinition? = nil) {
        pendingTheme = theme
        pickingKind = kind
        picking = true
    }

    func handlePick(_ result: Result<URL, Error>) {
        switch result {
        case .failure(let error):
            if (error as? CocoaError)?.code != .userCancelled { show(.message(title: "Couldn't open the file", text: error.localizedDescription)) }
        case .success(let url):
            switch pickingKind {
            case .svg: importSVG(url)
            case .stl: importSTL(url)
            case .architecture:
                holdScope(url)
                show(.architecture(url))
            case .classes:
                holdScope(url)
                show(.classes(url))
            case .database: importDatabase(url)
            }
        }
    }

    /// Presents a stage a moment later, so it never collides with a file picker that is still closing.
    private func show(_ s: Stage) {
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 350_000_000)
            self.stage = s
        }
    }

    private func holdScope(_ url: URL) {
        releaseScope()
        if url.startAccessingSecurityScopedResource() { scopedURL = url }
    }

    private func releaseScope() {
        scopedURL?.stopAccessingSecurityScopedResource()
        scopedURL = nil
    }

    func cancel() {
        releaseScope()
        stage = nil
    }

    private func finish() {
        releaseScope()
        stage = nil
    }

    private func fail(_ title: String, _ error: Error) {
        releaseScope()
        stage = .message(title: title, text: (error as? LocalizedError)?.errorDescription ?? error.localizedDescription)
    }

    // MARK: Delivering a new diagram

    /// Puts `drawing` on the canvas: straight away when it is empty, otherwise after asking Replace or Add.
    func deliver(_ drawing: Drawing, name: String) {
        if model.canvas.drawing.isBlankCanvas { replace(drawing) }
        else { stage = .confirm(ImportDelivery(drawing: drawing, name: name)) }
    }

    func replace(_ drawing: Drawing) {
        model.canvas.load(drawing)
        model.fitAfterImport()
        finish()
        onDelivered?()
    }

    func add(_ drawing: Drawing, name: String) {
        model.canvas.placeDrawing(drawing, named: "Add \(name)", near: model.canvas.visibleCenter, themed: false)
        finish()
        onDelivered?()
    }

    // MARK: SVG

    private func importSVG(_ url: URL) {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        do {
            let result = try SVGImport.parse(Data(contentsOf: url), name: url.deletingPathExtension().lastPathComponent)
            guard !result.shapes.isEmpty else {
                show(.message(title: "Nothing to import", text: "This SVG has no shapes, paths or text that Graffle can read." + (result.skippedSummary.map { " Left out: \($0)." } ?? "")))
                return
            }
            model.canvas.importSVG(result, near: model.canvas.visibleOrigin)
            if let note = result.skippedSummary {
                show(.message(title: "Some parts were left out", text: "Graffle imports simple SVG shapes, paths and text. Left out: \(note)."))
            }
        } catch {
            show(.message(title: "Couldn't import the SVG", text: error.localizedDescription))
        }
    }

    // MARK: STL

    private func importSTL(_ url: URL) {
        let scoped = url.startAccessingSecurityScopedResource()
        busyMessage = "Reading \(url.lastPathComponent)…"
        show(.busy)
        Task.detached {
            let outcome = Result<Mesh, Error> { try STLParser.parse(Data(contentsOf: url)) }
            if scoped { url.stopAccessingSecurityScopedResource() }
            await MainActor.run {
                switch outcome {
                case .success(let mesh): self.stage = .stl(STLRequest(mesh: mesh, name: url.lastPathComponent))
                case .failure(let error): self.fail("Could not read “\(url.lastPathComponent)”", error)
                }
            }
        }
    }

    func runSTL(_ request: STLRequest, options: MeshViewOptions) {
        busyMessage = "Working out \(request.mesh.triangles.count.formatted()) triangles…"
        stage = .busy
        Task.detached {
            let drawing = MeshDrawing.build(request.mesh, options: options)
            await MainActor.run { self.deliver(drawing, name: "Views") }
        }
    }

    // MARK: Architecture and classes

    func runArchitecture(_ url: URL, options: ArchitectureOptions) {
        let theme = self.theme
        busyMessage = "Analyzing \(url.lastPathComponent)…"
        stage = .busy
        Task.detached {
            let outcome = Result<ArchitectureGraph, Error> {
                try ArchitectureImporter.analyze(url, options: options) { message in
                    Task { @MainActor in self.busyMessage = message }
                }
            }
            await MainActor.run {
                switch outcome {
                case .success(let graph):
                    var drawing = ArchitectureDrawing.build(graph)
                    drawing.source = .architecture(ArchitectureModel(graph))
                    theme.apply(to: &drawing)
                    self.releaseScope()
                    self.deliver(drawing, name: graph.title + " Architecture")
                case .failure(let error): self.fail("Couldn't analyze \(url.lastPathComponent)", error)
                }
            }
        }
    }

    func runClasses(_ url: URL, options: ClassOptions) {
        let theme = self.theme
        busyMessage = "Reading \(url.lastPathComponent)…"
        stage = .busy
        Task.detached {
            let outcome = Result<ClassGraph, Error> {
                try ClassImporter.analyze(url, options: options) { message in
                    Task { @MainActor in self.busyMessage = message }
                }
            }
            await MainActor.run {
                switch outcome {
                case .success(let graph):
                    var drawing = ClassDrawing.build(graph, options: options)
                    drawing.source = .classes(ClassModel(graph))
                    theme.apply(to: &drawing)
                    self.releaseScope()
                    self.deliver(drawing, name: graph.title + " Classes")
                case .failure(let error): self.fail("Couldn't analyze \(url.lastPathComponent)", error)
                }
            }
        }
    }

    // MARK: Database

    /// Reads the structure of a SQLite file or a .sql script (server databases only exist on a Mac).
    private func importDatabase(_ url: URL) {
        let scoped = url.startAccessingSecurityScopedResource()
        busyMessage = "Reading \(url.lastPathComponent)…"
        show(.busy)
        Task.detached {
            let outcome = Result<DBSchema, Error> {
                // Work on a copy: SQLite wants a plain path it can open, and the original is never touched.
                let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("graffle-db-\(UUID().uuidString)", isDirectory: true)
                try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
                defer { try? FileManager.default.removeItem(at: tmp) }
                let copy = tmp.appendingPathComponent(url.lastPathComponent)
                try FileManager.default.copyItem(at: url, to: copy)
                var c = DatabaseConnection()
                c.kind = url.pathExtension.lowercased() == "sql" ? .sqlScript : .sqlite
                c.path = copy.path
                return try DatabaseConnector.readSchema(c)
            }
            if scoped { url.stopAccessingSecurityScopedResource() }
            await MainActor.run {
                switch outcome {
                case .success(let schema): self.stage = .database(DBRequest(schema: schema, name: url.deletingPathExtension().lastPathComponent))
                case .failure(let error): self.fail("Couldn't read “\(url.lastPathComponent)”", error)
                }
            }
        }
    }

    func runDatabase(_ request: DBRequest, tableIDs: [String]) {
        var drawing = ERBuilder.build(request.schema, tables: tableIDs)
        drawing.source = .entityRelationship(ERModel(title: request.schema.tables.first?.name ?? "Database", schema: request.schema, tableIDs: tableIDs))
        theme.apply(to: &drawing)
        deliver(drawing, name: "Database")
    }

    // MARK: Code generation

    func startCodeGen() {
        guard let source = model.canvas.drawing.source else { return }
        stage = .codeGen(CodeGenRequest(source: source, choices: CodeGenOption.choices(for: source), name: "Diagram"))
    }

    func runCodeGen(_ option: CodeGenOption, project: String, folder: URL) {
        let scoped = folder.startAccessingSecurityScopedResource()
        busyMessage = "Writing into “\(folder.lastPathComponent)”…"
        stage = .busy
        Task.detached {
            let outcome = Result<GeneratedProject, Error> {
                try FolderWriter.check(folder)
                let result = try option.make(project)
                try FolderWriter.write(result, to: folder)
                return result
            }
            if scoped { folder.stopAccessingSecurityScopedResource() }
            await MainActor.run {
                switch outcome {
                case .success(let result):
                    var text = "\(result.summary) written to “\(folder.lastPathComponent)”."
                    if !result.notes.isEmpty { text += "\n\n" + result.notes.map { "• " + $0 }.joined(separator: "\n") }
                    self.stage = .message(title: "Code generated", text: text)
                case .failure(let error): self.fail("Nothing was generated", error)
                }
            }
        }
    }
}

// MARK: - The sheet

extension View {
    /// Attaches the file picker and the sheet an `ImportFlow` needs.
    func importFlow(_ flow: ImportFlow) -> some View { modifier(ImportFlowModifier(flow: flow)) }
}

private struct ImportFlowModifier: ViewModifier {
    @ObservedObject var flow: ImportFlow
    func body(content: Content) -> some View {
        content
            .fileImporter(isPresented: $flow.picking, allowedContentTypes: flow.allowedTypes) { flow.handlePick($0) }
            .sheet(isPresented: Binding(get: { flow.stage != nil }, set: { if !$0 { flow.cancel() } })) {
                ImportFlowSheet(flow: flow)
            }
    }
}

struct ImportFlowSheet: View {
    @ObservedObject var flow: ImportFlow

    private var isBusy: Bool { if case .busy = flow.stage { return true }; return false }

    private var title: String {
        switch flow.stage {
        case .stl: return "Views from STL"
        case .architecture: return "Architecture Diagram"
        case .classes: return "Class Diagram"
        case .database: return "ER Diagram from Database"
        case .codeGen: return "Generate Code"
        case .busy: return "Working"
        case .confirm: return "Add the Diagram"
        case .message(let t, _): return t
        case nil: return ""
        }
    }

    var body: some View {
        NavigationStack {
            content
                .navigationTitle(title)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    if !isBusy {
                        ToolbarItem(placement: .cancellationAction) {
                            Button(closeLabel) { flow.cancel() }
                        }
                    }
                }
        }
        .presentationDetents([.large])
        .interactiveDismissDisabled(isBusy)
    }

    private var closeLabel: String {
        switch flow.stage { case .message: return "Done"; default: return "Cancel" }
    }

    @ViewBuilder private var content: some View {
        switch flow.stage {
        case .stl(let r): STLOptionsView(request: r) { flow.runSTL(r, options: $0) }
        case .architecture(let url): ArchitectureOptionsView(url: url) { flow.runArchitecture(url, options: $0) }
        case .classes(let url): ClassOptionsView(url: url) { flow.runClasses(url, options: $0) }
        case .database(let r): DatabaseTablesView(request: r) { flow.runDatabase(r, tableIDs: $0) }
        case .codeGen(let r): CodeGenView(request: r) { flow.runCodeGen($0, project: $1, folder: $2) }
        case .busy:
            VStack(spacing: 16) {
                ProgressView().controlSize(.large)
                Text(flow.busyMessage).font(.subheadline).foregroundStyle(Color(Tok.textSecondary))
                    .multilineTextAlignment(.center).lineLimit(3).padding(.horizontal, 24)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .confirm(let d): ConfirmDeliveryView(delivery: d, flow: flow)
        case .message(_, let text):
            ScrollView { Text(text).font(.body).frame(maxWidth: .infinity, alignment: .leading).padding(20) }
        case nil: Color.clear
        }
    }
}

private struct ConfirmDeliveryView: View {
    let delivery: ImportDelivery
    let flow: ImportFlow

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "square.on.square").font(.system(size: 40)).foregroundStyle(Color(Tok.accent)).padding(.top, 28)
            Text("This canvas already has a drawing").font(.title3.weight(.semibold))
            Text("Replace it with “\(delivery.name)”, or place the new diagram next to what is there.")
                .font(.subheadline).foregroundStyle(Color(Tok.textSecondary)).multilineTextAlignment(.center).padding(.horizontal, 24)
            VStack(spacing: 10) {
                if !delivery.drawing.shapes.isEmpty {
                    Button { flow.add(delivery.drawing, name: delivery.name) } label: {
                        Text("Add to Current").frame(maxWidth: .infinity, minHeight: 36)
                    }.buttonStyle(.borderedProminent)
                }
                Button(role: .destructive) { flow.replace(delivery.drawing) } label: {
                    Text("Replace").frame(maxWidth: .infinity, minHeight: 36)
                }.buttonStyle(.bordered)
                Text("Replacing clears the undo history.").font(.footnote).foregroundStyle(Color(Tok.textSecondary))
            }
            .padding(.horizontal, 24).padding(.top, 6)
            Spacer()
        }
    }
}
