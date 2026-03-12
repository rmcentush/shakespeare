import SwiftUI

struct VersionHistoryView: View {
    @Environment(DocumentModel.self) private var document
    @Environment(EditorViewModel.self) private var editorViewModel
    @State private var versions: [VersionStore.Version] = []
    @State private var selectedVersionID: Int64?
    @State private var previewHTML: String?
    @State private var renamingVersionID: Int64?
    @State private var renameText = ""
    @State private var showSaveNamedAlert = false
    @State private var namedVersionName = ""
    @State private var showDeleteConfirm = false
    @State private var deleteTargetID: Int64?

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if versions.isEmpty {
                emptyState
            } else {
                versionList
            }
        }
        .frame(width: 280)
        .background(.background)
        .onAppear { refreshVersions() }
        .onChange(of: document.fileURL) { refreshVersions() }
        .alert("Save Named Version", isPresented: $showSaveNamedAlert) {
            TextField("Version name", text: $namedVersionName)
            Button("Save") { saveNamedVersion() }
            Button("Cancel", role: .cancel) { namedVersionName = "" }
        } message: {
            Text("Give this version a name (e.g. \"Draft 1\", \"Final\")")
        }
        .alert("Delete Version?", isPresented: $showDeleteConfirm) {
            Button("Delete", role: .destructive) { confirmDelete() }
            Button("Cancel", role: .cancel) { deleteTargetID = nil }
        } message: {
            Text("This version will be permanently deleted.")
        }
    }

    private var header: some View {
        VStack(spacing: 8) {
            HStack {
                Label("Version History", systemImage: "clock.arrow.circlepath")
                    .font(.headline)
                Spacer()
            }
            if document.fileURL != nil {
                Button {
                    namedVersionName = ""
                    showSaveNamedAlert = true
                } label: {
                    Label("Save Named Version", systemImage: "bookmark")
                        .frame(maxWidth: .infinity)
                }
                .controlSize(.small)
            }
        }
        .padding(12)
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Spacer()
            Image(systemName: "clock.arrow.circlepath")
                .font(.system(size: 32))
                .foregroundStyle(.quaternary)
            if document.fileURL == nil {
                Text("Save your document first\nto start tracking versions.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            } else {
                Text("No versions yet.\nVersions are saved each time you save.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            Spacer()
        }
        .padding()
    }

    private var versionList: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(versions) { version in
                    versionRow(version)
                    Divider().padding(.leading, 12)
                }
            }
        }
    }

    private func versionRow(_ version: VersionStore.Version) -> some View {
        let isSelected = selectedVersionID == version.id
        return VStack(alignment: .leading, spacing: 4) {
            HStack {
                if version.isNamed {
                    if renamingVersionID == version.id {
                        TextField("Name", text: $renameText, onCommit: {
                            commitRename(version)
                        })
                        .textFieldStyle(.plain)
                        .font(.subheadline.weight(.semibold))
                    } else {
                        Text(version.versionName ?? "")
                            .font(.subheadline.weight(.semibold))
                            .lineLimit(1)
                    }
                    Image(systemName: "bookmark.fill")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                } else {
                    Text(formattedDate(version.createdAt))
                        .font(.subheadline)
                        .lineLimit(1)
                }
                Spacer()
            }
            HStack(spacing: 8) {
                if !version.isNamed {
                    Text(formattedTime(version.createdAt))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text(formattedDateTime(version.createdAt))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Text("\(version.wordCount) words")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }

            if isSelected {
                HStack(spacing: 6) {
                    Button("Restore") {
                        restoreVersion(version)
                    }
                    .controlSize(.small)

                    if version.isNamed {
                        Button("Rename") {
                            renameText = version.versionName ?? ""
                            renamingVersionID = version.id
                        }
                        .controlSize(.small)
                    } else {
                        Button("Name") {
                            namedVersionName = ""
                            nameUnnamedVersion(version)
                        }
                        .controlSize(.small)
                    }

                    Spacer()

                    Button(role: .destructive) {
                        deleteTargetID = version.id
                        showDeleteConfirm = true
                    } label: {
                        Image(systemName: "trash")
                    }
                    .controlSize(.small)
                }
                .padding(.top, 4)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .contentShape(Rectangle())
        .background(isSelected ? Color.accentColor.opacity(0.1) : Color.clear)
        .onTapGesture {
            withAnimation(.easeInOut(duration: 0.15)) {
                if selectedVersionID == version.id {
                    selectedVersionID = nil
                } else {
                    selectedVersionID = version.id
                    renamingVersionID = nil
                }
            }
        }
    }

    // MARK: - Actions

    private func refreshVersions() {
        guard let url = document.fileURL else {
            versions = []
            return
        }
        versions = VersionStore.shared.versions(forFile: url.path)
    }

    private func restoreVersion(_ version: VersionStore.Version) {
        // Save current state as a version first (so nothing is lost)
        if let url = document.fileURL {
            let html = document.htmlContent
            if EditorViewModel.hasSubstantialContent(html) {
                VersionStore.shared.saveVersion(
                    filePath: url.path,
                    htmlContent: html,
                    wordCount: document.wordCount
                )
            }
        }

        // Load the old version's content into the editor
        document.htmlContent = version.htmlContent
        document.isDirty = true
        editorViewModel.loadContent(version.htmlContent)
        refreshVersions()
    }

    private func saveNamedVersion() {
        guard let url = document.fileURL else { return }
        let name = namedVersionName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }

        editorViewModel.getContent { html in
            let content = html.isEmpty ? document.htmlContent : html
            VersionStore.shared.saveVersion(
                filePath: url.path,
                htmlContent: content,
                wordCount: document.wordCount,
                name: name
            )
            refreshVersions()
        }
        namedVersionName = ""
    }

    private func nameUnnamedVersion(_ version: VersionStore.Version) {
        namedVersionName = ""
        // Reuse the save-named alert but redirect to renaming
        showSaveNamedAlert = true
        // After dismiss, the save action will create a new named version
        // Instead, let's directly rename this version
        // We'll use a different approach - set renaming state
        renamingVersionID = version.id
        renameText = ""
        showSaveNamedAlert = false
    }

    private func commitRename(_ version: VersionStore.Version) {
        let name = renameText.trimmingCharacters(in: .whitespacesAndNewlines)
        if name.isEmpty {
            VersionStore.shared.nameVersion(id: version.id, name: nil)
        } else {
            VersionStore.shared.nameVersion(id: version.id, name: name)
        }
        renamingVersionID = nil
        refreshVersions()
    }

    private func confirmDelete() {
        guard let id = deleteTargetID else { return }
        VersionStore.shared.deleteVersion(id: id)
        if selectedVersionID == id { selectedVersionID = nil }
        deleteTargetID = nil
        refreshVersions()
    }

    // MARK: - Formatting

    private func formattedDate(_ date: Date) -> String {
        let cal = Calendar.current
        if cal.isDateInToday(date) { return "Today" }
        if cal.isDateInYesterday(date) { return "Yesterday" }
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: date)
    }

    private func formattedTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    private func formattedDateTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}
