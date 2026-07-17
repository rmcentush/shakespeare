import CryptoKit
import Foundation

enum PersonalizationSettings {
    static let enabledDefaultsKey = "personalizationCollectionEnabled"
    private static let writerIDDefaultsKey = "personalizationWriterID"

    static var isEnabled: Bool {
        get {
            guard UserDefaults.standard.object(forKey: enabledDefaultsKey) != nil else {
                return true
            }
            return UserDefaults.standard.bool(forKey: enabledDefaultsKey)
        }
        set { UserDefaults.standard.set(newValue, forKey: enabledDefaultsKey) }
    }

    static var writerID: String {
        if let existing = UserDefaults.standard.string(forKey: writerIDDefaultsKey),
           !existing.isEmpty {
            return existing
        }
        let created = UUID().uuidString
        UserDefaults.standard.set(created, forKey: writerIDDefaultsKey)
        return created
    }
}

struct PersonalizationOutcomeSnapshot: Codable, Equatable, Sendable {
    let actionID: String
    let outcome: String
    let finalText: String
    let confidence: Double
    let trainingEligible: Bool
}

final class TrainingEventStore: @unchecked Sendable {
    static let shared = TrainingEventStore()
    static let currentSchemaVersion = 2
    static let maximumWritingSampleCharacters = 100_000
    static let minimumWritingSampleWords = 300
    static let maximumWritingSamples = 50

    struct Consent: Codable, Equatable, Sendable {
        let collectionEnabled: Bool
        let scope: String
    }

    struct Provenance: Codable, Equatable, Sendable {
        let application: String
        let applicationVersion: String
        let capture: String
    }

    struct Event: Codable, Identifiable, Equatable, Sendable {
        let schemaVersion: Int
        let id: String
        let eventType: String
        let recordedAt: Double
        let writerID: String
        let documentID: String
        let provider: String
        let model: String
        let source: String
        let operationKind: String
        let learningCategory: String
        let decision: String
        let instruction: String
        let originalText: String
        let proposedText: String
        let finalText: String?
        let surroundingText: String
        let rationale: String
        let groupID: String
        let contentHash: String
        let consent: Consent
        let provenance: Provenance
        let parentEventID: String?
        let outcome: String?
        let confidence: Double?
        let trainingEligible: Bool?
    }

    struct DecisionSummary: Codable, Identifiable, Equatable, Sendable {
        let id: String
        let decision: String
        let source: String
        let kind: String
        let originalText: String
        let replacementText: String
        let finalText: String?
        let surroundingSentence: String
        let groupID: String
        let rationale: String
        let outcome: String?
        let confidence: Double?
        let timestamp: Double
    }

    struct WritingSampleSummary: Codable, Identifiable, Equatable, Sendable {
        let id: String
        let text: String
        let timestamp: Double
    }

    struct Readiness: Equatable, Sendable {
        let eventCount: Int
        let resolvedEditCount: Int
        let eligibleExampleCount: Int
        let styleDecisionCount: Int
        let confirmedRewriteCount: Int
        let bootstrapSampleCount: Int

        var progress: Double {
            let editProgress = min(Double(eligibleExampleCount) / 30, 1) * 0.7
                + min(Double(confirmedRewriteCount) / 8, 1) * 0.3
            let sampleProgress = min(Double(bootstrapSampleCount) / 5, 1)
            return max(editProgress, sampleProgress)
        }

        var status: String {
            if !PersonalizationSettings.isEnabled {
                return "Learning is paused"
            }
            if progress >= 1 {
                return "Your style profile is well grounded"
            }
            if bootstrapSampleCount > 0 {
                return "Learning from imported writing samples"
            }
            if eligibleExampleCount >= 15 {
                return "Building a reliable style sample"
            }
            return "Learning from saved edit outcomes"
        }
    }

    enum WritingSampleImportDisposition: Equatable, Sendable {
        case imported
        case duplicate
        case learningDisabled
        case tooShort
        case tooLong
        case insufficientStructure
        case sampleLimitReached
    }

    private static let styleKinds: Set<String> = [
        "voice", "tone", "clarity", "structure", "concision", "style",
    ]
    private let encoder: JSONEncoder
    private let decoder = JSONDecoder()
    private let lock = NSLock()
    private var cachedEvents: [Event]?
    private var cachedEventIDs: Set<String>?
    private var cachedEventLogSize: UInt64?
    private var lastCompactionAttemptEventCount = 0

