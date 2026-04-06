import SwiftUI

struct CommentsSidebarView: View {
    @Environment(EditorViewModel.self) private var editorViewModel
    @State private var editingCommentId: String?
    @State private var editingText: String = ""

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()

            if editorViewModel.comments.isEmpty {
                ContentUnavailableView(
                    "No Comments",
                    systemImage: "text.bubble",
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
                                    editingCommentId = comment.id
                                    editingText = comment.text
                                },
                                onSave: {
                                    editorViewModel.updateCommentText(comment.id, text: editingText)
                                    editingCommentId = nil
                                },
                                onCancel: {
                                    editingCommentId = nil
                                },
                                onDelete: {
                                    editorViewModel.removeComment(comment.id)
                                }
                            )
                        }
                    }
                    .padding(16)
                }
            }
        }
        .frame(maxHeight: .infinity)
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
                        .disabled(editingText.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            } else if comment.text.isEmpty {
                // Newly created comment — auto-edit
                Color.clear
                    .frame(height: 0)
                    .onAppear { onStartEdit() }
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
