import SwiftUI

struct CommentsSidebarView: View {
    @Environment(EditorViewModel.self) private var editorViewModel
    @State private var editingCommentId: String?
    @State private var editingText: String = ""
    @State private var knownCommentIDs: Set<String> = []

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()

            if editorViewModel.comments.isEmpty {
                ContentUnavailableView(
                    "No Comments",
                    systemImage: "quote.bubble",
                    description: Text("Select text and press Cmd+Shift+M to add a comment.")
                )
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        ForEach(editorViewModel.comments) { comment in
                            CommentCard(
                                comment: comment,
                                isEditing: editingCommentId == comment.id,
                                editingText: editingCommentId == comment.id ? $editingText : .constant(""),
                                onTap: {
                                    editorViewModel.focusComment(comment.id)
                                },
                                onStartEdit: {
                                    beginEditing(comment)
                                },
                                onSave: {
                                    saveComment(comment)
                                },
                                onCancel: {
                                    cancelEditing(comment)
                                },
                                onDelete: {
                                    deleteComment(comment)
                                }
                            )
                        }
                    }
                    .padding(16)
                }
            }
        }
        .frame(maxHeight: .infinity)
        .onAppear {
            syncEditingState(with: editorViewModel.comments)
        }
        .onChange(of: editorViewModel.comments) { _, comments in
            syncEditingState(with: comments)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Comments")
                        .font(.headline)
                    Text("\(editorViewModel.comments.count) comment\(editorViewModel.comments.count == 1 ? "" : "s")")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    editorViewModel.addComment()
                } label: {
                    Image(systemName: "plus")
                        .font(.body.weight(.medium))
                }
                .buttonStyle(.plain)
                .help("Add Comment (Cmd+Shift+M)")
                .disabled(!editorViewModel.selectionState.hasSelection)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private func beginEditing(_ comment: BridgePayload.CommentData) {
        editingCommentId = comment.id
        editingText = comment.text
    }

    private func saveComment(_ comment: BridgePayload.CommentData) {
        let trimmed = editingText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        editorViewModel.updateCommentText(comment.id, text: trimmed)
        editingCommentId = nil
        editingText = ""
    }

    private func cancelEditing(_ comment: BridgePayload.CommentData) {
        let isDraft = comment.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        editingCommentId = nil
        editingText = ""

        if isDraft {
            editorViewModel.removeComment(comment.id)
        }
    }

    private func deleteComment(_ comment: BridgePayload.CommentData) {
        if editingCommentId == comment.id {
            editingCommentId = nil
            editingText = ""
        }

        editorViewModel.removeComment(comment.id)
    }

    private func syncEditingState(with comments: [BridgePayload.CommentData]) {
        let ids = Set(comments.map(\.id))

        if let editingCommentId, !ids.contains(editingCommentId) {
            self.editingCommentId = nil
            editingText = ""
        }

        if self.editingCommentId == nil,
           let draft = comments
            .filter({ $0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !knownCommentIDs.contains($0.id) })
            .max(by: { $0.createdAt < $1.createdAt }) {
            self.editingCommentId = draft.id
            editingText = draft.text
        }

        knownCommentIDs = ids
    }
}

private struct CommentCard: View {
    let comment: BridgePayload.CommentData
    let isEditing: Bool
    @Binding var editingText: String
    let onTap: () -> Void
    let onStartEdit: () -> Void
    let onSave: () -> Void
    let onCancel: () -> Void
    let onDelete: () -> Void

    @FocusState private var isTextFieldFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Highlighted text excerpt
            HStack(spacing: 6) {
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(Color.yellow.opacity(0.6))
                    .frame(width: 3)

                Text(comment.selectedText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .italic()
            }

            if isEditing {
                TextField("Add your comment...", text: $editingText, axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(.callout)
                    .lineLimit(1...8)
                    .focused($isTextFieldFocused)
                    .onAppear { isTextFieldFocused = true }
                    .onSubmit { onSave() }

                HStack(spacing: 8) {
                    Spacer()
                    Button("Cancel", action: onCancel)
                        .buttonStyle(.plain)
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Button("Save", action: onSave)
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                        .disabled(editingText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            } else if comment.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text("No comment text")
                    .font(.callout)
                    .foregroundStyle(.tertiary)
                    .italic()
            } else {
                Text(comment.text)
                    .font(.callout)
                    .foregroundStyle(.primary)
            }

            // Timestamp
            if !isEditing {
                HStack {
                    Text(formattedDate)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                    Spacer()
                    Button {
                        onStartEdit()
                    } label: {
                        Image(systemName: "pencil")
                            .font(.caption2)
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(.secondary)
                    Button {
                        onDelete()
                    } label: {
                        Image(systemName: "trash")
                            .font(.caption2)
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(.secondary)
                }
            }
        }
        .padding(12)
        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 8))
        .contentShape(Rectangle())
        .onTapGesture { onTap() }
    }

    private var formattedDate: String {
        guard comment.createdAt > 0 else { return "" }
        let date = Date(timeIntervalSince1970: comment.createdAt / 1000)
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}
