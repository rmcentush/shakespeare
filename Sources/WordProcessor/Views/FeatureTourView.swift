import SwiftUI

enum FeatureTourTarget: String, Sendable {
    case research
    case comments
    case formatting
    case versionHistory
    case focus
}

struct FeatureTourStep: Identifiable, Sendable {
    let target: FeatureTourTarget
    let title: String
    let message: String

    var id: FeatureTourTarget { target }

    static let all: [FeatureTourStep] = [
        FeatureTourStep(
            target: .research,
            title: "Research as you write",
            message: "Ask about your draft or check a current fact."
        ),
        FeatureTourStep(
            target: .comments,
            title: "Leave yourself a note",
            message: "Select text, then add a comment here."
        ),
        FeatureTourStep(
            target: .formatting,
            title: "Shape the page",
            message: "Select words, then style them with these controls."
        ),
        FeatureTourStep(
            target: .versionHistory,
            title: "Go back anytime",
            message: "Version History keeps earlier saved drafts close by."
        ),
        FeatureTourStep(
            target: .focus,
            title: "Make some room",
            message: "Focus Mode leaves just you and the page."
        ),
    ]
}

enum FeatureTourSettings {
    private static let completedDefaultsKey = "featureTourCompletedV1"

    static var shouldPresent: Bool {
        !UserDefaults.standard.bool(forKey: completedDefaultsKey)
    }

    static func markCompleted() {
        UserDefaults.standard.set(true, forKey: completedDefaultsKey)
    }
}

@MainActor
enum FeatureTourPresentationCoordinator {
    private static var presentingWindowID: UUID?

    static func claim(for windowID: UUID) -> Bool {
        guard presentingWindowID == nil || presentingWindowID == windowID else { return false }
        presentingWindowID = windowID
        return true
    }

    static func release(for windowID: UUID) {
        guard presentingWindowID == windowID else { return }
        presentingWindowID = nil
    }
}

struct FeatureTourCard: View {
    let step: FeatureTourStep
    let stepIndex: Int
    let stepCount: Int
    let onBack: () -> Void
    let onNext: () -> Void
    let onSkip: () -> Void

    private var isFirstStep: Bool { stepIndex == 0 }
    private var isLastStep: Bool { stepIndex == stepCount - 1 }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text(step.title)
                    .font(.headline)
                Spacer(minLength: 12)
                Text("\(stepIndex + 1) of \(stepCount)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            Text(step.message)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 8) {
                Button("Skip Tour", action: onSkip)
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)

                Spacer()

                if !isFirstStep {
                    Button("Back", action: onBack)
                        .controlSize(.small)
                }

                Button(isLastStep ? "Done" : "Next", action: onNext)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(16)
        .frame(width: 330)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.primary.opacity(0.1), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.16), radius: 18, y: 8)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Feature tour, step \(stepIndex + 1) of \(stepCount)")
        .onExitCommand(perform: onSkip)
    }
}

private struct FeatureTourHighlightModifier: ViewModifier {
    let isActive: Bool

    func body(content: Content) -> some View {
        content
            .background(
                isActive ? Color.accentColor.opacity(0.2) : Color.clear,
                in: RoundedRectangle(cornerRadius: 7, style: .continuous)
            )
            .overlay {
                if isActive {
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .stroke(Color.accentColor, lineWidth: 2)
                        .shadow(color: Color.accentColor.opacity(0.65), radius: 6)
                }
            }
            .scaleEffect(isActive ? 1.06 : 1)
            .animation(.easeInOut(duration: 0.18), value: isActive)
    }
}

extension View {
    func featureTourHighlight(_ isActive: Bool) -> some View {
        modifier(FeatureTourHighlightModifier(isActive: isActive))
    }
}

extension Notification.Name {
    static let showFeatureTour = Notification.Name("showFeatureTour")
}
