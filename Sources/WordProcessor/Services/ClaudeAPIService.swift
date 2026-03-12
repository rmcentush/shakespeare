import Foundation

final class ClaudeAPIService: Sendable {
    private let baseURL = "https://api.anthropic.com/v1/messages"
    private let model = "claude-opus-4-6"
    private let session: URLSession

    init(session: URLSession = ClaudeAPIService.makeSession()) {
        self.session = session
    }

    // MARK: - Types

    enum StreamChunk: Sendable {
        case text(String)
        case toolUse(id: String, name: String, inputJSON: String)
    }

    static let webSearchTool: [String: Any] = [
        "type": "web_search_20250305",
        "name": "web_search"
    ]

    static let documentTools: [[String: Any]] = [
        [
            "name": "replace_selection",
            "description": "Replace the currently selected text in the document with new HTML content. Use when the user asks to modify, rewrite, edit, or change specific selected text.",
            "input_schema": [
                "type": "object",
                "properties": [
                    "html": [
                        "type": "string",
                        "description": "The HTML content to replace the selection with. Can include formatting like <b>, <i>, <u>, <span style='color: ...'>, etc."
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
                    ]
                ],
                "required": ["html"]
            ] as [String: Any]
        ] as [String: Any],
        [
            "name": "find_and_replace",
            "description": "Find specific text in the document and replace it with new HTML content. Useful for targeted edits without needing the user to select text first.",
            "input_schema": [
                "type": "object",
                "properties": [
                    "find": [
                        "type": "string",
                        "description": "The exact text to find in the document (case-insensitive)."
                    ],
                    "replace": [
                        "type": "string",
                        "description": "The HTML content to replace it with."
                    ],
                    "replace_all": [
                        "type": "boolean",
                        "description": "Whether to replace all occurrences or just the first one. Defaults to false."
                    ]
                ],
                "required": ["find", "replace"]
            ] as [String: Any]
        ] as [String: Any]
    ]

    // MARK: - Streaming

    func streamMessage(
        messages: [[String: Any]],
        systemPrompt: String? = nil,
        tools: [[String: Any]]? = nil
    ) -> AsyncThrowingStream<StreamChunk, Error> {
        AsyncThrowingStream { continuation in
            let task = Task.detached(priority: .userInitiated) { [baseURL, model, session] in
                do {
                    guard let apiKey = KeychainService.shared.getAPIKey(service: "anthropic") else {
                        continuation.finish(throwing: APIError.noAPIKey)
                        return
                    }

                    var request = URLRequest(url: URL(string: baseURL)!)
                    request.httpMethod = "POST"
                    request.timeoutInterval = 60
                    request.setValue("application/json", forHTTPHeaderField: "content-type")
                    request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
                    request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")

                    var body: [String: Any] = [
                        "model": model,
                        "max_tokens": 4096,
                        "stream": true,
                        "messages": messages
                    ]

                    if let tools = tools, !tools.isEmpty {
                        body["tools"] = tools
                    }

                    if let systemPrompt = systemPrompt {
                        body["system"] = systemPrompt
                    }
                    request.httpBody = try JSONSerialization.data(withJSONObject: body)

                    let (bytes, response) = try await session.bytes(for: request)

                    guard let httpResponse = response as? HTTPURLResponse else {
                        continuation.finish(throwing: APIError.invalidResponse)
                        return
                    }

                    guard httpResponse.statusCode == 200 else {
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
                            if blockType == "tool_use" {
                                inToolUse = true
                                currentToolId = contentBlock["id"] as? String ?? ""
                                currentToolName = contentBlock["name"] as? String ?? ""
                                currentToolInputJSON = ""
                            }
                        } else if eventType == "content_block_delta",
                                  let delta = event["delta"] as? [String: Any] {
                            let deltaType = delta["type"] as? String
                            if deltaType == "text_delta",
                               let text = delta["text"] as? String {
                                continuation.yield(.text(text))
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
                                inToolUse = false
                            }
                        } else if eventType == "message_stop" {
                            break
                        } else if eventType == "error" {
                            let errorMsg = (event["error"] as? [String: Any])?["message"] as? String ?? "Unknown error"
                            continuation.finish(throwing: APIError.streamError(errorMsg))
                            return
                        }
                    }

                    continuation.finish()
                } catch is CancellationError {
                    continuation.finish(throwing: CancellationError())
                } catch {
                    continuation.finish(throwing: error)
                }
            }

            continuation.onTermination = { _ in
                task.cancel()
            }
        }
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
        case noAPIKey
        case invalidResponse
        case httpError(Int, String)
        case streamError(String)

        var errorDescription: String? {
            switch self {
            case .noAPIKey:
                return "No Anthropic API key found. Please set it in Settings."
            case .invalidResponse:
                return "Invalid response from API"
            case .httpError(let code, let body):
                return "HTTP \(code): \(body)"
            case .streamError(let msg):
                return "Stream error: \(msg)"
            }
        }
    }
}
