import SwiftUI
import UniformTypeIdentifiers

private struct PrimaryButton: View {
    let title: String
    var enabled = true
    let action: () -> Void
    var body: some View {
        Button(action: action) { Text(title).font(.body.weight(.semibold)).frame(maxWidth: .infinity, minHeight: 36) }
            .buttonStyle(.borderedProminent)
            .disabled(!enabled)
            .listRowInsets(EdgeInsets())
            .listRowBackground(Color.clear)
    }
}

// MARK: STL

struct STLOptionsView: View {
    let request: STLRequest
    let onDraw: (MeshViewOptions) -> Void
    @State private var options = MeshViewOptions()
    @State private var views = Set(MeshViewOptions().views)
    @State private var crease = 30.0

    var body: some View {
        Form {
            Section {
                Text("“\(request.name)”: \(request.mesh.triangles.count.formatted()) triangles. STL files carry no units, so say what the file is measured in and dimensions will read correctly.")
                    .font(.footnote).foregroundStyle(Color(Tok.textSecondary))
            }
            Section("Units and projection") {
                Picker("File units", selection: $options.unit) { ForEach(LengthUnit.allCases, id: \.self) { Text($0.title).tag($0) } }
                Picker("Projection", selection: $options.system) { ForEach(ProjectionSystem.allCases, id: \.self) { Text($0.title).tag($0) } }
                    .pickerStyle(.navigationLink)
            }
            Section("Views") {
                ForEach(ViewKind.allCases, id: \.self) { kind in
                    Toggle(kind.title, isOn: Binding(get: { views.contains(kind) },
                                                     set: { on in if on { views.insert(kind) } else { views.remove(kind) } }))
                }
            }
            Section("Lines") {
                VStack(alignment: .leading) {
                    Text("Crease angle: \(Int(crease))°")
                    Slider(value: $crease, in: 1...89, step: 1)
                }
                Toggle("Dashed hidden lines", isOn: $options.hiddenLines)
                Toggle("Also in the isometric view", isOn: $options.hiddenInIsometric)
                Toggle("Overall dimensions", isOn: $options.dimensions)
            }
            Section {
                PrimaryButton(title: "Draw Views") {
                    var o = options
                    o.views = ViewKind.allCases.filter { views.contains($0) }
                    if o.views.isEmpty { o.views = [.front] }
                    o.creaseDegrees = min(max(crease, 1), 89)
                    onDraw(o)
                }
            }
        }
    }
}

// MARK: Architecture and classes

struct ArchitectureOptionsView: View {
    private enum Key { static let system = "arch.includeSystem", tests = "arch.includeTests", packages = "arch.includePackages" }
    let url: URL
    let onAnalyze: (ArchitectureOptions) -> Void
    @State private var system = UserDefaults.standard.bool(forKey: Key.system)
    @State private var tests = UserDefaults.standard.object(forKey: Key.tests) as? Bool ?? true
    @State private var packages = UserDefaults.standard.object(forKey: Key.packages) as? Bool ?? true

    var body: some View {
        Form {
            Section {
                Label(url.lastPathComponent, systemImage: "folder").font(.headline)
                Text("Reads an Xcode project or workspace, a .NET solution or an Android (Gradle) project in this folder. Swift package manifests can't be run on iPad, so a Package.swift on its own can't be read here.")
                    .font(.footnote).foregroundStyle(Color(Tok.textSecondary))
            }
            Section("Include") {
                Toggle("System frameworks (UIKit, shared .NET frameworks…)", isOn: $system)
                Toggle("Test targets", isOn: $tests)
                Toggle("External packages (Swift, NuGet)", isOn: $packages)
            }
            Section {
                PrimaryButton(title: "Analyze") {
                    let d = UserDefaults.standard
                    d.set(system, forKey: Key.system); d.set(tests, forKey: Key.tests); d.set(packages, forKey: Key.packages)
                    var o = ArchitectureOptions()
                    o.includeSystemFrameworks = system
                    o.includeTests = tests
                    o.includeExternalPackages = packages
                    onAnalyze(o)
                }
            }
        }
    }
}

struct ClassOptionsView: View {
    private enum Key { static let members = "classes.includeMembers", tests = "classes.includeTests", priv = "classes.includePrivate" }
    let url: URL
    let onAnalyze: (ClassOptions) -> Void
    @State private var members = UserDefaults.standard.object(forKey: Key.members) as? Bool ?? true
    @State private var tests = UserDefaults.standard.bool(forKey: Key.tests)
    @State private var priv = UserDefaults.standard.bool(forKey: Key.priv)

