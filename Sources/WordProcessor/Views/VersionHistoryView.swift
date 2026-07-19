import SwiftUI

struct VersionHistoryView: View {
    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter
    }()

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter
    }()

    private static let dateTimeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()

    @Environment(DocumentModel.self) private var document
    @Environment(EditorViewModel.self) private var editorViewModel
    @State private var versions: [VersionStore.VersionSummary] = []
    @State private var selectedVersionID: Int64?
    @State private var refreshTask: Task<Void, Never>?
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
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.background)
        .onAppear { refreshVersions() }
        .onChange(of: document.fileURL) { refreshVersions() }
        .onDisappear { refreshTask?.cancel() }
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

    private func versionRow(_ version: VersionStore.VersionSummary) -> some View {
        let isSelected = selectedVersionID == version.id
        return VStack(alignment: .leading, spacing: 4) {
            HStack {
                if renamingVersionID == version.id {
                    TextField("Name", text: $renameText, onCommit: {
                        commitRename(version)
                    })
                    .textFieldStyle(.plain)
                    .font(.subheadline.weight(.semibold))
                } else if version.isNamed {
                    Text(version.versionName ?? "")
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                } else {
                    Text(formattedDate(version.createdAt))
                        .font(.subheadline)
                        .lineLimit(1)
                }

                if version.isNamed {
                    Image(systemName: "bookmark.fill")
                        .font(.caption2)
                        .foregroundStyle(.orange)
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
                    .help("Delete Version")
                    .accessibilityLabel("Delete Version")
                }
                .padding(.top, 4)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .contentShape(Rectangle())
        .background(isSelected ? Color.accentColor.opacity(0.1) : Color.clear)
        .onTapGesture {
            toggleVersionSelection(version)
        }
        .focusable()
        .onKeyPress(.return) {
            toggleVersionSelection(version)
            return .handled
        }
        .accessibilityAddTraits(.isButton)
        .accessibilityAction {
            toggleVersionSelection(version)
        }
    }

    private func toggleVersionSelection(_ version: VersionStore.VersionSummary) {
        withAnimation(.easeInOut(duration: 0.15)) {
            if selectedVersionID == version.id {
                selectedVersionID = nil
            } else {
                selectedVersionID = version.id
                renamingVersionID = nil
            }
        }
    }

    // MARK: - Actions

    private func refreshVersions() {
        refreshTask?.cancel()
        guard let url = document.fileURL else {
            versions = []
            return
        }
        let filePath = url.path
        let documentID = document.documentID
        refreshTask = Task {
            do {
                let loaded = try await VersionStore.shared.versionSummaries(
                    forFile: filePath,
                    documentID: documentID
                )
                guard !Task.isCancelled, document.fileURL?.path == filePath else { return }
                versions = loaded
            } catch {
                guard !Task.isCancelled else { return }
                editorViewModel.reportPersistenceFailure("Load version history", error: error)
            }
        }
    }

    private func restoreVersion(_ summary: VersionStore.VersionSummary) {
        Task { @MainActor in
            do {
                guard let version = try await VersionStore.shared.version(id: summary.id) else { return }
                guard let currentSnapshot = await editorViewModel.latestSnapshot(for: document) else { return }

                // Save the current content and assets first so restore is always reversible.
                if let url = document.fileURL {
                    let sameJSON = currentSnapshot.canonicalJSON == version.canonicalJSON
                    let sameHTML = currentSnapshot.htmlContent == version.htmlContent
                    if !sameJSON || !sameHTML {
                        try await editorViewModel.saveVersionSnapshot(
                            currentSnapshot,
                            documentURL: url
                        )
                    }
                }

                let snapshot = DocumentFileStore.FileSnapshot(
                    canonicalJSON: version.canonicalJSON,
                    htmlContent: version.htmlContent,
                    plainText: version.plainText,
                    wordCount: version.wordCount,
                    characterCount: version.characterCount,
                    documentID: version.documentID ?? document.documentID,
                    schemaVersion: document.schemaVersion,
                    createdAt: document.createdAt,
                    modifiedAt: version.createdAt
                )
                try await editorViewModel.restoreVersionSnapshot(
                    snapshot,
                    assets: version.assets,
                    rollbackSnapshot: currentSnapshot,
                    document: document
                )
                refreshVersions()
            } catch {
                editorViewModel.reportPersistenceFailure("Restore version", error: error)
            }
        }
    }

    private func saveNamedVersion() {
        guard let url = document.fileURL else { return }
        let name = namedVersionName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }

        Task {
            do {
                guard let snapshot = await editorViewModel.latestSnapshot(for: document) else { return }
                try await editorViewModel.saveVersionSnapshot(
                    snapshot,
                    documentURL: url,
                    name: name
                )
                refreshVersions()
            } catch {
                editorViewModel.reportPersistenceFailure("Save named version", error: error)
            }
        }
        namedVersionName = ""
    }

    private func nameUnnamedVersion(_ version: VersionStore.VersionSummary) {
        renamingVersionID = version.id
        renameText = ""
    }

    private func commitRename(_ version: VersionStore.VersionSummary) {
        let name = renameText.trimmingCharacters(in: .whitespacesAndNewlines)
        renamingVersionID = nil
        Task {
            do {
                try await VersionStore.shared.nameVersion(
                    id: version.id,
                    name: name.isEmpty ? nil : name
                )
                refreshVersions()
            } catch {
                editorViewModel.reportPersistenceFailure("Rename version", error: error)
            }
        }
    }

    private func confirmDelete() {
        guard let id = deleteTargetID else { return }
        if selectedVersionID == id { selectedVersionID = nil }
        deleteTargetID = nil
        Task {
            do {
                try await VersionStore.shared.deleteVersion(id: id)
                refreshVersions()
            } catch {
                editorViewModel.reportPersistenceFailure("Delete version", error: error)
            }
        }
    }

    // MARK: - Formatting

    private func formattedDate(_ date: Date) -> String {
        let cal = Calendar.current
        if cal.isDateInToday(date) { return "Today" }
        if cal.isDateInYesterday(date) { return "Yesterday" }
        return Self.dateFormatter.string(from: date)
    }

    private func formattedTime(_ date: Date) -> String {
        Self.timeFormatter.string(from: date)
    }

    private func formattedDateTime(_ date: Date) -> String {
        Self.dateTimeFormatter.string(from: date)
    }
}
