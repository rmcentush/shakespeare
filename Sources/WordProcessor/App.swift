import AppKit
import SwiftUI

enum WordProcessorWindowID {
    static let editor = "editor"
    static let settings = "settings"
}

enum EditorMenuAction: Sendable {
    case showFind
    case showFindAndReplace
    case addComment
    case toggleResearch
    case toggleNotes
    case toggleComments
    case toggleVersionHistory
    case toggleFocusMode
    case zoomIn
    case zoomOut
    case resetZoom
    case format(command: String, value: String?)
}

extension Notification.Name {
    static let editorMenuActionRequested = Notification.Name("editorMenuActionRequested")
}

private struct WindowCommandContext {
    let canEditDocument: Bool
    let hasSelection: Bool
    let canSaveNamedVersion: Bool
    let canRunThoroughProofread: Bool
    let openDocument: () -> Void
    let openRecentFile: (URL) -> Void
    let saveDocument: () -> Void
    let saveDocumentAs: () -> Void
    let exportHTML: () -> Void
    let showSaveNamedVersion: () -> Void
    let runThoroughProofread: () -> Void
    let startTutorial: () -> Void
    let performEditorMenuAction: (EditorMenuAction) -> Void
}

private struct WindowCommandContextKey: FocusedValueKey {
    typealias Value = WindowCommandContext
}

@MainActor
private final class EditorWindowRouter {
    static let shared = EditorWindowRouter()

    private var openHandlers: [UUID: (URL) -> Void] = [:]
    private var tutorialHandlers: [UUID: () -> Void] = [:]
    private var handlerOrder: [UUID] = []
    private var activeHandlerID: UUID?

    func register(
        id: UUID,
        openHandler: @escaping (URL) -> Void,
        tutorialHandler: @escaping () -> Void
    ) {
        openHandlers[id] = openHandler
        tutorialHandlers[id] = tutorialHandler
        if !handlerOrder.contains(id) {
            handlerOrder.append(id)
        }
        if activeHandlerID == nil {
            activeHandlerID = id
        }
    }

