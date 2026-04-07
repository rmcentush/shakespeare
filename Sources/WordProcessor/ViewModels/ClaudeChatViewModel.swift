import Observation
import SwiftUI

@Observable
@MainActor
final class ClaudeChatViewModel {
    var messages: [ChatMessage] = []
    var isStreaming = false
    var streamingContentLength = 0

    @ObservationIgnored private let apiService = ClaudeAPIService()
    /// Full API conversation history (supports content blocks for tool use).
    /// Trimmed to the most recent messages when it grows too large.
    @ObservationIgnored private var apiMessages: [[String: Any]] = []
    @ObservationIgnored private var requestTask: Task<Void, Never>?
    @ObservationIgnored private var toolCallCounter = 0

    private static let maxApiMessages = 40
    private static let maxVisibleMessages = 60
    private static let maxAPIHistoryCharacters = 120_000
    private nonisolated static let maxDocumentContextCharacters = 24_000
    private static let maxToolHTMLCharacters = 20_000
    private static let maxFindQueryCharacters = 500
    private static let flushChunkThreshold = 12
    private static let flushInterval: TimeInterval = 0.12

    /// AI writing tropes guidance loaded from bundled resource.
    private static let aiTropesGuidance: String = {
        guard let resourceURL = Bundle.module.url(forResource: "ai_tropes", withExtension: "md"),
              let content = try? String(contentsOf: resourceURL, encoding: .utf8)
        else { return "" }
        return content
    }()

    deinit {
        requestTask?.cancel()
    }

    func sendMessage(_ text: String, documentContent: String = "", editorViewModel: EditorViewModel? = nil) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        cancelStreaming(markCancelledMessage: false)

