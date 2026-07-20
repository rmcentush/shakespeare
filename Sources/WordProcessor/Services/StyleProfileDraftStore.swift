import Foundation

struct StyleProfileDraft: Codable, Equatable, Sendable {
    let proposedMarkdown: String
    let eventIDs: [String]
    let createdAt: Date
    let ruleEvidence: [StyleProfileRuleEvidence]
    let evidenceItems: [StyleProfileEvidenceReviewItem]

    init(
        proposedMarkdown: String,
        eventIDs: [String],
        createdAt: Date,
        ruleEvidence: [StyleProfileRuleEvidence] = [],
        evidenceItems: [StyleProfileEvidenceReviewItem] = []
    ) {
        self.proposedMarkdown = proposedMarkdown
        self.eventIDs = eventIDs
        self.createdAt = createdAt
        self.ruleEvidence = ruleEvidence
        self.evidenceItems = evidenceItems
    }

    enum CodingKeys: String, CodingKey {
        case proposedMarkdown, eventIDs, createdAt, ruleEvidence, evidenceItems
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        proposedMarkdown = try container.decode(String.self, forKey: .proposedMarkdown)
        eventIDs = try container.decode([String].self, forKey: .eventIDs)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        ruleEvidence = try container.decodeIfPresent(
            [StyleProfileRuleEvidence].self,
            forKey: .ruleEvidence
        ) ?? []
        evidenceItems = try container.decodeIfPresent(
            [StyleProfileEvidenceReviewItem].self,
            forKey: .evidenceItems
        ) ?? []
    }
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
        guard isValid(draft) else { return nil }
        return draft
    }

    func save(_ draft: StyleProfileDraft) throws {
        guard isValid(draft) else {
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

    private func isValid(_ draft: StyleProfileDraft) -> Bool {
        let eventIDs = Set(draft.eventIDs)
        return !draft.proposedMarkdown.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && draft.proposedMarkdown.count <= StyleProfileCompiler.maximumProfileCharacters
            && !draft.eventIDs.isEmpty
            && draft.eventIDs.count <= 4_000
            && eventIDs.count == draft.eventIDs.count
            && draft.eventIDs.allSatisfy { !$0.isEmpty && $0.utf8.count <= 256 }
            && draft.ruleEvidence.count <= StyleProfileCompiler.maximumEstablishedRules
                + StyleProfileCompiler.maximumEmergingRules
            && draft.ruleEvidence.allSatisfy { rule in
                !rule.dimension.isEmpty
                    && rule.dimension.count <= 40
                    && rule.guidance.count >= 12
                    && rule.guidance.count <= 180
                    && rule.sampleIDs.count <= StyleProfileEvidenceCompiler.maximumSamples
                    && rule.editIDs.count <= StyleProfileEvidenceCompiler.maximumEdits
                    && rule.sessionIDs.count <= StyleProfileEvidenceCompiler.maximumEdits
                    && (rule.sampleIDs + rule.editIDs).allSatisfy {
                        eventIDs.contains($0)
                    }
            }
            && draft.evidenceItems.count <= StyleProfileEvidenceCompiler.maximumSamples
                + StyleProfileEvidenceCompiler.maximumEdits
            && draft.evidenceItems.allSatisfy {
                eventIDs.contains($0.id)
                    && $0.id.utf8.count <= 256
                    && $0.summary.count <= 420
            }
    }
}
