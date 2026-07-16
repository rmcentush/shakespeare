import Observation
import SwiftUI

@Observable
@MainActor
final class AssistantChatViewModel {
    var messages: [ChatMessage] = []
    var isStreaming = false
    var streamingMessageID: UUID?
    var streamingContentLength = 0

    @ObservationIgnored private let apiService = LanguageModelService()
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
    private static let flushChunkThreshold = 32
    private static let flushInterval: TimeInterval = 0.25

    private static let baseSystemPrompt = """
    You are a writing assistant embedded in a word processor. Keep responses concise and helpful.

    You have tools to directly edit the document. When the user asks you to change, rewrite, fill in, or edit text, \
    use the appropriate tool. If the user has text selected, use replace_selection. \
    If you need to change existing text that is not the active selection, use propose_edit with target metadata from <edit_context>. \
    To add new content, use insert_at_cursor. \
    To suggest a cut/deletion, use replace_selection or propose_edit with an empty replacement string. \
    Keep edit targets as small as possible. If only one sentence or one bracketed section changes, target only that span instead of replacing a whole paragraph.
    When the document contains bracketed placeholders like [stat here] or [link], prefer propose_edit targeting exactly the bracketed span, including the brackets, over rewriting surrounding text.
    For sentence-level edits, pass an inline HTML fragment or plain text as the replacement; do not wrap it in <p> unless replacing multiple whole paragraphs.
    Never guess between repeated occurrences. If the target is ambiguous, include block_id, prefix/suffix, and document_revision/document_hash from <edit_context>, or ask the user to select the text.

    When outputting HTML for the tools, you can use formatting tags like <b>, <i>, <u>, \
    <span style="color: #e53e3e"> (red), <span style="color: green">, etc.

    You also have web search available. Use it when the user asks about facts, references, or anything \
    that benefits from current information.

    The document may be trimmed for performance. Prefer the most recent user request if context is ambiguous.
    """

    /// AI writing tropes guidance loaded from bundled resource.
    private static let aiTropesGuidance: String = {
        guard let resourceURL = Bundle.shakespeareResources.url(forResource: "ai_tropes", withExtension: "md"),
              let content = try? String(contentsOf: resourceURL, encoding: .utf8)
        else { return "" }
        return content
    }()

    deinit {
        requestTask?.cancel()
    }

    func sendMessage(
        _ text: String,
        quotedSelection: String? = nil,
        documentContent: String = "",
        editContext: EditorViewModel.EditContextSnapshot? = nil,
        editorViewModel: EditorViewModel? = nil
    ) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        cancelStreaming(markCancelledMessage: false)

        let selection = quotedSelection?.trimmingCharacters(in: .whitespacesAndNewlines)

