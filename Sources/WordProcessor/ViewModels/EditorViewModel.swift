import AppKit
import SwiftUI
import WebKit

@Observable
@MainActor
final class EditorViewModel {
    private enum VersionRestoreError: LocalizedError {
        case editorRejectedSnapshot

        var errorDescription: String? {
            "The editor rejected the selected version, so the current draft was kept."
        }
    }
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
    var pendingSelectionFeedbackRequest: SelectionFeedbackRequest?
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
    private(set) var isDocumentTransitioning = false
    private var persistenceTimer: Timer?
    private var persistenceTask: Task<Void, Never>?
    private var ambientReviewTimer: Timer?
    private var ambientReviewTask: Task<Void, Never>?
    private var ambientReviewGeneration: UInt64 = 0
    private var grammarCheckTimer: Timer?
    private var grammarCheckTask: Task<Void, Never>?
    private var grammarCheckGeneration: UInt64 = 0
    private var gapFillTasks: [String: Task<Void, Never>] = [:]
    private var gapFillTaskIDs: [String: UUID] = [:]
    private var checkedGrammarBlockHashes: [String: String] = [:]
    private var grammarIssuesByBlockID: [String: [DisplayedGrammarIssue]] = [:]
    private var ambientReviewedBlockHashes: [String: String] = [:]
    private var pendingSnapshot: DocumentFileStore.FileSnapshot?
    private var lastAutoSaveCheckpointByDocumentID: [String: Date] = [:]
    /// Set when the most recent snapshot capture could not prove current state.
    private var lastSnapshotCaptureFailed = false
    private let autoSaveCheckpointInterval: TimeInterval = 60
    @ObservationIgnored private let ambientReviewService = LanguageModelService(
        purpose: .ambientReview
    )
    @ObservationIgnored private let gapFillService = LanguageModelService(purpose: .gapFill)
    @ObservationIgnored private let grammarService = LanguageModelService(purpose: .grammar)
    @ObservationIgnored private let thoroughGrammarService = LanguageModelService(purpose: .proofread)
    /// Incremented each time the editor signals ready (supports detecting web process restarts).
    var editorReadyCount = 0
    private static let zoomDefaultsKey = "editorZoomScale"
    private static let minimumZoomScale = 0.5
    private static let maximumZoomScale = 2.0
    private static let defaultZoomScale = 1.0
    private static let zoomStep = 0.1
    @ObservationIgnored private let trainingEventStore = TrainingEventStore.shared

    struct SelectionState: Equatable {
        var isBold = false
        var isItalic = false
        var isUnderline = false
        var isStrike = false
        var isBulletList = false
        var isOrderedList = false
        var isBlockquote = false
        var heading = 0
        var textAlign = "left"
        var hasSelection = false
        var selectedWords = 0
        var selectedCharacters = 0
        var isLink = false
        var linkHref = ""
        var textColor = ""
        var isTextColorMixed = false
        var fontFamily = ""
        var isFontFamilyMixed = false
        var fontSize = ""
        var isFontSizeMixed = false
        var lineHeight = ""
        var isLineHeightMixed = false
        var isFootnote = false
        var footnoteText = ""
        var isImage = false
        var imageLayout = "inline"
        var imageAlign = "center"
        var imageWidth = ""
        var imageHeight = ""
        var imageAlt = ""
        var imageDecorative = false

        init() {}

        init(_ state: BridgePayload.SelectionState) {
            isBold = state.isBold
            isItalic = state.isItalic
            isUnderline = state.isUnderline
            isStrike = state.isStrike
            isBulletList = state.isBulletList
            isOrderedList = state.isOrderedList
            isBlockquote = state.isBlockquote
            heading = state.heading
            textAlign = state.textAlign
            hasSelection = state.hasSelection
            selectedWords = state.selectedWords
            selectedCharacters = state.selectedCharacters
            isLink = state.isLink
            linkHref = state.linkHref
            textColor = state.textColor
            isTextColorMixed = state.isTextColorMixed
            fontFamily = state.fontFamily
            isFontFamilyMixed = state.isFontFamilyMixed
            fontSize = state.fontSize
            isFontSizeMixed = state.isFontSizeMixed
            lineHeight = state.lineHeight
            isLineHeightMixed = state.isLineHeightMixed
            isFootnote = state.isFootnote
            footnoteText = state.footnoteText
            isImage = state.isImage
            imageLayout = state.imageLayout
            imageAlign = state.imageAlign
            imageWidth = state.imageWidth
            imageHeight = state.imageHeight
            imageAlt = state.imageAlt
            imageDecorative = state.imageDecorative
        }
    }

