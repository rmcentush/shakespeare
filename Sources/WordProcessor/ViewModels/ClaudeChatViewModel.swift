import SwiftUI

@Observable
@MainActor
final class ClaudeChatViewModel {
    var messages: [ChatMessage] = []
    var isStreaming = false
    var streamingContentLength = 0
    private let apiService = ClaudeAPIService()
    /// Full API conversation history (supports content blocks for tool use).
    /// Trimmed to the most recent messages when it grows too large.
    private var apiMessages: [[String: Any]] = []
    private static let maxApiMessages = 40

    /// AI writing tropes guidance loaded from bundled resource.
    private static let aiTropesGuidance: String = {
        guard let resourceDir = Bundle.module.url(forResource: "Resources", withExtension: nil),
              let content = try? String(contentsOf: resourceDir.appendingPathComponent("ai_tropes.md"), encoding: .utf8)
        else { return "" }
        return content
    }()

    func sendMessage(_ text: String, documentContent: String = "", editorViewModel: EditorViewModel? = nil) async {
        let userMessage = ChatMessage(role: .user, content: text)
        messages.append(userMessage)
        apiMessages.append(["role": "user", "content": text])

        let assistantMessage = ChatMessage(role: .assistant, content: "")
        messages.append(assistantMessage)
        let assistantIndex = messages.count - 1

        isStreaming = true
        defer { isStreaming = false }

        var systemPrompt: String? = nil
        if !documentContent.isEmpty {
            var prompt = """
            You are a writing assistant embedded in a word processor. The user is currently working on the document below. \
            Use it to understand their writing style, voice, topic, and context when responding. \
            Keep responses concise and helpful.

            You have tools to directly edit the document. When the user asks you to change, rewrite, fill in, or edit text, \
            use the appropriate tool. If the user has text selected, use replace_selection. \
            If you need to find and change specific text, use find_and_replace. \
            To add new content, use insert_at_cursor.

            When outputting HTML for the tools, you can use formatting tags like <b>, <i>, <u>, \
            <span style="color: #e53e3e"> (red), <span style="color: green">, etc.

            You also have web search available. Use it when the user asks about facts, references, or anything \
            that benefits from current information.

            <current_document>
            \(documentContent)
            </current_document>
            """

            if !Self.aiTropesGuidance.isEmpty {
                prompt += """

                <writing_style_guidance>
                When writing or editing text for the user, follow this guidance carefully:

                \(Self.aiTropesGuidance)
                </writing_style_guidance>
                """
            }

            systemPrompt = prompt
        }

        // Tool use loop: keep calling API until Claude stops using tools
        var loopCount = 0
        let maxLoops = 10

        while loopCount < maxLoops {
            loopCount += 1

            var fullText = ""
            var toolCalls: [(id: String, name: String, inputJSON: String)] = []
            var flushCount = 0

            do {
                var allTools: [[String: Any]] = [ClaudeAPIService.webSearchTool]
                if editorViewModel != nil {
                    allTools.append(contentsOf: ClaudeAPIService.documentTools)
                }
                let tools: [[String: Any]]? = allTools
                for try await chunk in apiService.streamMessage(
                    messages: apiMessages,
                    systemPrompt: systemPrompt,
                    tools: tools
                ) {
                    switch chunk {
                    case .text(let text):
                        fullText += text
                        flushCount += 1
                        if flushCount >= 10 {
                            messages[assistantIndex].content = fullText
                            streamingContentLength = fullText.count
                            flushCount = 0
                        }
                    case .toolUse(let id, let name, let inputJSON):
                        toolCalls.append((id: id, name: name, inputJSON: inputJSON))
                    }
                }

                // Final flush of text
                messages[assistantIndex].content = fullText
                streamingContentLength = fullText.count

            } catch {
                if messages[assistantIndex].content.isEmpty {
                    messages[assistantIndex].content = "Error: \(error.localizedDescription)"
                }
                return
            }

            // If no tool calls, we're done
            if toolCalls.isEmpty {
                // Add assistant text to API history
                apiMessages.append(["role": "assistant", "content": fullText])
                break
            }

            // Build assistant content blocks for API history
            var assistantContentBlocks: [[String: Any]] = []
            if !fullText.isEmpty {
                assistantContentBlocks.append(["type": "text", "text": fullText])
            }
            for tc in toolCalls {
                let input = parseJSON(tc.inputJSON)
                assistantContentBlocks.append([
                    "type": "tool_use",
                    "id": tc.id,
                    "name": tc.name,
                    "input": input
                ] as [String: Any])
            }
            apiMessages.append(["role": "assistant", "content": assistantContentBlocks])

            // Execute tools and build results
            var toolResultBlocks: [[String: Any]] = []
            for tc in toolCalls {
                let result = await executeTool(
                    name: tc.name,
                    inputJSON: tc.inputJSON,
                    editorViewModel: editorViewModel
                )
                toolResultBlocks.append([
                    "type": "tool_result",
                    "tool_use_id": tc.id,
                    "content": result
                ] as [String: Any])

                // Show tool action in the UI
                let actionLabel = toolActionLabel(name: tc.name, inputJSON: tc.inputJSON)
                fullText += (fullText.isEmpty ? "" : "\n\n") + actionLabel
                messages[assistantIndex].content = fullText
                streamingContentLength = fullText.count
            }
            apiMessages.append(["role": "user", "content": toolResultBlocks])

            // Continue loop — Claude will respond to the tool results
        }

        // Prevent unbounded growth: keep the most recent messages
        if apiMessages.count > Self.maxApiMessages {
            // Keep at least the last N messages; trim from the front.
            // Ensure we don't split mid-turn (assistant+tool_result must stay paired).
            let excess = apiMessages.count - Self.maxApiMessages
            apiMessages.removeFirst(excess)
        }
    }

