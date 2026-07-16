import AppKit
import SwiftUI

enum OnboardingSettings {
    static let completedVersionKey = "onboardingCompletedVersion"
    static let currentVersion = 2
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

private enum OnboardingStep: Int {
    case writing = 1
    case research = 2
}

struct OnboardingView: View {
    let onFinish: () -> Void
    let onOpenDocument: () -> Void

    @State private var step: OnboardingStep = .writing

    @State private var tinkerKey = ""
    @State private var hasTinkerKey = false
    @State private var isReplacingTinkerKey = false
    @State private var isConnectingTinker = false
    @State private var tinkerError = ""
    @State private var tinkerRequiresBilling = false

    @State private var openRouterKey = ""
    @State private var hasOpenRouterKey = false
    @State private var isReplacingOpenRouterKey = false
    @State private var isConnectingOpenRouter = false
    @State private var openRouterError = ""
    @State private var openRouterRequiresBilling = false

    @FocusState private var focusedField: OnboardingStep?

    private let tinkerValidator = TinkerConnectionValidator()
    private let openRouterValidator = OpenRouterConnectionValidator()

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            content
            Divider()
            footer
        }
        .frame(width: 740, height: 610)
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear {
            hasTinkerKey = APIKeyStore.shared.getAPIKey(service: "tinker") != nil
            hasOpenRouterKey = APIKeyStore.shared.getAPIKey(service: "openrouter") != nil
            step = hasTinkerKey ? .research : .writing
            focusCurrentFieldIfNeeded()
        }
        .onChange(of: step) {
            focusCurrentFieldIfNeeded()
        }
    }

    private var header: some View {
        HStack(spacing: 14) {
            ShakespeareMark()

            VStack(alignment: .leading, spacing: 3) {
                Text("Welcome to Shakespeare")
                    .font(.system(size: 15, weight: .semibold))
                Text("Two focused connections. One calm workspace.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            HStack(spacing: 8) {
                StepIndicator(
                    number: 1,
                    title: "Writing",
                    isActive: step == .writing,
                    isComplete: hasTinkerKey
                )
                Rectangle()
                    .fill(Color.primary.opacity(0.12))
                    .frame(width: 24, height: 1)
                StepIndicator(
                    number: 2,
                    title: "Research",
                    isActive: step == .research,
                    isComplete: hasOpenRouterKey
                )
            }
        }
        .padding(.horizontal, 32)
        .padding(.vertical, 18)
    }

    @ViewBuilder
    private var content: some View {
        switch step {
        case .writing:
            writingContent
        case .research:
            researchContent
        }
    }

    private var writingContent: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Connect your writing engine.")
                    .font(.system(size: 31, weight: .semibold, design: .serif))
                Text("One Tinker API key powers Inkling writing help today and your opt-in personal model training later.")
                    .onboardingDescription()
            }

            HStack(spacing: 10) {
                ConnectionCapability(icon: "sparkles", title: "Inkling", detail: "Draft and revise")
                ConnectionCapability(icon: "person.text.rectangle", title: "Personal training", detail: "Only when you opt in")
                ConnectionCapability(icon: "checkmark.shield", title: "Secure", detail: "Stored in Keychain")
            }

            tinkerCredentialCard

            PrivacyNote(
                text: "Writing requests go to Tinker only when you use model-powered writing features. Connecting a key never enables style learning by itself."
            )

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 32)
        .padding(.top, 23)
        .padding(.bottom, 18)
    }

    private var researchContent: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text("Research without leaving the draft.")
                        .font(.system(size: 31, weight: .semibold, design: .serif))
                    Text("OPTIONAL")
                        .font(.system(size: 9.5, weight: .bold))
                        .kerning(0.7)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.primary.opacity(0.055), in: Capsule())
                }
                Text("OpenRouter powers the research sidebar. Shakespeare defaults to Perplexity Sonar for fast, economical web answers with source links.")
                    .onboardingDescription()
            }

            HStack(spacing: 10) {
                ConnectionCapability(icon: "globe.americas", title: "Live web", detail: "Current information")
                ConnectionCapability(icon: "link", title: "Sources", detail: "Links in answers")
                ConnectionCapability(icon: "bolt", title: "Sonar", detail: "Fast and low cost")
            }

            openRouterCredentialCard

            PrivacyNote(
                text: "Only research-chat questions and relevant draft context go to OpenRouter. Your style profile, training ledger, and Tinker credentials are never sent with chat requests."
            )

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 32)
        .padding(.top, 23)
        .padding(.bottom, 18)
    }

    @ViewBuilder
    private var tinkerCredentialCard: some View {
        if hasTinkerKey && !isReplacingTinkerKey {
            ConnectedCredentialCard(
                title: "Inkling is ready",
                detail: "A Tinker API key is saved in secure local credential storage.",
                onReplace: {
                    tinkerError = ""
                    tinkerRequiresBilling = false
                    isReplacingTinkerKey = true
                    focusedField = .writing
                }
            )
        } else {
            VStack(alignment: .leading, spacing: 10) {
                credentialHeader(
                    title: "Tinker API key",
                    linkTitle: "Get a key ↗",
                    destination: InferenceSettings.tinkerConsoleURL
                )

                HStack(spacing: 8) {
                    SecureField("Paste TINKER_API_KEY", text: $tinkerKey)
                        .textFieldStyle(.roundedBorder)
                        .focused($focusedField, equals: .writing)
                        .disabled(isConnectingTinker)
                        .onChange(of: tinkerKey) {
                            tinkerError = ""
                            tinkerRequiresBilling = false
                        }
                        .onSubmit { connectTinker() }

                    pasteButton(into: $tinkerKey)
                        .disabled(isConnectingTinker)
                }

                connectionFeedback(
                    isConnecting: isConnectingTinker,
                    checkingText: "Checking Inkling access…",
                    error: tinkerError,
                    requiresBilling: tinkerRequiresBilling,
                    billingText: "This key is valid, but Tinker won’t serve Inkling until the account has payment information or credits.",
                    billingURL: InferenceSettings.tinkerBillingURL,
                    billingLinkText: "Open Tinker billing ↗"
                )
            }
            .credentialCardStyle()
        }
    }

    @ViewBuilder
    private var openRouterCredentialCard: some View {
        if hasOpenRouterKey && !isReplacingOpenRouterKey {
            ConnectedCredentialCard(
                title: "Research chat is ready",
                detail: "An OpenRouter API key is saved in secure local credential storage.",
                onReplace: {
                    openRouterError = ""
                    openRouterRequiresBilling = false
                    isReplacingOpenRouterKey = true
                    focusedField = .research
                }
            )
        } else {
            VStack(alignment: .leading, spacing: 10) {
                credentialHeader(
                    title: "OpenRouter API key",
                    linkTitle: "Get a key ↗",
                    destination: InferenceSettings.openRouterKeysURL
                )

                HStack(spacing: 8) {
                    SecureField("Paste OPENROUTER_API_KEY", text: $openRouterKey)
                        .textFieldStyle(.roundedBorder)
                        .focused($focusedField, equals: .research)
                        .disabled(isConnectingOpenRouter)
                        .onChange(of: openRouterKey) {
                            openRouterError = ""
                            openRouterRequiresBilling = false
                        }
                        .onSubmit { connectOpenRouter() }

                    pasteButton(into: $openRouterKey)
                        .disabled(isConnectingOpenRouter)
                }

                connectionFeedback(
                    isConnecting: isConnectingOpenRouter,
                    checkingText: "Checking OpenRouter access…",
                    error: openRouterError,
                    requiresBilling: openRouterRequiresBilling,
                    billingText: "This key is valid, but OpenRouter needs credits before research chat can run.",
                    billingURL: InferenceSettings.openRouterCreditsURL,
                    billingLinkText: "Add OpenRouter credits ↗"
                )
            }
            .credentialCardStyle()
        }
    }

    private var footer: some View {
        HStack(spacing: 10) {
            if step == .research {
                Button("Back") {
                    step = .writing
                }
                .disabled(isBusy)
            } else {
                Button("Set Up Later") {
                    finish()
                }
                .disabled(isBusy)
            }

            Button("Open a Document") {
                OnboardingSettings.markCompleted()
                onOpenDocument()
            }
            .disabled(isBusy)

            Spacer()

            switch step {
            case .writing:
                if hasTinkerKey && !isReplacingTinkerKey {
                    Button("Continue") { step = .research }
                        .buttonStyle(.borderedProminent)
                        .keyboardShortcut(.defaultAction)
                } else {
                    Button(tinkerKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Skip Writing" : "Connect & Continue") {
                        if tinkerKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            step = .research
                        } else {
                            connectTinker()
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(isConnectingTinker)
                }
            case .research:
                if hasOpenRouterKey && !isReplacingOpenRouterKey {
                    Button("Start Writing") { finish() }
                        .buttonStyle(.borderedProminent)
                        .keyboardShortcut(.defaultAction)
                } else {
                    Button(openRouterKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Skip Research" : "Connect & Finish") {
                        if openRouterKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            finish()
                        } else {
                            connectOpenRouter()
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(isConnectingOpenRouter)
                }
            }
        }
        .padding(.horizontal, 32)
        .padding(.vertical, 16)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.45))
    }

    private var isBusy: Bool {
        isConnectingTinker || isConnectingOpenRouter
    }

    private func credentialHeader(title: String, linkTitle: String, destination: URL) -> some View {
        HStack {
            Text(title).font(.headline)
            Spacer()
            Link(linkTitle, destination: destination).font(.caption)
        }
    }

    private func pasteButton(into binding: Binding<String>) -> some View {
        Button {
            guard let value = NSPasteboard.general.string(forType: .string) else { return }
            binding.wrappedValue = value.trimmingCharacters(in: .whitespacesAndNewlines)
        } label: {
            Label("Paste", systemImage: "doc.on.clipboard")
        }
    }

    @ViewBuilder
    private func connectionFeedback(
        isConnecting: Bool,
        checkingText: String,
        error: String,
        requiresBilling: Bool,
        billingText: String,
        billingURL: URL,
        billingLinkText: String
    ) -> some View {
        if isConnecting {
            HStack(spacing: 7) {
                ProgressView().controlSize(.small)
                Text(checkingText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } else if requiresBilling {
            VStack(alignment: .leading, spacing: 5) {
                Label(billingText, systemImage: "creditcard.trianglebadge.exclamationmark.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
                Link(billingLinkText, destination: billingURL)
                    .font(.caption.weight(.semibold))
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.orange.opacity(0.09), in: RoundedRectangle(cornerRadius: 9))
        } else if !error.isEmpty {
            Label(error, systemImage: "exclamationmark.triangle.fill")
                .font(.caption)
                .foregroundStyle(.red)
                .fixedSize(horizontal: false, vertical: true)
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.red.opacity(0.075), in: RoundedRectangle(cornerRadius: 9))
        } else {
            Text("Shakespeare validates the connection before saving the key.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func connectTinker() {
        let normalized = tinkerKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty, !isConnectingTinker else { return }

        isConnectingTinker = true
        tinkerError = ""
        tinkerRequiresBilling = false

        Task { @MainActor in
            defer { isConnectingTinker = false }
            do {
                try await tinkerValidator.validate(apiKey: normalized)
                guard APIKeyStore.shared.setAPIKey(normalized, service: "tinker") else {
                    tinkerError = "The key worked, but it could not be stored securely on this Mac."
                    return
                }

                tinkerKey = ""
                hasTinkerKey = true
                isReplacingTinkerKey = false
                NotificationCenter.default.post(name: .inklingConnectionChanged, object: nil)
                step = .research
            } catch is CancellationError {
                return
            } catch let error as TinkerConnectionValidator.ValidationError {
                tinkerRequiresBilling = error == .billingRequired
                tinkerError = error.localizedDescription
            } catch {
                tinkerError = error.localizedDescription
            }
        }
    }

    private func connectOpenRouter() {
        let normalized = openRouterKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty, !isConnectingOpenRouter else { return }

        isConnectingOpenRouter = true
        openRouterError = ""
        openRouterRequiresBilling = false

        Task { @MainActor in
            defer { isConnectingOpenRouter = false }
            do {
                try await openRouterValidator.validate(apiKey: normalized)
                guard APIKeyStore.shared.setAPIKey(normalized, service: "openrouter") else {
                    openRouterError = "The key worked, but it could not be stored securely on this Mac."
                    return
                }

                openRouterKey = ""
                hasOpenRouterKey = true
                isReplacingOpenRouterKey = false
                NotificationCenter.default.post(name: .openRouterConnectionChanged, object: nil)
                finish()
            } catch is CancellationError {
                return
            } catch let error as OpenRouterConnectionValidator.ValidationError {
                openRouterRequiresBilling = error == .billingRequired
                openRouterError = error.localizedDescription
            } catch {
                openRouterError = error.localizedDescription
            }
        }
    }

    private func focusCurrentFieldIfNeeded() {
        let needsFocus = switch step {
        case .writing: !hasTinkerKey || isReplacingTinkerKey
        case .research: !hasOpenRouterKey || isReplacingOpenRouterKey
        }
        guard needsFocus else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            focusedField = step
        }
    }

    private func finish() {
        OnboardingSettings.markCompleted()
        onFinish()
    }
}

private struct StepIndicator: View {
    let number: Int
    let title: String
    let isActive: Bool
    let isComplete: Bool

    var body: some View {
        HStack(spacing: 6) {
            ZStack {
                Circle()
                    .fill(isActive ? Color.accentColor : Color.primary.opacity(0.07))
                Image(systemName: isComplete ? "checkmark" : "\(number).circle.fill")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(isActive ? .white : .secondary)
            }
            .frame(width: 22, height: 22)

            Text(title)
                .font(.caption.weight(isActive ? .semibold : .regular))
                .foregroundStyle(isActive ? .primary : .secondary)
        }
    }
}

private struct ShakespeareMark: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.accentColor.gradient)
            Text("S")
                .font(.system(size: 20, weight: .semibold, design: .serif))
                .foregroundStyle(.white)
        }
        .frame(width: 42, height: 42)
        .accessibilityHidden(true)
    }
}

