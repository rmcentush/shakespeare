import SwiftUI

@MainActor
private enum RecoveryDraftPresentationCoordinator {
    private static var presentingWindowID: UUID?
    private static var didOfferThisLaunch = false

    static func claim(for windowID: UUID) -> Bool {
        guard !didOfferThisLaunch, presentingWindowID == nil else { return false }
        didOfferThisLaunch = true
        presentingWindowID = windowID
        return true
    }

    static func release(for windowID: UUID) {
        guard presentingWindowID == windowID else { return }
        presentingWindowID = nil
    }
}

struct ContentView: View {
    private enum SidebarPanel {
        case chat
        case suggestions
        case comments
    }

    private enum Layout {
        static let versionHistoryWidth: CGFloat = 280
        static let compactVersionHistoryWidth: CGFloat = 220
        static let sidebarWidth: CGFloat = 340
        static let compactSidebarWidth: CGFloat = 260
        static let preferredEditorWidth: CGFloat = 360
        static let dividerWidth: CGFloat = 1
        static let sidebarAnimation = Animation.interactiveSpring(
            response: 0.32,
            dampingFraction: 0.9,
            blendDuration: 0.08
        )
    }

    private struct MainLayoutWidths {
        var versionHistory: CGFloat
        var editor: CGFloat
        var sidebar: CGFloat
    }

    private struct RecoveryDraftPresentation: Identifiable {
        let id = UUID()
        let drafts: [RecoveryDraftStore.DraftMetadata]
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
    @State private var showOnboarding = false
    @State private var hasCheckedOnboarding = false
    @State private var onboardingWindowID = UUID()
    @State private var hasCheckedRecoveryDrafts = false
    @State private var recoveryDraftsLoaded = false
    @State private var presentRecoveryWhenLoaded = false
    @State private var recoveryDrafts: [RecoveryDraftStore.DraftMetadata] = []
    @State private var recoveryDraftPresentation: RecoveryDraftPresentation?

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
                        .help("Toggle Research Chat (Cmd+\\)")
                    }
                    ToolbarItem(placement: .automatic) {
                        Button {
                            if editorViewModel.selectionState.hasSelection {
                                editorViewModel.addComment()
                                withAnimation(Layout.sidebarAnimation) {
                                    activeSidebar = .comments
                                }
                            } else {
                                toggleSidebar(.comments)
                            }
                        } label: {
                            Image(systemName: activeSidebar == .comments ? "quote.bubble.fill" : "quote.bubble")
                        }
                        .help(editorViewModel.selectionState.hasSelection ? "Add Comment (Cmd+Shift+M)" : "Toggle Comments")
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
            .onReceive(NotificationCenter.default.publisher(for: .editorContentUpdated, object: editorViewModel)) { notification in
                guard let html = notification.userInfo?["html"] as? String,
                      let text = notification.userInfo?["text"] as? String,
                      let words = notification.userInfo?["words"] as? Int,
                      let characters = notification.userInfo?["characters"] as? Int
                else { return }
                let contentChanged = document.syncFromEditor(
                    html: html,
                    plainText: text,
                    words: words,
                    characters: characters
                )
                if contentChanged {
                    editorViewModel.schedulePersistence(document: document)
                    editorViewModel.scheduleAmbientReview()
                    editorViewModel.scheduleGrammarCheck()
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .editorDocumentMutated, object: editorViewModel)) { _ in
                document.markEditorMutation()
                editorViewModel.schedulePersistence(document: document)
            }
            .onReceive(NotificationCenter.default.publisher(for: .editorCommentActivated, object: editorViewModel)) { _ in
                withAnimation(Layout.sidebarAnimation) {
                    activeSidebar = .comments
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .editorBecameReady, object: editorViewModel)) { _ in
                editorViewModel.loadSnapshot(document.currentSnapshot())
                editorViewModel.scheduleGrammarCheck(delay: 5)
            }
            .onReceive(NotificationCenter.default.publisher(for: .grammarCheckingSettingsChanged)) { _ in
                editorViewModel.grammarCheckingSettingsDidChange()
            }
            .onReceive(NotificationCenter.default.publisher(for: .fontSettingsChanged)) { _ in
                let appearance = UserDefaults.standard.string(forKey: "editorAppearance") ?? "system"
                let css = FontManager.shared.themedCSS(for: appearance)
                editorViewModel.setThemeCSS(css)
            }
            .onDisappear {
                editorViewModel.flushPendingChanges(document: document)
                OnboardingSettings.releasePresentation(for: onboardingWindowID)
                RecoveryDraftPresentationCoordinator.release(for: onboardingWindowID)
            }
            .onAppear {
                guard !hasCheckedOnboarding else { return }
                hasCheckedOnboarding = true
                let willPresentOnboarding = OnboardingSettings.shouldPresent
                    && OnboardingSettings.claimPresentation(for: onboardingWindowID)
                if willPresentOnboarding {
                    DispatchQueue.main.async {
                        showOnboarding = true
                    }
                }
                loadRecoveryDrafts(presentWhenReady: !willPresentOnboarding)
            }
            .onReceive(NotificationCenter.default.publisher(for: .showOnboarding, object: editorViewModel)) { _ in
                showOnboarding = true
            }
            .sheet(isPresented: $showOnboarding, onDismiss: {
                OnboardingSettings.markCompleted()
                OnboardingSettings.releasePresentation(for: onboardingWindowID)
                editorViewModel.focusEditor()
                presentRecoveryDraftsIfAvailable()
            }) {
                OnboardingView(
                    onFinish: {
                        showOnboarding = false
                    },
                    onOpenDocument: {
                        showOnboarding = false
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                            editorViewModel.openDocument(document: document)
                        }
                    }
                )
            }
            .sheet(item: $recoveryDraftPresentation, onDismiss: {
                RecoveryDraftPresentationCoordinator.release(for: onboardingWindowID)
                editorViewModel.focusEditor()
            }) { presentation in
                RecoveryDraftsView(
                    drafts: presentation.drafts,
                    onRecover: { draft in
                        recoveryDraftPresentation = nil
                        editorViewModel.recoverDraft(draft, document: document)
                    },
                    onDiscard: { draft in
                        discardRecoveryDraft(draft)
                    },
                    onClose: {
                        recoveryDraftPresentation = nil
                    }
                )
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
            .onReceive(NotificationCenter.default.publisher(for: .toggleFocusMode, object: editorViewModel)) { _ in
                toggleFocusMode()
            }
            .onChange(of: editorViewModel.pendingEditCount) {
                if editorViewModel.pendingEditCount == 0, activeSidebar == .suggestions {
                    withAnimation(Layout.sidebarAnimation) {
                        activeSidebar = nil
                    }
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .showSaveNamedVersion, object: editorViewModel)) { _ in
                // Open version history panel and trigger the naming alert
                withAnimation(.easeInOut(duration: 0.15)) {
                    showVersionHistory = true
                }
                showNamedVersionAlert = true
            }
    }

