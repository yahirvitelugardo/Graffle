import AppKit

/// The About panel: who made Graffle.
enum About {
    static let company = "EVM"
    static let website = URL(string: "https://evm.mx")!
    static let copyright = "Copyright © 2026 EVM. All rights reserved."

    static var version: String {
        (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String) ?? "0.1"
    }

    static var build: String {
        (Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String) ?? "1"
    }

    /// The text under the app name: credit to EVM, with a link to its website.
    static func credits() -> NSAttributedString {
        let centered = NSMutableParagraphStyle()
        centered.alignment = .center
        centered.paragraphSpacing = 6

        let body: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 11), .foregroundColor: NSColor.labelColor, .paragraphStyle: centered,
        ]
        let strong: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 11, weight: .semibold), .foregroundColor: NSColor.labelColor, .paragraphStyle: centered,
        ]
        let link: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 11, weight: .semibold), .link: website,
            .foregroundColor: NSColor.linkColor, .paragraphStyle: centered,
        ]

        let out = NSMutableAttributedString()
        out.append(NSAttributedString(string: "Graffle is a native macOS app for diagrams and vector drawing, designed and developed by ", attributes: body))
        out.append(NSAttributedString(string: company, attributes: strong))
        out.append(NSAttributedString(string: ".\n", attributes: body))
        out.append(NSAttributedString(string: "All credit for this app goes to ", attributes: body))
        out.append(NSAttributedString(string: company, attributes: strong))
        out.append(NSAttributedString(string: ".\n", attributes: body))
        out.append(NSAttributedString(string: "evm.mx", attributes: link))   // the panel itself prints the copyright line below
        return out
    }

    static var panelOptions: [NSApplication.AboutPanelOptionKey: Any] {
        [
            .applicationName: "Graffle",
            .applicationVersion: version,
            .version: build,
            .credits: credits(),
            NSApplication.AboutPanelOptionKey(rawValue: "Copyright"): copyright,
        ]
    }

    static func show() {
        NSApp.orderFrontStandardAboutPanel(options: panelOptions)
        NSApp.activate(ignoringOtherApps: true)
    }
}
