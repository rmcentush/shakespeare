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
    static func main() {
        let outcome = PersonalizationOutcomeSnapshot(
            actionID: "action-1",
            outcome: "accepted_modified",
            finalText: "Writer revision",
            confidence: 0.9,
            trainingEligible: true
        )
        let document = DocumentModel()
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
        print("Document-state evals passed (fresh snapshots, stale-JSON invalidation, learning outcomes).")
    }
}