        requestTask = Task { [weak self] in
            await self?.runSendMessage(
                trimmed,
                quotedSelection: (selection?.isEmpty ?? true) ? nil : selection,
                documentContent: documentContent,
                editContext: editContext,
                editorViewModel: editorViewModel
            )
        }
    }

    func cancelStreaming(markCancelledMessage: Bool = true) {
        requestTask?.cancel()
        requestTask = nil
        isStreaming = false
        streamingMessageID = nil

        guard markCancelledMessage,
              let lastIndex = messages.indices.last,
              messages[lastIndex].role == .assistant,
              messages[lastIndex].content.isEmpty
        else { return }

        messages[lastIndex].content = "Request cancelled."
        streamingContentLength = messages[lastIndex].content.count
    }

    private func runSendMessage(
        _ text: String,
        quotedSelection: String?,
        documentContent: String,
        editContext: EditorViewModel.EditContextSnapshot?,
        editorViewModel: EditorViewModel?
    ) async {
        let userMessage = ChatMessage(role: .user, content: text, quotedSelection: quotedSelection)
        messages.append(userMessage)

        var apiText = text
        if let quotedSelection {
            apiText = """
            <selected_text>
            \(quotedSelection)
            </selected_text>

            \(text)
            """
        }
        apiMessages.append(["role": "user", "content": apiText])
        trimAPIHistory()

        isStreaming = true
        defer {
            isStreaming = false
            streamingMessageID = nil
            requestTask = nil
            trimVisibleMessages()
        }

        let systemPrompt = await buildSystemPrompt(documentContent: documentContent, editContext: editContext)

        // Tool use loop: keep calling the provider until it stops using tools.
        var loopCount = 0
        let maxLoops = 10

        while loopCount < maxLoops {
            if Task.isCancelled {
                appendSystemMessage(content: "Request cancelled.")
                return
            }

            loopCount += 1
            let assistantMessageID = appendVisibleMessage(role: .assistant, content: "")
            streamingMessageID = assistantMessageID

            var fullText = ""
            var toolCalls: [(id: String, name: String, inputJSON: String)] = []
            var flushCount = 0
            var lastFlushTime = Date.distantPast

            do {
                var allTools: [[String: Any]] = [LanguageModelService.webSearchTool]
                if editorViewModel != nil {
                    allTools.append(contentsOf: LanguageModelService.documentTools)
                }
                let tools: [[String: Any]]? = allTools
                for try await chunk in apiService.streamMessage(
                    messages: apiMessages,
                    systemPrompt: systemPrompt,
                    tools: tools,
                    cacheControl: LanguageModelService.ephemeralPromptCacheControl
                ) {
                    switch chunk {
                    case .textBlockStart(let afterNonText):
                        if afterNonText {
                            fullText = Self.appendingInterBlockBreak(to: fullText)
                        }
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
                streamingMessageID = nil
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

                // Queued pending edits bump the document revision, so the
                // send-time context goes stale across multi-tool turns.
                let contextForTool = await freshEditContext(editor: editorViewModel) ?? editContext
                let result = await executeTool(
                    name: tc.name,
                    inputJSON: tc.inputJSON,
                    editContext: contextForTool,
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

            // Continue the loop so the provider can respond to the tool results.
        }

        if loopCount >= maxLoops {
            appendSystemMessage(content: "Stopped after too many tool rounds.")
        }
    }

    // MARK: - Tool Execution

    private func executeTool(
        name: String,
        inputJSON: String,
        editContext: EditorViewModel.EditContextSnapshot?,
        editorViewModel: EditorViewModel?
    ) async -> String {
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
            guard html.count <= Self.maxToolHTMLCharacters else {
                return "Suggested replacement is too large to preview safely. Narrow the request."
            }
            return await withCheckedContinuation { cont in
                editor.pendingReplaceSelection(
                    id: editId,
                    html: html,
                    target: selectionTarget(from: editContext)
                ) { count in
                    if count > 0 {
                        cont.resume(returning: "\(Self.suggestionNoun(for: html).capitalized) suggested for selected text. User will review before applying.")
                    } else if count == ToolExecutionResult.tooManyPendingEdits.rawValue {
                        cont.resume(returning: "Too many pending edits are already queued. Review or reject them before asking for more changes.")
                    } else if count == ToolExecutionResult.staleTarget.rawValue {
                        cont.resume(returning: "The selected text changed before the edit could be queued. Ask again or reselect the text.")
                    } else if count == ToolExecutionResult.invalidTarget.rawValue {
                        cont.resume(returning: "The selected range is no longer valid. Ask again or reselect the text.")
                    } else {
                        cont.resume(returning: "No text is currently selected. Use propose_edit to target specific text.")
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
                editor.pendingInsertAtCursor(
                    id: editId,
                    html: html,
                    target: insertionTarget(from: editContext)
                ) { count in
                    if count > 0 {
                        cont.resume(returning: "Edit suggested at cursor position. User will review before applying.")
                    } else if count == ToolExecutionResult.staleTarget.rawValue {
                        cont.resume(returning: "The document changed before the insertion could be queued. Ask again.")
                    } else if count == ToolExecutionResult.invalidTarget.rawValue {
                        cont.resume(returning: "The insertion position is no longer valid. Ask again.")
                    } else {
                        cont.resume(returning: "Too many pending edits are already queued. Review or reject them before asking for more changes.")
                    }
                }
            }

        case "propose_edit":
            let target = input["target"] as? [String: Any] ?? [:]
            let replacementHTML = input["replacement_html"] as? String ?? ""
            let replaceAll = input["replace_all"] as? Bool ?? false
            guard !target.isEmpty else {
                return "No target metadata was provided for propose_edit."
            }
            guard !(target["exact_original"] as? String ?? "").isEmpty else {
                return "No exact original text was provided for propose_edit."
            }
            guard replacementHTML.count <= Self.maxToolHTMLCharacters else {
                return "Suggested replacement is too large to preview safely. Narrow the request."
            }

            let count = await pendingProposeEditCount(
                editor: editor,
                id: editId,
                target: normalizedProposedTarget(target, editContext: editContext),
                replacementHTML: replacementHTML,
                replaceAll: replaceAll
            )
            let result = editToolResult(count: count, scopeDetail: nil, isDeletion: Self.isDeletionReplacement(replacementHTML))
            if count > 0,
               let note = Self.minimalityFeedback(
                original: target["exact_original"] as? String ?? "",
                replacementHTML: replacementHTML
               ) {
                return "\(result)\n\(note)"
            }
            return result

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

            let count = await pendingFindAndReplaceCount(
                editor: editor,
                id: editId,
                find: effectiveFind,
                replaceHTML: effectiveReplace,
                replaceAll: replaceAll
            )

            if count == 0, resolvedTarget != nil {
                let fallbackCount = await pendingFindAndReplaceCount(
                    editor: editor,
                    id: editId,
                    find: find,
                    replaceHTML: replace,
                    replaceAll: replaceAll
                )
                return editToolResult(count: fallbackCount, scopeDetail: nil, isDeletion: Self.isDeletionReplacement(replace))
            }

            return editToolResult(count: count, scopeDetail: scopeDetail, isDeletion: Self.isDeletionReplacement(effectiveReplace))

        default:
            return "Unknown tool: \(name)"
        }
    }

    private func updateAssistantMessage(id: UUID, content: String) {
        guard let index = messages.firstIndex(where: { $0.id == id }) else { return }
        messages[index].content = content
        streamingContentLength = content.count
    }

    private nonisolated static func appendingInterBlockBreak(to text: String) -> String {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return text }
        if text.hasSuffix("\n\n") { return text }
        if text.hasSuffix("\n") { return text + "\n" }
        if text.last?.isWhitespace == true { return text }
        return text + "\n\n"
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

    private func buildSystemPrompt(
        documentContent: String,
        editContext: EditorViewModel.EditContextSnapshot?
    ) async -> [[String: Any]] {
        let preparedDocument = await Task.detached(priority: .utility) {
            Self.prepareDocumentContext(documentContent)
        }.value

        var blocks: [[String: Any]] = [
            Self.cachedSystemBlock(Self.baseSystemPrompt)
        ]

        if !AuthorStyleReference.content.isEmpty {
            blocks.append(
                Self.cachedSystemBlock(
                    """
                    <author_voice_reference>
                    Use this fixed style reference as the high-priority guide for voice, cadence, pacing, sentence shape, paragraph movement, diction, and rhetorical habits when you draft or rewrite prose for the user.
                    This reference replaces the previous broad corpus context of the user's published writing. Follow the guidance without copying examples verbatim.

                    \(AuthorStyleReference.content)
                    </author_voice_reference>
                    """
                )
            )
        }

        if !Self.aiTropesGuidance.isEmpty {
            blocks.append(
                Self.cachedSystemBlock(
                    """
                    <writing_style_guidance>
                    When writing or editing text for the user, follow this guidance carefully:

                    \(Self.aiTropesGuidance)
                    </writing_style_guidance>
                    """
                )
            )
        }

        let learnedPreferences = AuthorStyleReference.learnedPreferences.trimmingCharacters(in: .whitespacesAndNewlines)
        if !learnedPreferences.isEmpty {
            blocks.append(
                Self.cachedSystemBlock(
                    """
                    <learned_style_preferences>
                    Rules distilled from the author's accepted/rejected edits. Where these conflict with the general voice reference, these win because they are more recent and more specific.

                    \(learnedPreferences)
                    </learned_style_preferences>
                    """
                )
            )
        }

        if !preparedDocument.isEmpty {
            blocks.append(
                Self.uncachedSystemBlock(
                    """
                    The user is currently working on the document below. Use it for topic, facts, continuity, and edit context when responding. Do not treat it as the primary voice reference; use <author_voice_reference> for style.

                    <current_document>
                    \(preparedDocument)
                    </current_document>
                    """
                )
            )
        }

        if let editContext {
            blocks.append(Self.uncachedSystemBlock(Self.editContextPrompt(editContext)))
        }

        let rejectedMemory = Self.recentRejectedSuggestionsPrompt()
        if !rejectedMemory.isEmpty {
            blocks.append(Self.uncachedSystemBlock(rejectedMemory))
        }

        return blocks
    }

    private nonisolated static func editContextPrompt(_ context: EditorViewModel.EditContextSnapshot) -> String {
        let selectionText: String
        if let selection = context.selection {
            selectionText = """
            <selection from="\(selection.from)" to="\(selection.to)" words="\(selection.words)" characters="\(selection.characters)">
            <text>\(selection.text)</text>
            <html>\(selection.html)</html>
            </selection>
            """
        } else {
            selectionText = "<selection />"
        }

        let blockLines = context.blocks.map { block in
            """
            <block id="\(block.id)" path="\(block.path)" type="\(block.type)" from="\(block.from)" to="\(block.to)" text_hash="\(block.textHash)">
            \(block.text)
            </block>
            """
        }.joined(separator: "\n")

        let placeholderLines = (context.placeholders ?? []).map { placeholder in
            """
            <placeholder block_id="\(placeholder.blockId.htmlEscaped)" from="\(placeholder.from)" to="\(placeholder.to)" text="\(placeholder.text.htmlEscaped)" />
            """
        }.joined(separator: "\n")
        let placeholdersBlock = placeholderLines.isEmpty
            ? "<placeholders />"
            : "<placeholders>\n\(placeholderLines)\n</placeholders>"

        return """
        <edit_context revision="\(context.revision)" document_hash="\(context.documentHash)" cursor_position="\(context.cursorPosition)">
        Use this context for edit tools. For propose_edit, copy document_revision/document_hash exactly, use block_id when available, and include exact_original plus short prefix/suffix if repeated text could be ambiguous.
        If <placeholders> contains a relevant bracketed placeholder, target exactly its text, including brackets.

        \(selectionText)

        <nearby_text>
        \(context.nearbyText)
        </nearby_text>

        \(placeholdersBlock)

        <block_index>
        \(blockLines)
        </block_index>
        </edit_context>
        """
    }

    private static func recentRejectedSuggestionsPrompt(limit: Int = 10) -> String {
        let rejected = StyleFeedbackStore.shared.recentRejectedDecisions(limit: limit)
        guard !rejected.isEmpty else { return "" }

        let lines = rejected.map { decision in
            """
            <rejected_suggestion source="\(decision.source.htmlEscaped)" kind="\(decision.kind.htmlEscaped)">
            <original>\(decision.originalText.htmlEscaped)</original>
            <replacement>\(decision.replacementText.htmlEscaped)</replacement>
            <context>\(decision.surroundingSentence.htmlEscaped)</context>
            </rejected_suggestion>
            """
        }.joined(separator: "\n")

        return """
        <recent_rejected_suggestions>
        The author rejected these suggestions recently. Do not re-suggest similar edits unless the user explicitly asks for them.
        \(lines)
        </recent_rejected_suggestions>
        """
    }

    private static func cachedSystemBlock(_ text: String) -> [String: Any] {
        [
            "type": "text",
            "text": text,
            "cache_control": LanguageModelService.oneHourPromptCacheControl
        ]
    }

    private static func uncachedSystemBlock(_ text: String) -> [String: Any] {
        [
            "type": "text",
            "text": text
        ]
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
            let input = parseJSON(inputJSON)
            let html = input["html"] as? String ?? ""
            return Self.isDeletionReplacement(html) ? "Suggested cut for selection" : "Suggested edit for selection"
        case "insert_at_cursor":
            return "Suggested insertion at cursor"
        case "propose_edit":
            let input = parseJSON(inputJSON)
            let target = input["target"] as? [String: Any] ?? [:]
            let original = target["exact_original"] as? String ?? ""
            let replacementHTML = input["replacement_html"] as? String ?? ""
            let action = Self.isDeletionReplacement(replacementHTML) ? "cut" : "edit"
            let truncated = original.count > 30 ? String(original.prefix(30)) + "…" : original
            return truncated.isEmpty ? "Suggested document \(action)" : "Suggested \(action) for \"\(truncated)\""
        case "find_and_replace":
            let input = parseJSON(inputJSON)
            let find = input["find"] as? String ?? ""
            let replace = input["replace"] as? String ?? ""
            let action = Self.isDeletionReplacement(replace) ? "cut" : "edit"
            let truncated = find.count > 30 ? String(find.prefix(30)) + "…" : find
            return "Suggested \(action) for \"\(truncated)\""
        default:
            return name
        }
    }

    private static func isDeletionReplacement(_ html: String) -> Bool {
        html.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private static func minimalityFeedback(original: String, replacementHTML: String) -> String? {
        guard original.count > 200 else { return nil }

        let originalWords = comparableWords(in: original)
        let replacementWords = comparableWords(in: plainTextFromHTML(replacementHTML))
        guard originalWords.count > 20, !replacementWords.isEmpty else { return nil }

        var prefixCount = 0
        while prefixCount < originalWords.count,
              prefixCount < replacementWords.count,
              originalWords[prefixCount] == replacementWords[prefixCount] {
            prefixCount += 1
        }

        var suffixCount = 0
        while suffixCount + prefixCount < originalWords.count,
              suffixCount + prefixCount < replacementWords.count,
              originalWords[originalWords.count - suffixCount - 1] == replacementWords[replacementWords.count - suffixCount - 1] {
            suffixCount += 1
        }

        let changedOriginalWords = max(0, originalWords.count - prefixCount - suffixCount)
        let changedReplacementWords = max(0, replacementWords.count - prefixCount - suffixCount)
        let changedWords = max(changedOriginalWords, changedReplacementWords)
        guard Double(changedWords) / Double(max(originalWords.count, 1)) < 0.25 else {
            return nil
        }

        return "Queued, but only \(changedWords) of your \(originalWords.count)-word target differ. Next time, target the smaller changed span directly."
    }

    private static func comparableWords(in text: String) -> [String] {
        text
            .lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
    }

    private static func plainTextFromHTML(_ html: String) -> String {
        html
            .replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func suggestionNoun(for html: String) -> String {
        isDeletionReplacement(html) ? "cut" : "edit"
    }

    private func parseJSON(_ json: String) -> [String: Any] {
        guard let data = json.data(using: .utf8),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return [:] }
        return dict
    }

    private func freshEditContext(editor: EditorViewModel?) async -> EditorViewModel.EditContextSnapshot? {
        guard let editor, editor.isEditorReady else { return nil }
        return await withCheckedContinuation { continuation in
            editor.getEditContextSnapshot { snapshot in
                continuation.resume(returning: snapshot)
            }
        }
    }

    private func currentDocumentText(from editor: EditorViewModel) async -> String {
        await withCheckedContinuation { continuation in
            editor.getPlainText { text in
                continuation.resume(returning: text)
            }
        }
    }

    private func selectionTarget(from context: EditorViewModel.EditContextSnapshot?) -> [String: Any]? {
        guard let context, let selection = context.selection else { return nil }
        return [
            "from": selection.from,
            "to": selection.to,
            "text": selection.text,
            "document_revision": context.revision,
            "document_hash": context.documentHash,
        ]
    }

    private func insertionTarget(from context: EditorViewModel.EditContextSnapshot?) -> [String: Any]? {
        guard let context else { return nil }
        return [
            "position": context.cursorPosition,
            "document_revision": context.revision,
            "document_hash": context.documentHash,
        ]
    }

    private func normalizedProposedTarget(
        _ target: [String: Any],
        editContext: EditorViewModel.EditContextSnapshot?
    ) -> [String: Any] {
        var normalized = target

        if normalized["document_revision"] == nil, let editContext {
            normalized["document_revision"] = editContext.revision
        }

        if normalized["document_hash"] == nil, let editContext {
            normalized["document_hash"] = editContext.documentHash
        }

        return normalized
    }

    private func pendingFindAndReplaceCount(
        editor: EditorViewModel,
        id: String,
        find: String,
        replaceHTML: String,
        replaceAll: Bool
    ) async -> Int {
        await withCheckedContinuation { continuation in
            editor.pendingFindAndReplace(
                id: id,
                find: find,
                replaceHTML: replaceHTML,
                replaceAll: replaceAll
            ) { count in
                continuation.resume(returning: count)
            }
        }
    }

    private func pendingProposeEditCount(
        editor: EditorViewModel,
        id: String,
        target: [String: Any],
        replacementHTML: String,
        replaceAll: Bool
    ) async -> Int {
        await withCheckedContinuation { continuation in
            editor.pendingProposeEdit(
                id: id,
                target: target,
                replacementHTML: replacementHTML,
                replaceAll: replaceAll
            ) { count in
                continuation.resume(returning: count)
            }
        }
    }

    private func editToolResult(count: Int, scopeDetail: String?, isDeletion: Bool = false) -> String {
        if count > 0 {
            let scopeSuffix = scopeDetail.map { " \($0)" } ?? ""
            let noun = isDeletion ? "cut" : "edit"
            return "Suggested \(count) \(noun)\(count == 1 ? "" : "s"). User will review before applying.\(scopeSuffix)"
        }

        if count == ToolExecutionResult.tooManyMatches.rawValue {
            return "That replacement matches too much of the document at once. Narrow the target text or select a smaller range."
        }

        if count == ToolExecutionResult.tooManyPendingEdits.rawValue {
            return "Too many pending edits are already queued. Review or reject them before asking for more changes."
        }

        if count == ToolExecutionResult.ambiguousTarget.rawValue {
            return "That edit target is ambiguous. Use a block_id plus prefix/suffix from the edit context, or ask the user to select the text."
        }

        if count == ToolExecutionResult.staleTarget.rawValue {
            return "The document changed before the edit could be queued. Ask again using the latest edit context."
        }

        if count == ToolExecutionResult.invalidTarget.rawValue {
            return "The edit target was invalid. Use a smaller exact_original span from the edit context."
        }

        return "Text not found in document."
    }
}

private enum ToolExecutionResult: Int {
    case tooManyMatches = -1
    case tooManyPendingEdits = -2
    case ambiguousTarget = -3
    case staleTarget = -4
    case invalidTarget = -5
}
