import SwiftUI

struct ContentView: View {
    @Environment(DocumentModel.self) private var document
    @Environment(EditorViewModel.self) private var editorViewModel
    @State private var showSidebar = false
    @State private var isDistractionFree = false
    @State private var showFindBar = false
    @State private var showReplace = false
    @State private var showVersionHistory = false
    @State private var showNamedVersionAlert = false
    @State private var namedVersionName = ""

    var body: some View {
        mainLayout
            .navigationTitle(document.windowTitle)
            .toolbar(isDistractionFree ? .hidden : .automatic)
            .toolbar {
                if !isDistractionFree {
                    ToolbarItem(placement: .automatic) {
                        Button {
                            withAnimation(.easeInOut(duration: 0.15)) {
                                showVersionHistory.toggle()
                            }
                        } label: {
                            Image(systemName: "clock.arrow.circlepath")
                        }
                        .help("Version History (Cmd+Shift+V)")
                    }
                    ToolbarItem(placement: .automatic) {
                        Button {
                            withAnimation(.easeInOut(duration: 0.15)) {
                                showSidebar.toggle()
                            }
                        } label: {
                            Image(systemName: "bubble.right")
                        }
                        .help("Toggle Claude (Cmd+\\)")
                    }
                }
            }
            .background { keyboardShortcuts }
            .onReceive(NotificationCenter.default.publisher(for: .editorContentUpdated)) { notification in
                if let html = notification.userInfo?["html"] as? String,
                   let words = notification.userInfo?["words"] as? Int,
                   let characters = notification.userInfo?["characters"] as? Int {
                    document.syncFromEditor(html: html, words: words, characters: characters)
                } else if let html = notification.userInfo?["html"] as? String {
                    document.updateContent(html)
                } else if let words = notification.userInfo?["words"] as? Int,
                          let characters = notification.userInfo?["characters"] as? Int {
                    document.updateWordCount(words: words, characters: characters)
                }
                editorViewModel.scheduleAutoSave(document: document)
            }
            .onReceive(NotificationCenter.default.publisher(for: .editorBecameReady)) { _ in
                // Reload document content when the editor (re)initializes.
                // This handles: web process restart, and any other editor reload scenario
                // where the JS context was reset but document.htmlContent still has content.
                editorViewModel.loadContent(document.htmlContent)
            }
            .onReceive(NotificationCenter.default.publisher(for: .fontSettingsChanged)) { _ in
                let css = FontManager.shared.fullThemeCSS()
                editorViewModel.setThemeCSS(css)
            }
            .onDisappear {
                editorViewModel.flushPendingChanges(document: document)
            }
            .alert("Save Named Version", isPresented: $showNamedVersionAlert) {
                TextField("Version name", text: $namedVersionName)
                Button("Save") {
                    saveNamedVersionFromMenu()
                }
                Button("Cancel", role: .cancel) { namedVersionName = "" }
            } message: {
                Text("Give this version a name (e.g. \"Draft 1\", \"Final\")")
            }
            .onReceive(NotificationCenter.default.publisher(for: .toggleFocusMode)) { _ in
                toggleFocusMode()
            }
            .onReceive(NotificationCenter.default.publisher(for: .showSaveNamedVersion)) { _ in
                // Open version history panel and trigger the naming alert
                withAnimation(.easeInOut(duration: 0.15)) {
                    showVersionHistory = true
                }
                showNamedVersionAlert = true
            }
    }

