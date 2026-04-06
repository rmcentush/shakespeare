import SwiftUI

struct ContentView: View {
    private enum SidebarPanel {
        case chat
        case orality
        case suggestions
        case comments
    }

    @Environment(DocumentModel.self) private var document
    @Environment(EditorViewModel.self) private var editorViewModel
    @State private var activeSidebar: SidebarPanel?
    @State private var isDistractionFree = false
    @State private var showFindBar = false
    @State private var showReplace = false
    @State private var findBarFocusRequest = 0
    @State private var showVersionHistory = false
    @State private var showNamedVersionAlert = false
    @State private var namedVersionName = ""
    @State private var oralityRequestID = 0

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
                            toggleSidebar(.chat)
                        } label: {
                            Image(systemName: "bubble.right")
                        }
                        .help("Toggle Claude (Cmd+\\)")
                    }
                    ToolbarItem(placement: .automatic) {
                        Button {
                            toggleOralityPanel()
                        } label: {
                            Text("A")
                                .font(.system(size: 13, weight: .bold, design: .serif))
                        }
                        .help("Toggle Orality Sidebar")
                    }
                    ToolbarItem(placement: .automatic) {
                        Button {
                            toggleSidebar(.comments)
                        } label: {
                            Image(systemName: activeSidebar == .comments ? "quote.bubble.fill" : "quote.bubble")
                        }
                        .help("Toggle Comments (Cmd+Shift+M)")
                    }
                    if editorViewModel.pendingEditCount > 0 {
                        ToolbarItem(placement: .automatic) {
                            Button {
                                toggleSidebar(.suggestions)
                            } label: {
                                Image(systemName: activeSidebar == .suggestions ? "list.bullet.rectangle.portrait.fill" : "list.bullet.rectangle.portrait")
                            }
                            .help("Review Suggestions")
                        }
                    }
                }
            }
            .background { keyboardShortcuts }
            .onReceive(NotificationCenter.default.publisher(for: .editorContentUpdated)) { notification in
                if let html = notification.userInfo?["html"] as? String,
                   let text = notification.userInfo?["text"] as? String,
                   let words = notification.userInfo?["words"] as? Int,
                   let characters = notification.userInfo?["characters"] as? Int {
                    document.syncFromEditor(html: html, plainText: text, words: words, characters: characters)
                } else if let html = notification.userInfo?["html"] as? String {
                    document.updateContent(html)
                } else if let words = notification.userInfo?["words"] as? Int,
                          let characters = notification.userInfo?["characters"] as? Int {
                    document.markEditorActivity(words: words, characters: characters)
                }
                editorViewModel.scheduleAutoSave(document: document)
            }
            .onReceive(NotificationCenter.default.publisher(for: .editorBecameReady)) { _ in
                editorViewModel.loadSnapshot(document.currentSnapshot())
            }
            .onReceive(NotificationCenter.default.publisher(for: .fontSettingsChanged)) { _ in
                let appearance = UserDefaults.standard.string(forKey: "editorAppearance") ?? "system"
                let css = FontManager.shared.themedCSS(for: appearance)
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
            .onChange(of: editorViewModel.pendingEditCount) {
                if editorViewModel.pendingEditCount == 0, activeSidebar == .suggestions {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        activeSidebar = nil
                    }
                }
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
                    FindBarView(
                        isVisible: $showFindBar,
                        showReplace: $showReplace,
                        focusRequest: findBarFocusRequest
                    )
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
                                canAcceptCurrent: editorViewModel.activePendingEdit?.canAccept ?? false,
                                onFocusPrevious: { editorViewModel.focusPreviousPendingEdit() },
                                onFocusNext: { editorViewModel.focusNextPendingEdit() },
                                onAcceptCurrent: { editorViewModel.acceptActivePendingEdit() },
                                onRejectCurrent: { editorViewModel.rejectActivePendingEdit() },
                                onReview: { toggleSidebar(.suggestions) },
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

            if let activeSidebar, !isDistractionFree {
                Divider()
                Group {
                    switch activeSidebar {
                    case .chat:
                        ClaudeChatView()
                    case .orality:
                        OralityView(requestID: oralityRequestID)
                    case .suggestions:
                        PendingEditsSidebarView()
                    case .comments:
                        CommentsSidebarView()
                    }
                }
                .frame(width: 340)
                .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
    }

    @ViewBuilder
    private var keyboardShortcuts: some View {
        // Cmd+\ to toggle sidebar
        Button("") {
            toggleSidebar(.chat)
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
                editorViewModel.focusEditor()
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
                findBarFocusRequest += 1
            }
        }
        .keyboardShortcut("f", modifiers: .command)
        .hidden()

        // Cmd+Option+F for find & replace
        Button("") {
            withAnimation(.easeInOut(duration: 0.15)) {
                showFindBar = true
                showReplace = true
                findBarFocusRequest += 1
            }
        }
        .keyboardShortcut("f", modifiers: [.command, .option])
        .hidden()

        // Cmd+Shift+M to add comment
        Button("") {
            if editorViewModel.selectionState.hasSelection {
                editorViewModel.addComment()
                withAnimation(.easeInOut(duration: 0.15)) {
                    activeSidebar = .comments
                }
            }
        }
        .keyboardShortcut("m", modifiers: [.command, .shift])
        .hidden()
    }
}

