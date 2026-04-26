import Foundation
import NaturalLanguage

struct ResolvedEditTarget {
    let findText: String
    let replaceHTML: String
    let scopeDescription: String?
}

enum EditTargetResolution {
    case useOriginal
    case narrowed(ResolvedEditTarget)
    case retry(String)
}

enum EditTargetResolver {
    private struct Candidate {
        let findText: String
        let replacementText: String
        let scopeDescription: String
    }

    private struct DiffRanges {
        let original: Range<Int>
        let replacement: Range<Int>
    }

    private static let bracketPairs: [(Character, Character)] = [
        ("(", ")"),
        ("[", "]"),
        ("{", "}")
    ]

    static func resolve(
        findText: String,
        replacementHTML: String,
        documentText: String
    ) -> EditTargetResolution {
        let normalizedFind = normalizeText(findText)
        guard !normalizedFind.isEmpty else { return .useOriginal }
        guard !containsFormattingMarkup(replacementHTML) else { return .useOriginal }

        let replacementPlainText = normalizeText(htmlToPlainText(replacementHTML))
        guard !replacementPlainText.isEmpty, replacementPlainText != normalizedFind else {
            return .useOriginal
        }

        let candidates = narrowerCandidates(
            original: normalizedFind,
            replacement: replacementPlainText
        )

        guard !candidates.isEmpty else { return .useOriginal }

        for candidate in candidates {
            guard countOccurrences(of: candidate.findText, in: documentText) == 1 else { continue }

            return .narrowed(
                ResolvedEditTarget(
                    findText: candidate.findText,
                    replaceHTML: escapeHTML(candidate.replacementText),
                    scopeDescription: candidate.scopeDescription
                )
            )
        }

        return .useOriginal
    }

    private static func narrowerCandidates(original: String, replacement: String) -> [Candidate] {
        guard let diffRanges = diffRanges(original: original, replacement: replacement) else { return [] }

        var candidates: [Candidate] = []

        if let candidate = bracketCandidate(original: original, replacement: replacement, diffRanges: diffRanges) {
            candidates.append(candidate)
        }

        if let candidate = sentenceCandidate(original: original, replacement: replacement, diffRanges: diffRanges) {
            candidates.append(candidate)
        }

        var seen = Set<String>()
        return candidates.filter { candidate in
            guard candidate.findText != original,
                  candidate.findText != candidate.replacementText
            else {
                return false
            }

            let key = "\(candidate.findText)\u{001F}\(candidate.replacementText)"
            guard !seen.contains(key) else { return false }
            seen.insert(key)
            return true
        }
    }

    private static func bracketCandidate(
        original: String,
        replacement: String,
        diffRanges: DiffRanges
    ) -> Candidate? {
        for (open, close) in bracketPairs {
            guard let originalRange = enclosingBracketRange(
                in: original,
                diffRange: diffRanges.original,
                open: open,
                close: close
            ),
            let replacementRange = enclosingBracketRange(
                in: replacement,
                diffRange: diffRanges.replacement,
                open: open,
                close: close
            )
            else {
                continue
            }

            let originalText = substring(original, offsetRange: originalRange)
            let replacementText = substring(replacement, offsetRange: replacementRange)

            guard !originalText.isEmpty,
                  !replacementText.isEmpty,
                  originalText.count < original.count
            else {
                continue
            }

            return Candidate(
                findText: originalText,
                replacementText: replacementText,
                scopeDescription: "Scoped to the changed bracketed section."
            )
        }

        return nil
    }

    private static func sentenceCandidate(
        original: String,
        replacement: String,
        diffRanges: DiffRanges
    ) -> Candidate? {
        guard let originalRange = relevantSentenceRange(in: original, diffRange: diffRanges.original),
              let replacementRange = relevantSentenceRange(in: replacement, diffRange: diffRanges.replacement)
        else {
            return nil
        }

        let originalText = normalizeText(substring(original, offsetRange: originalRange))
        let replacementText = normalizeText(substring(replacement, offsetRange: replacementRange))

        guard !originalText.isEmpty,
              !replacementText.isEmpty,
              originalText.count < original.count
        else {
            return nil
        }

        return Candidate(
            findText: originalText,
            replacementText: replacementText,
            scopeDescription: "Scoped to the changed sentence."
        )
    }

