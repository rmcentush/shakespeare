import AppKit
import SwiftUI

struct ClaudeChatView: View {
    @State private var chatViewModel = ClaudeChatViewModel()
    @Environment(EditorViewModel.self) private var editorViewModel
    @Environment(DocumentModel.self) private var document
    @State private var inputText = ""

    var body: some View {
        VStack(spacing: 0) {
            // Messages list
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        ForEach(chatViewModel.messages) { message in
                            MessageBubble(message: message)
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
                    withAnimation(.easeOut(duration: 0.15)) {
                        proxy.scrollTo("bottom")
                    }
                }
                .onChange(of: chatViewModel.streamingContentLength) {
                    proxy.scrollTo("bottom")
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
}

struct MessageBubble: View {
    let message: ChatMessage

    var body: some View {
        HStack {
            if message.role == .user { Spacer(minLength: 40) }

            Text(verbatim: message.content)
                .font(.body)
                .padding(10)
                .background(
                    message.role == .user
                        ? Color.accentColor.opacity(0.15)
                        : Color(.controlBackgroundColor)
                )
                .cornerRadius(12)
                .contextMenu {
                    Button("Copy") {
                        copyMessageToPasteboard(message.content)
                    }
                }

            if message.role == .assistant { Spacer(minLength: 40) }
        }
    }

    private func copyMessageToPasteboard(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }
}
