import AppKit
import SwiftUI

private enum WordProcessorWindowID {
    static let editor = "editor"
}

private struct WindowCommandContext {
    let canSaveNamedVersion: Bool
    let openDocument: () -> Void
    let openRecentFile: (URL) -> Void
    let saveDocument: () -> Void
    let saveDocumentAs: () -> Void
    let exportHTML: () -> Void
    let showSaveNamedVersion: () -> Void
    let cut: () -> Void
    let copy: () -> Void
    let paste: () -> Void
    let applyFormat: (String) -> Void
}

private struct WindowCommandContextKey: FocusedValueKey {
    typealias Value = WindowCommandContext
}

extension FocusedValues {
    fileprivate var windowCommandContext: WindowCommandContext? {
        get { self[WindowCommandContextKey.self] }
        set { self[WindowCommandContextKey.self] = newValue }
    }
}

private struct WordProcessorCommands: Commands {
    @Environment(\.openWindow) private var openWindow
    @FocusedValue(\.windowCommandContext) private var windowCommandContext
    @State private var textCheckingSettings = TextCheckingSettings.shared

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("New") {
                openWindow(id: WordProcessorWindowID.editor)
            }
            .keyboardShortcut("n")

            Button("Open...") {
                windowCommandContext?.openDocument()
            }
            .keyboardShortcut("o")
            .disabled(windowCommandContext == nil)

            Menu("Open Recent") {
                let recentFiles = DocumentModel.recentFiles()
                if recentFiles.isEmpty {
                    Text("No Recent Files")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(recentFiles, id: \.url) { item in
                        Button(item.name) {
                            windowCommandContext?.openRecentFile(item.url)
                        }
                        .disabled(windowCommandContext == nil)
                    }
                    Divider()
                    Button("Clear Recent Files") {
                        DocumentModel.clearRecentFiles()
                    }
                }
            }

            Divider()

            Button("Save") {
                windowCommandContext?.saveDocument()
            }
            .keyboardShortcut("s")
            .disabled(windowCommandContext == nil)

            Button("Save As...") {
                windowCommandContext?.saveDocumentAs()
            }
            .keyboardShortcut("s", modifiers: [.command, .shift])
            .disabled(windowCommandContext == nil)

            Divider()

            Button("Export HTML...") {
                windowCommandContext?.exportHTML()
            }
            .keyboardShortcut("e", modifiers: [.command, .option, .shift])
            .disabled(windowCommandContext == nil)

            Divider()

            Button("Save Named Version...") {
                windowCommandContext?.showSaveNamedVersion()
            }
            .keyboardShortcut("s", modifiers: [.command, .option])
            .disabled(windowCommandContext?.canSaveNamedVersion != true)
        }

        CommandGroup(replacing: .pasteboard) {
            Button("Cut") {
                performPasteboardAction(editorAction: { $0.cut() }, fallbackSelectorName: "cut:")
            }
            .keyboardShortcut("x")

            Button("Copy") {
                performPasteboardAction(editorAction: { $0.copy() }, fallbackSelectorName: "copy:")
            }
            .keyboardShortcut("c")

            Button("Paste") {
                performPasteboardAction(editorAction: { $0.paste() }, fallbackSelectorName: "paste:")
            }
            .keyboardShortcut("v")
        }

        CommandGroup(after: .textEditing) {
            Menu("Spelling and Grammar") {
                Button("Check Spelling Now") {
                    textCheckingSettings.checkSpellingNow()
                }

                Button("Show Guess Panel") {
                    textCheckingSettings.showGuessPanel()
                }

                Divider()

                Toggle("Check Spelling While Typing", isOn: Binding(
                    get: { textCheckingSettings.continuousSpellCheckingEnabled },
                    set: { textCheckingSettings.continuousSpellCheckingEnabled = $0 }
                ))

                Toggle("Check Grammar With Spelling", isOn: Binding(
                    get: { textCheckingSettings.grammarCheckingEnabled },
                    set: { textCheckingSettings.grammarCheckingEnabled = $0 }
                ))
            }

            Menu("Substitutions") {
                Toggle("Correct Spelling Automatically", isOn: Binding(
                    get: { textCheckingSettings.automaticSpellingCorrectionEnabled },
                    set: { textCheckingSettings.automaticSpellingCorrectionEnabled = $0 }
                ))

                Toggle("Use Text Replacements", isOn: Binding(
                    get: { textCheckingSettings.automaticTextReplacementEnabled },
                    set: { textCheckingSettings.automaticTextReplacementEnabled = $0 }
                ))
            }

            Divider()
            Button("Bold") {
                windowCommandContext?.applyFormat("bold")
            }
            .keyboardShortcut("b")
            .disabled(windowCommandContext == nil)

            Button("Italic") {
                windowCommandContext?.applyFormat("italic")
            }
            .keyboardShortcut("i")
            .disabled(windowCommandContext == nil)

            Button("Underline") {
                windowCommandContext?.applyFormat("underline")
            }
            .keyboardShortcut("u")
            .disabled(windowCommandContext == nil)
        }

        CommandGroup(replacing: .appSettings) {
            Button("Settings...") {
                NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
            }
            .keyboardShortcut(",")
        }
    }

    private func performPasteboardAction(
        editorAction: (WindowCommandContext) -> Void,
        fallbackSelectorName: String
    ) {
        if let windowCommandContext {
            editorAction(windowCommandContext)
        } else {
            NSApp.sendAction(Selector(fallbackSelectorName), to: nil, from: nil)
        }
    }
}

