import Foundation

@main
struct LedgerRetentionEvals {
    static func main() {
        var records: [PersonalizationLedgerRetentionRecord] = []
        for index in 0..<5 {
            records.append(record(id: "action-\(index)", type: "edit_decision", time: Double(index)))
            records.append(record(
                id: "outcome-\(index)",
                parent: "action-\(index)",
                type: "edit_outcome",
                time: Double(index) + 0.5,
                requiresProcessing: true
            ))
        }
        records.append(record(id: "sample", type: "document_snapshot", time: 10))
        records.append(record(id: "future", type: "future_event", time: 11))

        let retained = PersonalizationLedgerRetentionPolicy.retainedIndices(
            records: records,
            processedIDs: ["action-0", "action-2", "action-3"],
            recentDecisionLimit: 2
        )
        let retainedIDs = Set(retained.map { records[$0].id })

        require(!retainedIDs.contains("action-0"), "old processed action was retained")
        require(!retainedIDs.contains("outcome-2"), "old processed outcome was retained")
        require(retainedIDs.contains("action-1"), "unreviewed durable action was discarded")
        require(retainedIDs.contains("outcome-1"), "unreviewed durable outcome was discarded")
        require(retainedIDs.contains("action-3"), "recent processed action was discarded")
        require(retainedIDs.contains("action-4"), "newest action was discarded")
        require(retainedIDs.contains("sample"), "imported writing sample was discarded")
        require(retainedIDs.contains("future"), "unknown future record was discarded")

        print("Ledger retention evals passed (recent history, unreviewed evidence, samples, forward safety).")
    }

    private static func record(
        id: String,
        parent: String? = nil,
        type: String,
        time: Double,
        requiresProcessing: Bool = false
    ) -> PersonalizationLedgerRetentionRecord {
        PersonalizationLedgerRetentionRecord(
            id: id,
            parentEventID: parent,
            eventType: type,
            recordedAt: time,
            requiresProfileProcessing: requiresProcessing
        )
    }

    private static func require(_ condition: @autoclosure () -> Bool, _ message: String) {
        guard condition() else { fatalError("Ledger retention eval failed: \(message)") }
    }
}