        requestTask = Task { [weak self] in
            await self?.runSendMessage(trimmed, documentContent: documentContent, editorViewModel: editorViewModel)
        }
    }

    func cancelStreaming(markCancelledMessage: Bool = true) {
        requestTask?.cancel()
        requestTask = nil
        isStreaming = false

        guard markCancelledMessage,
              let lastIndex = messages.indices.last,
              messages[lastIndex].role == .assistant,
              messages[lastIndex].content.isEmpty
        else { return }

        messages[lastIndex].content = "Request cancelled."
        streamingContentLength = messages[lastIndex].content.count
    }

    private func runSendMessage(_ text: String, documentContent: String, editorViewModel: EditorViewModel?) async {
        let userMessage = ChatMessage(role: .user, content: text)
        messages.append(userMessage)
        apiMessages.append(["role": "user", "content": text])
        trimAPIHistory()

        isStreaming = true
        defer {
            isStreaming = false
            requestTask = nil
            trimVisibleMessages()
        }

        let systemPrompt = await buildSystemPrompt(documentContent: documentContent)

        // Tool use loop: keep calling API until Claude stops using tools
        var loopCount = 0
        let maxLoops = 10

        while loopCount < maxLoops {
            if Task.isCancelled {
                appendSystemMessage(content: "Request cancelled.")
                return
            }

            loopCount += 1
            let assistantMessageID = appendVisibleMessage(role: .assistant, content: "")

            var fullText = ""
            var toolCalls: [(id: String, name: String, inputJSON: String)] = []
            var flushCount = 0
            var lastFlushTime = Date.distantPast

            do {
                var allTools: [[String: Any]] = [ClaudeAPIService.webSearchTool]
                if editorViewModel != nil {
                    allTools.append(contentsOf: ClaudeAPIService.documentTools)
                }
                let tools: [[String: Any]]? = allTools
                for try await chunk in apiService.streamMessage(
                    messages: apiMessages,
                    systemPrompt: systemPrompt,
                    tools: tools,
                    cacheControl: ClaudeAPIService.ephemeralPromptCacheControl
                ) {
                    switch chunk {
                    case .text(let text):
                        fullText += text
                        flushCount += 1

                        let now = Date()
                        if flushCount >= Self.flushChunkThreshold ||
                            now.timeIntervalSince(lastFlushTime) >= Self.flushInterval {
                            updateAssistantMessage(id: assistantMessageID, content: fullText)
                            flushCount = 0
                            lastFlushTime = now
                        }
                    case .toolUse(let id, let name, let inputJSON):
                        toolCalls.append((id: id, name: name, inputJSON: inputJSON))
                    }
                }

                // Final flush of text
                updateAssistantMessage(id: assistantMessageID, content: fullText)
            } catch is CancellationError {
                if fullText.isEmpty {
                    updateAssistantMessage(id: assistantMessageID, content: "Request cancelled.")
                } else {
                    updateAssistantMessage(id: assistantMessageID, content: fullText)
                }
                return
            } catch {
                if fullText.isEmpty {
                    updateAssistantMessage(id: assistantMessageID, content: "Error: \(error.localizedDescription)")
                } else {
                    updateAssistantMessage(
                        id: assistantMessageID,
                        content: fullText + "\n\nError: \(error.localizedDescription)"
                    )
                }
                return
            }

            let hasVisibleAssistantText = !fullText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty

            // If no tool calls, we're done
            if toolCalls.isEmpty {
                if hasVisibleAssistantText {
                    apiMessages.append(["role": "assistant", "content": fullText])
                    trimAPIHistory()
                } else {
                    removeVisibleMessage(id: assistantMessageID)
                }
                break
            }

            if !hasVisibleAssistantText {
                removeVisibleMessage(id: assistantMessageID)
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
            trimAPIHistory()

            // Execute tools and build results
            var toolResultBlocks: [[String: Any]] = []
            for tc in toolCalls {
                if Task.isCancelled {
                    appendSystemMessage(content: "Request cancelled.")
                    return
                }

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

                let actionLabel = toolActionLabel(name: tc.name, inputJSON: tc.inputJSON)
                appendSystemMessage(content: actionLabel, detail: result)
            }
            apiMessages.append(["role": "user", "content": toolResultBlocks])
            trimAPIHistory()

            // Continue loop — Claude will respond to the tool results
        }

        if loopCount >= maxLoops {
            appendSystemMessage(content: "Stopped after too many tool rounds.")
        }
    }

    // MARK: - Tool Execution

    private func executeTool(name: String, inputJSON: String, editorViewModel: EditorViewModel?) async -> String {
        guard let editor = editorViewModel else {
            return "Error: editor not available"
        }
        guard editor.isEditorReady else {
            return "Editor is still loading. Ask again in a moment."
        }

        let input = parseJSON(inputJSON)
        toolCallCounter += 1
        let editId = "edit_\(toolCallCounter)"

        switch name {
        case "replace_selection":
            let html = input["html"] as? String ?? ""
            guard !html.isEmpty else {
                return "No replacement content was provided."
            }
            guard html.count <= Self.maxToolHTMLCharacters else {
                return "Suggested replacement is too large to preview safely. Narrow the request."
            }
            return await withCheckedContinuation { cont in
                editor.pendingReplaceSelection(id: editId, html: html) { count in
                    if count > 0 {
                        cont.resume(returning: "Edit suggested for selected text. User will review before applying.")
                    } else if count == ToolExecutionResult.tooManyPendingEdits.rawValue {
                        cont.resume(returning: "Too many pending edits are already queued. Review or reject them before asking for more changes.")
                    } else {
                        cont.resume(returning: "No text is currently selected. Use find_and_replace to target specific text.")
                    }
                }
            }

        case "insert_at_cursor":
            let html = input["html"] as? String ?? ""
            guard !html.isEmpty else {
                return "No insertion content was provided."
            }
            guard html.count <= Self.maxToolHTMLCharacters else {
                return "Suggested insertion is too large to preview safely. Narrow the request."
            }
            return await withCheckedContinuation { cont in
                editor.pendingInsertAtCursor(id: editId, html: html) { count in
                    if count > 0 {
                        cont.resume(returning: "Edit suggested at cursor position. User will review before applying.")
                    } else {
                        cont.resume(returning: "Too many pending edits are already queued. Review or reject them before asking for more changes.")
                    }
                }
            }

        case "find_and_replace":
            let find = input["find"] as? String ?? ""
            let replace = input["replace"] as? String ?? ""
            let replaceAll = input["replace_all"] as? Bool ?? false
            guard !find.isEmpty else {
                return "No target text was provided for find_and_replace."
            }
            guard find.count <= Self.maxFindQueryCharacters else {
                return "The target text is too long. Narrow the request to a smaller phrase."
            }
            guard replace.count <= Self.maxToolHTMLCharacters else {
                return "Suggested replacement is too large to preview safely. Narrow the request."
            }

            let resolvedTarget: ResolvedEditTarget?
            if replaceAll {
                resolvedTarget = nil
            } else {
                let documentText = await currentDocumentText(from: editor)
                switch EditTargetResolver.resolve(
                    findText: find,
                    replacementHTML: replace,
                    documentText: documentText
                ) {
                case .useOriginal:
                    resolvedTarget = nil
                case .narrowed(let target):
                    resolvedTarget = target
                case .retry(let message):
                    return message
                }
            }

            let effectiveFind = resolvedTarget?.findText ?? find
            let effectiveReplace = resolvedTarget?.replaceHTML ?? replace
            let scopeDetail = resolvedTarget?.scopeDescription

            return await withCheckedContinuation { cont in
                editor.pendingFindAndReplace(
                    id: editId,
                    find: effectiveFind,
                    replaceHTML: effectiveReplace,
                    replaceAll: replaceAll
                ) { count in
                    if count > 0 {
                        let scopeSuffix = scopeDetail.map { " \($0)" } ?? ""
                        cont.resume(returning: "Suggested \(count) edit\(count == 1 ? "" : "s"). User will review before applying.\(scopeSuffix)")
                    } else if count == ToolExecutionResult.tooManyMatches.rawValue {
                        cont.resume(returning: "That replacement matches too much of the document at once. Narrow the target text or select a smaller range.")
                    } else if count == ToolExecutionResult.tooManyPendingEdits.rawValue {
                        cont.resume(returning: "Too many pending edits are already queued. Review or reject them before asking for more changes.")
                    } else {
                        cont.resume(returning: "Text not found in document.")
                    }
                }
            }

        default:
            return "Unknown tool: \(name)"
        }
    }

    private func updateAssistantMessage(id: UUID, content: String) {
        guard let index = messages.firstIndex(where: { $0.id == id }) else { return }
        messages[index].content = content
        streamingContentLength = content.count
    }

    @discardableResult
    private func appendVisibleMessage(role: ChatMessage.Role, content: String, detail: String? = nil) -> UUID {
        let message = ChatMessage(role: role, content: content, detail: detail)
        messages.append(message)
        return message.id
    }

    private func appendSystemMessage(content: String, detail: String? = nil) {
        appendVisibleMessage(role: .system, content: content, detail: detail)
    }

    private func removeVisibleMessage(id: UUID) {
        guard let index = messages.firstIndex(where: { $0.id == id }) else { return }
        messages.remove(at: index)
    }

    private func buildSystemPrompt(documentContent: String) async -> String? {
        guard !documentContent.isEmpty else { return nil }

        let preparedDocument = await Task.detached(priority: .utility) {
            Self.prepareDocumentContext(documentContent)
        }.value

        guard !preparedDocument.isEmpty else { return nil }

        var prompt = """
        You are a writing assistant embedded in a word processor. The user is currently working on the document below. \
        Use it to understand their writing style, voice, topic, and context when responding. \
        Keep responses concise and helpful.

        You have tools to directly edit the document. When the user asks you to change, rewrite, fill in, or edit text, \
        use the appropriate tool. If the user has text selected, use replace_selection. \
        If you need to find and change specific text, use find_and_replace. \
        To add new content, use insert_at_cursor. \
        Keep edit targets as small as possible. If only one sentence or one bracketed section changes, target only that span instead of replacing a whole paragraph.

        When outputting HTML for the tools, you can use formatting tags like <b>, <i>, <u>, \
        <span style="color: #e53e3e"> (red), <span style="color: green">, etc.

        You also have web search available. Use it when the user asks about facts, references, or anything \
        that benefits from current information.

        The document may be trimmed for performance. Prefer the most recent user request if context is ambiguous.

        <current_document>
        \(preparedDocument)
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

        return prompt
    }

    private func trimVisibleMessages() {
        let excess = messages.count - Self.maxVisibleMessages
        guard excess > 0 else { return }
        messages.removeFirst(excess)
    }

    private func trimAPIHistory() {
        while apiMessages.count > Self.maxApiMessages || apiHistoryCharacterCount() > Self.maxAPIHistoryCharacters {
            apiMessages.removeFirst()
        }
    }

    private func apiHistoryCharacterCount() -> Int {
        apiMessages.reduce(into: 0) { total, message in
            total += Self.approximateSize(of: message)
        }
    }

    private static func approximateSize(of value: Any) -> Int {
        switch value {
        case let string as String:
            return string.count
        case let array as [Any]:
            return array.reduce(into: 0) { total, item in
                total += approximateSize(of: item)
            }
        case let dictionary as [String: Any]:
            return dictionary.reduce(into: 0) { total, entry in
                total += entry.key.count + approximateSize(of: entry.value)
            }
        default:
            return 8
        }
    }

    private nonisolated static func prepareDocumentContext(_ text: String) -> String {
        guard !text.isEmpty else { return "" }

        let normalized = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .replacingOccurrences(of: "\u{00a0}", with: " ")
            .replacingOccurrences(of: "[ \t]+", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "\n{3,}", with: "\n\n", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !normalized.isEmpty else { return "" }
        guard normalized.count > maxDocumentContextCharacters else { return normalized }

        let headCount = maxDocumentContextCharacters / 2
        let tailCount = maxDocumentContextCharacters - headCount
        let head = String(normalized.prefix(headCount))
        let tail = String(normalized.suffix(tailCount))

        return """
        \(head)

        [Document truncated for performance. Middle content omitted.]

        \(tail)
        """
    }

    private func toolActionLabel(name: String, inputJSON: String) -> String {
        switch name {
        case "replace_selection":
            return "Suggested edit for selection"
        case "insert_at_cursor":
            return "Suggested insertion at cursor"
        case "find_and_replace":
            let input = parseJSON(inputJSON)
            let find = input["find"] as? String ?? ""
            let truncated = find.count > 30 ? String(find.prefix(30)) + "…" : find
            return "Suggested edit for \"\(truncated)\""
        default:
            return name
        }
    }

    private func parseJSON(_ json: String) -> [String: Any] {
        guard let data = json.data(using: .utf8),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return [:] }
        return dict
    }

    private func currentDocumentText(from editor: EditorViewModel) async -> String {
        await withCheckedContinuation { continuation in
            editor.getPlainText { text in
                continuation.resume(returning: text)
            }
        }
    }
}

private enum ToolExecutionResult: Int {
    case tooManyMatches = -1
    case tooManyPendingEdits = -2
}