private struct EditorWindowRootView: View {
    @State private var document = DocumentModel()
    @State private var editorViewModel = EditorViewModel()

    var body: some View {
        ContentView()
            .environment(document)
            .environment(editorViewModel)
            .focusedSceneValue(\.windowCommandContext, windowCommandContext)
            .task {
                BlogVoiceLibrary.shared.refreshInBackgroundIfNeeded()
            }
            .onOpenURL { url in
                editorViewModel.openFile(url: url, document: document)
            }
    }

    private var windowCommandContext: WindowCommandContext {
        WindowCommandContext(
            canSaveNamedVersion: document.fileURL != nil,
            openDocument: {
                editorViewModel.openDocument(document: document)
            },
            openRecentFile: { url in
                editorViewModel.openFile(url: url, document: document)
            },
            saveDocument: {
                editorViewModel.saveDocument(document: document)
            },
            saveDocumentAs: {
                editorViewModel.saveDocumentAs(document: document)
            },
            exportHTML: {
                editorViewModel.exportHTML(document: document)
            },
            showSaveNamedVersion: {
                NotificationCenter.default.post(name: .showSaveNamedVersion, object: editorViewModel)
            },
            cut: {
                handlePasteboardCommand(cutAfterCopy: true)
            },
            copy: {
                handlePasteboardCommand(cutAfterCopy: false)
            },
            paste: {
                forwardPasteboardAction("paste:")
            },
            applyFormat: { command in
                editorViewModel.applyFormat(command)
            }
        )
    }

    private func handlePasteboardCommand(cutAfterCopy: Bool) {
        Task { @MainActor in
            guard editorViewModel.isEditorFocused else {
                forwardPasteboardAction(cutAfterCopy ? "cut:" : "copy:")
                return
            }

            let handled = await editorViewModel.copySelectionWithImagesToPasteboard(
                cutAfterCopy: cutAfterCopy
            )

            if !handled {
                forwardPasteboardAction(cutAfterCopy ? "cut:" : "copy:")
            }
        }
    }

    private func forwardPasteboardAction(_ selectorName: String) {
        NSApp.sendAction(Selector(selectorName), to: nil, from: nil)
    }
}

@main
struct WordProcessorApp: App {
    init() {
        // Prevent multiple instances: if another WordProcessor is already running, activate it and quit
        let myPID = ProcessInfo.processInfo.processIdentifier
        let others = NSRunningApplication.runningApplications(withBundleIdentifier: "com.shakespeare.app")
            .filter { $0.processIdentifier != myPID }
        if !others.isEmpty {
            others.first?.activate()
            exit(0)
        }

        // Bring the app to the foreground when launched from terminal
        DispatchQueue.main.async {
            NSApp.setActivationPolicy(.regular)
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    var body: some Scene {
        WindowGroup(id: WordProcessorWindowID.editor) {
            EditorWindowRootView()
        }
        .windowStyle(.titleBar)
        .defaultSize(width: 900, height: 700)
        .commands {
            WordProcessorCommands()
        }

        Settings {
            SettingsView()
        }
    }
}
