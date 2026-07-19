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

struct InferenceModelOption: Identifiable, Sendable, Equatable {
    let id: String
    let name: String
    let supportsTemperature: Bool
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
    static let geminiFlashModel = "google/gemini-3.5-flash"
    static let haikuModel = "anthropic/claude-haiku-4.5"
    static let grokModel = "x-ai/grok-4.5"
    static let defaultWritingModel = kimiModel
    static let defaultResearchModel = geminiFlashModel
    static let availableModels: [InferenceModelOption] = [
        .init(
            id: kimiModel,
            name: "Kimi K3",
            supportsTemperature: false
        ),
        .init(
            id: geminiFlashModel,
            name: "Gemini 3.5 Flash",
            supportsTemperature: true
        ),
        .init(
            id: haikuModel,
            name: "Claude Haiku 4.5",
            supportsTemperature: true
        ),
        .init(
            id: grokModel,
            name: "Grok 4.5",
            supportsTemperature: true
        ),
        .init(
            id: "openai/gpt-5.6-sol",
            name: "GPT-5.6 Sol",
            supportsTemperature: false
        ),
        .init(
            id: "anthropic/claude-fable-5",
            name: "Claude Fable 5",
            supportsTemperature: false
        ),
        .init(
            id: "anthropic/claude-opus-4.7",
            name: "Claude Opus 4.7",
            supportsTemperature: false
        ),
        .init(
            id: "anthropic/claude-opus-4.8",
            name: "Claude Opus 4.8",
            supportsTemperature: true
        ),
    ]
    static let openRouterKeysURL = URL(string: "https://openrouter.ai/settings/keys")!
    static let openRouterCreditsURL = URL(string: "https://openrouter.ai/settings/credits")!
    static let openRouterModelsURL = URL(string: "https://openrouter.ai/models")!

    static func modelOption(for id: String) -> InferenceModelOption? {
        availableModels.first { $0.id == id }
    }

    static func normalizedModelID(_ id: String) -> String {
        switch id {
        case "~x-ai/grok-latest":
            return grokModel
        case "~anthropic/claude-fable-latest":
            return "anthropic/claude-fable-5"
        default:
            return id
        }
    }

    static func fallbackModels(after primaryModel: String) -> [String] {
        availableModels.map(\.id).filter { $0 != primaryModel }
    }

    static func runtime(
        purpose: InferencePurpose,
        modelOverride: String? = nil
    ) -> InferenceRuntime {
        let defaultsKey = purpose == .chat ? researchModelDefaultsKey : writingModelDefaultsKey
        let fallback = purpose == .chat ? defaultResearchModel : defaultWritingModel

        let model = normalizedModelID(
            modelOverride ?? nonemptyDefault(key: defaultsKey, fallback: fallback)
        )
        return InferenceRuntime(
            providerID: .openRouter,
            providerName: "OpenRouter",
            messagesURL: URL(string: "https://openrouter.ai/api/v1/chat/completions")!,
            apiKeyService: "openrouter",
            model: model,
            fallbackModels: fallbackModels(after: model),
            webSearchEnabled: purpose == .chat,
            supportsTemperature: modelOption(for: model)?.supportsTemperature ?? true
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