    private var mainLayout: some View {
        GeometryReader { proxy in
            let widths = mainLayoutWidths(for: proxy.size.width)

            HStack(spacing: 0) {
                if showVersionHistory && !isDistractionFree {
                    VersionHistoryView()
                        .frame(width: widths.versionHistory)
                        .transition(.move(edge: .leading).combined(with: .opacity))
                    Divider()
                }

                editorColumn
                    .frame(width: widths.editor)
                    .frame(maxHeight: .infinity)
                    .clipped()

                if let activeSidebar, !isDistractionFree {
                    Divider()
                    sidebarView(for: activeSidebar)
                        .frame(width: widths.sidebar)
                        .transition(.move(edge: .trailing))
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .leading)
            .clipped()
            .animation(Layout.sidebarAnimation, value: activeSidebar)
        }
    }

    private var editorColumn: some View {
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
                            activeEdit: editorViewModel.activePendingEdit,
                            onFocusPrevious: { editorViewModel.focusPreviousPendingEdit() },
                            onFocusNext: { editorViewModel.focusNextPendingEdit() },
                            onAcceptCurrent: { editorViewModel.acceptActivePendingEdit() },
                            onRejectCurrent: { editorViewModel.rejectActivePendingEdit() },
                            onReview: { toggleSidebar(.suggestions) }
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
    }

    @ViewBuilder
    private func sidebarView(for panel: SidebarPanel) -> some View {
        switch panel {
        case .chat:
            AssistantChatView()
        case .suggestions:
            PendingEditsSidebarView()
        case .comments:
            CommentsSidebarView()
        }
    }

    private func mainLayoutWidths(for totalWidth: CGFloat) -> MainLayoutWidths {
        let showsVersionHistory = showVersionHistory && !isDistractionFree
        let showsSidebar = activeSidebar != nil && !isDistractionFree
        let dividerCount = (showsVersionHistory ? 1 : 0) + (showsSidebar ? 1 : 0)
        let availableWidth = max(totalWidth - CGFloat(dividerCount) * Layout.dividerWidth, 0)

        guard showsVersionHistory || showsSidebar else {
            return MainLayoutWidths(versionHistory: 0, editor: availableWidth, sidebar: 0)
        }

        var versionHistoryWidth = showsVersionHistory ? Layout.versionHistoryWidth : 0
        var sidebarWidth = showsSidebar ? Layout.sidebarWidth : 0
        let desiredPanelWidth = versionHistoryWidth + sidebarWidth
        let maximumPanelWidth = max(availableWidth - Layout.preferredEditorWidth, 0)

        if desiredPanelWidth > maximumPanelWidth {
            let versionShrinkCapacity = showsVersionHistory ? Layout.versionHistoryWidth - Layout.compactVersionHistoryWidth : 0
            let sidebarShrinkCapacity = showsSidebar ? Layout.sidebarWidth - Layout.compactSidebarWidth : 0
            let shrinkCapacity = versionShrinkCapacity + sidebarShrinkCapacity

            if shrinkCapacity > 0 {
                let requestedShrink = desiredPanelWidth - maximumPanelWidth
                let shrinkRatio = min(requestedShrink / shrinkCapacity, 1)
                versionHistoryWidth -= versionShrinkCapacity * shrinkRatio
                sidebarWidth -= sidebarShrinkCapacity * shrinkRatio
            }
        }

        let editorWidth = max(availableWidth - versionHistoryWidth - sidebarWidth, 0)
        return MainLayoutWidths(
            versionHistory: versionHistoryWidth,
            editor: editorWidth,
            sidebar: sidebarWidth
        )
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

        // ESC closes transient UI first, otherwise rejects only the current suggestion.
        Button("") {
            if showFindBar {
                editorViewModel.clearFind()
                withAnimation(.easeInOut(duration: 0.15)) {
                    showFindBar = false
                    showReplace = false
                }
                editorViewModel.focusEditor()
            } else if editorViewModel.pendingEditCount > 0 {
                editorViewModel.rejectActivePendingEdit()
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

        // Standard editor zoom shortcuts
        Button("") { editorViewModel.zoomIn() }
            .keyboardShortcut("+", modifiers: .command)
            .hidden()

        Button("") { editorViewModel.zoomIn() }
            .keyboardShortcut("=", modifiers: .command)
            .hidden()

        Button("") { editorViewModel.zoomOut() }
            .keyboardShortcut("-", modifiers: .command)
            .hidden()

        Button("") { editorViewModel.resetZoom() }
            .keyboardShortcut("0", modifiers: .command)
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
                withAnimation(Layout.sidebarAnimation) {
                    activeSidebar = .comments
                }
            }
        }
        .keyboardShortcut("m", modifiers: [.command, .shift])
        .hidden()
    }
}

extension ContentView {
    private func loadRecoveryDrafts(presentWhenReady: Bool) {
        guard !hasCheckedRecoveryDrafts else {
            if presentWhenReady { presentRecoveryDraftsIfAvailable() }
            return
        }
        hasCheckedRecoveryDrafts = true

        Task { @MainActor in
            recoveryDrafts = (try? await RecoveryDraftStore.shared.availableDrafts()) ?? []
            recoveryDraftsLoaded = true
            if presentWhenReady || presentRecoveryWhenLoaded {
                presentRecoveryWhenLoaded = false
                presentRecoveryDraftsIfAvailable()
            }
        }
    }

