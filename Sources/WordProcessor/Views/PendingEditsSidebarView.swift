import SwiftUI

struct PendingEditsSidebarView: View {
    @Environment(EditorViewModel.self) private var editorViewModel

    private var conflictCount: Int {
        editorViewModel.pendingEdits.filter { $0.status == .conflicted }.count
    }

    private var hasPendingEdits: Bool {
        !editorViewModel.pendingEdits.isEmpty
    }

    var body: some View {
        VStack(spacing: 0) {
            header

            Divider()

            if editorViewModel.pendingEdits.isEmpty {
                ContentUnavailableView(
                    "No Suggestions",
                    systemImage: "square.and.pencil",
                    description: Text("Writing suggestions will appear here once they are queued.")
                )
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 14) {
                            if let activeEdit = editorViewModel.activePendingEdit {
                                activeSummary(activeEdit)
                            }

                            ForEach(editorViewModel.pendingEdits) { edit in
                                PendingEditCard(edit: edit)
                                    .id(edit.id)
                            }
                        }
                        .padding(16)
                    }
                    .onAppear {
                        scrollToActiveEdit(with: proxy, animated: false)
                    }
                    .onChange(of: editorViewModel.activePendingEditID) { _, _ in
                        scrollToActiveEdit(with: proxy)
                    }
                }
            }
        }
        .frame(maxHeight: .infinity)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Suggestions")
                        .font(.headline)
                    Text(summaryText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if hasPendingEdits {
                    HStack(spacing: 6) {
                        smallButton("Prev", action: editorViewModel.focusPreviousPendingEdit)
                            .disabled(editorViewModel.pendingEditCount <= 1)
                        smallButton("Next", action: editorViewModel.focusNextPendingEdit)
                            .disabled(editorViewModel.pendingEditCount <= 1)
                    }
                }
            }

            if hasPendingEdits {
                HStack(spacing: 8) {
                    smallButton(
                        "Accept Current",
                        action: editorViewModel.acceptActivePendingEdit,
                        prominent: true
                    )
                    .disabled(!(editorViewModel.activePendingEdit?.canAccept ?? false))

                    smallButton("Reject Current", action: editorViewModel.rejectActivePendingEdit)
                        .disabled(!(editorViewModel.activePendingEdit?.canReject ?? false))
                }
            }
        }
        .padding(16)
    }

    private var summaryText: String {
        if editorViewModel.pendingEditCount == 0 {
            return "No pending suggestions"
        }

        if conflictCount == 0 {
            return "\(editorViewModel.pendingEditCount) pending suggestion\(editorViewModel.pendingEditCount == 1 ? "" : "s")"
        }

        let pendingCount = editorViewModel.pendingEditCount - conflictCount
        return "\(pendingCount) pending, \(conflictCount) conflicted"
    }

    private func activeSummary(_ edit: EditorViewModel.PendingEdit) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Current Suggestion")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text("Edit \(edit.index + 1) of \(max(editorViewModel.pendingEditCount, edit.index + 1))")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                statusBadge(edit.status)
            }

            Text(edit.label)
                .font(.body.weight(.semibold))

            Text(edit.source)
                .font(.caption)
                .foregroundStyle(.secondary)

            if !edit.conflictReason.orEmpty.isEmpty {
                Text(edit.conflictReason.orEmpty)
                    .font(.caption)
                    .foregroundStyle(.orange)
            }

            activePreviewBlock(
                title: edit.to == edit.from ? "Insert At Cursor" : "Original",
                text: displayOriginalText(for: edit),
                tint: .red
            )

            activePreviewBlock(
                title: edit.status == .conflicted ? "Suggested Replacement" : "Replacement",
                text: displayReplacementText(for: edit),
                tint: edit.status == .conflicted ? .orange : .green
            )
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.accentColor.opacity(0.08))
        )
    }

    @ViewBuilder
    private func smallButton(
        _ title: String,
        action: @escaping () -> Void,
        prominent: Bool = false
    ) -> some View {
        let button = Button(action: action) {
            Text(title)
                .font(.system(size: 12, weight: .medium))
        }
        .controlSize(.small)

        if prominent {
            button.buttonStyle(.borderedProminent)
        } else {
            button.buttonStyle(.bordered)
        }
    }

    private func activePreviewBlock(title: String, text: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title.uppercased())
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(text)
                .font(.system(size: 12.5))
                .textSelection(.enabled)
                .lineLimit(4)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(tint.opacity(0.08))
                )
        }
    }

    private func statusBadge(_ status: EditorViewModel.PendingEdit.Status) -> some View {
        Text(status == .pending ? "Pending" : "Conflict")
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                Capsule()
                    .fill(status == .pending ? Color.green.opacity(0.14) : Color.orange.opacity(0.16))
            )
            .foregroundStyle(status == .pending ? Color.green : Color.orange)
    }

    private func scrollToActiveEdit(with proxy: ScrollViewProxy, animated: Bool = true) {
        guard let id = editorViewModel.activePendingEdit?.id else { return }
        if animated {
            withAnimation(.easeInOut(duration: 0.18)) {
                proxy.scrollTo(id, anchor: .center)
            }
        } else {
            proxy.scrollTo(id, anchor: .center)
        }
    }
}

