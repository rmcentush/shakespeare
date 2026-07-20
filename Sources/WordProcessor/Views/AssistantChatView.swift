import AppKit
import Foundation
import SwiftUI

struct AssistantChatView: View {
    @Environment(\.openWindow) private var openWindow
    @State private var chatViewModel = AssistantChatViewModel()
    @Environment(EditorViewModel.self) private var editorViewModel
    @Environment(DocumentModel.self) private var document
    @State private var inputText = ""
    @State private var shouldFollowLatestMessage = true
    @State private var hasResearchConnection = false
    @FocusState private var isInputFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            // Messages list
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 14) {
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
                                isSearchingWeb: chatViewModel.isSearchingWeb,
                                isRetryEnabled: !chatViewModel.isStreaming,
                                onRetry: { chatViewModel.retryMessage(message.id) }
                            )
                                .id(message.id)
                        }

                        // Invisible anchor at the bottom for auto-scrolling
                        Color.clear
                            .frame(height: 1)
                            .id("bottom")
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 16)
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

            Rectangle()
                .fill(Color.primary.opacity(0.08))
                .frame(height: 1)

            // Input area
            VStack(alignment: .leading, spacing: 8) {
                if hasResearchConnection {
                    HStack(alignment: .bottom, spacing: 8) {
                        TextField("Ask anything…", text: smartQuotedInputText, axis: .vertical)
                            .textFieldStyle(.plain)
                            .font(AssistantChatFont.input)
                            .lineLimit(1...5)
                            .frame(minHeight: 28, alignment: .center)
                            .focused($isInputFocused)
                            .onSubmit {
                                if !chatViewModel.isStreaming {
                                    sendMessage()
                                }
                            }

                        Button {
                            if chatViewModel.isStreaming {
                                chatViewModel.cancelStreaming()
                            } else {
                                sendMessage()
                            }
                        } label: {
                            Image(systemName: chatViewModel.isStreaming ? "stop.fill" : "arrow.up")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(.white)
                                .frame(width: 28, height: 28)
                                .background(buttonColor, in: Circle())
                        }
                        .buttonStyle(.plain)
                        .disabled(!chatViewModel.isStreaming && inputText.isEmpty)
                        .help(chatViewModel.isStreaming ? "Stop Response" : "Send Message")
                        .accessibilityLabel(chatViewModel.isStreaming ? "Stop Response" : "Send Message")
                    }
                    .padding(.leading, 12)
                    .padding(.trailing, 6)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .fill(Color(nsColor: .controlBackgroundColor))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .stroke(
                                isInputFocused
                                    ? Color.accentColor.opacity(0.42)
                                    : Color.primary.opacity(0.09),
                                lineWidth: 1
                            )
                    )
                } else {
                    HStack(spacing: 8) {
                        Text("Connect OpenRouter for research chat")
                            .font(.system(size: 10.5, weight: .medium))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                            .layoutPriority(1)

                        Spacer(minLength: 0)

                        Button {
                            UserDefaults.standard.set(
                                SettingsDestination.apiKeys,
                                forKey: SettingsDestination.defaultsKey
                            )
                            openWindow(id: WordProcessorWindowID.settings)
                        } label: {
                            Label("Connect", systemImage: "key")
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                        .fixedSize()
                    }
                    .padding(.horizontal, 4)
                }
            }
            .padding(12)
            .background(Color(nsColor: .windowBackgroundColor))
        }
        .frame(maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear {
            refreshConnectionStatus()
            startPendingSelectionFeedbackIfPossible()
        }
        .onReceive(NotificationCenter.default.publisher(for: .openRouterConnectionChanged)) { _ in
            refreshConnectionStatus()
            startPendingSelectionFeedbackIfPossible()
        }
        .onChange(of: editorViewModel.pendingSelectionFeedbackRequest?.id) {
            startPendingSelectionFeedbackIfPossible()
        }
        .onDisappear {
            chatViewModel.cancelStreaming()
        }
    }

    private var buttonColor: Color {
        if chatViewModel.isStreaming {
            return .orange
        }
        return inputText.isEmpty
            ? Color(nsColor: .tertiaryLabelColor)
            : .accentColor
    }

    private var smartQuotedInputText: Binding<String> {
        Binding(
            get: { inputText },
            set: { inputText = SmartQuotes.smarten($0) }
        )
    }

    private func chooseStarterPrompt(_ prompt: String) {
        inputText = prompt
        isInputFocused = true
    }

    private func refreshConnectionStatus() {
        hasResearchConnection = APIKeyStore.shared.hasAPIKey(service: "openrouter")
    }

    private func startPendingSelectionFeedbackIfPossible() {
        guard hasResearchConnection,
              let request = editorViewModel.pendingSelectionFeedbackRequest
        else { return }
        editorViewModel.consumeSelectionFeedbackRequest(id: request.id)
        shouldFollowLatestMessage = true
        chatViewModel.sendSelectionFeedback(
            selection: request.selection,
            documentContent: request.documentContent
        )
    }

    private func sendMessage() {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        inputText = ""
        shouldFollowLatestMessage = true
        let editor = editorViewModel

        if editor.isEditorReady {
            editor.getEditContextSnapshot { context in
                if let context {
                    chatViewModel.sendMessage(
                        text,
                        documentContent: context.plainText
                    )
                    return
                }

                editor.getPlainText { content in
                    chatViewModel.sendMessage(
                        text,
                        documentContent: content
                    )
                }
            }
            return
        }

        chatViewModel.sendMessage(
            text,
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

}

private struct AssistantEmptyState: View {
    let isConnected: Bool
    let onChoosePrompt: (String) -> Void

    private let prompts = [
        "Fact-check this draft.",
        "Find supporting evidence.",
        "What am I missing?",
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            HStack(alignment: .center, spacing: 11) {
                Image(systemName: "globe.americas.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 34, height: 34)
                    .background(Color.accentColor.opacity(0.1), in: Circle())

                VStack(alignment: .leading, spacing: 2) {
                    Text("Research Chat")
                        .font(.system(size: 15, weight: .semibold))
                    Text("Draft-aware · source-backed")
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundStyle(.tertiary)
                }
            }

            Text(isConnected
                ? "Ask about your draft or research the live web. Shakespeare returns concise answers with source links."
                : "Connect OpenRouter once for writing help, grammar, and source-backed research.")
                .font(.system(size: 12.5))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

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
                                Text(prompt)
                                    .font(.system(size: 12))
                                    .multilineTextAlignment(.leading)
                                Spacer(minLength: 0)
                                Image(systemName: "arrow.up.right")
                                    .font(.system(size: 9, weight: .semibold))
                                    .foregroundStyle(.tertiary)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 8)
                        }
                        .buttonStyle(.plain)
                        .background(
                            Color(nsColor: .controlBackgroundColor),
                            in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .stroke(Color.primary.opacity(0.07), lineWidth: 1)
                        )
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 6)
    }
}