private struct ConnectionCapability: View {
    let icon: String
    let title: String
    let detail: String

    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.accentColor)
                .frame(width: 28, height: 28)
                .background(Color.accentColor.opacity(0.1), in: Circle())

            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.caption.weight(.semibold))
                Text(detail).font(.system(size: 10.5)).foregroundStyle(.secondary)
            }
            .lineLimit(1)

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 11)
        .padding(.vertical, 10)
        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 10))
        .overlay {
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.primary.opacity(0.055), lineWidth: 1)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title). \(detail).")
    }
}

private struct ConnectedCredentialCard: View {
    let title: String
    let detail: String
    let onReplace: () -> Void

    var body: some View {
        HStack(spacing: 13) {
            Image(systemName: "checkmark.circle.fill")
                .font(.title2)
                .foregroundStyle(.green)

            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.headline)
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }

            Spacer()
            Button("Replace Key", action: onReplace)
        }
        .padding(16)
        .background(Color.green.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.green.opacity(0.14), lineWidth: 1)
        }
    }
}

private struct PrivacyNote: View {
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "hand.raised")
                .foregroundStyle(.secondary)
                .frame(width: 18)
                .accessibilityHidden(true)
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
            .overlay {
                RoundedRectangle(cornerRadius: 14)
                    .stroke(Color.primary.opacity(0.07), lineWidth: 1)
            }
    }

    func onboardingDescription() -> some View {
        font(.system(size: 15))
            .lineSpacing(3)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: 650, alignment: .leading)
    }
}

extension Notification.Name {
    static let showOnboarding = Notification.Name("showOnboarding")
    static let inklingConnectionChanged = Notification.Name("inklingConnectionChanged")
    static let openRouterConnectionChanged = Notification.Name("openRouterConnectionChanged")
}
