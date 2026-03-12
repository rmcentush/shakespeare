import SwiftUI

@Observable
@MainActor
final class OralityViewModel {
    var result: OralityResult?
    var isLoading = false
    var error: String?

    private var service: HavelockService?
    private var serviceLoaded = false

    func checkOrality(text: String) async {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            error = "No text to analyze"
            return
        }

        isLoading = true
        error = nil
        defer { isLoading = false }

        // Lazy-load models on first use, off the main thread
        if !serviceLoaded {
            service = await Task.detached {
                HavelockService()
            }.value
            serviceLoaded = true
            if service == nil {
                print("Warning: HavelockService failed to initialize — orality analysis unavailable")
            }
        }

        guard let service else {
            error = "Orality model not available"
            return
        }

        do {
            let analysisResult = try await Task.detached {
                try service.analyzeOrality(text: text)
            }.value
            result = analysisResult
        } catch {
            self.error = error.localizedDescription
            print("Orality check failed: \(error)")
        }
    }
}