private enum AssistantChatFont {
    static let input = text(size: 13.5)
    static let message = text(size: 13.5)

    static func text(size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight)
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

    static func dismantleNSView(_ nsView: TrackingView, coordinator: Coordinator) {
        coordinator.detach()
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

    @MainActor
    final class Coordinator {
        private static let bottomThreshold: CGFloat = 32

        var onNearBottomChanged: (Bool) -> Void

        private weak var scrollView: NSScrollView?
        private var boundsObserver: NSObjectProtocol?
        private var lastReportedNearBottom: Bool?

        init(onNearBottomChanged: @escaping (Bool) -> Void) {
            self.onNearBottomChanged = onNearBottomChanged
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
                MainActor.assumeIsolated {
                    self?.reportNearBottomIfNeeded()
                }
            }

            reportNearBottomIfNeeded(force: true)
        }

        fileprivate func detach() {
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

struct MessageBubble: View {
    let message: ChatMessage
    let isStreaming: Bool
    let isSearchingWeb: Bool
    let isRetryEnabled: Bool
    let onRetry: () -> Void

    private let maxUserBubbleWidth: CGFloat = 360

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
            HStack(alignment: .top, spacing: 0) {
                if message.role == .user { Spacer(minLength: 40) }

                bubbleContent
                    .padding(drawsBubbleChrome ? 12 : 0)
                    .frame(
                        maxWidth: message.role == .assistant ? .infinity : maxUserBubbleWidth,
                        alignment: .leading
                    )
                    .background(bubbleBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 15, style: .continuous)
                            .stroke(bubbleBorderColor, lineWidth: 1)
                    )
                    .contextMenu {
                        Button("Copy") {
                            copyMessageToPasteboard(message.combinedText)
                        }
                    }

                if message.role == .assistant { Spacer(minLength: 24) }
            }
        }
    }

