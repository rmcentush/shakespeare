import Foundation

@main
private struct ChatSearchPolicyEvals {
    static func main() {
        let researchQueries = [
            "What's the weather in San Francisco right now?",
            "Fact-check this claim and cite sources.",
            "Find current evidence for this argument.",
            "Search the web for the latest polling.",
            "Summarize https://example.com/report",
            "What is Apple's stock price today?",
        ]
        for query in researchQueries {
            precondition(ChatSearchPolicy.requiresWebSearch(for: query), query)
        }

        let conversationalQueries = [
            "Reply with exactly: Ready.",
            "Tighten this paragraph.",
            "What counterargument is missing from my draft?",
            "Give this scene a stronger ending.",
            "Explain the difference between affect and effect.",
        ]
        for query in conversationalQueries {
            precondition(!ChatSearchPolicy.requiresWebSearch(for: query), query)
        }

        print("Chat search-policy evals passed (research routing and fast-path conversation).")
    }
}
