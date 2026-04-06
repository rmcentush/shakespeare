import SwiftUI
import WebKit

@Observable
@MainActor
final class EditorViewModel {
    var webView: WKWebView?
    var isEditorReady = false
    var assetBaseURL: URL?
    var selectionState = SelectionState()
    var pendingEdits: [PendingEdit] = []
    var pendingEditCount = 0
    var pendingEditCurrentIndex = -1
    var comments: [BridgePayload.CommentData] = []
    private var autoSaveTimer: Timer?
    private var pendingSnapshot: DocumentFileStore.FileSnapshot?
    /// Incremented each time the editor signals ready (supports detecting web process restarts).
    var editorReadyCount = 0

    struct SelectionState: Equatable {
        var isBold = false
        var isItalic = false
        var isUnderline = false
        var heading = 0
        var textAlign = "left"
        var hasSelection = false
        var selectedWords = 0
        var selectedCharacters = 0
        var isLink = false
        var linkHref = ""
        var textColor = ""
        var isFootnote = false
        var footnoteText = ""

        init() {}

        init(_ state: BridgePayload.SelectionState) {
            isBold = state.isBold
            isItalic = state.isItalic
            isUnderline = state.isUnderline
            heading = state.heading
            textAlign = state.textAlign
            hasSelection = state.hasSelection
            selectedWords = state.selectedWords
            selectedCharacters = state.selectedCharacters
            isLink = state.isLink
            linkHref = state.linkHref
            textColor = state.textColor
            isFootnote = state.isFootnote
            footnoteText = state.footnoteText
        }
    }

    struct PendingEdit: Identifiable, Equatable {
        enum Status: String {
            case pending
            case conflicted
        }

        let id: String
        let groupID: String
        let kind: String
        let source: String
        let label: String
        let from: Int
        let to: Int
        let originalText: String
        let replacementText: String
        let createdAt: Date
        let status: Status
        let conflictReason: String?
        let index: Int
        let isActive: Bool
        let canAccept: Bool
        let canReject: Bool
        let canFocus: Bool

        init(_ data: BridgePayload.PendingEditData) {
            id = data.id
            groupID = data.groupID
            kind = data.kind
            source = data.source
            label = data.label
            from = data.from
            to = data.to
            originalText = data.originalText
            replacementText = data.replacementText
            createdAt = Date(timeIntervalSince1970: data.createdAt / 1000.0)
            status = Status(rawValue: data.status) ?? .pending
            conflictReason = data.conflictReason
            index = data.index
            isActive = data.isActive
            canAccept = data.canAccept
            canReject = data.canReject
            canFocus = data.canFocus
        }
    }

    // Called by bridge when JS sends a message
    func handleBridgeMessage(type: String, payload: BridgePayload) {
        switch payload {
        case .editorReady:
            isEditorReady = true
            editorReadyCount += 1
            if let snapshot = pendingSnapshot {
                pendingSnapshot = nil
                applySnapshotToEditor(snapshot)
            }
            NotificationCenter.default.post(name: .editorBecameReady, object: nil)

        case .contentChanged(let html):
            NotificationCenter.default.post(
                name: .editorContentUpdated,
                object: nil,
                userInfo: ["html": html]
            )

        case .contentUpdate(let html, let text, let words, let characters):
            NotificationCenter.default.post(
                name: .editorContentUpdated,
                object: nil,
                userInfo: [
                    "html": html,
                    "text": text,
                    "words": words,
                    "characters": characters,
                ]
            )

        case .selectionChanged(let state):
            let nextSelectionState = SelectionState(state)
            if nextSelectionState != selectionState {
                selectionState = nextSelectionState
            }

        case .wordCount(let words, let characters):
            NotificationCenter.default.post(
                name: .editorContentUpdated,
                object: nil,
                userInfo: ["words": words, "characters": characters]
            )

        case .pendingEditUpdate(let update):
            pendingEditCount = update.count
            pendingEditCurrentIndex = update.currentIndex
            pendingEdits = update.edits.map(PendingEdit.init)

        case .commentsChanged(let newComments):
            comments = newComments

        case .unknown:
            break
        }
    }

    // MARK: - Content Loading

    func loadSnapshot(_ snapshot: DocumentFileStore.FileSnapshot) {
        guard isEditorReady else {
            pendingSnapshot = snapshot
            return
        }

        pendingSnapshot = nil
        applySnapshotToEditor(snapshot)
    }