    @ViewBuilder
    private var bubbleContent: some View {
        if message.role == .assistant {
            VStack(alignment: .leading, spacing: 10) {
                if isStreaming || hasAssistantContent {
                    AssistantMessageContent(
                        content: message.content,
                        sources: message.sources,
                        isStreaming: isStreaming,
                        isSearchingWeb: isSearchingWeb
                    )
                }

                if message.deliveryState != .normal {
                    AssistantDeliveryStatusView(
                        state: message.deliveryState,
                        isRetryEnabled: isRetryEnabled,
                        onRetry: onRetry
                    )
                }
            }
        } else {
            Text(verbatim: SmartQuotes.smarten(message.content))
                .font(AssistantChatFont.message)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
        }
    }

    private var bubbleBackground: Color {
        guard drawsBubbleChrome else { return .clear }
        if message.role == .user {
            return Color.accentColor.opacity(0.13)
        }
        return Color(nsColor: .controlBackgroundColor)
    }

    private var bubbleBorderColor: Color {
        guard drawsBubbleChrome else { return .clear }
        return message.role == .user
            ? Color.accentColor.opacity(0.12)
            : Color.primary.opacity(0.065)
    }

    private var hasAssistantContent: Bool {
        !message.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var drawsBubbleChrome: Bool {
        guard message.role == .assistant, !hasAssistantContent else { return true }
        if case .failed = message.deliveryState { return false }
        return true
    }

    private func copyMessageToPasteboard(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }
}

private struct AssistantDeliveryStatusView: View {
    let state: ChatMessage.DeliveryState
    let isRetryEnabled: Bool
    let onRetry: () -> Void

