import Foundation
import SQLite3

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
            notes: "Confirm the image credit.",
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
        precondition(restored?.notes == snapshot.notes, "version notes did not round-trip")
        precondition(restored?.assets[filename] == imageData, "version image did not round-trip")

        var revisedNotesSnapshot = snapshot
        revisedNotesSnapshot.notes = "Image credit confirmed."
        try await store.saveVersion(
            filePath: "/tmp/Draft.shkdoc",
            snapshot: revisedNotesSnapshot,
            versionAssets: [filename: imageData]
        )
        let revisedSummaries = try await store.versionSummaries(
            forFile: "/tmp/Draft.shkdoc",
            documentID: documentID
        )
        precondition(revisedSummaries.count == 2, "a note-only change was deduplicated")
        let revised = try await store.version(id: revisedSummaries[0].id)
        precondition(revised?.notes == revisedNotesSnapshot.notes)

        for summary in revisedSummaries {
            try await store.deleteVersion(id: summary.id)
        }
        let remaining = try await store.versionSummaries(
            forFile: "/tmp/Draft.shkdoc",
            documentID: documentID
        )
        precondition(remaining.isEmpty)

        let legacyDatabaseURL = root.appendingPathComponent("legacy-versions.sqlite")
        var legacyDatabase: OpaquePointer?
        precondition(sqlite3_open(legacyDatabaseURL.path, &legacyDatabase) == SQLITE_OK)
        let legacySchema = """
        CREATE TABLE versions (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            file_path TEXT NOT NULL,
            document_id TEXT,
            version_name TEXT,
            json_content TEXT,
            html_content TEXT NOT NULL DEFAULT '',
            plain_text TEXT NOT NULL DEFAULT '',
            word_count INTEGER DEFAULT 0,
            character_count INTEGER DEFAULT 0,
            created_at REAL NOT NULL,
            is_named INTEGER DEFAULT 0
        );
        """
        precondition(sqlite3_exec(legacyDatabase, legacySchema, nil, nil, nil) == SQLITE_OK)
        sqlite3_close(legacyDatabase)

        let migratedStore = VersionStore(testingDatabaseURL: legacyDatabaseURL)
        let migratedSnapshot = DocumentFileStore.FileSnapshot(
            htmlContent: "<p>Legacy document</p>",
            notes: "Notes survive the additive database migration."
        )
        try await migratedStore.saveVersion(
            filePath: "/tmp/Legacy.shkdoc",
            snapshot: migratedSnapshot,
            versionAssets: [:]
        )
        let migratedSummaries = try await migratedStore.versionSummaries(
            forFile: "/tmp/Legacy.shkdoc",
            documentID: migratedSnapshot.documentID
        )
        precondition(migratedSummaries.count == 1)
        let migratedVersion = try await migratedStore.version(id: migratedSummaries[0].id)
        precondition(migratedVersion?.notes == migratedSnapshot.notes)

        print("Version-store evals passed (transactional save, note-aware deduplication, migration, naming, asset restore, deletion).")
    }
}