    var eventLogURL: URL {
        try? ShakespeareStorage.prepare()
        return ShakespeareStorage.personalizationEventsDirectoryURL
            .appendingPathComponent("training_events.jsonl")
    }

    var processedIDsURL: URL {
        AuthorStyleReference.styleDirectoryURL.appendingPathComponent("processed_feedback_ids.json")
    }

    private var legacyFeedbackLogURL: URL {
        AuthorStyleReference.styleDirectoryURL.appendingPathComponent("feedback_log.jsonl")
    }

    private init() {
        encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
    }

    func appendEditDecision(
        _ decision: BridgePayload.EditDecisionData,
        documentID: String,
        runtime: InferenceRuntime
    ) {
        guard PersonalizationSettings.isEnabled, !documentID.isEmpty else { return }
        let event = Event(
            schemaVersion: Self.currentSchemaVersion,
            id: decision.eventID.isEmpty ? UUID().uuidString : decision.eventID,
            eventType: "edit_decision",
            recordedAt: decision.timestamp > 0 ? decision.timestamp : Self.nowMilliseconds,
            writerID: PersonalizationSettings.writerID,
            documentID: documentID,
            provider: runtime.providerID.rawValue,
            model: runtime.model,
            source: decision.source,
            operationKind: decision.kind,
            learningCategory: decision.learningCategory,
            decision: decision.decision,
            instruction: decision.instruction,
            originalText: decision.originalText,
            proposedText: decision.replacementText,
            finalText: nil,
            surroundingText: decision.surroundingSentence,
            rationale: decision.rationale,
            groupID: decision.groupID,
            contentHash: Self.hash(
                [decision.originalText, decision.replacementText, decision.surroundingSentence]
                    .joined(separator: "\u{001f}")
            ),
            consent: Self.localConsent,
            provenance: Self.provenance(capture: "editor_review"),
            parentEventID: nil,
            outcome: nil,
            confidence: nil,
            trainingEligible: nil
        )
        append(event)
    }

    /// Appends immutable, idempotent save-time outcomes and returns action IDs that
    /// the editor may stop tracking. Raw decisions are never rewritten.
    func appendOutcomes(
        _ outcomes: [PersonalizationOutcomeSnapshot],
        documentID: String,
        runtime: InferenceRuntime
    ) -> [String] {
        guard !outcomes.isEmpty else { return [] }
        guard PersonalizationSettings.isEnabled, !documentID.isEmpty else {
            return outcomes.map(\.actionID)
        }

        lock.lock()
        defer { lock.unlock() }

        let events = allEventsUnlocked()
        let actions = events
            .filter { $0.eventType == "edit_decision" && $0.documentID == documentID }
            .reduce(into: [String: Event]()) { result, event in
                result[event.id] = event
            }
        var existingParentIDs = Set(events.compactMap { event in
            event.eventType == "edit_outcome" ? event.parentEventID : nil
        })
        var acknowledged: [String] = []

        for snapshot in outcomes {
            guard let action = actions[snapshot.actionID] else {
                // Do not retroactively collect an action taken while learning was off.
                acknowledged.append(snapshot.actionID)
                continue
            }
            if existingParentIDs.contains(snapshot.actionID) {
                acknowledged.append(snapshot.actionID)
                continue
            }

            let event = Event(
                schemaVersion: Self.currentSchemaVersion,
                id: "\(snapshot.actionID)_outcome",
                eventType: "edit_outcome",
                recordedAt: Self.nowMilliseconds,
                writerID: action.writerID,
                documentID: documentID,
                provider: runtime.providerID.rawValue,
                model: runtime.model,
                source: action.source,
                operationKind: action.operationKind,
                learningCategory: action.learningCategory,
                decision: action.decision,
                instruction: action.instruction,
                originalText: action.originalText,
                proposedText: action.proposedText,
                finalText: snapshot.finalText,
                surroundingText: action.surroundingText,
                rationale: action.rationale,
                groupID: action.groupID,
                contentHash: Self.hash(
                    [snapshot.actionID, snapshot.outcome, snapshot.finalText]
                        .joined(separator: "\u{001f}")
                ),
                consent: Self.localConsent,
                provenance: Self.provenance(capture: "document_save_outcome"),
                parentEventID: snapshot.actionID,
                outcome: snapshot.outcome,
                confidence: min(max(snapshot.confidence, 0), 1),
                trainingEligible: snapshot.trainingEligible && snapshot.confidence >= 0.8
            )

            do {
                try appendUnlocked(event)
                existingParentIDs.insert(snapshot.actionID)
                acknowledged.append(snapshot.actionID)
            } catch {
                print("TrainingEventStore: failed to append outcome: \(error)")
            }
        }
        do {
            try compactIfNeededUnlocked()
        } catch {
            print("TrainingEventStore: failed to compact outcomes: \(error)")
        }
        return acknowledged
    }

