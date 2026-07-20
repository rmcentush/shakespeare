import Foundation

@main
struct LanguageModelContextEvals {
    static func main() {
        boundsEdgeContext()
        chunksExactUnicodeTextWithStableOffsets()
        print("Language-model context evals passed (edge bounds, exact chunks, UTF-16 anchors).")
    }

    private static func boundsEdgeContext() {
        let value = String(repeating: "opening ", count: 200)
            + "MIDDLE"
            + String(repeating: " ending", count: 200)
        let bounded = LanguageModelContextBudget.boundedEdges(
            value,
            maximumCharacters: 500
        )
        require(bounded.count == 500, "bounded context did not honor its exact ceiling")
        require(bounded.hasPrefix("opening"), "bounded context lost the beginning")
        require(bounded.hasSuffix("ending"), "bounded context lost the ending")
        require(bounded.contains("omitted"), "bounded context hid truncation")
    }

    private static func chunksExactUnicodeTextWithStableOffsets() {
        let value = (0..<120).map { index in
            "Paragraph \(index) — café 😀 keeps exact anchors intact."
        }.joined(separator: " ")
        let chunks = LanguageModelContextBudget.chunks(
            of: value,
            maximumCharacters: 420,
            overlap: 60
        )
        require(chunks.count > 2, "oversized text was not chunked")
        for chunk in chunks {
            require(chunk.text.count <= 420, "a chunk escaped its ceiling")
            let utf16 = value.utf16
            guard let start = utf16.index(
                utf16.startIndex,
                offsetBy: chunk.utf16Offset,
                limitedBy: utf16.endIndex
            ),
                  let end = utf16.index(
                    start,
                    offsetBy: chunk.text.utf16.count,
                    limitedBy: utf16.endIndex
                  ),
                  let startIndex = start.samePosition(in: value),
                  let endIndex = end.samePosition(in: value)
            else { fatalError("Language-model context eval failed: invalid UTF-16 offset") }
            require(String(value[startIndex..<endIndex]) == chunk.text, "chunk offset drifted")
        }
        require(chunks.first?.utf16Offset == 0, "first chunk did not start at zero")
        require(chunks.last?.text.hasSuffix("intact.") == true, "last chunk lost the document ending")
    }

    private static func require(_ condition: @autoclosure () -> Bool, _ message: String) {
        guard condition() else { fatalError("Language-model context eval failed: \(message)") }
    }
}
