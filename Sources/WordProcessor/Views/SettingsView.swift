import AppKit
import SwiftUI

enum SettingsDestination {
    static let defaultsKey = "settingsSelectedTab"
    static let apiKeys = "apiKeys"
    static let myStyle = "myStyle"
    static let typography = "typography"
    static let editing = "editing"
}

struct SettingsView: View {
    @State private var tinkerKey = ""
    @State private var showKey = false
    @State private var tinkerSaved = false
    @State private var tinkerConnected = false
    @AppStorage(SettingsDestination.defaultsKey) private var selectedTab = SettingsDestination.apiKeys
    @AppStorage(InferenceSettings.tinkerModelDefaultsKey) private var tinkerModel = InferenceSettings.defaultTinkerModel
    @AppStorage(PersonalizationSettings.enabledDefaultsKey) private var personalizationEnabled = false
    @State private var personalizationReadiness = TrainingEventStore.Readiness(
        eventCount: 0,
        resolvedEditCount: 0,
        eligibleExampleCount: 0,
        styleDecisionCount: 0,
        snapshotDocumentCount: 0
    )
    @State private var showDeleteEventsConfirmation = false
    @State private var pendingStyleDecisionCount = 0
    @State private var learnedPreferencesPreview = ""
    @State private var proposedLearnedPreferences = ""
    @State private var proposedLearnedPreferencesDiff = ""
    @State private var proposalEventIDs: [String] = []
    @State private var isUpdatingStylePreferences = false
    @State private var styleUpdateError = ""
    @State private var showStyleProposal = false
    @State private var activeCheckpoint = PersonalizationModelRegistry.activeSamplerPath

    // Font settings
    @State private var fontManager = FontManager.shared
    @State private var textCheckingSettings = TextCheckingSettings.shared
    private let styleGuideUpdater = StyleGuideUpdater()

