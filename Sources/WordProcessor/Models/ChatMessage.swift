import Foundation

struct ChatMessage: Identifiable {
    let id = UUID()
    let role: Role
    var content: String
    var detail: String?
    /// Document text the user attached as context, rendered as a quote block.
    var quotedSelection: String?
    let timestamp: Date

    enum Role {
        case user
        case assistant
        case system
    }

    init(role: Role, content: String, detail: String? = nil, quotedSelection: String? = nil) {
        self.role = role
        self.content = content
        self.detail = detail
        self.quotedSelection = quotedSelection
        self.timestamp = Date()
    }

    var combinedText: String {
        var parts: [String] = []
        if let quotedSelection, !quotedSelection.isEmpty {
            parts.append(quotedSelection)
        }
        parts.append(content)
        if let detail, !detail.isEmpty {
            parts.append(detail)
        }
        return parts.joined(separator: "\n")
    }
}