    func loadContent(_ html: String) {
        let snapshot = DocumentFileStore.FileSnapshot(
            canonicalJSON: nil,
            htmlContent: html,
            plainText: nil
        )
        loadSnapshot(snapshot)
    }

    private func applySnapshotToEditor(_ snapshot: DocumentFileStore.FileSnapshot) {
        if let canonicalJSON = snapshot.canonicalJSON, !canonicalJSON.isEmpty {
            loadJSONContent(canonicalJSON)
        } else {
            loadHTMLContent(snapshot.htmlContent)
        }
    }

    private func loadHTMLContent(_ html: String) {
        let escaped = escapeForJS(html)
        evaluateJS("window.editorAPI?.loadContent('\(escaped)')")
    }

    private func loadJSONContent(_ json: String) {
        let escaped = escapeForJS(json)
        evaluateJS("window.editorAPI?.loadJSONContent('\(escaped)')")
    }

    // MARK: - Snapshot Capture

    func getContent(completion: @escaping (String?) -> Void) {
        evaluateJS("window.editorAPI?.getContent()") { result in
            completion(result as? String)
        }
    }

    func getDocumentSnapshot(completion: @escaping (DocumentFileStore.FileSnapshot?) -> Void) {
        evaluateJS("window.editorAPI?.getDocumentSnapshot()") { [weak self] result in
            guard let jsonString = result as? String else {
                completion(nil)
                return
            }
            completion(self?.parseEditorSnapshot(from: jsonString))
        }
    }

    func applyFormat(_ command: String, value: String? = nil) {
        if let value = value {
            evaluateJS("window.editorAPI?.applyFormat('\(command)', '\(value)')")
        } else {
            evaluateJS("window.editorAPI?.applyFormat('\(command)')")
        }
    }

    func getPlainText(completion: @escaping (String) -> Void) {
        evaluateJS("window.editorAPI?.getPlainText()") { result in
            completion(result as? String ?? "")
        }
    }

    func getSelectedText(completion: @escaping (String) -> Void) {
        evaluateJS("window.editorAPI?.getSelectedText()") { result in
            completion(result as? String ?? "")
        }
    }

    func focusEditor() {
        evaluateJS("window.editorAPI?.focus()")
    }

    func setThemeCSS(_ css: String) {
        let escaped = escapeForJS(css)
        evaluateJS("window.editorAPI?.setThemeCSS('\(escaped)')")
    }

    // MARK: - Document Editing (for Claude tool use)

    func replaceSelectionHTML(_ html: String) {
        let escaped = escapeForJS(html)
        evaluateJS("window.editorAPI?.replaceSelectionHTML('\(escaped)')")
    }

    func insertHTMLAtCursor(_ html: String) {
        let escaped = escapeForJS(html)
        evaluateJS("window.editorAPI?.insertHTMLAtCursor('\(escaped)')")
    }

    func findAndReplaceText(find: String, replaceHTML: String, replaceAll: Bool, completion: @escaping (Int) -> Void) {
        let escapedFind = escapeForJS(find)
        let escapedReplace = escapeForJS(replaceHTML)
        evaluateJS("window.editorAPI?.findAndReplaceText('\(escapedFind)', '\(escapedReplace)', \(replaceAll))") { result in
            completion(result as? Int ?? 0)
        }
    }

    // MARK: - Pending Edits (Cursor-like diff review)

    func pendingReplaceSelection(id: String, html: String, completion: @escaping (Int) -> Void) {
        let escaped = escapeForJS(html)
        evaluateJS("window.editorAPI?.pendingReplaceSelection('\(id)', '\(escaped)')") { result in
            completion(result as? Int ?? 0)
        }
    }

    func pendingInsertAtCursor(id: String, html: String, completion: @escaping (Int) -> Void) {
        let escaped = escapeForJS(html)
        evaluateJS("window.editorAPI?.pendingInsertAtCursor('\(id)', '\(escaped)')") { result in
            completion(result as? Int ?? 0)
        }
    }

    func pendingFindAndReplace(id: String, find: String, replaceHTML: String, replaceAll: Bool, completion: @escaping (Int) -> Void) {
        let escapedFind = escapeForJS(find)
        let escapedReplace = escapeForJS(replaceHTML)
        evaluateJS("window.editorAPI?.pendingFindAndReplace('\(id)', '\(escapedFind)', '\(escapedReplace)', \(replaceAll))") { result in
            completion(result as? Int ?? 0)
        }
    }

