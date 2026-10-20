import AppKit

/// Options a document type offers when generating code.
struct CodeGenChoice {
    var title: String
    var make: (String) throws -> GeneratedProject
}

enum CodeGen {
    static func choices(for source: DiagramSource) -> [CodeGenChoice] {
        switch source {
        case .classes(let m):
            return ClassCode.languages.map { l in CodeGenChoice(title: ClassCode.title(l)) { try ClassCode.generate(m, language: l, project: $0) } }
        case .entityRelationship(let m):
            return SQLDialect.allCases.map { d in CodeGenChoice(title: d.title + " (SQL)") { try SQLCode.generate(m, dialect: d, project: $0) } }
        case .architecture(let m):
            let inferred = ScaffoldTarget.inferred(from: m)
            let order = [inferred] + ScaffoldTarget.allCases.filter { $0 != inferred }
            return order.map { t in CodeGenChoice(title: t.title) { try ArchitectureScaffold.generate(m, target: t, project: $0) } }
        }
    }

    static func heading(for source: DiagramSource) -> String {
        switch source {
        case .classes: return "Language"
        case .entityRelationship: return "Database"
        case .architecture: return "Project type"
        }
    }

    /// Generates and writes into `folder`, which must be empty. Nothing is written if it isn't.
    @discardableResult
    static func generate(_ choice: CodeGenChoice, project: String, into folder: URL) throws -> GeneratedProject {
        try FolderWriter.check(folder)
        let result = try choice.make(project)
        try FolderWriter.write(result, to: folder)
        return result
    }

    // Replaced by the self-test so no panel opens.
    static var chooseFolder: () -> URL? = {
        let panel = NSOpenPanel()
        panel.title = "Choose an empty folder"
        panel.message = "The code is only written into an empty folder. Create one with New Folder if needed."
        panel.prompt = "Generate Here"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        return panel.runModal() == .OK ? panel.url : nil
    }
    static var presentOptions: (DiagramSource, [CodeGenChoice]) -> CodeGenChoice? = { source, choices in
        let alert = NSAlert()
        alert.messageText = "Generate code from this \(source.kindTitle) diagram"
        alert.informativeText = "Pick the output, then an empty folder to write it to. Existing files are never overwritten."
        let popup = NSPopUpButton(frame: NSRect(x: 0, y: 0, width: 260, height: 26))
        popup.addItems(withTitles: choices.map(\.title))
        let label = NSTextField(labelWithString: heading(for: source))
        let stack = NSStackView(views: [label, popup])
        stack.spacing = 10
        stack.frame = NSRect(x: 0, y: 0, width: 330, height: 28)
        alert.accessoryView = stack
        alert.addButton(withTitle: "Choose Folder…")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return nil }
        return choices[max(0, popup.indexOfSelectedItem)]
    }
    static var presentResult: (String, String, URL?) -> Void = { title, text, folder in
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = text
        alert.addButton(withTitle: "OK")
        if folder != nil { alert.addButton(withTitle: "Reveal in Finder") }
        if alert.runModal() == .alertSecondButtonReturn, let folder { NSWorkspace.shared.activateFileViewerSelecting([folder]) }
    }
}

extension DocumentWindowController {
    var canGenerateCode: Bool { canvas.drawing.source != nil }

    @objc func generateCode(_ sender: Any?) {
        guard let source = canvas.drawing.source else { return }
        let name = graffleDocument?.displayName ?? "Diagram"
        guard let choice = CodeGen.presentOptions(source, CodeGen.choices(for: source)), let folder = CodeGen.chooseFolder() else { return }
        do {
            let result = try CodeGen.generate(choice, project: name, into: folder)
            var text = "\(result.summary) written to “\(folder.lastPathComponent)”."
            if !result.notes.isEmpty { text += "\n\n" + result.notes.map { "• " + $0 }.joined(separator: "\n") }
            CodeGen.presentResult("Code generated", text, folder)
        } catch {
            CodeGen.presentResult("Nothing was generated", (error as? LocalizedError)?.errorDescription ?? error.localizedDescription, nil)
        }
    }
}
