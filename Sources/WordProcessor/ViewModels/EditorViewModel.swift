import AppKit
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
    var activePendingEditID: String?
    var comments: [BridgePayload.CommentData] = []
    var activeCommentID: String?
    var ambientReviewEnabled = false
    var isAmbientReviewing = false
    var ambientReviewStatusText = ""
    var persistenceStatusText = ""
    var persistenceStatusIsError = false
    private var autoSaveTimer: Timer?
    private var recoveryDraftTimer: Timer?
    private var ambientReviewTimer: Timer?
    private var ambientReviewTask: Task<Void, Never>?
    private var lastAmbientReviewedDocumentHash: String?
    private var pendingSnapshot: DocumentFileStore.FileSnapshot?
    private var lastAutoSaveCheckpointByDocumentID: [String: Date] = [:]
    private let autoSaveCheckpointInterval: TimeInterval = 60
    @ObservationIgnored private let ambientReviewService = ClaudeAPIService()
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

    struct SelectionClipboardPayload: Decodable {
        let html: String
        let text: String
        let imageSources: [String]
        let singleImageSource: String?

        var containsImages: Bool {
            !imageSources.isEmpty
        }
    }

    struct AnchoredCommentRequest {
        var id: String = UUID().uuidString
        var rangeStart: Int
        var rangeEnd: Int
        var text: String
        var authorName: String = ""
        var source: String = "user"
        var kind: String = ""
        var severity: String = ""
        var status: String = "open"
        var suggestedReplacement: String = ""
        var agentRunID: String = ""
        var allowOverlap: Bool = false
    }

    struct EditContextSnapshot: Decodable, Equatable {
        struct Selection: Decodable, Equatable {
            let from: Int
            let to: Int
            let text: String
            let html: String
            let words: Int
            let characters: Int
        }

        struct Block: Decodable, Equatable {
            let id: String
            let path: String
            let type: String
            let from: Int
            let to: Int
            let text: String
            let textHash: String
        }

        let revision: Int
        let documentHash: String
        let plainText: String
        let cursorPosition: Int
        let nearbyText: String
        let selection: Selection?
        let blocks: [Block]
    }

    private struct AmbientReviewSuggestion: Decodable {
        let blockID: String
        let exactOriginal: String
        let comment: String
        let kind: String?
        let severity: String?
        let suggestedReplacement: String?

        enum CodingKeys: String, CodingKey {
            case blockID = "block_id"
            case exactOriginal = "exact_original"
            case comment
            case kind
            case severity
            case suggestedReplacement = "suggested_replacement"
        }
    }

    private struct AmbientReviewResponse: Decodable {
        let comments: [AmbientReviewSuggestion]
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
            NotificationCenter.default.post(name: .editorBecameReady, object: self)

        case .contentChanged(let html):
            NotificationCenter.default.post(
                name: .editorContentUpdated,
                object: self,
                userInfo: ["html": html]
            )

        case .contentUpdate(let html, let text, let words, let characters):
            NotificationCenter.default.post(
                name: .editorContentUpdated,
                object: self,
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
                object: self,
                userInfo: ["words": words, "characters": characters]
            )

        case .pendingEditUpdate(let update):
            pendingEditCount = update.count
            pendingEditCurrentIndex = update.currentIndex
            activePendingEditID = update.activeEditID
            pendingEdits = update.edits.map(PendingEdit.init)

        case .commentsChanged(let newComments, let documentChanged):
            comments = newComments.sorted {
                if $0.rangeStart != $1.rangeStart {
                    return $0.rangeStart < $1.rangeStart
                }
                if $0.createdAt != $1.createdAt {
                    return $0.createdAt < $1.createdAt
                }
                return $0.id < $1.id
            }
            if let activeCommentID, !comments.contains(where: { $0.id == activeCommentID }) {
                self.activeCommentID = nil
            }
            if documentChanged {
                NotificationCenter.default.post(name: .editorDocumentMutated, object: self)
            }

        case .commentActivated(let commentId):
            guard !commentId.isEmpty else { break }
            activeCommentID = commentId
            NotificationCenter.default.post(
                name: .editorCommentActivated,
                object: self,
                userInfo: ["commentId": commentId]
            )

        case .unknown:
            break
        }
    }

    // MARK: - Content Loading

    func loadSnapshot(_ snapshot: DocumentFileStore.FileSnapshot) {
        lastAmbientReviewedDocumentHash = nil

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
        callEditorAPI("loadContent", arguments: [html])
    }

    private func loadJSONContent(_ json: String) {
        callEditorAPI("loadJSONContent", arguments: [json])
    }

    // MARK: - Snapshot Capture

    func getContent(completion: @escaping (String?) -> Void) {
        callEditorAPI("getContent") { result in
            completion(result as? String)
        }
    }

    func getDocumentSnapshot(completion: @escaping (DocumentFileStore.FileSnapshot?) -> Void) {
        callEditorAPI("getDocumentSnapshot") { [weak self] result in
            guard let jsonString = result as? String else {
                completion(nil)
                return
            }
            completion(self?.parseEditorSnapshot(from: jsonString))
        }
    }

    func applyFormat(_ command: String, value: String? = nil) {
        if let value = value {
            callEditorAPI("applyFormat", arguments: [command, value])
        } else {
            callEditorAPI("applyFormat", arguments: [command])
        }
    }

    func getPlainText(completion: @escaping (String) -> Void) {
        callEditorAPI("getPlainText") { result in
            completion(result as? String ?? "")
        }
    }

    func getSelectedText(completion: @escaping (String) -> Void) {
        callEditorAPI("getSelectedText") { result in
            completion(result as? String ?? "")
        }
    }

    func getEditContextSnapshot(completion: @escaping (EditContextSnapshot?) -> Void) {
        callEditorAPI("getEditContextSnapshot") { result in
            guard let jsonString = result as? String,
                  let data = jsonString.data(using: .utf8),
                  let snapshot = try? JSONDecoder().decode(EditContextSnapshot.self, from: data)
            else {
                completion(nil)
                return
            }

            completion(snapshot)
        }
    }

    var isEditorFocused: Bool {
        guard let webView,
              let firstResponder = webView.window?.firstResponder
        else {
            return false
        }

        if let responderView = firstResponder as? NSView {
            return responderView == webView || responderView.isDescendant(of: webView)
        }

        return false
    }

    func copySelectionWithImagesToPasteboard(cutAfterCopy: Bool) async -> Bool {
        guard let payload = await getSelectionClipboardPayload(),
              payload.containsImages
        else {
            return false
        }

        do {
            let html = try await DocumentFileStore.shared.inlineHTMLForExternalTransfer(
                payload.html,
                sourceDocumentURL: assetBaseURL
            )
            let singleImageAsset: DocumentFileStore.ClipboardImageAsset?
            if let singleImageSource = payload.singleImageSource {
                singleImageAsset = try await DocumentFileStore.shared.clipboardImageAsset(
                    for: singleImageSource,
                    sourceDocumentURL: assetBaseURL
                )
            } else {
                singleImageAsset = nil
            }

            let wroteToPasteboard = EditorClipboardWriter.write(
                html: html,
                plainText: payload.text,
                singleImageAsset: singleImageAsset
            )

            if wroteToPasteboard, cutAfterCopy {
                deleteSelection()
            }

            return wroteToPasteboard
        } catch {
            print("Clipboard export failed: \(error)")
            return false
        }
    }

    func focusEditor() {
        callEditorAPI("focus")
    }

    func setThemeCSS(_ css: String) {
        callEditorAPI("setThemeCSS", arguments: [css])
    }

    // MARK: - Document Editing (for Claude tool use)

    func replaceSelectionHTML(_ html: String) {
        callEditorAPI("replaceSelectionHTML", arguments: [html])
    }

    func insertHTMLAtCursor(_ html: String) {
        callEditorAPI("insertHTMLAtCursor", arguments: [html])
    }

    func deleteSelection() {
        callEditorAPI("deleteSelection")
    }

    func findAndReplaceText(find: String, replaceHTML: String, replaceAll: Bool, completion: @escaping (Int) -> Void) {
        callEditorAPI("findAndReplaceText", arguments: [find, replaceHTML, replaceAll]) { result in
            completion(result as? Int ?? 0)
        }
    }

    // MARK: - Pending Edits (Cursor-like diff review)

    func pendingReplaceSelection(
        id: String,
        html: String,
        target: [String: Any]? = nil,
        completion: @escaping (Int) -> Void
    ) {
        var arguments: [Any] = [id, html]
        if let target {
            arguments.append(target)
        }
        callEditorAPI("pendingReplaceSelection", arguments: arguments) { result in
            completion(result as? Int ?? 0)
        }
    }

    func pendingInsertAtCursor(
        id: String,
        html: String,
        target: [String: Any]? = nil,
        completion: @escaping (Int) -> Void
    ) {
        var arguments: [Any] = [id, html]
        if let target {
            arguments.append(target)
        }
        callEditorAPI("pendingInsertAtCursor", arguments: arguments) { result in
            completion(result as? Int ?? 0)
        }
    }

    func pendingFindAndReplace(id: String, find: String, replaceHTML: String, replaceAll: Bool, completion: @escaping (Int) -> Void) {
        callEditorAPI("pendingFindAndReplace", arguments: [id, find, replaceHTML, replaceAll]) { result in
            completion(result as? Int ?? 0)
        }
    }

    func pendingProposeEdit(
        id: String,
        target: [String: Any],
        replacementHTML: String,
        replaceAll: Bool,
        completion: @escaping (Int) -> Void
    ) {
        callEditorAPI("pendingProposeEdit", arguments: [id, target, replacementHTML, replaceAll]) { result in
            completion(result as? Int ?? 0)
        }
    }

    func acceptAllPendingEdits() {
        callEditorAPI("acceptAllPendingEdits")
    }

    func rejectAllPendingEdits() {
        callEditorAPI("rejectAllPendingEdits")
    }

    func focusPendingEdit(_ id: String) {
        callEditorAPI("focusPendingEdit", arguments: [id])
    }

    func acceptPendingEdit(_ id: String) {
        callEditorAPI("acceptPendingEdit", arguments: [id])
    }

    func rejectPendingEdit(_ id: String) {
        callEditorAPI("rejectPendingEdit", arguments: [id])
    }

    // MARK: - Comments

    func addComment() {
        let id = UUID().uuidString
        callEditorAPI("addComment", arguments: [id])
    }

    func addAnchoredComment(_ comment: AnchoredCommentRequest, completion: ((Bool) -> Void)? = nil) {
        let payload: [String: Any] = [
            "commentId": comment.id,
            "from": comment.rangeStart,
            "to": comment.rangeEnd,
            "text": comment.text,
            "authorName": comment.authorName,
            "source": comment.source,
            "kind": comment.kind,
            "severity": comment.severity,
            "status": comment.status,
            "suggestedReplacement": comment.suggestedReplacement,
            "agentRunId": comment.agentRunID,
            "allowOverlap": comment.allowOverlap,
        ]

        guard let json = jsonString(for: payload) else {
            completion?(false)
            return
        }

        callEditorAPI("addCommentAtRange", arguments: [json]) { result in
            completion?(result as? Bool ?? false)
        }
    }

    func addAgentComment(
        rangeStart: Int,
        rangeEnd: Int,
        text: String,
        kind: String = "suggestion",
        severity: String = "medium",
        suggestedReplacement: String = "",
        agentRunID: String = "",
        completion: ((Bool) -> Void)? = nil
    ) {
        addAnchoredComment(
            AnchoredCommentRequest(
                rangeStart: rangeStart,
                rangeEnd: rangeEnd,
                text: text,
                authorName: "Ambient Editor",
                source: "agent",
                kind: kind,
                severity: severity,
                suggestedReplacement: suggestedReplacement,
                agentRunID: agentRunID,
                allowOverlap: true
            ),
            completion: completion
        )
    }

    func updateCommentText(_ commentId: String, text: String) {
        callEditorAPI("updateCommentText", arguments: [commentId, text])
    }

    func setCommentStatus(_ commentId: String, status: String) {
        callEditorAPI("setCommentStatus", arguments: [commentId, status])
    }

    func removeComment(_ commentId: String) {
        callEditorAPI("removeComment", arguments: [commentId])
    }

    func focusComment(_ commentId: String) {
        activeCommentID = commentId
        callEditorAPI("focusComment", arguments: [commentId])
    }

    func pendingReplaceComment(_ comment: BridgePayload.CommentData) {
        let replacement = comment.suggestedReplacement.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !replacement.isEmpty else { return }

        callEditorAPI(
            "pendingReplaceComment",
            arguments: [comment.id, "comment_edit_\(UUID().uuidString)", replacement]
        )
    }

    // MARK: - Ambient Review

    func setAmbientReviewEnabled(_ enabled: Bool) {
        ambientReviewEnabled = enabled
        ambientReviewTimer?.invalidate()
        ambientReviewTimer = nil

        if enabled {
            ambientReviewStatusText = "Ambient review will run after you pause."
            scheduleAmbientReview()
        } else {
            ambientReviewTask?.cancel()
            ambientReviewTask = nil
            isAmbientReviewing = false
            ambientReviewStatusText = ""
        }
    }

    func scheduleAmbientReview() {
        ambientReviewTimer?.invalidate()
        guard ambientReviewEnabled, !isAmbientReviewing else { return }

        ambientReviewTimer = Timer.scheduledTimer(withTimeInterval: 8, repeats: false) { [weak self] _ in
            Task { @MainActor in
                self?.startAmbientReview()
            }
        }
    }

    private func startAmbientReview() {
        guard ambientReviewEnabled, !isAmbientReviewing else { return }

        ambientReviewTask?.cancel()
        isAmbientReviewing = true
        ambientReviewTask = Task { [weak self] in
            await self?.runAmbientReview()
        }
    }

    private func runAmbientReview() async {
        defer {
            isAmbientReviewing = false
            ambientReviewTask = nil
        }

        guard ambientReviewEnabled else { return }
        guard let context = await currentEditContextSnapshot(), !context.blocks.isEmpty else { return }

        guard lastAmbientReviewedDocumentHash != context.documentHash else {
            ambientReviewStatusText = "Ambient review is up to date."
            return
        }

        ambientReviewStatusText = "Reviewing..."

        do {
            let responseText = try await collectAmbientReviewResponse(context: context)
            let suggestions = parseAmbientReviewSuggestions(from: responseText)
            let addedCount = await addAmbientReviewComments(suggestions, context: context)
            lastAmbientReviewedDocumentHash = context.documentHash

            if addedCount > 0 {
                ambientReviewStatusText = "Added \(addedCount) suggestion\(addedCount == 1 ? "" : "s")."
            } else {
                ambientReviewStatusText = "No new suggestions."
            }
        } catch is CancellationError {
            ambientReviewStatusText = ""
        } catch {
            ambientReviewStatusText = "Ambient review failed: \(error.localizedDescription)"
        }
    }

    private func currentEditContextSnapshot() async -> EditContextSnapshot? {
        await withCheckedContinuation { continuation in
            getEditContextSnapshot { snapshot in
                continuation.resume(returning: snapshot)
            }
        }
    }

    private func collectAmbientReviewResponse(context: EditContextSnapshot) async throws -> String {
        let systemPrompt: [[String: Any]] = [
            [
                "type": "text",
                "text": """
                You are an ambient editor inside a word processor. The user has explicitly enabled background review.
                Return only compact JSON. Do not use Markdown.
                Find at most 4 high-signal opportunities to improve clarity, structure, accuracy, tone, or concision.
                Only comment on text you can anchor to a block in the supplied edit context.
                You will receive existing comments. Treat them as already-covered feedback, even if resolved or dismissed.
                Do not repeat, paraphrase, or add a nearby overlapping version of an existing comment. If the only useful feedback is already covered, return {"comments":[]}.
                Schema:
                {"comments":[{"block_id":"...","exact_original":"exact current text span","comment":"short rationale","kind":"clarity|structure|tone|concision|grammar|accuracy","severity":"low|medium|high","suggested_replacement":"optional replacement HTML or plain text"}]}
                If there is nothing worth saying, return {"comments":[]}.
                """
            ]
        ]

        let messages: [[String: Any]] = [
            [
                "role": "user",
                "content": ambientReviewPrompt(context)
            ]
        ]

        var text = ""
        for try await chunk in ambientReviewService.streamMessage(
            messages: messages,
            systemPrompt: systemPrompt,
            tools: nil,
            cacheControl: nil
        ) {
            if case .text(let delta) = chunk {
                text += delta
            }
        }
        return text
    }

    private func ambientReviewPrompt(_ context: EditContextSnapshot) -> String {
        let existingComments = ambientExistingCommentsXML()
        let blockLines = context.blocks.map { block in
            """
            <block id="\(xmlEscaped(block.id))" type="\(xmlEscaped(block.type))" from="\(block.from)" to="\(block.to)" text_hash="\(xmlEscaped(block.textHash))">
            \(xmlEscaped(block.text))
            </block>
            """
        }.joined(separator: "\n")

        return """
        Review the current document using these anchorable blocks. Return JSON only.
        <edit_context revision="\(context.revision)" document_hash="\(xmlEscaped(context.documentHash))">
        \(existingComments)
        <block_index>
        \(blockLines)
        </block_index>
        </edit_context>
        """
    }

    private func ambientExistingCommentsXML(limit: Int = 40) -> String {
        let visibleComments = comments.filter {
            !$0.selectedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
            !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }

        guard !visibleComments.isEmpty else {
            return "<existing_comments />"
        }

        let commentLines = visibleComments.prefix(limit).map { comment in
            """
            <comment id="\(xmlEscaped(comment.id))" source="\(xmlEscaped(comment.source))" status="\(xmlEscaped(comment.status))" kind="\(xmlEscaped(comment.kind))" severity="\(xmlEscaped(comment.severity))" from="\(comment.rangeStart)" to="\(comment.rangeEnd)">
            <selected_text>\(xmlEscaped(comment.selectedText))</selected_text>
            <comment_text>\(xmlEscaped(comment.text))</comment_text>
            </comment>
            """
        }.joined(separator: "\n")

        let omittedLine = visibleComments.count > limit
            ? "\n<omitted_comments count=\"\(visibleComments.count - limit)\" />"
            : ""

        return """
        <existing_comments>
        \(commentLines)\(omittedLine)
        </existing_comments>
        """
    }

    private func parseAmbientReviewSuggestions(from responseText: String) -> [AmbientReviewSuggestion] {
        let trimmed = responseText
            .replacingOccurrences(of: "```json", with: "")
            .replacingOccurrences(of: "```", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        let candidateStrings = [
            jsonSubstring(in: trimmed, opening: "{", closing: "}"),
            jsonSubstring(in: trimmed, opening: "[", closing: "]"),
            trimmed,
        ].compactMap { $0 }

        for candidate in candidateStrings {
            guard let data = candidate.data(using: .utf8) else { continue }
            if let response = try? JSONDecoder().decode(AmbientReviewResponse.self, from: data) {
                return response.comments
            }
            if let comments = try? JSONDecoder().decode([AmbientReviewSuggestion].self, from: data) {
                return comments
            }
        }

        return []
    }

    private func addAmbientReviewComments(
        _ suggestions: [AmbientReviewSuggestion],
        context: EditContextSnapshot
    ) async -> Int {
        var addedCount = 0
        let existingAgentComments = comments.filter { $0.source == "agent" }
        var existingCommentFingerprints = Set(existingAgentComments
            .map { ambientCommentFingerprint(selectedText: $0.selectedText, comment: $0.text) })
        var existingAnchorFingerprints = Set(existingAgentComments
            .map { ambientAnchorFingerprint(selectedText: $0.selectedText) }
            .filter { !$0.isEmpty })
        var protectedRanges = existingAgentComments.map {
            (start: $0.rangeStart, end: $0.rangeEnd)
        }

        for suggestion in suggestions.prefix(4) {
            guard let range = resolveAmbientSuggestion(suggestion, context: context) else { continue }

            let suggestedRange = (start: range.start, end: range.end)
            guard !protectedRanges.contains(where: { rangesOverlap($0, suggestedRange) }) else {
                continue
            }

            let anchorFingerprint = ambientAnchorFingerprint(selectedText: suggestion.exactOriginal)
            guard !anchorFingerprint.isEmpty,
                  !existingAnchorFingerprints.contains(anchorFingerprint)
            else {
                continue
            }

            let fingerprint = ambientCommentFingerprint(
                selectedText: suggestion.exactOriginal,
                comment: suggestion.comment
            )
            guard !existingCommentFingerprints.contains(fingerprint) else { continue }

            let added = await addAgentCommentAsync(
                rangeStart: range.start,
                rangeEnd: range.end,
                text: suggestion.comment,
                kind: suggestion.kind ?? "suggestion",
                severity: suggestion.severity ?? "medium",
                suggestedReplacement: suggestion.suggestedReplacement ?? ""
            )
            if added {
                addedCount += 1
                existingCommentFingerprints.insert(fingerprint)
                existingAnchorFingerprints.insert(anchorFingerprint)
                protectedRanges.append(suggestedRange)
            }
        }

        return addedCount
    }

    private func addAgentCommentAsync(
        rangeStart: Int,
        rangeEnd: Int,
        text: String,
        kind: String,
        severity: String,
        suggestedReplacement: String
    ) async -> Bool {
        await withCheckedContinuation { continuation in
            addAgentComment(
                rangeStart: rangeStart,
                rangeEnd: rangeEnd,
                text: text,
                kind: kind,
                severity: severity,
                suggestedReplacement: suggestedReplacement,
                agentRunID: UUID().uuidString
            ) { added in
                continuation.resume(returning: added)
            }
        }
    }

    private func resolveAmbientSuggestion(
        _ suggestion: AmbientReviewSuggestion,
        context: EditContextSnapshot
    ) -> (start: Int, end: Int)? {
        guard let block = context.blocks.first(where: { $0.id == suggestion.blockID }) else {
            return nil
        }

        let original = suggestion.exactOriginal.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !original.isEmpty,
              let range = block.text.range(of: original)
        else {
            return nil
        }

        let remaining = block.text[range.upperBound...]
        guard remaining.range(of: original) == nil else {
            return nil
        }

        guard let utf16LowerBound = range.lowerBound.samePosition(in: block.text.utf16) else {
            return nil
        }

        let offset = block.text.utf16.distance(from: block.text.utf16.startIndex, to: utf16LowerBound)
        let length = original.utf16.count
        return (block.from + offset, block.from + offset + length)
    }

    private func ambientCommentFingerprint(selectedText: String, comment: String) -> String {
        "\(ambientAnchorFingerprint(selectedText: selectedText))|\(normalizedAmbientText(comment))"
    }

    private func ambientAnchorFingerprint(selectedText: String) -> String {
        normalizedAmbientText(selectedText)
    }

    private func normalizedAmbientText(_ text: String) -> String {
        text
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    private func rangesOverlap(
        _ lhs: (start: Int, end: Int),
        _ rhs: (start: Int, end: Int)
    ) -> Bool {
        lhs.start < rhs.end && rhs.start < lhs.end
    }

    var activePendingEdit: PendingEdit? {
        if let activePendingEditID,
           let active = pendingEdits.first(where: { $0.id == activePendingEditID }) {
            return active
        }

        if let active = pendingEdits.first(where: \.isActive) {
            return active
        }

        if pendingEditCurrentIndex >= 0, pendingEditCurrentIndex < pendingEdits.count {
            return pendingEdits[pendingEditCurrentIndex]
        }

        return pendingEdits.first
    }

    func focusNextPendingEdit() {
        callEditorAPI("focusNextPendingEdit")
    }

    func focusPreviousPendingEdit() {
        callEditorAPI("focusPreviousPendingEdit")
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
        callEditorAPI("findInDocument", arguments: [query]) { result in
            completion(result as? Int ?? 0)
        }
    }

    func findNext(completion: @escaping (Int, Int) -> Void) {
        callEditorAPI("findNext") { result in
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
        callEditorAPI("findPrevious") { result in
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
        callEditorAPI("replaceOne", arguments: [replacement]) { result in
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
        callEditorAPI("replaceAll", arguments: [replacement]) { result in
            completion(result as? Int ?? 0)
        }
    }

    func clearFind() {
        callEditorAPI("clearFind")
    }

    func latestSnapshot(for document: DocumentModel, preferEditorState: Bool = true) async -> DocumentFileStore.FileSnapshot {
        if preferEditorState, let snapshot = await captureEditorSnapshot(document: document) {
            document.syncFromEditor(snapshot: snapshot)
        }
        return document.currentSnapshot()
    }

    // MARK: - Auto-Save

    func scheduleRecoveryDraft(document: DocumentModel) {
        recoveryDraftTimer?.invalidate()
        guard document.isDirty else { return }
        recoveryDraftTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: false) { [weak self] _ in
            Task { @MainActor in
                await self?.saveRecoveryDraft(document: document)
            }
        }
    }

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
        let shouldCheckpoint = shouldCreateAutoSaveCheckpoint(for: document)
        await persistDocument(
            document: document,
            to: url,
            captureLatestEditorState: true,
            createVersionSnapshot: shouldCheckpoint,
            actionName: "Auto-save"
        )
    }

    private func flushBeforeDocumentChange(document: DocumentModel) async {
        autoSaveTimer?.invalidate()
        autoSaveTimer = nil
        recoveryDraftTimer?.invalidate()
        recoveryDraftTimer = nil
        ambientReviewTimer?.invalidate()
        ambientReviewTimer = nil
        ambientReviewTask?.cancel()
        ambientReviewTask = nil

        guard document.isDirty else { return }
        await saveRecoveryDraft(document: document)

        guard let url = document.fileURL else { return }
        await persistDocument(
            document: document,
            to: url,
            captureLatestEditorState: true,
            createVersionSnapshot: false,
            actionName: "Flush"
        )
    }

    private func shouldCreateAutoSaveCheckpoint(for document: DocumentModel) -> Bool {
        let documentID = document.documentID
        let now = Date()
        defer { lastAutoSaveCheckpointByDocumentID[documentID] = now }

        guard let lastCheckpoint = lastAutoSaveCheckpointByDocumentID[documentID] else {
            return true
        }
        return now.timeIntervalSince(lastCheckpoint) >= autoSaveCheckpointInterval
    }

    private func saveRecoveryDraft(document: DocumentModel) async {
        guard document.isDirty else { return }

        do {
            let snapshot = await latestSnapshot(for: document)
            _ = try await RecoveryDraftStore.shared.saveDraft(
                snapshot: snapshot,
                assetSourceDocumentURL: assetBaseURL ?? document.fileURL,
                originalDocumentURL: document.fileURL,
                displayName: document.displayName
            )
            if document.fileURL == nil {
                setPersistenceStatus("Recovery draft saved \(formattedStatusTime())", isError: false)
            }
        } catch {
            setPersistenceStatus("Recovery draft failed: \(error.localizedDescription)", isError: true)
        }
    }

    func recoverDraft(_ metadata: RecoveryDraftStore.DraftMetadata, document: DocumentModel) {
        Task { @MainActor in
            autoSaveTimer?.invalidate()
            autoSaveTimer = nil
            recoveryDraftTimer?.invalidate()
            recoveryDraftTimer = nil

            do {
                let draft = try await RecoveryDraftStore.shared.loadDraft(id: metadata.id)
                let originalFileURL = await RecoveryDraftStore.shared.originalFileURL(for: draft.metadata)
                document.recoverDraft(snapshot: draft.snapshot, originalFileURL: originalFileURL)
                assetBaseURL = draft.packageURL
                loadSnapshot(draft.snapshot)
                setPersistenceStatus("Recovered draft \(formattedStatusTime())", isError: false)
                scheduleRecoveryDraft(document: document)
            } catch {
                setPersistenceStatus("Recover failed: \(error.localizedDescription)", isError: true)
            }
        }
    }

    func discardRecoveryDraft(_ metadata: RecoveryDraftStore.DraftMetadata) {
        Task {
            do {
                try await RecoveryDraftStore.shared.deleteDraft(id: metadata.id)
            } catch {
                await MainActor.run {
                    setPersistenceStatus("Discard draft failed: \(error.localizedDescription)", isError: true)
                }
            }
        }
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
                setPersistenceStatus("Opened \(url.lastPathComponent)", isError: false)
            } catch {
                setPersistenceStatus("Open failed: \(error.localizedDescription)", isError: true)
            }
        }
    }

    func saveDocument(document: DocumentModel) {
        autoSaveTimer?.invalidate()
        autoSaveTimer = nil
        recoveryDraftTimer?.invalidate()
        recoveryDraftTimer = nil

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
        recoveryDraftTimer?.invalidate()
        recoveryDraftTimer = nil

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
                    _ = try await DocumentFileStore.shared.save(
                        snapshot,
                        to: url,
                        sourceDocumentURL: self.assetBaseURL ?? document.fileURL
                    )
                    self.setPersistenceStatus("Exported \(url.lastPathComponent)", isError: false)
                } catch {
                    self.setPersistenceStatus("Export failed: \(error.localizedDescription)", isError: true)
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
        let sourceDocumentURL = assetBaseURL ?? document.fileURL
        setPersistenceStatus("\(actionName) saving...", isError: false)

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

            if !document.isDirty {
                try? await RecoveryDraftStore.shared.deleteDraft(documentID: persistedSnapshot.documentID)
            }
            setPersistenceStatus("\(actionName) saved \(formattedStatusTime())", isError: false)
        } catch {
            setPersistenceStatus("\(actionName) failed: \(error.localizedDescription)", isError: true)
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

    private func getSelectionClipboardPayload() async -> SelectionClipboardPayload? {
        await withCheckedContinuation { continuation in
            callEditorAPI("getSelectionClipboardData") { result in
                guard let jsonString = result as? String,
                      let data = jsonString.data(using: .utf8),
                      let payload = try? JSONDecoder().decode(SelectionClipboardPayload.self, from: data)
                else {
                    continuation.resume(returning: nil)
                    return
                }

                continuation.resume(returning: payload)
            }
        }
    }

    private func setPersistenceStatus(_ text: String, isError: Bool) {
        persistenceStatusText = text
        persistenceStatusIsError = isError
    }

    private func formattedStatusTime(_ date: Date = Date()) -> String {
        DateFormatter.localizedString(from: date, dateStyle: .none, timeStyle: .short)
    }

    private func jsonString(for object: [String: Any]) -> String? {
        guard JSONSerialization.isValidJSONObject(object),
              let data = try? JSONSerialization.data(withJSONObject: object),
              let string = String(data: data, encoding: .utf8)
        else {
            return nil
        }
        return string
    }

    private func jsonSubstring(in text: String, opening: Character, closing: Character) -> String? {
        guard let start = text.firstIndex(of: opening),
              let end = text.lastIndex(of: closing),
              start <= end
        else {
            return nil
        }
        return String(text[start...end])
    }

    private func xmlEscaped(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&apos;")
    }

    // MARK: - JS Evaluation

    private func callEditorAPI(_ functionName: String, arguments: [Any] = [], completion: ((Any?) -> Void)? = nil) {
        let encodedArguments = Self.javascriptArgumentsLiteral(arguments)
        evaluateJS("window.editorAPI?.\(functionName)(\(encodedArguments))", completion: completion)
    }

    private static func javascriptArgumentsLiteral(_ arguments: [Any]) -> String {
        guard !arguments.isEmpty else { return "" }
        guard JSONSerialization.isValidJSONObject(arguments),
              let data = try? JSONSerialization.data(withJSONObject: arguments),
              let arrayLiteral = String(data: data, encoding: .utf8),
              arrayLiteral.first == "[",
              arrayLiteral.last == "]"
        else {
            return ""
        }

        return String(arrayLiteral.dropFirst().dropLast())
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

private enum EditorClipboardWriter {
    static func write(
        html: String,
        plainText: String,
        singleImageAsset: DocumentFileStore.ClipboardImageAsset?
    ) -> Bool {
        let item = NSPasteboardItem()
        var wroteAnything = false

        if !plainText.isEmpty {
            item.setString(plainText, forType: .string)
            wroteAnything = true
        }

        if !html.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let wrappedHTML = wrappedHTMLDocument(for: html)
            if let htmlData = wrappedHTML.data(using: .utf8) {
                item.setData(htmlData, forType: .html)
                wroteAnything = true
            }

            if let rtfData = rtfData(fromHTML: wrappedHTML) {
                item.setData(rtfData, forType: .rtf)
            }
        }

        if let singleImageAsset {
            if let typeIdentifier = singleImageAsset.pasteboardTypeIdentifier {
                item.setData(singleImageAsset.data, forType: NSPasteboard.PasteboardType(typeIdentifier))
                wroteAnything = true
            }

            if let image = NSImage(data: singleImageAsset.data),
               let tiffData = image.tiffRepresentation {
                item.setData(tiffData, forType: .tiff)
                wroteAnything = true
            }
        }

        guard wroteAnything else { return false }

        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        return pasteboard.writeObjects([item])
    }

    private static func wrappedHTMLDocument(for fragment: String) -> String {
        """
        <!DOCTYPE html>
        <html>
        <head>
        <meta charset="utf-8">
        </head>
        <body>\(fragment)</body>
        </html>
        """
    }

    private static func rtfData(fromHTML html: String) -> Data? {
        guard let htmlData = html.data(using: .utf8),
              let attributedString = try? NSAttributedString(
                  data: htmlData,
                  options: [
                      .documentType: NSAttributedString.DocumentType.html,
                      .characterEncoding: String.Encoding.utf8.rawValue,
                  ],
                  documentAttributes: nil
              )
        else {
            return nil
        }

        return try? attributedString.data(
            from: NSRange(location: 0, length: attributedString.length),
            documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf]
        )
    }
}

// MARK: - Notifications
extension Notification.Name {
    static let editorContentUpdated = Notification.Name("editorContentUpdated")
    static let editorBecameReady = Notification.Name("editorBecameReady")
    static let showSaveNamedVersion = Notification.Name("showSaveNamedVersion")
}
