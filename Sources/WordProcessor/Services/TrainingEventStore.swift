import CryptoKit
import Foundation

enum PersonalizationSettings {
    static let enabledDefaultsKey = "personalizationCollectionEnabled"
    private static let writerIDDefaultsKey = "personalizationWriterID"

    static var isEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: enabledDefaultsKey) }
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

    struct Readiness: Equatable, Sendable {
        let eventCount: Int
        let resolvedEditCount: Int
        let eligibleExampleCount: Int
        let styleDecisionCount: Int
        let snapshotDocumentCount: Int

        var progress: Double {
            let exampleProgress = min(Double(eligibleExampleCount) / 50, 1)
            let documentProgress = min(Double(snapshotDocumentCount) / 3, 1)
            return exampleProgress * 0.8 + documentProgress * 0.2
        }

        var isTrainingReady: Bool {
            eligibleExampleCount >= 50 && snapshotDocumentCount >= 3
        }

        var status: String {
            if !PersonalizationSettings.isEnabled {
                return "Learning is paused"
            }
            if isTrainingReady {
                return "Ready for an evaluated training run"
            }
            if eligibleExampleCount >= 15 {
                return "Building a reliable style sample"
            }
            return "Learning from saved edit outcomes"
        }
    }

    private static let snapshotHashesDefaultsKey = "personalizationSnapshotHashes"
    private static let styleKinds: Set<String> = [
        "voice", "tone", "clarity", "structure", "concision", "style",
    ]
    private let encoder: JSONEncoder
    private let decoder = JSONDecoder()
    private let lock = NSLock()
    private var cachedEvents: [Event]?
    private var cachedEventLogSize: UInt64?

    var eventLogURL: URL {
        PersonalizationStorage.directoryURL.appendingPathComponent("training_events.jsonl")
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
        return acknowledged
    }

    func appendDocumentSnapshot(_ snapshot: DocumentFileStore.FileSnapshot) {
        guard PersonalizationSettings.isEnabled,
              !snapshot.documentID.isEmpty,
              !snapshot.plainText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else { return }

        let contentHash = Self.hash(snapshot.plainText)
        lock.lock()
        defer { lock.unlock() }

        var hashes = UserDefaults.standard.dictionary(
            forKey: Self.snapshotHashesDefaultsKey
        ) as? [String: String] ?? [:]
        guard hashes[snapshot.documentID] != contentHash else { return }

        let runtime = InferenceSettings.runtime(
            purpose: .assistant,
            modelOverride: nil,
            effortOverride: "low"
        )
        let event = Event(
            schemaVersion: Self.currentSchemaVersion,
            id: UUID().uuidString,
            eventType: "document_snapshot",
            recordedAt: Self.nowMilliseconds,
            writerID: PersonalizationSettings.writerID,
            documentID: snapshot.documentID,
            provider: runtime.providerID.rawValue,
            model: runtime.model,
            source: "writer",
            operationKind: "save",
            learningCategory: "continuation",
            decision: "final",
            instruction: "Continue in the writer's own voice.",
            originalText: "",
            proposedText: "",
            finalText: snapshot.plainText,
            surroundingText: "",
            rationale: "",
            groupID: "",
            contentHash: contentHash,
            consent: Self.localConsent,
            provenance: Self.provenance(capture: "document_save"),
            parentEventID: nil,
            outcome: "saved_document",
            confidence: 1,
            trainingEligible: true
        )

        do {
            try appendUnlocked(event)
            hashes[snapshot.documentID] = contentHash
            UserDefaults.standard.set(hashes, forKey: Self.snapshotHashesDefaultsKey)
        } catch {
            print("TrainingEventStore: failed to append snapshot: \(error)")
        }
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
        let eligible = outcomes.filter { $0.trainingEligible == true && ($0.confidence ?? 0) >= 0.8 }
        let legacyEligible = events.filter {
            $0.schemaVersion == 1 && $0.eventType == "edit_decision"
                && $0.decision == "accept" && $0.finalText != nil
        }
        let styleCount = styleDecisionsUnlocked(events: events).count
        return Readiness(
            eventCount: events.count,
            resolvedEditCount: outcomes.count,
            eligibleExampleCount: eligible.count + legacyEligible.count,
            styleDecisionCount: styleCount,
            snapshotDocumentCount: Set(
                events.filter { $0.eventType == "document_snapshot" }.map(\.documentID)
            ).count
        )
    }

    func unprocessedStyleDecisions(limit: Int = 100) -> [DecisionSummary] {
        lock.lock()
        defer { lock.unlock() }
        let processed = processedIDsUnlocked()
        return styleDecisionsUnlocked(events: allEventsUnlocked())
            .filter { !processed.contains($0.id) }
            .suffix(limit)
    }

    func pendingDecisionCount() -> Int {
        unprocessedStyleDecisions(limit: .max).count
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
        if FileManager.default.fileExists(atPath: eventLogURL.path) {
            try FileManager.default.removeItem(at: eventLogURL)
        }
        if FileManager.default.fileExists(atPath: processedIDsURL.path) {
            try FileManager.default.removeItem(at: processedIDsURL)
        }
        if FileManager.default.fileExists(atPath: legacyFeedbackLogURL.path) {
            try FileManager.default.removeItem(at: legacyFeedbackLogURL)
        }
        cachedEvents = []
        cachedEventLogSize = 0
        UserDefaults.standard.removeObject(forKey: Self.snapshotHashesDefaultsKey)
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

            if action.schemaVersion == 1, action.decision == "accept", action.finalText != nil {
                return Self.summary(from: action)
            }
            guard let outcome = outcomes[action.id],
                  outcome.trainingEligible == true,
                  (outcome.confidence ?? 0) >= 0.8,
                  ["accepted_unchanged", "accepted_modified", "later_accepted", "rejected_rewritten"]
                    .contains(outcome.outcome ?? "")
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
            return cachedEvents
        }
        guard let raw = try? String(contentsOf: eventLogURL, encoding: .utf8) else {
            cachedEvents = []
            cachedEventLogSize = 0
            return []
        }
        let events = raw.split(separator: "\n").compactMap { line in
            try? decoder.decode(Event.self, from: Data(line.utf8))
        }
        cachedEvents = events
        cachedEventLogSize = fileSize
        return events
    }

    private func append(_ event: Event) {
        lock.lock()
        defer { lock.unlock() }
        do {
            let existingIDs = Set(allEventsUnlocked().map(\.id))
            guard !existingIDs.contains(event.id) else { return }
            try appendUnlocked(event)
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
        cachedEventLogSize = ((try? FileManager.default.attributesOfItem(atPath: eventLogURL.path)[.size])
            as? NSNumber)?.uint64Value
    }

    private func ensureStorageUnlocked() throws {
        try FileManager.default.createDirectory(
            at: PersonalizationStorage.directoryURL,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o700],
            ofItemAtPath: PersonalizationStorage.directoryURL.path
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
