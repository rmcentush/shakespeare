import Foundation

final class LanguageModelService: Sendable {
    static let maximumTransportRetryCount = 1
    static let maximumFallbackModelsPerRequest = 3

    private let purpose: InferencePurpose
    private let modelOverride: String?
    private let session: URLSession
    private let apiKeyProvider: @Sendable (String) -> String?

    init(
        purpose: InferencePurpose = .assistant,
        model: String? = nil,
        session: URLSession = LanguageModelService.makeSession(),
        apiKeyProvider: @escaping @Sendable (String) -> String? = {
            APIKeyStore.shared.getAPIKey(service: $0)
        }
    ) {
        self.purpose = purpose
        self.modelOverride = model
        self.session = session
        self.apiKeyProvider = apiKeyProvider
    }

    var currentRuntime: InferenceRuntime {
        InferenceSettings.runtime(purpose: purpose, modelOverride: modelOverride)
    }

    enum StreamChunk: Sendable {
        case text(String)
        case citation(title: String, url: String)
    }

    static let ephemeralPromptCacheControl: [String: Any] = ["type": "ephemeral"]

    func streamMessage(
        messages: [[String: Any]],
        systemPrompt: Any? = nil,
        outputFormat: [String: Any]? = nil,
        temperature: Double? = nil,
        maxTokens: Int = 3_072,
        webSearchEnabled: Bool? = nil
    ) -> AsyncThrowingStream<StreamChunk, Error> {
        let runtime = currentRuntime
        return AsyncThrowingStream { continuation in
            let task = Task.detached(priority: .userInitiated) { [runtime, session, apiKeyProvider] in
                guard let apiKey = apiKeyProvider(runtime.apiKeyService) else {
                    continuation.finish(throwing: APIError.noAPIKey)
                    return
                }

                let modelBatches = Self.modelBatches(for: runtime)
                var modelBatchIndex = 0
                var transportRetryCount = 0

                while true {
                    let attemptRuntime = modelBatches[modelBatchIndex]
                    let body = Self.requestBody(
                        runtime: attemptRuntime,
                        messages: messages,
                        systemPrompt: systemPrompt,
                        outputFormat: outputFormat,
                        temperature: temperature,
                        maxTokens: maxTokens,
                        webSearchEnabled: webSearchEnabled
                    )
                    var hasYieldedChunk = false
                    do {
                        var request = URLRequest(url: attemptRuntime.messagesURL)
                        request.httpMethod = "POST"
                        request.timeoutInterval = 60
                        request.setValue("application/json", forHTTPHeaderField: "content-type")
                        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "authorization")
                        request.setValue("Shakespeare", forHTTPHeaderField: "x-title")
                        request.httpBody = try JSONSerialization.data(withJSONObject: body)

                        let (bytes, response) = try await session.bytes(for: request)
                        guard let httpResponse = response as? HTTPURLResponse else {
                            continuation.finish(throwing: APIError.invalidResponse)
                            return
                        }

                        guard httpResponse.statusCode == 200 else {
                            var errorBody = ""
                            for try await line in bytes.lines { errorBody += line }
                            if Self.canAdvanceModelBatch(
                                after: modelBatchIndex,
                                batchCount: modelBatches.count,
                                statusCode: httpResponse.statusCode
                            ) {
                                modelBatchIndex += 1
                                transportRetryCount = 0
                                continue
                            }
                            continuation.finish(throwing: APIError.httpError(httpResponse.statusCode, errorBody))
                            return
                        }

                        var seenCitationURLs = Set<String>()
                        var streamFailure: String?
                        var sawTerminalEvent = false
                        for try await line in bytes.lines {
                            try Task.checkCancellation()
                            guard line.hasPrefix("data:") else { continue }
                            let jsonString = line.dropFirst(5)
                                .trimmingCharacters(in: .whitespaces)
                            if jsonString == "[DONE]" {
                                sawTerminalEvent = true
                                break
                            }
                            guard !jsonString.isEmpty else { continue }
                            guard let data = jsonString.data(using: .utf8),
                                  let event = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
                            else {
                                streamFailure = "OpenRouter returned a malformed streaming event."
                                break
                            }

                            if let error = event["error"] as? [String: Any] {
                                streamFailure = error["message"] as? String ?? "Unknown error"
                                break
                            }

                            if let choice = (event["choices"] as? [[String: Any]])?.first,
                               let delta = choice["delta"] as? [String: Any],
                               let text = delta["content"] as? String,
                               !text.isEmpty {
                                continuation.yield(.text(text))
                                hasYieldedChunk = true
                            }
                            if let choice = (event["choices"] as? [[String: Any]])?.first,
                               choice["finish_reason"] is String {
                                sawTerminalEvent = true
                            }

                            for citation in Self.openRouterCitations(from: event)
                            where seenCitationURLs.insert(citation.url).inserted {
                                continuation.yield(.citation(title: citation.title, url: citation.url))
                                hasYieldedChunk = true
                            }
                        }

                        if let streamFailure {
                            if !hasYieldedChunk, modelBatchIndex + 1 < modelBatches.count {
                                modelBatchIndex += 1
                                transportRetryCount = 0
                                continue
                            }
                            continuation.finish(throwing: APIError.streamError(streamFailure))
                            return
                        }

                        guard sawTerminalEvent else {
                            continuation.finish(throwing: APIError.incompleteStream)
                            return
                        }

                        continuation.finish()
                        return
                    } catch is CancellationError {
                        continuation.finish(throwing: CancellationError())
                        return
                    } catch {
                        if !hasYieldedChunk,
                           transportRetryCount < Self.maximumTransportRetryCount,
                           Self.isRetryableTransportError(error) {
                            transportRetryCount += 1
                            do {
                                try await Self.backoff(attempt: transportRetryCount)
                                continue
                            } catch {
                                continuation.finish(throwing: CancellationError())
                                return
                            }
                        }
                        continuation.finish(throwing: error)
                        return
                    }
                }
            }

            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// OpenRouter caps the `models` fallback array at three entries. Preserve the
    /// user's complete ordered waterfall by splitting larger catalogs into
    /// non-overlapping batches, each with one primary and up to three fallbacks.
    static func modelBatches(for runtime: InferenceRuntime) -> [InferenceRuntime] {
        let orderedModelIDs = [runtime.model] + runtime.fallbackModels
        let batchSize = maximumFallbackModelsPerRequest + 1

        return stride(from: 0, to: orderedModelIDs.count, by: batchSize).map { start in
            let end = min(start + batchSize, orderedModelIDs.count)
            let modelIDs = Array(orderedModelIDs[start..<end])
            let primaryModel = modelIDs[0]

            return InferenceRuntime(
                providerID: runtime.providerID,
                providerName: runtime.providerName,
                messagesURL: runtime.messagesURL,
                apiKeyService: runtime.apiKeyService,
                model: primaryModel,
                fallbackModels: Array(modelIDs.dropFirst()),
                webSearchEnabled: runtime.webSearchEnabled,
                supportsTemperature: InferenceSettings.modelOption(for: primaryModel)?.supportsTemperature
                    ?? runtime.supportsTemperature
            )
        }
    }

    static func requestBody(
        runtime: InferenceRuntime,
        messages: [[String: Any]],
        systemPrompt: Any?,
        outputFormat: [String: Any]?,
        temperature: Double?,
        maxTokens: Int,
        webSearchEnabled: Bool? = nil
    ) -> [String: Any] {
        var requestMessages = messages.map { message -> [String: Any] in
            var result = message
            if let content = message["content"] {
                result["content"] = openRouterContent(from: content)
            }
            return result
        }
        if let systemPrompt, !promptText(from: systemPrompt).isEmpty {
            requestMessages.insert(
                ["role": "system", "content": openRouterContent(from: systemPrompt)],
                at: 0
            )
        }

        var provider: [String: Any] = [
            "data_collection": "deny",
            "zdr": true,
        ]
        var body: [String: Any] = [
            "model": runtime.model,
            "max_tokens": maxTokens,
            "stream": true,
            "messages": requestMessages,
        ]
        let fallbackModels = Array(
            runtime.fallbackModels.prefix(maximumFallbackModelsPerRequest)
        )
        if !fallbackModels.isEmpty {
            body["models"] = fallbackModels
        }
        if runtime.supportsTemperature, let temperature { body["temperature"] = temperature }
        if webSearchEnabled ?? runtime.webSearchEnabled {
            provider["sort"] = "throughput"
            body["reasoning"] = [
                "effort": "minimal",
                "exclude": true,
            ]
            body["verbosity"] = "low"
            body["tools"] = [[
                "type": "openrouter:web_search",
                "parameters": [
                    "engine": "parallel",
                    "max_results": 3,
                    "max_total_results": 3,
                    "max_characters": 900,
                ],
            ]]
        }

        if let outputFormat,
           outputFormat["type"] as? String == "json_schema",
           let schema = outputFormat["schema"] as? [String: Any] {
            body["response_format"] = [
                "type": "json_schema",
                "json_schema": [
                    "name": "shakespeare_response",
                    "strict": true,
                    "schema": schema,
                ],
            ]
            provider["require_parameters"] = true
        }
        body["provider"] = provider
        return body
    }

    private static func openRouterContent(from value: Any) -> Any {
        if let text = value as? String { return text }
        if let dictionary = value as? [String: Any],
           let text = dictionary["text"] as? String {
            var block: [String: Any] = ["type": "text", "text": text]
            if let cacheControl = dictionary["cache_control"] as? [String: Any] {
                block["cache_control"] = cacheControl
            }
            return block
        }
        if let array = value as? [Any] {
            return array.compactMap { item -> Any? in
                let converted = openRouterContent(from: item)
                return promptText(from: converted).isEmpty ? nil : converted
            }
        }
        return promptText(from: value)
    }

    private static func promptText(from value: Any) -> String {
        if let text = value as? String { return text }
        if let dictionary = value as? [String: Any] {
            if let text = dictionary["text"] as? String { return text }
            if let content = dictionary["content"] { return promptText(from: content) }
            return ""
        }
        if let array = value as? [Any] {
            return array.map(promptText(from:)).filter { !$0.isEmpty }.joined(separator: "\n\n")
        }
        return ""
    }

    struct ProviderCitation: Equatable {
        let title: String
        let url: String
    }

    static func openRouterCitations(from event: [String: Any]) -> [ProviderCitation] {
        var citations: [ProviderCitation] = []
        var annotationGroups: [[[String: Any]]] = []

        if let annotations = event["annotations"] as? [[String: Any]] {
            annotationGroups.append(annotations)
        }
        if let choice = (event["choices"] as? [[String: Any]])?.first {
            if let delta = choice["delta"] as? [String: Any],
               let annotations = delta["annotations"] as? [[String: Any]] {
                annotationGroups.append(annotations)
            }
            if let message = choice["message"] as? [String: Any],
               let annotations = message["annotations"] as? [[String: Any]] {
                annotationGroups.append(annotations)
            }
        }
        for annotations in annotationGroups {
            for annotation in annotations {
                let payload = annotation["url_citation"] as? [String: Any] ?? annotation
                guard let url = validatedWebURL(payload["url"] as? String) else { continue }
                citations.append(ProviderCitation(
                    title: normalizedCitationTitle(payload["title"] as? String, url: url),
                    url: url
                ))
            }
        }
        if let urls = event["citations"] as? [String] {
            for candidate in urls {
                guard let url = validatedWebURL(candidate) else { continue }
                citations.append(ProviderCitation(title: normalizedCitationTitle(nil, url: url), url: url))
            }
        }
        if let results = event["search_results"] as? [[String: Any]] {
            for result in results {
                guard let url = validatedWebURL(result["url"] as? String) else { continue }
                citations.append(ProviderCitation(
                    title: normalizedCitationTitle(result["title"] as? String, url: url),
                    url: url
                ))
            }
        }
        return citations
    }

    private static func validatedWebURL(_ candidate: String?) -> String? {
        guard let candidate,
              let url = URL(string: candidate),
              let scheme = url.scheme?.lowercased(),
              scheme == "https" || scheme == "http",
              url.host != nil
        else { return nil }
        return candidate
    }

    private static func normalizedCitationTitle(_ candidate: String?, url: String) -> String {
        let cleaned = candidate?
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "]", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if let cleaned, !cleaned.isEmpty { return String(cleaned.prefix(120)) }
        return URL(string: url)?.host ?? "Source"
    }

    private static func isRetryableTransportError(_ error: Error) -> Bool {
        guard let urlError = error as? URLError else { return false }
        switch urlError.code {
        case .timedOut, .networkConnectionLost, .notConnectedToInternet,
             .cannotConnectToHost, .cannotFindHost, .dnsLookupFailed:
            return true
        default:
            return false
        }
    }

    private static func canAdvanceModelBatch(
        after batchIndex: Int,
        batchCount: Int,
        statusCode: Int
    ) -> Bool {
        guard batchIndex + 1 < batchCount else { return false }
        switch statusCode {
        case 401, 402, 403:
            return false
        case 400...599:
            return true
        default:
            return false
        }
    }

    private static func backoff(attempt: Int) async throws {
        let seconds = min(pow(2.0, Double(attempt - 1)), 8.0) + Double.random(in: 0...0.5)
        try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
    }

    private static func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        configuration.httpCookieStorage = nil
        configuration.waitsForConnectivity = false
        configuration.timeoutIntervalForRequest = 60
        configuration.timeoutIntervalForResource = 300
        return URLSession(configuration: configuration)
    }