    func unregister(id: UUID) {
        openHandlers[id] = nil
        tutorialHandlers[id] = nil
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

    @discardableResult
    func startTutorial() -> Bool {
        if let activeHandlerID, let tutorialHandler = tutorialHandlers[activeHandlerID] {
            tutorialHandler()
            return true
        }

        for id in handlerOrder.reversed() {
            if let tutorialHandler = tutorialHandlers[id] {
                activeHandlerID = id
                tutorialHandler()
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
        _ = EditorWindowRouter.shared.open(url)
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
        CommandGroup(replacing: .appSettings) {
            Button("Settings…") {
                openWindow(id: WordProcessorWindowID.settings)
            }
            .keyboardShortcut(",")
        }

        CommandGroup(replacing: .newItem) {
            Button("New") {
                openWindow(id: WordProcessorWindowID.editor)
            }
            .keyboardShortcut("n")

            Button("Open…") {
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
                    Button("Clear Menu") {
                        DocumentModel.clearRecentFiles()
                    }
                }
            }

            Divider()

            Button("Close Window") {
                NSApp.keyWindow?.performClose(nil)
            }
            .keyboardShortcut("w")
        }

        CommandGroup(replacing: .saveItem) {
            Button("Save") {
                windowCommandContext?.saveDocument()
            }
            .keyboardShortcut("s")
            .disabled(windowCommandContext == nil)

            Button("Save As…") {
                windowCommandContext?.saveDocumentAs()
            }
            .keyboardShortcut("s", modifiers: [.command, .shift])
            .disabled(windowCommandContext == nil)

            Divider()

            Button("Save Named Version…") {
                windowCommandContext?.showSaveNamedVersion()
            }
            .keyboardShortcut("s", modifiers: [.command, .option])
            .disabled(windowCommandContext?.canSaveNamedVersion != true)
        }

        CommandGroup(replacing: .importExport) {
            Button("Export HTML…") {
                windowCommandContext?.exportHTML()
            }
            .keyboardShortcut("e", modifiers: [.command, .option, .shift])
            .disabled(windowCommandContext == nil)
        }

        CommandGroup(replacing: .printItem) {
            EmptyView()
        }

        CommandGroup(after: .pasteboard) {
            Menu("Find") {
                Button("Find…") {
                    windowCommandContext?.performEditorMenuAction(.showFind)
                }
                .keyboardShortcut("f")

                Button("Find and Replace…") {
                    windowCommandContext?.performEditorMenuAction(.showFindAndReplace)
                }
                .keyboardShortcut("f", modifiers: [.command, .option])
            }
            .disabled(windowCommandContext?.canEditDocument != true)
        }

        CommandGroup(after: .textEditing) {
            Button("Add Comment") {
                windowCommandContext?.performEditorMenuAction(.addComment)
            }
            .keyboardShortcut("m", modifiers: [.command, .shift])
            .disabled(windowCommandContext?.hasSelection != true)

            Button("Run Thorough Proofread") {
                windowCommandContext?.runThoroughProofread()
            }
            .keyboardShortcut("p", modifiers: [.command, .option])
            .disabled(windowCommandContext?.canRunThoroughProofread != true)
        }

        CommandGroup(replacing: .textFormatting) {
            Button("Bold") {
                windowCommandContext?.performEditorMenuAction(.format(command: "bold", value: nil))
            }
            .keyboardShortcut("b")
            .disabled(windowCommandContext?.canEditDocument != true)

            Button("Italic") {
                windowCommandContext?.performEditorMenuAction(.format(command: "italic", value: nil))
            }
            .keyboardShortcut("i")
            .disabled(windowCommandContext?.canEditDocument != true)

            Button("Underline") {
                windowCommandContext?.performEditorMenuAction(.format(command: "underline", value: nil))
            }
            .keyboardShortcut("u")
            .disabled(windowCommandContext?.canEditDocument != true)

            Button("Strikethrough") {
                windowCommandContext?.performEditorMenuAction(.format(command: "strike", value: nil))
            }
            .disabled(windowCommandContext?.canEditDocument != true)

            Divider()

            Menu("Paragraph Style") {
                Button("Body") {
                    windowCommandContext?.performEditorMenuAction(.format(command: "paragraph", value: nil))
                }
                Button("Heading 1") {
                    windowCommandContext?.performEditorMenuAction(.format(command: "heading", value: "1"))
                }
                Button("Heading 2") {
                    windowCommandContext?.performEditorMenuAction(.format(command: "heading", value: "2"))
                }
                Button("Heading 3") {
                    windowCommandContext?.performEditorMenuAction(.format(command: "heading", value: "3"))
                }
                Button("Block Quote") {
                    windowCommandContext?.performEditorMenuAction(.format(command: "blockquote", value: nil))
                }
            }
            .disabled(windowCommandContext?.canEditDocument != true)

            Menu("Lists") {
                Button("Bulleted List") {
                    windowCommandContext?.performEditorMenuAction(.format(command: "bulletList", value: nil))
                }
                Button("Numbered List") {
                    windowCommandContext?.performEditorMenuAction(.format(command: "orderedList", value: nil))
                }
            }
            .disabled(windowCommandContext?.canEditDocument != true)

            Menu("Alignment") {
                Button("Left") {
                    windowCommandContext?.performEditorMenuAction(.format(command: "alignLeft", value: nil))
                }
                Button("Center") {
                    windowCommandContext?.performEditorMenuAction(.format(command: "alignCenter", value: nil))
                }
                Button("Right") {
                    windowCommandContext?.performEditorMenuAction(.format(command: "alignRight", value: nil))
                }
                Button("Justified") {
                    windowCommandContext?.performEditorMenuAction(.format(command: "alignJustify", value: nil))
                }
            }
            .disabled(windowCommandContext?.canEditDocument != true)
        }

        WorkspaceAndHelpCommands()
    }
}

private struct WorkspaceAndHelpCommands: Commands {
    @Environment(\.openWindow) private var openWindow
    @FocusedValue(\.windowCommandContext) private var windowCommandContext

    var body: some Commands {
        CommandGroup(replacing: .toolbar) {
            Button("Zoom In") {
                windowCommandContext?.performEditorMenuAction(.zoomIn)
            }
            .keyboardShortcut("+")
            .disabled(windowCommandContext?.canEditDocument != true)

            Button("Zoom Out") {
                windowCommandContext?.performEditorMenuAction(.zoomOut)
            }
            .keyboardShortcut("-")
            .disabled(windowCommandContext?.canEditDocument != true)

            Button("Actual Size") {
                windowCommandContext?.performEditorMenuAction(.resetZoom)
            }
            .keyboardShortcut("0")
            .disabled(windowCommandContext?.canEditDocument != true)
        }

        CommandGroup(replacing: .sidebar) {
            Button("Research Chat") {
                windowCommandContext?.performEditorMenuAction(.toggleResearch)
            }
            .keyboardShortcut("\\")
            .disabled(windowCommandContext?.canEditDocument != true)

            Button("Notes") {
                windowCommandContext?.performEditorMenuAction(.toggleNotes)
            }
            .keyboardShortcut("n", modifiers: [.command, .option])
            .disabled(windowCommandContext?.canEditDocument != true)

            Button("Comments") {
                windowCommandContext?.performEditorMenuAction(.toggleComments)
            }
            .disabled(windowCommandContext?.canEditDocument != true)

            Button("Version History") {
                windowCommandContext?.performEditorMenuAction(.toggleVersionHistory)
            }
            .keyboardShortcut("v", modifiers: [.command, .shift])
            .disabled(windowCommandContext?.canEditDocument != true)

            Divider()

            Button("Focus Mode") {
                windowCommandContext?.performEditorMenuAction(.toggleFocusMode)
            }
            .keyboardShortcut("f", modifiers: [.command, .shift])
            .disabled(windowCommandContext?.canEditDocument != true)
        }

        CommandGroup(replacing: .help) {
            Button("Start Tutorial") {
                if let windowCommandContext {
                    windowCommandContext.startTutorial()
                } else if !EditorWindowRouter.shared.startTutorial() {
                    openWindow(id: WordProcessorWindowID.editor)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        NotificationCenter.default.post(name: .showFeatureTour, object: nil)
                    }
                }
            }
        }
    }
}

private struct EditorWindowRootView: View {
    @Environment(ApplicationStorageStatus.self) private var storageStatus
    @State private var document = DocumentModel()
    @State private var editorViewModel = EditorViewModel()
    @State private var editorWindowHandlerID = UUID()
    @State private var documentSessionID = UUID()

