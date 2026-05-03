import Darwin
import Foundation

@main
struct LLMEditEvals {
    static func main() {
        var failures: [String] = []

        expectNarrowedSentence(&failures)
        expectNarrowedBracket(&failures)
        expectRepeatedSentenceFallsBack(&failures)
        expectFormattedReplacementFallsBack(&failures)

        if failures.isEmpty {
            print("LLM edit evals passed (4 fixtures).")
            return
        }

        print("LLM edit evals failed:")
        for failure in failures {
            print("- \(failure)")
        }
        exit(1)
    }

    private static func expectNarrowedSentence(_ failures: inout [String]) {
        let original = "The opening is fine. This sentence needs work. The ending is fine."
        let replacement = "The opening is fine. This sentence is sharper. The ending is fine."
        let result = EditTargetResolver.resolve(
            findText: original,
            replacementHTML: replacement,
            documentText: original
        )

        guard case .narrowed(let target) = result,
              target.findText == "This sentence needs work.",
              target.replaceHTML == "This sentence is sharper."
        else {
            failures.append("expected paragraph rewrite to narrow to the changed sentence")
            return
        }
    }

    private static func expectNarrowedBracket(_ failures: inout [String]) {
        let original = "The claim (old wording) should stay scoped."
        let replacement = "The claim (new wording) should stay scoped."
        let result = EditTargetResolver.resolve(
            findText: original,
            replacementHTML: replacement,
            documentText: original
        )

        guard case .narrowed(let target) = result,
              target.findText == "(old wording)",
              target.replaceHTML == "(new wording)"
        else {
            failures.append("expected bracketed rewrite to narrow to the changed bracketed span")
            return
        }
    }

    private static func expectRepeatedSentenceFallsBack(_ failures: inout [String]) {
        let original = "First sentence. Shared sentence. Last sentence."
        let replacement = "First sentence. New sentence. Last sentence."
        let document = "\(original)\n\nAnother paragraph. Shared sentence. Done."
        let result = EditTargetResolver.resolve(
            findText: original,
            replacementHTML: replacement,
            documentText: document
        )

        guard case .useOriginal = result else {
            failures.append("expected repeated changed sentence to keep the original broader target")
            return
        }
    }

    private static func expectFormattedReplacementFallsBack(_ failures: inout [String]) {
        let result = EditTargetResolver.resolve(
            findText: "This sentence changes.",
            replacementHTML: "<strong>This sentence changes with formatting.</strong>",
            documentText: "This sentence changes."
        )

        guard case .useOriginal = result else {
            failures.append("expected formatted replacement to keep original scope")
            return
        }
    }
}
