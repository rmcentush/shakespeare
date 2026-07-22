import Foundation
import Observation

@Observable
@MainActor
final class ApplicationStorageStatus {
    static let shared = ApplicationStorageStatus()

    private(set) var isReady = false
    private(set) var failureMessage: String?
    @ObservationIgnored private let prepareStorage: () throws -> Void

    init(prepareStorage: @escaping () throws -> Void = { try ShakespeareStorage.prepare() }) {
        self.prepareStorage = prepareStorage
    }

    func prepare() {
        do {
            try prepareStorage()
            failureMessage = nil
            isReady = true
        } catch {
            isReady = false
            failureMessage = error.localizedDescription
        }
    }
}
