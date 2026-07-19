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
    let startTutorial: () -> Void
}

private struct WindowCommandContextKey: FocusedValueKey {
    typealias Value = WindowCommandContext
}

@MainActor
private final class RecentDocumentRouter {
    static let shared = RecentDocumentRouter()

    private var openHandlers: [UUID: (URL) -> Void] = [:]
    private var handlerOrder: [UUID] = []
    private var activeHandlerID: UUID?

    func register(id: UUID, openHandler: @escaping (URL) -> Void) {
        openHandlers[id] = openHandler
        if !handlerOrder.contains(id) {
            handlerOrder.append(id)
        }
        if activeHandlerID == nil {
            activeHandlerID = id
        }
    }

    func unregister(id: UUID) {
        openHandlers[id] = nil
        handlerOrder.removeAll { $0 == id }
        if activeHandlerID == id {
            activeHandlerID = handlerOrder.last
        }
    }

    func markActive(id: UUID) {
        guard openHandlers[id] != nil else { return }
        activeHandlerID = id
    }

    @discardableResult
    func open(_ url: URL) -> Bool {
        if let activeHandlerID, let openHandler = openHandlers[activeHandlerID] {
            openHandler(url)
            return true
        }

        for id in handlerOrder.reversed() {
            if let openHandler = openHandlers[id] {
                activeHandlerID = id
                openHandler(url)
                return true
            }
        }

        return false
    }
}

@MainActor
private final class DocumentSessionCoordinator {
    static let shared = DocumentSessionCoordinator()

    private struct TerminationHandler {
        let prepare: () async -> Bool
        let cancel: () -> Void
    }
    private var terminationHandlers: [UUID: TerminationHandler] = [:]

    func register(
        id: UUID,
        prepare: @escaping () async -> Bool,
        cancel: @escaping () -> Void
    ) {
        terminationHandlers[id] = TerminationHandler(prepare: prepare, cancel: cancel)
    }

    func unregister(id: UUID) {
        terminationHandlers[id] = nil
    }

    func secureAllDocumentsForTermination() async -> Bool {
        let handlers = Array(terminationHandlers.values)
        for handler in handlers {
            guard await handler.prepare() else {
                handlers.forEach { $0.cancel() }
                return false
            }
        }
        return true
    }
}

@MainActor
private final class WordProcessorAppDelegate: NSObject, NSApplicationDelegate {
    private var isPreparingForTermination = false
    private var isMainMenuCleanupScheduled = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(mainMenuDidAddItem(_:)),
            name: NSMenu.didAddItemNotification,
            object: nil
        )
        removeUnusedMainMenus()
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        removeUnusedMainMenus()
    }

    private func removeUnusedMainMenus() {
        guard !isMainMenuCleanupScheduled else { return }
        isMainMenuCleanupScheduled = true
        DispatchQueue.main.async { [weak self] in
            self?.isMainMenuCleanupScheduled = false
            guard let mainMenu = NSApp.mainMenu else { return }
            for title in ["Edit", "Format", "View", "Help"] {
                if let item = mainMenu.items.first(where: { $0.title == title }) {
                    mainMenu.removeItem(item)
                }
            }
        }
    }

    @objc private func mainMenuDidAddItem(_ notification: Notification) {
        guard let menu = notification.object as? NSMenu, menu === NSApp.mainMenu else { return }
        removeUnusedMainMenus()
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard !isPreparingForTermination else { return .terminateLater }
        isPreparingForTermination = true

        Task { @MainActor [weak self, weak sender] in
            let secured = await DocumentSessionCoordinator.shared.secureAllDocumentsForTermination()
            self?.isPreparingForTermination = false
            sender?.reply(toApplicationShouldTerminate: secured)
        }
        return .terminateLater
    }

    func applicationDockMenu(_ sender: NSApplication) -> NSMenu? {
        let menu = NSMenu()
        let recentFiles = DocumentModel.recentFiles()

        if recentFiles.isEmpty {
            let item = NSMenuItem(title: "No Recent Documents", action: nil, keyEquivalent: "")
            item.isEnabled = false
            menu.addItem(item)
            return menu
        }

        for recentFile in recentFiles {
            let item = NSMenuItem(
                title: recentFile.name,
                action: #selector(openRecentDocument(_:)),
                keyEquivalent: ""
            )
            item.representedObject = recentFile.url
            item.toolTip = recentFile.url.path
            item.target = self
            menu.addItem(item)
        }

        menu.addItem(.separator())

        let clearItem = NSMenuItem(
            title: "Clear Recent Documents",
            action: #selector(clearRecentDocuments(_:)),
            keyEquivalent: ""
        )
        clearItem.target = self
        menu.addItem(clearItem)

        return menu
    }

    @MainActor
    @objc private func openRecentDocument(_ sender: NSMenuItem) {
        guard let url = sender.representedObject as? URL else { return }

        NSApp.activate(ignoringOtherApps: true)
        _ = RecentDocumentRouter.shared.open(url)
    }

    @MainActor
    @objc private func clearRecentDocuments(_ sender: NSMenuItem) {
        DocumentModel.clearRecentFiles()
    }
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

        // Keep the menu bar focused on actions that are specific to Shakespeare.
        // Editing and formatting remain available directly in the editor.
        CommandGroup(replacing: .undoRedo) {
            EmptyView()
        }

        CommandGroup(replacing: .pasteboard) {
            EmptyView()
        }

        CommandGroup(replacing: .textEditing) {
            EmptyView()
        }

        CommandGroup(replacing: .textFormatting) {
            EmptyView()
        }

        CommandGroup(replacing: .toolbar) {
            EmptyView()
        }

        CommandGroup(replacing: .sidebar) {
            EmptyView()
        }

        CommandGroup(replacing: .help) {
            EmptyView()
        }

        CommandMenu("Tutorial") {
            Button("Start Tutorial") {
                windowCommandContext?.startTutorial()
            }
            .disabled(windowCommandContext == nil)
        }
    }
}

