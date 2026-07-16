import Foundation

final class StyleGuideUpdater {
    struct Proposal: Equatable {
        let proposedMarkdown: String
        let eventIDs: [String]
    }

    enum UpdateError: LocalizedError {
        case noFeedback
        case emptyResponse

        var errorDescription: String? {
            switch self {
            case .noFeedback:
                return "No unprocessed style feedback is available yet."
            case .emptyResponse:
                return "The style updater returned an empty response."
            }
        }
    }

    private let apiService = LanguageModelService()
    private let store: TrainingEventStore

    init(store: TrainingEventStore = .shared) {
        self.store = store
    }

    func proposeUpdate() async throws -> Proposal {
        let decisions = store.unprocessedStyleDecisions(limit: 100)
        guard !decisions.isEmpty else { throw UpdateError.noFeedback }

        let currentPreferences = store.learnedPreferences()
        let batchJSON = try decisionsJSON(decisions)
        let today = ISO8601DateFormatter().string(from: Date()).prefix(10)

        let systemPrompt: [[String: Any]] = [
            [
                "type": "text",
                "text": """
                You update a compact markdown file named learned_preferences.md for a writer's style system.
                Return only the complete proposed markdown file. Do not use code fences.

                Rules:
                - Preserve useful existing rules unless newer evidence contradicts them.
                - Treat each decision as weak evidence, not a direct instruction to alter the style profile.
                - Add or materially strengthen an active rule only when supported by at least 5 consistent decisions from at least 3 distinct group IDs.
                - Put patterns supported by 3 or 4 consistent decisions under "Tentative". Drop patterns supported by only 1 or 2 decisions.
                - Do not create the opposite of a rejected suggestion as a positive preference. A rejection is negative evidence only unless the preferred alternative is independently accepted several times.
                - Do not generalize from topic-specific wording, factual corrections, targeting mistakes, one-off instructions, or document-specific constraints.
                - Conflicting evidence means no new rule. Keep a tentative rule tentative until the stronger threshold is met.
                - Phrase rules as actionable editing guidance.
                - Include date \(today) and evidence count for each rule.
                - Merge duplicates, prune contradicted rules, and keep the whole file under 30 rules and 1,500 words.
                - The input has already been filtered to style-relevant categories, but rejections may still mean bad targeting rather than bad style; infer conservatively from context and rationale.
                """,
                "cache_control": LanguageModelService.oneHourPromptCacheControl
            ]
        ]

        let messages: [[String: Any]] = [
            [
                "role": "user",
                "content": """
                <current_learned_preferences>
                \(currentPreferences)
                </current_learned_preferences>

                <new_decision_batch_json>
                \(batchJSON)
                </new_decision_batch_json>
                """
            ]
        ]

        var response = ""
        for try await chunk in apiService.streamMessage(
            messages: messages,
            systemPrompt: systemPrompt,
            tools: nil,
            cacheControl: nil
        ) {
            if case .text(let text) = chunk {
                response += text
            }
        }

        let markdown = Self.cleanedMarkdown(response)
        guard !markdown.isEmpty else { throw UpdateError.emptyResponse }
        return Proposal(proposedMarkdown: markdown, eventIDs: decisions.map(\.id))
    }

    func approve(_ proposal: Proposal) throws {
        try store.writeLearnedPreferences(proposal.proposedMarkdown)
        try store.markProcessed(ids: proposal.eventIDs)
        AuthorStyleReference.reload()
    }

    static func unifiedDiff(old: String, new: String) -> String {
        let oldLines = old.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        let newLines = new.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        var lines = ["--- current learned_preferences.md", "+++ proposed learned_preferences.md"]
        var oldIndex = 0
        var newIndex = 0

        while oldIndex < oldLines.count || newIndex < newLines.count {
            if oldIndex < oldLines.count,
               newIndex < newLines.count,
               oldLines[oldIndex] == newLines[newIndex] {
                lines.append(" \(oldLines[oldIndex])")
                oldIndex += 1
                newIndex += 1
            } else {
                if oldIndex < oldLines.count {
                    lines.append("-\(oldLines[oldIndex])")
                    oldIndex += 1
                }
                if newIndex < newLines.count {
                    lines.append("+\(newLines[newIndex])")
                    newIndex += 1
                }
            }
        }

        return lines.joined(separator: "\n")
    }

    private func decisionsJSON(_ decisions: [TrainingEventStore.DecisionSummary]) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(decisions)
        return String(decoding: data, as: UTF8.self)
    }

    private static func cleanedMarkdown(_ response: String) -> String {
        var cleaned = response.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned.hasPrefix("```markdown") {
            cleaned.removeFirst("```markdown".count)
        } else if cleaned.hasPrefix("```") {
            cleaned.removeFirst("```".count)
        }
        if cleaned.hasSuffix("```") {
            cleaned.removeLast("```".count)
        }
        return cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
