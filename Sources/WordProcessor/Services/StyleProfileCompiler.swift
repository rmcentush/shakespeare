import Foundation

enum StyleLearningPolicy {
    static let minimumConfirmedRewriteCharacters = 60

    /// Durable profile evidence must reflect an active writer choice. Merely
    /// accepting model prose unchanged is useful interaction history, but it
    /// must not teach that same prose back to the model as the writer's voice.
    static func isDurableStyleEvidence(
        outcome: String?,
        finalText: String?,
        trainingEligible: Bool?,
        confidence: Double?
    ) -> Bool {
        guard trainingEligible == true,
              (confidence ?? 0) >= 0.8,
              ["accepted_modified", "later_accepted", "rejected_rewritten"]
                .contains(outcome ?? ""),
              let text = finalText?.trimmingCharacters(in: .whitespacesAndNewlines),
              !text.isEmpty
        else { return false }
        return true
    }

    static func isConfirmedUserRewrite(outcome: String?, finalText: String?) -> Bool {
        guard ["accepted_modified", "rejected_rewritten"].contains(outcome ?? ""),
              let text = finalText?.trimmingCharacters(in: .whitespacesAndNewlines),
              text.count >= minimumConfirmedRewriteCharacters
        else { return false }
        return true
    }

    /// Accepting an inline gap fill unchanged is a preference signal, but not a
    /// writer-authored prose sample. The evidence packet therefore carries only
    /// the writer's note and the fill's abstract style rationale.
    static func isAcceptedGapPreference(
        groupID: String,
        decision: String,
        instruction: String,
        rationale: String,
        outcome: String?,
        confidence: Double?
    ) -> Bool {
        groupID.hasPrefix("edit_gap_")
            && decision == "accept"
            && outcome == "accepted_unchanged"
            && (confidence ?? 0) >= 0.8
            && !instruction.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !rationale.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

struct StyleProfileSampleEvidence: Codable, Equatable, Sendable {
    let id: String
    let text: String
}

struct StyleProfileEditEvidence: Codable, Equatable, Sendable {
    let id: String
    let decision: String
    let kind: String
    let originalText: String
    let replacementText: String
    let finalText: String
    let groupID: String
    let rationale: String
    let timestamp: Double
}

/// Compiles raw local evidence into a deliberately small, provenance-preserving
/// request. Imported documents are sampled across their beginning, middle, and
/// end; edit evidence is clipped field-by-field. No complete document or ledger
/// is ever sent to the profile-refinement request.
enum StyleProfileEvidenceCompiler {
    static let maximumSampleCharacters = 8_500
    static let maximumEditCharacters = 8_000
    static let maximumSamples = 5
    static let maximumEdits = 40

    struct Packet: Equatable, Sendable {
        let samplesJSON: String
        let editsJSON: String
        let eventIDs: [String]
        let sourceTexts: [String]
        let limits: StyleProfileCompiler.EvidenceLimits
        let sampleCount: Int
        let editCount: Int
    }

    static func compile(
        samples: [StyleProfileSampleEvidence],
        edits: [StyleProfileEditEvidence]
    ) throws -> Packet {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]

        var selectedSamples: [StyleProfileSampleEvidence] = []
        for sample in samples.prefix(maximumSamples) {
            let excerpt = representativeExcerpt(from: sample.text, maximumCharacters: 1_500)
            guard excerpt.count >= 240 else { continue }
            let candidate = StyleProfileSampleEvidence(id: sample.id, text: excerpt)
            let encoded = try encoder.encode(selectedSamples + [candidate])
            guard encoded.count <= maximumSampleCharacters else { break }
            selectedSamples.append(candidate)
        }

        var selectedEdits: [StyleProfileEditEvidence] = []
        for edit in edits.suffix(maximumEdits).reversed() {
            let candidate = StyleProfileEditEvidence(
                id: edit.id,
                decision: bounded(edit.decision, to: 40),
                kind: bounded(edit.kind, to: 40),
                originalText: bounded(edit.originalText, to: 240),
                replacementText: bounded(edit.replacementText, to: 240),
                finalText: bounded(edit.finalText, to: 280),
                groupID: bounded(edit.groupID, to: 80),
                rationale: bounded(edit.rationale, to: 160),
                timestamp: edit.timestamp
            )
            let encoded = try encoder.encode(selectedEdits + [candidate])
            guard encoded.count <= maximumEditCharacters else { break }
            selectedEdits.append(candidate)
        }

        let sampleData = try encoder.encode(selectedSamples)
        let editData = try encoder.encode(selectedEdits)
        let sampleJSON = String(decoding: sampleData, as: UTF8.self)
        let editsJSON = String(decoding: editData, as: UTF8.self)
        let eventIDs = (selectedSamples.map(\.id) + selectedEdits.map(\.id)).reduce(into: [String]()) {
            if !$0.contains($1) { $0.append($1) }
        }
        let groups = Set(selectedEdits.map(\.groupID).filter { !$0.isEmpty })
        let sourceTexts = selectedSamples.map(\.text) + selectedEdits.flatMap {
            [$0.originalText, $0.replacementText, $0.finalText]
        }.filter { !$0.isEmpty }

        return Packet(
            samplesJSON: sampleJSON,
            editsJSON: editsJSON,
            eventIDs: eventIDs,
            sourceTexts: sourceTexts,
            limits: StyleProfileCompiler.EvidenceLimits(
                sampleCount: selectedSamples.count,
                editCount: selectedEdits.count,
                editGroupCount: groups.count
            ),
            sampleCount: selectedSamples.count,
            editCount: selectedEdits.count
        )
    }

    private static func representativeExcerpt(
        from rawText: String,
        maximumCharacters: Int
    ) -> String {
        let text = rawText
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return "" }

        let paragraphs = text.components(separatedBy: "\n\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { $0.count >= 120 }
        guard !paragraphs.isEmpty else { return bounded(text, to: maximumCharacters) }

        let candidateIndices = [0, paragraphs.count / 2, paragraphs.count - 1]
        var seen = Set<Int>()
        var selected: [String] = []
        var remaining = maximumCharacters
        for index in candidateIndices where seen.insert(index).inserted {
            let separatorCost = selected.isEmpty ? 0 : 2
            guard remaining > separatorCost + 120 else { break }
            remaining -= separatorCost
            let excerpt = bounded(paragraphs[index], to: min(500, remaining))
            selected.append(excerpt)
            remaining -= excerpt.count
        }
        return selected.joined(separator: "\n\n")
    }

    private static func bounded(_ value: String, to maximumCharacters: Int) -> String {
        let normalized = value
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard normalized.count > maximumCharacters else { return normalized }
        return String(normalized.prefix(maximumCharacters - 1)).trimmingCharacters(
            in: .whitespacesAndNewlines
        ) + "…"
    }
}

/// Validates the model-produced profile against the amount of evidence actually
/// supplied, removes copied prose, and renders one compact file used at runtime.
/// The model proposes rules; these deterministic gates decide what may survive.
enum StyleProfileCompiler {
    static let maximumProfileCharacters = 1_800
    static let maximumEstablishedRules = 12
    static let maximumEmergingRules = 6

