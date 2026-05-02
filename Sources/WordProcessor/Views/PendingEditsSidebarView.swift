import SwiftUI

struct PendingEditsSidebarView: View {
    @Environment(EditorViewModel.self) private var editorViewModel

    private var conflictCount: Int {
        editorViewModel.pendingEdits.filter { $0.status == .conflicted }.count
    }

    var body: some View {
        VStack(spacing: 0) {
            header

            Divider()

            if editorViewModel.pendingEdits.isEmpty {
                ContentUnavailableView(
                    "No Suggestions",
                    systemImage: "square.and.pencil",
                    description: Text("Claude suggestions will appear here once they are queued.")
                )
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        if let activeEdit = editorViewModel.activePendingEdit {
                            activeSummary(activeEdit)
                        }

                        ForEach(editorViewModel.pendingEdits) { edit in
                            PendingEditCard(edit: edit)
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
                    Text("Suggestions")
                        .font(.headline)
                    Text(summaryText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                HStack(spacing: 6) {
                    smallButton("Prev", action: editorViewModel.focusPreviousPendingEdit)
                    smallButton("Next", action: editorViewModel.focusNextPendingEdit)
                }
            }

            HStack(spacing: 8) {
                smallButton(
                    "Accept Current",
                    action: editorViewModel.acceptActivePendingEdit,
                    prominent: true
                )
                .disabled(!(editorViewModel.activePendingEdit?.canAccept ?? false))

                smallButton("Reject Current", action: editorViewModel.rejectActivePendingEdit)
                smallButton("Accept All", action: editorViewModel.acceptAllPendingEdits, prominent: true)
                smallButton("Reject All", action: editorViewModel.rejectAllPendingEdits)
            }
        }
        .padding(16)
    }

    private var summaryText: String {
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

                statusBadge
            }

            previewBlock(
                title: edit.to == edit.from ? "Insert At Cursor" : "Original",
                text: edit.originalText.isEmpty ? "No existing text at this location." : edit.originalText,
                tint: .red
            )

            previewBlock(
                title: edit.status == .conflicted ? "Suggested Replacement" : "Replacement",
                text: replacementText,
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

    private var replacementText: String {
        if edit.replacementText.isEmpty {
            return edit.status == .conflicted ? "This edit can no longer be applied safely." : "Delete the current text."
        }
        return edit.replacementText
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
