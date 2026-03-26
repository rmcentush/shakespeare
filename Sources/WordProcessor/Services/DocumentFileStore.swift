import AppKit
import CryptoKit
import Foundation
import UniformTypeIdentifiers

actor DocumentFileStore {
    static let shared = DocumentFileStore()
    static let documentPackageExtension = "shkdoc"
    static let currentSchemaVersion = 1

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

    enum FileStoreError: LocalizedError {
        case missingPackageManifest
        case unsupportedPackageContentFormat
        case invalidDataURL

        var errorDescription: String? {
            switch self {
            case .missingPackageManifest:
                return "The document package is missing its manifest."
            case .unsupportedPackageContentFormat:
                return "The document package uses an unsupported content format."
            case .invalidDataURL:
                return "The document contains an invalid embedded asset."
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

    private func loadPackage(from url: URL) throws -> FileSnapshot {
        let manifestURL = url.appendingPathComponent("manifest.json")
        guard FileManager.default.fileExists(atPath: manifestURL.path) else {
            throw FileStoreError.missingPackageManifest
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let manifestData = try Data(contentsOf: manifestURL, options: .mappedIfSafe)
        let manifest = try decoder.decode(PackageManifest.self, from: manifestData)

        let plainText: String
        if let plainTextFileName = manifest.plainTextFileName {
            let plainTextURL = url.appendingPathComponent(plainTextFileName)
            plainText = (try? String(contentsOf: plainTextURL, encoding: .utf8)) ?? ""
        } else {
            plainText = ""
        }

        let contentURL = url.appendingPathComponent(manifest.contentFileName)
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
        var assets = try existingAssets(from: sourceDocumentURL)

        if let canonicalJSON = updated.canonicalJSON {
            updated.canonicalJSON = try rewriteDocumentJSON(
                canonicalJSON,
                assets: &assets,
                sourceDocumentURL: sourceDocumentURL
            )
        }

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
            let (data, fileExtension) = try dataFromDataURL(source)
            let filename = assetFilename(for: data, fileExtension: fileExtension)
            assets[filename] = data
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

    private func existingAssets(from sourceDocumentURL: URL?) throws -> [String: Data] {
        guard let sourceDocumentURL,
              Self.isNativeDocumentURL(sourceDocumentURL)
        else {
            return [:]
        }

        let assetsURL = sourceDocumentURL.appendingPathComponent(DocumentAssetReference.assetsDirectoryName, isDirectory: true)
        guard FileManager.default.fileExists(atPath: assetsURL.path) else { return [:] }

        let assetURLs = try FileManager.default.contentsOfDirectory(
            at: assetsURL,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )

        return try assetURLs.reduce(into: [String: Data]()) { result, assetURL in
            result[assetURL.lastPathComponent] = try Data(contentsOf: assetURL, options: .mappedIfSafe)
        }
    }

    private func htmlForExport(from snapshot: FileSnapshot, sourceDocumentURL: URL?) throws -> String {
        guard let sourceDocumentURL,
              Self.isNativeDocumentURL(sourceDocumentURL),
              snapshot.htmlContent.contains("\(DocumentAssetReference.scheme)://")
        else {
            return snapshot.htmlContent
        }

        let assets = try existingAssets(from: sourceDocumentURL)
        guard !assets.isEmpty else { return snapshot.htmlContent }

        return assets.reduce(into: snapshot.htmlContent) { html, entry in
            let assetURL = DocumentAssetReference.urlString(for: entry.key)
            html = html.replacingOccurrences(of: assetURL, with: dataURL(for: entry.value, filename: entry.key))
        }
    }

    private func existingAssetData(named filename: String, from sourceDocumentURL: URL?) throws -> Data? {
        guard let sourceDocumentURL,
              Self.isNativeDocumentURL(sourceDocumentURL)
        else {
            return nil
        }

        let assetURL = sourceDocumentURL
            .appendingPathComponent(DocumentAssetReference.assetsDirectoryName, isDirectory: true)
            .appendingPathComponent(filename)

        guard FileManager.default.fileExists(atPath: assetURL.path) else { return nil }
        return try Data(contentsOf: assetURL, options: .mappedIfSafe)
    }

    private func dataFromDataURL(_ source: String) throws -> (data: Data, fileExtension: String) {
        guard let commaIndex = source.firstIndex(of: ",") else {
            throw FileStoreError.invalidDataURL
        }

        let header = String(source[..<commaIndex])
        let payload = String(source[source.index(after: commaIndex)...])
        let metadata = String(header.dropFirst("data:".count))
        let parts = metadata.split(separator: ";")
        let mimeType = parts.first.map(String.init) ?? "application/octet-stream"

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

        let fileExtension = UTType(mimeType: mimeType)?.preferredFilenameExtension ?? fileExtension(forMIMEType: mimeType)
        return (data, fileExtension)
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
