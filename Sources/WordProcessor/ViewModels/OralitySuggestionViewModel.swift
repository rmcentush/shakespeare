import SwiftUI

struct OralitySuggestionState {
    var suggestionText = ""
    var isLoading = false
    var error: String?
    var status: String?
}

@Observable
@MainActor
final class OralitySuggestionViewModel {
    var sentenceStates: [UUID: OralitySuggestionState] = [:]
    var paragraphStates: [UUID: OralitySuggestionState] = [:]

    private let apiService = ClaudeAPIService()

    /// AI writing tropes guidance loaded from bundled resource.
    private static let aiTropesGuidance: String = {
        guard let resourceURL = Bundle.module.url(forResource: "ai_tropes", withExtension: "md"),
              let content = try? String(contentsOf: resourceURL, encoding: .utf8)
        else { return "" }
        return content
    }()

    /// Cached system prompt built once per rewrite session.
    private var cachedSystemPrompt: String?
    private var systemPromptBuilt = false

    func sentenceState(for id: UUID) -> OralitySuggestionState {
        sentenceStates[id] ?? OralitySuggestionState()
    }

    func paragraphState(for id: UUID) -> OralitySuggestionState {
        paragraphStates[id] ?? OralitySuggestionState()
    }

    func suggestSentenceRewrite(
        sentence: OralityResult.SentenceAnalysis,
        paragraphText: String,
        documentContent: String = ""
    ) async {
        let sentenceID = sentence.id
        updateSentenceState(sentenceID) { state in
            state.isLoading = true
            state.suggestionText = ""
            state.error = nil
            state.status = nil
        }

        let systemPrompt = await ensureSystemPrompt(documentContent: documentContent)
        let prompt = buildSentencePrompt(sentence: sentence, paragraphText: paragraphText)
        let messages: [[String: Any]] = [["role": "user", "content": prompt]]

        do {
            var rewritten = ""
            for try await chunk in apiService.streamMessage(messages: messages, systemPrompt: systemPrompt) {
                if case .text(let text) = chunk {
                    rewritten += text
                    updateSentenceState(sentenceID) { state in
                        state.suggestionText = rewritten
                    }
                }
            }

            updateSentenceState(sentenceID) { state in
                state.isLoading = false
                state.suggestionText = sanitizeSuggestion(rewritten)
            }
        } catch {
            updateSentenceState(sentenceID) { state in
                state.isLoading = false
                state.error = error.localizedDescription
            }
        }
    }

    func suggestParagraphRewrite(_ paragraph: OralityParagraphAnalysis, documentContent: String = "") async {
        let paragraphID = paragraph.id
        updateParagraphState(paragraphID) { state in
            state.isLoading = true
            state.suggestionText = ""
            state.error = nil
            state.status = nil
        }

        let systemPrompt = await ensureSystemPrompt(documentContent: documentContent)
        let prompt = buildParagraphPrompt(paragraph)
        let messages: [[String: Any]] = [["role": "user", "content": prompt]]

        do {
            var rewritten = ""
            for try await chunk in apiService.streamMessage(messages: messages, systemPrompt: systemPrompt) {
                if case .text(let text) = chunk {
                    rewritten += text
                    updateParagraphState(paragraphID) { state in
                        state.suggestionText = rewritten
                    }
                }
            }

            updateParagraphState(paragraphID) { state in
                state.isLoading = false
                state.suggestionText = sanitizeSuggestion(rewritten)
            }
        } catch {
            updateParagraphState(paragraphID) { state in
                state.isLoading = false
                state.error = error.localizedDescription
            }
        }
    }

    func clearSentenceSuggestion(for id: UUID) {
        sentenceStates[id] = OralitySuggestionState()
    }

    func clearParagraphSuggestion(for id: UUID) {
        paragraphStates[id] = OralitySuggestionState()
    }

    func setSentenceStatus(_ status: String?, error: String?, for id: UUID) {
        updateSentenceState(id) { state in
            state.status = status
            state.error = error
        }
    }

    func setParagraphStatus(_ status: String?, error: String?, for id: UUID) {
        updateParagraphState(id) { state in
            state.status = status
            state.error = error
        }
    }

    private func ensureSystemPrompt(documentContent: String) async -> String? {
        if systemPromptBuilt { return cachedSystemPrompt }
        cachedSystemPrompt = await buildSystemPrompt(documentContent: documentContent)
        systemPromptBuilt = true
        return cachedSystemPrompt
    }

