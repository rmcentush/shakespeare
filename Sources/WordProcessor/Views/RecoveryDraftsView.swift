import SwiftUI

struct RecoveryDraftsView: View {
    let drafts: [RecoveryDraftStore.DraftMetadata]
    let onRecover: (RecoveryDraftStore.DraftMetadata) -> Void
    let onDiscard: (RecoveryDraftStore.DraftMetadata) -> Void
    let onClose: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Label("Recovery Drafts", systemImage: "lifepreserver")
                    .font(.headline)
                Spacer()
                Button("Not Now", action: onClose)
                    .keyboardShortcut(.cancelAction)
            }
            .padding(16)

            Divider()

            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(drafts) { draft in
                        draftRow(draft)
                        Divider()
                    }
                }
            }
            .frame(minHeight: 120, maxHeight: 320)
        }
        .frame(width: 480)
    }

    private func draftRow(_ draft: RecoveryDraftStore.DraftMetadata) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: draft.isUntitled ? "doc.badge.plus" : "doc.text")
                .font(.system(size: 22))
                .foregroundStyle(.secondary)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 4) {
                Text(draft.displayName)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)

                Text("\(formattedDate(draft.updatedAt)) - \(draft.wordCount) words")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if let path = draft.originalFilePath {
                    Text(path)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }

            Spacer(minLength: 12)

            VStack(spacing: 6) {
                Button("Recover") {
                    onRecover(draft)
                }
                .controlSize(.small)
                .buttonStyle(.borderedProminent)

                Button("Discard", role: .destructive) {
                    onDiscard(draft)
                }
                .controlSize(.small)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private func formattedDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}
