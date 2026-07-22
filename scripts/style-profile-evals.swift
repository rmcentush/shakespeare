import Foundation

@main
struct StyleProfileEvals {
    static func main() throws {
        try boundsAndDiversifiesEvidence()
        excludesModelAuthoredFeedbackLoops()
        try enforcesEvidenceThresholdsAndCopySafety()
        try preservesReviewedRulesWithoutInventedSupport()
        rejectsMalformedProfiles()
        try persistsOnePrivateReviewDraft()
        print("Style-profile evals passed (6 cases: evidence bounds, feedback-loop safety, thresholds, copy safety, carry-forward, private draft persistence).")
    }

    private static func excludesModelAuthoredFeedbackLoops() {
        let substantial = String(repeating: "The writer actively reshaped this sentence. ", count: 3)
        require(
            !StyleLearningPolicy.isDurableStyleEvidence(
                outcome: "accepted_unchanged",
                finalText: substantial,
                trainingEligible: true,
                confidence: 1
            ),
            "accepted-unchanged model prose entered durable style evidence"
        )
        require(
            StyleLearningPolicy.isDurableStyleEvidence(
                outcome: "accepted_modified",
                finalText: substantial,
                trainingEligible: true,
                confidence: 0.9
            ),
            "an actively modified edit was excluded from durable evidence"
        )
        require(
            !StyleLearningPolicy.isDurableStyleEvidence(
                outcome: "rejected_rewritten",
                finalText: substantial,
                trainingEligible: false,
                confidence: 1
            ),
            "an explicitly ineligible outcome entered durable evidence"
        )
        require(
            !StyleLearningPolicy.isConfirmedUserRewrite(
                outcome: "accepted_unchanged",
                proposedText: substantial,
                finalText: substantial
            ),
            "accepted-unchanged model prose entered the confirmed rewrite layer"
        )
        require(
            StyleLearningPolicy.isConfirmedUserRewrite(
                outcome: "accepted_modified",
                proposedText: "The model produced a broad and generic sentence without the writer's cadence.",
                finalText: substantial
            ),
            "an actively modified rewrite was excluded"
        )
        require(
            StyleLearningPolicy.isConfirmedUserRewrite(
                outcome: "rejected_rewritten",
                proposedText: "The model produced a broad and generic sentence without the writer's cadence.",
                finalText: substantial
            ),
            "a writer-authored replacement was excluded"
        )
        require(
            !StyleLearningPolicy.isConfirmedUserRewrite(
                outcome: "accepted_modified",
                proposedText: "Tiny model change",
                finalText: "Tiny change"
            ),
            "a tiny edit was treated as representative style evidence"
        )
        require(
            !StyleLearningPolicy.isConfirmedUserRewrite(
                outcome: "accepted_modified",
                proposedText: substantial,
                finalText: String(substantial.dropLast()) + "!"
            ),
            "punctuation-only tweaks promoted model prose into the runtime example layer"
        )
    }

    private static func boundsAndDiversifiesEvidence() throws {
        let paragraphA = String(
            repeating: "The opening moves quickly, using concrete nouns and compact declarative sentences. ",
            count: 10
        )
        let paragraphB = String(
            repeating: "The middle widens the argument, then returns to a precise causal claim. ",
            count: 10
        )
        let paragraphC = String(
            repeating: "The ending stops on the consequence instead of explaining its own conclusion. ",
            count: 10
        )
        let samples = (0..<8).map {
            StyleProfileSampleEvidence(
                id: "sample-\($0)",
                text: paragraphA + "\n\n" + paragraphB + "\n\n" + paragraphC
            )
        }
        let edits = (0..<70).map {
            StyleProfileEditEvidence(
                id: "edit-\($0)",
                decision: "accept",
                kind: "voice",
                originalText: String(repeating: "generic opening ", count: 40),
                replacementText: String(repeating: "concrete opening ", count: 40),
                finalText: String(repeating: "writer revised opening ", count: 40),
                documentID: "document-\($0 % 4)",
                sessionID: "session-\($0 % 8)",
                timestamp: Double($0)
            )
        }

        let packet = try StyleProfileEvidenceCompiler.compile(samples: samples, edits: edits)
        require(packet.sampleCount <= 5, "sample count escaped its cap")
        require(packet.editCount <= 40, "edit count escaped its cap")
        require(packet.samplesJSON.utf8.count <= StyleProfileEvidenceCompiler.maximumSampleCharacters, "sample JSON escaped its budget")
        require(packet.editsJSON.utf8.count <= StyleProfileEvidenceCompiler.maximumEditCharacters, "edit JSON escaped its budget")
        require(packet.samplesJSON.contains("The opening moves quickly"), "sample beginning was omitted")
        require(packet.samplesJSON.contains("The middle widens"), "sample middle was omitted")
        require(packet.samplesJSON.contains("The ending stops"), "sample ending was omitted")
        require(!packet.samplesJSON.contains("sample-7"), "sample cap retained the unbounded tail")
    }

