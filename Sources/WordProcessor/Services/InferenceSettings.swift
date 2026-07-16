import Foundation

enum InferencePurpose: String, Sendable {
    case assistant
    case grammar
    case proofread
}

enum InferenceProviderID: String, Sendable {
    case tinker
}

struct InferenceRuntime: Sendable, Equatable {
    let providerID: InferenceProviderID
    let providerName: String
    let messagesURL: URL
    let apiKeyService: String
    let apiVersion: String
    let model: String
    let effort: String?
    let supportsPromptCaching: Bool
    let supportsOutputFormat: Bool
    let supportsServerWebSearch: Bool
}

enum InferenceSettings {
    static let tinkerModelDefaultsKey = "tinkerBaseModel"
    static let defaultTinkerModel = "thinkingmachines/Inkling"

    static func runtime(
        purpose: InferencePurpose,
        modelOverride: String?,
        effortOverride: String?
    ) -> InferenceRuntime {
        let configuredBaseModel = nonemptyDefault(
            key: tinkerModelDefaultsKey,
            fallback: defaultTinkerModel
        )
        let defaultModel = purpose == .assistant
            ? (PersonalizationModelRegistry.activeSamplerPath ?? configuredBaseModel)
            : configuredBaseModel
        let model = modelOverride ?? defaultModel
        return InferenceRuntime(
            providerID: .tinker,
            providerName: "Tinker",
            messagesURL: URL(
                string: "https://tinker.thinkingmachines.dev/services/tinker-prod/anthropic/api/v1/messages"
            )!,
            apiKeyService: "tinker",
            apiVersion: "2023-06-01",
            model: model,
            effort: effortOverride,
            supportsPromptCaching: false,
            supportsOutputFormat: false,
            supportsServerWebSearch: false
        )
    }

    private static func nonemptyDefault(key: String, fallback: String) -> String {
        guard let value = UserDefaults.standard.string(forKey: key)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty
        else { return fallback }
        return value
    }
}

enum PersonalizationModelRegistry {
    struct Record: Codable {
        let schemaVersion: Int
        let baseModel: String
        let samplerPath: String
        let statePath: String?
        let trainedAt: String
        let datasetManifest: String?
    }

    static var registryURL: URL {
        PersonalizationStorage.directoryURL.appendingPathComponent("model_registry.json")
    }

    static var activeRecord: Record? {
        guard let data = try? Data(contentsOf: registryURL) else { return nil }
        return try? JSONDecoder().decode(Record.self, from: data)
    }

    static var activeSamplerPath: String? {
        guard let path = activeRecord?.samplerPath
            .trimmingCharacters(in: .whitespacesAndNewlines),
              !path.isEmpty
        else { return nil }
        return path
    }

    static func deactivate() throws {
        guard FileManager.default.fileExists(atPath: registryURL.path) else { return }
        try FileManager.default.removeItem(at: registryURL)
    }
}

enum PersonalizationStorage {
    static var directoryURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Shakespeare", isDirectory: true)
            .appendingPathComponent("personalization", isDirectory: true)
    }
}