extension ContentView {
    private func toggleSidebar(_ panel: SidebarPanel) {
        withAnimation(.easeInOut(duration: 0.15)) {
            activeSidebar = activeSidebar == panel ? nil : panel
        }
    }

    func toggleOralityPanel() {
        withAnimation(.easeInOut(duration: 0.15)) {
            if activeSidebar == .orality {
                activeSidebar = nil
            } else {
                activeSidebar = .orality
                oralityRequestID += 1
            }
        }
    }

    func saveNamedVersionFromMenu() {
        guard let url = document.fileURL else { return }
        let name = namedVersionName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        Task {
            let snapshot = await editorViewModel.latestSnapshot(for: document)
            VersionStore.shared.saveVersion(filePath: url.path, snapshot: snapshot, name: name)
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
    let canAcceptCurrent: Bool
    let onFocusPrevious: () -> Void
    let onFocusNext: () -> Void
    let onAcceptCurrent: () -> Void
    let onRejectCurrent: () -> Void
    let onReview: () -> Void
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
                Button(action: onFocusPrevious) {
                    Text("Prev")
                        .font(.system(size: 11, weight: .medium))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Button(action: onFocusNext) {
                    Text("Next")
                        .font(.system(size: 11, weight: .medium))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Button(action: onReview) {
                    Text("Review")
                        .font(.system(size: 11, weight: .medium))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }

            Divider()
                .frame(height: 14)

            HStack(spacing: 4) {
                Button(action: onAcceptCurrent) {
                    Text("Accept")
                        .font(.system(size: 12, weight: .medium))
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)
                .controlSize(.small)
                .disabled(!canAcceptCurrent)

                Button(action: onRejectCurrent) {
                    Text("Reject")
                        .font(.system(size: 12, weight: .medium))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }

            Divider()
                .frame(height: 14)

            HStack(spacing: 4) {
                KeyHint("Tab")
                Text("accept current")
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

            Button(action: onRejectAll) {
                Text("Reject All")
                    .font(.system(size: 12, weight: .medium))
            }
            .buttonStyle(.bordered)
            .controlSize(.small)

            Button(action: onAcceptAll) {
                Text("Accept All")
                    .font(.system(size: 12, weight: .medium))
            }
            .buttonStyle(.borderedProminent)
            .tint(.green)
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
    @Environment(EditorViewModel.self) private var editorViewModel

    var body: some View {
        HStack {
            if editorViewModel.selectionState.hasSelection {
                Text("Selected \(editorViewModel.selectionState.selectedWords) words")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.primary)
                Text("\u{00B7}")
                    .foregroundStyle(.quaternary)
                Text("\(editorViewModel.selectionState.selectedCharacters) characters")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("\u{00B7}")
                    .foregroundStyle(.quaternary)
            }
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
