import AppKit
import SwiftUI

struct AssistantChatView: View {
    @State private var chatViewModel = AssistantChatViewModel()
    @Environment(EditorViewModel.self) private var editorViewModel
    @Environment(DocumentModel.self) private var document
    @State private var inputText = ""
    @State private var pendingSelection: String?
    @State private var shouldFollowLatestMessage = true
    @State private var hasResearchConnection = false
    @FocusState private var isInputFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            // Messages list
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        if chatViewModel.messages.isEmpty {
                            AssistantEmptyState(
                                isConnected: hasResearchConnection,
                                onChoosePrompt: chooseStarterPrompt
                            )
                        }

                        ForEach(chatViewModel.messages) { message in
                            MessageBubble(
                                message: message,
                                isStreaming: chatViewModel.streamingMessageID == message.id,
                                canInsertIntoDocument: editorViewModel.isEditorReady,
                                onQuoteAssistant: appendQuotedAssistantMessage,
                                onInsertAssistant: insertAssistantMessageIntoDocument
                            )
                                .equatable()
                                .id(message.id)
                        }

                        // Invisible anchor at the bottom for auto-scrolling
                        Color.clear
                            .frame(height: 1)
                            .id("bottom")
                    }
                    .padding()
                    .background {
                        ChatScrollObserver { isNearBottom in
                            shouldFollowLatestMessage = isNearBottom
                        }
                        .frame(width: 0, height: 0)
                    }
                }
                .onChange(of: chatViewModel.messages.count) {
                    scrollToBottomIfFollowing(proxy, animated: true)
                }
                .onChange(of: chatViewModel.streamingContentLength) {
                    scrollToBottomIfFollowing(proxy)
                }
            }

            Divider()

            // Input area
            VStack(alignment: .leading, spacing: 8) {
                if let pendingSelection {
                    SelectionContextChip(text: pendingSelection) {
                        withAnimation(.easeOut(duration: 0.15)) {
                            self.pendingSelection = nil
                        }
                    }
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
                }

                if hasResearchConnection {
                    HStack(alignment: .bottom, spacing: 8) {
                        // Attach selected text as context
                        Button {
                            attachSelection()
                        } label: {
                            Image(systemName: "text.quote")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(pendingSelection == nil ? AnyShapeStyle(.secondary) : AnyShapeStyle(Color.accentColor))
                        }
                        .buttonStyle(.plain)
                        .padding(.bottom, 3)
                        .help("Attach selected text")

                        TextField("Ask about the draft or research the web…", text: smartQuotedInputText, axis: .vertical)
                            .textFieldStyle(.plain)
                            .font(AssistantChatFont.input)
                            .lineLimit(1...5)
                            .padding(.vertical, 2)
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
                                .font(.system(size: 21))
                                .foregroundColor(buttonColor)
                        }
                        .buttonStyle(.plain)
                        .disabled(!chatViewModel.isStreaming && inputText.isEmpty)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(
                        RoundedRectangle(cornerRadius: 17, style: .continuous)
                            .fill(Color(nsColor: .textBackgroundColor))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 17, style: .continuous)
                            .stroke(Color.primary.opacity(isInputFocused ? 0.16 : 0.09), lineWidth: 1)
                    )
                } else {
                    HStack(spacing: 10) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Connect OpenRouter for research chat")
                                .font(.caption.weight(.semibold))
                            Text("Writing tools and local proofreading still work without it.")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        SettingsLink {
                            Label("Connect", systemImage: "key")
                        }
                        .simultaneousGesture(TapGesture().onEnded {
                            UserDefaults.standard.set(
                                SettingsDestination.apiKeys,
                                forKey: SettingsDestination.defaultsKey
                            )
                        })
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                    }
                    .padding(.horizontal, 4)
                }
            }
            .padding(10)
        }
        .frame(maxHeight: .infinity)
        .onAppear {
            refreshConnectionStatus()
        }
        .onReceive(NotificationCenter.default.publisher(for: .openRouterConnectionChanged)) { _ in
            refreshConnectionStatus()
        }
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

    private var smartQuotedInputText: Binding<String> {
        Binding(
            get: { inputText },
            set: { inputText = SmartQuotes.smarten($0) }
        )
    }

    private func attachSelection() {
        editorViewModel.getSelectedText { text in
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return }
            withAnimation(.easeOut(duration: 0.15)) {
                pendingSelection = SmartQuotes.smarten(trimmed)
            }
            isInputFocused = true
        }
    }

    private func chooseStarterPrompt(_ prompt: String) {
        inputText = prompt
        isInputFocused = true
    }

    private func refreshConnectionStatus() {
        hasResearchConnection = APIKeyStore.shared.hasAPIKey(service: "openrouter")
    }

    private func sendMessage() {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        let selection = pendingSelection
        inputText = ""
        pendingSelection = nil
        shouldFollowLatestMessage = true
        let editor = editorViewModel

        if editor.isEditorReady {
            editor.getEditContextSnapshot { context in
                if let context {
                    chatViewModel.sendMessage(
                        text,
                        quotedSelection: selection,
                        documentContent: context.plainText
                    )
                    return
                }

                editor.getPlainText { content in
                    chatViewModel.sendMessage(
                        text,
                        quotedSelection: selection,
                        documentContent: content
                    )
                }
            }
            return
        }

        chatViewModel.sendMessage(
            text,
            quotedSelection: selection,
            documentContent: document.plainTextContent
        )
    }

    private func scrollToBottomIfFollowing(
        _ proxy: ScrollViewProxy,
        animated: Bool = false
    ) {
        guard shouldFollowLatestMessage else { return }
        DispatchQueue.main.async {
            guard shouldFollowLatestMessage else { return }

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
            inputText = SmartQuotes.smarten(quoted + "\n\n")
        } else {
            inputText = SmartQuotes.smarten(inputText + "\n\n" + quoted)
        }
        isInputFocused = true
    }

    private func insertAssistantMessageIntoDocument(_ text: String) {
        guard editorViewModel.isEditorReady else { return }

        let html = AssistantMessageBlock.htmlFragment(from: text)
        guard !html.isEmpty else { return }

        editorViewModel.insertHTMLAtCursor(html)
        editorViewModel.focusEditor()
    }
}

