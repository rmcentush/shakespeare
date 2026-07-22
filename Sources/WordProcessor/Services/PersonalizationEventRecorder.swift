import Foundation

/// Serializes ledger mutations away from the main actor. Ordering matters: a
/// save-time outcome must never overtake the edit decision it resolves.
final class PersonalizationEventRecorder: @unchecked Sendable {
    static let shared = PersonalizationEventRecorder()

    private let queue = DispatchQueue(
        label: "com.shakespeare.personalization-ledger",
        qos: .utility
    )
    private let store: TrainingEventStore

    init(store: TrainingEventStore = .shared) {
        self.store = store
    }

    func appendEditDecision(
        _ decision: BridgePayload.EditDecisionData,
        documentID: String,
        sessionID: String,
        runtime: InferenceRuntime
    ) {
        queue.async { [store] in
            store.appendEditDecision(
                decision,
                documentID: documentID,
                sessionID: sessionID,
                runtime: runtime
            )
        }
    }

    func appendCommentDecision(
        decision: String,
        comment: BridgePayload.CommentData,
        documentID: String,
        sessionID: String,
        runtime: InferenceRuntime
    ) {
        queue.async { [store] in
            store.appendCommentDecision(
                decision: decision,
                comment: comment,
                documentID: documentID,
                sessionID: sessionID,
                runtime: runtime
            )
        }
    }

    func appendOutcomes(
        _ outcomes: [PersonalizationOutcomeSnapshot],
        documentID: String,
        runtime: InferenceRuntime
    ) async -> [String] {
        await withCheckedContinuation { continuation in
            queue.async { [store] in
                continuation.resume(returning: store.appendOutcomes(
                    outcomes,
                    documentID: documentID,
                    runtime: runtime
                ))
            }
        }
    }

    func deleteAll() async throws {
        try await withCheckedThrowingContinuation { continuation in
            queue.async { [store] in
                do {
                    try store.deleteAll()
                    continuation.resume()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
}