    private func presentRecoveryDraftsIfAvailable() {
        guard recoveryDraftsLoaded else {
            presentRecoveryWhenLoaded = true
            return
        }
        guard !recoveryDrafts.isEmpty,
              document.fileURL == nil,
              !document.isDirty,
              !showOnboarding,
              RecoveryDraftPresentationCoordinator.claim(for: onboardingWindowID)
        else { return }
        recoveryDraftPresentation = RecoveryDraftPresentation(drafts: recoveryDrafts)
    }

    private func discardRecoveryDraft(_ draft: RecoveryDraftStore.DraftMetadata) {
        editorViewModel.discardRecoveryDraft(draft)
        recoveryDrafts.removeAll { $0.id == draft.id }
        recoveryDraftPresentation = recoveryDrafts.isEmpty
            ? nil
            : RecoveryDraftPresentation(drafts: recoveryDrafts)
    }

    private func toggleSidebar(_ panel: SidebarPanel) {
        withAnimation(Layout.sidebarAnimation) {
            activeSidebar = activeSidebar == panel ? nil : panel
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
        let window = editorViewModel.webView?.window ?? NSApp.mainWindow
        withAnimation(.easeInOut(duration: 0.3)) {
            isDistractionFree.toggle()
        }
        if isDistractionFree {
            window?.toggleFullScreen(nil)
        } else if let window, window.styleMask.contains(.fullScreen) {
            window.toggleFullScreen(nil)
        }
    }
}

extension Notification.Name {
    static let toggleFocusMode = Notification.Name("toggleFocusMode")
    static let editorDocumentMutated = Notification.Name("editorDocumentMutated")
    static let editorCommentActivated = Notification.Name("editorCommentActivated")
}

struct PendingEditsBar: View {
    let count: Int
    let currentIndex: Int
    let activeEdit: EditorViewModel.PendingEdit?
    let onFocusPrevious: () -> Void
    let onFocusNext: () -> Void
    let onAcceptCurrent: () -> Void
    let onRejectCurrent: () -> Void
    let onReview: () -> Void

