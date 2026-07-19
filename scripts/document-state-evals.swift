import Foundation

// The production definition lives with the local learning ledger. Keeping this
// evaluator stub structurally identical lets the document-state contract run
// without touching the writer's real personalization storage.
struct PersonalizationOutcomeSnapshot: Codable, Equatable, Sendable {
    let actionID: String
    let outcome: String
    let finalText: String
    let confidence: Double
    let trainingEligible: Bool
}

@main
private struct DocumentStateEvals {
    @MainActor
    static func main() async throws {
        let outcome = PersonalizationOutcomeSnapshot(
            actionID: "action-1",
            outcome: "accepted_modified",
            finalText: "Writer revision",
            confidence: 0.9,
            trainingEligible: true
        )
        let document = DocumentModel()
        precondition(document.displayName == "Untitled")
        document.renameUnsavedDocument(to: "Chapter One")
        precondition(document.displayName == "Chapter One")

        let editorSnapshot = DocumentFileStore.FileSnapshot(
            canonicalJSON: #"{"type":"doc","content":[{"type":"paragraph","content":[{"type":"text","text":"Draft"}]}]}"#,
            htmlContent: "<p>Draft</p>",
            plainText: "Draft",
            wordCount: 1,
            characterCount: 5,
            documentID: document.documentID,
            personalizationOutcomes: [outcome]
        )

        precondition(document.syncFromEditor(snapshot: editorSnapshot))
        precondition(document.currentSnapshot().personalizationOutcomes == [outcome])
        precondition(!document.hasUnsyncedEditorChanges)

        document.markEditorMutation()
        precondition(document.hasUnsyncedEditorChanges)
        _ = document.syncFromEditor(
            html: "<p>Writer revision</p>",
            plainText: "Writer revision",
            words: 2,
            characters: 15
        )
        precondition(document.canonicalJSONContent == nil, "older JSON survived a newer HTML snapshot")
        precondition(document.currentSnapshot().personalizationOutcomes == [outcome])

        document.acknowledgePersonalizationOutcomes([outcome.actionID])
        precondition(document.currentSnapshot().personalizationOutcomes.isEmpty)

        let scratchURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("shakespeare-document-state-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: scratchURL, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: scratchURL) }

        let renameSourceURL = scratchURL.appendingPathComponent("Draft.shkdoc")
        let renameDestinationURL = scratchURL.appendingPathComponent("Revised.shkdoc")
        try Data("draft".utf8).write(to: renameSourceURL)
        try await DocumentFileStore.shared.rename(from: renameSourceURL, to: renameDestinationURL)
        precondition(!FileManager.default.fileExists(atPath: renameSourceURL.path))
        precondition(FileManager.default.fileExists(atPath: renameDestinationURL.path))

        let caseSourceURL = scratchURL.appendingPathComponent("Case.shkdoc")
        let caseDestinationURL = scratchURL.appendingPathComponent("case.shkdoc")
        try Data("case-only".utf8).write(to: caseSourceURL)
        try await DocumentFileStore.shared.rename(from: caseSourceURL, to: caseDestinationURL)
        let caseRenamedData = try Data(contentsOf: caseDestinationURL)
        precondition(caseRenamedData == Data("case-only".utf8))

        let occupiedSourceURL = scratchURL.appendingPathComponent("Source.shkdoc")
        let occupiedDestinationURL = scratchURL.appendingPathComponent("Existing.shkdoc")
        try Data("source".utf8).write(to: occupiedSourceURL)
        try Data("existing".utf8).write(to: occupiedDestinationURL)
        do {
            try await DocumentFileStore.shared.rename(
                from: occupiedSourceURL,
                to: occupiedDestinationURL
            )
            preconditionFailure("rename overwrote an existing document")
        } catch {
            precondition(FileManager.default.fileExists(atPath: occupiedSourceURL.path))
            precondition(FileManager.default.fileExists(atPath: occupiedDestinationURL.path))
        }

        let imageDataURL = "data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVQIHWP4z8DwHwAFgAI/ScL1WQAAAABJRU5ErkJggg=="
        let imageDocumentID = "asset-eval-\(UUID().uuidString)"
        let imagePackageURL = scratchURL.appendingPathComponent("Images.shkdoc", isDirectory: true)
        let imageSnapshot = DocumentFileStore.FileSnapshot(
            canonicalJSON: """
            {"type":"doc","content":[{"type":"paragraph","content":[{"type":"image","attrs":{"src":"\(imageDataURL)"}}]}]}
            """,
            htmlContent: "",
            plainText: "",
            wordCount: 0,
            characterCount: 0,
            documentID: imageDocumentID
        )
        let persistedImageSnapshot = try await DocumentFileStore.shared.save(
            imageSnapshot,
            to: imagePackageURL
        )
        let loadedImageSnapshot = try await DocumentFileStore.shared.load(from: imagePackageURL)
        precondition(loadedImageSnapshot.canonicalJSON == persistedImageSnapshot.canonicalJSON)

        let versionAssets = try await DocumentFileStore.shared.versionAssets(
            for: persistedImageSnapshot,
            sourceDocumentURL: imagePackageURL
        )
        precondition(versionAssets.count == 1, "version snapshot omitted its image")
        let stagedURL = try await DocumentFileStore.shared.stageVersionAssets(
            versionAssets,
            documentID: imageDocumentID
        )
        precondition(FileManager.default.fileExists(
            atPath: stagedURL.appendingPathComponent("assets", isDirectory: true).path
        ))
        try await DocumentFileStore.shared.deleteWorkingAssets(documentID: imageDocumentID)

        let assetDirectory = imagePackageURL.appendingPathComponent("assets", isDirectory: true)
        let assetURL = try FileManager.default.contentsOfDirectory(
            at: assetDirectory,
            includingPropertiesForKeys: nil
        ).first!
        try Data("tampered".utf8).write(to: assetURL, options: .atomic)
        do {
            _ = try await DocumentFileStore.shared.load(from: imagePackageURL)
            preconditionFailure("a tampered content-addressed image was accepted")
        } catch {
            // Expected: package reads verify image bytes, dimensions, and digest.
        }

        print("Document-state evals passed (fresh snapshots, safe renames, asset-complete versions, tamper detection, learning outcomes).")
    }
}
