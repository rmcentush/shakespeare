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
    private enum Step: Int, CaseIterable {
        case welcome
        case assistant
        case style
    }

    private enum KeySaveState: Equatable {
        case idle
        case saved
        case failed
    }

    let onFinish: () -> Void
    let onOpenDocument: () -> Void

    @State private var step: Step = .welcome
    @State private var apiKey = ""
    @State private var hasExistingAPIKey = false
    @State private var isReplacingAPIKey = false
    @State private var keySaveState: KeySaveState = .idle
    @State private var learningEnabled = PersonalizationSettings.isEnabled

    var body: some View {
        VStack(spacing: 0) {
            header

            Divider()

            Group {
                switch step {
                case .welcome:
                    welcomeStep
                case .assistant:
                    assistantStep
                case .style:
                    styleStep
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider()

            footer
        }
        .frame(width: 700, height: 540)
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear {
            hasExistingAPIKey = APIKeyStore.shared.getAPIKey(service: "tinker") != nil
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            ShakespeareMark()

            VStack(alignment: .leading, spacing: 2) {
                Text("Welcome to Shakespeare")
                    .font(.headline)
                Text("A calmer place to write, revise, and develop your voice.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            HStack(spacing: 7) {
                ForEach(Step.allCases, id: \.rawValue) { item in
                    Circle()
                        .fill(item.rawValue <= step.rawValue ? Color.accentColor : Color.secondary.opacity(0.22))
                        .frame(width: item == step ? 9 : 7, height: item == step ? 9 : 7)
                        .animation(.easeOut(duration: 0.16), value: step)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Step \(step.rawValue + 1) of \(Step.allCases.count)")
        }
        .padding(.horizontal, 26)
        .padding(.vertical, 18)
    }

    private var welcomeStep: some View {
        VStack(alignment: .leading, spacing: 24) {
            VStack(alignment: .leading, spacing: 9) {
                Text("Your words stay at the center.")
                    .font(.system(size: 28, weight: .semibold, design: .serif))
                Text("Write normally, ask for help when you want it, and review every suggested change before it touches your draft.")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(alignment: .top, spacing: 14) {
                OnboardingFeature(
                    icon: "doc.text",
                    title: "A real editor",
                    detail: "Draft, format, comment, save versions, and proofread without an AI connection."
                )
                OnboardingFeature(
                    icon: "checkmark.bubble",
                    title: "Edits you control",
                    detail: "Assistant changes arrive as suggestions. Accept, revise, or reject them."
                )
                OnboardingFeature(
                    icon: "person.crop.circle.badge.checkmark",
                    title: "Your style, optional",
                    detail: "Learning is opt-in, local by default, and reversible from Settings."
                )
            }

            Spacer()
        }
        .padding(34)
    }

    private var assistantStep: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 7) {
                Label("Connect the writing assistant", systemImage: "sparkles")
                    .font(.title2.weight(.semibold))
                Text("Optional. Shakespeare works as an editor without an API key.")
                    .foregroundStyle(.secondary)
            }

            if hasExistingAPIKey && !isReplacingAPIKey {
                HStack(spacing: 12) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.title2)
                        .foregroundStyle(.green)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Inkling is connected")
                            .font(.headline)
                        Text("Your key is stored in secure local credential storage.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Replace Key") {
                        isReplacingAPIKey = true
                    }
                }
                .padding(16)
                .background(Color.green.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Tinker API key")
                        .font(.headline)

                    HStack(spacing: 8) {
                        SecureField("Paste your TINKER_API_KEY", text: $apiKey)
                            .textFieldStyle(.roundedBorder)
                            .onSubmit { saveAPIKey() }

                        Button {
                            pasteAPIKey()
                        } label: {
                            Label("Paste", systemImage: "doc.on.clipboard")
                        }
                    }

                    switch keySaveState {
                    case .idle:
                        EmptyView()
                    case .saved:
                        Label("Connected securely", systemImage: "checkmark.circle.fill")
                            .font(.caption)
                            .foregroundStyle(.green)
                    case .failed:
                        Label("The key could not be stored. Try again or continue without it.", systemImage: "exclamationmark.triangle.fill")
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }
                .padding(16)
                .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 12))
            }

            Label {
                Text("When you ask the assistant for help, relevant document excerpts are sent to Tinker for that request. Shakespeare does not send documents in the background.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } icon: {
                Image(systemName: "hand.raised")
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding(34)
    }

    private var styleStep: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 7) {
                Label("Let Shakespeare learn your style?", systemImage: "person.text.rectangle")
                    .font(.title2.weight(.semibold))
                Text("This is separate from connecting the assistant, and you can change it anytime.")
                    .foregroundStyle(.secondary)
            }

            Toggle(isOn: $learningEnabled) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("Learn from saved edits and documents")
                        .font(.headline)
                    Text("After you save, Shakespeare checks whether you kept, revised, reverted, or rewrote assistant suggestions. Those outcomes build a local style history.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .toggleStyle(.switch)
            .accessibilityLabel("Learn from saved edits and documents")
            .accessibilityHint("Records local learning outcomes after documents are saved")
            .padding(18)
            .background(
                learningEnabled ? Color.accentColor.opacity(0.09) : Color(nsColor: .controlBackgroundColor),
                in: RoundedRectangle(cornerRadius: 12)
            )

            VStack(alignment: .leading, spacing: 10) {
                PrivacyPoint(icon: "internaldrive", text: "Learning history stays on this Mac unless you explicitly start a training workflow.")
                PrivacyPoint(icon: "eye", text: "You review learned preferences before they become part of your style profile.")
                PrivacyPoint(icon: "arrow.uturn.backward", text: "You can pause learning, delete its history, or return to untuned Inkling.")
            }

            Spacer()
        }
        .padding(34)
    }

    private var footer: some View {
        HStack {
            if step == .welcome {
                Button("Skip Setup") {
                    finish()
                }
            } else {
                Button("Back") {
                    move(to: Step(rawValue: step.rawValue - 1) ?? .welcome)
                }
            }

            Spacer()

            switch step {
            case .welcome:
                Button("Continue") {
                    move(to: .assistant)
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            case .assistant:
                if !hasExistingAPIKey || isReplacingAPIKey {
                    Button("Do This Later") {
                        move(to: .style)
                    }
                }
                Button(hasExistingAPIKey && !isReplacingAPIKey ? "Continue" : "Save & Continue") {
                    if hasExistingAPIKey && !isReplacingAPIKey {
                        move(to: .style)
                    } else if saveAPIKey() {
                        move(to: .style)
                    }
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled((!hasExistingAPIKey || isReplacingAPIKey) && apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            case .style:
                Button("Open a Document") {
                    PersonalizationSettings.isEnabled = learningEnabled
                    OnboardingSettings.markCompleted()
                    onOpenDocument()
                }
                Button("Start Writing") {
                    finish()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(.horizontal, 26)
        .padding(.vertical, 16)
    }

    private func move(to nextStep: Step) {
        withAnimation(.easeOut(duration: 0.16)) {
            step = nextStep
        }
    }

    @discardableResult
    private func saveAPIKey() -> Bool {
        let normalized = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return false }

        let saved = APIKeyStore.shared.setAPIKey(normalized, service: "tinker")
        keySaveState = saved ? .saved : .failed
        if saved {
            apiKey = ""
            hasExistingAPIKey = true
            isReplacingAPIKey = false
            NotificationCenter.default.post(name: .inklingConnectionChanged, object: nil)
        }
        return saved
    }

    private func pasteAPIKey() {
        guard let value = NSPasteboard.general.string(forType: .string) else { return }
        apiKey = value.trimmingCharacters(in: .whitespacesAndNewlines)
        keySaveState = .idle
    }

    private func finish() {
        PersonalizationSettings.isEnabled = learningEnabled
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

private struct OnboardingFeature: View {
    let icon: String
    let title: String
    let detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(Color.accentColor)
            Text(title)
                .font(.headline)
            Text(detail)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 12))
    }
}

private struct PrivacyPoint: View {
    let icon: String
    let text: String

    var body: some View {
        Label {
            Text(text)
                .font(.callout)
        } icon: {
            Image(systemName: icon)
                .foregroundStyle(Color.accentColor)
                .frame(width: 20)
        }
    }
}

extension Notification.Name {
    static let showOnboarding = Notification.Name("showOnboarding")
    static let inklingConnectionChanged = Notification.Name("inklingConnectionChanged")
}
