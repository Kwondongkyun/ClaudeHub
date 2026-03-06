// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "ClaudeHub",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "ClaudeHub",
            path: "Sources"
        )
    ]
)
