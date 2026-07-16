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
        .frame(width: 700, height: 520)
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
        HStack(spacing: 12) {
            ShakespeareMark()

            VStack(alignment: .leading, spacing: 2) {
                Text("Welcome to Shakespeare")
                    .font(.headline)
                Text("A calmer place to write and revise.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Text("ONE-MINUTE SETUP")
                .font(.system(size: 9.5, weight: .semibold))
                .kerning(0.7)
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 26)
        .padding(.vertical, 18)
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 8) {
                Text("One key. That’s it.")
                    .font(.system(size: 29, weight: .semibold, design: .serif))
                Text("Your Tinker API key automatically connects Inkling for writing help. The same credential is used by Tinker training later—there is no separate Inkling key.")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: 10) {
                ConnectionCapability(icon: "sparkles", label: "Inkling assistant")
                ConnectionCapability(icon: "person.text.rectangle", label: "Tinker training")
                ConnectionCapability(icon: "checkmark.shield", label: "One secure key")
            }

            credentialCard

            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "hand.raised")
                    .foregroundStyle(.secondary)
                    .frame(width: 18)
                Text("Text is sent to Tinker only when you ask the assistant for help. Style learning is a separate choice in My Style and is never enabled by connecting a key.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 34)
        .padding(.vertical, 28)
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
                } else if !connectionError.isEmpty {
                    Label(connectionError, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.red)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    Text("Shakespeare checks the connection before saving the key.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(16)
            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 12))
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
        .padding(.horizontal, 26)
        .padding(.vertical, 16)
    }

    private func pasteAPIKey() {
        guard let value = NSPasteboard.general.string(forType: .string) else { return }
        apiKey = value.trimmingCharacters(in: .whitespacesAndNewlines)
        connectionError = ""
    }

    private func connectAndFinish() {
        let normalized = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty, !isConnecting else { return }

        isConnecting = true
        connectionError = ""

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
        .frame(width: 40, height: 40)
        .accessibilityHidden(true)
    }
}

private struct ConnectionCapability: View {
    let icon: String
    let label: String

    var body: some View {
        Label(label, systemImage: icon)
            .font(.caption.weight(.medium))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 11)
            .padding(.vertical, 9)
            .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 9))
    }
}

extension Notification.Name {
    static let showOnboarding = Notification.Name("showOnboarding")
    static let inklingConnectionChanged = Notification.Name("inklingConnectionChanged")
}