private struct PendingEditCard: View {
    let edit: EditorViewModel.PendingEdit
    @Environment(EditorViewModel.self) private var editorViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(edit.label)
                        .font(.subheadline.weight(.semibold))

                    Text(edit.source)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 4) {
                    statusBadge
                    Text(edit.isActive ? "Current" : "Edit \(edit.index + 1)")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(edit.isActive ? Color.accentColor : .secondary)
                }
            }

            previewBlock(
                title: edit.to == edit.from ? "Insert At Cursor" : "Original",
                text: displayOriginalText(for: edit),
                tint: .red
            )

            previewBlock(
                title: edit.status == .conflicted ? "Suggested Replacement" : "Replacement",
                text: displayReplacementText(for: edit),
                tint: edit.status == .conflicted ? .orange : .green
            )

            if !edit.conflictReason.orEmpty.isEmpty {
                Text(edit.conflictReason.orEmpty)
                    .font(.caption)
                    .foregroundStyle(.orange)
            }

            HStack(spacing: 8) {
                actionButton("Jump") {
                    editorViewModel.focusPendingEdit(edit.id)
                }
                .disabled(!edit.canFocus)

                actionButton("Accept", prominent: true) {
                    editorViewModel.acceptPendingEdit(edit.id)
                }
                .disabled(!edit.canAccept)

                actionButton(edit.status == .conflicted ? "Dismiss" : "Reject") {
                    editorViewModel.rejectPendingEdit(edit.id)
                }
                .disabled(!edit.canReject)
            }
        }
        .padding(14)
        .background(cardBackground)
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(edit.isActive ? Color.accentColor.opacity(0.35) : Color.clear, lineWidth: 1.5)
        )
    }

    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: 14, style: .continuous)
            .fill(edit.isActive ? Color.accentColor.opacity(0.08) : Color(nsColor: .controlBackgroundColor))
    }

    private var statusBadge: some View {
        Text(edit.status == .pending ? "Pending" : "Conflict")
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                Capsule()
                    .fill(edit.status == .pending ? Color.green.opacity(0.14) : Color.orange.opacity(0.16))
            )
            .foregroundStyle(edit.status == .pending ? Color.green : Color.orange)
    }

    private func previewBlock(title: String, text: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title.uppercased())
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(text)
                .font(.system(size: 12.5))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(tint.opacity(0.08))
                )
        }
    }

    @ViewBuilder
    private func actionButton(
        _ title: String,
        prominent: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        let button = Button(action: action) {
            Text(title)
                .font(.system(size: 12, weight: .medium))
        }
        .controlSize(.small)

        if prominent {
            button.buttonStyle(.borderedProminent)
        } else {
            button.buttonStyle(.bordered)
        }
    }
}

private extension Optional where Wrapped == String {
    var orEmpty: String {
        self ?? ""
    }
}

private func displayOriginalText(for edit: EditorViewModel.PendingEdit) -> String {
    edit.originalText.isEmpty ? "No existing text at this location." : edit.originalText
}

private func displayReplacementText(for edit: EditorViewModel.PendingEdit) -> String {
    if edit.replacementText.isEmpty {
        return edit.status == .conflicted ? "This edit can no longer be applied safely." : "Delete the current text."
    }
    return edit.replacementText
}
