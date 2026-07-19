import Foundation

enum BridgePayload: Codable {
    case editorReady
    case contentUpdate(html: String, text: String, words: Int, characters: Int)
    case documentMetrics(revision: Int, words: Int, characters: Int)
    case selectionChanged(SelectionState)
    case pendingEditUpdate(PendingEditUpdateData)
    case editDecision(EditDecisionData)
    case commentsChanged([CommentData], documentChanged: Bool)
    case commentActivated(commentId: String)
    case proofreadingUpdate(ProofreadingUpdateData)
    case proofreadingUserStateChanged(json: String)
    case gapFillRequested(GapFillRequestData)
    case imageImportRequested(ImageImportRequestData)
    case openURL(url: String)
    case unknown

    struct SelectionState: Codable {
        let hasSelection: Bool
        let selectedWords: Int
        let selectedCharacters: Int
        let isBold: Bool
        let isItalic: Bool
        let isUnderline: Bool
        let isStrike: Bool
        let isBulletList: Bool
        let isOrderedList: Bool
        let isBlockquote: Bool
        let heading: Int
        let textAlign: String
        let isLink: Bool
        let linkHref: String
        let textColor: String
        let isTextColorMixed: Bool
        let fontFamily: String
        let isFontFamilyMixed: Bool
        let fontSize: String
        let isFontSizeMixed: Bool
        let lineHeight: String
        let isLineHeightMixed: Bool
        let isFootnote: Bool
        let footnoteText: String
        let isImage: Bool
        let imageLayout: String
        let imageAlign: String
        let imageWidth: String
        let imageHeight: String
    }

    struct ProofreadingUpdateData: Codable {
        let status: String
        let issueCount: Int
        let message: String
    }

    struct ImageImportRequestData: Codable {
        let requestID: String
        let dataURL: String
        let filename: String
        let referencedSources: [String]
    }

    struct GapFillRequestData: Codable, Equatable {
        let requestID: String
        let from: Int
        let to: Int
        let revision: Int
        let placeholder: String
        let instruction: String
        let isBlock: Bool
    }

    struct CommentData: Identifiable, Equatable {
        let id: String
        var text: String
        let selectedText: String
        let createdAt: Double
        let updatedAt: Double
        let rangeStart: Int
        let rangeEnd: Int
        let authorName: String
        let source: String
        let kind: String
        let severity: String
        let status: String
        let suggestedReplacement: String
        let agentRunID: String

        var commentId: String { id }
        var isAgentAuthored: Bool { source == "agent" }
    }

    struct PendingEditUpdateData: Codable {
        let count: Int
        let currentIndex: Int
        let activeEditID: String?
        let edits: [PendingEditData]
    }

    struct PendingEditData: Codable, Identifiable {
        let id: String
        let groupID: String
        let kind: String
        let source: String
        let label: String
        let from: Int
        let to: Int
        let originalText: String
        let replacementText: String
        let createdAt: Double
        let status: String
        let conflictReason: String?
        let index: Int
        let isActive: Bool
        let canAccept: Bool
        let canReject: Bool
        let canFocus: Bool
    }

    struct EditDecisionData: Codable {
        let eventID: String
        let decision: String
        let source: String
        let kind: String
        let originalText: String
        let replacementText: String
        let surroundingSentence: String
        let groupID: String
        let rationale: String
        let learningCategory: String
        let instruction: String
        let timestamp: Double
    }

    init(from decoder: Decoder) throws {
        // This is decoded manually from the raw JSON
        self = .unknown
    }

    func encode(to encoder: Encoder) throws {
        // Not needed — we only decode incoming messages
    }

