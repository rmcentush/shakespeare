import SwiftUI

enum OralityAnalysisScope {
    case selection
    case document

    var title: String {
        switch self {
        case .selection:
            return "Selection"
        case .document:
            return "Document"
        }
    }

    var detail: String {
        switch self {
        case .selection:
            return "Focused analysis of the current selection"
        case .document:
            return "Full-document analysis"
        }
    }
}

struct OralityParagraphAnalysis: Identifiable {
    let id = UUID()
    let index: Int
    let text: String
    let sentences: [OralityResult.SentenceAnalysis]

    var literateSentences: [OralityResult.SentenceAnalysis] {
        sentences.filter { $0.category == "literate" }
    }

    var oralSentences: [OralityResult.SentenceAnalysis] {
        sentences.filter { $0.category == "oral" }
    }
}

@Observable
@MainActor
final class OralityViewModel {
    var result: OralityResult?
    var analysisText = ""
    var analysisScope: OralityAnalysisScope = .document
    var paragraphs: [OralityParagraphAnalysis] = []
    var isLoading = false
    var error: String?

    private let apiService = HavelockAPIService()

    var literateParagraphs: [OralityParagraphAnalysis] {
        paragraphs.filter { !$0.literateSentences.isEmpty }
    }

    var literateSentences: [OralityResult.SentenceAnalysis] {
        result?.sentences.filter { $0.category == "literate" } ?? []
    }

    func checkOrality(text: String, scope: OralityAnalysisScope) async {
        let normalizedText = Self.normalizeInput(text)
        guard !normalizedText.isEmpty else {
            error = "No text to analyze"
            return
        }

        isLoading = true
        result = nil
        analysisText = normalizedText
        analysisScope = scope
        paragraphs = []
        error = nil
        defer { isLoading = false }

        do {
            let analysisResult = try await apiService.analyzeOrality(text: normalizedText)
            result = analysisResult
            paragraphs = Self.buildParagraphs(from: normalizedText, sentences: analysisResult.sentences)
        } catch {
            self.error = error.localizedDescription
            print("Havelock API check failed: \(error)")
        }
    }

    private static func normalizeInput(_ text: String) -> String {
        text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func buildParagraphs(
        from text: String,
        sentences: [OralityResult.SentenceAnalysis]
    ) -> [OralityParagraphAnalysis] {
        let normalizedText = normalizeInput(text)
        guard !normalizedText.isEmpty else { return [] }

        let paragraphTexts = normalizedText
            .replacingOccurrences(of: #"\n\s*\n+"#, with: "\u{2029}", options: .regularExpression)
            .components(separatedBy: "\u{2029}")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        guard !paragraphTexts.isEmpty else { return [] }

        var sentenceBuckets = Array(repeating: [OralityResult.SentenceAnalysis](), count: paragraphTexts.count)
        var sentenceIndex = 0

        for paragraphIndex in paragraphTexts.indices {
            let paragraphText = paragraphTexts[paragraphIndex]
            var searchStart = paragraphText.startIndex

            while sentenceIndex < sentences.count {
                let sentenceText = sentences[sentenceIndex].text.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !sentenceText.isEmpty else {
                    sentenceBuckets[paragraphIndex].append(sentences[sentenceIndex])
                    sentenceIndex += 1
                    continue
                }

                if let range = paragraphText.range(
                    of: sentenceText,
                    options: [.literal],
                    range: searchStart..<paragraphText.endIndex
                ) {
                    sentenceBuckets[paragraphIndex].append(sentences[sentenceIndex])
                    searchStart = range.upperBound
                    sentenceIndex += 1
                    continue
                }

                break
            }
        }

        if sentenceIndex < sentences.count, let lastIndex = sentenceBuckets.indices.last {
            sentenceBuckets[lastIndex].append(contentsOf: sentences[sentenceIndex...])
        }

        return paragraphTexts.enumerated().map { index, paragraphText in
            OralityParagraphAnalysis(
                index: index + 1,
                text: paragraphText,
                sentences: sentenceBuckets[index]
            )
        }
    }
}
