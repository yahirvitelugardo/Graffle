import Foundation

/// Reads an `.xcworkspace`: which projects and local Swift packages it brings together.
enum XcodeWorkspaceParser {
    struct Contents {
        var projects: [URL] = []
        var packageFolders: [URL] = []
    }

    static func parse(workspaceURL: URL) -> Contents {
        let file = workspaceURL.appendingPathComponent("contents.xcworkspacedata")
        guard let data = try? Data(contentsOf: file), let doc = try? XMLDocument(data: data, options: []),
              let root = doc.rootElement() else { return Contents() }
        var out = Contents()
        let base = workspaceURL.deletingLastPathComponent()

        /// `location` looks like "group:App/App.xcodeproj", "container:Other.xcodeproj" or "absolute:/path".
        func resolve(_ location: String, groupPath: String) -> URL? {
            guard let colon = location.firstIndex(of: ":") else { return nil }
            let scheme = location[..<colon], path = String(location[location.index(after: colon)...])
            switch scheme {
            case "absolute": return URL(fileURLWithPath: path)
            case "group": return base.appendingPathComponent(groupPath).appendingPathComponent(path).standardizedFileURL
            case "container", "self": return base.appendingPathComponent(path).standardizedFileURL
            default: return nil
            }
        }

        func walk(_ element: XMLElement, groupPath: String) {
            for child in (element.children ?? []).compactMap({ $0 as? XMLElement }) {
                let location = child.attribute(forName: "location")?.stringValue ?? ""
                switch child.name {
                case "FileRef":
                    guard let url = resolve(location, groupPath: groupPath) else { continue }
                    if url.pathExtension == "xcodeproj" { out.projects.append(url) }
                    else if FileManager.default.fileExists(atPath: url.appendingPathComponent("Package.swift").path) { out.packageFolders.append(url) }
                case "Group":
                    // A group's own location is relative to the one around it.
                    var sub = groupPath
                    if let colon = location.firstIndex(of: ":") {
                        let p = String(location[location.index(after: colon)...])
                        sub = (groupPath as NSString).appendingPathComponent(p)
                    }
                    walk(child, groupPath: sub)
                default:
                    break
                }
            }
        }
        walk(root, groupPath: "")
        return out
    }
}
