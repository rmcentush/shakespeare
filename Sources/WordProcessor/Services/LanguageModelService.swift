import Foundation

final class LanguageModelService: Sendable {
    static let maximumTransportRetryCount = 1
    static let maximumFallbackModelsPerRequest = 3
    static let maximumEmptyResponseAttempts = 3
    static let maximumRequestBodyBytes = 512 * 1_024

    private let purpose: InferencePurpose
    private let modelOverride: String?
    private let session: URLSession
    private let apiKeyProvider: @Sendable (String) -> String?
    private let promptCacheSessionID: String

    init(
        purpose: InferencePurpose = .assistant,
        model: String? = nil,
        promptCacheSessionID: String? = nil,
        session: URLSession = LanguageModelService.makeSession(),
        apiKeyProvider: @escaping @Sendable (String) -> String? = {
            APIKeyStore.shared.getAPIKey(service: $0)
        }
    ) {
        self.purpose = purpose
        self.modelOverride = model
        self.session = session
        self.apiKeyProvider = apiKeyProvider
        let requestedCacheSessionID = promptCacheSessionID?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        self.promptCacheSessionID = String(
            ((requestedCacheSessionID?.isEmpty == false ? requestedCacheSessionID : nil)
                ?? "shakespeare-\(purpose.rawValue)-\(UUID().uuidString.lowercased())")
                .prefix(256)
        )
    }

    var currentRuntime: InferenceRuntime {
        InferenceSettings.runtime(purpose: purpose, modelOverride: modelOverride)
    }

    enum StreamChunk: Sendable {
        case text(String)
        case citation(title: String, url: String)
        case cacheUsage(PromptCacheUsage)
    }

    struct PromptCacheUsage: Equatable, Sendable {
        let promptTokens: Int
        let cachedTokens: Int
        let cacheWriteTokens: Int
    }

    struct ProviderTextCandidate: Equatable {
        let text: String
        let isCumulative: Bool
    }

    static let ephemeralPromptCacheControl: [String: Any] = ["type": "ephemeral"]

