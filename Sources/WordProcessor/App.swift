import SwiftUI
import AppKit

@main
struct WordProcessorApp: App {
    @State private var document = DocumentModel()
    @State private var editorViewModel = EditorViewModel()
    @State private var textCheckingSettings = TextCheckingSettings.shared

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
        WindowGroup {
            ContentView()
                .environment(document)
                .environment(editorViewModel)
                .onOpenURL { url in
                    editorViewModel.openFile(url: url, document: document)
                }
        }
        .windowStyle(.titleBar)
        .defaultSize(width: 900, height: 700)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New") {
                    editorViewModel.createNewDocument(document: document)
                }
                .keyboardShortcut("n")

                Button("Open...") {
                    editorViewModel.openDocument(document: document)
                }
                .keyboardShortcut("o")

                Menu("Open Recent") {
                    let recentFiles = DocumentModel.recentFiles()
                    if recentFiles.isEmpty {
                        Text("No Recent Files")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(recentFiles, id: \.url) { item in
                            Button(item.name) {
                                editorViewModel.openFile(url: item.url, document: document)
                            }
                        }
                        Divider()
                        Button("Clear Recent Files") {
                            DocumentModel.clearRecentFiles()
                        }
                    }
                }

                Divider()

                Button("Save") {
                    editorViewModel.saveDocument(document: document)
                }
                .keyboardShortcut("s")

                Button("Save As...") {
                    editorViewModel.saveDocumentAs(document: document)
                }
                .keyboardShortcut("s", modifiers: [.command, .shift])

                Divider()

                Button("Export HTML...") {
                    editorViewModel.exportHTML(document: document)
                }
                .keyboardShortcut("e", modifiers: [.command, .option, .shift])

                Divider()

                Button("Save Named Version...") {
                    NotificationCenter.default.post(name: .showSaveNamedVersion, object: nil)
                }
                .keyboardShortcut("s", modifiers: [.command, .option])
                .disabled(document.fileURL == nil)
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
                    editorViewModel.applyFormat("bold")
                }
                .keyboardShortcut("b")

                Button("Italic") {
                    editorViewModel.applyFormat("italic")
                }
                .keyboardShortcut("i")

                Button("Underline") {
                    editorViewModel.applyFormat("underline")
                }
                .keyboardShortcut("u")
            }

            CommandGroup(replacing: .appSettings) {
                Button("Settings...") {
                    NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
                }
                .keyboardShortcut(",")
            }
        }

        Settings {
            SettingsView()
        }
    }
}