    /// Stores a user-confirmed, finished writing sample as a local bootstrap signal.
    /// The source filename/path is intentionally not persisted.
    func appendWritingSample(_ rawText: String) throws -> WritingSampleImportDisposition {
        guard PersonalizationSettings.isEnabled else { return .learningDisabled }
        let text = rawText
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.count <= Self.maximumWritingSampleCharacters else { return .tooLong }
        guard text.split(whereSeparator: \.isWhitespace).count >= Self.minimumWritingSampleWords
        else { return .tooShort }
        guard Self.bootstrapExampleEstimate(for: text) >= 3 else {
            return .insufficientStructure
        }

        let contentHash = Self.hash(text)
        lock.lock()
        defer { lock.unlock() }
        let events = allEventsUnlocked()
        guard !events.contains(where: {
            $0.contentHash == contentHash && $0.provenance.capture == "writing_sample_import"
        }) else {
            return .duplicate
        }
        let writingSampleCount = events.lazy.filter {
            $0.eventType == "document_snapshot"
                && $0.provenance.capture == "writing_sample_import"
        }.count
        guard writingSampleCount < Self.maximumWritingSamples else {
            return .sampleLimitReached
        }

        let documentID = "writing-sample-\(contentHash)"
        let event = Event(
            schemaVersion: Self.currentSchemaVersion,
            id: documentID,
            eventType: "document_snapshot",
            recordedAt: Self.nowMilliseconds,
            writerID: PersonalizationSettings.writerID,
            documentID: documentID,
            provider: "local",
            model: "user-supplied",
            source: "writer",
            operationKind: "bootstrap_import",
            learningCategory: "voice",
            decision: "final",
            instruction: "Continue in the writer's own voice.",
            originalText: "",
            proposedText: "",
            finalText: text,
            surroundingText: "",
            rationale: "",
            groupID: "",
            contentHash: contentHash,
            consent: Self.localConsent,
            provenance: Self.provenance(capture: "writing_sample_import"),
            parentEventID: nil,
            outcome: "user_confirmed_writing_sample",
            confidence: 1,
            trainingEligible: true
        )
        try appendUnlocked(event)
        try compactIfNeededUnlocked()
        return .imported
    }

    func appendCommentDecision(
        decision: String,
        comment: BridgePayload.CommentData,
        documentID: String,
        runtime: InferenceRuntime
    ) {
        guard PersonalizationSettings.isEnabled,
              !documentID.isEmpty,
              comment.source == "agent"
        else { return }
        let timestamp = Self.nowMilliseconds
        let proposed = comment.suggestedReplacement
        let event = Event(
            schemaVersion: Self.currentSchemaVersion,
            id: "\(comment.id)_\(decision)_\(Int(timestamp))",
            eventType: "edit_decision",
            recordedAt: timestamp,
            writerID: PersonalizationSettings.writerID,
            documentID: documentID,
            provider: runtime.providerID.rawValue,
            model: runtime.model,
            source: "ambient_review",
            operationKind: "comment",
            learningCategory: comment.kind,
            decision: decision,
            instruction: "Review this passage while preserving the writer's voice.",
            originalText: comment.selectedText,
            proposedText: proposed,
            finalText: nil,
            surroundingText: comment.selectedText,
            rationale: comment.text,
            groupID: comment.agentRunID.isEmpty ? comment.id : comment.agentRunID,
            contentHash: Self.hash(
                [comment.selectedText, proposed, comment.text].joined(separator: "\u{001f}")
            ),
            consent: Self.localConsent,
            provenance: Self.provenance(capture: "ambient_review"),
            parentEventID: nil,
            outcome: nil,
            confidence: nil,
            trainingEligible: nil
        )
        append(event)
    }

