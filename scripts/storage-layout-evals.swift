import Darwin
import Foundation

@main
struct StorageLayoutEvals {
    static func main() throws {
        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory
            .appendingPathComponent("shakespeare-storage-evals-\(UUID().uuidString)")
            .appendingPathComponent("Shakespeare")
        defer { try? fileManager.removeItem(at: root.deletingLastPathComponent()) }

        try fileManager.createDirectory(
            at: root.appendingPathComponent("WorkingDocuments"),
            withIntermediateDirectories: true
        )
        try "working".write(
            to: root.appendingPathComponent("WorkingDocuments/draft.shkdoc"),
            atomically: true,
            encoding: .utf8
        )
        try fileManager.createDirectory(
            at: root.appendingPathComponent("RecoveryDrafts"),
            withIntermediateDirectories: true
        )
        try "recovery".write(
            to: root.appendingPathComponent("RecoveryDrafts/draft.json"),
            atomically: true,
            encoding: .utf8
        )
        try "sqlite".write(
            to: root.appendingPathComponent("versions.sqlite"),
            atomically: true,
            encoding: .utf8
        )
        try fileManager.createDirectory(
            at: root.appendingPathComponent("personalization/events"),
            withIntermediateDirectories: true
        )
        try "{\"id\":\"new\"}\n".write(
            to: root.appendingPathComponent("personalization/events/training_events.jsonl"),
            atomically: true,
            encoding: .utf8
        )
        try "{\"id\":\"old\"}\n{\"id\":\"new\"}\n".write(
            to: root.appendingPathComponent("personalization/training_events.jsonl"),
            atomically: true,
            encoding: .utf8
        )
        try fileManager.createDirectory(
            at: root.appendingPathComponent("style"),
            withIntermediateDirectories: true
        )
        try "preference".write(
            to: root.appendingPathComponent("style/learned_preferences.md"),
            atomically: true,
            encoding: .utf8
        )
        try "temporary-key".write(
            to: root.appendingPathComponent(".openrouter.key"),
            atomically: true,
            encoding: .utf8
        )

        try ShakespeareStorage.prepare(rootURL: root)
        try ShakespeareStorage.prepare(rootURL: root)

        let expected = [
            "README.txt",
            "documents/working/draft.shkdoc",
            "documents/recovery/draft.json",
            "documents/versions.sqlite",
            "personalization/style/learned_preferences.md",
            "credentials/openrouter.key",
        ]
        for relativePath in expected {
            guard fileManager.fileExists(atPath: root.appendingPathComponent(relativePath).path)
            else {
                fail("missing migrated path: \(relativePath)")
            }
        }

        for legacyPath in [
            "WorkingDocuments",
            "RecoveryDrafts",
            "versions.sqlite",
            "style",
            ".openrouter.key",
            "personalization/training_events.jsonl",
        ] where fileManager.fileExists(atPath: root.appendingPathComponent(legacyPath).path) {
            fail("legacy path still exists: \(legacyPath)")
        }

        guard !fileManager.fileExists(atPath: root.appendingPathComponent("personalization/training").path)
        else { fail("obsolete training directory was recreated") }

        let ledger = try String(
            contentsOf: root.appendingPathComponent(
                "personalization/events/training_events.jsonl"
            ),
            encoding: .utf8
        )
        guard ledger.components(separatedBy: "{\"id\":\"new\"}").count - 1 == 1,
              ledger.contains("{\"id\":\"old\"}")
        else {
            fail("ledger migration did not merge and deduplicate records")
        }

        let permissions = try fileManager.attributesOfItem(atPath: root.path)[.posixPermissions]
            as? NSNumber
        guard permissions?.intValue == 0o700 else {
            fail("application data root is not owner-only")
        }

        let styleDirectory = root.appendingPathComponent("personalization/style")
        let referenceURL = styleDirectory.appendingPathComponent("writing_style_reference.md")
        let learnedURL = styleDirectory.appendingPathComponent("learned_preferences.md")
        let draftURL = styleDirectory.appendingPathComponent("pending_style_profile.json")
        try "writer-owned reference".write(to: referenceURL, atomically: true, encoding: .utf8)
        try "learned rule".write(to: learnedURL, atomically: true, encoding: .utf8)
        try "pending review".write(to: draftURL, atomically: true, encoding: .utf8)

        try ShakespeareStorage.resetPersonalization(rootURL: root)

        guard try String(contentsOf: referenceURL, encoding: .utf8) == "writer-owned reference"
        else { fail("learning reset deleted the writer's editable style reference") }
        for deletedURL in [learnedURL, draftURL, root.appendingPathComponent(
            "personalization/events/training_events.jsonl"
        )] where fileManager.fileExists(atPath: deletedURL.path) {
            fail("learning reset retained private evidence: \(deletedURL.lastPathComponent)")
        }
        let referencePermissions = try fileManager.attributesOfItem(atPath: referenceURL.path)[
            .posixPermissions
        ] as? NSNumber
        guard referencePermissions?.intValue == 0o600 else {
            fail("preserved style reference is not owner-only")
        }

        print("Storage layout evals passed (migration, reset safety, privacy, idempotence).")
    }

    private static func fail(_ message: String) -> Never {
        print("Storage layout eval failed: \(message)")
        exit(1)
    }
}
