import Foundation

private final class AvailabilityStubURLProtocol: URLProtocol {
    private static let lock = NSLock()
    private static var handler: ((URLRequest) throws -> (Int, Data))?
    private static var requestCount = 0

    static func configure(handler: @escaping (URLRequest) throws -> (Int, Data)) {
        synchronized {
            Self.handler = handler
            requestCount = 0
        }
    }

    static func currentRequestCount() -> Int {
        synchronized { requestCount }
    }

    private static func nextHandler() -> ((URLRequest) throws -> (Int, Data))? {
        synchronized {
            requestCount += 1
            return handler
        }
    }

    private static func synchronized<Value>(_ body: () -> Value) -> Value {
        lock.lock()
        defer { lock.unlock() }
        return body()
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        do {
            guard let handler = Self.nextHandler() else { throw URLError(.badServerResponse) }
            let (status, data) = try handler(request)
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: status,
                httpVersion: nil,
                headerFields: ["content-type": "application/json"]
            )!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

@main
private struct ModelAvailabilityEvals {
    static func main() async {
        await mapsProviderAndAliasStates()
        await mapsMissingAndNetworkStates()
        await cachesAndForceRefreshes()
        print("Model availability evals passed (3 cases).")
    }

    private static func makeService(
        cacheLifetime: TimeInterval = 300,
        handler: @escaping (URLRequest) throws -> (Int, Data)
    ) -> OpenRouterModelAvailabilityService {
        AvailabilityStubURLProtocol.configure(handler: handler)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [AvailabilityStubURLProtocol.self]
        return OpenRouterModelAvailabilityService(
            session: URLSession(configuration: configuration),
            cacheLifetime: cacheLifetime
        )
    }

    private static func mapsProviderAndAliasStates() async {
        let service = makeService { request in
            precondition(request.httpMethod == "GET")
            precondition(request.value(forHTTPHeaderField: "authorization") == nil)
            let path = request.url?.path ?? ""
            if path.contains("/online/") {
                return (200, Data(#"{"data":{"endpoints":[{"status":-5},{"status":0}]}}"#.utf8))
            }
            if path.contains("/offline/") {
                return (200, Data(#"{"data":{"endpoints":[{"status":-5}]}}"#.utf8))
            }
            return (200, Data(#"{"data":{"endpoints":[]}}"#.utf8))
        }

        let statuses = await service.statuses(for: ["test/online", "test/offline", "test/alias"])
        precondition(statuses["test/online"] == .online)
        precondition(statuses["test/offline"] == .offline)
        precondition(statuses["test/alias"] == .available)
    }

    private static func mapsMissingAndNetworkStates() async {
        let service = makeService { request in
            if request.url?.path.contains("/missing/") == true { return (404, Data()) }
            throw URLError(.notConnectedToInternet)
        }

        let statuses = await service.statuses(for: ["test/missing", "test/network"])
        precondition(statuses["test/missing"] == .offline)
        precondition(statuses["test/network"] == .unknown)
    }

    private static func cachesAndForceRefreshes() async {
        let service = makeService { _ in
            (200, Data(#"{"data":{"endpoints":[{"status":0}]}}"#.utf8))
        }

        _ = await service.statuses(for: ["test/model"])
        _ = await service.statuses(for: ["test/model"])
        precondition(AvailabilityStubURLProtocol.currentRequestCount() == 1)

        _ = await service.statuses(for: ["test/model"], forceRefresh: true)
        precondition(AvailabilityStubURLProtocol.currentRequestCount() == 2)
    }
}
