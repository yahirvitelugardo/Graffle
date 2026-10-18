import AppKit

/// File → Import Class Diagram… and the "Classes diagram" choice of Reverse Engineering.
extension AppDelegate {
    private enum Key {
        static let members = "classes.includeMembers", tests = "classes.includeTests", priv = "classes.includePrivate"
    }

    @objc func importClassDiagram(_ sender: Any?) { chooseProjectForClasses(theme: ThemeLibrary.clean) }

    /// Asks which project to read (and what to show), then opens its class diagram drawn in `theme`.
    func chooseProjectForClasses(theme: ThemeDefinition) {
        let defaults = UserDefaults.standard
        let panel = NSOpenPanel()
        panel.message = "Choose an Xcode project, a Swift package, a .NET or Android project, or any folder with source code"
        panel.prompt = "Analyze"
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.treatsFilePackagesAsDirectories = false

        func checkbox(_ title: String, _ on: Bool) -> NSButton {
            let b = NSButton(checkboxWithTitle: title, target: nil, action: nil)
            b.state = on ? .on : .off
            return b
        }
        let members = checkbox("Show properties and methods", defaults.object(forKey: Key.members) as? Bool ?? true)
        let tests = checkbox("Include test types", defaults.bool(forKey: Key.tests))
        let priv = checkbox("Include private members", defaults.bool(forKey: Key.priv))
        let stack = NSStackView(views: [members, tests, priv])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 6
        stack.edgeInsets = NSEdgeInsets(top: 10, left: 20, bottom: 10, right: 20)
        panel.accessoryView = stack
        panel.isAccessoryViewDisclosed = true

        guard panel.runModal() == .OK, let url = panel.url else { return }
        var options = ClassOptions()
        options.includeMembers = members.state == .on
        options.includeTests = tests.state == .on
        options.includePrivate = priv.state == .on
        defaults.set(options.includeMembers, forKey: Key.members)
        defaults.set(options.includeTests, forKey: Key.tests)
        defaults.set(options.includePrivate, forKey: Key.priv)
        importClasses(from: url, options: options, theme: theme)
    }

    /// Reads the source files in the background, then opens the diagram.
    func importClasses(from url: URL, options: ClassOptions, theme: ThemeDefinition = ThemeLibrary.clean) {
        let progress = ArchitectureProgress(title: "Reading \(url.lastPathComponent)…")
        progress.show()
        DispatchQueue.global(qos: .userInitiated).async {
            let outcome = Result { try ClassImporter.analyze(url, options: options) { message in
                DispatchQueue.main.async { progress.update(message) }
            } }
            DispatchQueue.main.async {
                progress.close()
                switch outcome {
                case .success(let graph):
                    var drawing = ClassDrawing.build(graph, options: options)
                    theme.apply(to: &drawing)
                    GraffleDocument.open(drawing: drawing, name: graph.title + " Classes")
                case .failure(let error):
                    let alert = NSAlert()
                    alert.alertStyle = .warning
                    alert.messageText = "Couldn't analyze \(url.lastPathComponent)"
                    alert.informativeText = error.localizedDescription
                    alert.runModal()
                }
            }
        }
    }
}
