import AppKit
import SwiftUI

struct ClaudeChatView: View {
    @State private var chatViewModel = ClaudeChatViewModel()
    @Environment(EditorViewModel.self) private var editorViewModel
    @Environment(DocumentModel.self) private var document
    @State private var inputText = ""
    @FocusState private var isInputFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            // Messages list
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(chatViewModel.messages) { message in
                            MessageBubble(
                                message: message,
                                canInsertIntoDocument: editorViewModel.isEditorReady,
                                onQuoteAssistant: appendQuotedAssistantMessage,
                                onInsertAssistant: insertAssistantMessageIntoDocument
                            )
                                .id(message.id)
                        }

                        // Invisible anchor at the bottom for auto-scrolling
                        Color.clear
                            .frame(height: 1)
                            .id("bottom")
                    }
                    .padding()
                }
                .onChange(of: chatViewModel.messages.count) {
                    scrollToBottom(proxy, animated: true)
                }
                .onChange(of: chatViewModel.streamingContentLength) {
                    scrollToBottom(proxy)
                }
            }

            Divider()

            // Input area
            HStack(spacing: 8) {
                // Send selected text as context
                Button {
                    editorViewModel.getSelectedText { text in
                        if !text.isEmpty {
                            inputText += "\n\n---\nSelected text:\n\(text)"
                        }
                    }
                } label: {
                    Image(systemName: "text.quote")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Include selected text")

                TextField("Ask Claude...", text: $inputText, axis: .vertical)
                    .textFieldStyle(.plain)
                    .lineLimit(1...5)
                    .focused($isInputFocused)
                    .onSubmit {
                        sendMessage()
                    }

                Button {
                    if chatViewModel.isStreaming {
                        chatViewModel.cancelStreaming()
                    } else {
                        sendMessage()
                    }
                } label: {
                    Image(systemName: chatViewModel.isStreaming ? "stop.circle.fill" : "arrow.up.circle.fill")
                        .font(.title2)
                        .foregroundColor(buttonColor)
                }
                .buttonStyle(.plain)
                .disabled(!chatViewModel.isStreaming && inputText.isEmpty)
            }
            .padding(10)
        }
        .frame(maxHeight: .infinity)
        .onDisappear {
            chatViewModel.cancelStreaming()
        }
    }

    private var buttonColor: Color {
        if chatViewModel.isStreaming {
            return .orange
        }
        return inputText.isEmpty ? .secondary : .accentColor
    }

    private func sendMessage() {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        inputText = ""
        let content = document.htmlContent
        let editor = editorViewModel
        chatViewModel.sendMessage(text, documentContent: content, editorViewModel: editor)
    }

    private func scrollToBottom(_ proxy: ScrollViewProxy, animated: Bool = false) {
        DispatchQueue.main.async {
            if animated {
                withAnimation(.easeOut(duration: 0.15)) {
                    proxy.scrollTo("bottom", anchor: .bottom)
                }
            } else {
                proxy.scrollTo("bottom", anchor: .bottom)
            }
        }
    }

    private func appendQuotedAssistantMessage(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let quoted = trimmed
            .components(separatedBy: "\n")
            .map { line in
                line.isEmpty ? ">" : "> \(line)"
            }
            .joined(separator: "\n")

        if inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            inputText = quoted + "\n\n"
        } else {
            inputText += "\n\n" + quoted
        }
        isInputFocused = true
    }

    private func insertAssistantMessageIntoDocument(_ text: String) {
        guard editorViewModel.isEditorReady else { return }

        let html = ClaudeMessageBlock.htmlFragment(from: text)
        guard !html.isEmpty else { return }

        editorViewModel.insertHTMLAtCursor(html)
        editorViewModel.focusEditor()
    }
}

struct MessageBubble: View {
    let message: ChatMessage
    let canInsertIntoDocument: Bool
    let onQuoteAssistant: (String) -> Void
    let onInsertAssistant: (String) -> Void

    @State private var isHovering = false
    private let maxBubbleWidth: CGFloat = 280

