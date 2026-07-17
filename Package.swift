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
                .copy("Resources/ai_tropes.md"),
                .copy("Resources/writing_style_reference.md"),
                .copy("Resources/editor.css"),
                .copy("Resources/editor.html"),
                .copy("Resources/editor.js"),
                .copy("Resources/harper-runtime.js"),
                .copy("Resources/harper-wasm-data.js"),
                .copy("Resources/THIRD_PARTY_NOTICES.txt")
            ]
        )
    ]
)
