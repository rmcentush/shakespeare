import AppKit
import SwiftUI

/// Catches Escape before a focused WKWebView consumes it. The monitor is
/// window-scoped and disabled outside Focus Mode so editor-specific Escape
/// behavior remains unchanged.
struct FocusModeEscapeMonitor: NSViewRepresentable {
    let isEnabled: Bool
    let onEscape: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        context.coordinator.hostView = view
        context.coordinator.update(isEnabled: isEnabled, onEscape: onEscape)
        context.coordinator.install()
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.hostView = nsView
        context.coordinator.update(isEnabled: isEnabled, onEscape: onEscape)
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        coordinator.uninstall()
    }

    static func shouldHandle(
        keyCode: UInt16,
        modifierFlags: NSEvent.ModifierFlags,
        isEnabled: Bool
    ) -> Bool {
        guard isEnabled, keyCode == 53 else { return false }
        let disallowedModifiers: NSEvent.ModifierFlags = [.command, .control, .option, .shift]
        return modifierFlags.intersection(disallowedModifiers).isEmpty
    }

    final class Coordinator {
        weak var hostView: NSView?

        private var eventMonitor: Any?
        private var isEnabled = false
        private var onEscape: () -> Void = {}

        func update(isEnabled: Bool, onEscape: @escaping () -> Void) {
            self.isEnabled = isEnabled
            self.onEscape = onEscape
        }

        func install() {
            guard eventMonitor == nil else { return }
            eventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard let self,
                      event.window === hostView?.window,
                      FocusModeEscapeMonitor.shouldHandle(
                          keyCode: event.keyCode,
                          modifierFlags: event.modifierFlags,
                          isEnabled: isEnabled
                      )
                else { return event }

                onEscape()
                return nil
            }
        }

        func uninstall() {
            guard let eventMonitor else { return }
            NSEvent.removeMonitor(eventMonitor)
            self.eventMonitor = nil
        }

        deinit {
            uninstall()
        }
    }
}
