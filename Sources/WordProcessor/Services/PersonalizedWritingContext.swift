import Foundation

/// Gives every editorial writing request the same live, reviewed style context.
/// AuthorStyleReference detects file changes and approval writes reload it, so
/// each request sees the newest guide without keeping another cache here.
enum PersonalizedWritingContext {
    static func assemble(
        task: String,
        documentExcerpt: String,
        generalGuidance: String = ""
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
                generalGuidance: generalGuidance,
                writingSamples: writingSamples,
                confirmedEdits: confirmedEdits
            )
        }.value
    }
}