    var body: some View {
        switch message.role {
        case .system:
            SystemMessageRow(message: message)
                .contextMenu {
                    Button("Copy") {
                        copyMessageToPasteboard(message.combinedText)
                    }
                }
        case .user, .assistant:
            HStack {
                if message.role == .user { Spacer(minLength: 40) }

                bubbleContent
                    .padding(12)
                    .frame(maxWidth: maxBubbleWidth, alignment: .leading)
                    .background(bubbleBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(alignment: .topTrailing) {
                        if showsAssistantToolbar {
                            AssistantBubbleToolbar(
                                canInsertIntoDocument: canInsertIntoDocument,
                                onCopy: { copyMessageToPasteboard(message.combinedText) },
                                onQuote: { onQuoteAssistant(message.content) },
                                onInsert: { onInsertAssistant(message.content) }
                            )
                            .padding(.trailing, 8)
                            .offset(y: -12)
                            .transition(.opacity.combined(with: .scale(scale: 0.96, anchor: .topTrailing)))
                        }
                    }
                    .onHover { hovering in
                        guard message.role == .assistant, hasAssistantContent else { return }
                        withAnimation(.easeOut(duration: 0.12)) {
                            isHovering = hovering
                        }
                    }
                    .contextMenu {
                        Button("Copy") {
                            copyMessageToPasteboard(message.combinedText)
                        }
                    }

                if message.role == .assistant { Spacer(minLength: 40) }
            }
            .zIndex(showsAssistantToolbar ? 1 : 0)
        }
    }

    @ViewBuilder
    private var bubbleContent: some View {
        if message.role == .assistant {
            AssistantMessageContent(content: message.content)
        } else {
            Text(verbatim: message.content)
                .font(.body)
                .foregroundStyle(.primary)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var bubbleBackground: Color {
        if message.role == .user {
            return Color.accentColor.opacity(0.15)
        }
        return Color(nsColor: .controlBackgroundColor)
    }

    private var hasAssistantContent: Bool {
        !message.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var showsAssistantToolbar: Bool {
        message.role == .assistant && isHovering && hasAssistantContent
    }

    private func copyMessageToPasteboard(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }
}

private struct SystemMessageRow: View {
    let message: ChatMessage

    var body: some View {
        HStack {
            Spacer()

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Image(systemName: "square.and.pencil")
                        .font(.system(size: 11, weight: .semibold))

                    Text(message.content)
                        .font(.system(size: 12.5, weight: .semibold))
                        .fixedSize(horizontal: false, vertical: true)
                }

                if let detail = message.detail, !detail.isEmpty {
                    Text(detail)
                        .font(.system(size: 11.5))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .frame(maxWidth: 280, alignment: .leading)
            .background(Color(nsColor: .windowBackgroundColor), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .stroke(Color.primary.opacity(0.08), lineWidth: 1)
            )

            Spacer()
        }
        .textSelection(.enabled)
    }
}

private struct AssistantBubbleToolbar: View {
    let canInsertIntoDocument: Bool
    let onCopy: () -> Void
    let onQuote: () -> Void
    let onInsert: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            toolbarButton(title: "Copy", action: onCopy)
            toolbarButton(title: "Quote", action: onQuote)
            toolbarButton(title: "Insert", action: onInsert, disabled: !canInsertIntoDocument)
        }
        .padding(5)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(
            Capsule()
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.08), radius: 8, y: 3)
    }

    private func toolbarButton(title: String, action: @escaping () -> Void, disabled: Bool = false) -> some View {
        Button(title, action: action)
            .buttonStyle(.plain)
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(disabled ? .secondary : .primary)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(disabled ? Color.clear : Color.white.opacity(0.001), in: Capsule())
            .contentShape(Capsule())
            .disabled(disabled)
    }
}

private struct AssistantMessageContent: View {
    let content: String

    private var blocks: [ClaudeMessageBlock] {
        ClaudeMessageBlock.parse(content)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { entry in
                blockView(entry.element)
            }
        }
        .textSelection(.enabled)
    }

