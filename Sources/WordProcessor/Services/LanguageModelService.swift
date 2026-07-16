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

    var supportsServerWebSearch: Bool { currentRuntime.supportsServerWebSearch }

    // MARK: - Types

    enum StreamChunk: Sendable {
        case textBlockStart(afterNonText: Bool)
        case text(String)
        case toolUse(id: String, name: String, inputJSON: String)
    }

    static let webSearchTool: [String: Any] = [
        "type": "web_search_20260318",
        "name": "web_search",
        "max_uses": 5,
        "response_inclusion": "excluded",
    ]

    static let ephemeralPromptCacheControl: [String: Any] = [
        "type": "ephemeral"
    ]

    static let oneHourPromptCacheControl: [String: Any] = [
        "type": "ephemeral",
        "ttl": "1h"
    ]

    static let documentTools: [[String: Any]] = [
        [
            "name": "replace_selection",
            "description": "Replace the currently selected text in the document with new HTML content. Use when the user asks to modify, rewrite, edit, change, cut, or delete specific selected text. Keep the replacement scoped to only the selected text. For cuts/deletions, set html to an empty string.",
            "input_schema": [
                "type": "object",
                "properties": [
                    "html": [
                        "type": "string",
                        "description": "The HTML content to replace the selection with. Can include formatting like <b>, <i>, <u>, <span style='color: ...'>, etc. Use an empty string to suggest deleting the selection."
                    ],
                    "learning_category": [
                        "type": "string",
                        "enum": ["voice", "tone", "clarity", "structure", "concision", "style", "mechanics"],
                        "description": "Optional editorial category that best explains the change."
                    ],
                    "rationale": [
                        "type": "string",
                        "description": "A short reason for the proposed change, suitable for learning from the writer's decision."
                    ]
                ],
                "required": ["html"]
            ] as [String: Any]
        ] as [String: Any],
        [
            "name": "insert_at_cursor",
            "description": "Insert HTML content at the current cursor position in the document.",
            "input_schema": [
                "type": "object",
                "properties": [
                    "html": [
                        "type": "string",
                        "description": "The HTML content to insert at the cursor position."
                    ],
                    "learning_category": [
                        "type": "string",
                        "enum": ["voice", "tone", "clarity", "structure", "concision", "style", "mechanics"],
                        "description": "Optional editorial category that best explains the insertion."
                    ],
                    "rationale": [
                        "type": "string",
                        "description": "A short reason for the proposed insertion."
                    ]
                ],
                "required": ["html"]
            ] as [String: Any]
        ] as [String: Any],
        [
            "name": "propose_edit",
            "description": "Queue a precise, reviewable edit to existing document text. Use this instead of a loose find/replace when the user asks to revise, cut, delete, or trim text that is not the active selection. Target the smallest exact span that changes; for bracketed placeholders, target exactly the bracketed text including brackets. Prefer a block_id from <edit_context>, the exact original text, nearby prefix/suffix, and the document revision/hash from that context so the app can resolve the target deterministically. For cuts/deletions, set replacement_html to an empty string.",
            "input_schema": [
                "type": "object",
                "properties": [
                    "target": [
                        "type": "object",
                        "description": "Deterministic location metadata from <edit_context>.",
                        "properties": [
                            "block_id": [
                                "type": "string",
                                "description": "The id of the block containing the exact original text, copied from <edit_context> when available."
                            ],
                            "exact_original": [
                                "type": "string",
                                "description": "The exact current text span to replace. Keep this as small as possible; if filling [placeholder] text, include only that bracketed span."
                            ],
                            "prefix": [
                                "type": "string",
                                "description": "Short text immediately before exact_original, used only to disambiguate repeated text."
                            ],
                            "suffix": [
                                "type": "string",
                                "description": "Short text immediately after exact_original, used only to disambiguate repeated text."
                            ],
                            "occurrence_index": [
                                "type": "integer",
                                "description": "Zero-based occurrence among matches after block/prefix/suffix filtering. Omit unless needed."
                            ],
                            "document_revision": [
                                "type": "integer",
                                "description": "The document revision from <edit_context>."
                            ],
                            "document_hash": [
                                "type": "string",
                                "description": "The document hash from <edit_context>."
                            ]
                        ],
                        "required": ["exact_original"]
                    ],
                    "replacement_html": [
                        "type": "string",
                        "description": "The HTML content to replace the target with. For replacements inside an existing paragraph, use plain text or inline tags, not a full <p> wrapper. Use an empty string to suggest cutting/deleting the target text."
                    ],
                    "replace_all": [
                        "type": "boolean",
                        "description": "Only true when the user explicitly asks to replace every matching occurrence. Defaults to false."
                    ],
                    "learning_category": [
                        "type": "string",
                        "enum": ["voice", "tone", "clarity", "structure", "concision", "style", "mechanics"],
                        "description": "Optional editorial category that best explains the change."
                    ],
                    "rationale": [
                        "type": "string",
                        "description": "A short reason for the proposed change, suitable for learning from the writer's decision."
                    ]
                ],
                "required": ["target", "replacement_html"]
            ] as [String: Any]
        ] as [String: Any]
    ]

    // MARK: - Streaming

    func streamMessage(
        messages: [[String: Any]],
        systemPrompt: Any? = nil,
        tools: [[String: Any]]? = nil,
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

                var body: [String: Any] = [
                    "model": runtime.model,
                    "max_tokens": maxTokens,
                    "stream": true,
                    "messages": Self.sanitizedForProvider(messages, runtime: runtime)
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

                if let tools = tools, !tools.isEmpty {
                    body["tools"] = tools.filter { tool in
                        runtime.supportsServerWebSearch || tool["name"] as? String != "web_search"
                    }
                }

                if let systemPrompt = systemPrompt {
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
                        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
                        request.setValue(runtime.apiVersion, forHTTPHeaderField: "anthropic-version")
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
                            continuation.finish(throwing: APIError.httpError(httpResponse.statusCode, errorBody))
                            return
                        }

                        // Track tool use blocks during streaming
                        var currentToolId = ""
                        var currentToolName = ""
                        var currentToolInputJSON = ""
                        var inToolUse = false
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
                                if blockType == "tool_use" {
                                    inToolUse = true
                                    currentToolId = contentBlock["id"] as? String ?? ""
                                    currentToolName = contentBlock["name"] as? String ?? ""
                                    currentToolInputJSON = ""
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
                                } else if deltaType == "input_json_delta",
                                          let partial = delta["partial_json"] as? String {
                                    currentToolInputJSON += partial
                                }
                            } else if eventType == "content_block_stop" {
                                if inToolUse {
                                    continuation.yield(.toolUse(
                                        id: currentToolId,
                                        name: currentToolName,
                                        inputJSON: currentToolInputJSON
                                    ))
                                    hasYieldedChunk = true
                                    inToolUse = false
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
        case httpError(Int, String)
        case streamError(String)
        case refused(String)

        var errorDescription: String? {
            switch self {
            case .noAPIKey(let provider):
                return "No \(provider) API key found. Please set it in Settings."
            case .invalidResponse:
                return "Invalid response from API"
            case .httpError(let code, let body):
                return "HTTP \(code): \(body)"
            case .streamError(let msg):
                return "Stream error: \(msg)"
            case .refused(let provider):
                return "\(provider) declined this request. Try rephrasing."
            }
        }
    }
}
