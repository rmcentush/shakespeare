import Foundation

@main
private struct CanonicalDocumentEvals {
    static func main() throws {
        try CanonicalDocumentValidator.validate(#"{"type":"doc","content":[{"type":"heading","attrs":{"level":1},"content":[{"type":"text","text":"Title","marks":[{"type":"bold"}]}]},{"type":"paragraph","content":[{"type":"text","text":"Draft","marks":[{"type":"link","attrs":{"href":"https://example.com"}}]}]}]}"#)

        expect(.unsupportedNode("table")) {
            try CanonicalDocumentValidator.validate(#"{"type":"doc","content":[{"type":"table"}]}"#)
        }
        expect(.unsupportedMark("highlight")) {
            try CanonicalDocumentValidator.validate(#"{"type":"doc","content":[{"type":"paragraph","content":[{"type":"text","text":"x","marks":[{"type":"highlight"}]}]}]}"#)
        }
        expect(.malformedNode) {
            try CanonicalDocumentValidator.validate(#"{"type":"doc","content":[{"type":"text","content":[]}]}"#)
        }
        expect(.invalidRoot) {
            try CanonicalDocumentValidator.validate(#"{"type":"paragraph"}"#)
        }

        var nested: [String: Any] = ["type": "paragraph"]
        for _ in 0...CanonicalDocumentEvals.maximumAcceptedDepth {
            nested = ["type": "blockquote", "content": [nested]]
        }
        let deepRoot: [String: Any] = ["type": "doc", "content": [nested]]
        let deepData = try JSONSerialization.data(withJSONObject: deepRoot)
        let deepJSON = String(decoding: deepData, as: UTF8.self)
        expect(.documentTooComplex) {
            try CanonicalDocumentValidator.validate(deepJSON)
        }

        print("Canonical document evals passed (valid schema, nodes, marks, shape, root, complexity).")
    }

    private static let maximumAcceptedDepth = 100

    private static func expect(
        _ expected: CanonicalDocumentValidationError,
        operation: () throws -> Void
    ) {
        do {
            try operation()
            preconditionFailure("Expected \(expected)")
        } catch let error as CanonicalDocumentValidationError {
            precondition(matches(error, expected), "Unexpected validation error: \(error)")
        } catch {
            preconditionFailure("Unexpected error: \(error)")
        }
    }

    private static func matches(
        _ actual: CanonicalDocumentValidationError,
        _ expected: CanonicalDocumentValidationError
    ) -> Bool {
        switch (actual, expected) {
        case (.invalidJSON, .invalidJSON),
             (.invalidRoot, .invalidRoot),
             (.malformedNode, .malformedNode),
             (.documentTooComplex, .documentTooComplex):
            return true
        case (.unsupportedNode(let actual), .unsupportedNode(let expected)),
             (.unsupportedMark(let actual), .unsupportedMark(let expected)):
            return actual == expected
        default:
            return false
        }
    }
}
