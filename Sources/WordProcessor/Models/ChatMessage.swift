import Foundation

struct ChatSource: Identifiable, Equatable {
    let title: String
    let url: String

    var id: String { url }

    var destination: URL? {
        URL(string: url)
    }

    var host: String {
        guard let host = destination?.host else { return "Source" }
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }

    var displayTitle: String {
        let cleaned = title
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? host : cleaned
    }
}

struct ChatMessage: Identifiable {
    let id = UUID()
    let role: Role
    var content: String
    var detail: String?
    var sources: [ChatSource]
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
        sources: [ChatSource] = [],
        deliveryState: DeliveryState = .normal
    ) {
        self.role = role
        self.content = content
        self.detail = detail
        self.sources = sources
        self.deliveryState = deliveryState
        self.timestamp = Date()
    }

    var combinedText: String {
        var parts: [String] = []
        parts.append(content)
        if let detail, !detail.isEmpty {
            parts.append(detail)
        }
        let sourceLines = sources
            .filter { !content.contains($0.url) }
            .map { "\($0.displayTitle): \($0.url)" }
        if !sourceLines.isEmpty {
            parts.append("Sources\n" + sourceLines.joined(separator: "\n"))
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
