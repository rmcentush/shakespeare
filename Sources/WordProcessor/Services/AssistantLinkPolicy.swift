import Foundation

enum AssistantLinkPolicy {
    static func isAllowed(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased(),
              scheme == "https" || scheme == "http",
              let host = url.host,
              !host.isEmpty,
              url.user == nil,
              url.password == nil
        else { return false }
        return true
    }

    static func sanitized(_ attributedString: AttributedString) -> AttributedString {
        var sanitized = attributedString
        for run in sanitized.runs {
            if let link = run.link, !isAllowed(link) {
                sanitized[run.range].link = nil
            }
        }
        return sanitized
    }
}