    static func cacheableTextBlock(_ text: String) -> [String: Any] {
        [
            "type": "text",
            "text": text,
            "cache_control": ephemeralPromptCacheControl,
        ]
    }

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
            let task = Task.detached(priority: .userInitiated) {
                [runtime, session, apiKeyProvider, promptCacheSessionID] in
                guard let apiKey = apiKeyProvider(runtime.apiKeyService) else {
                    continuation.finish(throwing: APIError.noAPIKey)
                    return
                }

                let modelBatches = Self.modelBatches(for: runtime)
                var modelBatchIndex = 0
                var transportRetryCount = 0
                var completedEmptyResponses = 0
                var attemptRuntime = modelBatches[modelBatchIndex]

                while true {
                    let body = Self.requestBody(
                        runtime: attemptRuntime,
                        messages: messages,
                        systemPrompt: systemPrompt,
                        outputFormat: outputFormat,
                        temperature: temperature,
                        maxTokens: maxTokens,
                        webSearchEnabled: webSearchEnabled,
                        promptCacheSessionID: promptCacheSessionID
                    )
                    var hasYieldedChunk = false
                    do {
                        var request = URLRequest(url: attemptRuntime.messagesURL)
                        request.httpMethod = "POST"
                        request.timeoutInterval = 60
                        request.setValue("application/json", forHTTPHeaderField: "content-type")
                        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "authorization")
                        request.setValue("Shakespeare", forHTTPHeaderField: "x-title")
                        let requestBody = try JSONSerialization.data(withJSONObject: body)
                        guard requestBody.count <= Self.maximumRequestBodyBytes else {
                            continuation.finish(throwing: APIError.requestTooLarge)
                            return
                        }
                        request.httpBody = requestBody

                        let (bytes, response) = try await session.bytes(for: request)
                        guard let httpResponse = response as? HTTPURLResponse else {
                            continuation.finish(throwing: APIError.invalidResponse)
                            return
                        }

                        guard httpResponse.statusCode == 200 else {
                            var errorBody = ""
                            for try await line in bytes.lines {
                                let remaining = 16_000 - errorBody.count
                                guard remaining > 0 else { break }
                                errorBody += String(line.prefix(remaining))
                            }
                            if Self.canAdvanceModelBatch(
                                after: modelBatchIndex,
                                batchCount: modelBatches.count,
                                statusCode: httpResponse.statusCode
                            ) {
                                modelBatchIndex += 1
                                attemptRuntime = modelBatches[modelBatchIndex]
                                transportRetryCount = 0
                                continue
                            }
                            continuation.finish(throwing: APIError.httpError(httpResponse.statusCode, errorBody))
                            return
                        }

                        var emittedCitationURLs = Set<String>()
                        var pendingCitations: [ProviderCitation] = []
                        var streamFailure: String?
                        var sawTerminalEvent = false
                        var attemptText = ""
                        var yieldedTextCount = 0
                        var dataLines: [String] = []

                        func emitPendingContentIfUseful() {
                            let hasUsefulText = !attemptText
                                .trimmingCharacters(in: .whitespacesAndNewlines)
                                .isEmpty
                            guard hasUsefulText else { return }

                            if yieldedTextCount < attemptText.count {
                                let text = String(attemptText.dropFirst(yieldedTextCount))
                                if !text.isEmpty {
                                    continuation.yield(.text(text))
                                    hasYieldedChunk = true
                                }
                                yieldedTextCount = attemptText.count
                            }

                            for citation in pendingCitations
                            where emittedCitationURLs.insert(citation.url).inserted {
                                continuation.yield(.citation(title: citation.title, url: citation.url))
                            }
                            pendingCitations.removeAll(keepingCapacity: true)
                        }

                        func consumeEventPayload(_ payload: String) -> Bool {
                            let jsonString = payload.trimmingCharacters(in: .whitespacesAndNewlines)
                            if jsonString == "[DONE]" {
                                sawTerminalEvent = true
                                return true
                            }
                            guard !jsonString.isEmpty else { return false }
                            guard let data = jsonString.data(using: .utf8),
                                  let event = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
                            else {
                                streamFailure = "OpenRouter returned a malformed streaming event."
                                return true
                            }

                            if let error = event["error"] as? [String: Any] {
                                streamFailure = error["message"] as? String ?? "Unknown error"
                                return true
                            }

                            if let candidate = Self.openRouterTextCandidate(from: event) {
                                let fragment: String?
                                if candidate.isCumulative {
                                    if attemptText.isEmpty {
                                        fragment = candidate.text
                                    } else if candidate.text.hasPrefix(attemptText) {
                                        fragment = String(candidate.text.dropFirst(attemptText.count))
                                    } else {
                                        // A final cumulative message can repeat content already
                                        // emitted as deltas. Never duplicate it in the UI.
                                        fragment = nil
                                    }
                                } else {
                                    fragment = candidate.text
                                }
                                if let fragment, !fragment.isEmpty {
                                    let responseCharacterLimit = max(8_000, maxTokens * 8)
                                    guard attemptText.count + fragment.count
                                            <= responseCharacterLimit
                                    else {
                                        streamFailure = "OpenRouter exceeded the bounded response size."
                                        return true
                                    }
                                    attemptText += fragment
                                    emitPendingContentIfUseful()
                                }
                            }

                            let citations = Self.openRouterCitations(from: event)
                            if !citations.isEmpty {
                                pendingCitations.append(contentsOf: citations)
                                emitPendingContentIfUseful()
                            }

                            if let usage = Self.openRouterPromptCacheUsage(from: event) {
                                continuation.yield(.cacheUsage(usage))
                            }

                            if let choice = (event["choices"] as? [[String: Any]])?.first,
                               choice["finish_reason"] is String {
                                sawTerminalEvent = true
                            }
                            return false
                        }

                        var shouldStopReading = false
                        for try await line in bytes.lines {
                            try Task.checkCancellation()
                            if line.isEmpty {
                                guard !dataLines.isEmpty else { continue }
                                shouldStopReading = consumeEventPayload(dataLines.joined(separator: "\n"))
                                dataLines.removeAll(keepingCapacity: true)
                                if shouldStopReading { break }
                                continue
                            }
                            guard line.hasPrefix("data:") else { continue }
                            dataLines.append(String(line.dropFirst(5)).trimmingCharacters(in: .whitespaces))
                            let bufferedPayload = dataLines.joined(separator: "\n")
                            let bufferedData = bufferedPayload.data(using: .utf8)
                            let hasCompleteJSON = bufferedData.flatMap {
                                try? JSONSerialization.jsonObject(with: $0)
                            } != nil
                            if bufferedPayload == "[DONE]" || hasCompleteJSON {
                                shouldStopReading = consumeEventPayload(bufferedPayload)
                                dataLines.removeAll(keepingCapacity: true)
                                if shouldStopReading { break }
                            }
                        }
                        if !shouldStopReading, !dataLines.isEmpty {
                            _ = consumeEventPayload(dataLines.joined(separator: "\n"))
                        }

                        if let streamFailure {
                            if !hasYieldedChunk, modelBatchIndex + 1 < modelBatches.count {
                                modelBatchIndex += 1
                                attemptRuntime = modelBatches[modelBatchIndex]
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

                        guard !attemptText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                            completedEmptyResponses += 1
                            transportRetryCount = 0

                            if completedEmptyResponses == 1 {
                                // Empty provider completions are often transient. Give
                                // the selected model one clean retry before rerouting.
                                continue
                            }
                            if completedEmptyResponses < Self.maximumEmptyResponseAttempts,
                               modelBatchIndex + 1 < modelBatches.count {
                                modelBatchIndex += 1
                                attemptRuntime = modelBatches[modelBatchIndex]
                                continue
                            }

                            continuation.finish(throwing: APIError.emptyResponse)
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

    static func openRouterTextCandidate(from event: [String: Any]) -> ProviderTextCandidate? {
        guard let choice = (event["choices"] as? [[String: Any]])?.first else {
            if let message = event["message"] as? [String: Any],
               let text = contentText(from: message["content"]),
               !text.isEmpty {
                return ProviderTextCandidate(text: text, isCumulative: true)
            }
            return nil
        }

        if let delta = choice["delta"] as? [String: Any] {
            if let text = contentText(from: delta["content"]), !text.isEmpty {
                return ProviderTextCandidate(text: text, isCumulative: false)
            }
            if let text = delta["text"] as? String, !text.isEmpty {
                return ProviderTextCandidate(text: text, isCumulative: false)
            }
        }
        if let text = choice["text"] as? String, !text.isEmpty {
            return ProviderTextCandidate(text: text, isCumulative: false)
        }
        if let message = choice["message"] as? [String: Any],
           let text = contentText(from: message["content"]),
           !text.isEmpty {
            return ProviderTextCandidate(text: text, isCumulative: true)
        }
        return nil
    }

    static func openRouterPromptCacheUsage(
        from event: [String: Any]
    ) -> PromptCacheUsage? {
        guard let usage = event["usage"] as? [String: Any] else { return nil }
        let details = usage["prompt_tokens_details"] as? [String: Any] ?? [:]
        return PromptCacheUsage(
            promptTokens: integerValue(usage["prompt_tokens"]),
            cachedTokens: integerValue(details["cached_tokens"]),
            cacheWriteTokens: integerValue(details["cache_write_tokens"])
        )
    }

    private static func integerValue(_ value: Any?) -> Int {
        if let value = value as? Int { return value }
        if let value = value as? NSNumber { return value.intValue }
        return 0
    }

    private static func contentText(from value: Any?) -> String? {
        if let text = value as? String { return text }
        if let block = value as? [String: Any] {
            if let text = block["text"] as? String { return text }
            if let content = block["content"] { return contentText(from: content) }
            return nil
        }
        if let blocks = value as? [Any] {
            let text = blocks.compactMap(contentText(from:)).joined()
            return text.isEmpty ? nil : text
        }
        return nil
    }

    /// OpenRouter caps the `models` fallback array at three entries. Keep each
    /// server-side batch parameter-compatible: a model that needs a different
    /// reasoning or temperature request gets its own later client-side batch.
    static func modelBatches(for runtime: InferenceRuntime) -> [InferenceRuntime] {
        var remainingModelIDs = [runtime.model] + runtime.fallbackModels
        var batches: [InferenceRuntime] = []

        while let primaryModel = remainingModelIDs.first {
            let primaryCompatibility = requestCompatibility(
                for: primaryModel,
                in: runtime
            )
            var modelIDs = [primaryModel]
            var deferredModelIDs: [String] = []

            for modelID in remainingModelIDs.dropFirst() {
                if modelIDs.count <= maximumFallbackModelsPerRequest,
                   requestCompatibility(for: modelID, in: runtime) == primaryCompatibility {
                    modelIDs.append(modelID)
                } else {
                    deferredModelIDs.append(modelID)
                }
            }
            remainingModelIDs = deferredModelIDs
            batches.append(InferenceRuntime(
                providerID: runtime.providerID,
                providerName: runtime.providerName,
                messagesURL: runtime.messagesURL,
                apiKeyService: runtime.apiKeyService,
                model: primaryModel,
                fallbackModels: Array(modelIDs.dropFirst()),
                webSearchEnabled: runtime.webSearchEnabled,
                supportsTemperature: InferenceSettings.modelOption(for: primaryModel)?.supportsTemperature
                    ?? runtime.supportsTemperature
            ))
        }
        return batches
    }

    private struct RequestCompatibility: Equatable {
        let reasoningEffort: String?
        let supportsTemperature: Bool
    }

    private static func requestCompatibility(
        for modelID: String,
        in runtime: InferenceRuntime
    ) -> RequestCompatibility {
        RequestCompatibility(
            reasoningEffort: InferenceSettings.preferredReasoningEffort(for: modelID),
            supportsTemperature: InferenceSettings.modelOption(for: modelID)?.supportsTemperature
                ?? (modelID == runtime.model ? runtime.supportsTemperature : true)
        )
    }

    static func requestBody(
        runtime: InferenceRuntime,
        messages: [[String: Any]],
        systemPrompt: Any?,
        outputFormat: [String: Any]?,
        temperature: Double?,
        maxTokens: Int,
        webSearchEnabled: Bool? = nil,
        promptCacheSessionID: String? = nil
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
                ["role": "system", "content": cacheablePromptContent(from: systemPrompt)],
                at: 0
            )
        }
        markRecentUserPrefixesCacheable(in: &requestMessages)

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
        if let promptCacheSessionID {
            let normalized = promptCacheSessionID.trimmingCharacters(in: .whitespacesAndNewlines)
            if !normalized.isEmpty {
                body["session_id"] = String(normalized.prefix(256))
            }
        }
        let fallbackModels = Array(
            runtime.fallbackModels.prefix(maximumFallbackModelsPerRequest)
        )
        if !fallbackModels.isEmpty {
            body["models"] = fallbackModels
        }
        if runtime.supportsTemperature, let temperature { body["temperature"] = temperature }
        let preferredReasoningEffort = InferenceSettings.preferredReasoningEffort(
            for: runtime.model
        )
        if let reasoningEffort = preferredReasoningEffort
            ?? ((webSearchEnabled ?? runtime.webSearchEnabled) ? "minimal" : nil) {
            body["reasoning"] = [
                "effort": reasoningEffort,
                "exclude": true,
            ]
        }
        if webSearchEnabled ?? runtime.webSearchEnabled {
            provider["sort"] = "throughput"
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

    /// Keep one completed chat turn reusable and write a breakpoint for the
    /// newest turn. Single-turn features simply cache their only user prompt.
    /// Combined with the system/style breakpoints this stays within the four
    /// explicit cache points accepted by supported OpenRouter providers.
    private static func markRecentUserPrefixesCacheable(
        in messages: inout [[String: Any]]
    ) {
        var remainingBreakpoints = 2
        for index in messages.indices.reversed() where remainingBreakpoints > 0 {
            guard messages[index]["role"] as? String == "user",
                  let content = messages[index]["content"]
            else { continue }
            messages[index]["content"] = cacheablePromptContent(from: content)
            remainingBreakpoints -= 1
        }
    }

    private static func cacheablePromptContent(from value: Any) -> Any {
        let converted = openRouterContent(from: value)
        if let text = converted as? String {
            return [cacheableTextBlock(text)]
        }
        if var block = converted as? [String: Any] {
            if block["cache_control"] == nil {
                block["cache_control"] = ephemeralPromptCacheControl
            }
            return [block]
        }
        guard var blocks = converted as? [Any] else { return converted }
        for index in blocks.indices.reversed() {
            guard var block = blocks[index] as? [String: Any],
                  block["type"] as? String == "text"
            else { continue }
            if block["cache_control"] == nil {
                block["cache_control"] = ephemeralPromptCacheControl
                blocks[index] = block
            }
            break
        }
        return blocks
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
        case emptyResponse
        case requestTooLarge

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
            case .emptyResponse:
                return "OpenRouter completed the request without returning answer text."
            case .requestTooLarge:
                return "This model request is too large. Shorten the active passage and try again."
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
