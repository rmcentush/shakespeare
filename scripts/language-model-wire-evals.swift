import Foundation

@main
struct LanguageModelWireEvals {
    static func main() async {
        extractsStandardOpenRouterAnnotations()
        extractsFlatFallbackCitations()
        rejectsUnsafeCitationURLs()
        extractsProviderTextShapes()
        buildsPrivateStructuredRequest()
        enablesBoundedWebSearchWhenRequested()
        defaultsChatToSkipWebSearch()
        validatesCuratedModelCatalog()
        configuresBoundedModelWaterfall()
        boundsClientRetriesAroundProviderWaterfall()
        await acceptsSupportedStreamingShapes()
        await retriesEmptyStreamsBeforeRerouting()
        await rejectsIncompleteMalformedAndRepeatedEmptyStreams()
        print("Language-model wire evals passed (request privacy, routing, citations, resilient SSE).")
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

    private static func extractsProviderTextShapes() {
        let blockDelta: [String: Any] = [
            "choices": [[
                "delta": [
                    "content": [
                        ["type": "text", "text": "Hello "],
                        ["type": "text", "text": "world"],
                    ],
                ],
            ]],
        ]
        precondition(
            LanguageModelService.openRouterTextCandidate(from: blockDelta)
                == .init(text: "Hello world", isCumulative: false)
        )

        let finalMessage: [String: Any] = [
            "choices": [[
                "message": ["content": "Complete answer"],
                "finish_reason": "stop",
            ]],
        ]
        precondition(
            LanguageModelService.openRouterTextCandidate(from: finalMessage)
                == .init(text: "Complete answer", isCumulative: true)
        )
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

    private static func enablesBoundedWebSearchWhenRequested() {
        let body = LanguageModelService.requestBody(
            runtime: InferenceSettings.runtime(purpose: .chat),
            messages: [["role": "user", "content": "What happened today?"]],
            systemPrompt: nil,
            outputFormat: nil,
            temperature: 0.2,
            maxTokens: 512,
            webSearchEnabled: true
        )
        let tools = body["tools"] as? [[String: Any]]
        let parameters = tools?.first?["parameters"] as? [String: Any]
        let provider = body["provider"] as? [String: Any]
        let reasoning = body["reasoning"] as? [String: Any]
        precondition(tools?.first?["type"] as? String == "openrouter:web_search")
        precondition(parameters?["engine"] as? String == "parallel")
        precondition(parameters?["max_results"] as? Int == 3)
        precondition(parameters?["max_total_results"] as? Int == 3)
        precondition(parameters?["max_characters"] as? Int == 900)
        precondition(provider?["sort"] as? String == "throughput")
        precondition(reasoning?["effort"] as? String == "minimal")
        precondition(reasoning?["exclude"] as? Bool == true)
        precondition(body["verbosity"] as? String == "low")
    }

    private static func defaultsChatToSkipWebSearch() {
        let body = LanguageModelService.requestBody(
            runtime: InferenceSettings.runtime(purpose: .chat),
            messages: [["role": "user", "content": "Tighten this paragraph."]],
            systemPrompt: nil,
            outputFormat: nil,
            temperature: 0.2,
            maxTokens: 512
        )
        let provider = body["provider"] as? [String: Any]
        precondition(body["tools"] == nil)
        precondition(body["reasoning"] == nil)
        precondition(body["verbosity"] == nil)
        precondition(provider?["sort"] == nil)
    }

    private static func configuresBoundedModelWaterfall() {
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
            precondition(
                defensivelyBoundedBody["models"] as? [String]
                    == Array(expectedFallbacks.prefix(LanguageModelService.maximumFallbackModelsPerRequest))
            )
            let batches = LanguageModelService.modelBatches(for: selectedRuntime)
            precondition(batches.count == 2)
            let routedModelIDs = batches.flatMap { [$0.model] + $0.fallbackModels }
            precondition(routedModelIDs == [option.id] + expectedFallbacks)
            precondition(Set(routedModelIDs).count == routedModelIDs.count)

            for batch in batches {
                precondition(
                    batch.fallbackModels.count
                        <= LanguageModelService.maximumFallbackModelsPerRequest
                )
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
        let maximumModelsPerBatch = LanguageModelService.maximumFallbackModelsPerRequest + 1
        let expectedBatchCount = ([customRuntime.model] + allModelIDs).count
            .quotientAndRemainder(dividingBy: maximumModelsPerBatch)
        precondition(
            customBatches.count
                == expectedBatchCount.quotient + (expectedBatchCount.remainder == 0 ? 0 : 1)
        )
    }

    private static func validatesCuratedModelCatalog() {
        let expectedIDs = [
            "moonshotai/kimi-k3",
            "google/gemini-3.5-flash",
            "anthropic/claude-haiku-4.5",
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
            "Gemini 3.5 Flash",
            "Claude Haiku 4.5",
            "Grok 4.5",
            "GPT-5.6 Sol",
            "Claude Fable 5",
            "Claude Opus 4.7",
            "Claude Opus 4.8",
        ])
        precondition(Set(options.map(\.id)).count == options.count)
        precondition(InferenceSettings.defaultWritingModel == InferenceSettings.kimiModel)
        precondition(InferenceSettings.defaultResearchModel == InferenceSettings.geminiFlashModel)
        let chatRuntime = InferenceSettings.runtime(
            purpose: .chat,
            modelOverride: InferenceSettings.defaultResearchModel
        )
        precondition(chatRuntime.model == InferenceSettings.geminiFlashModel)
        precondition(chatRuntime.fallbackModels.first == InferenceSettings.haikuModel)
        precondition(!chatRuntime.webSearchEnabled)
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
        precondition(LanguageModelService.maximumEmptyResponseAttempts == 3)
        precondition(
            LanguageModelService.modelBatches(
                for: InferenceSettings.runtime(purpose: .assistant)
            ).count == 2
        )
    }

    private static func acceptsSupportedStreamingShapes() async {
        let completed = """
        data: {"choices":[{"delta":{"content":"Hello"},"finish_reason":null}]}

        data: {"choices":[{"delta":{},"finish_reason":"stop"}]}

        data: [DONE]

        """
        do {
            let chunks = try await streamedText(from: [completed])
            precondition(chunks == "Hello")
        } catch {
            preconditionFailure("Complete SSE stream failed: \(error)")
        }

        let finalMessage = """
        data: {"choices":[{"message":{"content":[{"type":"text","text":"Final message"}]},"finish_reason":"stop"}]}

        data: [DONE]

        """
        do {
            let chunks = try await streamedText(from: [finalMessage])
            precondition(chunks == "Final message")
        } catch {
            preconditionFailure("Final-message SSE shape failed: \(error)")
        }

        let multiline = """
        data: {"choices":[{"delta":
        data: {"content":"Multi-line"},"finish_reason":"stop"}]}

        data: [DONE]

        """
        do {
            let chunks = try await streamedText(from: [multiline])
            precondition(chunks == "Multi-line")
        } catch {
            preconditionFailure("Multi-line SSE event failed: \(error)")
        }
    }

    private static func retriesEmptyStreamsBeforeRerouting() async {
        let empty = """
        data: {"choices":[{"delta":{},"finish_reason":"stop"}]}

        data: [DONE]

        """
        let recovered = """
        data: {"choices":[{"delta":{"content":"Recovered answer"},"finish_reason":"stop"}]}

        data: [DONE]

        """

        do {
            let text = try await streamedText(
                from: [empty, empty, recovered],
                purpose: .chat,
                model: InferenceSettings.geminiFlashModel
            )
            precondition(text == "Recovered answer")
            precondition(WireEvalURLProtocol.requestCount == 3)
        } catch {
            preconditionFailure("Empty-stream recovery failed: \(error)")
        }
    }

    private static func rejectsIncompleteMalformedAndRepeatedEmptyStreams() async {
        let empty = """
        data: {"choices":[{"delta":{},"finish_reason":"stop"}]}

        data: [DONE]

        """

        let incomplete = """
        data: {"choices":[{"delta":{"content":"partial"},"finish_reason":null}]}

        """
        do {
            _ = try await streamedText(from: [incomplete])
            preconditionFailure("Incomplete SSE stream was accepted")
        } catch let error as LanguageModelService.APIError {
            guard case .incompleteStream = error else {
                preconditionFailure("Unexpected incomplete-stream error: \(error)")
            }
        } catch {
            preconditionFailure("Unexpected incomplete-stream error: \(error)")
        }

        do {
            _ = try await streamedText(from: ["data: {not-json}\n\n"])
            preconditionFailure("Malformed SSE stream was accepted")
        } catch let error as LanguageModelService.APIError {
            guard case .streamError = error else {
                preconditionFailure("Unexpected malformed-stream error: \(error)")
            }
        } catch {
            preconditionFailure("Unexpected malformed-stream error: \(error)")
        }


        do {
            _ = try await streamedText(from: [empty, empty, empty])
            preconditionFailure("Repeated empty streams were accepted")
        } catch let error as LanguageModelService.APIError {
            guard case .emptyResponse = error else {
                preconditionFailure("Unexpected empty-response error: \(error)")
            }
        } catch {
            preconditionFailure("Unexpected empty-response error: \(error)")
        }
    }

    private static func streamedText(
        from eventStreams: [String],
        purpose: InferencePurpose = .assistant,
        model: String? = nil
    ) async throws -> String {
        WireEvalURLProtocol.responseBodies = eventStreams.map { Data($0.utf8) }
        WireEvalURLProtocol.requestCount = 0
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [WireEvalURLProtocol.self]
        let session = URLSession(configuration: configuration)
        let service = LanguageModelService(
            purpose: purpose,
            model: model,
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
    static var responseBodies: [Data] = []
    static var requestCount = 0

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.requestCount += 1
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "text/event-stream"]
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        let responseBody: Data
        if Self.responseBodies.count > 1 {
            responseBody = Self.responseBodies.removeFirst()
        } else {
            responseBody = Self.responseBodies.first ?? Data()
        }
        client?.urlProtocol(self, didLoad: responseBody)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