    struct EvidenceLimits: Equatable, Sendable {
        let sampleCount: Int
        let editCount: Int
        let editGroupCount: Int
    }

    enum CompilerError: LocalizedError {
        case invalidResponse
        case insufficientEvidence

        var errorDescription: String? {
            switch self {
            case .invalidResponse:
                return "The style refiner returned an invalid profile. Nothing was changed."
            case .insufficientEvidence:
                return "The evidence did not support a safe style-profile update yet."
            }
        }
    }

    struct ModelProfile: Codable, Equatable, Sendable {
        let summary: String
        let rules: [ModelRule]
    }

    struct ModelRule: Codable, Equatable, Sendable {
        let dimension: String
        let guidance: String
        let sampleCount: Int
        let editCount: Int
        let editGroupCount: Int
        let carriedForward: Bool

        enum CodingKeys: String, CodingKey {
            case dimension
            case guidance
            case sampleCount = "sample_count"
            case editCount = "edit_count"
            case editGroupCount = "edit_group_count"
            case carriedForward = "carried_forward"
        }
    }

    static let outputSchema: [String: Any] = [
        "type": "object",
        "properties": [
            "summary": ["type": "string"],
            "rules": [
                "type": "array",
                "items": [
                    "type": "object",
                    "properties": [
                        "dimension": [
                            "type": "string",
                            "enum": [
                                "voice", "tone", "diction", "syntax", "rhythm",
                                "paragraphs", "structure", "clarity", "concision", "avoidance",
                            ],
                        ],
                        "guidance": ["type": "string"],
                        "sample_count": ["type": "integer", "minimum": 0],
                        "edit_count": ["type": "integer", "minimum": 0],
                        "edit_group_count": ["type": "integer", "minimum": 0],
                        "carried_forward": ["type": "boolean"],
                    ],
                    "required": [
                        "dimension", "guidance", "sample_count", "edit_count",
                        "edit_group_count", "carried_forward",
                    ],
                    "additionalProperties": false,
                ],
            ],
        ],
        "required": ["summary", "rules"],
        "additionalProperties": false,
    ]

