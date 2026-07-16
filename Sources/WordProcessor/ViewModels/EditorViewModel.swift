import AppKit
import SwiftUI
import WebKit

@Observable
@MainActor
final class EditorViewModel {
    var webView: WKWebView? {
        didSet {
            applyCurrentZoomToWebView()
        }
    }
    var isEditorReady = false
    var assetBaseURL: URL?
    private var activeDocumentID = ""
    var selectionState = SelectionState()
    var zoomScale = EditorViewModel.storedZoomScale()
    var pendingEdits: [PendingEdit] = []
    var pendingEditCount = 0
    var pendingEditCurrentIndex = -1
    var activePendingEditID: String?
    var comments: [BridgePayload.CommentData] = []
    var activeCommentID: String?
    var ambientReviewEnabled = false
    var isAmbientReviewing = false
    var ambientReviewStatusText = ""
    var proofreadingStatus = "disabled"
    var proofreadingIssueCount = 0
    var proofreadingErrorMessage = ""
    var persistenceStatusText = ""
    var persistenceStatusIsError = false
    private var persistenceTimer: Timer?
    private var persistenceTask: Task<Void, Never>?
    private var ambientReviewTimer: Timer?
    private var ambientReviewTask: Task<Void, Never>?
    private var grammarCheckTimer: Timer?
    private var grammarCheckTask: Task<Void, Never>?
    private var checkedGrammarBlockHashes: [String: String] = [:]
    private var grammarIssuesByBlockID: [String: [DisplayedGrammarIssue]] = [:]
    private var lastAmbientReviewedDocumentHash: String?
    private var pendingSnapshot: DocumentFileStore.FileSnapshot?
    private var lastAutoSaveCheckpointByDocumentID: [String: Date] = [:]
    /// Set when the most recent snapshot capture fell back to last-synced state.
    private var lastSnapshotCaptureFailed = false
    private let autoSaveCheckpointInterval: TimeInterval = 60
    @ObservationIgnored private let ambientReviewService = LanguageModelService()
    @ObservationIgnored private let grammarService = LanguageModelService(
        purpose: .grammar,
        effort: nil
    )
    @ObservationIgnored private let thoroughGrammarService = LanguageModelService(
        purpose: .proofread,
        effort: "low"
    )
    /// Incremented each time the editor signals ready (supports detecting web process restarts).
    var editorReadyCount = 0
    private static let zoomDefaultsKey = "editorZoomScale"
    private static let minimumZoomScale = 0.5
    private static let maximumZoomScale = 2.0
    private static let defaultZoomScale = 1.0
    private static let zoomStep = 0.1
    private static let aiTropesGuidance: String = {
        guard let resourceURL = Bundle.shakespeareResources.url(forResource: "ai_tropes", withExtension: "md"),
              let content = try? String(contentsOf: resourceURL, encoding: .utf8)
        else { return "" }
        return content
    }()
    @ObservationIgnored private let trainingEventStore = TrainingEventStore.shared

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
        var isImage = false
        var imageLayout = "inline"
        var imageAlign = "center"
        var imageWidth = ""
        var imageHeight = ""

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
            isImage = state.isImage
            imageLayout = state.imageLayout
            imageAlign = state.imageAlign
            imageWidth = state.imageWidth
            imageHeight = state.imageHeight
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

        struct Placeholder: Decodable, Equatable {
            let blockId: String
            let from: Int
            let to: Int
            let text: String
        }

