import Foundation

@main
struct WritingQualityEvals {
    static func main() throws {
        try distinguishesValidSilenceFromMalformedOutput()
        try acceptsPreciselyAnchoredSuggestions()
        try rejectsHallucinatedAndAmbiguousAnchors()
        try rejectsUnhelpfulOrOversizedSuggestions()
        enforcesPromptAndSchemaQualityPolicy()
        print("Writing-quality evals passed (5 cases: valid silence, exact anchoring, hallucination rejection, usefulness bounds, prompt policy).")
    }

    private static func distinguishesValidSilenceFromMalformedOutput() throws {
        try require(
            try AmbientReviewContract.decode("{\"comments\":[]}").isEmpty,
            "valid empty review was rejected"
        )
        do {
            _ = try AmbientReviewContract.decode("not-json")
            fatalError("Writing-quality eval failed: malformed output was accepted as no feedback")
        } catch AmbientReviewContract.ContractError.invalidResponse {
            // Expected.
        }
    }

    private static func acceptsPreciselyAnchoredSuggestions() throws {
        let response = """
        {"comments":[{"block_id":"p2","exact_original":"It is important to note that the vote moved.","comment":"Open with the concrete action instead of throat-clearing.","kind":"voice","severity":"medium","suggested_replacement":"The vote moved."}]}
        """
        let decoded = try AmbientReviewContract.decode(response)
        let validated = AmbientReviewContract.validated(
            decoded,
            against: [
                .init(id: "p2", type: "paragraph", text: "It is important to note that the vote moved.")
            ]
        )
        require(validated == decoded, "a precise, actionable suggestion was filtered")
    }

    private static func rejectsHallucinatedAndAmbiguousAnchors() throws {
        let response = """
        {"comments":[
          {"block_id":"p1","exact_original":"missing sentence","comment":"This text is not present.","kind":"clarity","severity":"low","suggested_replacement":""},
          {"block_id":"p2","exact_original":"The claim repeats.","comment":"Remove the repetition.","kind":"concision","severity":"medium","suggested_replacement":""},
          {"block_id":"code","exact_original":"let value = 1","comment":"Rewrite code as prose.","kind":"voice","severity":"low","suggested_replacement":"Value is one."}
        ]}
        """
        let decoded = try AmbientReviewContract.decode(response)
        let validated = AmbientReviewContract.validated(
            decoded,
            against: [
                .init(id: "p1", type: "paragraph", text: "A different sentence appears here."),
                .init(id: "p2", type: "paragraph", text: "The claim repeats. The claim repeats."),
                .init(id: "code", type: "codeBlock", text: "let value = 1"),
            ]
        )
        require(validated.isEmpty, "an unsafe target passed the local quality gate")
    }

    private static func rejectsUnhelpfulOrOversizedSuggestions() throws {
        let original = "The result arrived late."
        let suggestions = [
            AmbientReviewSuggestion(
                blockID: "p1",
                exactOriginal: original,
                comment: "No actual change.",
                kind: "clarity",
                severity: "low",
                suggestedReplacement: original
            ),
            AmbientReviewSuggestion(
                blockID: "p1",
                exactOriginal: original,
                comment: String(repeating: "x", count: 501),
                kind: "clarity",
                severity: "low",
                suggestedReplacement: "The result was late."
            ),
        ]
        let validated = AmbientReviewContract.validated(
            suggestions,
            against: [.init(id: "p1", type: "paragraph", text: original)]
        )
        require(validated.isEmpty, "an unchanged or oversized suggestion passed the quality gate")
    }

    private static func enforcesPromptAndSchemaQualityPolicy() {
        let prompt = AmbientReviewContract.systemPrompt
        require(prompt.contains("preserve deliberate irregularities"), "voice-preservation policy disappeared")
        require(prompt.contains("document flow"), "essay-flow policy disappeared")
        require(prompt.contains("Do not repeat"), "duplicate-feedback policy disappeared")
        let schema = AmbientReviewContract.outputSchema()
        let properties = schema["properties"] as? [String: Any]
        let comments = properties?["comments"] as? [String: Any]
        require(comments?["maxItems"] as? Int == 4, "suggestion-count cap disappeared")
    }

    private static func require(_ condition: @autoclosure () throws -> Bool, _ message: String) rethrows {
        guard try condition() else { fatalError("Writing-quality eval failed: \(message)") }
    }
}
