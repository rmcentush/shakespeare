import AppKit
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
        let sanitized = NSMutableAttributedString(
            attributedString: NSAttributedString(attributedString)
        )
        let fullRange = NSRange(location: 0, length: sanitized.length)
        sanitized.enumerateAttribute(.link, in: fullRange) { value, range, _ in
            let url: URL?
            if let candidate = value as? URL {
                url = candidate
            } else if let candidate = value as? String {
                url = URL(string: candidate)
            } else {
                url = nil
            }
            if url.map(isAllowed) != true {
                sanitized.removeAttribute(.link, range: range)
            }
        }
        return AttributedString(sanitized)
    }
}
