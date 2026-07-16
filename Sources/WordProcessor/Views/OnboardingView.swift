import AppKit
import SwiftUI

enum OnboardingSettings {
    static let completedVersionKey = "onboardingCompletedVersion"
    static let currentVersion = 1
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
    @State private var hasExistingAPIKey = false
    @State private var isReplacingAPIKey = false
    @State private var isConnecting = false
    @State private var connectionError = ""
    @State private var connectionRequiresBilling = false
    @FocusState private var isAPIKeyFocused: Bool

    private let connectionValidator = TinkerConnectionValidator()

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            content
            Divider()
            footer
        }
        .frame(width: 720, height: 580)
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear {
            hasExistingAPIKey = APIKeyStore.shared.getAPIKey(service: "tinker") != nil
            if !hasExistingAPIKey {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                    isAPIKeyFocused = true
                }
            }
        }
    }

    private var header: some View {
        HStack(spacing: 14) {
            ShakespeareMark()

            VStack(alignment: .leading, spacing: 3) {
                Text("Welcome to Shakespeare")
                    .font(.system(size: 15, weight: .semibold))
                Text("A calmer place to write and revise.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Label("ONE-MINUTE SETUP", systemImage: "clock")
                .font(.system(size: 9.5, weight: .semibold))
                .kerning(0.55)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(Color.primary.opacity(0.045), in: Capsule())
        }
        .padding(.horizontal, 32)
        .padding(.vertical, 19)
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 9) {
                Text("One key. That’s it.")
                    .font(.system(size: 31, weight: .semibold, design: .serif))
                Text("Your Tinker API key automatically connects Inkling for writing help. The same credential is used by Tinker training later—there is no separate Inkling key.")
                    .font(.system(size: 15))
                    .lineSpacing(3)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: 620, alignment: .leading)
            }

            HStack(spacing: 10) {
                ConnectionCapability(
                    icon: "sparkles",
                    title: "Inkling assistant",
                    detail: "Draft and revise"
                )
                ConnectionCapability(
                    icon: "person.text.rectangle",
                    title: "Personal training",
                    detail: "Only when you opt in"
                )
                ConnectionCapability(
                    icon: "checkmark.shield",
                    title: "Secure credential",
                    detail: "Saved in Keychain"
                )
            }

            credentialCard

            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "hand.raised")
                    .foregroundStyle(.secondary)
                    .frame(width: 18)
                    .accessibilityHidden(true)
                Text("Text is sent to Tinker only when you ask the assistant for help. Style learning is a separate choice in My Style and is never enabled by connecting a key.")
                    .font(.caption)
                    .lineSpacing(2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 32)
        .padding(.top, 24)
        .padding(.bottom, 20)
    }

    @ViewBuilder
    private var credentialCard: some View {
        if hasExistingAPIKey && !isReplacingAPIKey {
            HStack(spacing: 13) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.title2)
                    .foregroundStyle(.green)

                VStack(alignment: .leading, spacing: 3) {
                    Text("Ready to use Inkling")
                        .font(.headline)
                    Text("A Tinker API key is saved in secure local credential storage.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button("Replace Key") {
                    connectionError = ""
                    connectionRequiresBilling = false
                    isReplacingAPIKey = true
                    DispatchQueue.main.async {
                        isAPIKeyFocused = true
                    }
                }
            }
            .padding(16)
            .background(Color.green.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
        } else {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Tinker API key")
                        .font(.headline)
                    Spacer()
                    Link("Get a key ↗", destination: InferenceSettings.tinkerConsoleURL)
                        .font(.caption)
                }

                HStack(spacing: 8) {
                    SecureField("Paste TINKER_API_KEY", text: $apiKey)
                        .textFieldStyle(.roundedBorder)
                        .focused($isAPIKeyFocused)
                        .disabled(isConnecting)
                        .onChange(of: apiKey) {
                            connectionError = ""
                            connectionRequiresBilling = false
                        }
                        .onSubmit {
                            connectAndFinish()
                        }

                    Button {
                        pasteAPIKey()
                    } label: {
                        Label("Paste", systemImage: "doc.on.clipboard")
                    }
                    .disabled(isConnecting)
                }

                if isConnecting {
                    HStack(spacing: 7) {
                        ProgressView()
                            .controlSize(.small)
                        Text("Checking access to Inkling…")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } else if connectionRequiresBilling {
                    TinkerBillingNotice(
                        message: "This key is valid, but Tinker won’t serve Inkling until the account has payment information or credits."
                    )
                } else if !connectionError.isEmpty {
                    HStack(alignment: .top, spacing: 9) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                        Text(connectionError)
                            .font(.caption)
                            .foregroundStyle(.red)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(11)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.red.opacity(0.075), in: RoundedRectangle(cornerRadius: 9))
                } else {
                    Text("Shakespeare checks the connection before saving the key.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(16)
            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 14))
            .overlay {
                RoundedRectangle(cornerRadius: 14)
                    .stroke(Color.primary.opacity(0.07), lineWidth: 1)
            }
        }
    }

    private var footer: some View {
        HStack(spacing: 10) {
            if !hasExistingAPIKey || isReplacingAPIKey {
                Button("Write Without Assistant") {
                    finish()
                }
                .disabled(isConnecting)
            }

            Spacer()

            Button("Open a Document") {
                OnboardingSettings.markCompleted()
                onOpenDocument()
            }
            .disabled(isConnecting)

            if hasExistingAPIKey && !isReplacingAPIKey {
                Button("Start Writing") {
                    finish()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            } else {
                Button {
                    connectAndFinish()
                } label: {
                    if isConnecting {
                        Text("Connecting…")
                    } else {
                        Text("Connect & Start Writing")
                    }
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isConnecting)
            }
        }
        .padding(.horizontal, 32)
        .padding(.vertical, 16)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.45))
    }

    private func pasteAPIKey() {
        guard let value = NSPasteboard.general.string(forType: .string) else { return }
        apiKey = value.trimmingCharacters(in: .whitespacesAndNewlines)
        connectionError = ""
        connectionRequiresBilling = false
    }

    private func connectAndFinish() {
        let normalized = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty, !isConnecting else { return }

        isConnecting = true
        connectionError = ""
        connectionRequiresBilling = false

        Task { @MainActor in
            defer { isConnecting = false }

            do {
                try await connectionValidator.validate(apiKey: normalized)
                guard APIKeyStore.shared.setAPIKey(normalized, service: "tinker") else {
                    connectionError = "The key worked, but it could not be stored securely on this Mac."
                    return
                }

                apiKey = ""
                hasExistingAPIKey = true
                isReplacingAPIKey = false
                NotificationCenter.default.post(name: .inklingConnectionChanged, object: nil)
                finish()
            } catch is CancellationError {
                return
            } catch let error as TinkerConnectionValidator.ValidationError {
                connectionRequiresBilling = error == .billingRequired
                connectionError = error.localizedDescription
            } catch {
                connectionError = error.localizedDescription
            }
        }
    }

    private func finish() {
        OnboardingSettings.markCompleted()
        onFinish()
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
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.primary)
                Text(detail)
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
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

extension Notification.Name {
    static let showOnboarding = Notification.Name("showOnboarding")
    static let inklingConnectionChanged = Notification.Name("inklingConnectionChanged")
}
