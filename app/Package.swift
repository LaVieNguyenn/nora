// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "NoraUI",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "NoraUI",
            path: "Sources/NoraUI",
            swiftSettings: [.swiftLanguageMode(.v5)]
        )
    ]
)
