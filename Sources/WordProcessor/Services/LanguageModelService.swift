import Foundation

final class LanguageModelService: Sendable {
    static let maximumRetryCount = 1
    static let maximumRetryAfterSeconds = 5.0
    static let maximumFallbackModelCount = 3

    private let purpose: InferencePurpose
    private let modelOverride: String?
    private let session: URLSession

    init(
        purpose: InferencePurpose = .assistant,
        model: String? = nil,
        session: URLSession = LanguageModelService.makeSession()
    ) {
        self.purpose = purpose
        self.modelOverride = model
        self.session = session
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
        maxTokens: Int = 3_072
    ) -> AsyncThrowingStream<StreamChunk, Error> {
        let runtime = currentRuntime
        return AsyncThrowingStream { continuation in
            let task = Task.detached(priority: .userInitiated) { [runtime, session] in
                guard let apiKey = APIKeyStore.shared.getAPIKey(service: runtime.apiKeyService) else {
                    continuation.finish(throwing: APIError.noAPIKey)
                    return
                }

                var attempt = 0
                let maxRetries = Self.maximumRetryCount

                while true {
                    var hasYieldedChunk = false
                    do {
                        let attemptRuntime = Self.runtimeForAttempt(runtime, attempt: attempt)
                        let body = Self.requestBody(
                            runtime: attemptRuntime,
                            messages: messages,
                            systemPrompt: systemPrompt,
                            outputFormat: outputFormat,
                            temperature: temperature,
                            maxTokens: maxTokens
                        )
                        var request = URLRequest(url: runtime.messagesURL)
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
                            if Self.isRetryableStatus(httpResponse.statusCode), attempt < maxRetries {
                                attempt += 1
                                try await Self.backoff(attempt: attempt, response: httpResponse)
                                continue
                            }
                            var errorBody = ""
                            for try await line in bytes.lines { errorBody += line }
                            continuation.finish(throwing: APIError.httpError(httpResponse.statusCode, errorBody))
                            return
                        }

                        var seenCitationURLs = Set<String>()
                        for try await line in bytes.lines {
                            try Task.checkCancellation()
                            guard line.hasPrefix("data:") else { continue }
                            let jsonString = line.dropFirst(5)
                                .trimmingCharacters(in: .whitespaces)
                            guard jsonString != "[DONE]",
                                  let data = jsonString.data(using: .utf8),
                                  let event = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
                            else { continue }

                            if let error = event["error"] as? [String: Any] {
                                let message = error["message"] as? String ?? "Unknown error"
                                continuation.finish(throwing: APIError.streamError(message))
                                return
                            }

                            if let choice = (event["choices"] as? [[String: Any]])?.first,
                               let delta = choice["delta"] as? [String: Any],
                               let text = delta["content"] as? String,
                               !text.isEmpty {
                                continuation.yield(.text(text))
                                hasYieldedChunk = true
                            }

                            for citation in Self.openRouterCitations(from: event)
                            where seenCitationURLs.insert(citation.url).inserted {
                                continuation.yield(.citation(title: citation.title, url: citation.url))
                                hasYieldedChunk = true
                            }
                        }

                        continuation.finish()
                        return
                    } catch is CancellationError {
                        continuation.finish(throwing: CancellationError())
                        return
                    } catch {
                        if !hasYieldedChunk, attempt < maxRetries, Self.isRetryableTransportError(error) {
                            attempt += 1
                            do {
                                try await Self.backoff(attempt: attempt, response: nil)
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

    static func requestBody(
        runtime: InferenceRuntime,
        messages: [[String: Any]],
        systemPrompt: Any?,
        outputFormat: [String: Any]?,
        temperature: Double?,
        maxTokens: Int
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

        var provider: [String: Any] = ["data_collection": "deny"]
        var body: [String: Any] = [
            "model": runtime.model,
            "max_tokens": maxTokens,
            "stream": true,
            "messages": requestMessages,
        ]
        let fallbackModels = Array(runtime.fallbackModels.prefix(maximumFallbackModelCount))
        if !fallbackModels.isEmpty {
            body["models"] = fallbackModels
        }
        if runtime.supportsTemperature, let temperature { body["temperature"] = temperature }
        if runtime.webSearchEnabled {
            body["tools"] = [[
                "type": "openrouter:web_search",
                "parameters": [
                    "engine": "parallel",
                    "max_results": 4,
                    "max_total_results": 8,
                    "max_characters": 2_000,
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

    /// Each provider request stays compact, while a retry continues with models
    /// that were not in the first request instead of paying to repeat the same
    /// waterfall. A single-model runtime still retries that model once.
    static func runtimeForAttempt(
        _ runtime: InferenceRuntime,
        attempt: Int
    ) -> InferenceRuntime {
        guard attempt > 0 else { return runtime }
        let allModels = [runtime.model] + runtime.fallbackModels
        let groupSize = maximumFallbackModelCount + 1
        let start = attempt * groupSize
        guard start < allModels.count else { return runtime }
        let group = Array(allModels.dropFirst(start).prefix(groupSize))
        guard let model = group.first else { return runtime }
        return InferenceRuntime(
            providerID: runtime.providerID,
            providerName: runtime.providerName,
            messagesURL: runtime.messagesURL,
            apiKeyService: runtime.apiKeyService,
            model: model,
            fallbackModels: Array(group.dropFirst()),
            webSearchEnabled: runtime.webSearchEnabled,
            supportsTemperature: InferenceSettings.modelOption(for: model)?.supportsTemperature
                ?? runtime.supportsTemperature
        )
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

    private static func isRetryableStatus(_ code: Int) -> Bool {
        code == 429 || code == 529 || (500...599).contains(code)
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

    private static func backoff(attempt: Int, response: HTTPURLResponse?) async throws {
        var seconds = min(pow(2.0, Double(attempt - 1)), 8.0) + Double.random(in: 0...0.5)
        if let retryAfter = response?.value(forHTTPHeaderField: "retry-after"),
           let parsed = Double(retryAfter) {
            seconds = max(seconds, min(parsed, maximumRetryAfterSeconds))
        }
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