    var body: some View {
        TabView(selection: $selectedTab) {
            // API Keys tab
            Form {
                Section("Inference") {
                    TextField("Inkling base model", text: $tinkerModel)
                        .textFieldStyle(.roundedBorder)
                    if let checkpoint = activeCheckpoint {
                        LabeledContent("Active personal checkpoint") {
                            Text(checkpoint)
                                .font(.caption2)
                                .lineLimit(2)
                                .textSelection(.enabled)
                        }
                    }
                    Text("An evaluated and promoted personal checkpoint overrides the base model automatically.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("Tinker API Key") {
                    HStack {
                        Label(
                            tinkerConnected ? "Inkling connected" : "Inkling not connected",
                            systemImage: tinkerConnected ? "checkmark.circle.fill" : "circle.dashed"
                        )
                        .foregroundStyle(tinkerConnected ? .green : .secondary)
                        Spacer()
                    }

                    HStack {
                        if showKey {
                            TextField("TINKER_API_KEY", text: $tinkerKey)
                                .textFieldStyle(.roundedBorder)
                        } else {
                            SecureField("TINKER_API_KEY", text: $tinkerKey)
                                .textFieldStyle(.roundedBorder)
                        }
                        Button {
                            pasteTinkerKeyFromClipboard()
                        } label: {
                            Image(systemName: "doc.on.clipboard")
                        }
                        .help("Paste from Clipboard")
                        Button {
                            showKey.toggle()
                        } label: {
                            Image(systemName: showKey ? "eye.slash" : "eye")
                        }
                        .help(showKey ? "Hide API Key" : "Show API Key")
                    }

                    HStack {
                        Button("Save") { saveTinkerKey() }
                        if tinkerSaved {
                            Text("Saved!")
                                .foregroundStyle(.green)
                                .font(.caption)
                        }
                    }
                }

                Section {
                    Text("Your API key is stored in the macOS Keychain, with an owner-only local fallback for development builds.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .tabItem { Label("API Keys", systemImage: "key") }
            .tag(SettingsDestination.apiKeys)

            Form {
                Section("How My Style Works") {
                    Text("Shakespeare combines your editable style reference, preferences learned from saved edit outcomes, and—after evaluation—a personal Inkling checkpoint. Project context stays temporary and is never baked into your permanent voice profile.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("Learn From My Writing") {
                    Toggle("Learn from saved edits and documents", isOn: $personalizationEnabled)

                    Text("Off by default. A suggestion is not treated as training data when you click Accept or Reject. Shakespeare waits until the document is saved, then records whether you kept, revised, reverted, or rewrote it. Nothing is uploaded automatically.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    HStack {
                        Text(personalizationReadiness.status)
                        Spacer()
                        Text("\(personalizationReadiness.eligibleExampleCount) reliable examples")
                            .font(.caption)
                    }

                    ProgressView(value: personalizationReadiness.progress)

                    HStack(spacing: 18) {
                        Label("\(personalizationReadiness.resolvedEditCount) resolved edits", systemImage: "checkmark.circle")
                        Label("\(personalizationReadiness.snapshotDocumentCount) documents", systemImage: "doc.text")
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }

                Section("What Shakespeare Learned") {
                    HStack {
                        Text("New style signals")
                        Spacer()
                        Text("\(pendingStyleDecisionCount)")
                            .font(.caption)
                            .foregroundStyle(pendingStyleDecisionCount >= 20 ? .orange : .secondary)
                    }

                    Text("Only repeated, high-confidence voice, tone, clarity, structure, concision, and style outcomes are proposed as durable preferences. You review every profile update before it becomes active.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Button {
                        Task { await updateStylePreferences() }
                    } label: {
                        if isUpdatingStylePreferences {
                            ProgressView().controlSize(.small)
                        } else {
                            Text("Review learned preferences")
                        }
                    }
                    .disabled(isUpdatingStylePreferences || pendingStyleDecisionCount == 0)

                    if !learnedPreferencesPreview.isEmpty {
                        Text(learnedPreferencesPreview)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(5)
                            .textSelection(.enabled)
                    }

                    if !styleUpdateError.isEmpty {
                        Text(styleUpdateError)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }

                Section("Personal Model") {
                    if let checkpoint = activeCheckpoint {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Active and evaluated")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(checkpoint)
                                .font(.caption2)
                                .lineLimit(3)
                                .textSelection(.enabled)
                        }
                        Button("Use Untuned Inkling") {
                            deactivatePersonalModel()
                        }
                    } else {
                        HStack {
                            Text("Status")
                            Spacer()
                            Text(personalizationReadiness.isTrainingReady ? "Ready to train" : "Collecting evidence")
                                .font(.caption)
                        }
                    }

                    Text("Training creates a candidate LoRA checkpoint. It only becomes active after a held-out evaluation report passes and you explicitly promote it.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("Files and Privacy") {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Style reference")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(styleReferencePath)
                            .font(.caption2)
                            .lineLimit(1)
                            .textSelection(.enabled)
                    }

                    VStack(alignment: .leading, spacing: 3) {
                        Text("Learned preferences")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(learnedPreferencesPath)
                            .font(.caption2)
                            .lineLimit(1)
                            .textSelection(.enabled)
                    }

                    HStack {
                        Text("Local events")
                        Spacer()
                        Text("\(personalizationReadiness.eventCount)")
                            .font(.caption)
                    }

                    HStack {
                        Button("Reveal in Finder") {
                            revealPersonalizationData()
                        }
                        Button("Delete Learning History", role: .destructive) {
                            showDeleteEventsConfirmation = true
                        }
                        .disabled(personalizationReadiness.eventCount == 0)
                    }
                }
            }
            .tabItem { Label("My Style", systemImage: "person.crop.circle.badge.checkmark") }
            .tag(SettingsDestination.myStyle)

            // Typography tab
            Form {
                Section("Font") {
                    Picker("Font Family", selection: $fontManager.currentFont) {
                        Text("Lyon Text").tag("Lyon Text")
                        Text("Gentium Plus").tag("Gentium Plus")
                        Text("Source Serif 4").tag("Source Serif 4")
                        Text("Scala").tag("Scala")
                        Text("Charter").tag("Charter")
                        Text("Signifier").tag("Signifier")
                        Text("Edgar").tag("Edgar")
                        Text("Quadraat").tag("Quadraat")
                        Text("EBGaramond").tag("EBGaramond")
                        Text("Times New Roman").tag("Times New Roman")
                        Text("Georgia").tag("Georgia")
                        Text("Palatino").tag("Palatino")
                        Text("Baskerville").tag("Baskerville")
                        Text("Helvetica Neue").tag("Helvetica Neue")
                        Text("San Francisco").tag("-apple-system")
                    }

                    HStack {
                        Text("Font Size: \(Int(fontManager.currentSize))px")
                        Slider(value: $fontManager.currentSize, in: 12...28, step: 1)
                    }

                    HStack {
                        Text("Line Height: \(String(format: "%.1f", fontManager.currentLineHeight))")
                        Slider(value: $fontManager.currentLineHeight, in: 1.0...2.5, step: 0.1)
                    }
                }

                Section {
                    Button("Apply & Save") {
                        fontManager.save()
                        NotificationCenter.default.post(name: .fontSettingsChanged, object: nil)
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .tabItem { Label("Typography", systemImage: "textformat") }
            .tag(SettingsDestination.typography)

            Form {
                Section("Spelling and Grammar") {
                    Toggle("Check spelling while typing", isOn: Binding(
                        get: { textCheckingSettings.continuousSpellCheckingEnabled },
                        set: { textCheckingSettings.continuousSpellCheckingEnabled = $0 }
                    ))

                    Toggle("Check grammar while typing", isOn: Binding(
                        get: { textCheckingSettings.grammarCheckingEnabled },
                        set: { textCheckingSettings.grammarCheckingEnabled = $0 }
                    ))

                    Picker("English dialect", selection: Binding(
                        get: { textCheckingSettings.dialect },
                        set: { textCheckingSettings.dialect = $0 }
                    )) {
                        ForEach(TextCheckingSettings.dialects, id: \.value) { dialect in
                            Text(dialect.label).tag(dialect.value)
                        }
                    }

                    Toggle("Correct spelling automatically", isOn: Binding(
                        get: { textCheckingSettings.automaticSpellingCorrectionEnabled },
                        set: { textCheckingSettings.automaticSpellingCorrectionEnabled = $0 }
                    ))
                }

                Section("Substitutions") {
                    Toggle("Use text replacements", isOn: Binding(
                        get: { textCheckingSettings.automaticTextReplacementEnabled },
                        set: { textCheckingSettings.automaticTextReplacementEnabled = $0 }
                    ))
                }

                Section {
                    Button("Reset Learned Words and Ignored Issues") {
                        textCheckingSettings.resetDictionary()
                    }

                    Text("Spelling is checked locally by Harper. When grammar checking is enabled, changed paragraphs are sent to the configured language-model provider. An on-demand thorough proofread is available from the Spelling and Grammar menu.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .tabItem { Label("Editing", systemImage: "checkmark.circle") }
            .tag(SettingsDestination.editing)
        }
        .frame(width: 620, height: 620)
        .onAppear {
            tinkerConnected = false
            if let key = APIKeyStore.shared.getAPIKey(service: "tinker") {
                tinkerKey = key
                tinkerConnected = true
            }
            refreshStyleContext()
        }
        .onChange(of: personalizationEnabled) { _, enabled in
            PersonalizationSettings.isEnabled = enabled
            refreshStyleContext()
        }
        .confirmationDialog(
            "Delete local learning history?",
            isPresented: $showDeleteEventsConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete Learning History", role: .destructive) { deleteTrainingEvents() }
            Button("Cancel", role: .cancel) {}
        }
        .sheet(isPresented: $showStyleProposal) {
            styleProposalSheet
        }
    }

    private var styleReferencePath: String {
        AuthorStyleReference.writableReferenceURL.path
    }

    private var learnedPreferencesPath: String {
        AuthorStyleReference.learnedPreferencesURL.path
    }

    private var styleProposalSheet: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Proposed Learned Preferences")
                .font(.headline)

            Text("Review or edit this file before approving. Approval marks \(proposalEventIDs.count) feedback event\(proposalEventIDs.count == 1 ? "" : "s") as processed.")
                .font(.caption)
                .foregroundStyle(.secondary)

            TextEditor(text: $proposedLearnedPreferences)
                .font(.system(.body, design: .monospaced))
                .frame(minHeight: 260)
                .border(Color.secondary.opacity(0.25))

            DisclosureGroup("Diff") {
                ScrollView {
                    Text(proposedLearnedPreferencesDiff)
                        .font(.system(.caption, design: .monospaced))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                }
                .frame(minHeight: 140)
            }

            HStack {
                Spacer()
                Button("Discard") {
                    showStyleProposal = false
                }
                Button("Approve") {
                    approveStyleProposal()
                }
                .buttonStyle(.borderedProminent)
                .disabled(proposedLearnedPreferences.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 760, height: 620)
    }

    private func pasteTinkerKeyFromClipboard() {
        guard let clipboardString = NSPasteboard.general.string(forType: .string) else { return }
        tinkerKey = clipboardString.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func saveTinkerKey() {
        tinkerKey = tinkerKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard APIKeyStore.shared.setAPIKey(tinkerKey, service: "tinker") else { return }
        tinkerConnected = !tinkerKey.isEmpty
        tinkerSaved = true
        NotificationCenter.default.post(name: .inklingConnectionChanged, object: nil)
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            tinkerSaved = false
        }
    }

    private func revealPersonalizationData() {
        let url = PersonalizationStorage.directoryURL
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    private func deleteTrainingEvents() {
        do {
            try TrainingEventStore.shared.deleteAll()
            refreshStyleContext()
        } catch {
            styleUpdateError = error.localizedDescription
        }
    }

    private func refreshStyleContext() {
        _ = AuthorStyleReference.content
        personalizationReadiness = TrainingEventStore.shared.readiness()
        pendingStyleDecisionCount = TrainingEventStore.shared.pendingDecisionCount()
        activeCheckpoint = PersonalizationModelRegistry.activeSamplerPath
        learnedPreferencesPreview = AuthorStyleReference.learnedPreferences
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func deactivatePersonalModel() {
        do {
            try PersonalizationModelRegistry.deactivate()
            activeCheckpoint = nil
        } catch {
            styleUpdateError = error.localizedDescription
        }
    }

    @MainActor
    private func updateStylePreferences() async {
        isUpdatingStylePreferences = true
        styleUpdateError = ""
        defer {
            isUpdatingStylePreferences = false
            refreshStyleContext()
        }

        do {
            let current = AuthorStyleReference.learnedPreferences
            let proposal = try await styleGuideUpdater.proposeUpdate()
            proposedLearnedPreferences = proposal.proposedMarkdown
            proposedLearnedPreferencesDiff = StyleGuideUpdater.unifiedDiff(
                old: current,
                new: proposal.proposedMarkdown
            )
            proposalEventIDs = proposal.eventIDs
            showStyleProposal = true
        } catch {
            styleUpdateError = error.localizedDescription
        }
    }

    private func approveStyleProposal() {
        do {
            let proposal = StyleGuideUpdater.Proposal(
                proposedMarkdown: proposedLearnedPreferences,
                eventIDs: proposalEventIDs
            )
            try styleGuideUpdater.approve(proposal)
            showStyleProposal = false
            proposedLearnedPreferences = ""
            proposedLearnedPreferencesDiff = ""
            proposalEventIDs = []
            refreshStyleContext()
        } catch {
            styleUpdateError = error.localizedDescription
        }
    }
}

extension Notification.Name {
    static let fontSettingsChanged = Notification.Name("fontSettingsChanged")
}
