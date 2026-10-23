#if canImport(AppKit)
import AppKit
#else
import UIKit
#endif

extension Notification.Name {
    /// Posted when themes are added to the library.
    static let themesChanged = Notification.Name("GraffleThemesChanged")
}

/// The themes available to the app: the ones that come with it plus the `.graftheme` files the user has imported.
enum ThemeLibrary {
    static let fileExtension = "graftheme"

    /// Where imported themes live. Settable so tests can use a scratch folder.
    nonisolated(unsafe) static var userFolder: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        return base.appendingPathComponent("Graffle/Themes", isDirectory: true)
    }()

    static var builtIn: [ThemeDefinition] { BuiltInThemes.all }

    /// Every valid `.graftheme` file in the user folder; unreadable ones are skipped.
    static func userThemes() -> [ThemeDefinition] {
        let files = (try? FileManager.default.contentsOfDirectory(at: userFolder, includingPropertiesForKeys: nil)) ?? []
        let reserved = Set(builtIn.map(\.id))
        return files.filter { $0.pathExtension == fileExtension }
            .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
            .compactMap { (try? ThemeDefinition.decode(Data(contentsOf: $0))) }
            .filter { !reserved.contains($0.id) }
    }

    static var all: [ThemeDefinition] { builtIn + userThemes() }

    static func theme(id: String) -> ThemeDefinition? { all.first { $0.id == id } }

    static var clean: ThemeDefinition { builtIn.first { $0.id == "clean" } ?? ThemeDefinition(id: "clean", name: "Clean") }

    /// Checks a theme file and copies it into the user folder, replacing an earlier import with the same id.
    @discardableResult
    static func importTheme(from url: URL) throws -> ThemeDefinition {
        let theme = try ThemeDefinition.decode(Data(contentsOf: url))
        if builtIn.contains(where: { $0.id == theme.id }) { throw ThemeDefinition.Problem.reservedID(theme.id) }
        try FileManager.default.createDirectory(at: userFolder, withIntermediateDirectories: true)
        let target = userFolder.appendingPathComponent("\(theme.id).\(fileExtension)")
        try theme.encoded().write(to: target, options: .atomic)
        NotificationCenter.default.post(name: .themesChanged, object: nil)
        return theme
    }

    /// Writes `theme` to `url` as a theme file (handy as a starting point for making one's own).
    static func export(_ theme: ThemeDefinition, to url: URL) throws {
        try theme.encoded().write(to: url, options: .atomic)
    }

    /// Fonts and text colors that themes set, so applying another theme can undo them without touching the user's own choices.
    static var themeFonts: Set<String> {
        Set(all.flatMap { $0.shape?.text?.fonts ?? [] })
    }
    static var themeTextColors: [RGBA] {
        all.flatMap { [$0.shape?.text?.color, $0.connector?.textColor] }.compactMap { $0.flatMap { RGBA(hex: $0) } }
    }
}

extension ThemeDefinition {
    init(id: String, name: String) {
        self.init(format: Self.currentFormat, id: id, name: name, author: nil, summary: nil, gridColor: nil, accent: nil, accentMix: nil,
                  shape: nil, connector: nil)
    }
}
