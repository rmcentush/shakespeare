import Foundation

struct PersonalizationLedgerRetentionRecord: Equatable, Sendable {
    let id: String
    let parentEventID: String?
    let eventType: String
    let recordedAt: Double
    let requiresProfileProcessing: Bool
}

enum PersonalizationLedgerRetentionPolicy {
    static let maximumEventCount = 4_000
    static let maximumEventLogBytes: UInt64 = 20 * 1024 * 1024
    static let recentDecisionLimit = 1_500

    private struct ActionReference {
        let id: String
        let index: Int
        let recordedAt: Double
    }

    /// Imported samples are user-managed source material and remain until the
    /// writer deletes learning history. Resolved edit telemetry is compacted to
    /// a recent window, while unreviewed profile evidence is always retained.
    static func retainedIndices(
        records: [PersonalizationLedgerRetentionRecord],
        processedIDs: Set<String>,
        recentDecisionLimit: Int = recentDecisionLimit
    ) -> IndexSet {
        var retained = IndexSet()
        var actionIndexByID: [String: Int] = [:]
        var outcomeIndicesByParent: [String: [Int]] = [:]

        for (index, record) in records.enumerated() {
            switch record.eventType {
            case "document_snapshot":
                retained.insert(index)
            case "edit_decision":
                actionIndexByID[record.id] = index
            case "edit_outcome":
                if let parent = record.parentEventID {
                    outcomeIndicesByParent[parent, default: []].append(index)
                }
            default:
                // Unknown future records are safer to preserve than silently discard.
                retained.insert(index)
            }
        }

        var actionReferences: [ActionReference] = []
        for (id, index) in actionIndexByID {
            actionReferences.append(ActionReference(
                id: id,
                index: index,
                recordedAt: records[index].recordedAt
            ))
        }
        actionReferences.sort { left, right in
            left.recordedAt == right.recordedAt
                ? left.index > right.index
                : left.recordedAt > right.recordedAt
        }
        let recentActionIDs = actionReferences
            .prefix(max(0, recentDecisionLimit))
            .map(\.id)

        var retainedActionIDs = Set(recentActionIDs)
        for (index, outcome) in records.enumerated()
        where outcome.eventType == "edit_outcome" && outcome.requiresProfileProcessing {
            guard let parent = outcome.parentEventID, !processedIDs.contains(parent) else { continue }
            retained.insert(index)
            retainedActionIDs.insert(parent)
        }
        for (id, index) in actionIndexByID
        where records[index].requiresProfileProcessing && !processedIDs.contains(id) {
            retainedActionIDs.insert(id)
        }

        for actionID in retainedActionIDs {
            if let actionIndex = actionIndexByID[actionID] {
                retained.insert(actionIndex)
            }
            for outcomeIndex in outcomeIndicesByParent[actionID] ?? [] {
                retained.insert(outcomeIndex)
            }
        }
        return retained
    }
}
