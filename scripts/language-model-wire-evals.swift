import Foundation

@main
struct LanguageModelWireEvals {
    static func main() async {
        extractsStandardOpenRouterAnnotations()
        extractsFlatFallbackCitations()
        rejectsUnsafeCitationURLs()
        buildsPrivateStructuredRequest()
        enablesBoundedWebSearchForChatOnly()
        validatesCuratedModelCatalog()
        configuresFullServerSideModelWaterfall()
        boundsClientRetriesAroundProviderWaterfall()
        await rejectsIncompleteAndMalformedStreams()
        print("Language-model wire evals passed (request privacy, routing, citations, terminal SSE).")
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
        precondition(provider?["zdr"] as? Bool == true)
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

    private static func configuresFullServerSideModelWaterfall() {
        let allModelIDs = InferenceSettings.availableModels.map(\.id)
        for option in InferenceSettings.availableModels {
            let selectedRuntime = InferenceSettings.runtime(
                purpose: .assistant,
                modelOverride: option.id
            )
            let expectedFallbacks = allModelIDs.filter { $0 != option.id }
            precondition(selectedRuntime.model == option.id)
            precondition(selectedRuntime.fallbackModels == expectedFallbacks)
            let defensivelyBoundedBody = LanguageModelService.requestBody(
                runtime: selectedRuntime,
                messages: [["role": "user", "content": "Revise this paragraph."]],
                systemPrompt: nil,
                outputFormat: nil,
                temperature: 0.2,
                maxTokens: 512
            )
            precondition(defensivelyBoundedBody["models"] as? [String] == expectedFallbacks)
            let batches = LanguageModelService.modelBatches(for: selectedRuntime)
            precondition(batches.count == 1)
            let routedModelIDs = batches.flatMap { [$0.model] + $0.fallbackModels }
            precondition(routedModelIDs == [option.id] + expectedFallbacks)
            precondition(Set(routedModelIDs).count == routedModelIDs.count)

            for batch in batches {
                let selectedBody = LanguageModelService.requestBody(
                    runtime: batch,
                    messages: [["role": "user", "content": "Revise this paragraph."]],
                    systemPrompt: nil,
                    outputFormat: nil,
                    temperature: 0.2,
                    maxTokens: 512
                )
                precondition(selectedBody["model"] as? String == batch.model)
                precondition(selectedBody["models"] as? [String] == batch.fallbackModels)
            }
        }

        let customRuntime = InferenceSettings.runtime(
            purpose: .assistant,
            modelOverride: "example/previous-custom-model"
        )
        precondition(customRuntime.fallbackModels == allModelIDs)
        let customBatches = LanguageModelService.modelBatches(for: customRuntime)
        let customRoutedIDs = customBatches.flatMap { [$0.model] + $0.fallbackModels }
        precondition(customRoutedIDs == [customRuntime.model] + allModelIDs)
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
        precondition(LanguageModelService.maximumTransportRetryCount == 1)
        precondition(
            LanguageModelService.modelBatches(
                for: InferenceSettings.runtime(purpose: .assistant)
            ).count == 1
        )
    }

    private static func rejectsIncompleteAndMalformedStreams() async {
        let completed = """
        data: {"choices":[{"delta":{"content":"Hello"},"finish_reason":null}]}

        data: {"choices":[{"delta":{},"finish_reason":"stop"}]}

        data: [DONE]

        """
        do {
            let chunks = try await streamedText(from: completed)
            precondition(chunks == "Hello")
        } catch {
            preconditionFailure("Complete SSE stream failed: \(error)")
        }

        let incomplete = """
        data: {"choices":[{"delta":{"content":"partial"},"finish_reason":null}]}

        """
        do {
            _ = try await streamedText(from: incomplete)
            preconditionFailure("Incomplete SSE stream was accepted")
        } catch let error as LanguageModelService.APIError {
            guard case .incompleteStream = error else {
                preconditionFailure("Unexpected incomplete-stream error: \(error)")
            }
        } catch {
            preconditionFailure("Unexpected incomplete-stream error: \(error)")
        }

        do {
            _ = try await streamedText(from: "data: {not-json}\n\n")
            preconditionFailure("Malformed SSE stream was accepted")
        } catch let error as LanguageModelService.APIError {
            guard case .streamError = error else {
                preconditionFailure("Unexpected malformed-stream error: \(error)")
            }
        } catch {
            preconditionFailure("Unexpected malformed-stream error: \(error)")
        }
    }

    private static func streamedText(from eventStream: String) async throws -> String {
        WireEvalURLProtocol.responseBody = Data(eventStream.utf8)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [WireEvalURLProtocol.self]
        let session = URLSession(configuration: configuration)
        let service = LanguageModelService(
            purpose: .assistant,
            session: session,
            apiKeyProvider: { _ in "test-key" }
        )
        var text = ""
        for try await chunk in service.streamMessage(
            messages: [["role": "user", "content": "test"]],
            maxTokens: 8
        ) {
            if case .text(let chunkText) = chunk { text += chunkText }
        }
        return text
    }
}

private final class WireEvalURLProtocol: URLProtocol {
    static var responseBody = Data()

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "text/event-stream"]
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Self.responseBody)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
