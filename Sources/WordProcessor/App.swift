import SwiftUI
import AppKit

@main
struct WordProcessorApp: App {
    @State private var document = DocumentModel()
    @State private var editorViewModel = EditorViewModel()

    init() {
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

                Button("Save Named Version...") {
                    NotificationCenter.default.post(name: .showSaveNamedVersion, object: nil)
                }
                .keyboardShortcut("s", modifiers: [.command, .option])
                .disabled(document.fileURL == nil)
            }

            CommandGroup(after: .textEditing) {
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
