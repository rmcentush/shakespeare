import AppKit

@main
private struct FocusModeEscapeEvals {
    static func main() {
        precondition(FocusModeEscapeMonitor.shouldHandle(
            keyCode: 53,
            modifierFlags: [],
            isEnabled: true
        ))
        precondition(!FocusModeEscapeMonitor.shouldHandle(
            keyCode: 53,
            modifierFlags: [],
            isEnabled: false
        ))
        precondition(!FocusModeEscapeMonitor.shouldHandle(
            keyCode: 53,
            modifierFlags: .command,
            isEnabled: true
        ))
        precondition(!FocusModeEscapeMonitor.shouldHandle(
            keyCode: 36,
            modifierFlags: [],
            isEnabled: true
        ))

        print("Focus-mode Escape evals passed (active, inactive, modified, non-Escape).")
    }
}