    enum APIError: LocalizedError {
        case noAPIKey
        case invalidResponse
        case httpError(Int, String)
        case streamError(String)
        case incompleteStream

        var errorDescription: String? {
            switch self {
            case .noAPIKey:
                return "No OpenRouter API key found. Please connect it in Settings."
            case .invalidResponse:
                return "Invalid response from OpenRouter."
            case .httpError(let code, let body):
                switch code {
                case 401, 403:
                    return "OpenRouter rejected the saved API key. Update it in Settings."
                case 402:
                    return "OpenRouter needs credits before this request can run."
                case 429:
                    return "OpenRouter is rate-limiting requests. Wait a moment and try again."
                default:
                    let detail = Self.providerMessage(from: body)
                    return detail.isEmpty
                        ? "OpenRouter request failed (HTTP \(code))."
                        : "OpenRouter request failed: \(detail)"
                }
            case .streamError(let message):
                return "OpenRouter stream error: \(message)"
            case .incompleteStream:
                return "OpenRouter ended the response before confirming completion. Partial text was not accepted as complete."
            }
        }

        private static func providerMessage(from body: String) -> String {
            guard let data = body.data(using: .utf8),
                  let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            else { return "" }
            let nested = (object["error"] as? [String: Any])?["message"] as? String
            let topLevel = object["message"] as? String
            return String((nested ?? topLevel ?? "").prefix(240))
        }
    }
}
