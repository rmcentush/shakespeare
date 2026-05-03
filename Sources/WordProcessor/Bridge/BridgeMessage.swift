import Foundation

struct BridgeMessage: Codable {
    let type: String
    let payload: BridgePayload
}

enum BridgePayload: Codable {
    case editorReady
    case contentChanged(html: String)
    case contentUpdate(html: String, text: String, words: Int, characters: Int)
    case selectionChanged(SelectionState)
    case wordCount(words: Int, characters: Int)
    case pendingEditUpdate(PendingEditUpdateData)
    case commentsChanged([CommentData], documentChanged: Bool)
    case commentActivated(commentId: String)
    case unknown

    struct SelectionState: Codable {
        let hasSelection: Bool
        let selectedWords: Int
        let selectedCharacters: Int
        let isBold: Bool
        let isItalic: Bool
        let isUnderline: Bool
        let heading: Int
        let textAlign: String
        let isLink: Bool
        let linkHref: String
        let textColor: String
        let isFootnote: Bool
        let footnoteText: String
        let isImage: Bool
        let imageLayout: String
        let imageAlign: String
        let imageWidth: String
        let imageHeight: String
    }

    struct WordCountData: Codable {
        let words: Int
        let characters: Int
    }

    struct ContentChangedData: Codable {
        let html: String
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
        case "contentChanged":
            let html = payload["html"] as? String ?? ""
            return .contentChanged(html: html)
        case "contentUpdate":
            let html = payload["html"] as? String ?? ""
            let text = payload["text"] as? String ?? ""
            let words = payload["words"] as? Int ?? 0
            let characters = payload["characters"] as? Int ?? 0
            return .contentUpdate(html: html, text: text, words: words, characters: characters)
        case "selectionChanged":
            let state = SelectionState(
                hasSelection: payload["hasSelection"] as? Bool ?? false,
                selectedWords: payload["selectedWords"] as? Int ?? 0,
                selectedCharacters: payload["selectedCharacters"] as? Int ?? 0,
                isBold: payload["isBold"] as? Bool ?? false,
                isItalic: payload["isItalic"] as? Bool ?? false,
                isUnderline: payload["isUnderline"] as? Bool ?? false,
                heading: payload["heading"] as? Int ?? 0,
                textAlign: payload["textAlign"] as? String ?? "left",
                isLink: payload["isLink"] as? Bool ?? false,
                linkHref: payload["linkHref"] as? String ?? "",
                textColor: payload["textColor"] as? String ?? "",
                isFootnote: payload["isFootnote"] as? Bool ?? false,
                footnoteText: payload["footnoteText"] as? String ?? "",
                isImage: payload["isImage"] as? Bool ?? false,
                imageLayout: payload["imageLayout"] as? String ?? "inline",
                imageAlign: payload["imageAlign"] as? String ?? "center",
                imageWidth: payload["imageWidth"] as? String ?? "",
                imageHeight: payload["imageHeight"] as? String ?? ""
            )
            return .selectionChanged(state)
        case "wordCount":
            let words = payload["words"] as? Int ?? 0
            let characters = payload["characters"] as? Int ?? 0
            return .wordCount(words: words, characters: characters)
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
        default:
            return .unknown
        }
    }
}