    private var editLabel: String {
        if count == 1 { return "Edit 1 of 1" }
        if let activeEdit { return "Edit \(activeEdit.index + 1) of \(count)" }
        if currentIndex >= 0 { return "Edit \(currentIndex + 1) of \(count)" }
        return "\(count) edits"
    }

    private var detailLabel: String {
        guard let activeEdit else { return "No active suggestion" }
        return "\(activeEdit.status == .pending ? "Pending" : "Conflict") - \(activeEdit.source)"
    }

    private var changePreview: String {
        guard let activeEdit else { return "" }
        let original = compactPreview(
            activeEdit.originalText.isEmpty ? "Insert at cursor" : activeEdit.originalText
        )
        let replacement = compactPreview(
            activeEdit.replacementText.isEmpty
                ? (activeEdit.status == .conflicted ? "Cannot apply safely" : "Delete")
                : activeEdit.replacementText
        )
        return "\(original) -> \(replacement)"
    }

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "pencil.and.outline")
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.orange)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(editLabel)
                        .font(.system(size: 13, weight: .semibold))
                    Text(detailLabel)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.secondary)
                }

                if !changePreview.isEmpty {
                    Text(changePreview)
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            .frame(maxWidth: 360, alignment: .leading)
            .layoutPriority(1)

            Divider()
                .frame(height: 14)

            HStack(spacing: 4) {
                Button(action: onFocusPrevious) {
                    Text("Prev")
                        .font(.system(size: 11, weight: .medium))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(count <= 1)

                Button(action: onFocusNext) {
                    Text("Next")
                        .font(.system(size: 11, weight: .medium))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(count <= 1)

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
                .disabled(!(activeEdit?.canAccept ?? false))

                Button(action: onRejectCurrent) {
                    Text("Reject")
                        .font(.system(size: 12, weight: .medium))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(!(activeEdit?.canReject ?? false))
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
                Text("reject current")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }
            HStack(spacing: 4) {
                KeyHint("Esc")
                Text("reject current")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10))
        .shadow(color: .black.opacity(0.15), radius: 8, y: 2)
    }

    private func compactPreview(_ text: String) -> String {
        let normalized = text
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard normalized.count > 80 else { return normalized }
        let end = normalized.index(normalized.startIndex, offsetBy: 80)
        return "\(normalized[..<end])..."
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
            proofreadingStatus
            if !editorViewModel.persistenceStatusText.isEmpty {
                Text(editorViewModel.persistenceStatusText)
                    .font(.caption)
                    .foregroundColor(editorViewModel.persistenceStatusIsError ? .red : .secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
        .background(.bar)
    }

    @ViewBuilder
    private var proofreadingStatus: some View {
        if editorViewModel.proofreadingStatus == "error" {
            Image(systemName: "exclamationmark.triangle")
                .foregroundStyle(.red)
                .help(editorViewModel.proofreadingErrorMessage.isEmpty
                    ? "The local proofreader could not start."
                    : editorViewModel.proofreadingErrorMessage)
        } else if editorViewModel.proofreadingIssueCount > 0 {
            Text("\(editorViewModel.proofreadingIssueCount) writing issue\(editorViewModel.proofreadingIssueCount == 1 ? "" : "s")")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}
