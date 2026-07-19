import Foundation

struct OpenRouterConnectionValidator: Sendable {
    enum ValidationError: LocalizedError, Equatable {
        case emptyKey
        case invalidResponse
        case unauthorized
        case billingRequired
        case unavailable
        case rejected(String)

        var errorDescription: String? {
            switch self {
            case .emptyKey:
                return "Paste an OpenRouter API key first."
            case .invalidResponse:
                return "OpenRouter returned an unexpected response. Try again."
            case .unauthorized:
                return "OpenRouter rejected this API key. Create a new key and try again."
            case .billingRequired:
                return "This key is valid, but OpenRouter needs credits before model-powered features can run."
            case .unavailable:
                return "OpenRouter is temporarily unavailable. Your existing connection was not changed."
            case .rejected(let message):
                return message
            }
        }
    }

    private let session: URLSession

    init(session: URLSession? = nil) {
        if let session {
            self.session = session
            return
        }

        let configuration = URLSessionConfiguration.ephemeral
        configuration.waitsForConnectivity = false
        configuration.timeoutIntervalForRequest = 15
        configuration.timeoutIntervalForResource = 20
        self.session = URLSession(configuration: configuration)
    }

    func validate(apiKey: String) async throws {
        let normalizedKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedKey.isEmpty else { throw ValidationError.emptyKey }

        var request = URLRequest(url: URL(string: "https://openrouter.ai/api/v1/key")!)
        request.httpMethod = "GET"
        request.timeoutInterval = 15
        request.setValue("Bearer \(normalizedKey)", forHTTPHeaderField: "authorization")

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw ValidationError.unavailable
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw ValidationError.invalidResponse
        }

        switch httpResponse.statusCode {
        case 200..<300:
            guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let keyData = object["data"] as? [String: Any]
            else {
                throw ValidationError.invalidResponse
            }
            // The key endpoint normally returns HTTP 200 even when a key's
            // spending allowance is exhausted. Catch that state during setup
            // instead of failing on the first model request.
            if let remaining = Self.number(keyData["limit_remaining"]), remaining <= 0 {
                throw ValidationError.billingRequired
            }
        case 401, 403:
            throw ValidationError.unauthorized
        case 402:
            throw ValidationError.billingRequired
        case 429, 500..<600:
            throw ValidationError.unavailable
        default:
            throw ValidationError.rejected(Self.errorMessage(from: data))
        }
    }

    private static func errorMessage(from data: Data) -> String {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            return "OpenRouter could not validate this connection."
        }

        let nestedMessage = (object["error"] as? [String: Any])?["message"] as? String
        let topLevelMessage = object["message"] as? String
        let message = (nestedMessage ?? topLevelMessage ?? "OpenRouter could not validate this connection.")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !message.isEmpty else { return "OpenRouter could not validate this connection." }
        return String(message.prefix(240))
    }

    private static func number(_ value: Any?) -> Double? {
        if let number = value as? NSNumber { return number.doubleValue }
        if let string = value as? String { return Double(string) }
        return nil
    }
}
