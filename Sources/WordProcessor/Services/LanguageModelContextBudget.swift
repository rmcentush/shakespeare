import Foundation

/// Central character budgets for document prose sent to model-backed features.
/// The transport still enforces a final byte limit; these feature-level limits
/// keep ordinary requests predictable and prevent one unusually large block
/// from consuming the entire request.
enum LanguageModelContextBudget {
    static let maximumDynamicCharacters = 48_000
    static let maximumGrammarBatchCharacters = 12_000
    static let maximumAmbientBatchCharacters = 32_000
    static let maximumBlockCharacters = 8_000
    static let maximumGapContextCharacters = 24_000
    static let overlapCharacters = 240

    struct TextChunk: Equatable, Sendable {
        let text: String
        let utf16Offset: Int
    }

    static func boundedEdges(
        _ value: String,
        maximumCharacters: Int,
        omission: String = "\n[…content omitted to fit the model context budget…]\n"
    ) -> String {
        guard maximumCharacters > 0 else { return "" }
        guard value.count > maximumCharacters else { return value }
        guard omission.count < maximumCharacters else {
            return String(value.prefix(maximumCharacters))
        }

        let available = maximumCharacters - omission.count
        let prefixCount = (available + 1) / 2
        let suffixCount = available / 2
        return String(value.prefix(prefixCount)) + omission + String(value.suffix(suffixCount))
    }

    /// Splits exact source text into overlapping chunks. Text is never
    /// normalized, so model-returned verbatim anchors remain applicable to the
    /// original editor positions. Offsets use UTF-16 because the editor bridge
    /// and ProseMirror positions are resolved in that coordinate space.
    static func chunks(
        of value: String,
        maximumCharacters: Int = maximumBlockCharacters,
        overlap: Int = overlapCharacters
    ) -> [TextChunk] {
        guard !value.isEmpty, maximumCharacters > 0 else { return [] }
        guard value.count > maximumCharacters else {
            return [TextChunk(text: value, utf16Offset: 0)]
        }

        let safeOverlap = min(max(overlap, 0), max(maximumCharacters / 4, 0))
        var result: [TextChunk] = []
        var start = value.startIndex

        while start < value.endIndex {
            let desiredEnd = value.index(
                start,
                offsetBy: maximumCharacters,
                limitedBy: value.endIndex
            ) ?? value.endIndex
            var end = desiredEnd

            if desiredEnd < value.endIndex {
                let searchStart = value.index(
                    start,
                    offsetBy: maximumCharacters * 3 / 4,
                    limitedBy: desiredEnd
                ) ?? start
                if let boundary = value[searchStart..<desiredEnd]
                    .lastIndex(where: { $0.isWhitespace }) {
                    end = value.index(after: boundary)
                }
            }

            guard end > start else { break }
            let offset = value.utf16.distance(
                from: value.utf16.startIndex,
                to: start.samePosition(in: value.utf16) ?? value.utf16.startIndex
            )
            result.append(TextChunk(text: String(value[start..<end]), utf16Offset: offset))
            guard end < value.endIndex else { break }

            let overlappedStart = value.index(
                end,
                offsetBy: -safeOverlap,
                limitedBy: start
            ) ?? end
            start = overlappedStart > start ? overlappedStart : end
        }

        return result
    }
}
