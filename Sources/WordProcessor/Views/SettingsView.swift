import AppKit
import SwiftUI

struct SettingsView: View {
    @State private var anthropicKey = ""
    @State private var showKey = false
    @State private var saved = false
    @State private var pendingStyleDecisionCount = 0
    @State private var learnedPreferencesPreview = ""
    @State private var proposedLearnedPreferences = ""
    @State private var proposedLearnedPreferencesDiff = ""
    @State private var proposalEventIDs: [String] = []
    @State private var isUpdatingStylePreferences = false
    @State private var styleUpdateError = ""
    @State private var showStyleProposal = false

    // Font settings
    @State private var fontManager = FontManager.shared
    @State private var textCheckingSettings = TextCheckingSettings.shared
    private let styleGuideUpdater = StyleGuideUpdater()

    var body: some View {
        TabView {
            // API Keys tab
            Form {
                Section("Anthropic API Key") {
                    HStack {
                        if showKey {
                            TextField("sk-ant-...", text: $anthropicKey)
                                .textFieldStyle(.roundedBorder)
                        } else {
                            SecureField("sk-ant-...", text: $anthropicKey)
                                .textFieldStyle(.roundedBorder)
                        }
                        Button {
                            pasteAnthropicKeyFromClipboard()
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
                        Button("Save") {
                            saveAnthropicKey()
                        }
                        if saved {
                            Text("Saved!")
                                .foregroundStyle(.green)
                                .font(.caption)
                        }
                    }
                }

                Section {
                    Text("Your API key is stored securely in the macOS Keychain.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .tabItem { Label("API Keys", systemImage: "key") }

            Form {
                Section("Style Reference") {
                    Text("Claude uses a fixed David Oks sentence and paragraph style guide as its voice reference when drafting or rewriting. The current document is still sent for topic, continuity, and edit targeting.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    LabeledContent("Reference File") {
                        Text(styleReferencePath)
                            .font(.caption2)
                            .textSelection(.enabled)
                    }

                    LabeledContent("Learned Preferences") {
                        Text(learnedPreferencesPath)
                            .font(.caption2)
                            .textSelection(.enabled)
                    }
                }

                Section("Adaptive Preferences") {
                    LabeledContent("Unprocessed Feedback") {
                        Text("\(pendingStyleDecisionCount)")
                            .font(.caption)
                            .foregroundStyle(pendingStyleDecisionCount >= 20 ? .orange : .secondary)
                    }

                    Button {
                        Task { await updateStylePreferences() }
                    } label: {
                        if isUpdatingStylePreferences {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Text("Update style preferences from edit history")
                        }
                    }
                    .disabled(isUpdatingStylePreferences || pendingStyleDecisionCount == 0)

                    if !styleUpdateError.isEmpty {
                        Text(styleUpdateError)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }

                    if !learnedPreferencesPreview.isEmpty {
                        Text(learnedPreferencesPreview)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(6)
                            .textSelection(.enabled)
                    }
                }
            }
            .tabItem { Label("Style Context", systemImage: "text.book.closed") }

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

            Form {
                Section("Spelling and Grammar") {
                    Toggle("Check spelling while typing", isOn: Binding(
                        get: { textCheckingSettings.continuousSpellCheckingEnabled },
                        set: { textCheckingSettings.continuousSpellCheckingEnabled = $0 }
                    ))

                    Toggle("Check grammar with spelling", isOn: Binding(
                        get: { textCheckingSettings.grammarCheckingEnabled },
                        set: { textCheckingSettings.grammarCheckingEnabled = $0 }
                    ))

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
                    Text("These settings use macOS and WebKit text checking for the editor.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .tabItem { Label("Editing", systemImage: "checkmark.circle") }
        }
        .frame(width: 500, height: 420)
        .onAppear {
            if let key = KeychainService.shared.getAPIKey(service: "anthropic") {
                anthropicKey = key
            }
            refreshStyleContext()
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

    private func pasteAnthropicKeyFromClipboard() {
        guard let clipboardString = NSPasteboard.general.string(forType: .string) else { return }
        anthropicKey = normalizedAnthropicKey(from: clipboardString)
    }

    private func saveAnthropicKey() {
        anthropicKey = normalizedAnthropicKey(from: anthropicKey)
        guard KeychainService.shared.setAPIKey(anthropicKey, service: "anthropic") else { return }
        saved = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            saved = false
        }
    }

    private func normalizedAnthropicKey(from rawValue: String) -> String {
        let trimmedValue = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let keyPattern = #"sk-ant-[A-Za-z0-9_\-]+"#

        if let match = trimmedValue.range(of: keyPattern, options: .regularExpression) {
            return String(trimmedValue[match])
        }

        return trimmedValue
    }

    private func refreshStyleContext() {
        _ = AuthorStyleReference.content
        pendingStyleDecisionCount = StyleFeedbackStore.shared.pendingDecisionCount()
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