    struct SelectionFeedbackRequest: Identifiable {
        let id = UUID()
        let selection: String
        let documentContent: String
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
        var expectedText: String?
        var sourceRevision: Int?
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
    func handleBridgeMessage(_ payload: BridgePayload) {
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

        case .documentMetrics(_, let words, let characters):
            NotificationCenter.default.post(
                name: .editorDocumentMetricsUpdated,
                object: self,
                userInfo: ["words": words, "characters": characters]
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

        case .proofreadingUserStateChanged(let json):
            TextCheckingSettings.shared.persistProofreadingUserState(json)

        case .selectionFeedbackRequested:
            NotificationCenter.default.post(name: .selectionFeedbackRequested, object: self)

        case .gapFillRequested(let request):
            gapFillTasks[request.requestID]?.cancel()
            let taskID = UUID()
            gapFillTaskIDs[request.requestID] = taskID
            gapFillTasks[request.requestID] = Task { [weak self] in
                await self?.runGapFill(request, taskID: taskID)
            }

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
                        sourceDocumentURL: sourceDocumentURL,
                        referencedAssetFilenames: Set(
                            request.referencedSources.compactMap(DocumentAssetReference.filename(from:))
                        )
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
        cancelGapFillTasks()
        activeDocumentID = snapshot.documentID
        ambientReviewedBlockHashes = [:]
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

    private func applySnapshotToEditor(
        _ snapshot: DocumentFileStore.FileSnapshot,
        completion: @escaping (Bool) -> Void
    ) {
        if let canonicalJSON = snapshot.canonicalJSON, !canonicalJSON.isEmpty {
            callEditorAPI("loadJSONContent", arguments: [canonicalJSON]) { result in
                completion(result as? Bool == true)
            }
        } else {
            callEditorAPI("loadContent", arguments: [snapshot.htmlContent]) { result in
                completion(result as? Bool == true)
            }
        }
    }

    private func loadSnapshotIntoReadyEditor(_ snapshot: DocumentFileStore.FileSnapshot) async -> Bool {
        guard isEditorReady else { return false }
        return await withCheckedContinuation { continuation in
            applySnapshotToEditor(snapshot) { success in
                continuation.resume(returning: success)
            }
        }
    }

    private func setEditorEditable(_ enabled: Bool) {
        callEditorAPI("setEditorEditable", arguments: [enabled])
    }

    // MARK: - Snapshot Capture

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
        guard let referencedAssetFilenames = await referencedAssetFilenamesInEditor() else {
            throw NSError(
                domain: "Shakespeare.Editor",
                code: 2,
                userInfo: [NSLocalizedDescriptionKey: "Could not verify the document's existing image references."]
            )
        }
        let staged = try await DocumentFileStore.shared.stageImageAsset(
            from: fileURL,
            documentID: activeDocumentID,
            sourceDocumentURL: assetBaseURL,
            referencedAssetFilenames: referencedAssetFilenames
        )
        assetBaseURL = staged.baseURL
        applyFormat("insertImage", value: staged.source)
    }

    private func referencedAssetFilenamesInEditor() async -> Set<String>? {
        guard isEditorReady else { return nil }
        return await withCheckedContinuation { continuation in
            callEditorAPI("getReferencedAssetSources") { result in
                guard let json = result as? String,
                      json.utf8.count <= 2 * 1_024 * 1_024,
                      let data = json.data(using: .utf8),
                      let sources = try? JSONDecoder().decode([String].self, from: data)
                else {
                    continuation.resume(returning: nil)
                    return
                }
                continuation.resume(returning: Set(
                    sources.prefix(2_048).compactMap(DocumentAssetReference.filename(from:))
                ))
            }
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

    func queueSelectionFeedback(selection: String, documentContent: String) {
        let selectedText = selection.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !selectedText.isEmpty else { return }
        pendingSelectionFeedbackRequest = SelectionFeedbackRequest(
            selection: String(selectedText.prefix(6_000)),
            documentContent: documentContent
        )
    }

    func consumeSelectionFeedbackRequest(id: UUID) {
        guard pendingSelectionFeedbackRequest?.id == id else { return }
        pendingSelectionFeedbackRequest = nil
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

    func setDefaultTypography(fontFamily: String, fontSize: Double, lineHeight: Double) {
        callEditorAPI(
            "setDefaultTypography",
            arguments: [fontFamily, fontSize, lineHeight]
        )
    }

    // MARK: - Document Editing (for assistant tool use)

    func deleteSelection() {
        callEditorAPI("deleteSelection")
    }

    // MARK: - Pending edit diff review

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
        var payload: [String: Any] = [
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
        if let expectedText = comment.expectedText {
            payload["expectedText"] = expectedText
        }
        if let sourceRevision = comment.sourceRevision {
            payload["sourceRevision"] = sourceRevision
        }

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
        expectedText: String? = nil,
        sourceRevision: Int? = nil,
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
                allowOverlap: false,
                expectedText: expectedText,
                sourceRevision: sourceRevision
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
        cancelGrammarCheckTask()

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
        cancelGrammarCheckTask()
        let generation = grammarCheckGeneration
        grammarCheckTask = Task { [weak self] in
            guard let self else { return }
            await self.runGrammarCheck(
                mode: .continuous,
                using: self.grammarService,
                temperature: 0,
                requiresEnabledSetting: true,
                verifiesCandidates: true,
                generation: generation
            )
        }
    }

    func runThoroughProofread() {
        grammarCheckTimer?.invalidate()
        grammarCheckTimer = nil
        cancelGrammarCheckTask()
        checkedGrammarBlockHashes = [:]
        let generation = grammarCheckGeneration
        grammarCheckTask = Task { [weak self] in
            guard let self else { return }
            await self.runGrammarCheck(
                mode: .thorough,
                using: self.thoroughGrammarService,
                temperature: nil,
                requiresEnabledSetting: false,
                verifiesCandidates: false,
                generation: generation
            )
        }
    }

    private func runGrammarCheck(
        mode: GrammarCheckContract.Mode,
        using service: LanguageModelService,
        temperature: Double?,
        requiresEnabledSetting: Bool,
        verifiesCandidates: Bool,
        generation: UInt64
    ) async {
        defer {
            if grammarCheckGeneration == generation {
                grammarCheckTask = nil
            }
        }

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
                    mode: mode,
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
        mode: GrammarCheckContract.Mode,
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

        let systemPrompt = GrammarCheckContract.detectorSystemPrompt(
            dialect: dialect,
            mode: mode
        )

        let messages: [[String: Any]] = [[
            "role": "user",
            "content": "\(mode.requestInstruction) Return structured JSON only.\n\(blockJSON)"
        ]]

        let outputFormat: [String: Any] = [
            "type": "json_schema",
            "schema": GrammarCheckContract.detectorOutputSchema(mode: mode),
        ]

        var responseText = ""
        for try await chunk in service.streamMessage(
            messages: messages,
            systemPrompt: systemPrompt,
            outputFormat: outputFormat,
            temperature: temperature,
            maxTokens: 2_048,
            webSearchEnabled: false
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

        let systemPrompt = GrammarCheckContract.verifierSystemPrompt(dialect: dialect)
        let messages: [[String: Any]] = [[
            "role": "user",
            "content": "Adjudicate these proposed corrections. Return structured JSON only.\n\(candidateJSON)",
        ]]
        let outputFormat: [String: Any] = [
            "type": "json_schema",
            "schema": GrammarCheckContract.verifierOutputSchema(
                candidateCount: candidates.count
            ),
        ]

        var responseText = ""
        for try await chunk in grammarService.streamMessage(
            messages: messages,
            systemPrompt: systemPrompt,
            outputFormat: outputFormat,
            temperature: 0,
            maxTokens: 1024,
            webSearchEnabled: false
        ) {
            if case .text(let text) = chunk {
                responseText += text
            }
        }

        guard let data = jsonObjectData(from: responseText) else {
            throw LanguageModelService.APIError.invalidResponse
        }
        let verification = try JSONDecoder().decode(GrammarVerificationResponse.self, from: data)
        let candidateIDs = Set(candidates.compactMap { $0["id"] })
        let decisionIDs = verification.decisions.map(\.id)
        guard decisionIDs.count == candidates.count,
              Set(decisionIDs).count == decisionIDs.count,
              Set(decisionIDs) == candidateIDs
        else {
            throw LanguageModelService.APIError.invalidResponse
        }
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
        cancelGrammarCheckTask()
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
            cancelAmbientReviewTask()
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

        cancelAmbientReviewTask()
        let generation = ambientReviewGeneration
        isAmbientReviewing = true
        ambientReviewTask = Task { [weak self] in
            await self?.runAmbientReview(generation: generation)
        }
    }

    private func runAmbientReview(generation: UInt64) async {
        defer {
            if ambientReviewGeneration == generation {
                isAmbientReviewing = false
                ambientReviewTask = nil
            }
        }

        guard ambientReviewEnabled else { return }
        guard let context = await currentEditContextSnapshot(), !context.blocks.isEmpty else { return }
        let reviewBlocks = ambientBlocksNeedingReview(in: context)
        guard !reviewBlocks.isEmpty else {
            ambientReviewStatusText = "Ambient review is up to date."
            return
        }

        ambientReviewStatusText = "Reviewing..."

        do {
            let responseText = try await collectAmbientReviewResponse(
                context: context,
                reviewBlocks: reviewBlocks
            )
            try Task.checkCancellation()
            let decodedSuggestions = try AmbientReviewContract.decode(responseText)
            let suggestions = AmbientReviewContract.validated(
                decodedSuggestions,
                against: reviewBlocks.map {
                    AmbientReviewContract.Block(id: $0.id, type: $0.type, text: $0.text)
                }
            )
            guard decodedSuggestions.isEmpty || !suggestions.isEmpty else {
                throw AmbientReviewContract.ContractError.invalidResponse
            }
            let addedCount = await addAmbientReviewComments(suggestions, context: context)
            markAmbientBlocksReviewed(reviewBlocks, currentContext: context)
            Task { await StyleProfileRefinementCoordinator.shared.prepareIfNeeded() }
            if addedCount > 0 {
                ambientReviewStatusText = "Added \(addedCount) suggestion\(addedCount == 1 ? "" : "s")."
            } else {
                ambientReviewStatusText = "No new suggestions."
            }
        } catch is CancellationError {
            if ambientReviewGeneration == generation {
                ambientReviewStatusText = ""
            }
        } catch {
            if ambientReviewGeneration == generation {
                ambientReviewStatusText = "Ambient review failed: \(error.localizedDescription)"
            }
        }
    }

    private func currentEditContextSnapshot() async -> EditContextSnapshot? {
        await withCheckedContinuation { continuation in
            getEditContextSnapshot { snapshot in
                continuation.resume(returning: snapshot)
            }
        }
    }

    private func runGapFill(
        _ request: BridgePayload.GapFillRequestData,
        taskID: UUID
    ) async {
        defer {
            if gapFillTaskIDs[request.requestID] == taskID {
                gapFillTasks[request.requestID] = nil
                gapFillTaskIDs[request.requestID] = nil
            }
        }

        do {
            guard let context = await currentEditContextSnapshot(),
                  let target = gapFillTarget(for: request, in: context)
            else {
                throw GapFillContract.ContractError.invalidResponse
            }

            let stylePacket = await PersonalizedWritingContext.assemble(
                task: GapFillContract.styleTask,
                documentExcerpt: gapFillDocumentExcerpt(targetIndex: target.blockIndex, in: context)
            )
            let systemPrompt: [[String: Any]] = [[
                "type": "text",
                "text": GapFillContract.systemPrompt,
                "cache_control": LanguageModelService.ephemeralPromptCacheControl,
            ]]
            let messages: [[String: Any]] = [[
                "role": "user",
                "content": [
                    LanguageModelService.cacheableTextBlock(
                        stylePacket.cacheablePrefixText
                    ),
                    [
                        "type": "text",
                        "text": stylePacket.taskRelevantText,
                    ],
                    [
                        "type": "text",
                        "text": gapFillPrompt(
                            request: request,
                            context: context,
                            target: target
                        ),
                    ],
                ],
            ]]

            var responseText = ""
            for try await chunk in gapFillService.streamMessage(
                messages: messages,
                systemPrompt: systemPrompt,
                outputFormat: ["type": "json_schema", "schema": GapFillContract.outputSchema()],
                temperature: 0.2,
                maxTokens: 1_200,
                webSearchEnabled: false
            ) {
                try Task.checkCancellation()
                if case .text(let text) = chunk { responseText += text }
            }

            let response = try GapFillContract.decode(responseText)
            callEditorAPI(
                "completeGapFill",
                arguments: [
                    request.requestID,
                    response.text,
                    response.styleNotes.joined(separator: "; "),
                    "",
                ]
            )
        } catch is CancellationError {
            return
        } catch {
            callEditorAPI(
                "completeGapFill",
                arguments: [request.requestID, "", "", error.localizedDescription]
            )
        }
    }

    private struct GapFillTarget {
        let placeholder: EditContextSnapshot.Placeholder
        let block: EditContextSnapshot.Block
        let blockIndex: Int
    }

    private func gapFillTarget(
        for request: BridgePayload.GapFillRequestData,
        in context: EditContextSnapshot
    ) -> GapFillTarget? {
        let candidates = (context.placeholders ?? []).filter { placeholder in
            placeholder.text == request.placeholder
        }
        let placeholder: EditContextSnapshot.Placeholder?
        if context.revision == request.revision {
            placeholder = candidates.first {
                $0.from == request.from && $0.to == request.to
            }
        } else {
            placeholder = candidates.min {
                abs($0.from - request.from) < abs($1.from - request.from)
            }
        }
        guard let placeholder,
              let blockIndex = context.blocks.firstIndex(where: { $0.id == placeholder.blockId }),
              context.blocks[blockIndex].type != "codeBlock"
        else { return nil }
        return GapFillTarget(
            placeholder: placeholder,
            block: context.blocks[blockIndex],
            blockIndex: blockIndex
        )
    }

    private func gapFillDocumentExcerpt(
        targetIndex: Int,
        in context: EditContextSnapshot
    ) -> String {
        let lower = max(0, targetIndex - 2)
        let upper = min(context.blocks.count - 1, targetIndex + 2)
        guard lower <= upper else { return "" }
        return context.blocks[lower...upper].map(\.text).joined(separator: "\n\n")
    }

    private func gapFillPrompt(
        request: BridgePayload.GapFillRequestData,
        context: EditContextSnapshot,
        target: GapFillTarget
    ) -> String {
        let lower = max(0, target.blockIndex - 2)
        let upper = min(context.blocks.count - 1, target.blockIndex + 2)
        let nearbyBlocks = context.blocks[lower...upper].map { block in
            let role = block.id == target.block.id ? "target" : "context"
            return """
            <block role="\(role)" type="\(xmlEscaped(block.type))">
            \(xmlEscaped(block.text))
            </block>
            """
        }.joined(separator: "\n")
        let flowMap = StyleContextAssembler.documentFlowMap(
            blocks: context.blocks.map {
                StyleContextAssembler.FlowBlock(id: $0.id, type: $0.type, text: $0.text)
            },
            targetIDs: [target.block.id]
        )
        let instruction = request.instruction.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedInstruction = instruction.isEmpty
            ? "Continue the surrounding text naturally."
            : instruction

        return """
        Fill exactly one marked gap. Return JSON only.
        <gap_request block_only="\(request.isBlock ? "true" : "false")">
        <placeholder>\(xmlEscaped(request.placeholder))</placeholder>
        <writer_note>\(xmlEscaped(resolvedInstruction))</writer_note>
        </gap_request>
        <nearby_blocks>
        \(nearbyBlocks)
        </nearby_blocks>
        <document_flow_map>
        Use this only to orient the fill within the larger document. Do not quote it.
        \(xmlEscaped(flowMap))
        </document_flow_map>
        """
    }

    private func cancelGapFillTasks() {
        gapFillTasks.values.forEach { $0.cancel() }
        gapFillTasks.removeAll()
        gapFillTaskIDs.removeAll()
    }

    private func cancelGrammarCheckTask() {
        grammarCheckGeneration &+= 1
        grammarCheckTask?.cancel()
        grammarCheckTask = nil
    }

    private func cancelAmbientReviewTask() {
        ambientReviewGeneration &+= 1
        ambientReviewTask?.cancel()
        ambientReviewTask = nil
        isAmbientReviewing = false
    }

    /// Reviews only changed blocks (plus immediate neighbors) and caps each request.
    /// A first pass through a long imported document therefore stays bounded; later
    /// edits do not repeatedly upload every unchanged paragraph.
    private func ambientBlocksNeedingReview(
        in context: EditContextSnapshot,
        limit: Int = 16
    ) -> [EditContextSnapshot.Block] {
        let blocks = context.blocks.map {
            StyleContextAssembler.ReviewBlock(
                id: $0.id,
                from: $0.from,
                to: $0.to,
                textHash: $0.textHash
            )
        }
        return StyleContextAssembler.reviewBlockIndices(
            blocks: blocks,
            reviewedHashes: ambientReviewedBlockHashes,
            cursorPosition: context.cursorPosition,
            limit: limit
        ).map { context.blocks[$0] }
    }

    private func markAmbientBlocksReviewed(
        _ reviewed: [EditContextSnapshot.Block],
        currentContext: EditContextSnapshot
    ) {
        let currentIDs = Set(currentContext.blocks.map(\.id))
        ambientReviewedBlockHashes = ambientReviewedBlockHashes.filter {
            currentIDs.contains($0.key)
        }
        for block in reviewed {
            ambientReviewedBlockHashes[block.id] = block.textHash
        }
    }

    private func collectAmbientReviewResponse(
        context: EditContextSnapshot,
        reviewBlocks: [EditContextSnapshot.Block]
    ) async throws -> String {
        let systemPrompt: [[String: Any]] = [[
            "type": "text",
            "text": AmbientReviewContract.systemPrompt,
            "cache_control": LanguageModelService.ephemeralPromptCacheControl,
        ]]

        let stylePacket = await PersonalizedWritingContext.assemble(
            task: AmbientReviewContract.styleTask,
            documentExcerpt: reviewBlocks.map(\.text).joined(separator: "\n\n")
        )
        let messages: [[String: Any]] = [
            [
                "role": "user",
                "content": [
                    LanguageModelService.cacheableTextBlock(
                        stylePacket.cacheablePrefixText
                    ),
                    [
                        "type": "text",
                        "text": stylePacket.taskRelevantText,
                    ],
                    [
                        "type": "text",
                        "text": ambientReviewPrompt(
                            context,
                            reviewBlocks: reviewBlocks
                        ),
                    ],
                ]
            ]
        ]

        let outputFormat: [String: Any] = [
            "type": "json_schema",
            "schema": AmbientReviewContract.outputSchema(),
        ]

        var text = ""
        for try await chunk in ambientReviewService.streamMessage(
            messages: messages,
            systemPrompt: systemPrompt,
            outputFormat: outputFormat,
            temperature: 0,
            maxTokens: 1_536,
            webSearchEnabled: false
        ) {
            if case .text(let delta) = chunk {
                text += delta
            }
        }
        return text
    }

    private func ambientReviewPrompt(
        _ context: EditContextSnapshot,
        reviewBlocks: [EditContextSnapshot.Block]
    ) -> String {
        let existingComments = ambientExistingCommentsXML()
        let recentRejected = ambientRecentRejectedSuggestionsXML()
        var flowBlocks = context.blocks.map {
            StyleContextAssembler.FlowBlock(id: $0.id, type: $0.type, text: $0.text)
        }
        let documentEnding = ambientPromptExcerpt(String(context.plainText.suffix(600)), limit: 400)
        if !documentEnding.isEmpty,
           !(flowBlocks.last?.text.contains(String(documentEnding.prefix(80))) ?? false) {
            flowBlocks.append(
                StyleContextAssembler.FlowBlock(
                    id: "document-ending",
                    type: "document_end",
                    text: documentEnding
                )
            )
        }
        let flowMap = StyleContextAssembler.documentFlowMap(
            blocks: flowBlocks,
            targetIDs: Set(reviewBlocks.map(\.id))
        )
        let blockLines = reviewBlocks.map { block in
            """
            <block id="\(xmlEscaped(block.id))" type="\(xmlEscaped(block.type))" from="\(block.from)" to="\(block.to)" text_hash="\(xmlEscaped(block.textHash))">
            \(xmlEscaped(block.text))
            </block>
            """
        }.joined(separator: "\n")

        return """
        Review the current document using these anchorable blocks. Return JSON only.
        <edit_context revision="\(context.revision)" document_hash="\(xmlEscaped(context.documentHash))" reviewed_blocks="\(reviewBlocks.count)" document_blocks="\(context.blocks.count)">
        \(existingComments)
        \(recentRejected)
        <document_flow_map>
        Sparse, document-ordered orientation only. It includes headings, section boundaries, opening and ending material, and distributed checkpoints. Editable targets appear separately below.
        \(xmlEscaped(flowMap))
        </document_flow_map>
        <editable_block_index>
        \(blockLines)
        </editable_block_index>
        </edit_context>
        """
    }

    private func ambientExistingCommentsXML(limit: Int = 20) -> String {
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
            <selected_text>\(xmlEscaped(ambientPromptExcerpt(comment.selectedText, limit: 300)))</selected_text>
            <comment_text>\(xmlEscaped(ambientPromptExcerpt(comment.text, limit: 240)))</comment_text>
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

    private func ambientRecentRejectedSuggestionsXML(limit: Int = 6) -> String {
        let rejected = trainingEventStore.recentRejectedDecisions(limit: limit)
        guard !rejected.isEmpty else {
            return "<recent_rejected_suggestions />"
        }

        let lines = rejected.map { decision in
            """
            <rejected_suggestion source="\(xmlEscaped(decision.source))" kind="\(xmlEscaped(decision.kind))">
            <original>\(xmlEscaped(ambientPromptExcerpt(decision.originalText, limit: 240)))</original>
            <replacement>\(xmlEscaped(ambientPromptExcerpt(decision.replacementText, limit: 240)))</replacement>
            <context>\(xmlEscaped(ambientPromptExcerpt(decision.surroundingSentence, limit: 320)))</context>
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

    private func ambientPromptExcerpt(_ text: String, limit: Int) -> String {
        let normalized = text
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        guard limit > 1, normalized.count > limit else { return normalized }
        let prefix = String(normalized.prefix(limit - 1))
        let boundary = prefix.lastIndex(where: { $0.isWhitespace }) ?? prefix.endIndex
        return String(prefix[..<boundary]).trimmingCharacters(in: .whitespacesAndNewlines) + "…"
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
                suggestedReplacement: suggestion.suggestedReplacement ?? "",
                expectedText: suggestion.exactOriginal,
                sourceRevision: context.revision
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
        suggestedReplacement: String,
        expectedText: String,
        sourceRevision: Int
    ) async -> Bool {
        await withCheckedContinuation { continuation in
            addAgentComment(
                rangeStart: rangeStart,
                rangeEnd: rangeEnd,
                text: text,
                kind: kind,
                severity: severity,
                suggestedReplacement: suggestedReplacement,
                agentRunID: UUID().uuidString,
                expectedText: expectedText,
                sourceRevision: sourceRevision
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

    func latestSnapshot(
        for document: DocumentModel,
        preferEditorState: Bool = true
    ) async -> DocumentFileStore.FileSnapshot? {
        guard preferEditorState else { return document.currentSnapshot() }

        if isEditorReady, let snapshot = await captureEditorSnapshot(document: document) {
            document.syncFromEditor(snapshot: snapshot)
            lastSnapshotCaptureFailed = false
            return document.currentSnapshot()
        }

        if !isEditorReady, !document.hasUnsyncedEditorChanges {
            lastSnapshotCaptureFailed = false
            return document.currentSnapshot()
        }

        print("Editor snapshot capture failed; refusing to persist unverified state")
        lastSnapshotCaptureFailed = true
        return nil
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
            _ = await flushBeforeDocumentChange(document: document)
        }
    }

    private func performScheduledPersistence(document: DocumentModel) async {
        guard document.isDirty else { return }
        guard let snapshot = await latestSnapshot(for: document) else {
            setPersistenceStatus("Auto-save paused — editor state is temporarily unavailable", isError: true)
            return
        }

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
                _ = await saveRecoveryDraft(document: document, providedSnapshot: snapshot)
            }
        } else {
            _ = await saveRecoveryDraft(document: document, providedSnapshot: snapshot)
        }
    }

    private func flushBeforeDocumentChange(document: DocumentModel) async -> Bool {
        persistenceTimer?.invalidate()
        persistenceTimer = nil
        if let persistenceTask {
            await persistenceTask.value
            self.persistenceTask = nil
        }
        ambientReviewTimer?.invalidate()
        ambientReviewTimer = nil
        cancelAmbientReviewTask()
        grammarCheckTimer?.invalidate()
        grammarCheckTimer = nil
        cancelGrammarCheckTask()
        cancelGapFillTasks()

        guard document.isDirty else { return true }
        guard let snapshot = await latestSnapshot(for: document) else {
            setPersistenceStatus("Could not capture the latest editor state", isError: true)
            return false
        }

        if let url = document.fileURL {
            let saved = await persistDocument(
                document: document,
                to: url,
                captureLatestEditorState: false,
                createVersionSnapshot: false,
                actionName: "Flush",
                providedSnapshot: snapshot
            )
            if saved { return true }
            return await saveRecoveryDraft(document: document, providedSnapshot: snapshot)
        } else {
            return await saveRecoveryDraft(document: document, providedSnapshot: snapshot)
        }
    }

    private func shouldCreateAutoSaveCheckpoint(for document: DocumentModel) -> Bool {
        let documentID = document.documentID
        guard let lastCheckpoint = lastAutoSaveCheckpointByDocumentID[documentID] else {
            return true
        }
        return Date().timeIntervalSince(lastCheckpoint) >= autoSaveCheckpointInterval
    }

    private func markAutoSaveCheckpointCreated(for documentID: String) {
        lastAutoSaveCheckpointByDocumentID[documentID] = Date()
    }

    @discardableResult
    private func saveRecoveryDraft(
        document: DocumentModel,
        providedSnapshot: DocumentFileStore.FileSnapshot? = nil
    ) async -> Bool {
        guard document.isDirty else { return true }

        do {
            let snapshot: DocumentFileStore.FileSnapshot
            if let providedSnapshot {
                snapshot = providedSnapshot
            } else {
                guard let captured = await latestSnapshot(for: document) else {
                    setPersistenceStatus("Recovery draft failed: latest editor state is unavailable", isError: true)
                    return false
                }
                snapshot = captured
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
            return true
        } catch {
            setPersistenceStatus("Recovery draft failed: \(error.localizedDescription)", isError: true)
            return false
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

    func renameDocument(named requestedName: String, document: DocumentModel) {
        let fileExtension = document.fileURL?.pathExtension
            ?? DocumentFileStore.documentPackageExtension
        guard let name = normalizedDocumentName(
            requestedName,
            removingExtension: fileExtension
        ) else {
            setPersistenceStatus("Rename failed: enter a valid file name", isError: true)
            return
        }

        guard name != document.displayName else { return }

        guard let sourceURL = document.fileURL else {
            document.renameUnsavedDocument(to: name)
            setPersistenceStatus("Document named \(name)", isError: false)
            return
        }

        guard !isDocumentTransitioning else {
            setPersistenceStatus("Rename failed: another document operation is in progress", isError: true)
            return
        }

        let destinationURL = sourceURL.deletingLastPathComponent()
            .appendingPathComponent(name, isDirectory: false)
            .appendingPathExtension(fileExtension)
        guard destinationURL.lastPathComponent.utf8.count <= 255 else {
            setPersistenceStatus("Rename failed: the file name is too long", isError: true)
            return
        }

        isDocumentTransitioning = true
        persistenceTimer?.invalidate()
        persistenceTimer = nil

        Task { @MainActor [weak self] in
            guard let self else { return }
            defer {
                isDocumentTransitioning = false
                if document.isDirty {
                    schedulePersistence(document: document)
                }
            }

            if let persistenceTask {
                await persistenceTask.value
                self.persistenceTask = nil
            }

            guard document.fileURL == sourceURL else {
                setPersistenceStatus("Rename cancelled: the open document changed", isError: true)
                return
            }

            do {
                try await DocumentFileStore.shared.rename(
                    from: sourceURL,
                    to: destinationURL
                )
                document.markRenamed(from: sourceURL, to: destinationURL)
                if assetBaseURL == sourceURL {
                    assetBaseURL = destinationURL
                }
                setPersistenceStatus("Renamed to \(destinationURL.lastPathComponent)", isError: false)
            } catch {
                setPersistenceStatus("Rename failed: \(error.localizedDescription)", isError: true)
            }
        }
    }

    private func normalizedDocumentName(
        _ requestedName: String,
        removingExtension fileExtension: String
    ) -> String? {
        var name = requestedName.trimmingCharacters(in: .whitespacesAndNewlines)
        let suffix = ".\(fileExtension)"
        if name.lowercased().hasSuffix(suffix.lowercased()) {
            name.removeLast(suffix.count)
            name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        guard !name.isEmpty,
              name != ".",
              name != "..",
              !name.contains("/"),
              !name.contains(":"),
              !name.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains)
        else {
            return nil
        }
        return name
    }

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
            guard !isDocumentTransitioning else {
                setPersistenceStatus("Another document transition is already in progress", isError: true)
                return
            }
            isDocumentTransitioning = true
            defer {
                setEditorEditable(true)
                isDocumentTransitioning = false
            }
            do {
                // Read and validate first so the existing document remains
                // editable during slow-volume I/O. Freeze only for the short
                // flush-and-commit transaction.
                let candidate = try await DocumentFileStore.shared.load(from: url)
                setEditorEditable(false)

                guard await flushBeforeDocumentChange(document: document) else {
                    setPersistenceStatus("Open cancelled — current changes could not be secured", isError: true)
                    return
                }

                let editorWasReady = isEditorReady
                let securedCurrentSnapshot = document.currentSnapshot()
                if editorWasReady {
                    guard await loadSnapshotIntoReadyEditor(candidate) else {
                        _ = await loadSnapshotIntoReadyEditor(securedCurrentSnapshot)
                        setPersistenceStatus("Open failed: the editor rejected this document", isError: true)
                        return
                    }
                }

                document.load(snapshot: candidate, from: url)
                assetBaseURL = DocumentFileStore.isNativeDocumentURL(url) ? url : nil
                if editorWasReady {
                    activeDocumentID = candidate.documentID
                    pendingSnapshot = nil
                    ambientReviewedBlockHashes = [:]
                    clearGrammarCheckingState()
                } else {
                    // Startup URL events may arrive before WKWebView is ready.
                    // Queue the already-validated snapshot for editorReady.
                    loadSnapshot(candidate)
                }
                do {
                    try await VersionStore.shared.saveVersion(
                        filePath: url.path,
                        snapshot: candidate,
                        sourceDocumentURL: url
                    )
                    markAutoSaveCheckpointCreated(for: candidate.documentID)
                    setPersistenceStatus("Opened \(url.lastPathComponent)", isError: false)
                } catch {
                    setPersistenceStatus(
                        "Opened \(url.lastPathComponent), but version history is unavailable: \(error.localizedDescription)",
                        isError: true
                    )
                }
            } catch {
                setPersistenceStatus("Open failed: \(error.localizedDescription)", isError: true)
            }
        }
    }

    func prepareForTermination(document: DocumentModel) async -> Bool {
        guard !isDocumentTransitioning else { return false }
        isDocumentTransitioning = true
        setEditorEditable(false)
        let secured = await flushBeforeDocumentChange(document: document)
        if !secured {
            setEditorEditable(true)
            isDocumentTransitioning = false
        }
        return secured
    }

    func cancelTerminationPreparation() {
        setEditorEditable(true)
        isDocumentTransitioning = false
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
                guard let snapshot = await self.latestSnapshot(for: document) else {
                    self.setPersistenceStatus("Export failed: latest editor state is unavailable", isError: true)
                    return
                }
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
            guard let captured = await latestSnapshot(
                for: document,
                preferEditorState: captureLatestEditorState
            ) else {
                setPersistenceStatus("\(actionName) failed: latest editor state is unavailable", isError: true)
                return false
            }
            resolvedSnapshot = captured
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

            var versionHistoryError: Error?
            if createVersionSnapshot {
                do {
                    try await VersionStore.shared.saveVersion(
                        filePath: url.path,
                        snapshot: persistedSnapshot,
                        sourceDocumentURL: url
                    )
                    markAutoSaveCheckpointCreated(for: persistedSnapshot.documentID)
                } catch {
                    versionHistoryError = error
                }
            }
            let acknowledgedOutcomes = trainingEventStore.appendOutcomes(
                request.snapshot.personalizationOutcomes,
                documentID: persistedSnapshot.documentID,
                runtime: ambientReviewService.currentRuntime
            )
            if !acknowledgedOutcomes.isEmpty {
                document.acknowledgePersonalizationOutcomes(acknowledgedOutcomes)
                callEditorAPI("acknowledgePersonalizationOutcomes", arguments: [acknowledgedOutcomes])
                Task { await StyleProfileRefinementCoordinator.shared.prepareIfNeeded() }
            }
            if !document.isDirty {
                try? await RecoveryDraftStore.shared.deleteDraft(documentID: persistedSnapshot.documentID)
                if sourceDocumentURL != url {
                    try? await DocumentFileStore.shared.deleteWorkingAssets(
                        documentID: persistedSnapshot.documentID
                    )
                }
            }
            if let versionHistoryError {
                setPersistenceStatus(
                    "\(actionName) saved, but version history failed: \(versionHistoryError.localizedDescription)",
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

    func saveVersionSnapshot(
        _ snapshot: DocumentFileStore.FileSnapshot,
        documentURL: URL,
        name: String? = nil
    ) async throws {
        try await VersionStore.shared.saveVersion(
            filePath: documentURL.path,
            snapshot: snapshot,
            name: name,
            sourceDocumentURL: assetBaseURL ?? documentURL
        )
        markAutoSaveCheckpointCreated(for: snapshot.documentID)
    }

    func restoreVersionSnapshot(
        _ snapshot: DocumentFileStore.FileSnapshot,
        assets: [String: Data],
        rollbackSnapshot: DocumentFileStore.FileSnapshot,
        document: DocumentModel
    ) async throws {
        let previousAssetBaseURL = assetBaseURL ?? document.fileURL
        let rollbackAssets = try await DocumentFileStore.shared.versionAssets(
            for: rollbackSnapshot,
            sourceDocumentURL: previousAssetBaseURL
        )
        let restoredAssetBaseURL = try await DocumentFileStore.shared.stageVersionAssets(
            assets,
            documentID: snapshot.documentID
        )
        assetBaseURL = restoredAssetBaseURL
        if isEditorReady {
            guard await loadSnapshotIntoReadyEditor(snapshot) else {
                _ = try? await DocumentFileStore.shared.stageVersionAssets(
                    rollbackAssets,
                    documentID: rollbackSnapshot.documentID
                )
                assetBaseURL = previousAssetBaseURL
                throw VersionRestoreError.editorRejectedSnapshot
            }
            cancelGapFillTasks()
            activeDocumentID = snapshot.documentID
            pendingSnapshot = nil
            ambientReviewedBlockHashes = [:]
            clearGrammarCheckingState()
        } else {
            loadSnapshot(snapshot)
        }
        document.restoreVersion(snapshot: snapshot)
    }

    func reportPersistenceFailure(_ action: String, error: Error) {
        setPersistenceStatus("\(action) failed: \(error.localizedDescription)", isError: true)
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
                        notes: currentSnapshot.notes,
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
    static let editorDocumentMetricsUpdated = Notification.Name("editorDocumentMetricsUpdated")
    static let editorBecameReady = Notification.Name("editorBecameReady")
    static let grammarCheckingSettingsChanged = Notification.Name("grammarCheckingSettingsChanged")
    static let showSaveNamedVersion = Notification.Name("showSaveNamedVersion")
    static let selectionFeedbackRequested = Notification.Name("selectionFeedbackRequested")
}
