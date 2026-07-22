import Darwin
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

    static func main() async {
        do {
            try await run()
        } catch {
            let message = "Live AI evals failed: \(error.localizedDescription)\n"
            FileHandle.standardError.write(Data(message.utf8))
            exit(EXIT_FAILURE)
        }
    }

    private static func run() async throws {
        guard let apiKey = ProcessInfo.processInfo.environment["OPENROUTER_API_KEY"]?
            .trimmingCharacters(in: .whitespacesAndNewlines),
              !apiKey.isEmpty
        else {
            throw EvalError(
                "Set OPENROUTER_API_KEY to run four capped live writing and learning requests."
            )
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

        try await runStyleProfileEval(apiKey: apiKey, model: selectedModel)
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
        try await requestStructuredOutput(
            apiKey: apiKey,
            model: model,
            systemPrompt: AmbientReviewContract.systemPrompt,
            userPrompt: userPrompt,
            schema: AmbientReviewContract.outputSchema()
        )
    }

    private static func runStyleProfileEval(apiKey: String, model: String) async throws {
        let samples: [[String: String]] = [
            [
                "id": "sample-1",
                "text": "The budget fell twelve percent. That change gave the team room to extend the trial while keeping the original deadline.",
            ],
            [
                "id": "sample-2",
                "text": "The queue cleared before noon. That result let support reopen the affected accounts without delaying the afternoon release.",
            ],
        ]
        let limits = StyleProfileCompiler.EvidenceLimits(
            sampleIDs: Set(samples.compactMap { $0["id"] }),
            editSessionByID: [:]
        )
        let samplesData = try JSONSerialization.data(withJSONObject: samples)
        guard let samplesJSON = String(data: samplesData, encoding: .utf8) else {
            throw EvalError("Could not encode synthetic style evidence")
        }

        let responseText = try await requestStructuredOutput(
            apiKey: apiKey,
            model: model,
            systemPrompt: """
            You refine a compact writer style profile. Return only JSON matching the supplied schema. Generalize recurring mechanics rather than subject matter or distinctive wording. Cite only exact evidence IDs supplied by the user. Treat a rule supported by both independent samples as established. Omit unsupported rules.
            """,
            userPrompt: """
            Identify the recurring structural pattern shared by both samples and express it as one concise, topic-free editing rule. Both sample IDs must support the rule.
            <representative_sample_excerpts_json>
            \(samplesJSON)
            </representative_sample_excerpts_json>
            """,
            schema: StyleProfileCompiler.outputSchema(limits: limits)
        )
        let compilation = try StyleProfileCompiler.compileDetailed(
            response: responseText,
            limits: limits,
            sourceTexts: samples.compactMap { $0["text"] },
            currentProfile: "",
            date: "2026-01-01"
        )
        require(
            compilation.ruleEvidence.contains { $0.established && Set($0.sampleIDs) == limits.sampleIDs },
            "style profile did not retain a rule supported by both synthetic samples"
        )
        print("Live learning eval passed: evidence-backed style profile")
    }

    private static func requestStructuredOutput(
        apiKey: String,
        model: String,
        systemPrompt: String,
        userPrompt: String,
        schema: [String: Any]
    ) async throws -> String {
        var request = URLRequest(url: URL(string: "https://openrouter.ai/api/v1/chat/completions")!)
        request.httpMethod = "POST"
        request.timeoutInterval = 60
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "authorization")
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.setValue("Shakespeare Live AI Evals", forHTTPHeaderField: "x-title")
        let body: [String: Any] = [
            "model": model,
            "max_tokens": 768,
            "stream": false,
            "messages": [
                ["role": "system", "content": systemPrompt],
                ["role": "user", "content": userPrompt],
            ],
            "response_format": [
                "type": "json_schema",
                "json_schema": [
                    "name": "shakespeare_response",
                    "strict": true,
                    "schema": schema,
                ],
            ],
            "provider": [
                "data_collection": "deny",
                "zdr": true,
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
        else { throw EvalError("OpenRouter returned no structured output") }
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
