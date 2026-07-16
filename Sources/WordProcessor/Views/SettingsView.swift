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
    @State private var isValidatingTinkerKey = false
    @State private var tinkerConnectionError = ""
    @State private var tinkerConnectionRequiresBilling = false
    @State private var showDisconnectConfirmation = false
    @State private var openRouterKey = ""
    @State private var showOpenRouterKey = false
    @State private var openRouterSaved = false
    @State private var openRouterConnected = false
    @State private var isValidatingOpenRouterKey = false
    @State private var openRouterConnectionError = ""
    @State private var openRouterConnectionRequiresBilling = false
    @State private var showOpenRouterDisconnectConfirmation = false
    @AppStorage(SettingsDestination.defaultsKey) private var selectedTab = SettingsDestination.apiKeys
    @AppStorage(InferenceSettings.tinkerModelDefaultsKey) private var tinkerModel = InferenceSettings.defaultTinkerModel
    @AppStorage(InferenceSettings.openRouterModelDefaultsKey) private var openRouterModel = InferenceSettings.defaultOpenRouterModel
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
    private let tinkerConnectionValidator = TinkerConnectionValidator()
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
            tinkerConnected = false
            tinkerConnected = APIKeyStore.shared.getAPIKey(service: "tinker") != nil
            openRouterConnected = APIKeyStore.shared.getAPIKey(service: "openrouter") != nil
            refreshStyleContext()
        }
        .onChange(of: personalizationEnabled) { _, enabled in
            PersonalizationSettings.isEnabled = enabled
            refreshStyleContext()
        }
        .onChange(of: tinkerKey) {
            tinkerConnectionError = ""
            tinkerConnectionRequiresBilling = false
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
        }
        .confirmationDialog(
            "Disconnect Inkling?",
            isPresented: $showDisconnectConfirmation,
            titleVisibility: .visible
        ) {
            Button("Disconnect", role: .destructive) { disconnectTinker() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes the saved Tinker API key from this Mac. The editor and local proofreading will keep working.")
        }
        .confirmationDialog(
            "Disconnect research chat?",
            isPresented: $showOpenRouterDisconnectConfirmation,
            titleVisibility: .visible
        ) {
            Button("Disconnect", role: .destructive) { disconnectOpenRouter() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes the saved OpenRouter API key from this Mac. Writing and personalization through Tinker are unaffected.")
        }
        .sheet(isPresented: $showStyleProposal) {
            styleProposalSheet
        }
    }

    private var myStyleSettings: some View {
        SettingsPage {
            SettingsCard(title: "How My Style Works") {
                Text("Shakespeare combines your editable style reference, preferences learned from saved edit outcomes, and—after evaluation—a personal Inkling checkpoint. Project context stays temporary and is never baked into your permanent voice profile.")
                    .settingsDescriptionStyle()
            }

            SettingsCard(title: "Learn From My Writing") {
                Toggle(isOn: $personalizationEnabled) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Learn from saved edits and documents")
                            .fontWeight(.medium)
                        Text("Off by default. Nothing is uploaded automatically.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Text("A suggestion is not treated as training data when you click Accept or Reject. Shakespeare waits until the document is saved, then records whether you kept, revised, reverted, or rewrote it.")
                    .settingsDescriptionStyle()

                Divider()

                HStack(alignment: .firstTextBaseline) {
                    Text(personalizationReadiness.status)
                        .fontWeight(.medium)
                    Spacer()
                    Text("\(personalizationReadiness.eligibleExampleCount) reliable examples")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                ProgressView(value: personalizationReadiness.progress)
                    .tint(.accentColor)

                HStack(spacing: 10) {
                    SettingsMetric(
                        value: personalizationReadiness.resolvedEditCount,
                        label: "Resolved edits",
                        systemImage: "checkmark.circle"
                    )
                    SettingsMetric(
                        value: personalizationReadiness.snapshotDocumentCount,
                        label: "Documents",
                        systemImage: "doc.text"
                    )
                }
            }

            SettingsCard(title: "What Shakespeare Learned") {
                HStack {
                    Label("New style signals", systemImage: "waveform.path.ecg")
                    Spacer()
                    Text("\(pendingStyleDecisionCount)")
                        .font(.callout.monospacedDigit().weight(.semibold))
                        .foregroundStyle(pendingStyleDecisionCount >= 20 ? .orange : .secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(.quaternary, in: Capsule())
                }

                Text("Only repeated, high-confidence voice, tone, clarity, structure, concision, and style outcomes are proposed as durable preferences. You review every profile update before it becomes active.")
                    .settingsDescriptionStyle()

                Button {
                    Task { await updateStylePreferences() }
                } label: {
                    if isUpdatingStylePreferences {
                        HStack(spacing: 6) {
                            ProgressView().controlSize(.small)
                            Text("Reviewing…")
                        }
                    } else {
                        Text("Review Learned Preferences")
                    }
                }
                .disabled(isUpdatingStylePreferences || pendingStyleDecisionCount == 0)

                if !learnedPreferencesPreview.isEmpty {
                    Text(learnedPreferencesPreview)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(5)
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

            SettingsCard(title: "Personal Model") {
                if let checkpoint = activeCheckpoint {
                    Label("Active and evaluated", systemImage: "checkmark.seal.fill")
                        .foregroundStyle(.green)
                    SettingsPathRow(title: "Active checkpoint", path: checkpoint)
                    Button("Use Untuned Inkling") {
                        deactivatePersonalModel()
                    }
                } else {
                    HStack {
                        Label("Status", systemImage: "cpu")
                        Spacer()
                        Text(personalizationReadiness.isTrainingReady ? "Ready to train" : "Collecting evidence")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(personalizationReadiness.isTrainingReady ? .green : .secondary)
                    }
                }

                Text("Training creates a candidate LoRA checkpoint. It only becomes active after a held-out evaluation report passes and you explicitly promote it.")
                    .settingsDescriptionStyle()
            }

            SettingsCard(title: "Files and Privacy") {
                SettingsPathRow(title: "Style reference", path: styleReferencePath)
                SettingsPathRow(title: "Learned preferences", path: learnedPreferencesPath)

                Divider()

                HStack {
                    Label("Local learning events", systemImage: "internaldrive")
                    Spacer()
                    Text("\(personalizationReadiness.eventCount)")
                        .font(.callout.monospacedDigit())
                        .foregroundStyle(.secondary)
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
    }

    private var typographySettings: some View {
        SettingsPage {
            SettingsCard(title: "Document Typography") {
                Picker("Font family", selection: $fontManager.currentFont) {
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

                Text("Typography applies to the editor and is saved for future documents.")
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
                    title: "Check grammar while typing",
                    description: "Changed paragraphs are checked with the configured language-model provider.",
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
                    textCheckingSettings.resetDictionary()
                }
            }
        }
    }

    private var connectionsSettings: some View {
        SettingsPage {
            SettingsCard(title: "Writing — Tinker & Inkling") {
                    Label(
                        tinkerConnected ? "Connected and ready" : "Not connected",
                        systemImage: tinkerConnected ? "checkmark.circle.fill" : "circle.dashed"
                    )
                    .foregroundStyle(tinkerConnected ? .green : .secondary)

                    Text("One Tinker API key authenticates the Inkling writing assistant and Tinker training. There is no separate Inkling key.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if let checkpoint = activeCheckpoint {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Active personal checkpoint")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(checkpoint)
                                .font(.caption2)
                                .lineLimit(2)
                                .textSelection(.enabled)
                        }
                    }
                }

            SettingsCard(title: "Writing Connection") {
                    HStack {
                        Text("Tinker API key")
                            .font(.headline)
                        Spacer()
                        Link("Get a key ↗", destination: InferenceSettings.tinkerConsoleURL)
                            .font(.caption)
                    }

                    HStack {
                        if showKey {
                            TextField(
                                tinkerConnected ? "Paste a new key to replace the current one" : "Paste TINKER_API_KEY",
                                text: $tinkerKey
                            )
                                .textFieldStyle(.roundedBorder)
                        } else {
                            SecureField(
                                tinkerConnected ? "Paste a new key to replace the current one" : "Paste TINKER_API_KEY",
                                text: $tinkerKey
                            )
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
                    .disabled(isValidatingTinkerKey)

                    HStack {
                        Button(tinkerConnected ? "Update Connection" : "Connect") {
                            Task { await saveTinkerKey() }
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(
                            tinkerKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                            isValidatingTinkerKey
                        )

                        if tinkerConnected {
                            Button("Disconnect", role: .destructive) {
                                showDisconnectConfirmation = true
                            }
                            .disabled(isValidatingTinkerKey)
                        }

                        if isValidatingTinkerKey {
                            ProgressView()
                                .controlSize(.small)
                            Text("Checking Inkling…")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        if tinkerSaved {
                            Text("Connected")
                                .foregroundStyle(.green)
                                .font(.caption)
                        }
                    }

                    if tinkerConnectionRequiresBilling {
                        TinkerBillingNotice(
                            message: "This key is valid, but Inkling cannot connect until the Tinker account has payment information or credits."
                        )
                    } else if !tinkerConnectionError.isEmpty {
                        Label(tinkerConnectionError, systemImage: "exclamationmark.triangle.fill")
                            .font(.caption)
                            .foregroundStyle(.red)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Text("The key is checked against Inkling before it is stored in secure local credential storage.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

            SettingsCard(title: "Research Chat — OpenRouter") {
                Label(
                    openRouterConnected ? "Connected and ready" : "Not connected",
                    systemImage: openRouterConnected ? "checkmark.circle.fill" : "circle.dashed"
                )
                .foregroundStyle(openRouterConnected ? .green : .secondary)

                Text("OpenRouter powers only the research sidebar. Shakespeare uses Perplexity Sonar by default for fast, economical web answers with source links.")
                    .settingsDescriptionStyle()

                Label("Writing and personal style data stay on the Tinker path", systemImage: "arrow.triangle.branch")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            SettingsCard(title: "Research Chat Connection") {
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

                    Button {
                        showOpenRouterKey.toggle()
                    } label: {
                        Image(systemName: showOpenRouterKey ? "eye.slash" : "eye")
                    }
                    .help(showOpenRouterKey ? "Hide API Key" : "Show API Key")
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
                            Text("This key is valid, but OpenRouter needs credits before research chat can run.")
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

                Text("The key is validated before it is stored in macOS Keychain. Research questions and the relevant draft context are sent to OpenRouter only when you use chat.")
                    .settingsDescriptionStyle()
            }

            SettingsCard(title: "Advanced") {
                DisclosureGroup("Model configuration") {
                    VStack(alignment: .leading, spacing: 12) {
                        VStack(alignment: .leading, spacing: 5) {
                            Text("Writing model").font(.caption.weight(.semibold))
                            TextField("Inkling base model", text: $tinkerModel)
                                .textFieldStyle(.roundedBorder)
                            Text("An evaluated and promoted personal checkpoint overrides this base model automatically.")
                                .settingsDescriptionStyle()
                        }

                        Divider()

                        VStack(alignment: .leading, spacing: 5) {
                            Text("Research chat model").font(.caption.weight(.semibold))
                            TextField("OpenRouter model", text: $openRouterModel)
                                .textFieldStyle(.roundedBorder)
                            Text("The default, perplexity/sonar, prioritizes speed, low cost, and cited web answers.")
                                .settingsDescriptionStyle()
                        }
                    }
                    .padding(.top, 8)
                }
            }
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
        tinkerConnectionError = ""
        tinkerConnectionRequiresBilling = false
    }

    @MainActor
    private func saveTinkerKey() async {
        tinkerKey = tinkerKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !tinkerKey.isEmpty, !isValidatingTinkerKey else { return }

        isValidatingTinkerKey = true
        tinkerConnectionError = ""
        tinkerConnectionRequiresBilling = false
        tinkerSaved = false
        defer { isValidatingTinkerKey = false }

        do {
            try await tinkerConnectionValidator.validate(apiKey: tinkerKey)
            guard APIKeyStore.shared.setAPIKey(tinkerKey, service: "tinker") else {
                tinkerConnectionError = "The key worked, but it could not be stored securely on this Mac."
                return
            }
            tinkerKey = ""
            tinkerConnected = true
            tinkerSaved = true
            NotificationCenter.default.post(name: .inklingConnectionChanged, object: nil)
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                tinkerSaved = false
            }
        } catch is CancellationError {
            return
        } catch let error as TinkerConnectionValidator.ValidationError {
            tinkerConnectionRequiresBilling = error == .billingRequired
            tinkerConnectionError = error.localizedDescription
        } catch {
            tinkerConnectionError = error.localizedDescription
        }
    }

    private func disconnectTinker() {
        APIKeyStore.shared.deleteAPIKey(service: "tinker")
        tinkerKey = ""
        tinkerConnected = false
        tinkerSaved = false
        tinkerConnectionError = ""
        tinkerConnectionRequiresBilling = false
        NotificationCenter.default.post(name: .inklingConnectionChanged, object: nil)
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

private struct SettingsMetric: View {
    let value: Int
    let label: String
    let systemImage: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: systemImage)
                .foregroundStyle(.secondary)
            Text("\(value)")
                .font(.callout.monospacedDigit().weight(.semibold))
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
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