    func acceptAllPendingEdits() {
        evaluateJS("window.editorAPI?.acceptAllPendingEdits()")
    }

    func rejectAllPendingEdits() {
        evaluateJS("window.editorAPI?.rejectAllPendingEdits()")
    }

    func focusPendingEdit(_ id: String) {
        let escaped = escapeForJS(id)
        evaluateJS("window.editorAPI?.focusPendingEdit('\(escaped)')")
    }

    func acceptPendingEdit(_ id: String) {
        let escaped = escapeForJS(id)
        evaluateJS("window.editorAPI?.acceptPendingEdit('\(escaped)')")
    }

    func rejectPendingEdit(_ id: String) {
        let escaped = escapeForJS(id)
        evaluateJS("window.editorAPI?.rejectPendingEdit('\(escaped)')")
    }

    // MARK: - Comments

    func addComment() {
        let id = UUID().uuidString
        evaluateJS("window.editorAPI?.addComment('\(id)')")
    }

    func updateCommentText(_ commentId: String, text: String) {
        let escapedId = escapeForJS(commentId)
        let escapedText = escapeForJS(text)
        evaluateJS("window.editorAPI?.updateCommentText('\(escapedId)', '\(escapedText)')")
    }

    func removeComment(_ commentId: String) {
        let escaped = escapeForJS(commentId)
        evaluateJS("window.editorAPI?.removeComment('\(escaped)')")
    }

    func focusComment(_ commentId: String) {
        let escaped = escapeForJS(commentId)
        evaluateJS("window.editorAPI?.focusComment('\(escaped)')")
    }

    var activePendingEdit: PendingEdit? {
        pendingEdits.first(where: \.isActive)
    }

    func focusNextPendingEdit() {
        guard !pendingEdits.isEmpty else { return }
        let currentIndex = pendingEditCurrentIndex >= 0 ? pendingEditCurrentIndex : 0
        let nextIndex = (currentIndex + 1) % pendingEdits.count
        focusPendingEdit(pendingEdits[nextIndex].id)
    }

    func focusPreviousPendingEdit() {
        guard !pendingEdits.isEmpty else { return }
        let currentIndex = pendingEditCurrentIndex >= 0 ? pendingEditCurrentIndex : 0
        let previousIndex = (currentIndex - 1 + pendingEdits.count) % pendingEdits.count
        focusPendingEdit(pendingEdits[previousIndex].id)
    }

    func acceptActivePendingEdit() {
        guard let id = activePendingEdit?.id else { return }
        acceptPendingEdit(id)
    }

    func rejectActivePendingEdit() {
        guard let id = activePendingEdit?.id else { return }
        rejectPendingEdit(id)
    }

    // MARK: - Find & Replace

    func findInDocument(_ query: String, completion: @escaping (Int) -> Void) {
        let escaped = escapeForJS(query)
        evaluateJS("window.editorAPI?.findInDocument('\(escaped)')") { result in
            completion(result as? Int ?? 0)
        }
    }

