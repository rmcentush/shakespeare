import Foundation

@main
struct StyleContextEvals {
    static func main() throws {
        try compactsBundledGuidesDeterministically()
        retrievesTaskRelevantSections()
        boundsLearnedPreferencesWithoutChangingPrecedence()
        retrievesRelevantWritingSamplesWithinBudget()
        usesConfirmedRewritesWithoutCreatingAFeedbackArchive()
        mapsWholeDocumentFlowWithinBudget()
        scopesAmbientReviewToChangedBlocks()
        print("Style-context evals passed (7 cases: retrieval, samples, rewrites, document flow, budgets, precedence, incremental scope).")
    }

    private static func compactsBundledGuidesDeterministically() throws {
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let reference = try String(
            contentsOf: root.appendingPathComponent(
                "Sources/WordProcessor/Resources/writing_style_reference.md"
            ),
            encoding: .utf8
        )
        let guidance = try String(
            contentsOf: root.appendingPathComponent(
                "Sources/WordProcessor/Resources/writing_quality_guidance.md"
            ),
            encoding: .utf8
        )
        let learned = """
        # Reviewed preferences
        - Prefer concrete openings. Evidence: 8 decisions.
        - Keep the author's deliberate fragments. Evidence: 6 decisions.
        """

        let first = StyleContextAssembler.assemble(
            task: "ambient voice and structure review",
            documentExcerpt: "A short opening leads into a long causal argument.",
            reference: reference,
            learnedPreferences: learned,
            generalGuidance: guidance
        )
        let second = StyleContextAssembler.assemble(
            task: "ambient voice and structure review",
            documentExcerpt: "A short opening leads into a long causal argument.",
            reference: reference,
            learnedPreferences: learned,
            generalGuidance: guidance
        )

        require(first == second, "style retrieval is not deterministic")
        require(
            first.characterCount <= StyleContextAssembler.maxPacketCharacters,
            "style packet exceeded its hard character budget"
        )
        require(
            first.characterCount < reference.count + guidance.count,
            "style packet did not compact the bundled guides"
        )
        require(
            first.text.contains("Reviewed learned preferences are the most specific"),
            "precedence contract is missing"
        )
        require(
            first.text.contains("Prefer concrete openings"),
            "reviewed learned preference was omitted"
        )
        require(
            first.selectedReferenceSections.count <= 4
                && first.selectedGuidanceSections.count <= 2,
            "retrieval selected too many sections"
        )
        require(first.estimatedTokenCount <= 2_000, "style packet exceeded its token target")
    }

    private static func retrievesTaskRelevantSections() {
        let reference = """
        # Reference
        Intro.
        ## The core stance
        CORE_MARKER
        ## Evidence and citations
        EVIDENCE_MARKER
        ## Humor
        HUMOR_MARKER
        ## Formatting
        FORMATTING_MARKER
        ## Paragraph mechanics
        PARAGRAPH_MARKER
        ## Sentence mechanics
        SENTENCE_MARKER
        ## Anti-patterns
        ANTI_MARKER
        ## Voice check
        VOICE_MARKER
        ## Travel writing
        TRAVEL_MARKER
        """
        let guidance = """
        # General
        ## Word choice
        WORD_MARKER
        ### Negative parallelism
        NEGATIVE_PARALLELISM_MARKER
        ### Rhetorical questions
        QUESTION_MARKER
        ### Stock conclusions
        CONCLUSION_MARKER
        """

        let packet = StyleContextAssembler.assemble(
            task: "check humor and negative parallelism",
            documentExcerpt: "The result? A joke nobody asked for.",
            reference: reference,
            learnedPreferences: "",
            generalGuidance: guidance
        )

        require(packet.text.contains("HUMOR_MARKER"), "task-relevant humor section was not retrieved")
        require(
            packet.text.contains("NEGATIVE_PARALLELISM_MARKER"),
            "task-relevant general guidance was not retrieved"
        )
    }

    private static func boundsLearnedPreferencesWithoutChangingPrecedence() {
        let longPreferences = (0..<600).map {
            "- Reviewed personal rule \($0): keep the exact intended claim."
        }.joined(separator: "\n")
        let packet = StyleContextAssembler.assemble(
            task: "rewrite",
            documentExcerpt: "",
            reference: "## The core stance\nBe direct.",
            learnedPreferences: longPreferences
        )

        require(
            packet.characterCount <= StyleContextAssembler.maxPacketCharacters,
            "long preferences escaped the packet budget"
        )
        require(packet.text.contains("Reviewed personal rule 0"), "learned rules were omitted")
        require(packet.text.contains("excerpt bounded locally"), "bounded excerpt marker is missing")
        let learnedIndex = packet.text.range(of: "<reviewed_learned_preferences>")?.lowerBound
        let referenceIndex = packet.text.range(of: "<relevant_author_reference>")?.lowerBound
        require(
            learnedIndex != nil && referenceIndex != nil && learnedIndex! < referenceIndex!,
            "learned preferences no longer precede the general reference"
        )
    }

