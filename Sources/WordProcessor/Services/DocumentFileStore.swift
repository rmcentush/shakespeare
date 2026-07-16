import AppKit
import CryptoKit
import Foundation
import UniformTypeIdentifiers

actor DocumentFileStore {
    static let shared = DocumentFileStore()
    static let documentPackageExtension = "shkdoc"
    static let currentSchemaVersion = 1
    static let maximumImportedImageBytes = 25 * 1024 * 1024
    static let maximumPackageAssetBytes = 250 * 1024 * 1024

    struct FileSnapshot: Sendable {
        var canonicalJSON: String?
        var htmlContent: String
        var plainText: String
        var wordCount: Int
        var characterCount: Int
        var documentID: String
        var schemaVersion: Int
        var createdAt: Date
        var modifiedAt: Date

        init(
            canonicalJSON: String? = nil,
            htmlContent: String = "",
            plainText: String? = nil,
            wordCount: Int? = nil,
            characterCount: Int? = nil,
            documentID: String = UUID().uuidString,
            schemaVersion: Int = DocumentFileStore.currentSchemaVersion,
            createdAt: Date = Date(),
            modifiedAt: Date = Date()
        ) {
            let trimmedJSON = canonicalJSON?.trimmingCharacters(in: .whitespacesAndNewlines)
            self.canonicalJSON = trimmedJSON?.isEmpty == false ? trimmedJSON : nil
            self.htmlContent = htmlContent

            let resolvedPlainText = plainText ?? Self.plainText(fromHTML: htmlContent)
            self.plainText = resolvedPlainText

            if let wordCount, let characterCount {
                self.wordCount = wordCount
                self.characterCount = characterCount
            } else {
                let metrics = Self.metrics(forPlainText: resolvedPlainText)
                self.wordCount = metrics.wordCount
                self.characterCount = metrics.characterCount
            }

            self.documentID = documentID
            self.schemaVersion = schemaVersion
            self.createdAt = createdAt
            self.modifiedAt = modifiedAt
        }

        static func empty(documentID: String = UUID().uuidString, at date: Date = Date()) -> Self {
            FileSnapshot(
                canonicalJSON: Self.emptyDocumentJSON,
                htmlContent: "",
                plainText: "",
                wordCount: 0,
                characterCount: 0,
                documentID: documentID,
                createdAt: date,
                modifiedAt: date
            )
        }

        private static let emptyDocumentJSON = """
        {
          "type": "doc",
          "content": [
            {
              "type": "paragraph"
            }
          ]
        }
        """

        private static func metrics(forPlainText text: String) -> (wordCount: Int, characterCount: Int) {
            (
                wordCount: text.split(whereSeparator: \.isWhitespace).count,
                characterCount: text.count
            )
        }

        private static func plainText(fromHTML html: String) -> String {
            guard let data = html.data(using: .utf8) else { return fallbackPlainText(fromHTML: html) }

            if let attributed = try? NSAttributedString(
                data: data,
                options: [
                    .documentType: NSAttributedString.DocumentType.html,
                    .characterEncoding: String.Encoding.utf8.rawValue,
                ],
                documentAttributes: nil
            ) {
                return attributed.string
            }

            return fallbackPlainText(fromHTML: html)
        }

        private static func fallbackPlainText(fromHTML html: String) -> String {
            html.replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
                .replacingOccurrences(of: "&nbsp;", with: " ")
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }

    private enum ContentFormat: String, Codable {
        case prosemirrorJSON = "prosemirror-json"
        case html
    }

    private struct PackageManifest: Codable {
        let schemaVersion: Int
        let documentID: String
        let createdAt: Date
        let modifiedAt: Date
        let contentFormat: ContentFormat
        let contentFileName: String
        let plainTextFileName: String?
        let wordCount: Int
        let characterCount: Int
    }

    private struct PreparedPackage {
        let snapshot: FileSnapshot
        let assets: [String: Data]
    }

    struct ClipboardImageAsset: Sendable {
        let data: Data
        let pasteboardTypeIdentifier: String?
    }

    struct StagedImageAsset: Sendable {
        let source: String
        let baseURL: URL
    }

    enum FileStoreError: LocalizedError {
        case missingPackageManifest
        case unsupportedPackageContentFormat
        case invalidDataURL
        case invalidPackagePath(String)
        case assetTooLarge(maximumMegabytes: Int)
        case packageAssetsTooLarge(maximumMegabytes: Int)
        case incompletePackageWrite(String)

        var errorDescription: String? {
            switch self {
            case .missingPackageManifest:
                return "The document package is missing its manifest."
            case .unsupportedPackageContentFormat:
                return "The document package uses an unsupported content format."
            case .invalidDataURL:
                return "The document contains an invalid embedded asset."
            case .invalidPackagePath(let filename):
                return "The document package contains an unsafe file path (\(filename))."
            case .assetTooLarge(let maximumMegabytes):
                return "Images must be \(maximumMegabytes) MB or smaller."
            case .packageAssetsTooLarge(let maximumMegabytes):
                return "Document assets must total \(maximumMegabytes) MB or less."
            case .incompletePackageWrite(let detail):
                return "The document was not saved completely (\(detail))."
            }
        }
    }

    func load(from url: URL) throws -> FileSnapshot {
        try withSecurityScopedAccess(to: [url]) {
            if Self.isNativeDocumentURL(url) {
                return try loadPackage(from: url)
            }

            let html = try String(contentsOf: url, encoding: .utf8)
            let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
            let createdAt = attributes?[.creationDate] as? Date ?? Date()
            let modifiedAt = attributes?[.modificationDate] as? Date ?? createdAt
            return FileSnapshot(
                canonicalJSON: nil,
                htmlContent: html,
                documentID: UUID().uuidString,
                createdAt: createdAt,
                modifiedAt: modifiedAt
            )
        }
    }

    @discardableResult
    func save(_ snapshot: FileSnapshot, to url: URL, sourceDocumentURL: URL? = nil) throws -> FileSnapshot {
        let accessURLs = [url, sourceDocumentURL].compactMap { $0 }

        return try withSecurityScopedAccess(to: accessURLs) {
            var updated = snapshot
            updated.modifiedAt = Date()

            if Self.isNativeDocumentURL(url) {
                let preparedPackage = try preparePackage(from: updated, sourceDocumentURL: sourceDocumentURL)
                try writePackage(preparedPackage, to: url)
                return preparedPackage.snapshot
            }

            let exportableHTML = try htmlForExport(from: updated, sourceDocumentURL: sourceDocumentURL)
            updated.htmlContent = exportableHTML
            try exportableHTML.write(to: url, atomically: true, encoding: .utf8)
            return updated
        }
    }

    func inlineHTMLForExternalTransfer(_ html: String, sourceDocumentURL: URL?) throws -> String {
        let accessURLs = [sourceDocumentURL].compactMap { $0 }

        return try withSecurityScopedAccess(to: accessURLs) {
            guard html.contains("\(DocumentAssetReference.scheme)://") else {
                return html
            }

            let assets = try referencedAssets(
                in: html,
                sourceDocumentURL: sourceDocumentURL
            )
            guard !assets.isEmpty else { return html }

            return assets.reduce(into: html) { rewrittenHTML, entry in
                let assetURL = DocumentAssetReference.urlString(for: entry.key)
                rewrittenHTML = rewrittenHTML.replacingOccurrences(
                    of: assetURL,
                    with: dataURL(for: entry.value, filename: entry.key)
                )
            }
        }
    }

    func clipboardImageAsset(for source: String, sourceDocumentURL: URL?) throws -> ClipboardImageAsset? {
        let accessURLs = [sourceDocumentURL].compactMap { $0 }

        return try withSecurityScopedAccess(to: accessURLs) {
            if source.hasPrefix("data:") {
                let payload = try dataFromDataURL(
                    source,
                    maximumBytes: Self.maximumImportedImageBytes
                )
                let type = UTType(mimeType: payload.mimeType) ?? UTType(filenameExtension: payload.fileExtension)
                return ClipboardImageAsset(
                    data: payload.data,
                    pasteboardTypeIdentifier: type?.identifier
                )
            }

            if let filename = DocumentAssetReference.filename(from: source),
               let data = try existingAssetData(named: filename, from: sourceDocumentURL) {
                let fileExtension = URL(fileURLWithPath: filename).pathExtension
                let type = UTType(filenameExtension: fileExtension)
                return ClipboardImageAsset(
                    data: data,
                    pasteboardTypeIdentifier: type?.identifier
                )
            }

            if let fileURL = URL(string: source),
               fileURL.isFileURL,
               FileManager.default.fileExists(atPath: fileURL.path) {
                let data = try imageAssetData(contentsOf: fileURL)
                let type = UTType(filenameExtension: fileURL.pathExtension)
                return ClipboardImageAsset(
                    data: data,
                    pasteboardTypeIdentifier: type?.identifier
                )
            }

            return nil
        }
    }

    func stageImageAsset(
        from dataURL: String,
        documentID: String,
        sourceDocumentURL: URL?
    ) throws -> StagedImageAsset {
        let payload = try dataFromDataURL(
            dataURL,
            maximumBytes: Self.maximumImportedImageBytes
        )
        return try stageImageAsset(
            data: payload.data,
            fileExtension: payload.fileExtension,
            documentID: documentID,
            sourceDocumentURL: sourceDocumentURL
        )
    }

    func stageImageAsset(
        from fileURL: URL,
        documentID: String,
        sourceDocumentURL: URL?
    ) throws -> StagedImageAsset {
        guard let type = UTType(filenameExtension: fileURL.pathExtension),
              type.conforms(to: .image)
        else {
            throw FileStoreError.invalidDataURL
        }
        let data = try imageAssetData(contentsOf: fileURL)
        let fileExtension = type.preferredFilenameExtension ?? fileURL.pathExtension.lowercased()
        return try stageImageAsset(
            data: data,
            fileExtension: fileExtension,
            documentID: documentID,
            sourceDocumentURL: sourceDocumentURL
        )
    }

    private func stageImageAsset(
        data: Data,
        fileExtension: String,
        documentID: String,
        sourceDocumentURL: URL?
    ) throws -> StagedImageAsset {
        let filename = assetFilename(for: data, fileExtension: fileExtension)
        let baseURL = try workingDocumentURL(for: documentID)
        let assetsURL = baseURL.appendingPathComponent(
            DocumentAssetReference.assetsDirectoryName,
            isDirectory: true
        )

        try FileManager.default.createDirectory(at: assetsURL, withIntermediateDirectories: true)
        try copyExistingAssetsIfNeeded(from: sourceDocumentURL, to: assetsURL)

        let destinationURL = assetsURL.appendingPathComponent(filename)
        if !FileManager.default.fileExists(atPath: destinationURL.path) {
            try data.write(to: destinationURL, options: .atomic)
        }

        return StagedImageAsset(
            source: DocumentAssetReference.urlString(for: filename),
            baseURL: baseURL
        )
    }

    func deleteWorkingAssets(documentID: String) throws {
        let url = try workingDocumentURL(for: documentID)
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
    }

    private func loadPackage(from url: URL) throws -> FileSnapshot {
        guard let manifestURL = DocumentAssetReference.containedFileURL(
            named: "manifest.json",
            in: url
        ), FileManager.default.fileExists(atPath: manifestURL.path) else {
            throw FileStoreError.missingPackageManifest
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let manifestData = try Data(contentsOf: manifestURL, options: .mappedIfSafe)
        let manifest = try decoder.decode(PackageManifest.self, from: manifestData)

        let plainText: String
        if let plainTextFileName = manifest.plainTextFileName {
            guard let plainTextURL = DocumentAssetReference.containedFileURL(
                named: plainTextFileName,
                in: url
            ) else {
                throw FileStoreError.invalidPackagePath(plainTextFileName)
            }
            plainText = (try? String(contentsOf: plainTextURL, encoding: .utf8)) ?? ""
        } else {
            plainText = ""
        }

        guard let contentURL = DocumentAssetReference.containedFileURL(
            named: manifest.contentFileName,
            in: url
        ) else {
            throw FileStoreError.invalidPackagePath(manifest.contentFileName)
        }
        switch manifest.contentFormat {
        case .prosemirrorJSON:
            let canonicalJSON = try String(contentsOf: contentURL, encoding: .utf8)
            return FileSnapshot(
                canonicalJSON: canonicalJSON,
                htmlContent: "",
                plainText: plainText,
                wordCount: manifest.wordCount,
                characterCount: manifest.characterCount,
                documentID: manifest.documentID,
                schemaVersion: manifest.schemaVersion,
                createdAt: manifest.createdAt,
                modifiedAt: manifest.modifiedAt
            )

        case .html:
            let html = try String(contentsOf: contentURL, encoding: .utf8)
            return FileSnapshot(
                canonicalJSON: nil,
                htmlContent: html,
                plainText: plainText.isEmpty ? nil : plainText,
                wordCount: manifest.wordCount,
                characterCount: manifest.characterCount,
                documentID: manifest.documentID,
                schemaVersion: manifest.schemaVersion,
                createdAt: manifest.createdAt,
                modifiedAt: manifest.modifiedAt
            )
        }
    }

    private func preparePackage(from snapshot: FileSnapshot, sourceDocumentURL: URL?) throws -> PreparedPackage {
        var updated = snapshot
        var assets = try referencedAssets(
            in: updated.htmlContent,
            sourceDocumentURL: sourceDocumentURL
        )

        if let canonicalJSON = updated.canonicalJSON {
            updated.canonicalJSON = try rewriteDocumentJSON(
                canonicalJSON,
                assets: &assets,
                sourceDocumentURL: sourceDocumentURL
            )
        }

        try validatePackageAssetTotal(assets)

        return PreparedPackage(snapshot: updated, assets: assets)
    }

    private func writePackage(_ preparedPackage: PreparedPackage, to url: URL) throws {
        let snapshot = preparedPackage.snapshot
        let hasCanonicalJSON = snapshot.canonicalJSON?.isEmpty == false
        let contentFormat: ContentFormat = hasCanonicalJSON ? .prosemirrorJSON : .html
        let contentFileName = hasCanonicalJSON ? "content.json" : "content.html"
        let plainTextFileName = "preview.txt"

        let manifest = PackageManifest(
            schemaVersion: snapshot.schemaVersion,
            documentID: snapshot.documentID,
            createdAt: snapshot.createdAt,
            modifiedAt: snapshot.modifiedAt,
            contentFormat: contentFormat,
            contentFileName: contentFileName,
            plainTextFileName: plainTextFileName,
            wordCount: snapshot.wordCount,
            characterCount: snapshot.characterCount
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601

        var fileWrappers: [String: FileWrapper] = [:]
        fileWrappers["manifest.json"] = regularFileWrapper(
            named: "manifest.json",
            contents: try encoder.encode(manifest)
        )
        fileWrappers[contentFileName] = regularFileWrapper(
            named: contentFileName,
            contents: Data((hasCanonicalJSON ? snapshot.canonicalJSON! : snapshot.htmlContent).utf8)
        )
        fileWrappers[plainTextFileName] = regularFileWrapper(
            named: plainTextFileName,
            contents: Data(snapshot.plainText.utf8)
        )

        let assetWrappers = preparedPackage.assets.reduce(into: [String: FileWrapper]()) { result, entry in
            result[entry.key] = regularFileWrapper(named: entry.key, contents: entry.value)
        }
        let assetsDirectory = FileWrapper(directoryWithFileWrappers: assetWrappers)
        assetsDirectory.preferredFilename = DocumentAssetReference.assetsDirectoryName
        fileWrappers[DocumentAssetReference.assetsDirectoryName] = assetsDirectory

        let rootWrapper = FileWrapper(directoryWithFileWrappers: fileWrappers)
        rootWrapper.preferredFilename = url.lastPathComponent

        let originalContentsURL = FileManager.default.fileExists(atPath: url.path) ? url : nil
        try rootWrapper.write(to: url, options: [.atomic, .withNameUpdating], originalContentsURL: originalContentsURL)
        try validateWrittenPackage(at: url, contentFileName: contentFileName)
    }

    /// Verifies the package on disk is complete after a write, so a partial or
    /// corrupted write surfaces as a save error instead of silent data loss.
    private func validateWrittenPackage(at url: URL, contentFileName: String) throws {
        let manifestURL = url.appendingPathComponent("manifest.json")
        guard let manifestData = try? Data(contentsOf: manifestURL), !manifestData.isEmpty else {
            throw FileStoreError.incompletePackageWrite("manifest.json missing or empty")
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard (try? decoder.decode(PackageManifest.self, from: manifestData)) != nil else {
            throw FileStoreError.incompletePackageWrite("manifest.json unreadable")
        }
        let contentURL = url.appendingPathComponent(contentFileName)
        guard FileManager.default.fileExists(atPath: contentURL.path) else {
            throw FileStoreError.incompletePackageWrite("\(contentFileName) missing")
        }
    }

    private func rewriteDocumentJSON(
        _ canonicalJSON: String,
        assets: inout [String: Data],
        sourceDocumentURL: URL?
    ) throws -> String {
        let data = Data(canonicalJSON.utf8)
        let object = try JSONSerialization.jsonObject(with: data)
        let rewritten = try rewriteAssetSources(in: object, assets: &assets, sourceDocumentURL: sourceDocumentURL)
        let rewrittenData = try JSONSerialization.data(withJSONObject: rewritten, options: [.prettyPrinted, .sortedKeys])
        return String(decoding: rewrittenData, as: UTF8.self)
    }

    private func rewriteAssetSources(
        in value: Any,
        assets: inout [String: Data],
        sourceDocumentURL: URL?
    ) throws -> Any {
        if let array = value as? [Any] {
            return try array.map { try rewriteAssetSources(in: $0, assets: &assets, sourceDocumentURL: sourceDocumentURL) }
        }

        if var dictionary = value as? [String: Any] {
            if dictionary["type"] as? String == "image",
               var attrs = dictionary["attrs"] as? [String: Any],
               let source = attrs["src"] as? String {
                attrs["src"] = try normalizedImageSource(
                    from: source,
                    assets: &assets,
                    sourceDocumentURL: sourceDocumentURL
                )
                dictionary["attrs"] = attrs
            }

            for (key, nestedValue) in dictionary {
                if key == "attrs" || key == "src" {
                    continue
                }
                dictionary[key] = try rewriteAssetSources(
                    in: nestedValue,
                    assets: &assets,
                    sourceDocumentURL: sourceDocumentURL
                )
            }
            return dictionary
        }

        return value
    }

    private func normalizedImageSource(
        from source: String,
        assets: inout [String: Data],
        sourceDocumentURL: URL?
    ) throws -> String {
        if source.hasPrefix("data:") {
            let payload = try dataFromDataURL(
                source,
                maximumBytes: Self.maximumImportedImageBytes
            )
            let filename = assetFilename(for: payload.data, fileExtension: payload.fileExtension)
            assets[filename] = payload.data
            return DocumentAssetReference.urlString(for: filename)
        }

        if let filename = DocumentAssetReference.filename(from: source) {
            if assets[filename] == nil,
               let existingData = try existingAssetData(named: filename, from: sourceDocumentURL) {
                assets[filename] = existingData
            }
            return DocumentAssetReference.urlString(for: filename)
        }

        return source
    }

    private func referencedAssets(
        in html: String,
        sourceDocumentURL: URL?
    ) throws -> [String: Data] {
        guard let sourceDocumentURL,
              Self.isNativeDocumentURL(sourceDocumentURL)
        else {
            return [:]
        }

        var result: [String: Data] = [:]
        for filename in DocumentAssetReference.filenames(in: html) {
            if let data = try existingAssetData(named: filename, from: sourceDocumentURL) {
                result[filename] = data
            }
        }
        try validatePackageAssetTotal(result)
        return result
    }

    private func validatePackageAssetTotal(_ assets: [String: Data]) throws {
        let totalBytes = assets.values.reduce(0) { partialResult, data in
            partialResult + data.count
        }
        guard totalBytes <= Self.maximumPackageAssetBytes else {
            throw FileStoreError.packageAssetsTooLarge(
                maximumMegabytes: Self.maximumPackageAssetBytes / 1024 / 1024
            )
        }
    }

    private func workingDocumentURL(for documentID: String) throws -> URL {
        guard let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first else {
            throw CocoaError(.fileNoSuchFile)
        }
        let safeID = documentID.replacingOccurrences(
            of: "[^A-Za-z0-9_-]",
            with: "-",
            options: .regularExpression
        )
        let directory = appSupport
            .appendingPathComponent("Shakespeare", isDirectory: true)
            .appendingPathComponent("WorkingDocuments", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent(
            "\(safeID.isEmpty ? UUID().uuidString : safeID).\(Self.documentPackageExtension)",
            isDirectory: true
        )
    }

    private func copyExistingAssetsIfNeeded(from sourceDocumentURL: URL?, to destination: URL) throws {
        guard let sourceDocumentURL,
              Self.isNativeDocumentURL(sourceDocumentURL),
              sourceDocumentURL.standardizedFileURL != destination.deletingLastPathComponent().standardizedFileURL
        else { return }

        try withSecurityScopedAccess(to: [sourceDocumentURL]) {
            guard let source = DocumentAssetReference.containedFileURL(
                named: DocumentAssetReference.assetsDirectoryName,
                in: sourceDocumentURL
            ) else { return }
            guard FileManager.default.fileExists(atPath: source.path) else { return }
            let files = try FileManager.default.contentsOfDirectory(
                at: source,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            )
            for listedURL in files {
                let filename = listedURL.lastPathComponent
                guard let file = DocumentAssetReference.containedFileURL(
                    named: filename,
                    in: source
                ) else { continue }
                let target = destination.appendingPathComponent(filename)
                guard !FileManager.default.fileExists(atPath: target.path) else { continue }
                do {
                    try FileManager.default.linkItem(at: file, to: target)
                } catch {
                    try FileManager.default.copyItem(at: file, to: target)
                }
            }
        }
    }

    private func htmlForExport(from snapshot: FileSnapshot, sourceDocumentURL: URL?) throws -> String {
        try inlineHTMLForExternalTransfer(snapshot.htmlContent, sourceDocumentURL: sourceDocumentURL)
    }

    private func existingAssetData(named filename: String, from sourceDocumentURL: URL?) throws -> Data? {
        guard let sourceDocumentURL,
              Self.isNativeDocumentURL(sourceDocumentURL)
        else {
            return nil
        }

        guard let assetsDirectory = DocumentAssetReference.containedFileURL(
            named: DocumentAssetReference.assetsDirectoryName,
            in: sourceDocumentURL
        ), let assetURL = DocumentAssetReference.containedFileURL(
            named: filename,
            in: assetsDirectory
        ) else {
            return nil
        }

        guard FileManager.default.fileExists(atPath: assetURL.path) else { return nil }
        return try imageAssetData(contentsOf: assetURL)
    }

    private func imageAssetData(contentsOf url: URL) throws -> Data {
        let values = try url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
        guard values.isRegularFile == true else {
            throw CocoaError(.fileReadUnsupportedScheme)
        }
        if let fileSize = values.fileSize, fileSize > Self.maximumImportedImageBytes {
            throw FileStoreError.assetTooLarge(
                maximumMegabytes: Self.maximumImportedImageBytes / 1024 / 1024
            )
        }
        return try Data(contentsOf: url, options: .mappedIfSafe)
    }

    private func dataFromDataURL(
        _ source: String,
        maximumBytes: Int? = nil
    ) throws -> (data: Data, mimeType: String, fileExtension: String) {
        if let maximumBytes, source.utf8.count > maximumBytes * 2 {
            throw FileStoreError.assetTooLarge(maximumMegabytes: maximumBytes / 1024 / 1024)
        }

        guard let commaIndex = source.firstIndex(of: ",") else {
            throw FileStoreError.invalidDataURL
        }

        let header = String(source[..<commaIndex])
        let payload = String(source[source.index(after: commaIndex)...])
        let metadata = String(header.dropFirst("data:".count))
        let parts = metadata.split(separator: ";")
        let mimeType = parts.first.map(String.init) ?? "application/octet-stream"
        guard mimeType.lowercased().hasPrefix("image/") else {
            throw FileStoreError.invalidDataURL
        }

        let data: Data
        if metadata.contains("base64") {
            guard let decoded = Data(base64Encoded: payload) else {
                throw FileStoreError.invalidDataURL
            }
            data = decoded
        } else if let decodedPayload = payload.removingPercentEncoding {
            data = Data(decodedPayload.utf8)
        } else {
            throw FileStoreError.invalidDataURL
        }

        if let maximumBytes, data.count > maximumBytes {
            throw FileStoreError.assetTooLarge(maximumMegabytes: maximumBytes / 1024 / 1024)
        }

        let fileExtension = UTType(mimeType: mimeType)?.preferredFilenameExtension ?? fileExtension(forMIMEType: mimeType)
        return (data, mimeType, fileExtension)
    }

    private func assetFilename(for data: Data, fileExtension: String) -> String {
        let digest = SHA256.hash(data: data)
        let hash = digest.map { String(format: "%02x", $0) }.joined()
        return "\(hash).\(fileExtension)"
    }

    private func fileExtension(forMIMEType mimeType: String) -> String {
        switch mimeType.lowercased() {
        case "image/png":
            return "png"
        case "image/gif":
            return "gif"
        case "image/webp":
            return "webp"
        case "image/svg+xml":
            return "svg"
        default:
            return "jpg"
        }
    }

    private func dataURL(for data: Data, filename: String) -> String {
        let fileExtension = URL(fileURLWithPath: filename).pathExtension
        let mimeType = UTType(filenameExtension: fileExtension)?.preferredMIMEType ?? "application/octet-stream"
        return "data:\(mimeType);base64,\(data.base64EncodedString())"
    }

    private func regularFileWrapper(named filename: String, contents: Data) -> FileWrapper {
        let wrapper = FileWrapper(regularFileWithContents: contents)
        wrapper.preferredFilename = filename
        return wrapper
    }

    private func withSecurityScopedAccess<T>(to urls: [URL], operation: () throws -> T) throws -> T {
        let uniqueURLs = urls.reduce(into: [URL]()) { result, url in
            if !result.contains(url) {
                result.append(url)
            }
        }

        let accessedURLs = uniqueURLs.filter { $0.startAccessingSecurityScopedResource() }
        defer {
            accessedURLs.forEach { $0.stopAccessingSecurityScopedResource() }
        }
        return try operation()
    }

    static func isNativeDocumentURL(_ url: URL) -> Bool {
        url.pathExtension.lowercased() == documentPackageExtension
    }
}
