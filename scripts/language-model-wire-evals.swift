import Foundation

@main
struct LanguageModelWireEvals {
    static func main() {
        extractsStandardOpenRouterAnnotations()
        extractsFlatFallbackCitations()
        rejectsUnsafeCitationURLs()
        buildsPrivateStructuredRequest()
        enablesBoundedWebSearchForChatOnly()
        validatesCuratedModelCatalog()
        configuresFullModelWaterfall()
        boundsClientRetriesAroundProviderWaterfall()
        print("Language-model wire evals passed (8 cases).")
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

    private static func configuresFullModelWaterfall() {
        let allModelIDs = InferenceSettings.availableModels.map(\.id)
        for option in InferenceSettings.availableModels {
            let selectedRuntime = InferenceSettings.runtime(
                purpose: .assistant,
                modelOverride: option.id
            )
            let expectedFallbacks = allModelIDs.filter { $0 != option.id }
            let expectedWireFallbacks = Array(
                expectedFallbacks.prefix(LanguageModelService.maximumFallbackModelCount)
            )
            precondition(selectedRuntime.model == option.id)
            precondition(selectedRuntime.fallbackModels == expectedFallbacks)
            let selectedBody = LanguageModelService.requestBody(
                runtime: selectedRuntime,
                messages: [["role": "user", "content": "Revise this paragraph."]],
                systemPrompt: nil,
                outputFormat: nil,
                temperature: 0.2,
                maxTokens: 512
            )
            precondition(selectedBody["model"] as? String == option.id)
            precondition(selectedBody["models"] as? [String] == expectedWireFallbacks)
            precondition(expectedWireFallbacks.count <= 3)
        }

        let customRuntime = InferenceSettings.runtime(
            purpose: .assistant,
            modelOverride: "example/previous-custom-model"
        )
        precondition(customRuntime.fallbackModels == allModelIDs)
    }

    private static func validatesCuratedModelCatalog() {
        let expectedIDs = [
            "moonshotai/kimi-k3",
            "x-ai/grok-4.5",
            "openai/gpt-5.6-sol",
            "anthropic/claude-fable-5",
            "anthropic/claude-opus-4.7",
            "anthropic/claude-opus-4.8",
        ]
        let options = InferenceSettings.availableModels
        precondition(options.map(\.id) == expectedIDs)
        precondition(options.map(\.name) == [
            "Kimi K3",
            "Grok 4.5",
            "GPT-5.6 Sol",
            "Claude Fable 5",
            "Claude Opus 4.7",
            "Claude Opus 4.8",
        ])
        precondition(Set(options.map(\.id)).count == options.count)
        precondition(InferenceSettings.defaultWritingModel == InferenceSettings.kimiModel)
        precondition(InferenceSettings.defaultResearchModel == InferenceSettings.kimiModel)
        precondition(InferenceSettings.normalizedModelID("~x-ai/grok-latest") == "x-ai/grok-4.5")
        precondition(
            InferenceSettings.normalizedModelID("~anthropic/claude-fable-latest")
                == "anthropic/claude-fable-5"
        )

        for option in options {
            let runtime = InferenceSettings.runtime(
                purpose: .assistant,
                modelOverride: option.id
            )
            precondition(runtime.supportsTemperature == option.supportsTemperature)
        }
    }

    private static func boundsClientRetriesAroundProviderWaterfall() {
        precondition(LanguageModelService.maximumRetryCount == 1)
        precondition(LanguageModelService.maximumRetryAfterSeconds <= 5)

        let runtime = InferenceSettings.runtime(purpose: .assistant)
        let retryRuntime = LanguageModelService.runtimeForAttempt(runtime, attempt: 1)
        let allModels = [runtime.model] + runtime.fallbackModels
        let retryStart = LanguageModelService.maximumFallbackModelCount + 1
        precondition(retryRuntime.model == allModels[retryStart])
        precondition(retryRuntime.fallbackModels == Array(allModels.dropFirst(retryStart + 1)))
        precondition(!([runtime.model] + Array(runtime.fallbackModels.prefix(3))).contains(retryRuntime.model))
    }
}
