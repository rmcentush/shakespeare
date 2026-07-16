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

final class TrainingEventStore: @unchecked Sendable {
    static let shared = TrainingEventStore()
    static let currentSchemaVersion = 1

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
    }

    private static let snapshotHashesDefaultsKey = "personalizationSnapshotHashes"
    private let encoder: JSONEncoder
    private let lock = NSLock()

    var eventLogURL: URL {
        PersonalizationStorage.directoryURL.appendingPathComponent("training_events.jsonl")
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
        let finalText = decision.decision == "accept" ? decision.replacementText : nil
        let event = Event(
            schemaVersion: Self.currentSchemaVersion,
            id: decision.eventID.isEmpty ? UUID().uuidString : decision.eventID,
            eventType: "edit_decision",
            recordedAt: decision.timestamp > 0 ? decision.timestamp : Date().timeIntervalSince1970 * 1_000,
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
            finalText: finalText,
            surroundingText: decision.surroundingSentence,
            rationale: decision.rationale,
            groupID: decision.groupID,
            contentHash: Self.hash(
                [decision.originalText, decision.replacementText, decision.surroundingSentence]
                    .joined(separator: "\u{001f}")
            ),
            consent: Consent(collectionEnabled: true, scope: "local_personalization"),
            provenance: Self.provenance(capture: "editor_review")
        )
        append(event)
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
            recordedAt: Date().timeIntervalSince1970 * 1_000,
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
            consent: Consent(collectionEnabled: true, scope: "local_personalization"),
            provenance: Self.provenance(capture: "document_save")
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
        let timestamp = Date().timeIntervalSince1970 * 1_000
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
            finalText: decision == "accept" ? proposed : nil,
            surroundingText: comment.selectedText,
            rationale: comment.text,
            groupID: comment.agentRunID.isEmpty ? comment.id : comment.agentRunID,
            contentHash: Self.hash(
                [comment.selectedText, proposed, comment.text].joined(separator: "\u{001f}")
            ),
            consent: Consent(collectionEnabled: true, scope: "local_personalization"),
            provenance: Self.provenance(capture: "ambient_review")
        )
        append(event)
    }

    func eventCount() -> Int {
        lock.lock()
        defer { lock.unlock() }
        guard let contents = try? String(contentsOf: eventLogURL, encoding: .utf8) else { return 0 }
        return contents.split(separator: "\n").count
    }

    func deleteAll() throws {
        lock.lock()
        defer { lock.unlock() }
        if FileManager.default.fileExists(atPath: eventLogURL.path) {
            try FileManager.default.removeItem(at: eventLogURL)
        }
        UserDefaults.standard.removeObject(forKey: Self.snapshotHashesDefaultsKey)
    }

    private func append(_ event: Event) {
        lock.lock()
        defer { lock.unlock() }
        do {
            try appendUnlocked(event)
        } catch {
            print("TrainingEventStore: failed to append event: \(error)")
        }
    }

    private func appendUnlocked(_ event: Event) throws {
        try ensureStorage()
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
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: eventLogURL.path
        )
    }

    private func ensureStorage() throws {
        try FileManager.default.createDirectory(
            at: PersonalizationStorage.directoryURL,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o700],
            ofItemAtPath: PersonalizationStorage.directoryURL.path
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