private struct EditorWindowRootView: View {
    @State private var document = DocumentModel()
    @State private var editorViewModel = EditorViewModel()
    @State private var recentDocumentHandlerID = UUID()
    @State private var documentSessionID = UUID()

    var body: some View {
        ContentView()
            .environment(document)
            .environment(editorViewModel)
            .focusedSceneValue(\.windowCommandContext, windowCommandContext)
            .onAppear {
                RecentDocumentRouter.shared.register(id: recentDocumentHandlerID) { url in
                    editorViewModel.openFile(url: url, document: document)
                }
                DocumentSessionCoordinator.shared.register(
                    id: documentSessionID,
                    prepare: { await editorViewModel.prepareForTermination(document: document) },
                    cancel: { editorViewModel.cancelTerminationPreparation() }
                )
            }
            .onDisappear {
                RecentDocumentRouter.shared.unregister(id: recentDocumentHandlerID)
                DocumentSessionCoordinator.shared.unregister(id: documentSessionID)
            }
            .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { notification in
                guard let window = notification.object as? NSWindow,
                      editorViewModel.webView?.window === window
                else {
                    return
                }
                RecentDocumentRouter.shared.markActive(id: recentDocumentHandlerID)
            }
            .onOpenURL { url in
                RecentDocumentRouter.shared.markActive(id: recentDocumentHandlerID)
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
            startTutorial: {
                NotificationCenter.default.post(name: .showFeatureTour, object: editorViewModel)
            }
        )
    }
}

@main
struct WordProcessorApp: App {
    @NSApplicationDelegateAdaptor(WordProcessorAppDelegate.self) private var appDelegate

    init() {
        do {
            try ShakespeareStorage.prepare()
        } catch {
            print("ShakespeareStorage: failed to prepare application data: \(error)")
        }

        // Prevent duplicate processes while still allowing alternate bundle IDs
        // for isolated UI and release testing.
        if let bundleIdentifier = Bundle.main.bundleIdentifier {
            let myPID = ProcessInfo.processInfo.processIdentifier
            let others = NSRunningApplication.runningApplications(
                withBundleIdentifier: bundleIdentifier
            ).filter { $0.processIdentifier != myPID }
            if !others.isEmpty {
                others.first?.activate()
                exit(0)
            }
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