    private static func diffRanges(original: String, replacement: String) -> DiffRanges? {
        let originalChars = Array(original)
        let replacementChars = Array(replacement)
        let sharedCount = min(originalChars.count, replacementChars.count)

        var prefix = 0
        while prefix < sharedCount, originalChars[prefix] == replacementChars[prefix] {
            prefix += 1
        }

        if prefix == originalChars.count, prefix == replacementChars.count {
            return nil
        }

        var suffix = 0
        while suffix < originalChars.count - prefix,
              suffix < replacementChars.count - prefix,
              originalChars[originalChars.count - 1 - suffix] == replacementChars[replacementChars.count - 1 - suffix] {
            suffix += 1
        }

        return DiffRanges(
            original: prefix..<(originalChars.count - suffix),
            replacement: prefix..<(replacementChars.count - suffix)
        )
    }

    private static func relevantSentenceRange(
        in text: String,
        diffRange: Range<Int>
    ) -> Range<Int>? {
        let sentences = sentenceOffsetRanges(in: text)
        guard !sentences.isEmpty else {
            return text.isEmpty ? nil : 0..<text.count
        }

        let maxOffset = max(text.count - 1, 0)
        let startAnchor = min(diffRange.lowerBound, maxOffset)
        let endAnchor = min(max(diffRange.upperBound - 1, diffRange.lowerBound), maxOffset)

        let startIndex = sentenceIndex(containing: startAnchor, in: sentences) ?? 0
        let endIndex = sentenceIndex(containing: endAnchor, in: sentences) ?? startIndex

        return sentences[startIndex].lowerBound..<sentences[endIndex].upperBound
    }

    private static func sentenceIndex(
        containing anchor: Int,
        in ranges: [Range<Int>]
    ) -> Int? {
        if let exactIndex = ranges.firstIndex(where: { range in
            anchor >= range.lowerBound && anchor < range.upperBound
        }) {
            return exactIndex
        }

        if let previousIndex = ranges.lastIndex(where: { $0.upperBound <= anchor }) {
            return previousIndex
        }

        return ranges.indices.first
    }

    private static func sentenceOffsetRanges(in text: String) -> [Range<Int>] {
        let normalized = normalizeText(text)
        guard !normalized.isEmpty else { return [] }

        let tokenizer = NLTokenizer(unit: .sentence)
        tokenizer.string = normalized

        var ranges: [Range<Int>] = []
        tokenizer.enumerateTokens(in: normalized.startIndex..<normalized.endIndex) { range, _ in
            let lowerBound = normalized.distance(from: normalized.startIndex, to: range.lowerBound)
            let upperBound = normalized.distance(from: normalized.startIndex, to: range.upperBound)
            if lowerBound < upperBound {
                ranges.append(lowerBound..<upperBound)
            }
            return true
        }

        return ranges.isEmpty ? [0..<normalized.count] : ranges
    }

    private static func enclosingBracketRange(
        in text: String,
        diffRange: Range<Int>,
        open: Character,
        close: Character
    ) -> Range<Int>? {
        let characters = Array(text)
        guard !characters.isEmpty else { return nil }

        let diffStart = min(diffRange.lowerBound, characters.count - 1)
        var depth = 0
        var openIndex: Int?

        for index in stride(from: diffStart, through: 0, by: -1) {
            let character = characters[index]
            if character == close {
                depth += 1
            } else if character == open {
                if depth == 0 {
                    openIndex = index
                    break
                }
                depth -= 1
            }
        }

        guard let openIndex else { return nil }

        depth = 0
        let searchStart = max(diffRange.upperBound, openIndex + 1)
        guard searchStart < characters.count else { return nil }

        for index in searchStart..<characters.count {
            let character = characters[index]
            if character == open {
                depth += 1
            } else if character == close {
                if depth == 0 {
                    return openIndex..<(index + 1)
                }
                depth -= 1
            }
        }

        return nil
    }

