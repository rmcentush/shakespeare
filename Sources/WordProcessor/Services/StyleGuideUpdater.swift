import Foundation

final class StyleGuideUpdater {
    struct Proposal: Equatable {
        let proposedMarkdown: String
        let eventIDs: [String]
    }

    enum UpdateError: LocalizedError {
        case noEvidence
        case emptyResponse

        var errorDescription: String? {
            switch self {
            case .noEvidence:
                return "No new writing samples or reliable style outcomes are available yet."
            case .emptyResponse:
                return "The style refiner returned an empty response. Nothing was changed."
            }
        }
    }

    private let apiService = LanguageModelService()
    private let store: TrainingEventStore

    init(store: TrainingEventStore = .shared) {
        self.store = store
    }

    func proposeUpdate() async throws -> Proposal {
        let decisions = store.unprocessedStyleDecisions(limit: 40)
        let samples = store.unprocessedWritingSamples(limit: 5)
        guard !decisions.isEmpty || !samples.isEmpty else { throw UpdateError.noEvidence }

        let evidence = try StyleProfileEvidenceCompiler.compile(
            samples: samples.map { StyleProfileSampleEvidence(id: $0.id, text: $0.text) },
            edits: decisions.map {
                StyleProfileEditEvidence(
                    id: $0.id,
                    decision: $0.decision,
                    kind: $0.kind,
                    originalText: $0.originalText,
                    replacementText: $0.replacementText,
                    finalText: $0.finalText ?? "",
                    groupID: $0.groupID,
                    rationale: $0.rationale,
                    timestamp: $0.timestamp
                )
            }
        )
        guard !evidence.eventIDs.isEmpty else { throw UpdateError.noEvidence }

        let currentPreferences = store.learnedPreferences()
        let today = String(ISO8601DateFormatter().string(from: Date()).prefix(10))
        let systemPrompt: [[String: Any]] = [[
            "type": "text",
            "text": """
            You refine a compact, evidence-backed writer style profile. Return only JSON matching the supplied schema.

            Rules:
            - Generalize recurring mechanics of voice, syntax, rhythm, diction, paragraph movement, structure, clarity, and concision. Never preserve subject matter, names, facts, quotations, or distinctive phrases.
            - Treat each saved edit outcome as weak evidence, not a direct instruction.
            - A rule is established only with support from at least 2 independent samples, at least 5 consistent edits across 3 sessions, or a mixture of 1 sample and 3 edits across 2 sessions.
            - A rule may be emerging with 1 sample or at least 3 consistent edits across 2 sessions. Drop weaker patterns.
            - Count only supplied evidence that directly supports a rule. Never invent counts. sample_count cannot exceed \(evidence.limits.sampleCount), edit_count cannot exceed \(evidence.limits.editCount), and edit_group_count cannot exceed \(evidence.limits.editGroupCount).
            - Preserve a useful existing rule by repeating its guidance exactly and setting carried_forward=true only when it already appears in the current reviewed profile and the new evidence does not contradict it. The local compiler verifies exact carry-forward matches and preserves their existing status.
            - Do not create the opposite of a rejected suggestion as a positive preference. A rejection is negative evidence unless the writer's preferred alternative is independently supported.
            - Do not generalize from topic-specific wording, factual corrections, targeting mistakes, one-off instructions, or document-specific constraints.
            - Conflicting evidence means no new rule. Prefer omission over a speculative rule.
            - Phrase each rule as concise, actionable editing guidance without examples or quoted prose.
            - Merge duplicates and return no more than 18 rules. A local compiler applies stricter evidence, copying, and size gates afterward.
            - Samples are deliberately excerpted across documents. Edit evidence is already filtered to style-relevant, high-confidence save outcomes.
            """,
            "cache_control": LanguageModelService.ephemeralPromptCacheControl,
        ]]

        let messages: [[String: Any]] = [[
            "role": "user",
            "content": """
            <current_learned_preferences>
            \(String(currentPreferences.prefix(4_000)))
            </current_learned_preferences>

            <representative_sample_excerpts_json>
            \(evidence.samplesJSON)
            </representative_sample_excerpts_json>

            <confirmed_edit_outcomes_json>
            \(evidence.editsJSON)
            </confirmed_edit_outcomes_json>
            """,
        ]]

        var response = ""
        for try await chunk in apiService.streamMessage(
            messages: messages,
            systemPrompt: systemPrompt,
            outputFormat: ["type": "json_schema", "schema": StyleProfileCompiler.outputSchema],
            temperature: 0,
            maxTokens: 3_072
        ) {
            if case .text(let text) = chunk { response += text }
        }

        guard !response.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw UpdateError.emptyResponse
        }
        let markdown = try StyleProfileCompiler.compile(
            response: response,
            limits: evidence.limits,
            sourceTexts: evidence.sourceTexts,
            currentProfile: currentPreferences,
            date: today
        )
        return Proposal(proposedMarkdown: markdown, eventIDs: evidence.eventIDs)
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
}