    static func compile(
        response: String,
        limits: EvidenceLimits,
        sourceTexts: [String],
        currentProfile: String,
        date: String
    ) throws -> String {
        guard let data = jsonData(from: response),
              let profile = try? JSONDecoder().decode(ModelProfile.self, from: data)
        else { throw CompilerError.invalidResponse }

        struct AcceptedRule {
            let line: String
            let established: Bool
        }

        let reviewedRules = reviewedRuleStatuses(in: currentProfile)
        var accepted: [AcceptedRule] = []
        var seen = Set<String>()
        for rule in profile.rules {
            let dimension = rule.dimension.lowercased()
            guard allowedDimensions.contains(dimension) else { continue }
            let guidance = compactSentence(rule.guidance, maximumCharacters: 180)
            guard guidance.count >= 12,
                  !containsCopiedPhrase(guidance, in: sourceTexts),
                  seen.insert(guidance.lowercased()).inserted
            else { continue }

            let sampleCount = min(max(rule.sampleCount, 0), limits.sampleCount)
            let editCount = min(max(rule.editCount, 0), limits.editCount)
            let groupCount = min(max(rule.editGroupCount, 0), limits.editGroupCount)
            let reviewedStatus = rule.carriedForward
                ? reviewedRules[guidance.lowercased()]
                : nil
            let carriedEstablished = reviewedStatus == true
            let carriedEmerging = reviewedStatus == false
            let established = carriedEstablished
                || sampleCount >= 2
                || (editCount >= 5 && groupCount >= 3)
                || (sampleCount >= 1 && editCount >= 3 && groupCount >= 2)
            let emerging = carriedEmerging
                || sampleCount >= 1
                || (editCount >= 3 && groupCount >= 2)
            guard established || emerging else { continue }

            var evidence: [String] = []
            if sampleCount > 0 { evidence.append("\(sampleCount) sample\(sampleCount == 1 ? "" : "s")") }
            if editCount > 0 { evidence.append("\(editCount) edits/\(groupCount) sessions") }
            if reviewedStatus != nil && evidence.isEmpty { evidence.append("reviewed") }
            let suffix = evidence.isEmpty ? "" : " — \(evidence.joined(separator: ", "))"
            accepted.append(AcceptedRule(
                line: "- [\(dimension)] \(guidance)\(suffix)",
                established: established
            ))
        }

        let established = accepted.filter(\.established).prefix(maximumEstablishedRules)
        let emerging = accepted.filter { !$0.established }.prefix(maximumEmergingRules)
        guard !established.isEmpty || !emerging.isEmpty else {
            throw CompilerError.insufficientEvidence
        }

        var rendered = "# Learned Style Profile\n\nUpdated: \(date)"
        let summary = compactSentence(profile.summary, maximumCharacters: 220)
        if summary.count >= 20, !containsCopiedPhrase(summary, in: sourceTexts) {
            let candidate = rendered + "\n\nProfile: \(summary)"
            if candidate.count <= maximumProfileCharacters { rendered = candidate }
        }

        for (heading, rules) in [
            ("## Established", established.map(\.line)),
            ("## Emerging", emerging.map(\.line)),
        ] where !rules.isEmpty {
            var section = heading
            var appendedRule = false
            for line in rules {
                let candidateSection = section + "\n" + line
                let candidateProfile = rendered + "\n\n" + candidateSection
                guard candidateProfile.count <= maximumProfileCharacters else { break }
                section = candidateSection
                appendedRule = true
            }
            if appendedRule { rendered += "\n\n" + section }
        }
        guard rendered.contains("- [") else { throw CompilerError.insufficientEvidence }
        return rendered
    }