    private static func scopesAmbientReviewToChangedBlocks() {
        let blocks = (0..<80).map { index in
            StyleContextAssembler.ReviewBlock(
                id: "block-\(index)",
                from: index * 100,
                to: index * 100 + 90,
                textHash: "hash-\(index)"
            )
        }
        var reviewed = Dictionary(uniqueKeysWithValues: blocks.map { ($0.id, $0.textHash) })
        reviewed["block-40"] = "old-hash"

        let indices = StyleContextAssembler.reviewBlockIndices(
            blocks: blocks,
            reviewedHashes: reviewed,
            cursorPosition: 4_050,
            limit: 24
        )
        require(indices == [39, 40, 41], "changed block did not receive immediate continuity neighbors")

        let coldStart = StyleContextAssembler.reviewBlockIndices(
            blocks: blocks,
            reviewedHashes: [:],
            cursorPosition: 4_050,
            limit: 24
        )
        require(coldStart.count == 24, "cold-start review did not honor its block cap")
        require(coldStart.contains(40), "cold-start scope did not prioritize the cursor area")

        let unchanged = StyleContextAssembler.reviewBlockIndices(
            blocks: blocks,
            reviewedHashes: Dictionary(uniqueKeysWithValues: blocks.map { ($0.id, $0.textHash) }),
            cursorPosition: 4_050,
            limit: 24
        )
        require(unchanged.isEmpty, "unchanged blocks were needlessly selected")
    }

    private static func retrievesRelevantWritingSamplesWithinBudget() {
        let technical = String(repeating: "The compiler makes each boundary explicit and keeps the runtime small. ", count: 8)
        let travel = String(repeating: "The harbor opened beyond the stone road, bright with salt and afternoon light. ", count: 8)
        let packet = StyleContextAssembler.assemble(
            task: "revise this technical explanation",
            documentExcerpt: "A compiler and runtime are involved.",
            reference: "## The core stance\nBe precise.",
            learnedPreferences: "",
            writingSamples: [travel, technical]
        )

        require(packet.selectedSampleCount > 0, "no representative sample was selected")
        require(packet.selectedSampleCount <= 2, "too many writing samples entered context")
        require(packet.text.contains("compiler makes each boundary"), "relevant sample was not retrieved")
        require(packet.text.contains("Never copy their names, facts"), "sample safety instruction is missing")
        require(packet.characterCount <= StyleContextAssembler.maxPacketCharacters, "samples escaped the packet budget")
    }

    private static func usesConfirmedRewritesWithoutCreatingAFeedbackArchive() {
        let direct = String(
            repeating: "The revised paragraph begins with the claim and stops on the consequence. ",
            count: 5
        )
        let rhythmic = String(
            repeating: "A long sentence gathers the evidence. Then the short sentence lands. ",
            count: 5
        )
        let ignoredTail = String(
            repeating: "This third rewrite must remain outside the two-example runtime cap. ",
            count: 5
        )
        let packet = StyleContextAssembler.assemble(
            task: "tighten the paragraph opening and rhythm",
            documentExcerpt: "The opening delays its main claim.",
            reference: "## The core stance\nBe direct.",
            learnedPreferences: "## Established\n- Prefer concrete openings.",
            writingSamples: [],
            confirmedEdits: [direct, rhythmic, ignoredTail]
        )

        require(packet.selectedConfirmedEditCount == 2, "confirmed rewrite cap was not enforced")
        require(packet.text.contains("<confirmed_saved_rewrites>"), "confirmed rewrites were not layered")
        require(packet.text.contains("recent positive examples, not general rules"), "rewrite safety precedence is missing")
        require(!packet.text.contains("third rewrite must remain"), "confirmed rewrite tail entered context")
        require(packet.characterCount <= StyleContextAssembler.maxPacketCharacters, "rewrites escaped the packet budget")
    }

    private static func mapsWholeDocumentFlowWithinBudget() {
        let blocks = (0..<60).map { index in
            StyleContextAssembler.FlowBlock(
                id: "block-\(index)",
                type: [0, 20, 40].contains(index) ? "heading" : "paragraph",
                text: index == 0
                    ? "Opening thesis about institutional incentives and their downstream consequences."
                    : index == 59
                        ? "The conclusion returns to the thesis and states the practical consequence."
                        : "Paragraph \(index) develops a distinct step in the essay's causal sequence without standing in for the complete paragraph."
            )
        }
        let map = StyleContextAssembler.documentFlowMap(
            blocks: blocks,
            targetIDs: ["block-30"]
        )

        require(map.count <= StyleContextAssembler.maxDocumentFlowCharacters, "document flow map escaped its budget")
        require(map.contains("Opening thesis"), "flow map omitted the essay opening")
        require(map.contains("20/60 heading") || map.contains("21/60 heading"), "flow map omitted section headings")
        require(map.contains("conclusion returns"), "flow map omitted the essay ending")
        require(map.contains("Paragraph 29") || map.contains("Paragraph 31"), "flow map omitted target-adjacent continuity")
        require(map.split(separator: "\n").count < blocks.count / 2, "flow map copied too much of the document")
    }

    private static func require(_ condition: @autoclosure () -> Bool, _ message: String) {
        guard condition() else {
            fatalError("Style-context eval failed: \(message)")
        }
    }
}
