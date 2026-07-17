import Foundation

/// Selects a small, query-aware document view for research chat. The assistant
/// gets local relevance plus a sparse beginning-to-end map without resending a
/// long draft on every turn.
enum ChatDocumentContextAssembler {
    static let standardMaximumCharacters = 6_000
    static let wholeDocumentMaximumCharacters = 12_000

    private static let maximumSegmentCharacters = 900
    private static let stopWords: Set<String> = [
        "a", "about", "an", "and", "are", "as", "at", "be", "by", "can", "do",
        "for", "from", "how", "i", "if", "in", "is", "it", "me", "my", "of",
        "on", "or", "that", "the", "this", "to", "was", "what", "when", "where",
        "which", "who", "why", "will", "with", "would", "you", "your",
    ]
    private static let wholeDocumentPhrases = [
        "whole draft", "entire draft", "whole document", "entire document",
        "overall argument", "overall flow", "essay structure", "document structure",
        "across the essay", "across the draft",
    ]

    private struct Segment {
        let index: Int
        let text: String
    }

    private struct RankedSegment {
        let index: Int
        let score: Int
    }

    static func assemble(document: String, query: String, selection: String? = nil) -> String {
        let normalized = normalize(document)
        guard !normalized.isEmpty else { return "" }

        let asksForWholeDocument = wholeDocumentPhrases.contains {
            query.localizedCaseInsensitiveContains($0)
        }
        let maximumCharacters = asksForWholeDocument
            ? wholeDocumentMaximumCharacters
            : standardMaximumCharacters
        guard normalized.count > maximumCharacters else { return normalized }

        let segments = makeSegments(from: normalized)
        guard segments.count > 1 else {
            return bounded(normalized, to: maximumCharacters)
        }

        let queryTerms = terms(in: query)
        let selectionTerms = terms(in: selection ?? "")
        var priorities: [Int: Int] = [:]
        func promote(_ index: Int, to priority: Int) {
            guard segments.indices.contains(index) else { return }
            priorities[index] = max(priorities[index] ?? 0, priority)
        }

        promote(segments.startIndex, to: 100)
        promote(segments.index(after: segments.startIndex), to: 85)
        promote(segments.index(before: segments.endIndex), to: 100)
        promote(segments.index(before: segments.endIndex) - 1, to: 85)

        var ranked: [RankedSegment] = []
        for segment in segments {
            let textTerms = terms(in: segment.text)
            let queryScore = overlapScore(
                evidence: textTerms,
                query: queryTerms,
                weight: 4
            )
            let selectionScore = overlapScore(
                evidence: textTerms,
                query: selectionTerms,
                weight: 7
            )
            let score = queryScore + selectionScore
            if score > 0 {
                ranked.append(RankedSegment(index: segment.index, score: score))
            }
        }
        ranked.sort { left, right in
            left.score == right.score ? left.index < right.index : left.score > right.score
        }

        for result in ranked.prefix(asksForWholeDocument ? 10 : 6) {
            promote(result.index, to: 120 + result.score)
            promote(result.index - 1, to: 75)
            promote(result.index + 1, to: 75)
        }

        let checkpointCount = asksForWholeDocument ? 14 : 8
        if checkpointCount > 1 {
            for checkpoint in 0..<checkpointCount {
                let index = checkpoint * (segments.count - 1) / (checkpointCount - 1)
                promote(index, to: 60)
            }
        }

        let rankedCandidates = priorities.keys.sorted { left, right in
            let leftPriority = priorities[left] ?? 0
            let rightPriority = priorities[right] ?? 0
            return leftPriority == rightPriority ? left < right : leftPriority > rightPriority
        }
        var accepted: [Int] = []
        var estimatedCharacters = 220
        for index in rankedCandidates {
            let cost = segments[index].text.count + 70
            guard estimatedCharacters + cost <= maximumCharacters else { continue }
            accepted.append(index)
            estimatedCharacters += cost
        }

        let excerpts = accepted.sorted().map { index in
            let percent = Int((Double(index) / Double(max(segments.count - 1, 1)) * 100).rounded())
            return "[Draft position \(percent)%]\n\(segments[index].text)"
        }
        let result = """
        [Query-aware excerpts from a longer draft; omitted passages are not evidence of absence.]

        \(excerpts.joined(separator: "\n\n"))
        """
        return bounded(result, to: maximumCharacters)
    }

    private static func makeSegments(from document: String) -> [Segment] {
        var chunks: [String] = []
        for paragraph in document.components(separatedBy: "\n\n") {
            let trimmed = paragraph.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            var remaining = trimmed[...]
            while remaining.count > maximumSegmentCharacters {
                let tentativeEnd = remaining.index(
                    remaining.startIndex,
                    offsetBy: maximumSegmentCharacters
                )
                let prefix = remaining[..<tentativeEnd]
                let split = prefix.lastIndex(where: { $0.isWhitespace }) ?? tentativeEnd
                let chunk = remaining[..<split].trimmingCharacters(in: .whitespacesAndNewlines)
                if !chunk.isEmpty { chunks.append(chunk) }
                remaining = remaining[split...].drop(while: { $0.isWhitespace })
            }
            let tail = remaining.trimmingCharacters(in: .whitespacesAndNewlines)
            if !tail.isEmpty { chunks.append(tail) }
        }
        return chunks.enumerated().map { Segment(index: $0.offset, text: $0.element) }
    }

    private static func normalize(_ text: String) -> String {
        text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .replacingOccurrences(of: "\u{00a0}", with: " ")
            .replacingOccurrences(of: "[ \t]+", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "\n{3,}", with: "\n\n", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func terms(in text: String) -> Set<String> {
        let words = text.lowercased().components(
            separatedBy: CharacterSet.alphanumerics.inverted
        )
        return Set(words.filter { $0.count >= 3 && !stopWords.contains($0) })
    }

    private static func overlapScore(
        evidence: Set<String>,
        query: Set<String>,
        weight: Int
    ) -> Int {
        query.reduce(into: 0) { score, term in
            if evidence.contains(term) { score += weight }
        }
    }

    private static func bounded(_ text: String, to maximumCharacters: Int) -> String {
        guard text.count > maximumCharacters else { return text }
        let marker = "\n\n[Excerpt clipped to the context budget.]"
        return String(text.prefix(max(0, maximumCharacters - marker.count))) + marker
    }
}
