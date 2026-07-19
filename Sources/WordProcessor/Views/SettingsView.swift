import AppKit
import SwiftUI
import UniformTypeIdentifiers

enum SettingsDestination {
    static let defaultsKey = "settingsSelectedTab"
    static let apiKeys = "apiKeys"
    static let myStyle = "myStyle"
    static let typography = "typography"
    static let editing = "editing"
}

struct SettingsView: View {
    @State private var openRouterKey = ""
    @State private var showOpenRouterKey = false
    @State private var openRouterSaved = false
    @State private var openRouterConnected = false
    @State private var isValidatingOpenRouterKey = false
    @State private var openRouterConnectionError = ""
    @State private var openRouterConnectionRequiresBilling = false
    @State private var showOpenRouterDisconnectConfirmation = false
    @AppStorage(SettingsDestination.defaultsKey) private var selectedTab = SettingsDestination.apiKeys
    @AppStorage(InferenceSettings.writingModelDefaultsKey) private var writingModel = InferenceSettings.defaultWritingModel
    @AppStorage(InferenceSettings.researchModelDefaultsKey) private var researchModel = InferenceSettings.defaultResearchModel
    @AppStorage(PersonalizationSettings.enabledDefaultsKey) private var personalizationEnabled = true
    @State private var personalizationReadiness = TrainingEventStore.Readiness(
        eventCount: 0,
        resolvedEditCount: 0,
        eligibleExampleCount: 0,
        styleDecisionCount: 0,
        confirmedRewriteCount: 0,
        bootstrapSampleCount: 0
    )
    @State private var showDeleteEventsConfirmation = false
    @State private var showResetDictionaryConfirmation = false
    @State private var pendingProfileEvidenceCount = 0
    @State private var learnedPreferencesPreview = ""
    @State private var proposedLearnedPreferences = ""
    @State private var proposedLearnedPreferencesDiff = ""
    @State private var proposalEventIDs: [String] = []
    @State private var isUpdatingStylePreferences = false
    @State private var styleUpdateError = ""
    @State private var showStyleProposal = false
    @State private var preparedStyleDraft: StyleProfileDraft?
    @State private var showWritingSampleImporter = false
    @State private var writingSampleImportMessage = ""
    @State private var writingSampleImportFailed = false
    @State private var modelAvailability: [String: OpenRouterModelAvailabilityService.ModelStatus] = [:]
    @State private var isCheckingModelAvailability = false

    // Font settings
    @State private var fontManager = FontManager.shared
    @State private var textCheckingSettings = TextCheckingSettings.shared
    private let openRouterConnectionValidator = OpenRouterConnectionValidator()

