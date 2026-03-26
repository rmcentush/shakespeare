import SwiftUI

@Observable
@MainActor
final class OralityViewModel {
    var result: OralityResult?
    var isLoading = false
    var error: String?

    private let apiService = HavelockAPIService()

    func checkOrality(text: String) async {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            error = "No text to analyze"
            return
        }

        isLoading = true
        result = nil
        error = nil
        defer { isLoading = false }

        do {
            result = try await apiService.analyzeOrality(text: text)
        } catch {
            self.error = error.localizedDescription
            print("Havelock API check failed: \(error)")
        }
    }
}
