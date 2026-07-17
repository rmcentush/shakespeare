import Foundation

@main
struct LanguageModelWireEvals {
    static func main() {
        extractsStandardOpenRouterAnnotations()
        extractsFlatFallbackCitations()
        rejectsUnsafeCitationURLs()
        buildsPrivateStructuredRequest()
        enablesBoundedWebSearchForChatOnly()
        print("Language-model wire evals passed (5 cases).")
    }

    private static func extractsStandardOpenRouterAnnotations() {
        let event: [String: Any] = [
            "choices": [[
                "delta": [
                    "annotations": [[
                        "type": "url_citation",
                        "url_citation": [
                            "url": "https://example.com/report",
                            "title": "Primary report",
                        ],
                    ]],
                ],
            ]],
        ]

        let citations = LanguageModelService.openRouterCitations(from: event)
        precondition(citations == [
            .init(title: "Primary report", url: "https://example.com/report")
        ])
    }

    private static func extractsFlatFallbackCitations() {
        let event: [String: Any] = [
            "citations": ["https://www.nasa.gov/example"],
            "search_results": [[
                "url": "https://www.noaa.gov/example",
                "title": "NOAA source",
            ]],
        ]

        let citations = LanguageModelService.openRouterCitations(from: event)
        precondition(citations.count == 2)
        precondition(citations[0].url == "https://www.nasa.gov/example")
        precondition(citations[1].title == "NOAA source")
    }

    private static func rejectsUnsafeCitationURLs() {
        let event: [String: Any] = [
            "annotations": [[
                "type": "url_citation",
                "url_citation": [
                    "url": "javascript:alert(1)",
                    "title": "Unsafe",
                ],
            ]],
        ]

        precondition(LanguageModelService.openRouterCitations(from: event).isEmpty)
    }

    private static func buildsPrivateStructuredRequest() {
        let schema: [String: Any] = [
            "type": "object",
            "properties": ["answer": ["type": "string"]],
            "required": ["answer"],
            "additionalProperties": false,
        ]
        let body = LanguageModelService.requestBody(
            runtime: InferenceSettings.runtime(purpose: .grammar),
            messages: [["role": "user", "content": "Check this sentence."]],
            systemPrompt: [["type": "text", "text": "Return JSON."]],
            outputFormat: ["type": "json_schema", "schema": schema],
            temperature: 0,
            maxTokens: 256
        )

        let provider = body["provider"] as? [String: Any]
        precondition(provider?["data_collection"] as? String == "deny")
        precondition(provider?["require_parameters"] as? Bool == true)
        precondition(body["response_format"] is [String: Any])
        let messages = body["messages"] as? [[String: Any]]
        precondition(messages?.first?["role"] as? String == "system")
        let systemBlocks = messages?.first?["content"] as? [[String: Any]]
        precondition(systemBlocks?.first?["text"] as? String == "Return JSON.")
        precondition(body["temperature"] == nil)
        precondition(body["tools"] == nil)
    }

    private static func enablesBoundedWebSearchForChatOnly() {
        let body = LanguageModelService.requestBody(
            runtime: InferenceSettings.runtime(purpose: .chat),
            messages: [["role": "user", "content": "What happened today?"]],
            systemPrompt: nil,
            outputFormat: nil,
            temperature: 0.2,
            maxTokens: 512
        )
        let tools = body["tools"] as? [[String: Any]]
        let parameters = tools?.first?["parameters"] as? [String: Any]
        precondition(tools?.first?["type"] as? String == "openrouter:web_search")
        precondition(parameters?["engine"] as? String == "parallel")
        precondition(parameters?["max_results"] as? Int == 4)
        precondition(parameters?["max_total_results"] as? Int == 8)
        precondition(parameters?["max_characters"] as? Int == 2_000)
    }
}