    var body: some View {
        TabView(selection: $selectedTab) {
            connectionsSettings
                .tabItem { Label("Connections", systemImage: "link") }
                .tag(SettingsDestination.apiKeys)

            myStyleSettings
                .tabItem { Label("My Style", systemImage: "person.crop.circle.badge.checkmark") }
                .tag(SettingsDestination.myStyle)

            typographySettings
                .tabItem { Label("Typography", systemImage: "textformat") }
                .tag(SettingsDestination.typography)

            editingSettings
                .tabItem { Label("Editing", systemImage: "checkmark.circle") }
                .tag(SettingsDestination.editing)
        }
        .frame(width: 680, height: 640)
        .onAppear {
            openRouterConnected = APIKeyStore.shared.hasAPIKey(service: "openrouter")
            writingModel = InferenceSettings.normalizedModelID(writingModel)
            researchModel = InferenceSettings.normalizedModelID(researchModel)
            refreshStyleContext()
            Task { await refreshPreparedStyleDraft() }
        }
        .onChange(of: personalizationEnabled) { _, enabled in
            PersonalizationSettings.isEnabled = enabled
            refreshStyleContext()
        }
        .onChange(of: openRouterKey) {
            openRouterConnectionError = ""
            openRouterConnectionRequiresBilling = false
        }
        .confirmationDialog(
            "Delete local learning history?",
            isPresented: $showDeleteEventsConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete Learning History", role: .destructive) { deleteTrainingEvents() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes imported samples, learned preferences, and local learning history. Your editable style reference, documents, settings, and API key are kept.")
        }
        .confirmationDialog(
            "Disconnect OpenRouter?",
            isPresented: $showOpenRouterDisconnectConfirmation,
            titleVisibility: .visible
        ) {
            Button("Disconnect", role: .destructive) { disconnectOpenRouter() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes the saved OpenRouter API key from this Mac. Model-powered writing, grammar, and research will pause; the editor and local spelling remain available.")
        }
        .confirmationDialog(
            "Reset learned spelling data?",
            isPresented: $showResetDictionaryConfirmation,
            titleVisibility: .visible
        ) {
            Button("Reset Learned Words and Ignored Issues", role: .destructive) {
                textCheckingSettings.resetDictionary()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Shakespeare will forget words you taught it and issues you chose to ignore.")
        }
        .sheet(isPresented: $showStyleProposal) {
            styleProposalSheet
        }
        .fileImporter(
            isPresented: $showWritingSampleImporter,
            allowedContentTypes: [
                .plainText,
                UTType(filenameExtension: "md") ?? .plainText,
            ],
            allowsMultipleSelection: true,
            onCompletion: importWritingSamples
        )
        .onReceive(NotificationCenter.default.publisher(for: .styleProfileDraftChanged)) { _ in
            Task { await refreshPreparedStyleDraft() }
        }
    }

    private var myStyleSettings: some View {
        SettingsPage {
            SettingsCard(title: "Personalization") {
                Toggle(isOn: $personalizationEnabled) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Make suggestions sound like me")
                            .fontWeight(.medium)
                        Text("Learns from writing samples and rewrites you save.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Divider()

                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Writing samples")
                            .fontWeight(.medium)
                        Text(styleSourceSummary)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Add Samples…") {
                        writingSampleImportMessage = ""
                        showWritingSampleImporter = true
                    }
                    .disabled(!personalizationEnabled)
                }

                if !writingSampleImportMessage.isEmpty {
                    Label(
                        writingSampleImportMessage,
                        systemImage: writingSampleImportFailed
                            ? "exclamationmark.triangle.fill" : "checkmark.circle.fill"
                    )
                    .font(.caption)
                    .foregroundStyle(writingSampleImportFailed ? .red : .green)
                    .fixedSize(horizontal: false, vertical: true)
                }

                Divider()

                HStack(alignment: .center) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Style profile")
                            .fontWeight(.medium)
                        Text(styleProfileStatus)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button {
                        if let preparedStyleDraft {
                            presentStyleDraft(preparedStyleDraft)
                        } else {
                            Task { await updateStylePreferences() }
                        }
                    } label: {
                        if isUpdatingStylePreferences {
                            HStack(spacing: 6) {
                                ProgressView().controlSize(.small)
                                Text("Preparing…")
                            }
                        } else {
                            Text("Review Update")
                        }
                    }
                    .disabled(
                        !personalizationEnabled ||
                        isUpdatingStylePreferences ||
                        pendingProfileEvidenceCount == 0
                    )
                }

                if !learnedPreferencesPreview.isEmpty {
                    Text(learnedPreferencesPreview)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(10)
                        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
                }

                if !styleUpdateError.isEmpty {
                    Label(styleUpdateError, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.red)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            SettingsCard(title: "Privacy & Data") {
                Text("Your style data stays on this Mac. Only short, relevant excerpts are sent with writing requests.")
                    .settingsDescriptionStyle()

                DisclosureGroup("Local files and controls") {
                    VStack(alignment: .leading, spacing: 10) {
                        SettingsPathRow(title: "Style reference", path: styleReferencePath)
                        SettingsPathRow(title: "Style profile", path: learnedPreferencesPath)

                        HStack {
                            Text("Learning history")
                            Spacer()
                            Text("\(personalizationReadiness.eventCount) events")
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }

                        HStack {
                            Button("Reveal Folder") {
                                revealPersonalizationData()
                            }
                            Button("Delete Learning History", role: .destructive) {
                                showDeleteEventsConfirmation = true
                            }
                        }
                    }
                    .padding(.top, 8)
                }
            }
        }
    }

    private var styleSourceSummary: String {
        let samples = personalizationReadiness.bootstrapSampleCount
        let rewrites = personalizationReadiness.confirmedRewriteCount
        if samples == 0, rewrites == 0 { return "Add finished .txt or .md files to get started." }
        return "\(samples) sample\(samples == 1 ? "" : "s") · \(rewrites) saved rewrite\(rewrites == 1 ? "" : "s")"
    }

    private var styleProfileStatus: String {
        guard personalizationEnabled else { return "Paused" }
        if preparedStyleDraft != nil { return "Update ready to review" }
        if pendingProfileEvidenceCount > 0 {
            return "\(pendingProfileEvidenceCount) new pattern\(pendingProfileEvidenceCount == 1 ? "" : "s") ready to review"
        }
        if !learnedPreferencesPreview.isEmpty { return "Active and up to date" }
        return "Builds as you save rewrites"
    }

    private var typographySettings: some View {
        SettingsPage {
            SettingsCard(title: "Default Typography") {
                Picker("Font family", selection: $fontManager.currentFont) {
                    Text("Georgia").tag("Georgia")
                    Text("Palatino").tag("Palatino")
                    Text("Baskerville").tag("Baskerville")
                    Text("Times New Roman").tag("Times New Roman")
                    Text("Helvetica Neue").tag("Helvetica Neue")
                    Text("San Francisco").tag("-apple-system")
                }

                SettingsSlider(
                    title: "Font size",
                    valueLabel: "\(Int(fontManager.currentSize)) px",
                    value: $fontManager.currentSize,
                    range: 12...28,
                    step: 1
                )

                SettingsSlider(
                    title: "Line height",
                    valueLabel: String(format: "%.1f", fontManager.currentLineHeight),
                    value: $fontManager.currentLineHeight,
                    range: 1...2.5,
                    step: 0.1
                )

                HStack {
                    Spacer()
                    Button("Apply & Save") {
                        fontManager.save()
                        NotificationCenter.default.post(name: .fontSettingsChanged, object: nil)
                    }
                    .buttonStyle(.borderedProminent)
                }
            }

            SettingsCard(title: "Preview") {
                Text("Words should feel as considered on the page as they did in the writer’s mind.")
                    .font(.custom(fontManager.currentFont, size: fontManager.currentSize))
                    .frame(maxWidth: .infinity, minHeight: 100, alignment: .leading)
                    .padding(.horizontal, 4)

                Text("New empty documents start with these defaults. Existing text is never reformatted.")
                    .settingsDescriptionStyle()
            }
        }
    }

    private var editingSettings: some View {
        SettingsPage {
            SettingsCard(title: "Spelling and Grammar") {
                SettingsToggle(
                    title: "Check spelling while typing",
                    description: "Misspellings are underlined as you write.",
                    isOn: Binding(
                        get: { textCheckingSettings.continuousSpellCheckingEnabled },
                        set: { textCheckingSettings.continuousSpellCheckingEnabled = $0 }
                    )
                )

                SettingsToggle(
                    title: "Check AI grammar while typing",
                    description: "Off by default. Changed paragraphs use your paid OpenRouter account after you pause.",
                    isOn: Binding(
                        get: { textCheckingSettings.grammarCheckingEnabled },
                        set: { textCheckingSettings.grammarCheckingEnabled = $0 }
                    )
                )

                Picker("English dialect", selection: Binding(
                    get: { textCheckingSettings.dialect },
                    set: { textCheckingSettings.dialect = $0 }
                )) {
                    ForEach(TextCheckingSettings.dialects, id: \.value) { dialect in
                        Text(dialect.label).tag(dialect.value)
                    }
                }
            }

            SettingsCard(title: "Automatic Corrections") {
                SettingsToggle(
                    title: "Correct spelling automatically",
                    description: "Replace likely misspellings while you type.",
                    isOn: Binding(
                        get: { textCheckingSettings.automaticSpellingCorrectionEnabled },
                        set: { textCheckingSettings.automaticSpellingCorrectionEnabled = $0 }
                    )
                )

                SettingsToggle(
                    title: "Use text replacements",
                    description: "Apply substitutions configured in macOS.",
                    isOn: Binding(
                        get: { textCheckingSettings.automaticTextReplacementEnabled },
                        set: { textCheckingSettings.automaticTextReplacementEnabled = $0 }
                    )
                )
            }

            SettingsCard(title: "Dictionary and Privacy") {
                Text("Spelling is checked locally by Harper. An on-demand thorough proofread is available from the Spelling and Grammar menu.")
                    .settingsDescriptionStyle()

                Button("Reset Learned Words and Ignored Issues") {
                    showResetDictionaryConfirmation = true
                }
            }

            SettingsCard(title: "Feature Tour") {
                HStack(alignment: .center, spacing: 16) {
                    Text("Take another quick look at the main writing tools.")
                        .settingsDescriptionStyle()
                    Spacer()
                    Button("Replay Tour") {
                        replayFeatureTour()
                    }
                }
            }
        }
    }

    private var connectionsSettings: some View {
        SettingsPage {
            SettingsCard(title: "OpenRouter") {
                Label(
                    openRouterConnected ? "Connected and ready" : "Not connected",
                    systemImage: openRouterConnected ? "checkmark.circle.fill" : "circle.dashed"
                )
                .foregroundStyle(openRouterConnected ? .green : .secondary)

                Text("One API key powers drafting, revision, grammar, style review, and cited research. Personal style context is sent only with writing features; research chat remains isolated from your permanent style profile.")
                    .settingsDescriptionStyle()

                HStack {
                    Text("OpenRouter API key")
                        .font(.headline)
                    Spacer()
                    Link("Get a key ↗", destination: InferenceSettings.openRouterKeysURL)
                        .font(.caption)
                }

                HStack {
                    if showOpenRouterKey {
                        TextField(
                            openRouterConnected ? "Paste a new key to replace the current one" : "Paste OPENROUTER_API_KEY",
                            text: $openRouterKey
                        )
                        .textFieldStyle(.roundedBorder)
                    } else {
                        SecureField(
                            openRouterConnected ? "Paste a new key to replace the current one" : "Paste OPENROUTER_API_KEY",
                            text: $openRouterKey
                        )
                        .textFieldStyle(.roundedBorder)
                    }

                    Button {
                        pasteOpenRouterKeyFromClipboard()
                    } label: {
                        Image(systemName: "doc.on.clipboard")
                    }
                    .help("Paste from Clipboard")
                    .accessibilityLabel("Paste API Key from Clipboard")

                    Button {
                        showOpenRouterKey.toggle()
                    } label: {
                        Image(systemName: showOpenRouterKey ? "eye.slash" : "eye")
                    }
                    .help(showOpenRouterKey ? "Hide API Key" : "Show API Key")
                    .accessibilityLabel(showOpenRouterKey ? "Hide API Key" : "Show API Key")
                }
                .disabled(isValidatingOpenRouterKey)

                HStack {
                    Button(openRouterConnected ? "Update Connection" : "Connect") {
                        Task { await saveOpenRouterKey() }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(
                        openRouterKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                        isValidatingOpenRouterKey
                    )

                    if openRouterConnected {
                        Button("Disconnect", role: .destructive) {
                            showOpenRouterDisconnectConfirmation = true
                        }
                        .disabled(isValidatingOpenRouterKey)
                    }

                    if isValidatingOpenRouterKey {
                        ProgressView().controlSize(.small)
                        Text("Checking OpenRouter…")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    if openRouterSaved {
                        Text("Connected")
                            .font(.caption)
                            .foregroundStyle(.green)
                    }
                }

                if openRouterConnectionRequiresBilling {
                    HStack(alignment: .top, spacing: 9) {
                        Image(systemName: "creditcard.trianglebadge.exclamationmark.fill")
                            .foregroundStyle(.orange)
                        VStack(alignment: .leading, spacing: 4) {
                            Text("This key is valid, but OpenRouter needs credits before model-powered features can run.")
                                .font(.caption)
                            Link("Add OpenRouter credits ↗", destination: InferenceSettings.openRouterCreditsURL)
                                .font(.caption.weight(.semibold))
                        }
                    }
                    .padding(11)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.orange.opacity(0.09), in: RoundedRectangle(cornerRadius: 9))
                } else if !openRouterConnectionError.isEmpty {
                    Label(openRouterConnectionError, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.red)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Text("The key is validated before it is stored securely on this Mac. Requests disable provider data collection and are sent only when you use a model-powered feature.")
                    .settingsDescriptionStyle()
            }

            SettingsCard(title: "Advanced") {
                DisclosureGroup("Model configuration") {
                    VStack(alignment: .leading, spacing: 12) {
                        modelPicker(
                            title: "Writing",
                            selection: $writingModel,
                            description: "Drafting, revision, grammar, and style."
                        )

                        Divider()

                        modelPicker(
                            title: "Research chat",
                            selection: $researchModel,
                            description: "Includes bounded web search for current, cited answers."
                        )

                        Divider()

                        HStack {
                            Link("Compare pricing ↗", destination: InferenceSettings.openRouterModelsURL)
                                .font(.caption.weight(.semibold))
                            Spacer()
                            Button {
                                Task { await refreshModelAvailability(forceRefresh: true) }
                            } label: {
                                if isCheckingModelAvailability {
                                    ProgressView()
                                        .controlSize(.small)
                                } else {
                                    Label("Refresh status", systemImage: "arrow.clockwise")
                                }
                            }
                            .buttonStyle(.plain)
                            .font(.caption.weight(.semibold))
                            .disabled(isCheckingModelAvailability)
                            .help("Check OpenRouter model availability without using credits")
                        }
                    }
                    .padding(.top, 8)
                }
            }
        }
        .task {
            await refreshModelAvailability()
        }
    }

    private var styleReferencePath: String {
        AuthorStyleReference.writableReferenceURL.path
    }

    private var learnedPreferencesPath: String {
        AuthorStyleReference.learnedPreferencesURL.path
    }

    @ViewBuilder
    private func modelPicker(
        title: String,
        selection: Binding<String>,
        description: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(title)
                    .font(.caption.weight(.semibold))
                Spacer()
                modelAvailabilityBadge(for: selection.wrappedValue)
                Picker(title, selection: selection) {
                    ForEach(InferenceSettings.availableModels) { model in
                        Text(model.name).tag(model.id)
                    }
                    if InferenceSettings.modelOption(for: selection.wrappedValue) == nil {
                        Text("Previous custom model").tag(selection.wrappedValue)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .frame(width: 250)
            }

            Text(description)
                .settingsDescriptionStyle()

            if InferenceSettings.modelOption(for: selection.wrappedValue) == nil {
                Text(selection.wrappedValue)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
        }
    }

    private func modelAvailabilityBadge(for modelID: String) -> some View {
        let status = modelAvailability[modelID]
        let label: String
        let systemImage: String
        let color: Color

        switch status {
        case .online:
            label = "Online"
            systemImage = "circle.fill"
            color = .green
        case .available:
            label = "Available"
            systemImage = "circle"
            color = .green
        case .offline:
            label = "Offline"
            systemImage = "exclamationmark.circle.fill"
            color = .red
        case .unknown:
            label = "Unknown"
            systemImage = "questionmark.circle"
            color = .secondary
        case nil:
            label = isCheckingModelAvailability ? "Checking" : "Unknown"
            systemImage = isCheckingModelAvailability ? "clock" : "questionmark.circle"
            color = .secondary
        }

        return Label(label, systemImage: systemImage)
            .font(.caption2)
            .foregroundStyle(color)
            .help("Free OpenRouter availability check; no model request is sent")
    }

    @MainActor
    private func refreshModelAvailability(forceRefresh: Bool = false) async {
        guard !isCheckingModelAvailability else { return }
        isCheckingModelAvailability = true
        let statuses = await OpenRouterModelAvailabilityService.shared.statuses(
            for: InferenceSettings.availableModels.map(\.id),
            forceRefresh: forceRefresh
        )
        guard !Task.isCancelled else {
            isCheckingModelAvailability = false
            return
        }
        modelAvailability = statuses
        isCheckingModelAvailability = false
    }

    private var styleProposalSheet: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Proposed Style Profile")
                .font(.headline)

            Text("Review or edit this compact profile before approving. Approval marks \(proposalEventIDs.count) evidence item\(proposalEventIDs.count == 1 ? "" : "s") as processed.")
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
                Button("Later") {
                    showStyleProposal = false
                }
                Button("Approve") {
                    Task { await approveStyleProposal() }
                }
                .buttonStyle(.borderedProminent)
                .disabled(proposedLearnedPreferences.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 760, height: 620)
    }

    private func pasteOpenRouterKeyFromClipboard() {
        guard let clipboardString = NSPasteboard.general.string(forType: .string) else { return }
        openRouterKey = clipboardString.trimmingCharacters(in: .whitespacesAndNewlines)
        openRouterConnectionError = ""
        openRouterConnectionRequiresBilling = false
    }

    @MainActor
    private func saveOpenRouterKey() async {
        openRouterKey = openRouterKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !openRouterKey.isEmpty, !isValidatingOpenRouterKey else { return }

        isValidatingOpenRouterKey = true
        openRouterConnectionError = ""
        openRouterConnectionRequiresBilling = false
        openRouterSaved = false
        defer { isValidatingOpenRouterKey = false }

        do {
            try await openRouterConnectionValidator.validate(apiKey: openRouterKey)
            guard APIKeyStore.shared.setAPIKey(openRouterKey, service: "openrouter") else {
                openRouterConnectionError = "The key worked, but it could not be stored securely on this Mac."
                return
            }

            openRouterKey = ""
            openRouterConnected = true
            openRouterSaved = true
            NotificationCenter.default.post(name: .openRouterConnectionChanged, object: nil)
            Task { await StyleProfileRefinementCoordinator.shared.prepareIfNeeded() }
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                openRouterSaved = false
            }
        } catch is CancellationError {
            return
        } catch let error as OpenRouterConnectionValidator.ValidationError {
            openRouterConnectionRequiresBilling = error == .billingRequired
            openRouterConnectionError = error.localizedDescription
        } catch {
            openRouterConnectionError = error.localizedDescription
        }
    }

    private func disconnectOpenRouter() {
        APIKeyStore.shared.deleteAPIKey(service: "openrouter")
        openRouterKey = ""
        openRouterConnected = false
        openRouterSaved = false
        openRouterConnectionError = ""
        openRouterConnectionRequiresBilling = false
        NotificationCenter.default.post(name: .openRouterConnectionChanged, object: nil)
    }

    private func replayFeatureTour() {
        NSApp.keyWindow?.close()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            NotificationCenter.default.post(name: .showFeatureTour, object: nil)
        }
    }

    private func revealPersonalizationData() {
        let url = ShakespeareStorage.rootURL
        try? ShakespeareStorage.prepare()
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    private func importWritingSamples(_ result: Result<[URL], Error>) {
        writingSampleImportFailed = false
        guard case let .success(urls) = result else {
            if case let .failure(error) = result,
               (error as NSError).code != NSUserCancelledError {
                writingSampleImportFailed = true
                writingSampleImportMessage = error.localizedDescription
            }
            return
        }

        let importResult = WritingSampleImporter.importFiles(urls)
        writingSampleImportFailed = importResult.isFailure
        writingSampleImportMessage = importResult.message
        refreshStyleContext()
        if importResult.imported > 0 {
            Task { await StyleProfileRefinementCoordinator.shared.prepareIfNeeded() }
        }
    }

    private func deleteTrainingEvents() {
        do {
            try TrainingEventStore.shared.deleteAll()
            refreshStyleContext()
            Task { await refreshPreparedStyleDraft() }
        } catch {
            styleUpdateError = error.localizedDescription
        }
    }

    private func refreshStyleContext() {
        _ = AuthorStyleReference.content
        personalizationReadiness = TrainingEventStore.shared.readiness()
        pendingProfileEvidenceCount = TrainingEventStore.shared.pendingProfileEvidenceCount()
        learnedPreferencesPreview = AuthorStyleReference.learnedPreferences
            .trimmingCharacters(in: .whitespacesAndNewlines)
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
            let draft = try await StyleProfileRefinementCoordinator.shared.prepareNow()
            preparedStyleDraft = draft
            presentStyleDraft(draft, currentProfile: current)
        } catch {
            styleUpdateError = error.localizedDescription
        }
    }

    @MainActor
    private func approveStyleProposal() async {
        do {
            try await StyleProfileRefinementCoordinator.shared.approve(
                proposedMarkdown: proposedLearnedPreferences,
                eventIDs: proposalEventIDs
            )
            showStyleProposal = false
            preparedStyleDraft = nil
            proposedLearnedPreferences = ""
            proposedLearnedPreferencesDiff = ""
            proposalEventIDs = []
            refreshStyleContext()
        } catch {
            styleUpdateError = error.localizedDescription
        }
    }

    @MainActor
    private func refreshPreparedStyleDraft() async {
        preparedStyleDraft = await StyleProfileRefinementCoordinator.shared.preparedDraft()
    }

    private func presentStyleDraft(
        _ draft: StyleProfileDraft,
        currentProfile: String = AuthorStyleReference.learnedPreferences
    ) {
        proposedLearnedPreferences = draft.proposedMarkdown
        proposedLearnedPreferencesDiff = StyleGuideUpdater.unifiedDiff(
            old: currentProfile,
            new: draft.proposedMarkdown
        )
        proposalEventIDs = draft.eventIDs
        showStyleProposal = true
    }
}

private struct SettingsCard<Content: View>: View {
    let title: String
    let content: Content

    init(title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.headline.weight(.semibold))
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(
            Color(nsColor: .controlBackgroundColor),
            in: RoundedRectangle(cornerRadius: 12, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        }
    }
}

private struct SettingsPage<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                content
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(24)
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

private struct SettingsPathRow: View {
    let title: String
    let path: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
            Text(path)
                .font(.system(.caption, design: .monospaced))
                .lineLimit(2)
                .truncationMode(.middle)
                .textSelection(.enabled)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
    }
}

private struct SettingsSlider: View {
    let title: String
    let valueLabel: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title)
                Spacer()
                Text(valueLabel)
                    .font(.callout.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            Slider(value: $value, in: range, step: step)
        }
    }
}

private struct SettingsToggle: View {
    let title: String
    let description: String
    @Binding var isOn: Bool

    var body: some View {
        Toggle(isOn: $isOn) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                Text(description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

private extension View {
    func settingsDescriptionStyle() -> some View {
        font(.callout)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}

extension Notification.Name {
    static let fontSettingsChanged = Notification.Name("fontSettingsChanged")
}
