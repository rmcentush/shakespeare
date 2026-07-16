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

private func requestBodyData(_ request: URLRequest) -> Data {
    if let body = request.httpBody { return body }
    guard let stream = request.httpBodyStream else { return Data() }

    stream.open()
    defer { stream.close() }

    var data = Data()
    var buffer = [UInt8](repeating: 0, count: 1_024)
    while stream.hasBytesAvailable {
        let count = stream.read(&buffer, maxLength: buffer.count)
        guard count > 0 else { break }
        data.append(buffer, count: count)
    }
    return data
}

@main
private struct TinkerConnectionEvals {
    static func main() async {
        await validatesExpectedRequest()
        await mapsUnauthorizedResponse()
        await mapsBillingRequiredResponse()
        await mapsTemporaryFailure()
        await rejectsMalformedSuccess()
        print("Tinker connection evals passed (5 cases).")
    }

    private static func makeValidator(
        handler: @escaping (URLRequest) throws -> (Int, Data)
    ) -> TinkerConnectionValidator {
        StubURLProtocol.handler = handler
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        return TinkerConnectionValidator(session: URLSession(configuration: configuration))
    }

    private static func validatesExpectedRequest() async {
        let validator = makeValidator { request in
            precondition(request.url?.path.hasSuffix("/v1/messages/count_tokens") == true)
            precondition(request.httpMethod == "POST")
            precondition(request.value(forHTTPHeaderField: "x-api-key") == "test-key")
            precondition(request.value(forHTTPHeaderField: "anthropic-version") == "2023-06-01")

            let body = try JSONSerialization.jsonObject(with: requestBodyData(request)) as! [String: Any]
            precondition(body["model"] as? String == InferenceSettings.defaultTinkerModel)
            return (200, Data(#"{"input_tokens":3}"#.utf8))
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
        } catch let error as TinkerConnectionValidator.ValidationError {
            precondition(error == .unauthorized)
        } catch {
            preconditionFailure("Unexpected error: \(error)")
        }
    }

    private static func mapsTemporaryFailure() async {
        let validator = makeValidator { _ in
            (503, Data())
        }

        do {
            try await validator.validate(apiKey: "test-key")
            preconditionFailure("Expected unavailable error")
        } catch let error as TinkerConnectionValidator.ValidationError {
            precondition(error == .unavailable)
        } catch {
            preconditionFailure("Unexpected error: \(error)")
        }
    }

    private static func mapsBillingRequiredResponse() async {
        let validator = makeValidator { _ in
            (402, Data(#"{"detail":"Access is blocked due to billing status."}"#.utf8))
        }

        do {
            try await validator.validate(apiKey: "test-key")
            preconditionFailure("Expected billing-required error")
        } catch let error as TinkerConnectionValidator.ValidationError {
            precondition(error == .billingRequired)
        } catch {
            preconditionFailure("Unexpected error: \(error)")
        }
    }

    private static func rejectsMalformedSuccess() async {
        let validator = makeValidator { _ in
            (200, Data(#"{"ok":true}"#.utf8))
        }

        do {
            try await validator.validate(apiKey: "test-key")
            preconditionFailure("Expected invalid response error")
        } catch let error as TinkerConnectionValidator.ValidationError {
            precondition(error == .invalidResponse)
        } catch {
            preconditionFailure("Unexpected error: \(error)")
        }
    }
}
