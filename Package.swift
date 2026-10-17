// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Graffle",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(name: "Graffle", path: "Sources/Graffle")
    ]
)