    var body: some View {
        if storageStatus.isReady {
            editorContent
        } else {
            StorageUnavailableView()
                .frame(minWidth: 680, minHeight: 520)
        }
    }

    private var editorContent: some View {
        ContentView()
            .frame(minWidth: 680, minHeight: 520)
            .environment(document)
            .environment(editorViewModel)
            .focusedSceneValue(\.windowCommandContext, windowCommandContext)
            .onAppear {
                EditorWindowRouter.shared.register(
                    id: editorWindowHandlerID,
                    openHandler: { url in
                        editorViewModel.openFile(url: url, document: document)
                    },
                    tutorialHandler: {
                        NotificationCenter.default.post(
                            name: .showFeatureTour,
                            object: editorViewModel
                        )
                    }
                )
                DocumentSessionCoordinator.shared.register(
                    id: documentSessionID,
                    prepare: { await editorViewModel.prepareForTermination(document: document) },
                    cancel: { editorViewModel.cancelTerminationPreparation() }
                )
            }
            .onDisappear {
                EditorWindowRouter.shared.unregister(id: editorWindowHandlerID)
                DocumentSessionCoordinator.shared.unregister(id: documentSessionID)
            }
            .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { notification in
                guard let window = notification.object as? NSWindow,
                      editorViewModel.webView?.window === window
                else {
                    return
                }
                EditorWindowRouter.shared.markActive(id: editorWindowHandlerID)
            }
            .onOpenURL { url in
                EditorWindowRouter.shared.markActive(id: editorWindowHandlerID)
                editorViewModel.openFile(url: url, document: document)
            }
    }

    private var windowCommandContext: WindowCommandContext {
        WindowCommandContext(
            canEditDocument: editorViewModel.isEditorReady
                && !editorViewModel.isDocumentTransitioning,
            hasSelection: editorViewModel.selectionState.hasSelection,
            canSaveNamedVersion: document.fileURL != nil,
            canRunThoroughProofread: editorViewModel.isEditorReady
                && !editorViewModel.isDocumentTransitioning
                && APIKeyStore.shared.hasAPIKey(service: "openrouter"),
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
            runThoroughProofread: {
                editorViewModel.runThoroughProofread()
            },
            startTutorial: {
                NotificationCenter.default.post(name: .showFeatureTour, object: editorViewModel)
            },
            performEditorMenuAction: { action in
                NotificationCenter.default.post(
                    name: .editorMenuActionRequested,
                    object: editorViewModel,
                    userInfo: ["action": action]
                )
            }
        )
    }
}

private struct StorageUnavailableView: View {
    @Environment(ApplicationStorageStatus.self) private var storageStatus

    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: "externaldrive.badge.exclamationmark")
                .font(.system(size: 42, weight: .medium))
                .foregroundStyle(.red)
                .accessibilityHidden(true)

            Text("Shakespeare Storage Is Unavailable")
                .font(.title2.weight(.semibold))

            Text("Shakespeare can’t safely open documents because its private application data could not be prepared.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .frame(maxWidth: 460)

            if let failureMessage = storageStatus.failureMessage {
                Text(failureMessage)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 520)
                    .accessibilityLabel("Storage error: \(failureMessage)")
            }

            HStack(spacing: 12) {
                Button("Quit Shakespeare") {
                    NSApp.terminate(nil)
                }
                Button("Retry") {
                    storageStatus.prepare()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(40)
    }
}

@main
struct WordProcessorApp: App {
    @NSApplicationDelegateAdaptor(WordProcessorAppDelegate.self) private var appDelegate
    @State private var storageStatus = ApplicationStorageStatus.shared

    init() {
        ApplicationStorageStatus.shared.prepare()

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
                .environment(storageStatus)
        }
        .windowStyle(.titleBar)
        .defaultSize(width: 900, height: 700)
        .windowResizability(.contentMinSize)
        .commands {
            WordProcessorCommands()
        }

        Window("Settings", id: WordProcessorWindowID.settings) {
            Group {
                if storageStatus.isReady {
                    SettingsView()
                } else {
                    StorageUnavailableView()
                        .frame(minWidth: 560, minHeight: 380)
                }
            }
            .environment(storageStatus)
        }
        .windowResizability(.contentSize)
    }
}
