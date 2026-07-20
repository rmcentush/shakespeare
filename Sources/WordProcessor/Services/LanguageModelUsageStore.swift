import Foundation

/// Stores aggregate, content-free model diagnostics locally. No prompt,
/// response, document identifier, API key, or provider error body is retained.
final class LanguageModelUsageStore: @unchecked Sendable {
    static let shared = LanguageModelUsageStore()
    static let defaultsKey = "languageModelUsageSnapshot"

    struct Snapshot: Codable, Equatable, Sendable {
        var requestCount: Int
        var promptTokens: Int
        var completionTokens: Int
        var cachedTokens: Int
        var cacheWriteTokens: Int
        var cost: Double
        var lastSelectedModel: String
        var lastActualModel: String
        var lastPurpose: String
        var lastLatencyMilliseconds: Int
        var lastUpdatedAt: Date?

        static let empty = Snapshot(
            requestCount: 0,
            promptTokens: 0,
            completionTokens: 0,
            cachedTokens: 0,
            cacheWriteTokens: 0,
            cost: 0,
            lastSelectedModel: "",
            lastActualModel: "",
            lastPurpose: "",
            lastLatencyMilliseconds: 0,
            lastUpdatedAt: nil
        )
    }

    private let lock = NSLock()
    private let defaults: UserDefaults
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func snapshot() -> Snapshot {
        lock.lock()
        defer { lock.unlock() }
        return snapshotUnlocked()
    }

    func record(
        purpose: InferencePurpose,
        selectedModel: String,
        routedModel: String,
        usage: LanguageModelService.PromptCacheUsage?,
        latencyMilliseconds: Int
    ) {
        lock.lock()
        var value = snapshotUnlocked()
        Self.saturatingAdd(1, to: &value.requestCount)
        Self.saturatingAdd(max(usage?.promptTokens ?? 0, 0), to: &value.promptTokens)
        Self.saturatingAdd(max(usage?.completionTokens ?? 0, 0), to: &value.completionTokens)
        Self.saturatingAdd(max(usage?.cachedTokens ?? 0, 0), to: &value.cachedTokens)
        Self.saturatingAdd(max(usage?.cacheWriteTokens ?? 0, 0), to: &value.cacheWriteTokens)
        let reportedCost = usage?.cost ?? 0
        let safeCost = reportedCost.isFinite ? max(reportedCost, 0) : 0
        let updatedCost = value.cost + safeCost
        value.cost = updatedCost.isFinite ? updatedCost : value.cost
        value.lastSelectedModel = String(selectedModel.prefix(256))
        value.lastActualModel = String((usage?.actualModel ?? routedModel).prefix(256))
        value.lastPurpose = purpose.rawValue
        value.lastLatencyMilliseconds = max(latencyMilliseconds, 0)
        value.lastUpdatedAt = Date()
        if let data = try? encoder.encode(value) {
            defaults.set(data, forKey: Self.defaultsKey)
        }
        lock.unlock()
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: .languageModelUsageChanged, object: nil)
        }
    }

    func reset() {
        lock.lock()
        defaults.removeObject(forKey: Self.defaultsKey)
        lock.unlock()
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: .languageModelUsageChanged, object: nil)
        }
    }

    private func snapshotUnlocked() -> Snapshot {
        guard let data = defaults.data(forKey: Self.defaultsKey),
              let value = try? decoder.decode(Snapshot.self, from: data)
        else { return .empty }
        return value
    }

    private static func saturatingAdd(_ increment: Int, to value: inout Int) {
        let (result, overflowed) = value.addingReportingOverflow(increment)
        value = overflowed ? Int.max : result
    }
}

extension Notification.Name {
    static let languageModelUsageChanged = Notification.Name("languageModelUsageChanged")
}
