import Foundation

/// Versions of the Swift packages a project resolved to, read from `Package.resolved` (formats 1, 2 and 3).
enum SwiftPackageResolved {
    /// Lower-cased package identity (the last part of its URL, without ".git") -> version, branch or short revision.
    static func versions(at url: URL) -> [String: String] {
        guard let data = try? Data(contentsOf: url), let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [:] }
        let pins: [[String: Any]]
        if let p = root["pins"] as? [[String: Any]] { pins = p }                                       // versions 2 and 3
        else if let obj = root["object"] as? [String: Any], let p = obj["pins"] as? [[String: Any]] { pins = p }   // version 1
        else { return [:] }

        var out: [String: String] = [:]
        for pin in pins {
            let location = (pin["location"] as? String) ?? (pin["repositoryURL"] as? String) ?? ""
            let identity = ((pin["identity"] as? String) ?? (pin["package"] as? String) ?? identity(ofURL: location)).lowercased()
            guard let state = pin["state"] as? [String: Any] else { continue }
            if let v = state["version"] as? String { out[identity] = v }
            else if let b = state["branch"] as? String { out[identity] = b }
            else if let r = state["revision"] as? String { out[identity] = String(r.prefix(7)) }
        }
        return out
    }

    /// "https://github.com/Alamofire/Alamofire.git" -> "alamofire".
    static func identity(ofURL url: String) -> String {
        var last = url.split(separator: "/").last.map(String.init) ?? url
        if last.hasSuffix(".git") { last.removeLast(4) }
        return last.lowercased()
    }

    /// Where Xcode keeps the resolved versions for a project or workspace.
    static func candidates(forProjectAt url: URL) -> [URL] {
        [url.appendingPathComponent("project.xcworkspace/xcshareddata/swiftpm/Package.resolved"),
         url.appendingPathComponent("xcshareddata/swiftpm/Package.resolved")]
    }
}
