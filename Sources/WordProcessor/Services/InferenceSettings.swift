import Foundation

enum InferencePurpose: String, Sendable {
    case assistant
    case grammar
    case proofread
}

enum InferenceProviderID: String, CaseIterable, Identifiable, Sendable {
    case anthropic
    case tinker

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .anthropic: return "Anthropic"
        case .tinker: return "Tinker / Inkling"
        }
    }
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
    static let providerDefaultsKey = "inferenceProvider"
    static let anthropicModelDefaultsKey = "anthropicAssistantModel"
    static let tinkerModelDefaultsKey = "tinkerBaseModel"
    static let defaultAnthropicModel = "claude-fable-5"
    static let defaultTinkerModel = "thinkingmachines/Inkling"

    static var selectedProvider: InferenceProviderID {
        let rawValue = UserDefaults.standard.string(forKey: providerDefaultsKey) ?? ""
        return InferenceProviderID(rawValue: rawValue) ?? .anthropic
    }

    static func runtime(
        purpose: InferencePurpose,
        modelOverride: String?,
        effortOverride: String?
    ) -> InferenceRuntime {
        switch selectedProvider {
        case .anthropic:
            let configuredAssistantModel = nonemptyDefault(
                key: anthropicModelDefaultsKey,
                fallback: defaultAnthropicModel
            )
            let model = modelOverride ?? {
                switch purpose {
                case .assistant: return configuredAssistantModel
                case .grammar: return "claude-haiku-4-5-20251001"
                case .proofread: return "claude-sonnet-5"
                }
            }()
            return InferenceRuntime(
                providerID: .anthropic,
                providerName: "Anthropic",
                messagesURL: URL(string: "https://api.anthropic.com/v1/messages")!,
                apiKeyService: "anthropic",
                apiVersion: "2023-06-01",
                model: model,
                effort: effortOverride,
                supportsPromptCaching: true,
                supportsOutputFormat: true,
                supportsServerWebSearch: true
            )

        case .tinker:
            let configuredBaseModel = nonemptyDefault(
                key: tinkerModelDefaultsKey,
                fallback: defaultTinkerModel
            )
            let model = PersonalizationModelRegistry.activeSamplerPath ?? configuredBaseModel
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
}

enum PersonalizationStorage {
    static var directoryURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Shakespeare", isDirectory: true)
            .appendingPathComponent("personalization", isDirectory: true)
    }
}
