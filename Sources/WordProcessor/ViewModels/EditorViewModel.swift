import SwiftUI
import WebKit

@Observable
@MainActor
final class EditorViewModel {
    var webView: WKWebView?
    var isEditorReady = false
    var selectionState = SelectionState()
    var pendingEditCount = 0
    var pendingEditCurrentIndex = -1
    private var autoSaveTimer: Timer?
    /// Content buffered for loading when the editor becomes ready.
    private var pendingContent: String?
    /// Incremented each time the editor signals ready (supports detecting web process restarts).
    var editorReadyCount = 0

    struct SelectionState {
        var isBold = false
        var isItalic = false
        var isUnderline = false
        var heading = 0
        var textAlign = "left"
        var hasSelection = false
        var isLink = false
        var linkHref = ""
        var textColor = ""
    }

    // Called by bridge when JS sends a message
    func handleBridgeMessage(type: String, payload: BridgePayload) {
        switch payload {
        case .editorReady:
            isEditorReady = true
            editorReadyCount += 1
            // Flush any content that was buffered before the editor was ready
            if let content = pendingContent {
                pendingContent = nil
                let escaped = escapeForJS(content)
                evaluateJS("window.editorAPI?.loadContent('\(escaped)')")
            }
            // Notify so ContentView can reload content (handles web process restart too)
            NotificationCenter.default.post(name: .editorBecameReady, object: nil)

        case .contentChanged(let html):
            NotificationCenter.default.post(
                name: .editorContentUpdated,
                object: nil,
                userInfo: ["html": html]
            )

        case .contentUpdate(let html, let words, let characters):
            NotificationCenter.default.post(
                name: .editorContentUpdated,
                object: nil,
                userInfo: ["html": html, "words": words, "characters": characters]
            )

        case .selectionChanged(let state):
            selectionState.isBold = state.isBold
            selectionState.isItalic = state.isItalic
            selectionState.isUnderline = state.isUnderline
            selectionState.heading = state.heading
            selectionState.textAlign = state.textAlign
            selectionState.hasSelection = state.hasSelection
            selectionState.isLink = state.isLink
            selectionState.linkHref = state.linkHref
            selectionState.textColor = state.textColor

        case .wordCount(let words, let characters):
            NotificationCenter.default.post(
                name: .editorContentUpdated,
                object: nil,
                userInfo: ["words": words, "characters": characters]
            )

        case .pendingEditUpdate(let count, let currentIndex):
            pendingEditCount = count
            pendingEditCurrentIndex = currentIndex

        case .unknown:
            break
        }
    }

    // Call JS functions from Swift
    func loadContent(_ html: String) {
        guard isEditorReady else {
            // Editor JS not loaded yet — buffer for when editorReady fires
            pendingContent = html
            return
        }
        pendingContent = nil
        let escaped = escapeForJS(html)
        evaluateJS("window.editorAPI?.loadContent('\(escaped)')")
    }

    func getContent(completion: @escaping (String) -> Void) {
        evaluateJS("window.editorAPI?.getContent()") { result in
            completion(result as? String ?? "")
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

    // MARK: - Auto-Save

    /// Schedule auto-save 5s after the last edit. Only auto-saves if the document has a file URL.
    func scheduleAutoSave(document: DocumentModel) {
        autoSaveTimer?.invalidate()
        guard document.fileURL != nil else { return }
        autoSaveTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: false) { [weak self] _ in
            Task { @MainActor in
                self?.autoSave(document: document)
            }
        }
    }

    /// Auto-save uses document.htmlContent (already synced via notifications) to avoid
    /// async getContent races where the editor content changes between call and callback.
    private func autoSave(document: DocumentModel) {
        guard let url = document.fileURL, document.isDirty else { return }
        let html = document.htmlContent
        guard Self.hasSubstantialContent(html) else {
            print("Auto-save: refusing to write empty content to \(url.lastPathComponent)")
            return
        }
        Task.detached {
            do {
                try html.write(to: url, atomically: true, encoding: .utf8)
                await MainActor.run {
                    // Only mark saved if the document still points to the same file
                    if document.fileURL == url {
                        document.isDirty = false
                    }
                }
            } catch {
                print("Auto-save failed for \(url.lastPathComponent): \(error)")
            }
        }
    }

    /// Cancel auto-save timer and flush any unsaved changes before switching documents.
    /// Call this before openFile() or newDocument().
    func flushBeforeDocumentChange(document: DocumentModel) {
        autoSaveTimer?.invalidate()
        autoSaveTimer = nil
        guard let url = document.fileURL, document.isDirty else { return }
        let html = document.htmlContent
        guard Self.hasSubstantialContent(html) else {
            print("Flush: refusing to write empty content to \(url.lastPathComponent)")
            return
        }
        Task.detached {
            do {
                try html.write(to: url, atomically: true, encoding: .utf8)
            } catch {
                print("Flush write failed for \(url.lastPathComponent): \(error)")
            }
        }
    }

    // MARK: - File Operations

    func openDocument(document: DocumentModel) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.html]
        panel.allowsMultipleSelection = false