    // MARK: - Tool Execution

    private var toolCallCounter = 0

    private func executeTool(name: String, inputJSON: String, editorViewModel: EditorViewModel?) async -> String {
        guard let editor = editorViewModel else {
            return "Error: editor not available"
        }
        let input = parseJSON(inputJSON)
        toolCallCounter += 1
        let editId = "edit_\(toolCallCounter)"

        switch name {
        case "replace_selection":
            let html = input["html"] as? String ?? ""
            return await withCheckedContinuation { cont in
                editor.pendingReplaceSelection(id: editId, html: html) { count in
                    if count > 0 {
                        cont.resume(returning: "Edit suggested for selected text. User will review before applying.")
                    } else {
                        cont.resume(returning: "No text is currently selected. Use find_and_replace to target specific text.")
                    }
                }
            }

        case "insert_at_cursor":
            let html = input["html"] as? String ?? ""
            return await withCheckedContinuation { cont in
                editor.pendingInsertAtCursor(id: editId, html: html) { count in
                    cont.resume(returning: "Edit suggested at cursor position. User will review before applying.")
                }
            }

        case "find_and_replace":
            let find = input["find"] as? String ?? ""
            let replace = input["replace"] as? String ?? ""
            let replaceAll = input["replace_all"] as? Bool ?? false
            return await withCheckedContinuation { cont in
                editor.pendingFindAndReplace(id: editId, find: find, replaceHTML: replace, replaceAll: replaceAll) { count in
                    if count > 0 {
                        cont.resume(returning: "Suggested \(count) edit\(count == 1 ? "" : "s"). User will review before applying.")
                    } else {
                        cont.resume(returning: "Text not found in document.")
                    }
                }
            }

        default:
            return "Unknown tool: \(name)"
        }
    }

    private func toolActionLabel(name: String, inputJSON: String) -> String {
        switch name {
        case "replace_selection":
            return "✎ Suggested edit for selection"
        case "insert_at_cursor":
            return "✎ Suggested insertion at cursor"
        case "find_and_replace":
            let input = parseJSON(inputJSON)
            let find = input["find"] as? String ?? ""
            let truncated = find.count > 30 ? String(find.prefix(30)) + "…" : find
            return "✎ Suggested edit for \"\(truncated)\""
        default:
            return "✎ \(name)"
        }
    }

    private func parseJSON(_ json: String) -> [String: Any] {
        guard let data = json.data(using: .utf8),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return [:] }
        return dict
    }
}
