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
                                isActive: editorViewModel.activeCommentID == comment.id,
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
                                },
                                onSetStatus: { status in
                                    editorViewModel.setCommentStatus(comment.id, status: status)
                                },
                                onApplySuggestion: {
                                    editorViewModel.pendingReplaceComment(comment)
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
                if editorViewModel.isAmbientReviewing {
                    ProgressView()
                        .controlSize(.small)
                        .scaleEffect(0.7)
                }
                Toggle(isOn: Binding(
                    get: { editorViewModel.ambientReviewEnabled },
                    set: { editorViewModel.setAmbientReviewEnabled($0) }
                )) {
                    Image(systemName: "sparkles")
                }
                .toggleStyle(.button)
                .controlSize(.small)
                .help("Ambient Review")
                .accessibilityLabel("Ambient Review")
                Button {
                    editorViewModel.addComment()
                } label: {
                    Image(systemName: "plus")
                        .font(.body.weight(.medium))
                }
                .buttonStyle(.plain)
                .help("Add Comment (Cmd+Shift+M)")
                .accessibilityLabel("Add Comment")
                .disabled(!editorViewModel.selectionState.hasSelection)
            }
            if !editorViewModel.ambientReviewStatusText.isEmpty {
                Text(editorViewModel.ambientReviewStatusText)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
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
    let isActive: Bool
    let isEditing: Bool
    @Binding var editingText: String
    let onTap: () -> Void
    let onStartEdit: () -> Void
    let onSave: () -> Void
    let onCancel: () -> Void
    let onDelete: () -> Void
    let onSetStatus: (String) -> Void
    let onApplySuggestion: () -> Void

    @FocusState private var isTextFieldFocused: Bool
    @State private var showDeleteConfirmation = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !metadataBadges.isEmpty {
                HStack(spacing: 6) {
                    ForEach(metadataBadges, id: \.self) { badge in
                        Text(badge)
                            .font(.caption2.weight(.medium))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(badgeBackground, in: Capsule())
                            .foregroundStyle(badgeForeground)
                    }
                    Spacer(minLength: 0)
                }
            }

            // Highlighted text excerpt
            HStack(spacing: 6) {
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(accentColor.opacity(0.7))
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

            if !isEditing, !comment.suggestedReplacement.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text(comment.suggestedReplacement)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(4)
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 6))
            }

            // Timestamp
            if !isEditing {
                HStack {
                    Text(formattedDate)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                    Spacer()
                    if !comment.suggestedReplacement.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Button("Apply") {
                            onApplySuggestion()
                        }
                        .buttonStyle(.plain)
                        .font(.caption)
                        .foregroundColor(.accentColor)
                    }
                    Button(statusActionTitle) {
                        onSetStatus(nextStatus)
                    }
                    .buttonStyle(.plain)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    Button {
                        onStartEdit()
                    } label: {
                        Image(systemName: "pencil")
                            .font(.caption2)
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(.secondary)
                    .help("Edit Comment")
                    .accessibilityLabel("Edit Comment")
                    Button {
                        showDeleteConfirmation = true
                    } label: {
                        Image(systemName: "trash")
                            .font(.caption2)
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(.secondary)
                    .help("Delete Comment")
                    .accessibilityLabel("Delete Comment")
                }
            }
        }
        .padding(12)
        .background(cardBackground, in: RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(isActive ? Color.accentColor.opacity(0.55) : Color.clear, lineWidth: 1)
        }
        .contentShape(Rectangle())
        .onTapGesture { onTap() }
        .focusable()
        .onKeyPress(.return) {
            onTap()
            return .handled
        }
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { onTap() }
        .confirmationDialog(
            "Delete this comment?",
            isPresented: $showDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete Comment", role: .destructive, action: onDelete)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The selected text will stay in the document, but this comment will be removed.")
        }
    }

    private var metadataBadges: [String] {
        var badges: [String] = []
        if comment.source == "agent" {
            badges.append(comment.authorName.isEmpty ? "Editor" : comment.authorName)
        }
        if !comment.kind.isEmpty {
            badges.append(comment.kind.capitalized)
        }
        if !comment.severity.isEmpty {
            badges.append(comment.severity.capitalized)
        }
        if comment.status != "open" {
            badges.append(comment.status.capitalized)
        }
        return badges
    }

    private var accentColor: Color {
        if comment.source == "agent" {
            switch comment.severity {
            case "high": return .red
            case "medium": return .orange
            case "low": return .blue
            default: return .purple
            }
        }
        return .yellow
    }

    private var badgeBackground: Color {
        accentColor.opacity(0.14)
    }

    private var badgeForeground: Color {
        comment.source == "agent" ? accentColor : .secondary
    }

    private var cardBackground: Color {
        if isActive {
            return Color.accentColor.opacity(0.08)
        }
        if comment.status == "resolved" || comment.status == "dismissed" {
            return Color.primary.opacity(0.025)
        }
        return Color.primary.opacity(0.04)
    }

    private var statusActionTitle: String {
        comment.status == "open" ? (comment.source == "agent" ? "Dismiss" : "Resolve") : "Reopen"
    }

    private var nextStatus: String {
        if comment.status != "open" {
            return "open"
        }
        return comment.source == "agent" ? "dismissed" : "resolved"
    }

    private var formattedDate: String {
        guard comment.createdAt > 0 else { return "" }
        let date = Date(timeIntervalSince1970: comment.createdAt / 1000)
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}
