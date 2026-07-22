import Foundation

actor OpenRouterModelAvailabilityService {
    enum ModelStatus: Sendable, Equatable {
        case online
        case available
        case offline
        case unknown
    }

    static let shared = OpenRouterModelAvailabilityService()

    private let session: URLSession
    private let cacheLifetime: TimeInterval
    private var cachedStatuses: [String: ModelStatus] = [:]
    private var cachedAt: Date?

    init(session: URLSession? = nil, cacheLifetime: TimeInterval = 300) {
        if let session {
            self.session = session
        } else {
            let configuration = URLSessionConfiguration.ephemeral
            configuration.waitsForConnectivity = false
            configuration.timeoutIntervalForRequest = 8
            configuration.timeoutIntervalForResource = 12
            self.session = URLSession(configuration: configuration)
        }
        self.cacheLifetime = cacheLifetime
    }

    func statuses(
        for modelIDs: [String],
        forceRefresh: Bool = false
    ) async -> [String: ModelStatus] {
        let uniqueModelIDs = Array(Set(modelIDs)).sorted()
        let cacheIsFresh = cachedAt.map { Date().timeIntervalSince($0) < cacheLifetime } ?? false
        if !forceRefresh,
           cacheIsFresh,
           uniqueModelIDs.allSatisfy({ cachedStatuses[$0] != nil }) {
            return Dictionary(uniqueKeysWithValues: uniqueModelIDs.compactMap { modelID in
                cachedStatuses[modelID].map { (modelID, $0) }
            })
        }

        let session = self.session
        let refreshed = await withTaskGroup(
            of: (String, ModelStatus).self,
            returning: [String: ModelStatus].self
        ) { group in
            for modelID in uniqueModelIDs {
                group.addTask {
                    (modelID, await Self.fetchStatus(for: modelID, session: session))
                }
            }

            var statuses: [String: ModelStatus] = [:]
            for await (modelID, status) in group {
                statuses[modelID] = status
            }
            return statuses
        }

        cachedStatuses.merge(refreshed) { _, new in new }
        cachedAt = Date()
        return refreshed
    }

    private static func fetchStatus(
        for modelID: String,
        session: URLSession
    ) async -> ModelStatus {
        guard let url = URL(
            string: "https://openrouter.ai/api/v1/models/\(modelID)/endpoints"
        ) else { return .unknown }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 8

        do {
            let (data, response) = try await session.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else { return .unknown }
            if httpResponse.statusCode == 404 { return .offline }
            guard (200..<300).contains(httpResponse.statusCode),
                  let payload = try? JSONDecoder().decode(EndpointsResponse.self, from: data)
            else { return .unknown }

            if payload.data.endpoints.contains(where: { $0.status == 0 }) { return .online }
            if payload.data.endpoints.contains(where: { $0.status != nil }) { return .offline }

            // Routed aliases are valid models even when OpenRouter does not
            // expose the selected provider's live endpoint telemetry.
            return .available
        } catch is CancellationError {
            return .unknown
        } catch {
            return .unknown
        }
    }

    private struct EndpointsResponse: Decodable {
        let data: ModelData
    }

    private struct ModelData: Decodable {
        let endpoints: [Endpoint]
    }

    private struct Endpoint: Decodable {
        let status: Int?
    }
}
