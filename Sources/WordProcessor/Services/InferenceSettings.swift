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
    let note: String
    let supportsTemperature: Bool

    var selectionLabel: String {
        note.isEmpty ? name : "\(name) — \(note)"
    }
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
    static let grokModel = "~x-ai/grok-latest"
    static let defaultWritingModel = kimiModel
    static let defaultResearchModel = kimiModel
    static let defaultFallbackModel = grokModel
    static let availableModels: [InferenceModelOption] = [
        .init(
            id: kimiModel,
            name: "Kimi K3",
            note: "Default",
            supportsTemperature: false
        ),
        .init(
            id: grokModel,
            name: "Grok Latest",
            note: "Kimi fallback",
            supportsTemperature: true
        ),
        .init(
            id: "openai/gpt-5.6-sol",
            name: "GPT-5.6 Sol",
            note: "",
            supportsTemperature: false
        ),
        .init(
            id: "~anthropic/claude-fable-latest",
            name: "Claude Fable Latest",
            note: "",
            supportsTemperature: false
        ),
        .init(
            id: "anthropic/claude-opus-4.7",
            name: "Claude Opus 4.7",
            note: "",
            supportsTemperature: false
        ),
        .init(
            id: "anthropic/claude-opus-4.8",
            name: "Claude Opus 4.8",
            note: "",
            supportsTemperature: true
        ),
    ]
    static let openRouterKeysURL = URL(string: "https://openrouter.ai/settings/keys")!
    static let openRouterCreditsURL = URL(string: "https://openrouter.ai/settings/credits")!
    static let openRouterModelsURL = URL(string: "https://openrouter.ai/models")!

    static func modelOption(for id: String) -> InferenceModelOption? {
        availableModels.first { $0.id == id }
    }

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
