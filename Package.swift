// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "WordProcessor",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "WordProcessor",
            path: "Sources/WordProcessor",
            resources: [
                .copy("Resources")
            ]
        )
    ]
)