        let revision: Int
        let documentHash: String
        let plainText: String
        let cursorPosition: Int
        let nearbyText: String
        let selection: Selection?
        let blocks: [Block]
        let placeholders: [Placeholder]?
    }

    private struct GrammarContextSnapshot: Decodable {
        struct Block: Decodable {
            let id: String
            let from: Int
            let to: Int
            let text: String
            let textHash: String
            let type: String
        }

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

    private struct GrammarCheckIssue: Decodable {
        let id: String
        let blockID: String
        let exactOriginal: String
        let replacement: String
        let message: String
        let kind: String
        let rule: String

        enum CodingKeys: String, CodingKey {
            case id
            case blockID = "block_id"
            case exactOriginal = "exact_original"
            case replacement
            case message
            case kind
            case rule
        }
    }

    private struct GrammarCheckResponse: Decodable {
        let issues: [GrammarCheckIssue]
    }

    private struct GrammarVerificationDecision: Decodable {
        let id: String
        let verdict: String
    }

    private struct GrammarVerificationResponse: Decodable {
        let decisions: [GrammarVerificationDecision]
    }

    private struct DisplayedGrammarIssue {
        let id: String
        let from: Int
        let to: Int
        let kind: String
        let message: String
        let problem: String
        let replacement: String
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

        case .pendingEditUpdate(let update):
            pendingEditCount = update.count
            pendingEditCurrentIndex = update.currentIndex
            activePendingEditID = update.activeEditID
            pendingEdits = update.edits.map(PendingEdit.init)

        case .editDecision(let decision):
            trainingEventStore.appendEditDecision(
                decision,
                documentID: activeDocumentID,
                runtime: ambientReviewService.currentRuntime
            )

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

        case .proofreadingUpdate(let update):
            proofreadingStatus = update.status
            proofreadingIssueCount = update.issueCount
            proofreadingErrorMessage = update.message

        case .imageImportRequested(let request):
            guard !request.requestID.isEmpty,
                  !request.dataURL.isEmpty,
                  !activeDocumentID.isEmpty
            else { break }
            let sourceDocumentURL = assetBaseURL
            let documentID = activeDocumentID
            Task { [weak self] in
                guard let self else { return }
                do {
                    let staged = try await DocumentFileStore.shared.stageImageAsset(
                        from: request.dataURL,
                        documentID: documentID,
                        sourceDocumentURL: sourceDocumentURL
                    )
                    assetBaseURL = staged.baseURL
                    callEditorAPI(
                        "completeImageImport",
                        arguments: [request.requestID, staged.source, ""]
                    )
                } catch {
                    callEditorAPI(
                        "completeImageImport",
                        arguments: [request.requestID, "", error.localizedDescription]
                    )
                }
            }

        case .openURL(let urlString):
            guard let url = URL(string: urlString),
                  let scheme = url.scheme?.lowercased(),
                  scheme == "http" || scheme == "https" || scheme == "mailto"
            else { break }
            NSWorkspace.shared.open(url)

        case .unknown:
            break
        }
    }

    // MARK: - Content Loading

    func loadSnapshot(_ snapshot: DocumentFileStore.FileSnapshot) {
        activeDocumentID = snapshot.documentID
        lastAmbientReviewedDocumentHash = nil
        clearGrammarCheckingState()

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
            if let dictionary = result as? [String: Any] {
                completion(self?.parseEditorSnapshot(from: dictionary))
            } else if let jsonString = result as? String,
                      let data = jsonString.data(using: .utf8),
                      let dictionary = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                completion(self?.parseEditorSnapshot(from: dictionary))
            } else {
                completion(nil)
            }
        }
    }

    func applyFormat(_ command: String, value: String? = nil) {
        if let value = value {
            callEditorAPI("applyFormat", arguments: [command, value])
        } else {
            callEditorAPI("applyFormat", arguments: [command])
        }
    }

    func importImage(from fileURL: URL) async throws {
        guard !activeDocumentID.isEmpty else { return }
        let staged = try await DocumentFileStore.shared.stageImageAsset(
            from: fileURL,
            documentID: activeDocumentID,
            sourceDocumentURL: assetBaseURL
        )
        assetBaseURL = staged.baseURL
        applyFormat("insertImage", value: staged.source)
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

    private func currentGrammarContextSnapshot() async -> GrammarContextSnapshot? {
        await withCheckedContinuation { continuation in
            callEditorAPI("getGrammarContextSnapshot") { result in
                guard let jsonString = result as? String,
                      let data = jsonString.data(using: .utf8),
                      let snapshot = try? JSONDecoder().decode(GrammarContextSnapshot.self, from: data)
                else {
                    continuation.resume(returning: nil)
                    return
                }
                continuation.resume(returning: snapshot)
            }
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

    var zoomPercent: Int {
        Int((zoomScale * 100).rounded())
    }

    var canZoomIn: Bool {
        zoomScale < Self.maximumZoomScale
    }

    var canZoomOut: Bool {
        zoomScale > Self.minimumZoomScale
    }

    func zoomIn() {
        setZoomScale(zoomScale + Self.zoomStep)
    }

    func zoomOut() {
        setZoomScale(zoomScale - Self.zoomStep)
    }

    func resetZoom() {
        setZoomScale(Self.defaultZoomScale)
    }

    func setZoomScale(_ scale: Double) {
        let normalizedScale = Self.normalizedZoomScale(scale)
        zoomScale = normalizedScale
        UserDefaults.standard.set(normalizedScale, forKey: Self.zoomDefaultsKey)
        applyCurrentZoomToWebView()
    }

    func applyCurrentZoomToWebView() {
        webView?.pageZoom = 1
        callEditorAPI("setZoomScale", arguments: [zoomScale])
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

    // MARK: - Document Editing (for assistant tool use)

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
        metadata: [String: Any] = [:],
        completion: @escaping (Int) -> Void
    ) {
        callEditorAPI("pendingReplaceSelection", arguments: [id, html, target ?? [:], metadata]) { result in
            completion(result as? Int ?? 0)
        }
    }

    func pendingInsertAtCursor(
        id: String,
        html: String,
        target: [String: Any]? = nil,
        metadata: [String: Any] = [:],
        completion: @escaping (Int) -> Void
    ) {
        callEditorAPI("pendingInsertAtCursor", arguments: [id, html, target ?? [:], metadata]) { result in
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
        metadata: [String: Any] = [:],
        completion: @escaping (Int) -> Void
    ) {
        callEditorAPI("pendingProposeEdit", arguments: [id, target, replacementHTML, replaceAll, metadata]) { result in
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
        if status == "dismissed",
           let comment = comments.first(where: { $0.id == commentId && $0.source == "agent" }) {
            trainingEventStore.appendCommentDecision(
                decision: "reject",
                comment: comment,
                documentID: activeDocumentID,
                runtime: ambientReviewService.currentRuntime
            )
        }
        callEditorAPI("setCommentStatus", arguments: [commentId, status])
    }

    func removeComment(_ commentId: String) {
        if let comment = comments.first(where: { $0.id == commentId && $0.source == "agent" && $0.status == "open" }) {
            trainingEventStore.appendCommentDecision(
                decision: "reject",
                comment: comment,
                documentID: activeDocumentID,
                runtime: ambientReviewService.currentRuntime
            )
        }
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

    // MARK: - Grammar Checking

    func scheduleGrammarCheck(delay: TimeInterval = 4) {
        grammarCheckTimer?.invalidate()
        grammarCheckTimer = nil
        grammarCheckTask?.cancel()

        guard TextCheckingSettings.shared.grammarCheckingEnabled else { return }

        grammarCheckTimer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
            Task { @MainActor in
                self?.startGrammarCheck()
            }
        }
    }

    func grammarCheckingSettingsDidChange() {
        if TextCheckingSettings.shared.grammarCheckingEnabled {
            checkedGrammarBlockHashes = [:]
            scheduleGrammarCheck(delay: 0)
        } else {
            clearGrammarCheckingState()
        }
    }

    private func startGrammarCheck() {
        guard TextCheckingSettings.shared.grammarCheckingEnabled else { return }
        grammarCheckTask?.cancel()
        grammarCheckTask = Task { [weak self] in
            guard let self else { return }
            await self.runGrammarCheck(
                using: self.grammarService,
                temperature: 0,
                requiresEnabledSetting: true,
                verifiesCandidates: true
            )
        }
    }

    func runThoroughProofread() {
        grammarCheckTimer?.invalidate()
        grammarCheckTimer = nil
        grammarCheckTask?.cancel()
        checkedGrammarBlockHashes = [:]
        grammarCheckTask = Task { [weak self] in
            guard let self else { return }
            await self.runGrammarCheck(
                using: self.thoroughGrammarService,
                temperature: nil,
                requiresEnabledSetting: false,
                verifiesCandidates: false
            )
        }
    }

    private func runGrammarCheck(
        using service: LanguageModelService,
        temperature: Double?,
        requiresEnabledSetting: Bool,
        verifiesCandidates: Bool
    ) async {
        defer { grammarCheckTask = nil }

        if requiresEnabledSetting {
            guard TextCheckingSettings.shared.grammarCheckingEnabled else { return }
        }
        guard let context = await currentGrammarContextSnapshot() else { return }

        let currentBlockIDs = Set(context.blocks.map(\.id))
        grammarIssuesByBlockID = grammarIssuesByBlockID.filter { currentBlockIDs.contains($0.key) }
        checkedGrammarBlockHashes = checkedGrammarBlockHashes.filter { currentBlockIDs.contains($0.key) }

        let changedBlocks = context.blocks.filter { block in
            block.type != "codeBlock"
                && !block.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                && checkedGrammarBlockHashes[block.id] != block.textHash
        }
        guard !changedBlocks.isEmpty else { return }

        proofreadingStatus = "checking"
        proofreadingErrorMessage = ""

        do {
            for batch in grammarBlockBatches(changedBlocks) {
                try Task.checkCancellation()

                for block in batch {
                    grammarIssuesByBlockID[block.id] = []
                }
                publishGrammarIssues()

                var response = try await collectGrammarResponse(
                    blocks: batch,
                    using: service,
                    temperature: temperature
                )
                try Task.checkCancellation()
                if verifiesCandidates, !response.issues.isEmpty {
                    response = try await verifyGrammarResponse(response, blocks: batch)
                    try Task.checkCancellation()
                }
                applyGrammarResponse(response, to: batch)

                for block in batch {
                    checkedGrammarBlockHashes[block.id] = block.textHash
                }
                publishGrammarIssues()
            }
            proofreadingStatus = "ready"
        } catch is CancellationError {
            return
        } catch {
            proofreadingStatus = "error"
            proofreadingErrorMessage = "Grammar check failed: \(error.localizedDescription)"
        }
    }

    private func grammarBlockBatches(
        _ blocks: [GrammarContextSnapshot.Block],
        maximumCharacters: Int = 12_000,
        maximumBlocks: Int = 30
    ) -> [[GrammarContextSnapshot.Block]] {
        var batches: [[GrammarContextSnapshot.Block]] = []
        var current: [GrammarContextSnapshot.Block] = []
        var characters = 0

        for block in blocks {
            let blockCharacters = block.text.count
            if !current.isEmpty,
               current.count >= maximumBlocks || characters + blockCharacters > maximumCharacters {
                batches.append(current)
                current = []
                characters = 0
            }
            current.append(block)
            characters += blockCharacters
        }
        if !current.isEmpty {
            batches.append(current)
        }
        return batches
    }

    private func collectGrammarResponse(
        blocks: [GrammarContextSnapshot.Block],
        using service: LanguageModelService,
        temperature: Double?
    ) async throws -> GrammarCheckResponse {
        let dialect = TextCheckingSettings.shared.dialect
        let blockPayload = blocks.map { block in
            ["id": block.id, "type": block.type, "text": block.text]
        }
        guard JSONSerialization.isValidJSONObject(blockPayload),
              let blockData = try? JSONSerialization.data(withJSONObject: blockPayload),
              let blockJSON = String(data: blockData, encoding: .utf8)
        else {
            throw LanguageModelService.APIError.invalidResponse
        }

        let systemPrompt = """
        You are a conservative grammar checker inside a word processor. Flag a passage only when the original is grammatically invalid under standard edited English.
        Use \(dialect) English conventions.

        An issue must fit exactly one of these objective rules:
        - agreement
        - verb_form_or_tense
        - article_or_determiner
        - preposition
        - pronoun
        - number_or_possessive
        - word_order
        - missing_or_extra_word
        - conjunction
        - confused_word (only an unambiguously incorrect word, not a better word)
        - punctuation (only punctuation required for grammatical correctness)
        - capitalization

        Never flag awkwardness, wordiness, concision, clarity, fluency, tone, formality, vocabulary preference, sentence length, passive voice, repeated words, optional commas, the Oxford comma, split infinitives, sentence-ending prepositions, singular "they," contractions, dialect or register, disputed usage, or any other defensible stylistic choice. In particular, do not enforce less/fewer preferences or rewrite "the reason is because"; treat those as usage/style, not grammar. Preserve deliberate fragments, quotations, names, meaning, voice, and factual claims. If a construction is acceptable in context, debatable, or merely improvable, emit no issue. Precision is more important than recall.

        Each issue must target one supplied block. exact_original must be a nonempty, exact, uniquely occurring substring copied verbatim from that block.
        replacement must be the smallest replacement for exact_original that fixes the error. For an insertion, include a small existing anchor in exact_original and return that anchor with the insertion in replacement.
        Give each issue a unique short id. message must identify the violated grammatical rule, not describe a stylistic benefit. kind must be Grammar or Punctuation.
        """

        let messages: [[String: Any]] = [[
            "role": "user",
            "content": "Check these changed document blocks. Return structured JSON only.\n\(blockJSON)"
        ]]

        let outputFormat: [String: Any] = [
            "type": "json_schema",
            "schema": [
                "type": "object",
                "properties": [
                    "issues": [
                        "type": "array",
                        "items": [
                            "type": "object",
                            "properties": [
                                "id": ["type": "string"],
                                "block_id": ["type": "string"],
                                "exact_original": ["type": "string"],
                                "replacement": ["type": "string"],
                                "message": ["type": "string"],
                                "kind": [
                                    "type": "string",
                                    "enum": ["Grammar", "Punctuation"]
                                ],
                                "rule": [
                                    "type": "string",
                                    "enum": [
                                        "agreement",
                                        "verb_form_or_tense",
                                        "article_or_determiner",
                                        "preposition",
                                        "pronoun",
                                        "number_or_possessive",
                                        "word_order",
                                        "missing_or_extra_word",
                                        "conjunction",
                                        "confused_word",
                                        "punctuation",
                                        "capitalization",
                                    ]
                                ],
                            ],
                            "required": ["id", "block_id", "exact_original", "replacement", "message", "kind", "rule"],
                            "additionalProperties": false,
                        ],
                    ],
                ],
                "required": ["issues"],
                "additionalProperties": false,
            ] as [String: Any],
        ]

        var responseText = ""
        for try await chunk in service.streamMessage(
            messages: messages,
            systemPrompt: systemPrompt,
            tools: nil,
            cacheControl: nil,
            outputFormat: outputFormat,
            temperature: temperature,
            maxTokens: 4096
        ) {
            if case .text(let text) = chunk {
                responseText += text
            }
        }

        guard let data = jsonObjectData(from: responseText) else {
            throw LanguageModelService.APIError.invalidResponse
        }
        return try JSONDecoder().decode(GrammarCheckResponse.self, from: data)
    }

    /// The first-pass detector is intentionally followed by a separate, conservative
    /// adjudication pass. A candidate must survive both passes before it is shown.
    private func verifyGrammarResponse(
        _ response: GrammarCheckResponse,
        blocks: [GrammarContextSnapshot.Block]
    ) async throws -> GrammarCheckResponse {
        let dialect = TextCheckingSettings.shared.dialect
        let blocksByID = Dictionary(uniqueKeysWithValues: blocks.map { ($0.id, $0.text) })
        let candidates: [[String: String]] = response.issues.compactMap { issue in
            guard let blockText = blocksByID[issue.blockID] else { return nil }
            return [
                "id": issue.id,
                "block_id": issue.blockID,
                "block_text": blockText,
                "exact_original": issue.exactOriginal,
                "replacement": issue.replacement,
                "claimed_rule": issue.rule,
                "detector_explanation": issue.message,
            ]
        }
        guard !candidates.isEmpty,
              JSONSerialization.isValidJSONObject(candidates),
              let candidateData = try? JSONSerialization.data(withJSONObject: candidates),
              let candidateJSON = String(data: candidateData, encoding: .utf8)
        else { return GrammarCheckResponse(issues: []) }

        let systemPrompt = """
        You are the strict final gate for an automatic grammar checker. Independently judge each proposed correction using \(dialect) English.

        Accept a candidate only if all of these are true:
        1. The exact original clearly violates a rule of standard edited English in its full block context.
        2. The problem is objective, not stylistic, optional, regional, register-dependent, or reasonably debatable.
        3. The replacement is the smallest correction and preserves meaning and voice.

        Reject candidates about awkwardness, wordiness, concision, clarity, fluency, tone, formality, vocabulary preference, sentence length, passive voice, repetition, optional commas, the Oxford comma, split infinitives, sentence-ending prepositions, singular "they," contractions, deliberate fragments, dialect, or disputed usage. Do not accept a candidate merely because the proposed replacement also sounds natural.

        For calibration, all of these are grammatical and any proposed rewrite must be rejected: "Where are you at?"; "Due to the fact that it rained, we stayed home"; "I think that that is correct"; "Less people attended"; and "The reason is because costs rose." They may attract usage or style advice, but they are not errors for this checker. Reject any candidate if you are uncertain. False positives are substantially worse than missed errors.

        Return exactly one decision for every supplied candidate, in the same order. Use actual_error only when every acceptance condition is met; otherwise use style_or_uncertain. Do not omit a candidate. Do not repair or replace candidates.
        """
        let messages: [[String: Any]] = [[
            "role": "user",
            "content": "Adjudicate these proposed corrections. Return structured JSON only.\n\(candidateJSON)",
        ]]
        let outputFormat: [String: Any] = [
            "type": "json_schema",
            "schema": [
                "type": "object",
                "properties": [
                    "decisions": [
                        "type": "array",
                        "items": [
                            "type": "object",
                            "properties": [
                                "id": ["type": "string"],
                                "verdict": [
                                    "type": "string",
                                    "enum": ["actual_error", "style_or_uncertain"],
                                ],
                            ],
                            "required": ["id", "verdict"],
                            "additionalProperties": false,
                        ],
                    ],
                ],
                "required": ["decisions"],
                "additionalProperties": false,
            ] as [String: Any],
        ]

        var responseText = ""
        for try await chunk in grammarService.streamMessage(
            messages: messages,
            systemPrompt: systemPrompt,
            tools: nil,
            cacheControl: nil,
            outputFormat: outputFormat,
            temperature: 0,
            maxTokens: 1024
        ) {
            if case .text(let text) = chunk {
                responseText += text
            }
        }

        guard let data = jsonObjectData(from: responseText) else {
            throw LanguageModelService.APIError.invalidResponse
        }
        let verification = try JSONDecoder().decode(GrammarVerificationResponse.self, from: data)
        let acceptedIDs = Set(
            verification.decisions
                .filter { $0.verdict == "actual_error" }
                .map(\.id)
        )
        return GrammarCheckResponse(issues: response.issues.filter { acceptedIDs.contains($0.id) })
    }

    private func applyGrammarResponse(
        _ response: GrammarCheckResponse,
        to blocks: [GrammarContextSnapshot.Block]
    ) {
        let blocksByID = Dictionary(uniqueKeysWithValues: blocks.map { ($0.id, $0) })
        var acceptedRangesByBlockID: [String: [(start: Int, end: Int)]] = [:]

        for issue in response.issues {
            guard let block = blocksByID[issue.blockID],
                  !issue.exactOriginal.isEmpty,
                  issue.exactOriginal != issue.replacement,
                  let range = block.text.range(of: issue.exactOriginal),
                  block.text[range.upperBound...].range(of: issue.exactOriginal) == nil,
                  let lowerBound = range.lowerBound.samePosition(in: block.text.utf16)
            else { continue }

            let offset = block.text.utf16.distance(from: block.text.utf16.startIndex, to: lowerBound)
            let start = block.from + offset
            let end = start + issue.exactOriginal.utf16.count
            let candidateRange = (start: start, end: end)
            let existingRanges = acceptedRangesByBlockID[block.id, default: []]
            guard !existingRanges.contains(where: { rangesOverlap($0, candidateRange) }) else { continue }

            let displayed = DisplayedGrammarIssue(
                id: "ai_grammar_\(UUID().uuidString)",
                from: start,
                to: end,
                kind: issue.kind,
                message: issue.message,
                problem: issue.exactOriginal,
                replacement: issue.replacement
            )
            grammarIssuesByBlockID[block.id, default: []].append(displayed)
            acceptedRangesByBlockID[block.id, default: []].append(candidateRange)
        }
    }

    private func publishGrammarIssues() {
        let payload: [[String: Any]] = grammarIssuesByBlockID.values.flatMap { issues in
            issues.map { issue in
                [
                    "id": issue.id,
                    "from": issue.from,
                    "to": issue.to,
                    "kind": issue.kind,
                    "message": issue.message,
                    "problem": issue.problem,
                    "replacement": issue.replacement,
                ]
            }
        }

        guard JSONSerialization.isValidJSONObject(payload),
              let data = try? JSONSerialization.data(withJSONObject: payload),
              let json = String(data: data, encoding: .utf8)
        else { return }
        callEditorAPI("setAIGrammarIssues", arguments: [json])
    }

    private func clearGrammarCheckingState() {
        grammarCheckTimer?.invalidate()
        grammarCheckTimer = nil
        grammarCheckTask?.cancel()
        grammarCheckTask = nil
        checkedGrammarBlockHashes = [:]
        grammarIssuesByBlockID = [:]
        callEditorAPI("setAIGrammarIssues", arguments: ["[]"])
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
        var systemPrompt: [[String: Any]] = [
            [
                "type": "text",
                "text": """
                You are an ambient editor inside a word processor. The user has explicitly enabled background review.
                Return only compact JSON. Do not use Markdown.
                Find at most 4 high-signal opportunities to improve clarity, structure, accuracy, tone, concision, or adherence to the user's author voice.
                Only comment on text you can anchor to a block in the supplied edit context.
                For voice suggestions, use the author voice reference to identify concrete sentence- or paragraph-level departures: rhetorical-question pivots, throat-clearing, vague abstraction, filler, generic internet-essay phrasing, weak paragraph endings, or places where a flatter declarative, sharper catalogue, more precise noun, or tighter rhythm would better fit the user's voice.
                Voice comments must be specific and actionable. Prefer a small suggested_replacement when the fix is local. Do not ask the user to rewrite a whole section in the abstract.
                You will receive existing comments. Treat them as already-covered feedback, even if resolved or dismissed.
                Do not repeat, paraphrase, or add a nearby overlapping version of an existing comment. If the only useful feedback is already covered, return {"comments":[]}.
                Schema:
                {"comments":[{"block_id":"...","exact_original":"exact current text span","comment":"short rationale","kind":"clarity|structure|tone|voice|concision|grammar|accuracy","severity":"low|medium|high","suggested_replacement":"optional replacement HTML or plain text"}]}
                If there is nothing worth saying, return {"comments":[]}.
                """,
                "cache_control": LanguageModelService.oneHourPromptCacheControl
            ]
        ]

        if !AuthorStyleReference.content.isEmpty {
            systemPrompt.append([
                "type": "text",
                "text": """
                <author_voice_reference>
                Use this fixed style reference when deciding whether to add ambient voice suggestions. Follow the guidance without copying examples verbatim.

                \(AuthorStyleReference.content)
                </author_voice_reference>
                """,
                "cache_control": LanguageModelService.oneHourPromptCacheControl
            ])
        }

        if !Self.aiTropesGuidance.isEmpty {
            systemPrompt.append([
                "type": "text",
                "text": """
                <writing_style_guidance>
                When writing or editing text for the user, follow this guidance carefully:

                \(Self.aiTropesGuidance)
                </writing_style_guidance>
                """,
                "cache_control": LanguageModelService.oneHourPromptCacheControl
            ])
        }

        let learnedPreferences = AuthorStyleReference.learnedPreferences.trimmingCharacters(in: .whitespacesAndNewlines)
        if !learnedPreferences.isEmpty {
            systemPrompt.append([
                "type": "text",
                "text": """
                <learned_style_preferences>
                Rules distilled from the author's accepted/rejected edits. Where these conflict with the general voice reference, these win because they are more recent and more specific.

                \(learnedPreferences)
                </learned_style_preferences>
                """,
                "cache_control": LanguageModelService.oneHourPromptCacheControl
            ])
        }

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
        let recentRejected = ambientRecentRejectedSuggestionsXML()
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
        \(recentRejected)
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

    private func ambientRecentRejectedSuggestionsXML(limit: Int = 10) -> String {
        let rejected = trainingEventStore.recentRejectedDecisions(limit: limit)
        guard !rejected.isEmpty else {
            return "<recent_rejected_suggestions />"
        }

        let lines = rejected.map { decision in
            """
            <rejected_suggestion source="\(xmlEscaped(decision.source))" kind="\(xmlEscaped(decision.kind))">
            <original>\(xmlEscaped(decision.originalText))</original>
            <replacement>\(xmlEscaped(decision.replacementText))</replacement>
            <context>\(xmlEscaped(decision.surroundingSentence))</context>
            </rejected_suggestion>
            """
        }.joined(separator: "\n")

        return """
        <recent_rejected_suggestions>
        The author rejected these suggestions recently. Do not repeat similar suggestions.
        \(lines)
        </recent_rejected_suggestions>
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

    private func jsonObjectData(from responseText: String) -> Data? {
        let trimmed = responseText
            .replacingOccurrences(of: "```json", with: "")
            .replacingOccurrences(of: "```", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let candidate = jsonSubstring(in: trimmed, opening: "{", closing: "}") ?? trimmed
        return candidate.data(using: .utf8)
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
        if preferEditorState {
            if let snapshot = await captureEditorSnapshot(document: document) {
                document.syncFromEditor(snapshot: snapshot)
                lastSnapshotCaptureFailed = false
            } else if isEditorReady {
                // The editor should have produced a snapshot; falling back to
                // the last-synced state means live edits may not be captured.
                print("Editor snapshot capture failed; using last-synced document state")
                lastSnapshotCaptureFailed = true
            }
        }
        return document.currentSnapshot()
    }

    // MARK: - Auto-Save

    func schedulePersistence(document: DocumentModel) {
        persistenceTimer?.invalidate()
        guard document.isDirty else { return }

        let delay: TimeInterval = document.fileURL == nil ? 2 : 5
        persistenceTimer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.startScheduledPersistence(document: document)
            }
        }
    }

    private func startScheduledPersistence(document: DocumentModel) {
        let previousTask = persistenceTask
        persistenceTask = Task { @MainActor [weak self] in
            guard let self else { return }
            if let previousTask {
                await previousTask.value
            }
            await performScheduledPersistence(document: document)
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

    private func performScheduledPersistence(document: DocumentModel) async {
        guard document.isDirty else { return }
        let snapshot = await latestSnapshot(for: document)

        if let url = document.fileURL {
            let saved = await persistDocument(
                document: document,
                to: url,
                captureLatestEditorState: false,
                createVersionSnapshot: shouldCreateAutoSaveCheckpoint(for: document),
                actionName: "Auto-save",
                providedSnapshot: snapshot
            )
            if !saved {
                await saveRecoveryDraft(document: document, providedSnapshot: snapshot)
            }
        } else {
            await saveRecoveryDraft(document: document, providedSnapshot: snapshot)
        }
    }

    private func flushBeforeDocumentChange(document: DocumentModel) async {
        persistenceTimer?.invalidate()
        persistenceTimer = nil
        if let persistenceTask {
            await persistenceTask.value
            self.persistenceTask = nil
        }
        ambientReviewTimer?.invalidate()
        ambientReviewTimer = nil
        ambientReviewTask?.cancel()
        ambientReviewTask = nil
        grammarCheckTimer?.invalidate()
        grammarCheckTimer = nil
        grammarCheckTask?.cancel()
        grammarCheckTask = nil

        guard document.isDirty else { return }
        let snapshot = await latestSnapshot(for: document)

        if let url = document.fileURL {
            _ = await persistDocument(
                document: document,
                to: url,
                captureLatestEditorState: false,
                createVersionSnapshot: false,
                actionName: "Flush",
                providedSnapshot: snapshot
            )
        } else {
            await saveRecoveryDraft(document: document, providedSnapshot: snapshot)
        }
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

    private func saveRecoveryDraft(
        document: DocumentModel,
        providedSnapshot: DocumentFileStore.FileSnapshot? = nil
    ) async {
        guard document.isDirty else { return }

        do {
            let snapshot: DocumentFileStore.FileSnapshot
            if let providedSnapshot {
                snapshot = providedSnapshot
            } else {
                snapshot = await latestSnapshot(for: document)
            }
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
            persistenceTimer?.invalidate()
            persistenceTimer = nil

            do {
                let draft = try await RecoveryDraftStore.shared.loadDraft(id: metadata.id)
                let originalFileURL = await RecoveryDraftStore.shared.originalFileURL(for: draft.metadata)
                document.recoverDraft(snapshot: draft.snapshot, originalFileURL: originalFileURL)
                assetBaseURL = draft.packageURL
                loadSnapshot(draft.snapshot)
                setPersistenceStatus("Recovered draft \(formattedStatusTime())", isError: false)
                schedulePersistence(document: document)
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
        persistenceTimer?.invalidate()
        persistenceTimer = nil

        if let url = document.fileURL {
            Task { @MainActor in
                _ = await persistDocument(
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
        persistenceTimer?.invalidate()
        persistenceTimer = nil

        let panel = NSSavePanel()
        panel.allowedContentTypes = [.shakespeareDocument]
        panel.nameFieldStringValue = document.displayName + ".\(DocumentFileStore.documentPackageExtension)"

        panel.begin { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            Task { @MainActor in
                _ = await self?.persistDocument(
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
        actionName: String,
        providedSnapshot: DocumentFileStore.FileSnapshot? = nil
    ) async -> Bool {
        let resolvedSnapshot: DocumentFileStore.FileSnapshot
        if let providedSnapshot {
            resolvedSnapshot = providedSnapshot
        } else {
            resolvedSnapshot = await latestSnapshot(
                for: document,
                preferEditorState: captureLatestEditorState
            )
        }
        let request = document.makePersistenceRequest(snapshot: resolvedSnapshot)
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
            let acknowledgedOutcomes = trainingEventStore.appendOutcomes(
                request.snapshot.personalizationOutcomes,
                documentID: persistedSnapshot.documentID,
                runtime: ambientReviewService.currentRuntime
            )
            if !acknowledgedOutcomes.isEmpty {
                callEditorAPI("acknowledgePersonalizationOutcomes", arguments: [acknowledgedOutcomes])
            }
            trainingEventStore.appendDocumentSnapshot(persistedSnapshot)

            if !document.isDirty {
                try? await RecoveryDraftStore.shared.deleteDraft(documentID: persistedSnapshot.documentID)
                if sourceDocumentURL != url {
                    try? await DocumentFileStore.shared.deleteWorkingAssets(
                        documentID: persistedSnapshot.documentID
                    )
                }
            }
            if lastSnapshotCaptureFailed {
                setPersistenceStatus(
                    "\(actionName) saved last-synced state \(formattedStatusTime()) — latest edits may be missing",
                    isError: true
                )
            } else {
                setPersistenceStatus("\(actionName) saved \(formattedStatusTime())", isError: false)
            }
            return true
        } catch {
            setPersistenceStatus("\(actionName) failed: \(error.localizedDescription)", isError: true)
            return false
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
                        modifiedAt: Date(),
                        personalizationOutcomes: snapshot.personalizationOutcomes
                    )
                )
            }
        }
    }

    private func parseEditorSnapshot(from dict: [String: Any]) -> DocumentFileStore.FileSnapshot? {
        let html = dict["html"] as? String ?? ""
        let plainText = dict["text"] as? String ?? ""
        let words = dict["words"] as? Int
        let characters = dict["characters"] as? Int
        let personalizationOutcomes = (dict["personalizationOutcomes"] as? [[String: Any]] ?? [])
            .compactMap { item -> PersonalizationOutcomeSnapshot? in
                guard let actionID = item["actionId"] as? String,
                      !actionID.isEmpty,
                      let outcome = item["outcome"] as? String,
                      let finalText = item["finalText"] as? String,
                      let confidence = item["confidence"] as? Double,
                      let trainingEligible = item["trainingEligible"] as? Bool
                else { return nil }
                return PersonalizationOutcomeSnapshot(
                    actionID: actionID,
                    outcome: outcome,
                    finalText: finalText,
                    confidence: confidence,
                    trainingEligible: trainingEligible
                )
            }

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
            characterCount: characters,
            personalizationOutcomes: personalizationOutcomes
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
        value.htmlEscaped
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

    private static func storedZoomScale() -> Double {
        let storedScale = UserDefaults.standard.double(forKey: zoomDefaultsKey)
        guard storedScale > 0 else { return defaultZoomScale }
        return normalizedZoomScale(storedScale)
    }

    private static func normalizedZoomScale(_ scale: Double) -> Double {
        let clampedScale = min(max(scale, minimumZoomScale), maximumZoomScale)
        return (clampedScale / zoomStep).rounded() * zoomStep
    }

    private func evaluateJS(_ js: String, completion: ((Any?) -> Void)? = nil) {
        guard let webView = webView else {
            completion?(nil)
            return
        }

        webView.evaluateJavaScript(js) { result, error in
            if let error {
                let nsError = error as NSError
                if nsError.domain == WKError.errorDomain,
                   nsError.code == WKError.webContentProcessTerminated.rawValue {
                    print("JS evaluation failed: web content process terminated")
                } else {
                    print("JS error (\(nsError.domain) \(nsError.code)): \(error.localizedDescription)")
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
    static let grammarCheckingSettingsChanged = Notification.Name("grammarCheckingSettingsChanged")
    static let showSaveNamedVersion = Notification.Name("showSaveNamedVersion")
}
