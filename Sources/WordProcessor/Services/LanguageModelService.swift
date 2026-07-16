import Foundation

final class LanguageModelService: Sendable {
    private let purpose: InferencePurpose
    private let modelOverride: String?
    private let effortOverride: String?
    private let session: URLSession

    init(
        purpose: InferencePurpose = .assistant,
        model: String? = nil,
        effort: String? = "low",
        session: URLSession = LanguageModelService.makeSession()
    ) {
        self.purpose = purpose
        self.modelOverride = model
        self.effortOverride = effort
        self.session = session
    }

    var currentRuntime: InferenceRuntime {
        InferenceSettings.runtime(
            purpose: purpose,
            modelOverride: modelOverride,
            effortOverride: effortOverride
        )
    }

    // MARK: - Types

    enum StreamChunk: Sendable {
        case textBlockStart(afterNonText: Bool)
        case text(String)
        case citation(title: String, url: String)
    }

    static let ephemeralPromptCacheControl: [String: Any] = [
        "type": "ephemeral"
    ]

    static let oneHourPromptCacheControl: [String: Any] = [
        "type": "ephemeral",
        "ttl": "1h"
    ]

    // MARK: - Streaming

    func streamMessage(
        messages: [[String: Any]],
        systemPrompt: Any? = nil,
        cacheControl: [String: Any]? = nil,
        outputFormat: [String: Any]? = nil,
        temperature: Double? = nil,
        maxTokens: Int = 8192
    ) -> AsyncThrowingStream<StreamChunk, Error> {
        let runtime = currentRuntime
        return AsyncThrowingStream { continuation in
            let task = Task.detached(priority: .userInitiated) { [runtime, session] in
                guard let apiKey = APIKeyStore.shared.getAPIKey(service: runtime.apiKeyService) else {
                    continuation.finish(throwing: APIError.noAPIKey(runtime.providerName))
                    return
                }

                let sanitizedMessages = Self.sanitizedForProvider(messages, runtime: runtime)
                var requestMessages = sanitizedMessages as? [[String: Any]] ?? messages
                if runtime.apiStyle == .openAIChatCompletions,
                   let systemPrompt,
                   !Self.promptText(from: systemPrompt).isEmpty {
                    requestMessages.insert(
                        ["role": "system", "content": Self.promptText(from: systemPrompt)],
                        at: 0
                    )
                }

                var body: [String: Any] = [
                    "model": runtime.model,
                    "max_tokens": maxTokens,
                    "stream": true,
                    "messages": requestMessages
                ]

                var outputConfig: [String: Any] = [:]
                if let effort = runtime.effort {
                    outputConfig["effort"] = effort
                }
                if runtime.supportsOutputFormat, let outputFormat {
                    outputConfig["format"] = outputFormat
                }
                if !outputConfig.isEmpty {
                    body["output_config"] = outputConfig
                }
                if let temperature {
                    body["temperature"] = temperature
                }

                if runtime.apiStyle == .anthropicMessages, let systemPrompt {
                    body["system"] = Self.sanitizedForProvider(systemPrompt, runtime: runtime)
                }

                if runtime.supportsPromptCaching, let cacheControl = cacheControl {
                    body["cache_control"] = cacheControl
                }

                var attempt = 0
                let maxRetries = 3

                while true {
                    // Once any chunk has been yielded, a retry would duplicate
                    // already-delivered text, so retries only happen before that.
                    var hasYieldedChunk = false
                    do {
                        var request = URLRequest(url: runtime.messagesURL)
                        request.httpMethod = "POST"
                        request.timeoutInterval = 60
                        request.setValue("application/json", forHTTPHeaderField: "content-type")
                        switch runtime.authentication {
                        case .anthropicAPIKey:
                            request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
                            if let apiVersion = runtime.apiVersion {
                                request.setValue(apiVersion, forHTTPHeaderField: "anthropic-version")
                            }
                        case .bearerToken:
                            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "authorization")
                            request.setValue("Shakespeare", forHTTPHeaderField: "x-title")
                        }
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
                            for try await line in bytes.lines {
                                errorBody += line
                            }
                            continuation.finish(
                                throwing: APIError.httpError(
                                    runtime.providerName,
                                    httpResponse.statusCode,
                                    errorBody
                                )
                            )
                            return
                        }

                        if runtime.apiStyle == .openAIChatCompletions {
                            var seenCitationURLs = Set<String>()

                            for try await line in bytes.lines {
                                try Task.checkCancellation()
                                guard line.hasPrefix("data: ") else { continue }
                                let jsonString = String(line.dropFirst(6))
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
                                    continuation.yield(.citation(
                                        title: citation.title,
                                        url: citation.url
                                    ))
                                    hasYieldedChunk = true
                                }
                            }

                            continuation.finish()
                            return
                        }

                        var hasStartedContentBlock = false
                        var previousContentBlockWasText = false
                        var wasRefused = false

                        for try await line in bytes.lines {
                            try Task.checkCancellation()
                            guard line.hasPrefix("data: ") else { continue }
                            let jsonString = String(line.dropFirst(6))

                            guard jsonString != "[DONE]",
                                  let data = jsonString.data(using: .utf8),
                                  let event = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
                            else { continue }

                            let eventType = event["type"] as? String

                            if eventType == "content_block_start",
                               let contentBlock = event["content_block"] as? [String: Any] {
                                let blockType = contentBlock["type"] as? String
                                if blockType == "thinking" || blockType == "redacted_thinking" {
                                    // Reasoning blocks never render in the sidebar, so they
                                    // must not count toward inter-block break detection.
                                    continue
                                }
                                if blockType == "text" {
                                    continuation.yield(.textBlockStart(
                                        afterNonText: hasStartedContentBlock && !previousContentBlockWasText
                                    ))
                                    hasYieldedChunk = true
                                }
                                hasStartedContentBlock = true
                                previousContentBlockWasText = blockType == "text"
                            } else if eventType == "content_block_delta",
                                      let delta = event["delta"] as? [String: Any] {
                                let deltaType = delta["type"] as? String
                                if deltaType == "text_delta",
                                   let text = delta["text"] as? String {
                                    continuation.yield(.text(text))
                                    hasYieldedChunk = true
                                }
                            } else if eventType == "message_delta",
                                      let delta = event["delta"] as? [String: Any],
                                      delta["stop_reason"] as? String == "refusal" {
                                wasRefused = true
                            } else if eventType == "message_stop" {
                                break
                            } else if eventType == "error" {
                                let errorMsg = (event["error"] as? [String: Any])?["message"] as? String ?? "Unknown error"
                                continuation.finish(throwing: APIError.streamError(errorMsg))
                                return
                            }
                        }

                        if wasRefused {
                            continuation.finish(throwing: APIError.refused(runtime.providerName))
                        } else {
                            continuation.finish()
                        }
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

            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }

    private static func sanitizedForProvider(_ value: Any, runtime: InferenceRuntime) -> Any {
        guard !runtime.supportsPromptCaching else { return value }
        if let dictionary = value as? [String: Any] {
            return dictionary.reduce(into: [String: Any]()) { result, entry in
                guard entry.key != "cache_control" else { return }
                result[entry.key] = sanitizedForProvider(entry.value, runtime: runtime)
            }
        }
        if let array = value as? [Any] {
            return array.map { sanitizedForProvider($0, runtime: runtime) }
        }
        return value
    }

    private static func promptText(from value: Any) -> String {
        if let text = value as? String {
            return text
        }
        if let dictionary = value as? [String: Any] {
            if let text = dictionary["text"] as? String {
                return text
            }
            return dictionary.values
                .map(promptText(from:))
                .filter { !$0.isEmpty }
                .joined(separator: "\n\n")
        }
        if let array = value as? [Any] {
            return array
                .map(promptText(from:))
                .filter { !$0.isEmpty }
                .joined(separator: "\n\n")
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
                let title = normalizedCitationTitle(payload["title"] as? String, url: url)
                citations.append(ProviderCitation(title: title, url: url))
            }
        }

        if let urls = event["citations"] as? [String] {
            for candidate in urls {
                guard let url = validatedWebURL(candidate) else { continue }
                citations.append(ProviderCitation(
                    title: normalizedCitationTitle(nil, url: url),
                    url: url
                ))
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
        if let cleaned, !cleaned.isEmpty {
            return String(cleaned.prefix(120))
        }
        return URL(string: url)?.host ?? "Source"
    }

    // MARK: - Retry

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
            seconds = max(seconds, min(parsed, 30))
        }
        try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
    }

    private static func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.default
        configuration.waitsForConnectivity = false
        configuration.timeoutIntervalForRequest = 60
        configuration.timeoutIntervalForResource = 300
        return URLSession(configuration: configuration)
    }

    // MARK: - Errors

    enum APIError: LocalizedError {
        case noAPIKey(String)
        case invalidResponse
        case httpError(String, Int, String)
        case streamError(String)
        case refused(String)

        var errorDescription: String? {
            switch self {
            case .noAPIKey(let provider):
                return "No \(provider) API key found. Please set it in Settings."
            case .invalidResponse:
                return "Invalid response from API"
            case .httpError(let provider, let code, let body):
                switch code {
                case 401, 403:
                    return "\(provider) rejected the saved API key. Update it in Settings."
                case 402:
                    return "\(provider) needs credits before this request can run."
                case 429:
                    return "\(provider) is rate-limiting requests. Wait a moment and try again."
                default:
                    let detail = Self.providerMessage(from: body)
                    return detail.isEmpty
                        ? "\(provider) request failed (HTTP \(code))."
                        : "\(provider) request failed: \(detail)"
                }
            case .streamError(let msg):
                return "Stream error: \(msg)"
            case .refused(let provider):
                return "\(provider) declined this request. Try rephrasing."
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