    private var mainLayout: some View {
        HStack(spacing: 0) {
            if showVersionHistory && !isDistractionFree {
                VersionHistoryView()
                    .transition(.move(edge: .leading).combined(with: .opacity))
                Divider()
            }
            VStack(spacing: 0) {
                if !isDistractionFree {
                    ToolbarView()
                }
                if showFindBar {
                    FindBarView(isVisible: $showFindBar, showReplace: $showReplace)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
                ZStack {
                    EditorWebView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    if isDistractionFree {
                        VStack {
                            HStack {
                                Spacer()
                                Button {
                                    toggleFocusMode()
                                } label: {
                                    Image(systemName: "arrow.down.right.and.arrow.up.left")
                                        .font(.system(size: 14))
                                        .foregroundColor(.secondary)
                                        .padding(8)
                                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 6))
                                }
                                .buttonStyle(.plain)
                                .padding(12)
                                .help("Exit Focus Mode (Cmd+Shift+F or Esc)")
                            }
                            Spacer()
                        }
                    }
                    if editorViewModel.pendingEditCount > 0 {
                        VStack {
                            Spacer()
                            PendingEditsBar(
                                count: editorViewModel.pendingEditCount,
                                currentIndex: editorViewModel.pendingEditCurrentIndex,
                                onAcceptAll: { editorViewModel.acceptAllPendingEdits() },
                                onRejectAll: { editorViewModel.rejectAllPendingEdits() }
                            )
                            .padding(.bottom, 12)
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                        }
                        .animation(.easeInOut(duration: 0.2), value: editorViewModel.pendingEditCount)
                    }
                }
                if !isDistractionFree {
                    StatusBarView()
                }
            }

            if showSidebar && !isDistractionFree {
                Divider()
                ClaudeChatView()
                    .frame(width: 340)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
    }

    @ViewBuilder
    private var keyboardShortcuts: some View {
        // Cmd+\ to toggle sidebar
        Button("") {
            withAnimation(.easeInOut(duration: 0.15)) { showSidebar.toggle() }
        }
        .keyboardShortcut("\\", modifiers: .command)
        .hidden()

        // Cmd+Shift+F for focus mode
        Button("") { toggleFocusMode() }
            .keyboardShortcut("f", modifiers: [.command, .shift])
            .hidden()

        // ESC exits find bar or focus mode
        Button("") {
            if showFindBar {
                editorViewModel.clearFind()
                withAnimation(.easeInOut(duration: 0.15)) {
                    showFindBar = false
                    showReplace = false
                }
            } else if isDistractionFree {
                toggleFocusMode()
            }
        }
        .keyboardShortcut(.escape, modifiers: [])
        .hidden()

        // Cmd+Shift+V for version history
        Button("") {
            withAnimation(.easeInOut(duration: 0.15)) { showVersionHistory.toggle() }
        }
        .keyboardShortcut("v", modifiers: [.command, .shift])
        .hidden()

        // Cmd+F to open find bar
        Button("") {
            withAnimation(.easeInOut(duration: 0.15)) {
                showFindBar = true
                showReplace = false
            }
        }
        .keyboardShortcut("f", modifiers: .command)
        .hidden()

        // Cmd+Option+F for find & replace
        Button("") {
            withAnimation(.easeInOut(duration: 0.15)) {
                showFindBar = true
                showReplace = true
            }
        }
        .keyboardShortcut("f", modifiers: [.command, .option])
        .hidden()
    }
}

extension ContentView {
    func saveNamedVersionFromMenu() {
        guard let url = document.fileURL else { return }
        let name = namedVersionName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        Task {
            let snapshot = await editorViewModel.latestSnapshot(for: document)
            VersionStore.shared.saveVersion(
                filePath: url.path,
                htmlContent: snapshot.htmlContent,
                wordCount: snapshot.wordCount,
                name: name
            )
        }
        namedVersionName = ""
    }

    func toggleFocusMode() {
        withAnimation(.easeInOut(duration: 0.3)) {
            isDistractionFree.toggle()
        }
        if isDistractionFree {
            NSApp.mainWindow?.toggleFullScreen(nil)
        } else {
            if let window = NSApp.mainWindow, window.styleMask.contains(.fullScreen) {
                window.toggleFullScreen(nil)
            }
        }
    }
}

extension Notification.Name {
    static let toggleFocusMode = Notification.Name("toggleFocusMode")
}

struct PendingEditsBar: View {
    let count: Int
    let currentIndex: Int
    let onAcceptAll: () -> Void
    let onRejectAll: () -> Void

    private var editLabel: String {
        if count == 1 { return "1 edit" }
        if currentIndex >= 0 { return "Edit \(currentIndex + 1) of \(count)" }
        return "\(count) edits"
    }

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "pencil.and.outline")
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.orange)

            Text(editLabel)
                .font(.system(size: 13, weight: .medium))

            Divider()
                .frame(height: 14)

            HStack(spacing: 4) {
                KeyHint("Tab")
                Text("accept")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }
            HStack(spacing: 4) {
                KeyHint("Shift+Tab")
                Text("reject")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }
            HStack(spacing: 4) {
                KeyHint("Esc")
                Text("reject all")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }

            Divider()
                .frame(height: 14)

            Button(action: onAcceptAll) {
                Text("Accept All")
                    .font(.system(size: 12, weight: .medium))
            }
            .buttonStyle(.borderedProminent)
            .tint(.green)
            .controlSize(.small)

            Button(action: onRejectAll) {
                Text("Reject All")
                    .font(.system(size: 12, weight: .medium))
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10))
        .shadow(color: .black.opacity(0.15), radius: 8, y: 2)
    }
}

struct KeyHint: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text)
            .font(.system(size: 10, weight: .medium, design: .rounded))
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(Color.primary.opacity(0.08), in: RoundedRectangle(cornerRadius: 4))
            .foregroundColor(.secondary)
    }
}

struct StatusBarView: View {
    @Environment(DocumentModel.self) private var document

    var body: some View {
        HStack {
            Text("\(document.wordCount) words")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text("\u{00B7}")
                .foregroundStyle(.quaternary)
            Text("\(document.characterCount) characters")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
        .background(.bar)
    }
}