    var body: some View {
        Form {
            Section {
                Label(url.lastPathComponent, systemImage: "folder").font(.headline)
                Text("Reads the Swift, C#, Kotlin and Java source files in this folder.")
                    .font(.footnote).foregroundStyle(Color(Tok.textSecondary))
            }
            Section("Show") {
                Toggle("Properties and methods", isOn: $members)
                Toggle("Test types", isOn: $tests)
                Toggle("Private members", isOn: $priv)
            }
            Section {
                PrimaryButton(title: "Analyze") {
                    let d = UserDefaults.standard
                    d.set(members, forKey: Key.members); d.set(tests, forKey: Key.tests); d.set(priv, forKey: Key.priv)
                    var o = ClassOptions()
                    o.includeMembers = members
                    o.includeTests = tests
                    o.includePrivate = priv
                    onAnalyze(o)
                }
            }
        }
    }
}

// MARK: Database

struct DatabaseTablesView: View {
    static let maxTables = 60
    let request: DBRequest
    let onBuild: ([String]) -> Void
    @State private var checked: Set<String>
    @State private var query = ""

    init(request: DBRequest, onBuild: @escaping ([String]) -> Void) {
        self.request = request
        self.onBuild = onBuild
        _checked = State(initialValue: Set(request.schema.tables.prefix(min(12, Self.maxTables)).map(\.id)))
    }

    private var visible: [DBTable] {
        let q = query.trimmingCharacters(in: .whitespaces)
        return q.isEmpty ? request.schema.tables : request.schema.tables.filter { $0.name.localizedCaseInsensitiveContains(q) }
    }

    var body: some View {
        let n = checked.count
        List {
            Section {
                Text("Tick the tables that go into the diagram (up to \(Self.maxTables)). Graffle only reads table and column names and foreign keys. Server databases (PostgreSQL, MySQL, SQL Server) are only available on the Mac.")
                    .font(.footnote).foregroundStyle(Color(Tok.textSecondary))
                HStack {
                    Button("Select All") { checked = Set(request.schema.tables.prefix(Self.maxTables).map(\.id)) }
                    Spacer()
                    Button("Select None") { checked = [] }
                }.buttonStyle(.borderless)
            }
            Section("\(n) of \(request.schema.tables.count) tables" + (n > Self.maxTables ? " (too many)" : "")) {
                ForEach(visible) { t in
                    Button {
                        if checked.contains(t.id) { checked.remove(t.id) } else { checked.insert(t.id) }
                    } label: {
                        HStack {
                            Image(systemName: checked.contains(t.id) ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(checked.contains(t.id) ? Color(Tok.accent) : Color(Tok.textSecondary))
                            VStack(alignment: .leading, spacing: 2) {
                                Text(t.name).foregroundStyle(Color(Tok.textPrimary))
                                Text("\(t.columns.count) columns").font(.caption).foregroundStyle(Color(Tok.textSecondary))
                            }
                            Spacer()
                        }
                        .frame(minHeight: 44).contentShape(Rectangle())
                    }
                }
            }
        }
        .searchable(text: $query)
        .safeAreaInset(edge: .bottom) {
            Button {
                onBuild(request.schema.tables.map(\.id).filter(checked.contains))
            } label: { Text("Create Diagram").font(.body.weight(.semibold)).frame(maxWidth: .infinity, minHeight: 36) }
                .buttonStyle(.borderedProminent)
                .disabled(n == 0 || n > Self.maxTables)
                .padding(.horizontal, 20).padding(.vertical, 10)
                .background(.bar)
        }
    }
}

// MARK: Code generation

struct CodeGenView: View {
    let request: CodeGenRequest
    let onGenerate: (CodeGenOption, String, URL) -> Void
    @State private var choice: String
    @State private var project: String
    @State private var choosing = false

    init(request: CodeGenRequest, onGenerate: @escaping (CodeGenOption, String, URL) -> Void) {
        self.request = request
        self.onGenerate = onGenerate
        _choice = State(initialValue: request.choices.first?.id ?? "")
        _project = State(initialValue: request.name)
    }

    var body: some View {
        Form {
            Section {
                Text("Generate code from this \(request.source.kindTitle) diagram. Pick the output, then an empty folder to write it to. Existing files are never overwritten, and nothing is written unless the folder is empty.")
                    .font(.footnote).foregroundStyle(Color(Tok.textSecondary))
            }
            Section(CodeGenOption.heading(for: request.source)) {
                Picker(CodeGenOption.heading(for: request.source), selection: $choice) {
                    ForEach(request.choices) { Text($0.title).tag($0.id) }
                }
                .pickerStyle(.inline).labelsHidden()
            }
            Section("Project name") {
                TextField("Project name", text: $project).textInputAutocapitalization(.words).autocorrectionDisabled()
            }
            Section {
                PrimaryButton(title: "Choose Empty Folder…", enabled: !project.trimmingCharacters(in: .whitespaces).isEmpty) { choosing = true }
            }
        }
        .fileImporter(isPresented: $choosing, allowedContentTypes: [.folder]) { result in
            guard case .success(let folder) = result,
                  let option = request.choices.first(where: { $0.id == choice }) else { return }
            onGenerate(option, project.trimmingCharacters(in: .whitespaces), folder)
        }
    }
}