    func findNext(completion: @escaping (Int, Int) -> Void) {
        evaluateJS("window.editorAPI?.findNext()") { result in
            if let json = result as? String,
               let data = json.data(using: .utf8),
               let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                let index = dict["index"] as? Int ?? -1
                let total = dict["total"] as? Int ?? 0
                completion(index, total)
            } else {
                completion(-1, 0)
            }
        }
    }

    func findPrevious(completion: @escaping (Int, Int) -> Void) {
        evaluateJS("window.editorAPI?.findPrevious()") { result in
            if let json = result as? String,
               let data = json.data(using: .utf8),
               let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                let index = dict["index"] as? Int ?? -1
                let total = dict["total"] as? Int ?? 0
                completion(index, total)
            } else {
                completion(-1, 0)
            }
        }
    }

    func replaceOne(_ replacement: String, completion: @escaping (Int, Int) -> Void) {
        let escaped = escapeForJS(replacement)
        evaluateJS("window.editorAPI?.replaceOne('\(escaped)')") { result in
            if let json = result as? String,
               let data = json.data(using: .utf8),
               let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                let index = dict["index"] as? Int ?? -1
                let total = dict["total"] as? Int ?? 0
                completion(index, total)
            } else {
                completion(-1, 0)
            }
        }
    }

    func replaceAll(_ replacement: String, completion: @escaping (Int) -> Void) {
        let escaped = escapeForJS(replacement)
        evaluateJS("window.editorAPI?.replaceAll('\(escaped)')") { result in
            completion(result as? Int ?? 0)
        }
    }

    func clearFind() {
        evaluateJS("window.editorAPI?.clearFind()")
    }

    func latestSnapshot(for document: DocumentModel, preferEditorState: Bool = true) async -> DocumentFileStore.FileSnapshot {
        if preferEditorState, let snapshot = await captureEditorSnapshot(document: document) {
            document.syncFromEditor(snapshot: snapshot)
        }
        return document.currentSnapshot()
    }

    // MARK: - Auto-Save

    func scheduleAutoSave(document: DocumentModel) {
        autoSaveTimer?.invalidate()
        guard document.fileURL != nil else { return }
        autoSaveTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: false) { [weak self] _ in
            Task { @MainActor in
                await self?.autoSave(document: document)
            }
        }
    }

    func flushPendingChanges(document: DocumentModel) {
        Task { @MainActor in
            await flushBeforeDocumentChange(document: document)
        }
    }

    func createNewDocument(document: DocumentModel) {
        Task { @MainActor in
            await flushBeforeDocumentChange(document: document)
            document.newDocument()
            assetBaseURL = nil
            loadSnapshot(document.currentSnapshot())
        }
    }

    private func autoSave(document: DocumentModel) async {
        guard let url = document.fileURL, document.isDirty else { return }
        await persistDocument(
            document: document,
            to: url,
            captureLatestEditorState: true,
            createVersionSnapshot: false,
            actionName: "Auto-save"
        )
    }

    private func flushBeforeDocumentChange(document: DocumentModel) async {
        autoSaveTimer?.invalidate()
        autoSaveTimer = nil
        guard let url = document.fileURL, document.isDirty else { return }
        await persistDocument(
            document: document,
            to: url,
            captureLatestEditorState: true,
            createVersionSnapshot: false,
            actionName: "Flush"
        )
    }

    // MARK: - File Operations

    func openDocument(document: DocumentModel) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.shakespeareDocument, .html]
        panel.allowsMultipleSelection = false

        panel.begin { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            self?.openFile(url: url, document: document)
        }
    }

    func openFile(url: URL, document: DocumentModel) {
        Task { @MainActor in
            await flushBeforeDocumentChange(document: document)
            do {
                let snapshot = try await DocumentFileStore.shared.load(from: url)
                document.load(snapshot: snapshot, from: url)
                assetBaseURL = DocumentFileStore.isNativeDocumentURL(url) ? url : nil
                loadSnapshot(snapshot)
                VersionStore.shared.saveVersion(filePath: url.path, snapshot: snapshot)
            } catch {
                print("Failed to open file: \(error)")
            }
        }
    }

    func saveDocument(document: DocumentModel) {
        autoSaveTimer?.invalidate()
        autoSaveTimer = nil

        if let url = document.fileURL {
            Task { @MainActor in
                await persistDocument(
                    document: document,
                    to: url,
                    captureLatestEditorState: true,
                    createVersionSnapshot: true,
                    actionName: "Save"
                )
            }
        } else {
            saveDocumentAs(document: document)
        }
    }

    func saveDocumentAs(document: DocumentModel) {
        autoSaveTimer?.invalidate()
        autoSaveTimer = nil

        let panel = NSSavePanel()
        panel.allowedContentTypes = [.shakespeareDocument]
        panel.nameFieldStringValue = document.displayName + ".\(DocumentFileStore.documentPackageExtension)"

        panel.begin { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            Task { @MainActor in
                await self?.persistDocument(
                    document: document,
                    to: url,
                    captureLatestEditorState: true,
                    createVersionSnapshot: true,
                    actionName: "Save"
                )
            }
        }
    }

    func exportHTML(document: DocumentModel) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.html]
        panel.nameFieldStringValue = document.displayName + ".html"

        panel.begin { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            Task { @MainActor in
                guard let self else { return }
                let snapshot = await self.latestSnapshot(for: document)
                do {
                    _ = try await DocumentFileStore.shared.save(snapshot, to: url, sourceDocumentURL: document.fileURL)
                } catch {
                    print("HTML export failed for \(url.lastPathComponent): \(error)")
                }
            }
        }
    }

    private func persistDocument(
        document: DocumentModel,
        to url: URL,
        captureLatestEditorState: Bool,
        createVersionSnapshot: Bool,
        actionName: String
    ) async {
        let latestSnapshot = await latestSnapshot(for: document, preferEditorState: captureLatestEditorState)
        let request = document.makePersistenceRequest(snapshot: latestSnapshot)
        let sourceDocumentURL = document.fileURL

        do {
            let persistedSnapshot = try await DocumentFileStore.shared.save(
                request.snapshot,
                to: url,
                sourceDocumentURL: sourceDocumentURL
            )
            let persistedRequest = DocumentModel.PersistenceRequest(
                requestID: request.requestID,
                generation: request.generation,
                revision: request.revision,
                snapshot: persistedSnapshot
            )
            document.markSaved(url: url, request: persistedRequest)
            assetBaseURL = DocumentFileStore.isNativeDocumentURL(url) ? url : nil

            if createVersionSnapshot {
                VersionStore.shared.saveVersion(filePath: url.path, snapshot: persistedSnapshot)
            }
        } catch {
            print("\(actionName) failed for \(url.lastPathComponent): \(error)")
        }
    }

    private func captureEditorSnapshot(document: DocumentModel) async -> DocumentFileStore.FileSnapshot? {
        await withCheckedContinuation { continuation in
            getDocumentSnapshot { [currentSnapshot = document.currentSnapshot()] snapshot in
                guard let snapshot else {
                    continuation.resume(returning: nil)
                    return
                }

                continuation.resume(
                    returning: DocumentFileStore.FileSnapshot(
                        canonicalJSON: snapshot.canonicalJSON,
                        htmlContent: snapshot.htmlContent,
                        plainText: snapshot.plainText,
                        wordCount: snapshot.wordCount,
                        characterCount: snapshot.characterCount,
                        documentID: currentSnapshot.documentID,
                        schemaVersion: currentSnapshot.schemaVersion,
                        createdAt: currentSnapshot.createdAt,
                        modifiedAt: Date()
                    )
                )
            }
        }
    }

    private func parseEditorSnapshot(from jsonString: String) -> DocumentFileStore.FileSnapshot? {
        guard let data = jsonString.data(using: .utf8),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            return nil
        }

        let html = dict["html"] as? String ?? ""
        let plainText = dict["text"] as? String ?? ""
        let words = dict["words"] as? Int
        let characters = dict["characters"] as? Int

        let canonicalJSON: String?
        if let jsonObject = dict["json"],
           JSONSerialization.isValidJSONObject(jsonObject),
           let jsonData = try? JSONSerialization.data(withJSONObject: jsonObject, options: [.prettyPrinted, .sortedKeys]) {
            canonicalJSON = String(decoding: jsonData, as: UTF8.self)
        } else {
            canonicalJSON = nil
        }

        return DocumentFileStore.FileSnapshot(
            canonicalJSON: canonicalJSON,
            htmlContent: html,
            plainText: plainText,
            wordCount: words,
            characterCount: characters
        )
    }

    // MARK: - JS Evaluation

    private func escapeForJS(_ s: String) -> String {
        var result = ""
        result.reserveCapacity(s.count)
        for char in s {
            switch char {
            case "\\":
                result += "\\\\"
            case "'":
                result += "\\'"
            case "\n":
                result += "\\n"
            case "\r":
                result += "\\r"
            default:
                result.append(char)
            }
        }
        return result
    }

    private func evaluateJS(_ js: String, completion: ((Any?) -> Void)? = nil) {
        guard let webView = webView else {
            completion?(nil)
            return
        }

        webView.evaluateJavaScript(js) { result, error in
            if let error = error {
                let desc = error.localizedDescription
                if desc.contains("process terminated") || desc.contains("not found") {
                    print("JS evaluation failed (possible web process crash): \(desc)")
                } else {
                    print("JS error: \(desc)")
                }
            }
            completion?(result)
        }
    }
}

// MARK: - Notifications
extension Notification.Name {
    static let editorContentUpdated = Notification.Name("editorContentUpdated")
    static let editorBecameReady = Notification.Name("editorBecameReady")
    static let showSaveNamedVersion = Notification.Name("showSaveNamedVersion")
}
