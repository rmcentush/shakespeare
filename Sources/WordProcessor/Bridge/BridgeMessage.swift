import Foundation

struct BridgeMessage: Codable {
    let type: String
    let payload: BridgePayload
}

enum BridgePayload: Codable {
    case editorReady
    case contentChanged(html: String)
    case contentUpdate(html: String, words: Int, characters: Int)
    case selectionChanged(SelectionState)
    case wordCount(words: Int, characters: Int)
    case pendingEditUpdate(count: Int, currentIndex: Int)
    case unknown

    struct SelectionState: Codable {
        let from: Int
        let to: Int
        let hasSelection: Bool
        let isBold: Bool
        let isItalic: Bool
        let isUnderline: Bool
        let heading: Int
        let textAlign: String
        let isLink: Bool
        let linkHref: String
        let textColor: String
    }

    struct WordCountData: Codable {
        let words: Int
        let characters: Int
    }

    struct ContentChangedData: Codable {
        let html: String
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
            let words = payload["words"] as? Int ?? 0
            let characters = payload["characters"] as? Int ?? 0
            return .contentUpdate(html: html, words: words, characters: characters)
        case "selectionChanged":
            let state = SelectionState(
                from: payload["from"] as? Int ?? 0,
                to: payload["to"] as? Int ?? 0,
                hasSelection: payload["hasSelection"] as? Bool ?? false,
                isBold: payload["isBold"] as? Bool ?? false,
                isItalic: payload["isItalic"] as? Bool ?? false,
                isUnderline: payload["isUnderline"] as? Bool ?? false,
                heading: payload["heading"] as? Int ?? 0,
                textAlign: payload["textAlign"] as? String ?? "left",
                isLink: payload["isLink"] as? Bool ?? false,
                linkHref: payload["linkHref"] as? String ?? "",
                textColor: payload["textColor"] as? String ?? ""
            )
            return .selectionChanged(state)
        case "wordCount":
            let words = payload["words"] as? Int ?? 0
            let characters = payload["characters"] as? Int ?? 0
            return .wordCount(words: words, characters: characters)
        case "pendingEditUpdate":
            let count = payload["count"] as? Int ?? 0
            let currentIndex = payload["currentIndex"] as? Int ?? -1
            return .pendingEditUpdate(count: count, currentIndex: currentIndex)
        default:
            return .unknown
        }
    }
}