        panel.begin { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            Task { @MainActor in
                self?.openFile(url: url, document: document)
            }
        }
    }

    func openFile(url: URL, document: DocumentModel) {
        // Flush unsaved changes to the current file before switching
        flushBeforeDocumentChange(document: document)

        Task {
            do {
                let html = try await Task.detached {
                    try String(contentsOf: url, encoding: .utf8)
                }.value
                document.htmlContent = html
                document.fileURL = url
                document.isDirty = false
                DocumentModel.addToRecentFiles(url)
                loadContent(html)

                // Snapshot when opening so the file-on-disk state is captured
                if EditorViewModel.hasSubstantialContent(html) {
                    VersionStore.shared.saveVersion(
                        filePath: url.path,
                        htmlContent: html,
                        wordCount: document.wordCount
                    )
                }
            } catch {
                print("Failed to open file: \(error)")
            }
        }
    }

    func saveDocument(document: DocumentModel) {
        if let url = document.fileURL {
            writeToFile(document: document, url: url)
        } else {
            saveDocumentAs(document: document)
        }
    }

    func saveDocumentAs(document: DocumentModel) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.html]
        panel.nameFieldStringValue = document.displayName + ".html"

        panel.begin { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            self?.writeToFile(document: document, url: url)
        }
    }

    /// Manual save (Cmd+S) — uses getContent for the freshest editor state.
    /// Falls back to document.htmlContent if JS returns empty, and refuses to
    /// overwrite a file with content that has no actual text or images.
    /// Also creates a version snapshot on each manual save.
    private func writeToFile(document: DocumentModel, url: URL) {
        getContent { html in
            // Prefer fresh editor content; fall back to in-memory model
            let content = html.isEmpty ? document.htmlContent : html
            guard EditorViewModel.hasSubstantialContent(content) else {
                print("Refusing to save empty content to \(url.lastPathComponent)")
                return
            }
            Task.detached {
                do {
                    try content.write(to: url, atomically: true, encoding: .utf8)
                    await MainActor.run {
                        if document.fileURL == url {
                            document.markSaved(url: url)
                        }
                        // Snapshot version on every manual save
                        VersionStore.shared.saveVersion(
                            filePath: url.path,
                            htmlContent: content,
                            wordCount: document.wordCount
                        )
                    }
                } catch {
                    print("Save failed for \(url.lastPathComponent): \(error)")
                }
            }
        }
    }

    // MARK: - JS Evaluation

    /// Single-pass string escaping for JS string literals.
    private func escapeForJS(_ s: String) -> String {
        var result = ""
        result.reserveCapacity(s.count)
        for char in s {
            switch char {
            case "\\": result += "\\\\"
            case "'":  result += "\\'"
            case "\n": result += "\\n"
            case "\r": result += "\\r"
            default:   result.append(char)
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
                // WKErrorWebContentProcessTerminated (code 11) means the process crashed;
                // other errors may indicate a hung or disconnected webview.
                if desc.contains("process terminated") || desc.contains("not found") {
                    print("JS evaluation failed (possible web process crash): \(desc)")
                } else {
                    print("JS error: \(desc)")
                }
            }
            completion?(result)
        }
    }

    // MARK: - Content Validation

    /// Returns true if the HTML has actual text or meaningful elements (images).
    /// Used to prevent saving empty/near-empty content over real files.
    static func hasSubstantialContent(_ html: String) -> Bool {
        if html.isEmpty { return false }
        // Images count as substantial content even without text
        if html.contains("<img") { return true }
        // Strip all HTML tags and check for non-whitespace text
        let stripped = html.replacingOccurrences(of: "<[^>]*>", with: "", options: .regularExpression)
        return !stripped.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

// MARK: - Notifications
extension Notification.Name {
    static let editorContentUpdated = Notification.Name("editorContentUpdated")
    static let editorBecameReady = Notification.Name("editorBecameReady")
    static let showSaveNamedVersion = Notification.Name("showSaveNamedVersion")
}
