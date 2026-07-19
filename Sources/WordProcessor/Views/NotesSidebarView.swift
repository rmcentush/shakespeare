import SwiftUI

struct NotesSidebarView: View {
    @Environment(DocumentModel.self) private var document
    @Environment(EditorViewModel.self) private var editorViewModel
    @FocusState private var isNotesFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()

            if supportsNotes {
                notesEditor
            } else {
                unsupportedDocumentView
            }
        }
        .frame(maxHeight: .infinity)
        .onAppear {
            guard supportsNotes else { return }
            DispatchQueue.main.async {
                isNotesFocused = true
            }
        }
        .onChange(of: supportsNotes) { _, isSupported in
            guard isSupported else { return }
            DispatchQueue.main.async {
                isNotesFocused = true
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("Notes")
                .font(.headline)
            Text(summaryText)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var notesBinding: Binding<String> {
        Binding(
            get: { document.notes },
            set: { notes in
                document.updateNotes(notes)
                editorViewModel.schedulePersistence(document: document)
            }
        )
    }

    private var supportsNotes: Bool {
        guard let fileURL = document.fileURL else { return true }
        return DocumentFileStore.isNativeDocumentURL(fileURL)
    }

    private var notesEditor: some View {
        ZStack(alignment: .topLeading) {
            TextEditor(text: notesBinding)
                .font(.body)
                .scrollContentBackground(.hidden)
                .padding(12)
                .focused($isNotesFocused)
                .accessibilityLabel("Document Notes")

            if document.notes.isEmpty {
                Text("Add context, reminders, or loose ideas…")
                    .font(.body)
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 17)
                    .padding(.vertical, 20)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var unsupportedDocumentView: some View {
        VStack(spacing: 12) {
            Image(systemName: "note.text")
                .font(.system(size: 32))
                .foregroundStyle(.secondary)
            Text("Save as a Shakespeare Document")
                .font(.headline)
            Text("Notes are stored inside .shkdoc files so they stay with the document.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Button("Save As…") {
                editorViewModel.saveDocumentAs(document: document)
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var summaryText: String {
        guard supportsNotes else { return "Available in .shkdoc documents" }
        let wordCount = document.notes.split(whereSeparator: \.isWhitespace).count
        guard wordCount > 0 else { return "Saved with this document" }
        return "\(wordCount) word\(wordCount == 1 ? "" : "s") · Saved with this document"
    }
}