private struct AssistantEmptyState: View {
    let isConnected: Bool
    let onChoosePrompt: (String) -> Void

    private let prompts = [
        "Fact-check the claims in this draft and cite sources.",
        "Find current evidence that supports this argument.",
        "What important context or counterarguments am I missing?",
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            Image(systemName: "globe.americas.fill")
                .font(.system(size: 24))
                .foregroundStyle(Color.accentColor)

            VStack(alignment: .leading, spacing: 5) {
                Text("Research Chat")
                    .font(.headline)
                Text(isConnected
                    ? "Ask questions without leaving the draft. Kimi can search the live web and return source links in its answer."
                    : "Connect OpenRouter once for writing help, grammar, and fast cited web research.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if isConnected {
                VStack(alignment: .leading, spacing: 7) {
                    Text("TRY ASKING")
                        .font(.system(size: 9.5, weight: .semibold))
                        .kerning(0.7)
                        .foregroundStyle(.tertiary)

                    ForEach(prompts, id: \.self) { prompt in
                        Button {
                            onChoosePrompt(prompt)
                        } label: {
                            HStack(alignment: .firstTextBaseline, spacing: 8) {
                                Image(systemName: "arrow.up.right")
                                    .font(.caption)
                                Text(prompt)
                                    .font(.caption)
                                    .multilineTextAlignment(.leading)
                                Spacer(minLength: 0)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 8)
                        }
                        .buttonStyle(.plain)
                        .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 9))
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 6)
    }
}

private struct SelectionContextChip: View {
    let text: String
    let onRemove: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Rectangle()
                .fill(Color.accentColor.opacity(0.45))
                .frame(width: 3)
                .clipShape(Capsule())

            VStack(alignment: .leading, spacing: 2) {
                Text("SELECTION")
                    .font(.system(size: 9.5, weight: .semibold))
                    .kerning(0.6)
                    .foregroundStyle(.tertiary)

                Text(verbatim: text)
                    .font(AssistantChatFont.text(size: 12))
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 4)

            Button(action: onRemove) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 13))
                    .foregroundStyle(.tertiary)
            }
            .buttonStyle(.plain)
            .help("Remove attached selection")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        )
    }
}

private enum AssistantChatFont {
    static let input = text(size: 13.5)
    static let message = text(size: 13.5)

    static func text(size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .serif)
    }
}

