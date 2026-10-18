import Foundation

/// Reads an Xcode project (`.xcodeproj`) and turns its targets and the links between them into an `ArchitectureGraph`.
/// It reads `project.pbxproj` directly, so it needs neither Xcode nor a build.
enum XcodeProjectParser {
    /// A target that uses a product of a Swift package that lives on disk; resolved once that package is read.
    struct LocalPackageUse: Equatable {
        var fromTarget: String      // node id
        var packagePath: String     // relative to the project's folder
        var product: String
    }

    struct Result {
        var graph: ArchitectureGraph
        var localPackageUses: [LocalPackageUse]
        /// Other projects this one depends on (their targets appear as nodes; the importer can analyze them too).
        var referencedProjects: [URL]
        var projectFolder: URL
    }

    enum ParseError: LocalizedError {
        case unreadable(String)
        case notAProject(String)

        var errorDescription: String? {
            switch self {
            case .unreadable(let why): return "The project couldn't be read: \(why)"
            case .notAProject(let name): return "\(name) doesn't look like an Xcode project."
            }
        }
    }

    static func parse(projectURL: URL, packageVersions: [String: String] = [:]) throws -> Result {
        let projectName = projectURL.deletingPathExtension().lastPathComponent
        let pbxproj = projectURL.appendingPathComponent("project.pbxproj")
        guard let data = try? Data(contentsOf: pbxproj) else { throw ParseError.unreadable("no project.pbxproj in \(projectURL.lastPathComponent)") }
        guard let plist = (try? PropertyListSerialization.propertyList(from: data, options: [], format: nil)) as? [String: Any],
              let objects = plist["objects"] as? [String: Any],
              let rootID = plist["rootObject"] as? String,
              let project = objects[rootID] as? [String: Any],
              let targetIDs = project["targets"] as? [String] else { throw ParseError.notAProject(projectURL.lastPathComponent) }

        let folder = projectURL.deletingLastPathComponent()
        func obj(_ id: String) -> [String: Any]? { objects[id] as? [String: Any] }
        func strings(_ any: Any?) -> [String] { (any as? [String]) ?? [] }

        // Which target makes which product, so a link to a product file is understood as a link to that target.
        var productOwner: [String: String] = [:]
        for tid in targetIDs { if let ref = obj(tid)?["productReference"] as? String { productOwner[ref] = tid } }

        // Swift packages the project refers to.
        struct PackageRef { var remoteURL: String?; var localPath: String?; var requirement: String }
        var packageRefs: [String: PackageRef] = [:]
        for (id, any) in objects {
            guard let o = any as? [String: Any], let isa = o["isa"] as? String else { continue }
            if isa == "XCRemoteSwiftPackageReference" {
                let req = o["requirement"] as? [String: Any]
                let summary: String
                switch req?["kind"] as? String {
                case "upToNextMajorVersion", "upToNextMinorVersion": summary = "from " + ((req?["minimumVersion"] as? String) ?? "?")
                case "exactVersion": summary = (req?["version"] as? String) ?? "exact"
                case "branch": summary = (req?["branch"] as? String) ?? "branch"
                case "revision": summary = String(((req?["revision"] as? String) ?? "").prefix(7))
                default: summary = ""
                }
                packageRefs[id] = PackageRef(remoteURL: o["repositoryURL"] as? String, localPath: nil, requirement: summary)
            } else if isa == "XCLocalSwiftPackageReference" {
                packageRefs[id] = PackageRef(remoteURL: nil, localPath: o["relativePath"] as? String, requirement: "")
            }
        }

        var graph = ArchitectureGraph(title: projectName, source: projectURL.lastPathComponent)
        var localUses: [LocalPackageUse] = []
        var referenced: [URL] = []

        func platform(of tid: String) -> String? {
            var chain: [[String: Any]] = []
            if let list = obj(tid)?["buildConfigurationList"] as? String, let first = strings(obj(list)?["buildConfigurations"]).first,
               let s = obj(first)?["buildSettings"] as? [String: Any] { chain.append(s) }
            if let list = project["buildConfigurationList"] as? String, let first = strings(obj(list)?["buildConfigurations"]).first,
               let s = obj(first)?["buildSettings"] as? [String: Any] { chain.append(s) }
            for s in chain {
                var raw = ""
                if let sdk = s["SDKROOT"] as? String { raw = sdk }
                else if let sp = s["SUPPORTED_PLATFORMS"] as? String { raw = sp }
                else if let sp = s["SUPPORTED_PLATFORMS"] as? [String] { raw = sp.joined(separator: " ") }
                let low = raw.lowercased()
                if low.contains("iphone") { return "iOS" }
                if low.contains("macosx") { return "macOS" }
                if low.contains("watch") { return "watchOS" }
                if low.contains("appletv") { return "tvOS" }
                if low.contains("xros") || low.contains("xrsimulator") { return "visionOS" }
            }
            return nil
        }

        // Folders that Xcode 16 keeps in sync with a target, instead of listing every file in the project.
        var groupParent: [String: String] = [:]
        for (id, any) in objects {
            guard let o = any as? [String: Any], (o["isa"] as? String) == "PBXGroup" else { continue }
            for child in strings(o["children"]) { groupParent[child] = id }
        }
        func folderPath(ofGroup id: String) -> String {
            var parts: [String] = []
            var current: String? = id
            while let c = current {
                if let o = obj(c), (o["sourceTree"] as? String) == "<group>", let p = o["path"] as? String { parts.insert(p, at: 0) }
                else if let o = obj(c), let p = o["path"] as? String, (o["sourceTree"] as? String) != "<group>" { parts.insert(p, at: 0); break }
                current = groupParent[c]
            }
            return parts.joined(separator: "/")
        }

        func describeSources(of tid: String) -> String {
            var counts = SourceCounts()
            guard let t = obj(tid) else { return "" }
            for phaseID in strings(t["buildPhases"]) {
                guard let phase = obj(phaseID), (phase["isa"] as? String) == "PBXSourcesBuildPhase" else { continue }
                for bfID in strings(phase["files"]) {
                    guard let ref = (obj(bfID)?["fileRef"] as? String).flatMap(obj) else { continue }
                    let path = (ref["path"] as? String) ?? (ref["name"] as? String) ?? ""
                    counts.add(extension: (path as NSString).pathExtension)
                }
            }
            for gid in strings(t["fileSystemSynchronizedGroups"]) {
                counts.add(folder: folder.appendingPathComponent(folderPath(ofGroup: gid)))
            }
            return counts.summary
        }

        var nodeID: [String: String] = [:]          // target object id -> node id
        // Pass 1: one node per target.
        for tid in targetIDs {
            guard let t = obj(tid), let name = t["name"] as? String else { continue }
            let id = "\(projectName):\(name)"
            nodeID[tid] = id
            let kind: NodeKind, label: String
            switch t["isa"] as? String {
            case "PBXAggregateTarget": (kind, label) = (.other, "Aggregate target")
            case "PBXLegacyTarget": (kind, label) = (.other, "External build tool")
            default: (kind, label) = classify(productType: t["productType"] as? String)
            }
            var parts = [label]
            if let p = platform(of: tid) { parts.append(p) }
            let sources = describeSources(of: tid)
            if !sources.isEmpty { parts.append(sources) }
            graph.add(ArchitectureNode(id: id, name: name, kind: kind, detail: parts.joined(separator: " · "), container: projectName))
        }

        // Pass 2: the links.
        for tid in targetIDs {
            guard let t = obj(tid), let from = nodeID[tid] else { continue }

            // Explicit target dependencies, including ones on targets of other projects.
            for depID in strings(t["dependencies"]) {
                guard let dep = obj(depID) else { continue }
                if let local = dep["target"] as? String, let to = nodeID[local] {
                    graph.connect(from, to, .dependsOn)
                } else if let proxyID = dep["targetProxy"] as? String, let proxy = obj(proxyID) {
                    let portal = proxy["containerPortal"] as? String
                    if portal == rootID, let gid = proxy["remoteGlobalIDString"] as? String, let to = nodeID[gid] {
                        graph.connect(from, to, .dependsOn)
                    } else if let portal, portal != rootID, let ref = obj(portal), let path = ref["path"] as? String {
                        let other = ((path as NSString).lastPathComponent as NSString).deletingPathExtension
                        let remote = (proxy["remoteInfo"] as? String) ?? (dep["name"] as? String) ?? other
                        let id = "\(other):\(remote)"
                        graph.add(ArchitectureNode(id: id, name: remote, kind: .other, detail: "Target of \(other).xcodeproj", container: other))
                        graph.connect(from, id, .dependsOn)
                        let url = folder.appendingPathComponent(path)
                        if FileManager.default.fileExists(atPath: url.path), !referenced.contains(url) { referenced.append(url) }
                    }
                }
            }

            // Swift package products.
            for pid in strings(t["packageProductDependencies"]) {
                guard let p = obj(pid), let product = p["productName"] as? String else { continue }
                let ref = (p["package"] as? String).flatMap { packageRefs[$0] }
                if let url = ref?.remoteURL {
                    let identity = SwiftPackageResolved.identity(ofURL: url)
                    var display = url.split(separator: "/").last.map(String.init) ?? url
                    if display.hasSuffix(".git") { display.removeLast(4) }
                    let version = packageVersions[identity] ?? ref?.requirement ?? ""
                    graph.add(ArchitectureNode(id: "pkg:\(identity)", name: display, kind: .externalPackage,
                                               detail: "Swift package" + (version.isEmpty ? "" : " · \(version)"), container: "Packages"))
                    graph.connect(from, "pkg:\(identity)", .package)
                } else if let path = ref?.localPath {
                    localUses.append(LocalPackageUse(fromTarget: from, packagePath: path, product: product))
                } else {
                    graph.add(ArchitectureNode(id: "pkg:\(product.lowercased())", name: product, kind: .externalPackage, detail: "Swift package", container: "Packages"))
                    graph.connect(from, "pkg:\(product.lowercased())", .package)
                }
            }

            // Linking and embedding.
            for phaseID in strings(t["buildPhases"]) {
                guard let phase = obj(phaseID), let isa = phase["isa"] as? String else { continue }
                let buildFiles = strings(phase["files"]).compactMap(obj)
                switch isa {
                case "PBXFrameworksBuildPhase":
                    for bf in buildFiles {
                        guard let refID = bf["fileRef"] as? String else { continue }
                        if let owner = productOwner[refID], let to = nodeID[owner] { graph.connect(from, to, .dependsOn); continue }
                        guard let ref = obj(refID) else { continue }
                        let path = (ref["path"] as? String) ?? (ref["name"] as? String) ?? ""
                        let file = (path as NSString).lastPathComponent
                        let ext = (file as NSString).pathExtension.lowercased()
                        let name = (file as NSString).deletingPathExtension
                        let tree = ref["sourceTree"] as? String
                        if tree == "SDKROOT" || tree == "DEVELOPER_DIR", ["framework", "tbd", "dylib"].contains(ext) {
                            graph.add(ArchitectureNode(id: "sys:\(name)", name: name, kind: .system, detail: "System framework", container: "System"))
                            graph.connect(from, "sys:\(name)", .dependsOn)
                        } else if ["framework", "xcframework", "a", "dylib"].contains(ext) {
                            graph.add(ArchitectureNode(id: "bin:\(name)", name: name, kind: .externalPackage, detail: "Binary framework", container: "Packages"))
                            graph.connect(from, "bin:\(name)", .dependsOn)
                        }
                    }
                case "PBXCopyFilesBuildPhase":
                    for bf in buildFiles {
                        if let refID = bf["fileRef"] as? String, let owner = productOwner[refID], let to = nodeID[owner] {
                            graph.connect(from, to, .embeds)
                        }
                    }
                default:
                    break
                }
            }
        }

        return Result(graph: graph, localPackageUses: localUses, referencedProjects: referenced, projectFolder: folder)
    }

    /// The kind of node, and a short label, for an Xcode product type.
    static func classify(productType: String?) -> (NodeKind, String) {
        let type = (productType ?? "").replacingOccurrences(of: "com.apple.product-type.", with: "")
        switch type {
        case "application", "application.watchapp", "application.watchapp2", "application.watchapp2-container",
             "application.on-demand-install-capable", "application.messages":
            return (.app, type.contains("watch") ? "Watch app" : (type.contains("on-demand") ? "App Clip" : "App"))
        case let t where t.hasPrefix("app-extension") || t.hasPrefix("extensionkit-extension") || t == "watchkit2-extension" || t == "watchkit-extension":
            return (.appExtension, "Extension")
        case "framework", "framework.static":
            return (.framework, type.hasSuffix("static") ? "Static framework" : "Framework")
        case "library.static": return (.library, "Static library")
        case "library.dynamic": return (.library, "Dynamic library")
        case "tool", "xpc-service": return (.tool, type == "tool" ? "Command-line tool" : "XPC service")
        case "bundle.unit-test": return (.tests, "Unit tests")
        case "bundle.ui-testing": return (.tests, "UI tests")
        case "bundle": return (.other, "Bundle")
        default: return (.other, type.isEmpty ? "Target" : type)
        }
    }
}
