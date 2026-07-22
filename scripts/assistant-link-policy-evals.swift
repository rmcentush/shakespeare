import Darwin
import Foundation

@main
struct AssistantLinkPolicyEvals {
    static func main() throws {
        let allowed = [
            "https://example.com/research",
            "http://localhost:8080/source",
        ]
        let rejected = [
            "file:///etc/passwd",
            "javascript:alert(1)",
            "data:text/html,unsafe",
            "https://user:secret@example.com/private",
            "mailto:test@example.com",
        ]

        for raw in allowed {
            guard let url = URL(string: raw), AssistantLinkPolicy.isAllowed(url) else {
                fail("rejected expected web URL: \(raw)")
            }
        }
        for raw in rejected {
            guard let url = URL(string: raw), !AssistantLinkPolicy.isAllowed(url) else {
                fail("accepted unsafe URL: \(raw)")
            }
        }

        let markdown = try AttributedString(
            markdown: "[safe](https://example.com) [unsafe](file:///etc/passwd)",
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        )
        let links = AssistantLinkPolicy.sanitized(markdown).runs.compactMap(\.link)
        guard links.count == 1, links.first?.scheme == "https" else {
            fail("markdown sanitizer did not remove the unsafe link")
        }
        print("Assistant link policy eval passed.")
    }

    private static func fail(_ message: String) -> Never {
        print("Assistant link policy eval failed: \(message)")
        exit(1)
    }
}