private struct ChatScrollObserver: NSViewRepresentable {
    var onNearBottomChanged: (Bool) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onNearBottomChanged: onNearBottomChanged)
    }

    func makeNSView(context: Context) -> TrackingView {
        let view = TrackingView()
        view.onAttachedToHierarchy = { [weak coordinator = context.coordinator] view in
            DispatchQueue.main.async { [weak view, weak coordinator] in
                coordinator?.attach(to: view?.enclosingScrollView)
            }
        }
        return view
    }

    func updateNSView(_ nsView: TrackingView, context: Context) {
        context.coordinator.onNearBottomChanged = onNearBottomChanged

        DispatchQueue.main.async { [weak nsView, weak coordinator = context.coordinator] in
            coordinator?.attach(to: nsView?.enclosingScrollView)
        }
    }

    final class TrackingView: NSView {
        var onAttachedToHierarchy: ((TrackingView) -> Void)?

        override func viewDidMoveToSuperview() {
            super.viewDidMoveToSuperview()
            onAttachedToHierarchy?(self)
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            onAttachedToHierarchy?(self)
        }
    }

    final class Coordinator {
        private static let bottomThreshold: CGFloat = 32

        var onNearBottomChanged: (Bool) -> Void

        private weak var scrollView: NSScrollView?
        private var boundsObserver: NSObjectProtocol?
        private var lastReportedNearBottom: Bool?

        init(onNearBottomChanged: @escaping (Bool) -> Void) {
            self.onNearBottomChanged = onNearBottomChanged
        }

        deinit {
            detach()
        }

        func attach(to scrollView: NSScrollView?) {
            guard self.scrollView !== scrollView else { return }

            detach()

            guard let scrollView else { return }
            self.scrollView = scrollView

            scrollView.contentView.postsBoundsChangedNotifications = true
            boundsObserver = NotificationCenter.default.addObserver(
                forName: NSView.boundsDidChangeNotification,
                object: scrollView.contentView,
                queue: .main
            ) { [weak self] _ in
                self?.reportNearBottomIfNeeded()
            }

            reportNearBottomIfNeeded(force: true)
        }

        private func detach() {
            if let boundsObserver {
                NotificationCenter.default.removeObserver(boundsObserver)
            }

            boundsObserver = nil
            scrollView = nil
            lastReportedNearBottom = nil
        }

        private func reportNearBottomIfNeeded(
            force: Bool = false
        ) {
            let isNearBottom = self.isNearBottom()
            guard force || lastReportedNearBottom != isNearBottom else { return }

            lastReportedNearBottom = isNearBottom
            onNearBottomChanged(isNearBottom)
        }

        private func isNearBottom() -> Bool {
            guard let scrollView,
                  let documentView = scrollView.documentView
            else { return true }

            let visibleRect = scrollView.contentView.documentVisibleRect
            let documentBounds = documentView.bounds

            guard documentBounds.height > visibleRect.height else { return true }

            let distanceToBottom: CGFloat
            if documentView.isFlipped {
                distanceToBottom = documentBounds.maxY - visibleRect.maxY
            } else {
                distanceToBottom = visibleRect.minY - documentBounds.minY
            }

            return distanceToBottom <= Self.bottomThreshold
        }
    }
}

struct MessageBubble: View, Equatable {
    let message: ChatMessage
    let isStreaming: Bool
    let canInsertIntoDocument: Bool
    let onQuoteAssistant: (String) -> Void
    let onInsertAssistant: (String) -> Void

    @State private var isHovering = false
    private let maxBubbleWidth: CGFloat = 280

