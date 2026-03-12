import Foundation

/// Minimal BERT WordPiece tokenizer for bert-base-uncased.
final class BertTokenizer: Sendable {
    private let vocab: [String: Int]
    private let idToToken: [Int: String]
    private let unkTokenId: Int
    private let clsTokenId: Int
    private let sepTokenId: Int
    private let padTokenId: Int

    init?() {
        guard let url = Bundle.module.url(forResource: "Resources", withExtension: nil)?
            .appendingPathComponent("Havelock")
            .appendingPathComponent("vocab.txt"),
              let content = try? String(contentsOf: url, encoding: .utf8)
        else { return nil }

        var vocab: [String: Int] = [:]
        var idToToken: [Int: String] = [:]
        for (i, line) in content.components(separatedBy: "\n").enumerated() {
            let token = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !token.isEmpty else { continue }
            vocab[token] = i
            idToToken[i] = token
        }

        self.vocab = vocab
        self.idToToken = idToToken
        self.unkTokenId = vocab["[UNK]"] ?? 100
        self.clsTokenId = vocab["[CLS]"] ?? 101
        self.sepTokenId = vocab["[SEP]"] ?? 102
        self.padTokenId = vocab["[PAD]"] ?? 0
    }

    struct TokenizedInput {
        let inputIds: [Int32]
        let attentionMask: [Int32]
    }

    func tokenize(_ text: String, maxLength: Int = 128) -> TokenizedInput {
        let lowered = text.lowercased()

        // Basic tokenization: split on whitespace and punctuation
        let basicTokens = basicTokenize(lowered)

        // WordPiece tokenization
        var wpTokenIds: [Int] = [clsTokenId]
        for token in basicTokens {
            let subTokens = wordPieceTokenize(token)
            // Reserve space for [SEP]
            if wpTokenIds.count + subTokens.count >= maxLength - 1 { break }
            wpTokenIds.append(contentsOf: subTokens)
        }
        wpTokenIds.append(sepTokenId)

        // Pad to maxLength
        let attentionMask = Array(repeating: Int32(1), count: wpTokenIds.count)
            + Array(repeating: Int32(0), count: max(0, maxLength - wpTokenIds.count))

        let padded = wpTokenIds.map { Int32($0) }
            + Array(repeating: Int32(padTokenId), count: max(0, maxLength - wpTokenIds.count))

        return TokenizedInput(
            inputIds: Array(padded.prefix(maxLength)),
            attentionMask: Array(attentionMask.prefix(maxLength))
        )
    }

    // MARK: - Basic tokenization

    private func basicTokenize(_ text: String) -> [String] {
        var tokens: [String] = []
        var current = ""

        for char in text {
            if char.isWhitespace {
                if !current.isEmpty { tokens.append(current) }
                current = ""
            } else if isPunctuation(char) {
                if !current.isEmpty { tokens.append(current) }
                tokens.append(String(char))
                current = ""
            } else {
                current.append(char)
            }
        }
        if !current.isEmpty { tokens.append(current) }
        return tokens
    }

    private func isPunctuation(_ char: Character) -> Bool {
        let scalar = char.unicodeScalars.first!
        let category = scalar.properties.generalCategory
        switch category {
        case .connectorPunctuation, .dashPunctuation, .closePunctuation,
             .finalPunctuation, .initialPunctuation, .otherPunctuation,
             .openPunctuation:
            return true
        default:
            // Also treat some ASCII symbols as punctuation
            if (33...47).contains(scalar.value) || (58...64).contains(scalar.value) ||
               (91...96).contains(scalar.value) || (123...126).contains(scalar.value) {
                return true
            }
            return false
        }
    }

    // MARK: - WordPiece tokenization

    private func wordPieceTokenize(_ token: String) -> [Int] {
        if token.count > 200 { return [unkTokenId] }

        var ids: [Int] = []
        var start = token.startIndex
        var isFirst = true

        while start < token.endIndex {
            var end = token.endIndex
            var foundId: Int?

            while start < end {
                let substr: String
                if isFirst {
                    substr = String(token[start..<end])
                } else {
                    substr = "##" + String(token[start..<end])
                }

                if let id = vocab[substr] {
                    foundId = id
                    break
                }
                end = token.index(before: end)
            }

            if let id = foundId {
                ids.append(id)
                start = end
                isFirst = false
            } else {
                ids.append(unkTokenId)
                break
            }
        }

        return ids
    }
}
