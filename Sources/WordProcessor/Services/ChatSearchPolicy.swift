import Foundation

/// Keeps ordinary draft conversation fast while preserving live, cited research
/// when the writer's wording calls for fresh or externally verified information.
enum ChatSearchPolicy {
    private static let searchPhrases = [
        "as of",
        "breaking news",
        "browse the web",
        "check online",
        "cite sources",
        "current evidence",
        "external evidence",
        "fact check",
        "fact-check",
        "find sources",
        "latest news",
        "live web",
        "look it up",
        "look up",
        "on the web",
        "recent news",
        "research this",
        "right now",
        "search online",
        "search the web",
        "source-backed",
        "this month",
        "this week",
        "this year",
    ]

    private static let searchTerms: Set<String> = [
        "browse",
        "citation",
        "citations",
        "cite",
        "currently",
        "forecast",
        "latest",
        "news",
        "newest",
        "online",
        "poll",
        "polls",
        "price",
        "prices",
        "recent",
        "research",
        "schedule",
        "score",
        "scores",
        "search",
        "source",
        "sources",
        "stock",
        "stocks",
        "today",
        "tonight",
        "tomorrow",
        "verify",
        "weather",
    ]

    static func requiresWebSearch(for query: String) -> Bool {
        let normalized = query
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !normalized.isEmpty else { return false }
        if normalized.contains("http://") ||
            normalized.contains("https://") ||
            normalized.contains("www.") {
            return true
        }
        if searchPhrases.contains(where: normalized.contains) { return true }

        let terms = normalized.split(whereSeparator: { !$0.isLetter && !$0.isNumber })
        return terms.contains { searchTerms.contains(String($0)) }
    }
}