    static func == (lhs: MessageBubble, rhs: MessageBubble) -> Bool {
        lhs.message.id == rhs.message.id
            && lhs.message.content == rhs.message.content
            && lhs.message.detail == rhs.message.detail
            && lhs.message.quotedSelection == rhs.message.quotedSelection
            && lhs.isStreaming == rhs.isStreaming
            && lhs.canInsertIntoDocument == rhs.canInsertIntoDocument
    }

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
            AssistantMessageContent(content: message.content, isStreaming: isStreaming)
        } else {
            VStack(alignment: .leading, spacing: 8) {
                if let quote = message.quotedSelection, !quote.isEmpty {
                    HStack(alignment: .top, spacing: 8) {
                        Rectangle()
                            .fill(Color.accentColor.opacity(0.4))
                            .frame(width: 3)
                            .clipShape(Capsule())

                        Text(verbatim: SmartQuotes.smarten(quote))
                            .font(AssistantChatFont.text(size: 12))
                            .foregroundStyle(.secondary)
                            .lineLimit(5)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                Text(verbatim: SmartQuotes.smarten(message.content))
                    .font(AssistantChatFont.message)
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .textSelection(.enabled)
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
        message.role == .assistant && !isStreaming && isHovering && hasAssistantContent
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

                    Text(verbatim: SmartQuotes.smarten(message.content))
                        .font(AssistantChatFont.text(size: 12.5, weight: .semibold))
                        .fixedSize(horizontal: false, vertical: true)
                }

                if let detail = message.detail, !detail.isEmpty {
                    Text(verbatim: SmartQuotes.smarten(detail))
                        .font(AssistantChatFont.text(size: 11.5))
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

private struct AssistantThinkingLabel: View {
    private static let dotCounts = [1, 2, 3, 3, 2, 1]
    @State private var phase = 0

    private var dots: String {
        String(repeating: ".", count: Self.dotCounts[phase])
    }

    var body: some View {
        HStack(spacing: 0) {
            Text("Words, words, words")

            Text("...")
                .hidden()
                .overlay(alignment: .leading) {
                    Text(dots)
                        .contentTransition(.opacity)
                        .animation(.easeInOut(duration: 0.14), value: phase)
                }
        }
        .font(AssistantChatFont.message)
        .foregroundStyle(.secondary)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Shakespeare is preparing a response")
        .task {
            while !Task.isCancelled {
                do {
                    try await Task.sleep(nanoseconds: 380_000_000)
                } catch {
                    return
                }
                phase = (phase + 1) % Self.dotCounts.count
            }
        }
    }
}

private struct AssistantMessageContent: View {
    let content: String
    let isStreaming: Bool

    private var blocks: [AssistantMessageBlock] {
        AssistantMessageBlock.parse(content)
    }

    var body: some View {
        Group {
            if isStreaming {
                if content.isEmpty {
                    AssistantThinkingLabel()
                } else {
                    Text(verbatim: content)
                        .foregroundStyle(.primary)
                        .fixedSize(horizontal: false, vertical: true)
                        .font(AssistantChatFont.message)
                        .lineSpacing(3)
                }
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(Array(blocks.enumerated()), id: \.offset) { entry in
                        blockView(entry.element)
                    }
                }
            }
        }
        .textSelection(.enabled)
    }

    @ViewBuilder
    private func blockView(_ block: AssistantMessageBlock) -> some View {
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

    private var blocks: [SidebarMarkdownBlock] {
        SidebarMarkdownBlock.parse(content)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { entry in
                blockView(entry.element)
            }
        }
        .foregroundStyle(.primary)
        .fixedSize(horizontal: false, vertical: true)
        .font(AssistantChatFont.message)
        .lineSpacing(3)
    }

    @ViewBuilder
    private func blockView(_ block: SidebarMarkdownBlock) -> some View {
        switch block {
        case .heading(let level, let text):
            InlineMarkdownText(content: text)
                .font(headingFont(for: level))
        case .paragraph(let lines):
            VStack(alignment: .leading, spacing: 3) {
                ForEach(Array(lines.enumerated()), id: \.offset) { entry in
                    InlineMarkdownText(content: entry.element)
                }
            }
        case .unorderedList(let items):
            VStack(alignment: .leading, spacing: 5) {
                ForEach(Array(items.enumerated()), id: \.offset) { entry in
                    HStack(alignment: .firstTextBaseline, spacing: 7) {
                        Text("•")
                            .font(AssistantChatFont.text(size: 13.5, weight: .semibold))
                        InlineMarkdownText(content: entry.element)
                    }
                }
            }
            .padding(.leading, 2)
        case .orderedList(let items):
            VStack(alignment: .leading, spacing: 5) {
                ForEach(Array(items.enumerated()), id: \.offset) { entry in
                    HStack(alignment: .firstTextBaseline, spacing: 7) {
                        Text("\(entry.offset + 1).")
                            .font(AssistantChatFont.text(size: 13.5, weight: .medium))
                            .foregroundStyle(.secondary)
                        InlineMarkdownText(content: entry.element)
                    }
                }
            }
        case .quote(let lines):
            HStack(alignment: .top, spacing: 8) {
                Rectangle()
                    .fill(Color.primary.opacity(0.18))
                    .frame(width: 3)
                    .clipShape(Capsule())
                VStack(alignment: .leading, spacing: 3) {
                    ForEach(Array(lines.enumerated()), id: \.offset) { entry in
                        InlineMarkdownText(content: entry.element)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private func headingFont(for level: Int) -> Font {
        switch level {
        case 1:
            return AssistantChatFont.text(size: 15.5, weight: .semibold)
        case 2:
            return AssistantChatFont.text(size: 14.5, weight: .semibold)
        default:
            return AssistantChatFont.text(size: 13.5, weight: .semibold)
        }
    }
}

private struct InlineMarkdownText: View {
    let content: String

    var body: some View {
        let displayContent = SmartQuotes.smarten(content)

        Group {
            if let attributed = try? AttributedString(markdown: displayContent) {
                Text(attributed)
            } else {
                Text(verbatim: displayContent)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }
}

private enum SidebarMarkdownBlock {
    case heading(level: Int, text: String)
    case paragraph([String])
    case unorderedList([String])
    case orderedList([String])
    case quote([String])

    static func parse(_ content: String) -> [SidebarMarkdownBlock] {
        let normalized = content
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !normalized.isEmpty else { return [] }

        let lines = normalized.components(separatedBy: "\n")
        var blocks: [SidebarMarkdownBlock] = []
        var index = 0

        while index < lines.count {
            let line = lines[index].trimmingCharacters(in: .whitespaces)
            if line.isEmpty {
                index += 1
                continue
            }

            if let headingLevel = headingLevel(for: line) {
                let headingText = String(line.dropFirst(headingLevel)).trimmingCharacters(in: .whitespaces)
                blocks.append(.heading(level: headingLevel, text: headingText))
                index += 1
                continue
            }

            if let firstItem = unorderedListItem(in: line) {
                var items = [firstItem]
                index += 1
                while index < lines.count {
                    let candidate = lines[index].trimmingCharacters(in: .whitespaces)
                    guard let item = unorderedListItem(in: candidate) else { break }
                    items.append(item)
                    index += 1
                }
                blocks.append(.unorderedList(items))
                continue
            }

            if let firstItem = orderedListItem(in: line) {
                var items = [firstItem]
                index += 1
                while index < lines.count {
                    let candidate = lines[index].trimmingCharacters(in: .whitespaces)
                    guard let item = orderedListItem(in: candidate) else { break }
                    items.append(item)
                    index += 1
                }
                blocks.append(.orderedList(items))
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
                blocks.append(.quote(quoteLines))
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

            blocks.append(.paragraph(paragraphLines))
        }

        return blocks
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

            Text(verbatim: SmartQuotes.smarten(text))
                .font(AssistantChatFont.text(size: 12.5, weight: .medium))
                .fixedSize(horizontal: false, vertical: true)
        }
        .foregroundStyle(.secondary)
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(Color.accentColor.opacity(0.08), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

private enum AssistantMessageBlock {
    case markdown(String)
    case code(language: String?, content: String)
    case toolAction(String)

    static func parse(_ content: String) -> [AssistantMessageBlock] {
        let normalizedContent = content.replacingOccurrences(of: "\r\n", with: "\n")
        var blocks: [AssistantMessageBlock] = []
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
            return "<pre><code>\(code.htmlEscaped)</code></pre>"
        case .toolAction:
            return nil
        }
    }

    /// Renders markdown to an HTML fragment via the same block parser the
    /// sidebar uses for display, so display and export can't drift apart.
    private static func htmlFromMarkdownText(_ text: String) -> String {
        SidebarMarkdownBlock.parse(text).map { block in
            switch block {
            case .heading(let level, let headingText):
                return "<h\(level)>\(headingText.htmlEscaped)</h\(level)>"
            case .paragraph(let lines):
                return "<p>\(lines.map(\.htmlEscaped).joined(separator: "<br>"))</p>"
            case .unorderedList(let items):
                return "<ul>\(items.map { "<li>\($0.htmlEscaped)</li>" }.joined())</ul>"
            case .orderedList(let items):
                return "<ol>\(items.map { "<li>\($0.htmlEscaped)</li>" }.joined())</ol>"
            case .quote(let lines):
                return "<blockquote><p>\(lines.map(\.htmlEscaped).joined(separator: "<br>"))</p></blockquote>"
            }
        }.joined()
    }
}
