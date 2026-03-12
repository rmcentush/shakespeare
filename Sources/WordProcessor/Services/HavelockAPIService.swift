import Foundation

final class HavelockAPIService: Sendable {
    // Havelock.AI Gradio API (v0.2.1) — two-step SSE protocol
    private let baseURL = "https://thestalwart-havelock-demo.hf.space/gradio_api"

    func analyzeOrality(text: String) async throws -> OralityResult {
        // Step 1: POST to /call/analyze to get an event_id
        let submitURL = URL(string: "\(baseURL)/call/analyze")!
        var request = URLRequest(url: submitURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.timeoutInterval = 120 // Space may need to wake up

        let body: [String: Any] = ["data": [text]]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw OralityError.submitFailed
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let eventId = json["event_id"] as? String else {
            throw OralityError.invalidResponse
        }

        // Step 2: GET /call/analyze/{event_id} for SSE results
        let resultURL = URL(string: "\(baseURL)/call/analyze/\(eventId)")!
        var resultRequest = URLRequest(url: resultURL)
        resultRequest.timeoutInterval = 120

        let (resultData, resultResponse) = try await URLSession.shared.data(for: resultRequest)

        guard let resultHttp = resultResponse as? HTTPURLResponse,
              resultHttp.statusCode == 200 else {
            throw OralityError.submitFailed
        }

        // Parse SSE response — find the "data: " line after "event: complete"
        let responseText = String(data: resultData, encoding: .utf8) ?? ""
        return try parseSSEResponse(responseText)
    }

    private func parseSSEResponse(_ text: String) throws -> OralityResult {
        // SSE format: lines like "event: complete\ndata: [...]"
        let lines = text.components(separatedBy: "\n")
        var foundComplete = false

        for line in lines {
            if line.starts(with: "event: complete") {
                foundComplete = true
                continue
            }
            if foundComplete, line.starts(with: "data: ") {
                let jsonString = String(line.dropFirst(6))
                guard let jsonData = jsonString.data(using: .utf8),
                      let array = try? JSONSerialization.jsonObject(with: jsonData) as? [Any],
                      let analysis = array.first as? [String: Any]
                else {
                    throw OralityError.invalidResponse
                }
                return parseAnalysis(analysis)
            }
        }

        throw OralityError.invalidResponse
    }

    private func parseAnalysis(_ json: [String: Any]) -> OralityResult {
        let score = json["score"] as? Int ?? 0
        let docScore = json["doc_score"] as? Double ?? 0
        let oralCount = json["oral_count"] as? Int ?? 0
        let literateCount = json["literate_count"] as? Int ?? 0

        var sentences: [OralityResult.SentenceAnalysis] = []
        if let sentenceArray = json["sentences"] as? [[String: Any]] {
            for s in sentenceArray {
                let text = s["text"] as? String ?? ""
                let category = s["category"] as? String ?? "unknown"
                let categoryConfidence = s["category_confidence"] as? Double ?? 0
                let primaryMarker = s["marker"] as? String ?? ""

                var markers: [OralityResult.Marker] = []
                if let markerArray = s["markers"] as? [[String: Any]] {
                    for m in markerArray {
                        let name = m["marker"] as? String ?? ""
                        let confidence = m["confidence"] as? Double ?? 0
                        markers.append(OralityResult.Marker(name: name, confidence: confidence))
                    }
                }

                sentences.append(OralityResult.SentenceAnalysis(
                    text: text,
                    category: category,
                    categoryConfidence: categoryConfidence,
                    primaryMarker: primaryMarker,
                    markers: markers
                ))
            }
        }

        return OralityResult(
            score: score,
            docScore: docScore,
            oralCount: oralCount,
            literateCount: literateCount,
            sentences: sentences
        )
    }

    enum OralityError: LocalizedError {
        case submitFailed
        case invalidResponse
        case timeout

        var errorDescription: String? {
            switch self {
            case .submitFailed: return "Failed to connect to Havelock API. The service may be waking up — try again in 30 seconds."
            case .invalidResponse: return "Invalid response from Havelock API"
            case .timeout: return "Analysis timed out"
            }
        }
    }
}