    private static func enforcesEvidenceThresholdsAndCopySafety() throws {
        let copied = "the harbor opened beyond the stone road bright with salt and afternoon light"
        let response = """
        {
          "summary": "Direct, concrete prose with controlled variation and decisive paragraph endings.",
          "rules": [
            {"dimension":"syntax","guidance":"Prefer compact declarative sentences before expanding a causal argument.","supporting_sample_ids":["sample-1","sample-2"],"supporting_edit_ids":[],"carried_forward":false},
            {"dimension":"rhythm","guidance":"Vary sentence length, then stop the paragraph on its consequence.","supporting_sample_ids":[],"supporting_edit_ids":["edit-1","edit-2","edit-3","edit-4","edit-5"],"carried_forward":false},
            {"dimension":"voice","guidance":"Use an unsupported weak habit as a permanent rule.","supporting_sample_ids":[],"supporting_edit_ids":["unknown-1","unknown-2","unknown-3"],"carried_forward":false},
            {"dimension":"diction","guidance":"The harbor opened beyond the stone road bright with salt and afternoon light.","supporting_sample_ids":["sample-1","sample-2"],"supporting_edit_ids":[],"carried_forward":false},
            {"dimension":"tone","guidance":"Carry an unreviewed rule without any evidence.","supporting_sample_ids":[],"supporting_edit_ids":[],"carried_forward":true}
          ]
        }
        """

        let profile = try StyleProfileCompiler.compile(
            response: response,
            limits: .init(
                sampleIDs: ["sample-1", "sample-2"],
                editSessionByID: [
                    "edit-1": "session-1",
                    "edit-2": "session-1",
                    "edit-3": "session-2",
                    "edit-4": "session-2",
                    "edit-5": "session-3",
                ]
            ),
            sourceTexts: [copied],
            currentProfile: "",
            date: "2026-07-16"
        )
        require(profile.contains("compact declarative"), "cross-sample rule was dropped")
        require(profile.contains("Vary sentence length"), "repeated edit rule was dropped")
        require(!profile.contains("unsupported weak habit"), "weak edit evidence became a rule")
        require(!profile.lowercased().contains("harbor opened"), "source prose was copied into the profile")
        require(!profile.contains("unreviewed rule"), "unreviewed carry-forward bypassed evidence")
        require(profile.count <= StyleProfileCompiler.maximumProfileCharacters, "profile escaped its runtime budget")
    }

    private static func preservesReviewedRulesWithoutInventedSupport() throws {
        let response = """
        {"summary":"A reviewed profile remains stable until stronger evidence contradicts it.","rules":[
          {"dimension":"voice","guidance":"Open with the concrete claim instead of preliminary scene-setting.","supporting_sample_ids":["invented-sample"],"supporting_edit_ids":["invented-edit"],"carried_forward":true}
        ]}
        """
        let profile = try StyleProfileCompiler.compile(
            response: response,
            limits: .init(sampleIDs: [], editSessionByID: [:]),
            sourceTexts: [],
            currentProfile: "## Established\n- [voice] Open with the concrete claim instead of preliminary scene-setting.",
            date: "2026-07-16"
        )
        require(profile.contains("reviewed"), "carried rule did not expose its reviewed basis")
        require(!profile.contains("invented"), "invented evidence IDs entered the rendered profile")
    }

    private static func rejectsMalformedProfiles() {
        do {
            _ = try StyleProfileCompiler.compile(
                response: "not-json",
                limits: .init(sampleIDs: ["sample-1"], editSessionByID: [:]),
                sourceTexts: [],
                currentProfile: "",
                date: "2026-07-16"
            )
            fatalError("Style-profile eval failed: malformed response was accepted")
        } catch {
            // Expected.
        }
    }

    private static func persistsOnePrivateReviewDraft() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("shakespeare-style-draft-eval-(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = StyleProfileDraftStore(
            fileURL: directory.appendingPathComponent("pending_style_profile.json")
        )
        let draft = StyleProfileDraft(
            proposedMarkdown: "## Established\n- Prefer direct openings.",
            eventIDs: ["sample-1", "edit-2"],
            createdAt: Date(timeIntervalSince1970: 1_700_000_000),
            ruleEvidence: [StyleProfileRuleEvidence(
                dimension: "voice",
                guidance: "Prefer direct openings.",
                established: true,
                sampleIDs: ["sample-1"],
                editIDs: ["edit-2"],
                sessionIDs: ["session-1"],
                carriedForward: false
            )],
            evidenceItems: [StyleProfileEvidenceReviewItem(
                id: "sample-1",
                kind: .sample,
                summary: "Imported sample: “Direct opening.”"
            )]
        )

        try store.save(draft)
        let loadedDraft = try store.load()
        require(loadedDraft == draft, "prepared draft did not round-trip")
        let attributes = try FileManager.default.attributesOfItem(atPath: store.fileURL.path)
        let permissions = (attributes[.posixPermissions] as? NSNumber)?.intValue
        require(permissions == 0o600, "prepared draft was not owner-only")
        try store.delete()
        let deletedDraft = try store.load()
        require(deletedDraft == nil, "discarded draft remained on disk")
    }

    private static func require(_ condition: @autoclosure () -> Bool, _ message: String) {
        guard condition() else { fatalError("Style-profile eval failed: \(message)") }
    }
}
