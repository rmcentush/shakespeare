import Foundation

struct TinkerConnectionValidator: Sendable {
    enum ValidationError: LocalizedError, Equatable {
        case emptyKey
        case invalidResponse
        case unauthorized
        case unavailable
        case rejected(String)

        var errorDescription: String? {
            switch self {
            case .emptyKey:
                return "Paste a Tinker API key first."
            case .invalidResponse:
                return "Tinker returned an unexpected response. Try again."
            case .unauthorized:
                return "Tinker rejected this key, or Inkling access is not enabled for this account."
            case .unavailable:
                return "Tinker is temporarily unavailable. Your existing connection was not changed."
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

        let runtime = InferenceSettings.runtime(
            purpose: .assistant,
            modelOverride: InferenceSettings.defaultTinkerModel,
            effortOverride: nil
        )
        let endpoint = runtime.messagesURL.appendingPathComponent("count_tokens")
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 15
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.setValue(normalizedKey, forHTTPHeaderField: "x-api-key")
        request.setValue(runtime.apiVersion, forHTTPHeaderField: "anthropic-version")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "model": InferenceSettings.defaultTinkerModel,
            "messages": [
                ["role": "user", "content": "Connection check"],
            ],
        ])

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
                  object["input_tokens"] is NSNumber
            else {
                throw ValidationError.invalidResponse
            }
        case 401, 403:
            throw ValidationError.unauthorized
        case 429, 500..<600:
            throw ValidationError.unavailable
        default:
            throw ValidationError.rejected(Self.errorMessage(from: data))
        }
    }

    private static func errorMessage(from data: Data) -> String {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            return "Tinker could not validate this connection."
        }

        let nestedMessage = (object["error"] as? [String: Any])?["message"] as? String
        let topLevelMessage = object["message"] as? String
        let message = (nestedMessage ?? topLevelMessage ?? "Tinker could not validate this connection.")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !message.isEmpty else { return "Tinker could not validate this connection." }
        return String(message.prefix(240))
    }
}
