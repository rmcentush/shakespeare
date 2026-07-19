import Foundation

struct ChatMessage: Identifiable {
    let id = UUID()
    let role: Role
    var content: String
    var detail: String?
    var deliveryState: DeliveryState
    let timestamp: Date

    enum Role {
        case user
        case assistant
        case system
    }

    enum DeliveryState: Equatable {
        case normal
        case cancelled
        case failed(title: String, detail: String)
    }

    init(
        role: Role,
        content: String,
        detail: String? = nil,
        deliveryState: DeliveryState = .normal
    ) {
        self.role = role
        self.content = content
        self.detail = detail
        self.deliveryState = deliveryState
        self.timestamp = Date()
    }

    var combinedText: String {
        var parts: [String] = []
        parts.append(content)
        if let detail, !detail.isEmpty {
            parts.append(detail)
        }
        switch deliveryState {
        case .normal:
            break
        case .cancelled:
            parts.append("Request cancelled.")
        case .failed(let title, let detail):
            parts.append("\(title)\n\(detail)")
        }
        return parts.joined(separator: "\n")
    }
}
