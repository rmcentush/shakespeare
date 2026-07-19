import Foundation

/// Gives every editorial writing request the same live, reviewed style context.
/// AuthorStyleReference detects file changes and approval writes reload it, so
/// each request sees the newest guide without keeping another cache here.
enum PersonalizedWritingContext {
    static func assemble(
        task: String,
        documentExcerpt: String,
        generalGuidance: String = ""
    ) -> StyleContextAssembler.Packet {
        let usesPersonalStyle = PersonalizationSettings.isEnabled
        return StyleContextAssembler.assemble(
            task: task,
            documentExcerpt: documentExcerpt,
            reference: usesPersonalStyle ? AuthorStyleReference.content : "",
            learnedPreferences: usesPersonalStyle ? AuthorStyleReference.learnedPreferences : "",
            generalGuidance: generalGuidance,
            writingSamples: usesPersonalStyle
                ? TrainingEventStore.shared.writingSamples()
                : [],
            confirmedEdits: usesPersonalStyle
                ? TrainingEventStore.shared.confirmedStyleExamples()
                : []
        )
    }
}
