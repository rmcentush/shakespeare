import SwiftUI

enum FeatureTourTarget: String, Sendable {
    case documents
    case formatting
    case writingGaps
    case proofreading
    case research
    case notes
    case versionHistory
    case focus
    case settings
}

struct FeatureTourStep: Identifiable, Sendable {
    let target: FeatureTourTarget
    let symbol: String
    let title: String
    let summary: String
    let details: [String]
    let shortcut: String?

    var id: FeatureTourTarget { target }

    static let all: [FeatureTourStep] = [
        FeatureTourStep(
            target: .documents,
            symbol: "doc.text",
            title: "Documents",
            summary: "Your work stays in familiar, portable files.",
            details: [
                "Create a document, reopen a recent one, or open .shkdoc and HTML files.",
                "Click the title to rename. Save, Save As, and Export HTML live in the File menu.",
            ],
            shortcut: "⌘S saves · ⇧⌘S saves a copy"
        ),
        FeatureTourStep(
            target: .formatting,
            symbol: "textformat",
            title: "Write and format",
            summary: "Everything on the page is controlled from the editor toolbar.",
            details: [
                "Set type, spacing, document styles, emphasis, color, links, footnotes, lists, quotes, and alignment.",
                "Insert images, then select one to set its layout, crop, and accessible description.",
            ],
            shortcut: "⌘B bold · ⌘I italic · ⌘K link"
        ),
        FeatureTourStep(
            target: .writingGaps,
            symbol: "sparkles",
            title: "Ask for writing help",
            summary: "Shakespeare proposes changes; you stay in control.",
            details: [
                "Select text and click ✦ for feedback, or type [[what belongs here]] to fill a gap.",
                "Every rewrite is queued as a suggestion for you to accept or reject—never applied silently.",
            ],
            shortcut: "⌘↩ fills the active [[gap]]"
        ),
        FeatureTourStep(
            target: .proofreading,
            symbol: "checkmark.bubble",
            title: "Proofread and review",
            summary: "Catch small errors or request a deeper editorial pass.",
            details: [
                "Local spelling works offline. AI grammar is optional; a thorough proofread is available from the Edit menu.",
                "Select text to add a comment. Turn on Ambient Review for suggestions you can apply, resolve, edit, or delete.",
            ],
            shortcut: "⇧⌘M comments · ⌥⌘P proofreads"
        ),
        FeatureTourStep(
            target: .research,
            symbol: "globe.americas",
            title: "Research with sources",
            summary: "Ask questions without leaving the draft.",
            details: [
                "Research Chat understands the current document, can check the live web, and returns linked sources.",
                "Research is kept separate from your writing samples and permanent style profile.",
            ],
            shortcut: "⌘\\ opens Research Chat"
        ),
        FeatureTourStep(
            target: .notes,
            symbol: "note.text",
            title: "Keep private notes",
            summary: "Store context beside the draft—not inside it.",
            details: [
                "Notes travel inside .shkdoc files and save with the document.",
                "They are excluded from model requests and HTML exports.",
            ],
            shortcut: "⌥⌘N opens Notes"
        ),
        FeatureTourStep(
            target: .versionHistory,
            symbol: "clock.arrow.circlepath",
            title: "Versions and recovery",
            summary: "Experiment without losing a good draft.",
            details: [
                "Each save creates a local version. Name, rename, restore, or delete versions here.",
                "If the app closes before a save, Shakespeare offers the recovery draft next time it opens.",
            ],
            shortcut: "⇧⌘V opens Versions · ⌥⌘S names one"
        ),
        FeatureTourStep(
            target: .focus,
            symbol: "eye",
            title: "Shape your workspace",
            summary: "Use only the tools you need in the moment.",
            details: [
                "Focus Mode hides the interface. Find and Replace, zoom, light/dark appearance, and live word counts stay close at hand.",
                "Press Escape to close transient tools or leave Focus Mode.",
            ],
            shortcut: "⌘F find · ⌥⌘F replace · ⇧⌘F focus"
        ),
        FeatureTourStep(
            target: .settings,
            symbol: "gearshape",
            title: "Make it yours",
            summary: "Settings keeps every optional behavior visible and reversible.",
            details: [
                "Connections manages your key, models, and usage. Typography and Editing control defaults, dialect, spelling, grammar, and corrections.",
                "My Style lets you add samples, review or edit learned guidance, pause learning, and delete its local history.",
            ],
            shortcut: "⌘, opens Settings · Help → Start Tutorial replays this tour"
        ),
    ]
}

enum FeatureTourSettings {
    private static let completedDefaultsKey = "featureTourCompletedV2"

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
    let width: CGFloat
    let onBack: () -> Void
    let onNext: () -> Void
    let onSkip: () -> Void

    private var isFirstStep: Bool { stepIndex == 0 }
    private var isLastStep: Bool { stepIndex == stepCount - 1 }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center, spacing: 11) {
                Image(systemName: step.symbol)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 34, height: 34)
                    .background(Color.accentColor.opacity(0.12), in: Circle())
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 2) {
                    Text("QUICK TOUR")
                        .font(.system(size: 9, weight: .bold))
                        .tracking(0.8)
                        .foregroundStyle(.tertiary)
                    Text(step.title)
                        .font(.headline)
                }

                Spacer(minLength: 12)
                Text("\(stepIndex + 1) of \(stepCount)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            Text(step.summary)
                .font(.callout)
                .fontWeight(.medium)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 9) {
                ForEach(step.details, id: \.self) { detail in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Image(systemName: "circle.fill")
                            .font(.system(size: 4))
                            .foregroundStyle(Color.accentColor)
                            .accessibilityHidden(true)
                        Text(detail)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }

            if let shortcut = step.shortcut {
                Text(shortcut)
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 6)
                    .background(Color.primary.opacity(0.055), in: Capsule())
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: 8) {
                if !isLastStep {
                    Button("Skip Tour", action: onSkip)
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if !isFirstStep {
                    Button("Back", action: onBack)
                        .controlSize(.small)
                }

                Button(isLastStep ? "Start Writing" : "Next", action: onNext)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(18)
        .frame(width: width)
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