    func readiness() -> Readiness {
        lock.lock()
        defer { lock.unlock() }
        let events = allEventsUnlocked()
        let outcomes = events.filter { $0.eventType == "edit_outcome" }
        let eligible = outcomes.filter {
            StyleLearningPolicy.isDurableStyleEvidence(
                outcome: $0.outcome,
                finalText: $0.finalText,
                trainingEligible: $0.trainingEligible,
                confidence: $0.confidence
            )
        }
        let writingSamples = events.filter {
            $0.eventType == "document_snapshot"
                && $0.provenance.capture == "writing_sample_import"
                && $0.trainingEligible == true
        }
        let styleCount = styleDecisionsUnlocked(events: events).count
        let confirmedRewriteCount = styleDecisionsUnlocked(events: events).filter {
            StyleLearningPolicy.isConfirmedUserRewrite(
                outcome: $0.outcome,
                finalText: $0.finalText
            )
        }.count
        return Readiness(
            eventCount: events.count,
            resolvedEditCount: outcomes.count,
            eligibleExampleCount: eligible.count,
            styleDecisionCount: styleCount,
            confirmedRewriteCount: confirmedRewriteCount,
            bootstrapSampleCount: writingSamples.count
        )
    }

    func writingSamples(limit: Int = 20) -> [String] {
        guard limit > 0 else { return [] }
        lock.lock()
        defer { lock.unlock() }
        return allEventsUnlocked()
            .filter {
                $0.eventType == "document_snapshot"
                    && $0.provenance.capture == "writing_sample_import"
                    && $0.trainingEligible == true
            }
            .sorted { $0.recordedAt > $1.recordedAt }
            .prefix(limit)
            .compactMap { $0.finalText?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    func unprocessedStyleDecisions(limit: Int = 100) -> [DecisionSummary] {
        lock.lock()
        defer { lock.unlock() }
        let processed = processedIDsUnlocked()
        return styleDecisionsUnlocked(events: allEventsUnlocked())
            .filter { !processed.contains($0.id) }
            .suffix(limit)
    }

    func unprocessedWritingSamples(limit: Int = 5) -> [WritingSampleSummary] {
        guard limit > 0 else { return [] }
        lock.lock()
        defer { lock.unlock() }
        let processed = processedIDsUnlocked()
        return allEventsUnlocked()
            .filter {
                $0.eventType == "document_snapshot"
                    && $0.provenance.capture == "writing_sample_import"
                    && $0.trainingEligible == true
                    && !processed.contains($0.id)
            }
            .sorted { $0.recordedAt < $1.recordedAt }
            .prefix(limit)
            .compactMap { event in
                guard let text = event.finalText?.trimmingCharacters(in: .whitespacesAndNewlines),
                      !text.isEmpty
                else { return nil }
                return WritingSampleSummary(id: event.id, text: text, timestamp: event.recordedAt)
            }
    }

    /// Returns only prose the writer actively changed or rewrote after a model
    /// suggestion. Accepted-unchanged model text is intentionally excluded so
    /// the runtime context cannot become a self-reinforcing model feedback loop.
    func confirmedStyleExamples(limit: Int = 20) -> [String] {
        guard limit > 0 else { return [] }
        lock.lock()
        defer { lock.unlock() }

        let decisions = styleDecisionsUnlocked(events: allEventsUnlocked())
            .sorted { $0.timestamp > $1.timestamp }
        var seenGroups = Set<String>()
        var seenTexts = Set<String>()
        var examples: [String] = []
        for decision in decisions {
            guard StyleLearningPolicy.isConfirmedUserRewrite(
                outcome: decision.outcome,
                finalText: decision.finalText
            ),
                  let finalText = decision.finalText?.trimmingCharacters(
                    in: .whitespacesAndNewlines
                  )
            else { continue }
            let groupKey = decision.groupID.isEmpty ? decision.id : decision.groupID
            let textKey = Self.hash(finalText.lowercased())
            guard seenGroups.insert(groupKey).inserted,
                  seenTexts.insert(textKey).inserted
            else { continue }
            examples.append(finalText)
            if examples.count == limit { break }
        }
        return examples
    }

    func pendingProfileEvidenceCount() -> Int {
        unprocessedStyleDecisions(limit: .max).count
            + unprocessedWritingSamples(limit: .max).count
    }

    func recentRejectedDecisions(limit: Int = 10) -> [DecisionSummary] {
        lock.lock()
        defer { lock.unlock() }
        return allEventsUnlocked()
            .filter {
                $0.eventType == "edit_decision"
                    && ($0.decision == "reject" || $0.decision == "dismiss")
            }
            .suffix(limit)
            .map(Self.summary(from:))
    }

    func markProcessed(ids: [String]) throws {
        lock.lock()
        defer { lock.unlock() }
        try ensureStorageUnlocked()
        var processed = processedIDsUnlocked()
        ids.forEach { processed.insert($0) }
        let data = try encoder.encode(Array(processed).sorted())
        try data.write(to: processedIDsURL, options: .atomic)
        try Self.protectFile(at: processedIDsURL)
        try compactIfNeededUnlocked()
    }

    func learnedPreferences() -> String {
        AuthorStyleReference.learnedPreferences
    }

    func writeLearnedPreferences(_ content: String) throws {
        try AuthorStyleReference.writeLearnedPreferences(content)
    }

    func deleteAll() throws {
        lock.lock()
        defer { lock.unlock() }
        try ShakespeareStorage.resetPersonalization()
        AuthorStyleReference.reload()
        cachedEvents = []
        cachedEventIDs = []
        cachedEventLogSize = 0
        lastCompactionAttemptEventCount = 0
        UserDefaults.standard.removeObject(forKey: "personalizationSnapshotHashes")
    }

    private func styleDecisionsUnlocked(events: [Event]) -> [DecisionSummary] {
        let outcomes = events.reduce(into: [String: Event]()) { result, event in
            guard event.eventType == "edit_outcome", let parent = event.parentEventID else {
                return
            }
            if let existing = result[parent], existing.recordedAt > event.recordedAt {
                return
            }
            result[parent] = event
        }

        return events.compactMap { action in
            guard action.eventType == "edit_decision",
                  Self.styleKinds.contains(action.learningCategory.lowercased()),
                  !action.originalText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            else { return nil }

            guard let outcome = outcomes[action.id],
                  StyleLearningPolicy.isDurableStyleEvidence(
                    outcome: outcome.outcome,
                    finalText: outcome.finalText,
                    trainingEligible: outcome.trainingEligible,
                    confidence: outcome.confidence
                  )
            else { return nil }

            return DecisionSummary(
                id: action.id,
                decision: outcome.outcome == "rejected_rewritten" ? "reject" : "accept",
                source: action.source,
                kind: action.learningCategory.isEmpty ? action.operationKind : action.learningCategory,
                originalText: action.originalText,
                replacementText: action.proposedText,
                finalText: outcome.finalText,
                surroundingSentence: action.surroundingText,
                groupID: action.groupID,
                rationale: action.rationale,
                outcome: outcome.outcome,
                confidence: outcome.confidence,
                timestamp: outcome.recordedAt
            )
        }
    }

    private static func summary(from event: Event) -> DecisionSummary {
        DecisionSummary(
            id: event.id,
            decision: event.decision,
            source: event.source,
            kind: event.learningCategory.isEmpty ? event.operationKind : event.learningCategory,
            originalText: event.originalText,
            replacementText: event.proposedText,
            finalText: event.finalText,
            surroundingSentence: event.surroundingText,
            groupID: event.groupID,
            rationale: event.rationale,
            outcome: event.outcome,
            confidence: event.confidence,
            timestamp: event.recordedAt
        )
    }

    private func processedIDsUnlocked() -> Set<String> {
        guard let data = try? Data(contentsOf: processedIDsURL),
              let ids = try? decoder.decode([String].self, from: data)
        else { return [] }
        return Set(ids)
    }

    private func allEventsUnlocked() -> [Event] {
        let fileSize = ((try? FileManager.default.attributesOfItem(atPath: eventLogURL.path)[.size])
            as? NSNumber)?.uint64Value ?? 0
        if let cachedEvents, cachedEventLogSize == fileSize {
            if cachedEventIDs == nil { cachedEventIDs = Set(cachedEvents.map(\.id)) }
            return cachedEvents
        }
        guard let raw = try? String(contentsOf: eventLogURL, encoding: .utf8) else {
            cachedEvents = []
            cachedEventIDs = []
            cachedEventLogSize = 0
            return []
        }
        let events = raw.split(separator: "\n").compactMap { line in
            try? decoder.decode(Event.self, from: Data(line.utf8))
        }
        cachedEvents = events
        cachedEventIDs = Set(events.map(\.id))
        cachedEventLogSize = fileSize
        return events
    }

    private func append(_ event: Event) {
        lock.lock()
        defer { lock.unlock() }
        do {
            _ = allEventsUnlocked()
            guard cachedEventIDs?.contains(event.id) != true else { return }
            try appendUnlocked(event)
            try compactIfNeededUnlocked()
        } catch {
            print("TrainingEventStore: failed to append event: \(error)")
        }
    }

    private func appendUnlocked(_ event: Event) throws {
        try ensureStorageUnlocked()
        let data = try encoder.encode(event)
        var line = Data()
        line.append(data)
        line.append(0x0a)

        if FileManager.default.fileExists(atPath: eventLogURL.path) {
            let handle = try FileHandle(forWritingTo: eventLogURL)
            try handle.seekToEnd()
            try handle.write(contentsOf: line)
            try handle.close()
        } else {
            try line.write(to: eventLogURL, options: .atomic)
        }
        try Self.protectFile(at: eventLogURL)
        cachedEvents?.append(event)
        cachedEventIDs?.insert(event.id)
        cachedEventLogSize = ((try? FileManager.default.attributesOfItem(atPath: eventLogURL.path)[.size])
            as? NSNumber)?.uint64Value
    }

    private func compactIfNeededUnlocked() throws {
        let events = allEventsUnlocked()
        let fileSize = cachedEventLogSize ?? 0
        let exceedsLimit = events.count > PersonalizationLedgerRetentionPolicy.maximumEventCount
            || fileSize > PersonalizationLedgerRetentionPolicy.maximumEventLogBytes
        guard exceedsLimit else { return }
        guard lastCompactionAttemptEventCount == 0
                || events.count >= lastCompactionAttemptEventCount + 250
        else { return }
        let processed = processedIDsUnlocked()
        let records = events.map { event in
            let requiresProfileProcessing: Bool
            if event.eventType == "edit_outcome" {
                requiresProfileProcessing = StyleLearningPolicy.isDurableStyleEvidence(
                    outcome: event.outcome,
                    finalText: event.finalText,
                    trainingEligible: event.trainingEligible,
                    confidence: event.confidence
                )
            } else {
                // Legacy action-only records cannot prove the writer changed
                // model prose, so they remain history rather than profile evidence.
                requiresProfileProcessing = false
            }
            return PersonalizationLedgerRetentionRecord(
                id: event.id,
                parentEventID: event.parentEventID,
                eventType: event.eventType,
                recordedAt: event.recordedAt,
                requiresProfileProcessing: requiresProfileProcessing
            )
        }
        let retainedIndices = PersonalizationLedgerRetentionPolicy.retainedIndices(
            records: records,
            processedIDs: processed
        )
        let retainedEvents = retainedIndices.map { events[$0] }
        guard retainedEvents.count < events.count else {
            lastCompactionAttemptEventCount = events.count
            return
        }

        var compactedData = Data()
        for event in retainedEvents {
            compactedData.append(try encoder.encode(event))
            compactedData.append(0x0a)
        }
        try compactedData.write(to: eventLogURL, options: .atomic)
        try Self.protectFile(at: eventLogURL)

        let retainedEventIDs = Set(retainedEvents.map(\.id))
        let retainedProcessedIDs = processed.intersection(retainedEventIDs)
        if retainedProcessedIDs != processed {
            let processedData = try encoder.encode(Array(retainedProcessedIDs).sorted())
            try processedData.write(to: processedIDsURL, options: .atomic)
            try Self.protectFile(at: processedIDsURL)
        }

        cachedEvents = retainedEvents
        cachedEventIDs = retainedEventIDs
        cachedEventLogSize = UInt64(compactedData.count)
        lastCompactionAttemptEventCount = events.count
    }

    private func ensureStorageUnlocked() throws {
        try FileManager.default.createDirectory(
            at: ShakespeareStorage.personalizationDirectoryURL,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o700],
            ofItemAtPath: ShakespeareStorage.personalizationDirectoryURL.path
        )
        try FileManager.default.createDirectory(
            at: AuthorStyleReference.styleDirectoryURL,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
    }

    private static var nowMilliseconds: Double {
        Date().timeIntervalSince1970 * 1_000
    }

    private static var localConsent: Consent {
        Consent(collectionEnabled: true, scope: "local_personalization")
    }

    private static func protectFile(at url: URL) throws {
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: url.path
        )
    }

    private static func hash(_ text: String) -> String {
        SHA256.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    private static func bootstrapExampleEstimate(for text: String) -> Int {
        let paragraphs = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .components(separatedBy: "\n\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { paragraph in
                let words = paragraph.split(whereSeparator: \.isWhitespace).count
                return words >= 20 && paragraph.count <= 4_000
            }
        return min(max(paragraphs.count - 1, 0), 8)
    }

    private static func provenance(capture: String) -> Provenance {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
            ?? "development"
        return Provenance(
            application: "Shakespeare",
            applicationVersion: version,
            capture: capture
        )
    }
}
