import Foundation

/// Gives every editorial writing request the same live, reviewed style context.
/// AuthorStyleReference detects file changes and approval writes reload it, so
/// each request sees the newest guide without keeping another cache here.
enum PersonalizedWritingContext {
    /// A resource-copy failure should reduce nuance, not silently remove the
    /// writing-quality floor from every editorial feature.
    private static let builtInGeneralGuidanceFallback = """
    ## Core anti-pattern check
    Lead with the concrete claim. Remove unearned throat-clearing, inflated significance, vague attribution, formulaic contrast, automatic groups of three, canned transitions, generic summaries, and chatbot artifacts. Preserve facts, uncertainty, deliberate irregularities, and the writer's reviewed voice. Treat patterns as contextual signals, never hard bans, and leave effective prose alone.
    """

    private static let defaultGeneralGuidance: String = {
        guard let resourceURL = Bundle.shakespeareResources.url(
            forResource: "writing_quality_guidance",
            withExtension: "md"
        ),
              let content = try? String(contentsOf: resourceURL, encoding: .utf8),
              !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else { return builtInGeneralGuidanceFallback }
        return content
    }()

    static func assemble(
        task: String,
        documentExcerpt: String,
        generalGuidance: String? = nil
    ) async -> StyleContextAssembler.Packet {
        let usesPersonalStyle = PersonalizationSettings.isEnabled
        let reference = usesPersonalStyle ? AuthorStyleReference.content : ""
        let learnedPreferences = usesPersonalStyle ? AuthorStyleReference.learnedPreferences : ""
        let writingSamples = usesPersonalStyle
            ? TrainingEventStore.shared.writingSamples()
            : []
        let confirmedEdits = usesPersonalStyle
            ? TrainingEventStore.shared.confirmedStyleExamples()
            : []

        return await Task.detached(priority: .utility) {
            StyleContextAssembler.assemble(
                task: task,
                documentExcerpt: documentExcerpt,
                reference: reference,
                learnedPreferences: learnedPreferences,
                generalGuidance: generalGuidance ?? defaultGeneralGuidance,
                writingSamples: writingSamples,
                confirmedEdits: confirmedEdits
            )
        }.value
    }
}
