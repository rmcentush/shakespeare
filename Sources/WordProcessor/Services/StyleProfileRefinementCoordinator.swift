import Foundation

/// Prepares at most one cost-bounded profile proposal in the background. The
/// writer still reviews and approves it before it can affect future prompts.
actor StyleProfileRefinementCoordinator {
    static let shared = StyleProfileRefinementCoordinator()

    private static let minimumAutomaticEditCount = 5
    private static let automaticRetryInterval: TimeInterval = 6 * 60 * 60

    private let eventStore: TrainingEventStore
    private let updater: StyleGuideUpdater
    private let draftStore: StyleProfileDraftStore
    private var activePreparation: (
        id: UUID,
        task: Task<StyleGuideUpdater.Proposal, Error>
    )?
    private var lastAutomaticAttempt: Date?

    private init(
        eventStore: TrainingEventStore = .shared,
        updater: StyleGuideUpdater = StyleGuideUpdater()
    ) {
        self.eventStore = eventStore
        self.updater = updater
        draftStore = StyleProfileDraftStore(
            fileURL: AuthorStyleReference.styleDirectoryURL
                .appendingPathComponent("pending_style_profile.json")
        )
    }

    func preparedDraft() -> StyleProfileDraft? {
        do {
            guard let draft = try draftStore.load() else { return nil }
            if draft.proposedMarkdown == eventStore.learnedPreferences() {
                try? draftStore.delete()
                return nil
            }
            return draft
        } catch {
            try? draftStore.delete()
            return nil
        }
    }

    func prepareIfNeeded() async {
        guard PersonalizationSettings.isEnabled,
              APIKeyStore.shared.hasAuthorizedAPIKeyInSession(service: "openrouter"),
              preparedDraft() == nil,
              automaticEvidenceIsReady()
        else { return }

        if let lastAutomaticAttempt,
           Date().timeIntervalSince(lastAutomaticAttempt) < Self.automaticRetryInterval {
            return
        }
        lastAutomaticAttempt = Date()

        do {
            _ = try await prepareDraft()
        } catch is CancellationError {
            return
        } catch {
            // Automatic refinement is opportunistic. Manual preparation in My
            // Style remains available and exposes any actionable error there.
        }
    }

    func prepareNow() async throws -> StyleProfileDraft {
        if let draft = preparedDraft() { return draft }
        return try await prepareDraft()
    }

    func approve(proposedMarkdown: String, eventIDs: [String]) throws {
        let existingCreatedAt = (try? draftStore.load())?.createdAt ?? Date()
        try draftStore.save(
            StyleProfileDraft(
                proposedMarkdown: proposedMarkdown,
                eventIDs: eventIDs,
                createdAt: existingCreatedAt
            )
        )
        try updater.approve(
            StyleGuideUpdater.Proposal(
                proposedMarkdown: proposedMarkdown,
                eventIDs: eventIDs
            )
        )
        try? draftStore.delete()
        NotificationCenter.default.post(name: .styleProfileDraftChanged, object: nil)
    }

    private func automaticEvidenceIsReady() -> Bool {
        if !eventStore.unprocessedWritingSamples(limit: 1).isEmpty { return true }
        return eventStore.unprocessedStyleDecisions(
            limit: Self.minimumAutomaticEditCount
        ).count >= Self.minimumAutomaticEditCount
    }

    private func prepareDraft() async throws -> StyleProfileDraft {
        let preparationID: UUID
        let task: Task<StyleGuideUpdater.Proposal, Error>
        if let activePreparation {
            preparationID = activePreparation.id
            task = activePreparation.task
        } else {
            preparationID = UUID()
            task = Task { try await updater.proposeUpdate() }
            activePreparation = (preparationID, task)
        }

        do {
            let proposal = try await task.value
            if activePreparation?.id == preparationID {
                activePreparation = nil
            }
            if let existing = preparedDraft() { return existing }

            let draft = StyleProfileDraft(
                proposedMarkdown: proposal.proposedMarkdown,
                eventIDs: proposal.eventIDs,
                createdAt: Date()
            )
            try draftStore.save(draft)
            NotificationCenter.default.post(name: .styleProfileDraftChanged, object: nil)
            return draft
        } catch {
            if activePreparation?.id == preparationID {
                activePreparation = nil
            }
            throw error
        }
    }
}

extension Notification.Name {
    static let styleProfileDraftChanged = Notification.Name("styleProfileDraftChanged")
}
