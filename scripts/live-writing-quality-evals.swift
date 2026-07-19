import Foundation

@main
struct LiveWritingQualityEvals {
    private struct Fixture {
        let name: String
        let userPrompt: String
        let blocks: [AmbientReviewContract.Block]
        let requiresSuggestion: Bool
        let forbiddenPhrase: String?
    }

    static func main() async throws {
        guard let apiKey = ProcessInfo.processInfo.environment["OPENROUTER_API_KEY"]?
            .trimmingCharacters(in: .whitespacesAndNewlines),
              !apiKey.isEmpty
        else {
            print("Live writing-quality evals skipped (set OPENROUTER_API_KEY to run three capped model requests).")
            return
        }

        let model = ProcessInfo.processInfo.environment["OPENROUTER_EVAL_MODEL"]?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let selectedModel = (model?.isEmpty == false) ? model! : "google/gemini-3.5-flash"

        for fixture in fixtures {
            let responseText = try await requestReview(
                apiKey: apiKey,
                model: selectedModel,
                userPrompt: fixture.userPrompt
            )
            let decoded = try AmbientReviewContract.decode(responseText)
            let validated = AmbientReviewContract.validated(decoded, against: fixture.blocks)
            require(decoded.count == validated.count, "\(fixture.name): model returned an unsafe or unanchored suggestion")
            if fixture.requiresSuggestion {
                require(!validated.isEmpty, "\(fixture.name): obvious writing problem was missed")
            }
            if let forbiddenPhrase = fixture.forbiddenPhrase {
                let rendered = validated.map {
                    [$0.comment, $0.suggestedReplacement ?? ""].joined(separator: " ")
                }.joined(separator: " ").lowercased()
                require(
                    !rendered.contains(forbiddenPhrase.lowercased()),
                    "\(fixture.name): prose leaked from the style sample"
                )
            }
            print("Live writing-quality eval passed: \(fixture.name) (\(validated.count) suggestion\(validated.count == 1 ? "" : "s")).")
        }
    }

    private static let fixtures: [Fixture] = [
        Fixture(
            name: "direct opening",
            userPrompt: """
            <personal_style_context><reviewed_learned_preferences>Open with the concrete claim; remove throat-clearing.</reviewed_learned_preferences></personal_style_context>
            <edit_context><document_flow_map>[1/1 paragraph] [editable target supplied in full below]</document_flow_map><editable_block_index>
            <block id="p1" type="paragraph">It is important to note that the committee delayed the vote because the estimates arrived late.</block>
            </editable_block_index></edit_context>
            """,
            blocks: [
                .init(
                    id: "p1",
                    type: "paragraph",
                    text: "It is important to note that the committee delayed the vote because the estimates arrived late."
                )
            ],
            requiresSuggestion: true,
            forbiddenPhrase: nil
        ),
        Fixture(
            name: "document-flow repetition",
            userPrompt: """
            <personal_style_context><reviewed_learned_preferences>Advance the argument once the thesis is established; do not restate it.</reviewed_learned_preferences></personal_style_context>
            <edit_context><document_flow_map>[1/3 paragraph] The thesis establishes that remote work changes where people sit.
            [2/3 paragraph] The evidence explains the resulting coordination cost.
            [3/3 paragraph] [editable target supplied in full below]</document_flow_map><editable_block_index>
            <block id="p3" type="paragraph">Remote work changes where people sit. This means remote work changes where people sit.</block>
            </editable_block_index></edit_context>
            """,
            blocks: [
                .init(
                    id: "p3",
                    type: "paragraph",
                    text: "Remote work changes where people sit. This means remote work changes where people sit."
                )
            ],
            requiresSuggestion: true,
            forbiddenPhrase: nil
        ),
        Fixture(
            name: "sample-copy protection",
            userPrompt: """
            <personal_style_context><precedence>Samples demonstrate rhythm only. Never copy their names, facts, or distinctive phrases.</precedence>
            <representative_writing_samples>Blue Orchard turns the silver key at noon.</representative_writing_samples></personal_style_context>
            <edit_context><document_flow_map>[1/1 paragraph] [editable target supplied in full below]</document_flow_map><editable_block_index>
            <block id="p1" type="paragraph">The launch was delayed by two weeks because testing uncovered a fault.</block>
            </editable_block_index></edit_context>
            """,
            blocks: [
                .init(
                    id: "p1",
                    type: "paragraph",
                    text: "The launch was delayed by two weeks because testing uncovered a fault."
                )
            ],
            requiresSuggestion: false,
            forbiddenPhrase: "Blue Orchard turns the silver key at noon"
        ),
    ]

    private static func requestReview(
        apiKey: String,
        model: String,
        userPrompt: String
    ) async throws -> String {
        var request = URLRequest(url: URL(string: "https://openrouter.ai/api/v1/chat/completions")!)
        request.httpMethod = "POST"
        request.timeoutInterval = 60
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "authorization")
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.setValue("Shakespeare Quality Evals", forHTTPHeaderField: "x-title")
        let body: [String: Any] = [
            "model": model,
            "max_tokens": 768,
            "stream": false,
            "messages": [
                ["role": "system", "content": AmbientReviewContract.systemPrompt],
                ["role": "user", "content": userPrompt],
            ],
            "response_format": [
                "type": "json_schema",
                "json_schema": [
                    "name": "shakespeare_response",
                    "strict": true,
                    "schema": AmbientReviewContract.outputSchema(),
                ],
            ],
            "provider": [
                "data_collection": "deny",
                "require_parameters": true,
            ],
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let configuration = URLSessionConfiguration.ephemeral
        configuration.waitsForConnectivity = false
        configuration.timeoutIntervalForRequest = 60
        configuration.timeoutIntervalForResource = 75
        let (data, response) = try await URLSession(configuration: configuration).data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw EvalError("OpenRouter returned a non-HTTP response")
        }
        guard (200..<300).contains(http.statusCode) else {
            let message = Self.safeErrorMessage(from: data)
            throw EvalError("OpenRouter returned HTTP \(http.statusCode): \(message)")
        }
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = object["choices"] as? [[String: Any]],
              let message = choices.first?["message"] as? [String: Any],
              let content = message["content"] as? String,
              !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else { throw EvalError("OpenRouter returned no review text") }
        return content
    }

    private static func safeErrorMessage(from data: Data) -> String {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return "unreadable error" }
        let nested = (object["error"] as? [String: Any])?["message"] as? String
        let topLevel = object["message"] as? String
        return String((nested ?? topLevel ?? "unknown error").prefix(240))
    }

    private static func require(_ condition: @autoclosure () -> Bool, _ message: String) {
        guard condition() else { fatalError("Live writing-quality eval failed: \(message)") }
    }

    private struct EvalError: LocalizedError {
        let message: String
        init(_ message: String) { self.message = message }
        var errorDescription: String? { message }
    }
}
