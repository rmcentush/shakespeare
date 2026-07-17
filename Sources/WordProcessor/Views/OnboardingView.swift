import AppKit
import SwiftUI
import UniformTypeIdentifiers

enum OnboardingSettings {
    static let completedVersionKey = "onboardingCompletedVersion"
    static let currentVersion = 4
    @MainActor private static var presentingWindowID: UUID?

    static var shouldPresent: Bool {
        UserDefaults.standard.integer(forKey: completedVersionKey) < currentVersion
    }

    static func markCompleted() {
        UserDefaults.standard.set(currentVersion, forKey: completedVersionKey)
    }

    @MainActor
    static func claimPresentation(for windowID: UUID) -> Bool {
        guard presentingWindowID == nil || presentingWindowID == windowID else { return false }
        presentingWindowID = windowID
        return true
    }

    @MainActor
    static func releasePresentation(for windowID: UUID) {
        guard presentingWindowID == windowID else { return }
        presentingWindowID = nil
    }
}

struct OnboardingView: View {
    let onFinish: () -> Void
    let onOpenDocument: () -> Void

    @State private var apiKey = ""
    @State private var hasKey = false
    @State private var isReplacingKey = false
    @State private var isConnecting = false
    @State private var connectionError = ""
    @State private var requiresBilling = false
    @State private var personalizationEnabled = true
    @State private var connectionTask: Task<Void, Never>?
    @State private var showWritingSampleImporter = false
    @State private var writingSampleImportMessage = ""
    @State private var writingSampleImportFailed = false
    @FocusState private var keyFieldFocused: Bool

