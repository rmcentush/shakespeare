import Foundation

struct StyleProfileDraft: Codable, Equatable, Sendable {
    let proposedMarkdown: String
    let eventIDs: [String]
    let createdAt: Date
}

/// Persists one compact, reviewable profile proposal. Keeping only one draft
/// prevents background refinement from accumulating requests or stale variants.
struct StyleProfileDraftStore: Sendable {
    let fileURL: URL

    func load() throws -> StyleProfileDraft? {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return nil }
        let data = try Data(contentsOf: fileURL)
        let draft = try JSONDecoder().decode(StyleProfileDraft.self, from: data)
        guard !draft.proposedMarkdown.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !draft.eventIDs.isEmpty
        else { return nil }
        return draft
    }

    func save(_ draft: StyleProfileDraft) throws {
        let directory = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o700],
            ofItemAtPath: directory.path
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        try encoder.encode(draft).write(to: fileURL, options: .atomic)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: fileURL.path
        )
    }

    func delete() throws {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
        try FileManager.default.removeItem(at: fileURL)
    }
}
