import Foundation

final class StyleFeedbackStore {
    static let shared = StyleFeedbackStore()

    struct EditDecision: Codable, Identifiable, Equatable {
        let id: String
        let decision: String
        let source: String
        let kind: String
        let originalText: String
        let replacementText: String
        let surroundingSentence: String
        let groupID: String
        let rationale: String
        let timestamp: Double
    }

    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    var feedbackLogURL: URL {
        AuthorStyleReference.styleDirectoryURL.appendingPathComponent("feedback_log.jsonl")
    }

    var processedIDsURL: URL {
        AuthorStyleReference.styleDirectoryURL.appendingPathComponent("processed_feedback_ids.json")
    }

    private init() {
        encoder.outputFormatting = [.sortedKeys]
    }

    func append(_ decision: EditDecision) {
        do {
            try ensureStorage()
            let data = try encoder.encode(decision)
            var line = Data()
            line.append(data)
            line.append(0x0a)

            if FileManager.default.fileExists(atPath: feedbackLogURL.path) {
                let handle = try FileHandle(forWritingTo: feedbackLogURL)
                try handle.seekToEnd()
                try handle.write(contentsOf: line)
                try handle.close()
            } else {
                try line.write(to: feedbackLogURL, options: .atomic)
            }
            try protectFile(at: feedbackLogURL)
        } catch {
            print("StyleFeedbackStore: failed to append feedback: \(error)")
        }
    }

    func appendBridgeDecision(_ data: BridgePayload.EditDecisionData) {
        append(
            EditDecision(
                id: data.eventID.isEmpty ? UUID().uuidString : data.eventID,
                decision: data.decision,
                source: data.source,
                kind: data.learningCategory.isEmpty ? data.kind : data.learningCategory,
                originalText: data.originalText,
                replacementText: data.replacementText,
                surroundingSentence: data.surroundingSentence,
                groupID: data.groupID,
                rationale: data.rationale,
                timestamp: data.timestamp > 0 ? data.timestamp : Date().timeIntervalSince1970 * 1000
            )
        )
    }

    func appendCommentDecision(
        decision: String,
        comment: BridgePayload.CommentData
    ) {
        append(
            EditDecision(
                id: "\(comment.id)_\(decision)_\(Int(Date().timeIntervalSince1970 * 1000))",
                decision: decision,
                source: comment.source.isEmpty ? "agent_comment" : comment.source,
                kind: comment.kind.isEmpty ? "comment" : comment.kind,
                originalText: comment.selectedText,
                replacementText: comment.suggestedReplacement,
                surroundingSentence: comment.selectedText,
                groupID: comment.id,
                rationale: comment.text,
                timestamp: Date().timeIntervalSince1970 * 1000
            )
        )
    }

    func allDecisions() -> [EditDecision] {
        guard let raw = try? String(contentsOf: feedbackLogURL, encoding: .utf8) else {
            return []
        }

        return raw
            .split(separator: "\n")
            .compactMap { line -> EditDecision? in
                guard let data = String(line).data(using: .utf8) else { return nil }
                return try? decoder.decode(EditDecision.self, from: data)
            }
    }

    func processedIDs() -> Set<String> {
        guard let data = try? Data(contentsOf: processedIDsURL),
              let ids = try? decoder.decode([String].self, from: data)
        else {
            return []
        }
        return Set(ids)
    }

    func unprocessedDecisions(limit: Int = 80) -> [EditDecision] {
        let processed = processedIDs()
        return allDecisions()
            .filter { !processed.contains($0.id) }
            .suffix(limit)
    }

    func unprocessedStyleDecisions(limit: Int = 80) -> [EditDecision] {
        let processed = processedIDs()
        return allDecisions()
            .filter { !processed.contains($0.id) && Self.isStyleLearningEligible($0) }
            .suffix(limit)
    }

    func pendingDecisionCount() -> Int {
        let processed = processedIDs()
        return allDecisions().filter {
            !processed.contains($0.id) && Self.isStyleLearningEligible($0)
        }.count
    }

    func recentRejectedDecisions(limit: Int = 10) -> [EditDecision] {
        allDecisions()
            .reversed()
            .filter { $0.decision == "reject" || $0.decision == "dismiss" }
            .prefix(limit)
            .reversed()
    }

    func markProcessed(ids: [String]) throws {
        try ensureStorage()
        var processed = processedIDs()
        ids.forEach { processed.insert($0) }
        let data = try encoder.encode(Array(processed).sorted())
        try data.write(to: processedIDsURL, options: .atomic)
        try protectFile(at: processedIDsURL)
    }

    func learnedPreferences() -> String {
        AuthorStyleReference.learnedPreferences
    }

    func writeLearnedPreferences(_ content: String) throws {
        try AuthorStyleReference.writeLearnedPreferences(content)
    }

    private static func isStyleLearningEligible(_ decision: EditDecision) -> Bool {
        let styleKinds: Set<String> = [
            "voice",
            "tone",
            "clarity",
            "structure",
            "concision",
            "style",
        ]
        return styleKinds.contains(decision.kind.lowercased())
            && !decision.originalText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func ensureStorage() throws {
        try FileManager.default.createDirectory(
            at: AuthorStyleReference.styleDirectoryURL,
            withIntermediateDirectories: true
        )
        _ = AuthorStyleReference.content
    }

    private func protectFile(at url: URL) throws {
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: url.path
        )
    }
}