    private let validator = OpenRouterConnectionValidator()

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            content
            Divider()
            footer
        }
        .frame(width: 640)
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear {
            hasKey = APIKeyStore.shared.hasAPIKey(service: "openrouter")
            personalizationEnabled = PersonalizationSettings.isEnabled
            focusKeyIfNeeded()
        }
        .onChange(of: personalizationEnabled) { _, enabled in
            PersonalizationSettings.isEnabled = enabled
        }
        .onDisappear {
            connectionTask?.cancel()
            connectionTask = nil
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
    }

    private var header: some View {
        HStack(spacing: 14) {
            ShakespeareMark()
            VStack(alignment: .leading, spacing: 3) {
                Text("Set up Shakespeare")
                    .font(.system(size: 15, weight: .semibold))
                Text("One key. Writing that sounds like you.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 16)
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 14) {
            credentialCard
            personalizationCard

            PrivacyNote(text: "Your key stays securely on this Mac. Style data stays here too; only short excerpts are sent for writing help. OpenRouter bills usage.")

        }
        .padding(.horizontal, 28)
        .padding(.top, 18)
        .padding(.bottom, 14)
    }

    private var personalizationCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Toggle(isOn: $personalizationEnabled) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("2. Make it sound like me").font(.headline)
                    Text("Learns from rewrites you save.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            HStack {
                Text("Add samples for a faster start.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
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
            }
        }
        .credentialCardStyle()
    }

    @ViewBuilder
    private var credentialCard: some View {
        if hasKey && !isReplacingKey {
            ConnectedCredentialCard(
                title: "1. OpenRouter connected",
                detail: "Writing and web research are ready.",
                onReplace: {
                    connectionError = ""
                    requiresBilling = false
                    isReplacingKey = true
                    focusKeyIfNeeded()
                }
            )
        } else {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("1. OpenRouter key").font(.headline)
                    Spacer()
                    Link("Get a key ↗", destination: InferenceSettings.openRouterKeysURL).font(.caption)
                }

                HStack(spacing: 8) {
                    SecureField("Paste OPENROUTER_API_KEY", text: $apiKey)
                        .textFieldStyle(.roundedBorder)
                        .focused($keyFieldFocused)
                        .disabled(isConnecting)
                        .onChange(of: apiKey) {
                            connectionError = ""
                            requiresBilling = false
                        }
                        .onSubmit { connect() }

                    Button {
                        guard let value = NSPasteboard.general.string(forType: .string) else { return }
                        apiKey = value.trimmingCharacters(in: .whitespacesAndNewlines)
                    } label: {
                        Label("Paste", systemImage: "doc.on.clipboard")
                    }
                    .disabled(isConnecting)
                }

                connectionFeedback
            }
            .credentialCardStyle()
        }
    }

    @ViewBuilder
    private var connectionFeedback: some View {
        if isConnecting {
            HStack(spacing: 7) {
                ProgressView().controlSize(.small)
                Text("Checking OpenRouter access…").font(.caption).foregroundStyle(.secondary)
            }
        } else if requiresBilling {
            VStack(alignment: .leading, spacing: 5) {
                Label("This key is valid, but OpenRouter needs credits before model-powered features can run.", systemImage: "creditcard.trianglebadge.exclamationmark.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
                Link("Add OpenRouter credits ↗", destination: InferenceSettings.openRouterCreditsURL)
                    .font(.caption.weight(.semibold))
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.orange.opacity(0.09), in: RoundedRectangle(cornerRadius: 9))
        } else if !connectionError.isEmpty {
            Label(connectionError, systemImage: "exclamationmark.triangle.fill")
                .font(.caption)
                .foregroundStyle(.red)
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.red.opacity(0.075), in: RoundedRectangle(cornerRadius: 9))
        } else {
            Text("Shakespeare validates the connection before saving the key.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var footer: some View {
        HStack(spacing: 10) {
            Button("Skip for Now") { finish() }
            Button("Open Document") {
                cancelConnection()
                OnboardingSettings.markCompleted()
                onOpenDocument()
            }
            Spacer()

            if hasKey && !isReplacingKey {
                Button("Start Writing") { finish() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            } else {
                Button("Connect & Start Writing") { connect() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isConnecting)
            }
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 14)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.45))
    }

    private func connect() {
        let normalized = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty, !isConnecting else { return }
        isConnecting = true
        connectionError = ""
        requiresBilling = false

        connectionTask?.cancel()
        connectionTask = Task { @MainActor in
            defer {
                isConnecting = false
                connectionTask = nil
            }
            do {
                try await validator.validate(apiKey: normalized)
                try Task.checkCancellation()
                guard APIKeyStore.shared.setAPIKey(normalized, service: "openrouter") else {
                    connectionError = "The key worked, but it could not be stored securely on this Mac."
                    return
                }
                apiKey = ""
                hasKey = true
                isReplacingKey = false
                NotificationCenter.default.post(name: .openRouterConnectionChanged, object: nil)
                Task { await StyleProfileRefinementCoordinator.shared.prepareIfNeeded() }
                isConnecting = false
                connectionTask = nil
                finish()
            } catch is CancellationError {
                return
            } catch let error as OpenRouterConnectionValidator.ValidationError {
                requiresBilling = error == .billingRequired
                connectionError = error.localizedDescription
            } catch {
                connectionError = error.localizedDescription
            }
        }
    }

    private func focusKeyIfNeeded() {
        guard !hasKey || isReplacingKey else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { keyFieldFocused = true }
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
        PersonalizationSettings.isEnabled = personalizationEnabled
        let importResult = WritingSampleImporter.importFiles(urls)
        writingSampleImportFailed = importResult.isFailure
        writingSampleImportMessage = importResult.message
        if importResult.imported > 0 {
            Task { await StyleProfileRefinementCoordinator.shared.prepareIfNeeded() }
        }
    }

    private func finish() {
        cancelConnection()
        OnboardingSettings.markCompleted()
        onFinish()
    }

    private func cancelConnection() {
        connectionTask?.cancel()
        connectionTask = nil
        isConnecting = false
    }
}

private struct ShakespeareMark: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.accentColor.gradient)
            Text("S").font(.system(size: 20, weight: .semibold, design: .serif)).foregroundStyle(.white)
        }
        .frame(width: 42, height: 42)
        .accessibilityHidden(true)
    }
}

private struct ConnectedCredentialCard: View {
    let title: String
    let detail: String
    let onReplace: () -> Void

    var body: some View {
        HStack(spacing: 13) {
            Image(systemName: "checkmark.circle.fill").font(.title2).foregroundStyle(.green)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.headline)
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Button("Replace Key", action: onReplace)
        }
        .padding(16)
        .background(Color.green.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
        .overlay { RoundedRectangle(cornerRadius: 12).stroke(Color.green.opacity(0.14), lineWidth: 1) }
    }
}

private struct PrivacyNote: View {
    let text: String
    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "hand.raised").foregroundStyle(.secondary).frame(width: 18)
            Text(text)
                .font(.caption)
                .lineSpacing(2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private extension View {
    func credentialCardStyle() -> some View {
        padding(16)
            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 14))
            .overlay { RoundedRectangle(cornerRadius: 14).stroke(Color.primary.opacity(0.07), lineWidth: 1) }
    }
}

extension Notification.Name {
    static let showOnboarding = Notification.Name("showOnboarding")
    static let openRouterConnectionChanged = Notification.Name("openRouterConnectionChanged")
}
