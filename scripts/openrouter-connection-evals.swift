import Foundation

private final class StubURLProtocol: URLProtocol {
    static var handler: ((URLRequest) throws -> (Int, Data))?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        do {
            guard let handler = Self.handler else {
                throw NSError(domain: "StubURLProtocol", code: 1)
            }
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
private struct OpenRouterConnectionEvals {
    static func main() async {
        validatesAllRuntimePurposes()
        await validatesExpectedRequest()
        await mapsUnauthorizedResponse()
        await mapsBillingRequiredResponse()
        await mapsExhaustedKeyResponse()
        await mapsTemporaryFailure()
        await rejectsMalformedSuccess()
        print("OpenRouter connection evals passed (7 cases).")
    }

    private static func validatesAllRuntimePurposes() {
        for purpose in [InferencePurpose.assistant, .grammar, .proofread, .chat] {
            let runtime = InferenceSettings.runtime(purpose: purpose)
            precondition(runtime.providerID == .openRouter)
            precondition(runtime.apiKeyService == "openrouter")
            precondition(runtime.messagesURL.absoluteString == "https://openrouter.ai/api/v1/chat/completions")
            precondition(runtime.model == (purpose == .chat
                ? InferenceSettings.defaultResearchModel
                : InferenceSettings.defaultWritingModel))
            precondition(runtime.webSearchEnabled == (purpose == .chat))
            precondition(runtime.supportsTemperature == (purpose == .chat))
        }
    }

    private static func makeValidator(
        handler: @escaping (URLRequest) throws -> (Int, Data)
    ) -> OpenRouterConnectionValidator {
        StubURLProtocol.handler = handler
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        return OpenRouterConnectionValidator(session: URLSession(configuration: configuration))
    }

    private static func validatesExpectedRequest() async {
        let validator = makeValidator { request in
            precondition(request.url?.path == "/api/v1/key")
            precondition(request.httpMethod == "GET")
            precondition(request.value(forHTTPHeaderField: "authorization") == "Bearer test-key")
            return (200, Data(#"{"data":{"label":"Shakespeare","is_free_tier":false}}"#.utf8))
        }

        do {
            try await validator.validate(apiKey: " test-key ")
        } catch {
            preconditionFailure("Expected valid connection, got \(error)")
        }
    }

    private static func mapsUnauthorizedResponse() async {
        let validator = makeValidator { _ in
            (401, Data(#"{"error":{"message":"bad key"}}"#.utf8))
        }

        do {
            try await validator.validate(apiKey: "bad-key")
            preconditionFailure("Expected unauthorized error")
        } catch let error as OpenRouterConnectionValidator.ValidationError {
            precondition(error == .unauthorized)
        } catch {
            preconditionFailure("Unexpected error: \(error)")
        }
    }

    private static func mapsBillingRequiredResponse() async {
        let validator = makeValidator { _ in (402, Data()) }

        do {
            try await validator.validate(apiKey: "test-key")
            preconditionFailure("Expected billing-required error")
        } catch let error as OpenRouterConnectionValidator.ValidationError {
            precondition(error == .billingRequired)
        } catch {
            preconditionFailure("Unexpected error: \(error)")
        }
    }

    private static func mapsExhaustedKeyResponse() async {
        let validator = makeValidator { _ in
            (200, Data(#"{"data":{"label":"Shakespeare","limit_remaining":0}}"#.utf8))
        }

        do {
            try await validator.validate(apiKey: "test-key")
            preconditionFailure("Expected billing-required error for exhausted key")
        } catch let error as OpenRouterConnectionValidator.ValidationError {
            precondition(error == .billingRequired)
        } catch {
            preconditionFailure("Unexpected error: \(error)")
        }
    }

    private static func mapsTemporaryFailure() async {
        let validator = makeValidator { _ in (503, Data()) }

        do {
            try await validator.validate(apiKey: "test-key")
            preconditionFailure("Expected unavailable error")
        } catch let error as OpenRouterConnectionValidator.ValidationError {
            precondition(error == .unavailable)
        } catch {
            preconditionFailure("Unexpected error: \(error)")
        }
    }

    private static func rejectsMalformedSuccess() async {
        let validator = makeValidator { _ in (200, Data(#"{"ok":true}"#.utf8)) }

        do {
            try await validator.validate(apiKey: "test-key")
            preconditionFailure("Expected invalid response error")
        } catch let error as OpenRouterConnectionValidator.ValidationError {
            precondition(error == .invalidResponse)
        } catch {
            preconditionFailure("Unexpected error: \(error)")
        }
    }
}
