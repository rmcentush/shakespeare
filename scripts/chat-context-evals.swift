import Foundation

@main
struct ChatContextEvals {
    static func main() {
        let paragraphs = (0..<60).map { index in
            if index == 47 {
                return "Zebra evidence appears here with the decisive archival finding and its consequence. "
                    + String(repeating: "Relevant supporting detail. ", count: 12)
            }
            return "Paragraph \(index) develops this part of the essay. "
                + String(repeating: "Distinct draft context for structure and continuity. ", count: 12)
        }
        let document = paragraphs.joined(separator: "\n\n")

        let focused = ChatDocumentContextAssembler.assemble(
            document: document,
            query: "What does the zebra evidence establish?"
        )
        require(
            focused.count <= ChatDocumentContextAssembler.standardMaximumCharacters,
            "focused context exceeded its budget"
        )
        require(focused.contains("Paragraph 0"), "draft opening was omitted")
        require(focused.contains("Paragraph 59"), "draft ending was omitted")
        require(focused.contains("Zebra evidence"), "query-relevant evidence was omitted")
        require(!focused.contains("Paragraph 31"), "ordinary query resent too much middle context")

        let selectionFocused = ChatDocumentContextAssembler.assemble(
            document: document,
            query: "Give feedback on this selection.",
            selection: "Zebra evidence decisive archival finding consequence"
        )
        require(
            selectionFocused.contains("Zebra evidence"),
            "the selected passage did not pull in its surrounding draft context"
        )
        require(
            selectionFocused.count <= ChatDocumentContextAssembler.standardMaximumCharacters,
            "selection-focused context exceeded its budget"
        )

        let whole = ChatDocumentContextAssembler.assemble(
            document: document,
            query: "Review the overall flow of the entire draft."
        )
        require(
            whole.count <= ChatDocumentContextAssembler.wholeDocumentMaximumCharacters,
            "whole-document context exceeded its budget"
        )
        require(whole.count > focused.count, "whole-document request did not receive a larger budget")

        let short = "A short document stays intact."
        require(
            ChatDocumentContextAssembler.assemble(document: short, query: "Summarize") == short,
            "short document was needlessly transformed"
        )

        print("Chat context evals passed (query and selection relevance, flow, adaptive budgets, short drafts).")
    }

    private static func require(_ condition: @autoclosure () -> Bool, _ message: String) {
        guard condition() else { fatalError("Chat context eval failed: \(message)") }
    }
}
