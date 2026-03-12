import SwiftUI

@Observable
@MainActor
final class OralityRewriteViewModel {
    var rewrittenText: String = ""
    var isRewriting = false
    var error: String?

    private let apiService = ClaudeAPIService()

    func rewriteForOrality(fullText: String, oralityResult: OralityResult) async {
        isRewriting = true
        rewrittenText = ""
        error = nil
        defer { isRewriting = false }

        let prompt = buildPrompt(fullText: fullText, oralityResult: oralityResult)
        let messages: [[String: Any]] = [["role": "user", "content": prompt]]

        do {
            for try await chunk in apiService.streamMessage(messages: messages) {
                if case .text(let text) = chunk {
                    rewrittenText += text
                }
            }
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func buildPrompt(fullText: String, oralityResult: OralityResult) -> String {
        var literateDetails = ""
        for sentence in oralityResult.sentences where sentence.category == "literate" {
            let markerNames = sentence.markers.map {
                "\($0.name.replacingOccurrences(of: "_", with: " ")) (\(Int($0.confidence * 100))%)"
            }.joined(separator: ", ")
            literateDetails += "- \"\(sentence.text)\" [markers: \(markerNames)]\n"
        }

        return """
        You are an expert editor specializing in oral style writing. Your task is to rewrite \
        a document to improve its orality score while preserving meaning.

        The following sentences were identified as "literate" (overly formal/written style) \
        and need to be rewritten in a more oral, conversational style:

        \(literateDetails)

        Here is the full document text:

        ---
        \(fullText)
        ---

        Rewrite the FULL document, keeping sentences that are already oral-style unchanged, \
        and rewriting only the literate sentences to be more oral and conversational. \
        Preserve the document's meaning, structure, and paragraph breaks. \
        Return ONLY the rewritten text with no commentary, no markdown formatting, no explanations.
        """
    }

    func reset() {
        rewrittenText = ""
        error = nil
    }
}
