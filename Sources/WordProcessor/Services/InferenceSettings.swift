import Foundation

enum InferencePurpose: String, Sendable {
    case assistant
    case chat
    case grammar
    case proofread
}

enum InferenceProviderID: String, Sendable {
    case openRouter
}

struct InferenceRuntime: Sendable, Equatable {
    let providerID: InferenceProviderID
    let providerName: String
    let messagesURL: URL
    let apiKeyService: String
    let model: String
    let fallbackModels: [String]
    let webSearchEnabled: Bool
    let supportsTemperature: Bool
}

enum InferenceSettings {
    static let writingModelDefaultsKey = "openRouterWritingModel"
    static let researchModelDefaultsKey = "openRouterChatModel"
    static let kimiModel = "moonshotai/kimi-k3"
    static let defaultWritingModel = kimiModel
    static let defaultResearchModel = kimiModel
    static let defaultFallbackModel = "~x-ai/grok-latest"
    static let openRouterKeysURL = URL(string: "https://openrouter.ai/settings/keys")!
    static let openRouterCreditsURL = URL(string: "https://openrouter.ai/settings/credits")!

    static func runtime(
        purpose: InferencePurpose,
        modelOverride: String? = nil
    ) -> InferenceRuntime {
        let defaultsKey = purpose == .chat ? researchModelDefaultsKey : writingModelDefaultsKey
        let fallback = purpose == .chat ? defaultResearchModel : defaultWritingModel

        let model = modelOverride ?? nonemptyDefault(key: defaultsKey, fallback: fallback)
        return InferenceRuntime(
            providerID: .openRouter,
            providerName: "OpenRouter",
            messagesURL: URL(string: "https://openrouter.ai/api/v1/chat/completions")!,
            apiKeyService: "openrouter",
            model: model,
            fallbackModels: model == kimiModel ? [defaultFallbackModel] : [],
            webSearchEnabled: purpose == .chat,
            supportsTemperature: model != kimiModel
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