    var body: some View {
        switch state {
        case .normal:
            EmptyView()
        case .cancelled:
            HStack(spacing: 8) {
                Label("Stopped", systemImage: "stop.circle")
                    .font(.system(size: 11.5, weight: .medium))
                Spacer(minLength: 0)
                retryButton
            }
            .foregroundStyle(.secondary)
        case .failed(let title, let detail):
            HStack(alignment: .top, spacing: 9) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.orange)
                    .padding(.top, 1)

                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.primary)
                    Text(detail)
                        .font(.system(size: 11.5))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 4)
                retryButton
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(10)
            .background(
                Color.orange.opacity(0.075),
                in: RoundedRectangle(cornerRadius: 10, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(Color.orange.opacity(0.16), lineWidth: 1)
            )
        }
    }

    private var retryButton: some View {
        Button(action: onRetry) {
            Label("Try Again", systemImage: "arrow.clockwise")
                .font(.system(size: 10.5, weight: .semibold))
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .fixedSize()
        .disabled(!isRetryEnabled)
        .accessibilityLabel("Try request again")
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

private struct AssistantThinkingLabel: View {
    let isSearchingWeb: Bool

    var body: some View {
        HStack(spacing: 8) {
            ProgressView()
                .controlSize(.small)
                .scaleEffect(0.72)
                .frame(width: 16, height: 16)

            Text(isSearchingWeb ? "Searching sources…" : "Thinking…")
            .font(.system(size: 11.5, weight: .medium))
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 1)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(isSearchingWeb ? "Searching sources" : "Preparing a response")
    }
}

private struct AssistantMessageContent: View {
    let content: String
    let sources: [ChatSource]
    let isStreaming: Bool
    let isSearchingWeb: Bool

    private var blocks: [AssistantMessageBlock] {
        AssistantMessageBlock.parse(content)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if isStreaming && content.isEmpty {
                AssistantThinkingLabel(isSearchingWeb: isSearchingWeb)
            } else {
                ForEach(Array(blocks.enumerated()), id: \.offset) { entry in
                    blockView(entry.element)
                }
            }

            if !isStreaming, !sources.isEmpty {
                AssistantSourcesView(sources: sources)
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

private struct AssistantSourcesView: View {
    let sources: [ChatSource]
    @State private var isExpanded = false

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            VStack(alignment: .leading, spacing: 5) {
                ForEach(sources) { source in
                    if let destination = source.destination {
                        Link(destination: destination) {
                            HStack(spacing: 7) {
                                Image(systemName: "arrow.up.right.square")
                                    .font(.system(size: 9.5, weight: .semibold))
                                    .foregroundStyle(.tertiary)

                                VStack(alignment: .leading, spacing: 1) {
                                    Text(source.displayTitle)
                                        .font(.system(size: 11.5, weight: .medium))
                                        .foregroundStyle(.primary)
                                        .lineLimit(1)
                                    Text(source.host)
                                        .font(.system(size: 9.5))
                                        .foregroundStyle(.tertiary)
                                        .lineLimit(1)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, 3)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(.top, 6)
        } label: {
            Label(sourceCountLabel, systemImage: "link")
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundStyle(.secondary)
        }
        .padding(.top, 2)
        .accessibilityLabel(sourceCountLabel)
    }

    private var sourceCountLabel: String {
        sources.count == 1 ? "1 source" : "\(sources.count) sources"
    }
}

private struct MarkdownText: View {
    let content: String

    private var blocks: [SidebarMarkdownBlock] {
        SidebarMarkdownBlock.parse(content)
    }

    private var attributedContent: AttributedString {
        var result = AttributedString()

        for (index, block) in blocks.enumerated() {
            if index > 0 {
                result.append(AttributedString("\n\n"))
            }
            append(block, to: &result)
        }

        return result
    }

    var body: some View {
        Text(attributedContent)
            .foregroundStyle(.primary)
            .fixedSize(horizontal: false, vertical: true)
            .font(AssistantChatFont.message)
            .lineSpacing(3)
            .textSelection(.enabled)
            .environment(\.openURL, OpenURLAction { url in
                guard AssistantLinkPolicy.isAllowed(url) else { return .discarded }
                NSWorkspace.shared.open(url)
                return .handled
            })
    }

    private func append(_ block: SidebarMarkdownBlock, to result: inout AttributedString) {
        switch block {
        case .heading(let level, let text):
            result.append(applyingFont(headingFont(for: level), to: inlineMarkdown(text)))
        case .paragraph(let lines):
            append(lines, to: &result)
        case .unorderedList(let items):
            append(items.map { "• \($0)" }, to: &result)
        case .orderedList(let items):
            append(items.enumerated().map { "\($0.offset + 1). \($0.element)" }, to: &result)
        case .quote(let lines):
            var quote = AttributedString()
            append(lines.map { "│ \($0)" }, to: &quote)
            result.append(applyingColor(.secondaryLabelColor, to: quote))
        }
    }

    private func append(_ lines: [String], to result: inout AttributedString) {
        for (index, line) in lines.enumerated() {
            if index > 0 {
                result.append(AttributedString("\n"))
            }
            result.append(inlineMarkdown(line))
        }
    }

    private func inlineMarkdown(_ text: String) -> AttributedString {
        let displayText = SmartQuotes.smarten(text)
        let options = AttributedString.MarkdownParsingOptions(
            interpretedSyntax: .inlineOnlyPreservingWhitespace
        )
        let attributed = (try? AttributedString(markdown: displayText, options: options))
            ?? AttributedString(displayText)
        return AssistantLinkPolicy.sanitized(attributed)
    }

    private func headingFont(for level: Int) -> NSFont {
        switch level {
        case 1:
            return .systemFont(ofSize: 15.5, weight: .semibold)
        case 2:
            return .systemFont(ofSize: 14.5, weight: .semibold)
        default:
            return .systemFont(ofSize: 13.5, weight: .semibold)
        }
    }

    private func applyingFont(_ font: NSFont, to value: AttributedString) -> AttributedString {
        let attributed = NSMutableAttributedString(attributedString: NSAttributedString(value))
        attributed.addAttribute(
            .font,
            value: font,
            range: NSRange(location: 0, length: attributed.length)
        )
        return AttributedString(attributed)
    }

    private func applyingColor(_ color: NSColor, to value: AttributedString) -> AttributedString {
        let attributed = NSMutableAttributedString(attributedString: NSAttributedString(value))
        attributed.addAttribute(
            .foregroundColor,
            value: color,
            range: NSRange(location: 0, length: attributed.length)
        )
        return AttributedString(attributed)
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