    private static let allowedDimensions: Set<String> = [
        "voice", "tone", "diction", "syntax", "rhythm",
        "paragraphs", "structure", "clarity", "concision", "avoidance",
    ]

    private static func reviewedRuleStatuses(in markdown: String) -> [String: Bool] {
        var established = true
        var result: [String: Bool] = [:]
        for rawLine in markdown.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            if line.hasPrefix("## ") {
                let heading = line.lowercased()
                established = !heading.contains("emerging") && !heading.contains("tentative")
                continue
            }
            guard line.hasPrefix("- ") else { continue }
            var guidance = String(line.dropFirst(2))
            if guidance.hasPrefix("["), let bracket = guidance.firstIndex(of: "]") {
                guidance = String(guidance[guidance.index(after: bracket)...])
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            }
            if let evidence = guidance.range(of: " — ") {
                guidance = String(guidance[..<evidence.lowerBound])
            } else if let evidence = guidance.range(of: " (evidence", options: .caseInsensitive) {
                guidance = String(guidance[..<evidence.lowerBound])
            }
            let compact = compactSentence(guidance, maximumCharacters: 180).lowercased()
            if compact.count >= 12 { result[compact] = established }
        }
        return result
    }

    private static func jsonData(from response: String) -> Data? {
        var cleaned = response.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned.hasPrefix("```json") { cleaned.removeFirst("```json".count) }
        else if cleaned.hasPrefix("```") { cleaned.removeFirst(3) }
        if cleaned.hasSuffix("```") { cleaned.removeLast(3) }
        cleaned = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
        if let first = cleaned.firstIndex(of: "{"), let last = cleaned.lastIndex(of: "}") {
            cleaned = String(cleaned[first...last])
        }
        return cleaned.data(using: .utf8)
    }

    private static func compactSentence(_ raw: String, maximumCharacters: Int) -> String {
        let normalized = raw
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
            .replacingOccurrences(of: "\"", with: "")
            .replacingOccurrences(of: "“", with: "")
            .replacingOccurrences(of: "”", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard normalized.count > maximumCharacters else { return normalized }
        let prefix = String(normalized.prefix(maximumCharacters - 1))
        let boundary = prefix.lastIndex(where: { $0.isWhitespace }) ?? prefix.endIndex
        return String(prefix[..<boundary]).trimmingCharacters(in: .whitespacesAndNewlines) + "…"
    }

    static func containsCopiedPhrase(
        _ candidate: String,
        in sources: [String],
        minimumWords: Int = 8
    ) -> Bool {
        let candidateTokens = tokens(in: candidate)
        guard candidateTokens.count >= minimumWords else { return false }
        let candidatePhrases = ngrams(candidateTokens, length: minimumWords)
        guard !candidatePhrases.isEmpty else { return false }
        for source in sources {
            let sourceTokens = tokens(in: source)
            if !candidatePhrases.isDisjoint(with: ngrams(sourceTokens, length: minimumWords)) {
                return true
            }
        }
        return false
    }

    private static func tokens(in text: String) -> [String] {
        text.lowercased().split { !$0.isLetter && !$0.isNumber }.map(String.init)
    }

    private static func ngrams(_ tokens: [String], length: Int) -> Set<String> {
        guard length > 0, tokens.count >= length else { return [] }
        return Set((0...(tokens.count - length)).map {
            tokens[$0..<($0 + length)].joined(separator: "\u{001f}")
        })
    }
}
