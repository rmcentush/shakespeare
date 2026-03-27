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

    func sentenceState(for id: UUID) -> OralitySuggestionState {
        sentenceStates[id] ?? OralitySuggestionState()
    }

    func paragraphState(for id: UUID) -> OralitySuggestionState {
        paragraphStates[id] ?? OralitySuggestionState()
    }

    func suggestSentenceRewrite(
        sentence: OralityResult.SentenceAnalysis,
        paragraphText: String
    ) async {
        let sentenceID = sentence.id
        updateSentenceState(sentenceID) { state in
            state.isLoading = true
            state.suggestionText = ""
            state.error = nil
            state.status = nil
        }

        let prompt = buildSentencePrompt(sentence: sentence, paragraphText: paragraphText)
        let messages: [[String: Any]] = [["role": "user", "content": prompt]]

        do {
            var rewritten = ""
            for try await chunk in apiService.streamMessage(messages: messages) {
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

    func suggestParagraphRewrite(_ paragraph: OralityParagraphAnalysis) async {
        let paragraphID = paragraph.id
        updateParagraphState(paragraphID) { state in
            state.isLoading = true
            state.suggestionText = ""
            state.error = nil
            state.status = nil
        }

        let prompt = buildParagraphPrompt(paragraph)
        let messages: [[String: Any]] = [["role": "user", "content": prompt]]

        do {
            var rewritten = ""
            for try await chunk in apiService.streamMessage(messages: messages) {
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

        Havelock markers:
        \(markerDetails)

        Rewrite only the sentence. Keep the meaning, factual content, and point of view intact.
        Make it sound more spoken and less institutional or academic.
        Return only the rewritten sentence with no explanation, no quotation marks, and no markdown.
        """
    }

    private func buildParagraphPrompt(_ paragraph: OralityParagraphAnalysis) -> String {
        let flaggedSentences = paragraph.literateSentences
            .map { sentence in
                "- \"\(sentence.text)\" [\(markerDetailsText(for: sentence))]"
            }
            .joined(separator: "\n")

        return """
        You are revising prose to sound more oral, spoken, and natural while preserving meaning.

        Rewrite this paragraph so it reads more orally while staying faithful to the original content:
        "\(paragraph.text)"

        Havelock flagged these sentences as literate:
        \(flaggedSentences)

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
                "\(marker.name.replacingOccurrences(of: "_", with: " ")) (\(Int(marker.confidence * 100))%)"
            }

        return details.isEmpty ? "none provided" : details.joined(separator: ", ")
    }

    private func sanitizeSuggestion(_ text: String) -> String {
        text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