    static func parse(type: String, payload: [String: Any]) -> BridgePayload {
        switch type {
        case "editorReady":
            return .editorReady
        case "contentUpdate":
            let html = payload["html"] as? String ?? ""
            let text = payload["text"] as? String ?? ""
            let words = payload["words"] as? Int ?? 0
            let characters = payload["characters"] as? Int ?? 0
            return .contentUpdate(html: html, text: text, words: words, characters: characters)
        case "documentMetrics":
            guard let revision = payload["revision"] as? Int,
                  let words = payload["words"] as? Int,
                  let characters = payload["characters"] as? Int,
                  revision >= 0,
                  words >= 0,
                  characters >= 0
            else { return .unknown }
            return .documentMetrics(revision: revision, words: words, characters: characters)
        case "selectionChanged":
            let state = SelectionState(
                hasSelection: payload["hasSelection"] as? Bool ?? false,
                selectedWords: payload["selectedWords"] as? Int ?? 0,
                selectedCharacters: payload["selectedCharacters"] as? Int ?? 0,
                isBold: payload["isBold"] as? Bool ?? false,
                isItalic: payload["isItalic"] as? Bool ?? false,
                isUnderline: payload["isUnderline"] as? Bool ?? false,
                isStrike: payload["isStrike"] as? Bool ?? false,
                isBulletList: payload["isBulletList"] as? Bool ?? false,
                isOrderedList: payload["isOrderedList"] as? Bool ?? false,
                isBlockquote: payload["isBlockquote"] as? Bool ?? false,
                heading: payload["heading"] as? Int ?? 0,
                textAlign: payload["textAlign"] as? String ?? "left",
                isLink: payload["isLink"] as? Bool ?? false,
                linkHref: payload["linkHref"] as? String ?? "",
                textColor: payload["textColor"] as? String ?? "",
                isTextColorMixed: payload["isTextColorMixed"] as? Bool ?? false,
                fontFamily: payload["fontFamily"] as? String ?? "",
                isFontFamilyMixed: payload["isFontFamilyMixed"] as? Bool ?? false,
                fontSize: payload["fontSize"] as? String ?? "",
                isFontSizeMixed: payload["isFontSizeMixed"] as? Bool ?? false,
                lineHeight: payload["lineHeight"] as? String ?? "",
                isLineHeightMixed: payload["isLineHeightMixed"] as? Bool ?? false,
                isFootnote: payload["isFootnote"] as? Bool ?? false,
                footnoteText: payload["footnoteText"] as? String ?? "",
                isImage: payload["isImage"] as? Bool ?? false,
                imageLayout: payload["imageLayout"] as? String ?? "inline",
                imageAlign: payload["imageAlign"] as? String ?? "center",
                imageWidth: payload["imageWidth"] as? String ?? "",
                imageHeight: payload["imageHeight"] as? String ?? ""
            )
            return .selectionChanged(state)
        case "pendingEditUpdate":
            let count = payload["count"] as? Int ?? 0
            let currentIndex = payload["currentIndex"] as? Int ?? -1
            let activeEditID = payload["activeEditId"] as? String
            let edits = (payload["edits"] as? [[String: Any]] ?? []).map { item in
                PendingEditData(
                    id: item["id"] as? String ?? UUID().uuidString,
                    groupID: item["groupId"] as? String ?? "",
                    kind: item["kind"] as? String ?? "",
                    source: item["source"] as? String ?? "",
                    label: item["label"] as? String ?? "",
                    from: item["from"] as? Int ?? 0,
                    to: item["to"] as? Int ?? 0,
                    originalText: item["originalText"] as? String ?? "",
                    replacementText: item["replacementText"] as? String ?? "",
                    createdAt: item["createdAt"] as? Double ?? 0,
                    status: item["status"] as? String ?? "pending",
                    conflictReason: item["conflictReason"] as? String,
                    index: item["index"] as? Int ?? 0,
                    isActive: item["isActive"] as? Bool ?? false,
                    canAccept: item["canAccept"] as? Bool ?? false,
                    canReject: item["canReject"] as? Bool ?? false,
                    canFocus: item["canFocus"] as? Bool ?? false
                )
            }
            return .pendingEditUpdate(
                PendingEditUpdateData(
                    count: count,
                    currentIndex: currentIndex,
                    activeEditID: activeEditID,
                    edits: edits
                )
            )
        case "editDecision":
            let timestamp: Double
            if let doubleValue = payload["timestamp"] as? Double {
                timestamp = doubleValue
            } else if let intValue = payload["timestamp"] as? Int {
                timestamp = Double(intValue)
            } else {
                timestamp = 0
            }
            return .editDecision(
                EditDecisionData(
                    eventID: payload["eventId"] as? String ?? "",
                    decision: payload["decision"] as? String ?? "",
                    source: payload["source"] as? String ?? "",
                    kind: payload["kind"] as? String ?? "",
                    originalText: payload["originalText"] as? String ?? "",
                    replacementText: payload["replacementText"] as? String ?? "",
                    surroundingSentence: payload["surroundingSentence"] as? String ?? "",
                    groupID: payload["groupId"] as? String ?? "",
                    rationale: payload["rationale"] as? String ?? "",
                    learningCategory: payload["learningCategory"] as? String ?? "",
                    instruction: payload["instruction"] as? String ?? "",
                    timestamp: timestamp
                )
            )
        case "commentsChanged":
            let rawComments = payload["comments"] as? [[String: Any]] ?? []
            let documentChanged = payload["documentChanged"] as? Bool ?? false
            let comments = rawComments.map { item in
                CommentData(
                    id: item["commentId"] as? String ?? UUID().uuidString,
                    text: item["text"] as? String ?? "",
                    selectedText: item["selectedText"] as? String ?? "",
                    createdAt: item["createdAt"] as? Double ?? 0,
                    updatedAt: item["updatedAt"] as? Double ?? item["createdAt"] as? Double ?? 0,
                    rangeStart: item["rangeStart"] as? Int ?? 0,
                    rangeEnd: item["rangeEnd"] as? Int ?? 0,
                    authorName: item["authorName"] as? String ?? "",
                    source: item["source"] as? String ?? "user",
                    kind: item["kind"] as? String ?? "",
                    severity: item["severity"] as? String ?? "",
                    status: item["status"] as? String ?? "open",
                    suggestedReplacement: item["suggestedReplacement"] as? String ?? "",
                    agentRunID: item["agentRunId"] as? String ?? ""
                )
            }
            return .commentsChanged(comments, documentChanged: documentChanged)
        case "commentActivated":
            return .commentActivated(commentId: payload["commentId"] as? String ?? "")
        case "proofreadingUpdate":
            return .proofreadingUpdate(
                ProofreadingUpdateData(
                    status: payload["status"] as? String ?? "ready",
                    issueCount: payload["issueCount"] as? Int ?? 0,
                    message: payload["message"] as? String ?? ""
                )
            )
        case "proofreadingUserStateChanged":
            guard let json = payload["json"] as? String,
                  json.utf8.count <= 256 * 1_024
            else { return .unknown }
            return .proofreadingUserStateChanged(json: json)
        case "gapFillRequested":
            guard let requestID = payload["requestId"] as? String,
                  !requestID.isEmpty,
                  requestID.utf8.count <= 128,
                  let from = payload["from"] as? Int,
                  let to = payload["to"] as? Int,
                  let revision = payload["revision"] as? Int,
                  from >= 0,
                  to > from,
                  to - from <= 604,
                  revision >= 0,
                  let placeholder = payload["placeholder"] as? String,
                  placeholder.utf8.count <= 1_204,
                  placeholder.hasPrefix("[["),
                  placeholder.hasSuffix("]]"),
                  let instruction = payload["instruction"] as? String,
                  instruction.utf8.count <= 1_204,
                  let isBlock = payload["isBlock"] as? Bool
            else { return .unknown }
            return .gapFillRequested(
                GapFillRequestData(
                    requestID: requestID,
                    from: from,
                    to: to,
                    revision: revision,
                    placeholder: placeholder,
                    instruction: instruction,
                    isBlock: isBlock
                )
            )
        case "imageImportRequested":
            guard let rawReferencedSources = payload["referencedSources"] as? [Any],
                  rawReferencedSources.count <= 2_048
            else { return .unknown }
            let referencedSources = rawReferencedSources.compactMap { value -> String? in
                guard let source = value as? String, source.utf8.count <= 1_024 else { return nil }
                return source
            }
            guard referencedSources.count == rawReferencedSources.count else { return .unknown }
            return .imageImportRequested(
                ImageImportRequestData(
                    requestID: payload["requestId"] as? String ?? "",
                    dataURL: payload["dataURL"] as? String ?? "",
                    filename: payload["filename"] as? String ?? "",
                    referencedSources: referencedSources
                )
            )
        case "openURL":
            return .openURL(url: payload["url"] as? String ?? "")
        default:
            return .unknown
        }
    }
}
