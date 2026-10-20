import AppKit

/// File → Import Project Architecture…: choose a project, workspace, package or folder, and get its architecture as a new diagram.
extension AppDelegate {
    private enum Key {
        static let system = "arch.includeSystem", tests = "arch.includeTests", packages = "arch.includePackages"
    }

    @objc func importXcodeProject(_ sender: Any?) { chooseProjectForArchitecture(theme: ThemeLibrary.clean) }

    /// Asks which project to map (and what to include), then opens the diagram drawn in `theme`.
    func chooseProjectForArchitecture(theme: ThemeDefinition) {
        let defaults = UserDefaults.standard
        let panel = NSOpenPanel()
        panel.message = "Choose an Xcode project or workspace, a Swift package, a .NET solution or project, or a folder that contains one"
        panel.prompt = "Analyze"
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.treatsFilePackagesAsDirectories = false

        func checkbox(_ title: String, _ on: Bool) -> NSButton {
            let b = NSButton(checkboxWithTitle: title, target: nil, action: nil)
            b.state = on ? .on : .off
            return b
        }
        let system = checkbox("System frameworks (UIKit, shared .NET frameworks…)", defaults.bool(forKey: Key.system))
        let tests = checkbox("Test targets", defaults.object(forKey: Key.tests) as? Bool ?? true)
        let packages = checkbox("External packages (Swift, NuGet)", defaults.object(forKey: Key.packages) as? Bool ?? true)
        let stack = NSStackView(views: [system, tests, packages])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 6
        stack.edgeInsets = NSEdgeInsets(top: 10, left: 20, bottom: 10, right: 20)
        panel.accessoryView = stack
        panel.isAccessoryViewDisclosed = true

        guard panel.runModal() == .OK, let url = panel.url else { return }
        var options = ArchitectureOptions()
        options.includeSystemFrameworks = system.state == .on
        options.includeTests = tests.state == .on
        options.includeExternalPackages = packages.state == .on
        defaults.set(options.includeSystemFrameworks, forKey: Key.system)
        defaults.set(options.includeTests, forKey: Key.tests)
        defaults.set(options.includeExternalPackages, forKey: Key.packages)
        importArchitecture(from: url, options: options, theme: theme)
    }

    /// Analyzes in the background (a Swift package manifest has to be compiled to be read), then opens the diagram.
    func importArchitecture(from url: URL, options: ArchitectureOptions, theme: ThemeDefinition = ThemeLibrary.clean) {
        let progress = ArchitectureProgress(title: "Analyzing \(url.lastPathComponent)…")
        progress.show()
        DispatchQueue.global(qos: .userInitiated).async {
            let outcome = Result { try ArchitectureImporter.analyze(url, options: options) { message in
                DispatchQueue.main.async { progress.update(message) }
            } }
            DispatchQueue.main.async {
                progress.close()
                switch outcome {
                case .success(let graph):
                    var drawing = ArchitectureDrawing.build(graph)
                    drawing.source = .architecture(ArchitectureModel(graph))
                    theme.apply(to: &drawing)
                    GraffleDocument.open(drawing: drawing, name: graph.title + " Architecture")
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

/// A small floating window with a spinner, shown while a project is read.
final class ArchitectureProgress {
    private let panel: NSPanel
    private let label = NSTextField(labelWithString: "")
    private let spinner = NSProgressIndicator()

    init(title: String) {
        panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 340, height: 86), styleMask: [.titled, .hudWindow, .utilityWindow],
                        backing: .buffered, defer: false)
        panel.title = "Import"
        panel.isFloatingPanel = true
        let heading = NSTextField(labelWithString: title)
        heading.font = .boldSystemFont(ofSize: 13)
        label.textColor = .secondaryLabelColor
        label.lineBreakMode = .byTruncatingMiddle
        spinner.style = .bar
        spinner.isIndeterminate = true
        let stack = NSStackView(views: [heading, label, spinner])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 6
        stack.translatesAutoresizingMaskIntoConstraints = false
        panel.contentView = NSView()
        panel.contentView!.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: panel.contentView!.leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: panel.contentView!.trailingAnchor, constant: -16),
            stack.centerYAnchor.constraint(equalTo: panel.contentView!.centerYAnchor),
            spinner.widthAnchor.constraint(equalTo: stack.widthAnchor),
        ])
    }

    func show() { panel.center(); panel.orderFront(nil); spinner.startAnimation(nil) }
    func update(_ message: String) { label.stringValue = message }
    func close() { spinner.stopAnimation(nil); panel.orderOut(nil) }
}
