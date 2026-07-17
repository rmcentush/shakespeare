import Foundation

/// Owns every mutable file created by Shakespeare. User-saved documents remain
/// wherever the writer chooses; internal state stays under one Application
/// Support root with a stable, inspectable layout.
enum ShakespeareStorage {
    private static let lock = NSLock()
    private static var preparedRoots: Set<String> = []

    static var rootURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Shakespeare", isDirectory: true)
    }

    static var documentsDirectoryURL: URL {
        rootURL.appendingPathComponent("documents", isDirectory: true)
    }

    static var workingDocumentsDirectoryURL: URL {
        documentsDirectoryURL.appendingPathComponent("working", isDirectory: true)
    }

    static var recoveryDraftsDirectoryURL: URL {
        documentsDirectoryURL.appendingPathComponent("recovery", isDirectory: true)
    }

    static var versionsDatabaseURL: URL {
        documentsDirectoryURL.appendingPathComponent("versions.sqlite", isDirectory: false)
    }

    static var personalizationDirectoryURL: URL {
        rootURL.appendingPathComponent("personalization", isDirectory: true)
    }

    static var personalizationEventsDirectoryURL: URL {
        personalizationDirectoryURL.appendingPathComponent("events", isDirectory: true)
    }

    static var styleDirectoryURL: URL {
        personalizationDirectoryURL.appendingPathComponent("style", isDirectory: true)
    }

    static var credentialsDirectoryURL: URL {
        rootURL.appendingPathComponent("credentials", isDirectory: true)
    }

    static func prepare() throws {
        try prepare(rootURL: rootURL)
    }

    static func resetPersonalization() throws {
        try resetPersonalization(rootURL: rootURL)
    }

    /// Removes locally learned evidence while preserving the writer-maintained
    /// style reference. The injectable root keeps deletion behavior testable.
    static func resetPersonalization(rootURL: URL) throws {
        lock.lock()
        defer { lock.unlock() }

        let fileManager = FileManager.default
        let standardizedRoot = rootURL.standardizedFileURL
        let personalization = standardizedRoot
            .appendingPathComponent("personalization", isDirectory: true)
        let events = personalization.appendingPathComponent("events", isDirectory: true)
        let style = personalization.appendingPathComponent("style", isDirectory: true)

        try createPrivateDirectory(standardizedRoot, fileManager: fileManager)
        try createPrivateDirectory(personalization, fileManager: fileManager)

        for entry in try fileManager.contentsOfDirectory(
            at: personalization,
            includingPropertiesForKeys: [.isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey],
            options: []
        ) {
            if entry.lastPathComponent == "style" {
                let values = try entry.resourceValues(
                    forKeys: [.isDirectoryKey, .isSymbolicLinkKey]
                )
                if values.isDirectory != true || values.isSymbolicLink == true {
                    try fileManager.removeItem(at: entry)
                }
                continue
            }
            try fileManager.removeItem(at: entry)
        }

        try createPrivateDirectory(style, fileManager: fileManager)
        for entry in try fileManager.contentsOfDirectory(
            at: style,
            includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey],
            options: []
        ) {
            let values = try entry.resourceValues(
                forKeys: [.isRegularFileKey, .isSymbolicLinkKey]
            )
            let isWritableReference = entry.lastPathComponent == "writing_style_reference.md"
                && values.isRegularFile == true
                && values.isSymbolicLink != true
            if isWritableReference {
                try fileManager.setAttributes(
                    [.posixPermissions: 0o600], ofItemAtPath: entry.path
                )
            } else {
                try fileManager.removeItem(at: entry)
            }
        }

        for directory in [personalization, events, style] {
            try createPrivateDirectory(directory, fileManager: fileManager)
        }
    }

    /// The injectable root keeps migration behavior deterministic in evals.
    static func prepare(rootURL: URL) throws {
        let standardizedRoot = rootURL.standardizedFileURL
        lock.lock()
        defer { lock.unlock() }
        guard !preparedRoots.contains(standardizedRoot.path) else { return }

        let fileManager = FileManager.default
        try createPrivateDirectory(standardizedRoot, fileManager: fileManager)

        let documents = standardizedRoot.appendingPathComponent("documents", isDirectory: true)
        let personalization = standardizedRoot.appendingPathComponent(
            "personalization", isDirectory: true
        )
        let events = personalization.appendingPathComponent("events", isDirectory: true)
        let style = personalization.appendingPathComponent("style", isDirectory: true)
        let credentials = standardizedRoot.appendingPathComponent(
            "credentials", isDirectory: true
        )

        for directory in [documents, personalization, events, style, credentials] {
            try createPrivateDirectory(directory, fileManager: fileManager)
        }

        try migrateItem(
            from: standardizedRoot.appendingPathComponent("WorkingDocuments"),
            to: documents.appendingPathComponent("working"),
            root: standardizedRoot,
            fileManager: fileManager
        )
        try migrateItem(
            from: standardizedRoot.appendingPathComponent("RecoveryDrafts"),
            to: documents.appendingPathComponent("recovery"),
            root: standardizedRoot,
            fileManager: fileManager
        )
        for suffix in ["", "-wal", "-shm"] {
            try migrateItem(
                from: standardizedRoot.appendingPathComponent("versions.sqlite\(suffix)"),
                to: documents.appendingPathComponent("versions.sqlite\(suffix)"),
                root: standardizedRoot,
                fileManager: fileManager
            )
        }
        try migrateItem(
            from: standardizedRoot.appendingPathComponent("style"),
            to: style,
            root: standardizedRoot,
            fileManager: fileManager
        )
        try migrateJSONLines(
            from: personalization.appendingPathComponent("training_events.jsonl"),
            to: events.appendingPathComponent("training_events.jsonl"),
            fileManager: fileManager
        )
        try migrateFallbackCredentials(
            root: standardizedRoot,
            destination: credentials,
            fileManager: fileManager
        )

        for directory in [
            documents.appendingPathComponent("working", isDirectory: true),
            documents.appendingPathComponent("recovery", isDirectory: true),
        ] {
            try createPrivateDirectory(directory, fileManager: fileManager)
        }

        let readme = standardizedRoot.appendingPathComponent("README.txt")
        if !fileManager.fileExists(atPath: readme.path) {
            try Self.readmeText.write(to: readme, atomically: true, encoding: .utf8)
            try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: readme.path)
        }

        preparedRoots.insert(standardizedRoot.path)
    }

    private static func createPrivateDirectory(
        _ url: URL,
        fileManager: FileManager
    ) throws {
        try fileManager.createDirectory(
            at: url,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        try fileManager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: url.path)
    }

    private static func migrateJSONLines(
        from source: URL,
        to destination: URL,
        fileManager: FileManager
    ) throws {
        guard fileManager.fileExists(atPath: source.path) else { return }
        guard fileManager.fileExists(atPath: destination.path) else {
            try fileManager.moveItem(at: source, to: destination)
            try fileManager.setAttributes(
                [.posixPermissions: 0o600], ofItemAtPath: destination.path
            )
            return
        }

        let sourceLines = (try String(contentsOf: source, encoding: .utf8))
            .split(separator: "\n").map(String.init)
        let destinationLines = (try String(contentsOf: destination, encoding: .utf8))
            .split(separator: "\n").map(String.init)
        var seen = Set<String>()
        let merged = (sourceLines + destinationLines).filter { seen.insert($0).inserted }
        let temporary = destination.appendingPathExtension("migrating")
        try (merged.joined(separator: "\n") + (merged.isEmpty ? "" : "\n"))
            .write(to: temporary, atomically: true, encoding: .utf8)
        try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: temporary.path)
        _ = try fileManager.replaceItemAt(destination, withItemAt: temporary)
        try fileManager.removeItem(at: source)
    }

    private static func migrateFallbackCredentials(
        root: URL,
        destination: URL,
        fileManager: FileManager
    ) throws {
        let entries = try fileManager.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey],
            options: []
        )
        for source in entries {
            let name = source.lastPathComponent
            guard name.hasPrefix("."), name.hasSuffix(".key"), name.count > 5 else {
                continue
            }
            let values = try source.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
            guard values.isRegularFile == true, values.isSymbolicLink != true else { continue }
            let service = String(name.dropFirst().dropLast(4))
            guard service.range(of: "^[A-Za-z0-9_-]+$", options: .regularExpression) != nil
            else { continue }
            try migrateItem(
                from: source,
                to: destination.appendingPathComponent("\(service).key"),
                root: root,
                fileManager: fileManager
            )
        }
    }

    private static func migrateItem(
        from source: URL,
        to destination: URL,
        root: URL,
        fileManager: FileManager
    ) throws {
        guard fileManager.fileExists(atPath: source.path) else { return }
        guard fileManager.fileExists(atPath: destination.path) else {
            try fileManager.createDirectory(
                at: destination.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try fileManager.moveItem(at: source, to: destination)
            return
        }

        let sourceValues = try source.resourceValues(forKeys: [.isDirectoryKey])
        let destinationValues = try destination.resourceValues(forKeys: [.isDirectoryKey])
        if sourceValues.isDirectory == true, destinationValues.isDirectory == true {
            for child in try fileManager.contentsOfDirectory(
                at: source,
                includingPropertiesForKeys: nil,
                options: []
            ) {
                try migrateItem(
                    from: child,
                    to: destination.appendingPathComponent(child.lastPathComponent),
                    root: root,
                    fileManager: fileManager
                )
            }
            try fileManager.removeItem(at: source)
            return
        }

        if sourceValues.isDirectory != true,
           destinationValues.isDirectory != true,
           (try? Data(contentsOf: source)) == (try? Data(contentsOf: destination)) {
            try fileManager.removeItem(at: source)
            return
        }

        let conflicts = root.appendingPathComponent("migration-conflicts", isDirectory: true)
        try createPrivateDirectory(conflicts, fileManager: fileManager)
        let conflictURL = conflicts.appendingPathComponent(
            "\(UUID().uuidString)-\(source.lastPathComponent)"
        )
        try fileManager.moveItem(at: source, to: conflictURL)
    }

    private static let readmeText = """
    Shakespeare application data

    documents/       Working copies, recovery drafts, and local version history.
    personalization/ Opt-in learning events, writing samples, and reviewed
                     style preferences.
    credentials/     Owner-only development fallback files. Normal installs keep
                     API keys in macOS Keychain instead.

    Documents you explicitly save remain in the folder you chose. App preferences
    use the standard macOS Preferences system. You can reveal this folder from
    Settings > My Style > Files and Privacy.
    """
}
