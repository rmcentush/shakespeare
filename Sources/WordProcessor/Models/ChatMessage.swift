import Foundation

struct ChatMessage: Identifiable {
    let id = UUID()
    let role: Role
    var content: String
    var detail: String?
    let timestamp: Date

    enum Role {
        case user
        case assistant
        case system
    }

    init(role: Role, content: String, detail: String? = nil) {
        self.role = role
        self.content = content
        self.detail = detail
        self.timestamp = Date()
    }

    var combinedText: String {
        guard let detail, !detail.isEmpty else { return content }
        return "\(content)\n\(detail)"
    }
}
