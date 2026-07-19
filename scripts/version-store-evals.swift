import Foundation

struct PersonalizationOutcomeSnapshot: Codable, Equatable, Sendable {
    let actionID: String
    let outcome: String
    let finalText: String
    let confidence: Double
    let trainingEligible: Bool
}

@main
struct VersionStoreEvals {
    static func main() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("shakespeare-version-store-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = VersionStore(testingDatabaseURL: root.appendingPathComponent("versions.sqlite"))

        let filename = "057cffc71a1a5265f5b4c718ebc5fcd80dc034391d3a3459c7e39721a2cb879f.png"
        let imageData = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVQIHWP4z8DwHwAFgAI/ScL1WQAAAABJRU5ErkJggg==")!
        let source = DocumentAssetReference.urlString(for: filename)
        let documentID = UUID().uuidString
        let snapshot = DocumentFileStore.FileSnapshot(
            canonicalJSON: """
            {"type":"doc","content":[{"type":"paragraph","content":[{"type":"image","attrs":{"src":"\(source)"}}]}]}
            """,
            plainText: "",
            wordCount: 0,
            characterCount: 0,
            documentID: documentID
        )

        try await store.saveVersion(
            filePath: "/tmp/Draft.shkdoc",
            snapshot: snapshot,
            versionAssets: [filename: imageData]
        )
        // Identical snapshots deduplicate while still allowing the row to be named.
        try await store.saveVersion(
            filePath: "/tmp/Draft.shkdoc",
            snapshot: snapshot,
            name: "First draft",
            versionAssets: [filename: imageData]
        )

        let summaries = try await store.versionSummaries(
            forFile: "/tmp/Draft.shkdoc",
            documentID: documentID
        )
        precondition(summaries.count == 1)
        precondition(summaries[0].isNamed && summaries[0].versionName == "First draft")

        let restored = try await store.version(id: summaries[0].id)
        precondition(restored?.canonicalJSON == snapshot.canonicalJSON)
        precondition(restored?.htmlContent == "", "canonical snapshots should not duplicate HTML")
        precondition(restored?.assets[filename] == imageData, "version image did not round-trip")

        try await store.deleteVersion(id: summaries[0].id)
        let remaining = try await store.versionSummaries(
            forFile: "/tmp/Draft.shkdoc",
            documentID: documentID
        )
        precondition(remaining.isEmpty)
        print("Version-store evals passed (transactional save, deduplication, naming, asset restore, deletion).")
    }
}