    private func buildSystemPrompt(documentContent: String) async -> String? {
        let blogVoiceContext = await BlogVoiceLibrary.shared.ensureCorpusAvailable()

        let hasDocument = !documentContent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let hasBlogVoice = !(blogVoiceContext?.isEmpty ?? true)
        let hasTropes = !Self.aiTropesGuidance.isEmpty

        guard hasDocument || hasBlogVoice || hasTropes else { return nil }

        var prompt = """
        You are a writing assistant revising prose to sound more oral, spoken, and natural while preserving meaning. \
        Your rewrites should sound like the user wrote them, not like an AI.
        """

        if hasDocument {
            let trimmed = Self.prepareDocumentContext(documentContent)
            if !trimmed.isEmpty {
                prompt += """

                <current_document>
                The user is currently working on the document below. Use it to understand their writing style, voice, topic, and context.

                \(trimmed)
                </current_document>
                """
            }
        }

        if let blogVoiceContext, !blogVoiceContext.isEmpty {
            prompt += """

            <author_voice_reference>
            The user has a synced corpus of published writing from their blog. Use it as a high-priority reference for voice, cadence, pacing, and rhetorical habits when you rewrite prose.
            Match the style without copying distinctive phrasing, examples, or structure too closely.

            \(blogVoiceContext)
            </author_voice_reference>
            """
        }

        if hasTropes {
            prompt += """

            <writing_style_guidance>
            When rewriting text for the user, follow this guidance carefully:

            \(Self.aiTropesGuidance)
            </writing_style_guidance>
            """
        }

        return prompt
    }

    private nonisolated static let maxDocumentContextCharacters = 24_000

    private nonisolated static func prepareDocumentContext(_ text: String) -> String {
        let normalized = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .replacingOccurrences(of: "\u{00a0}", with: " ")
            .replacingOccurrences(of: "[ \t]+", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "\n{3,}", with: "\n\n", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !normalized.isEmpty else { return "" }
        guard normalized.count > maxDocumentContextCharacters else { return normalized }

        let headCount = maxDocumentContextCharacters / 2
        let tailCount = maxDocumentContextCharacters - headCount
        let head = String(normalized.prefix(headCount))
        let tail = String(normalized.suffix(tailCount))

        return """
        \(head)

        [Document truncated for performance. Middle content omitted.]

        \(tail)
        """
    }

    private func updateSentenceState(_ id: UUID, mutate: (inout OralitySuggestionState) -> Void) {
        var state = sentenceStates[id] ?? OralitySuggestionState()
        mutate(&state)
        sentenceStates[id] = state
    }

    private func updateParagraphState(_ id: UUID, mutate: (inout OralitySuggestionState) -> Void) {
        var state = paragraphStates[id] ?? OralitySuggestionState()
        mutate(&state)
        paragraphStates[id] = state
    }

    private func buildSentencePrompt(
        sentence: OralityResult.SentenceAnalysis,
        paragraphText: String
    ) -> String {
        let markerDetails = markerDetailsText(for: sentence)

        return """
        You are revising prose to sound more oral, spoken, and natural while preserving meaning.

        Havelock classified this sentence as literate:
        "\(sentence.text)"

        Paragraph context:
        "\(paragraphText)"

        Havelock flagged these specific markers — your rewrite should directly address each one:
        \(markerDetails)

        Rewrite only the sentence. Keep the meaning, factual content, and point of view intact.
        Focus your changes on the specific issues each marker identifies. Do not make generic changes unrelated to the flags.
        Return only the rewritten sentence with no explanation, no quotation marks, and no markdown.
        """
    }

    private func buildParagraphPrompt(_ paragraph: OralityParagraphAnalysis) -> String {
        let flaggedSentences = paragraph.literateSentences
            .map { sentence in
                "- \"\(sentence.text)\"\n  Markers: \(markerDetailsText(for: sentence))"
            }
            .joined(separator: "\n")

        return """
        You are revising prose to sound more oral, spoken, and natural while preserving meaning.

        Rewrite this paragraph so it reads more orally while staying faithful to the original content:
        "\(paragraph.text)"

        Havelock flagged these sentences as literate. Your rewrite should directly address the specific markers for each:
        \(flaggedSentences)

        Focus your changes on the specific issues each marker identifies. Do not make generic changes unrelated to the flags.
        Keep the result as a single paragraph. Preserve the meaning and order of ideas.
        Return only the rewritten paragraph with no explanation, no quotation marks, and no markdown.
        """
    }

    private func markerDetailsText(for sentence: OralityResult.SentenceAnalysis) -> String {
        let topMarkers = sentence.markers.isEmpty
            ? [OralityResult.Marker(name: sentence.primaryMarker, confidence: sentence.categoryConfidence)]
            : Array(sentence.markers.prefix(3))

        let details = topMarkers
            .filter { !$0.name.isEmpty }
            .map { marker in
                let displayName = marker.name.replacingOccurrences(of: "_", with: " ")
                let description = OralityResult.descriptionForMarker(marker.name)
                return "- \(displayName) (\(Int(marker.confidence * 100))%): \(description)"
            }

        return details.isEmpty ? "none provided" : details.joined(separator: "\n")
    }

    private func sanitizeSuggestion(_ text: String) -> String {
        text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