    private static func substring(_ text: String, offsetRange: Range<Int>) -> String {
        let lowerBound = index(in: text, offset: offsetRange.lowerBound)
        let upperBound = index(in: text, offset: offsetRange.upperBound)
        return String(text[lowerBound..<upperBound])
    }

    private static func index(in text: String, offset: Int) -> String.Index {
        text.index(text.startIndex, offsetBy: max(0, min(offset, text.count)))
    }

    private static func containsFormattingMarkup(_ html: String) -> Bool {
        let wrapperMarkupRemoved = html
            .replacingOccurrences(of: "(?i)</?p\\b[^>]*>", with: "", options: .regularExpression)
            .replacingOccurrences(of: "(?i)</?div\\b[^>]*>", with: "", options: .regularExpression)
            .replacingOccurrences(of: "(?i)<br\\s*/?>", with: "", options: .regularExpression)

        return wrapperMarkupRemoved.range(of: "<[^>]+>", options: .regularExpression) != nil
    }

    private static func htmlToPlainText(_ html: String) -> String {
        let withLineBreaks = html
            .replacingOccurrences(of: "(?i)<br\\s*/?>", with: "\n", options: .regularExpression)
            .replacingOccurrences(of: "(?i)</p\\s*>", with: "\n", options: .regularExpression)
            .replacingOccurrences(of: "(?i)</div\\s*>", with: "\n", options: .regularExpression)

        let withoutTags = withLineBreaks.replacingOccurrences(
            of: "<[^>]+>",
            with: "",
            options: .regularExpression
        )

        return decodeHTMLEntities(withoutTags)
    }

    private static func decodeHTMLEntities(_ text: String) -> String {
        text
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
    }

    private static func normalizeText(_ text: String) -> String {
        text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func normalizeForSearch(_ text: String) -> String {
        let folded = normalizeText(text)
            .replacingOccurrences(of: "\u{00a0}", with: " ")
            .replacingOccurrences(of: "\u{2018}", with: "'")
            .replacingOccurrences(of: "\u{2019}", with: "'")
            .replacingOccurrences(of: "\u{201A}", with: "'")
            .replacingOccurrences(of: "\u{201B}", with: "'")
            .replacingOccurrences(of: "\u{201C}", with: "\"")
            .replacingOccurrences(of: "\u{201D}", with: "\"")
            .replacingOccurrences(of: "\u{201E}", with: "\"")
            .replacingOccurrences(of: "\u{201F}", with: "\"")
            .lowercased()

        var result = ""
        var previousWasWhitespace = false

        for character in folded {
            if character.isWhitespace {
                if !result.isEmpty, !previousWasWhitespace {
                    result.append(" ")
                    previousWasWhitespace = true
                }
            } else {
                result.append(character)
                previousWasWhitespace = false
            }
        }

        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func countOccurrences(of needle: String, in haystack: String) -> Int {
        let normalizedNeedle = normalizeForSearch(needle)
        let normalizedHaystack = normalizeForSearch(haystack)

        guard !normalizedNeedle.isEmpty, normalizedHaystack.count >= normalizedNeedle.count else {
            return 0
        }

        var count = 0
        var searchStart = normalizedHaystack.startIndex

        while searchStart < normalizedHaystack.endIndex,
              let range = normalizedHaystack.range(
                of: normalizedNeedle,
                options: [],
                range: searchStart..<normalizedHaystack.endIndex
              ) {
            count += 1
            searchStart = range.upperBound
        }

        return count
    }

    private static func escapeHTML(_ text: String) -> String {
        text
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&#39;")
    }
}
