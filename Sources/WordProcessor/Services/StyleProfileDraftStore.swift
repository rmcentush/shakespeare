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
        let data = try PackageFileSafety.readData(
            from: fileURL,
            maximumBytes: 512 * 1_024,
            displayName: fileURL.lastPathComponent
        )
        let draft = try JSONDecoder().decode(StyleProfileDraft.self, from: data)
        guard !draft.proposedMarkdown.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              draft.proposedMarkdown.count <= 12_000,
              !draft.eventIDs.isEmpty,
              draft.eventIDs.count <= 4_000,
              draft.eventIDs.allSatisfy({ !$0.isEmpty && $0.utf8.count <= 256 })
        else { return nil }
        return draft
    }

    func save(_ draft: StyleProfileDraft) throws {
        guard !draft.proposedMarkdown.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              draft.proposedMarkdown.count <= 12_000,
              !draft.eventIDs.isEmpty,
              draft.eventIDs.count <= 4_000,
              draft.eventIDs.allSatisfy({ !$0.isEmpty && $0.utf8.count <= 256 })
        else {
            throw CocoaError(.fileWriteInapplicableStringEncoding)
        }
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
        let data = try encoder.encode(draft)
        guard data.count <= 512 * 1_024 else {
            throw CocoaError(.fileWriteFileExists)
        }
        try data.write(to: fileURL, options: .atomic)
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