    @ViewBuilder
    private func blockView(_ block: ClaudeMessageBlock) -> some View {
        switch block {
        case .markdown(let text):
            MarkdownText(content: text)
        case .code(let language, let code):
            CodeBlockView(language: language, content: code)
        case .toolAction(let text):
            ToolActionView(text: text)
        }
    }
}

private struct MarkdownText: View {
    let content: String

    var body: some View {
        Group {
            if let attributed = renderedContent {
                Text(attributed)
            } else {
                Text(verbatim: content)
            }
        }
        .foregroundStyle(.primary)
        .fixedSize(horizontal: false, vertical: true)
        .lineSpacing(3)
    }

    private var renderedContent: AttributedString? {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return try? AttributedString(markdown: content)
    }
}

private struct CodeBlockView: View {
    let language: String?
    let content: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let language, !language.isEmpty {
                Text(language.uppercased())
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                Text(verbatim: content.isEmpty ? " " : content)
                    .font(.system(size: 12.5, design: .monospaced))
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: true, vertical: false)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(10)
        .background(Color(nsColor: .windowBackgroundColor), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

private struct ToolActionView: View {
    let text: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "square.and.pencil")
                .font(.system(size: 12, weight: .semibold))

            Text(text)
                .font(.system(size: 12.5, weight: .medium))
                .fixedSize(horizontal: false, vertical: true)
        }
        .foregroundStyle(.secondary)
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(Color.accentColor.opacity(0.08), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

private enum ClaudeMessageBlock {
    case markdown(String)
    case code(language: String?, content: String)
    case toolAction(String)

    static func parse(_ content: String) -> [ClaudeMessageBlock] {
        let normalizedContent = content.replacingOccurrences(of: "\r\n", with: "\n")
        var blocks: [ClaudeMessageBlock] = []
        var markdownLines: [String] = []
        var codeLines: [String] = []
        var codeLanguage: String?
        var isInCodeFence = false

        func flushMarkdown() {
            let markdown = markdownLines.joined(separator: "\n")
            if !markdown.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                blocks.append(.markdown(markdown))
            }
            markdownLines.removeAll(keepingCapacity: true)
        }

        func flushCode() {
            let code = codeLines.joined(separator: "\n")
            if !code.isEmpty || codeLanguage != nil {
                blocks.append(.code(language: codeLanguage, content: code))
            }
            codeLines.removeAll(keepingCapacity: true)
            codeLanguage = nil
        }

        for line in normalizedContent.components(separatedBy: "\n") {
            let trimmedLine = line.trimmingCharacters(in: .whitespaces)

            if isInCodeFence {
                if trimmedLine.hasPrefix("```") {
                    flushCode()
                    isInCodeFence = false
                } else {
                    codeLines.append(line)
                }
                continue
            }

            if trimmedLine.hasPrefix("```") {
                flushMarkdown()
                let language = trimmedLine.dropFirst(3).trimmingCharacters(in: .whitespacesAndNewlines)
                codeLanguage = language.isEmpty ? nil : String(language)
                isInCodeFence = true
                continue
            }

            if isToolActionLine(trimmedLine) {
                flushMarkdown()
                blocks.append(.toolAction(cleanToolActionLine(trimmedLine)))
                continue
            }

            markdownLines.append(line)
        }

        if isInCodeFence {
            flushCode()
        }
        flushMarkdown()

        return blocks.isEmpty ? [.markdown(content)] : blocks
    }

    private static func isToolActionLine(_ line: String) -> Bool {
        line.hasPrefix("✎ ")
    }

    private static func cleanToolActionLine(_ line: String) -> String {
        if line.hasPrefix("✎ ") {
            return String(line.dropFirst(2)).trimmingCharacters(in: .whitespaces)
        }
        return line
    }

    static func htmlFragment(from content: String) -> String {
        parse(content)
            .compactMap(\.htmlFragment)
            .filter { !$0.isEmpty }
            .joined()
    }

    private var htmlFragment: String? {
        switch self {
        case .markdown(let text):
            return Self.htmlFromMarkdownText(text)
        case .code(_, let code):
            return "<pre><code>\(Self.escapeHTML(code))</code></pre>"
        case .toolAction:
            return nil
        }
    }

    private static func htmlFromMarkdownText(_ text: String) -> String {
        let normalized = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !normalized.isEmpty else { return "" }

        let lines = normalized.components(separatedBy: "\n")
        var fragments: [String] = []
        var index = 0

        while index < lines.count {
            let line = lines[index].trimmingCharacters(in: .whitespaces)
            if line.isEmpty {
                index += 1
                continue
            }

            if let headingLevel = headingLevel(for: line) {
                let headingText = String(line.dropFirst(headingLevel)).trimmingCharacters(in: .whitespaces)
                fragments.append("<h\(headingLevel)>\(escapeHTML(headingText))</h\(headingLevel)>")
                index += 1
                continue
            }

            if let firstItem = unorderedListItem(in: line) {
                var items = ["<li>\(escapeHTML(firstItem))</li>"]
                index += 1
                while index < lines.count {
                    let candidate = lines[index].trimmingCharacters(in: .whitespaces)
                    guard let item = unorderedListItem(in: candidate) else { break }
                    items.append("<li>\(escapeHTML(item))</li>")
                    index += 1
                }
                fragments.append("<ul>\(items.joined())</ul>")
                continue
            }

            if let firstItem = orderedListItem(in: line) {
                var items = ["<li>\(escapeHTML(firstItem))</li>"]
                index += 1
                while index < lines.count {
                    let candidate = lines[index].trimmingCharacters(in: .whitespaces)
                    guard let item = orderedListItem(in: candidate) else { break }
                    items.append("<li>\(escapeHTML(item))</li>")
                    index += 1
                }
                fragments.append("<ol>\(items.joined())</ol>")
                continue
            }

            if line.hasPrefix(">") {
                var quoteLines: [String] = []
                while index < lines.count {
                    let candidate = lines[index].trimmingCharacters(in: .whitespaces)
                    guard candidate.hasPrefix(">") else { break }
                    quoteLines.append(String(candidate.dropFirst()).trimmingCharacters(in: .whitespaces))
                    index += 1
                }
                let quoteBody = quoteLines
                    .map(escapeHTML)
                    .joined(separator: "<br>")
                fragments.append("<blockquote><p>\(quoteBody)</p></blockquote>")
                continue
            }

            var paragraphLines = [line]
            index += 1
            while index < lines.count {
                let candidate = lines[index].trimmingCharacters(in: .whitespaces)
                if candidate.isEmpty {
                    index += 1
                    break
                }
                if headingLevel(for: candidate) != nil ||
                    unorderedListItem(in: candidate) != nil ||
                    orderedListItem(in: candidate) != nil ||
                    candidate.hasPrefix(">") {
                    break
                }
                paragraphLines.append(candidate)
                index += 1
            }

            fragments.append(
                "<p>\(paragraphLines.map(escapeHTML).joined(separator: "<br>"))</p>"
            )
        }

        return fragments.joined()
    }

    private static func headingLevel(for line: String) -> Int? {
        let hashes = line.prefix { $0 == "#" }.count
        guard (1...6).contains(hashes) else { return nil }
        let remainder = line.dropFirst(hashes)
        guard remainder.first == " " else { return nil }
        return hashes
    }

    private static func unorderedListItem(in line: String) -> String? {
        for marker in ["- ", "* ", "+ "] where line.hasPrefix(marker) {
            return String(line.dropFirst(marker.count)).trimmingCharacters(in: .whitespaces)
        }
        return nil
    }

    private static func orderedListItem(in line: String) -> String? {
        let digits = line.prefix { $0.isNumber }
        guard !digits.isEmpty else { return nil }

        let remainder = line.dropFirst(digits.count)
        guard let marker = remainder.first, marker == "." || marker == ")" else { return nil }

        let content = String(remainder.dropFirst()).trimmingCharacters(in: .whitespaces)
        guard !content.isEmpty else { return nil }
        return content
    }

    private static func escapeHTML(_ text: String) -> String {
        text
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&#39;")
    }
}
