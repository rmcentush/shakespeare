import AppKit
import CryptoKit
import Foundation
import ImageIO
import UniformTypeIdentifiers

actor DocumentFileStore {
    static let shared = DocumentFileStore()
    static let documentPackageExtension = "shkdoc"
    static let currentSchemaVersion = 1
    static let maximumImportedImageBytes = 10 * 1024 * 1024
    static let maximumPackageAssetFileBytes = 25 * 1024 * 1024
    static let maximumPackageAssetBytes = 250 * 1024 * 1024
    static let maximumPackageAssetCount = 2_048
    static let maximumImagePixelCount = 40_000_000
    static let maximumImageDimension = 12_000
    static let maximumImageFrameCount = 500
    static let maximumManifestBytes = 64 * 1024
    static let maximumDocumentContentBytes = 32 * 1024 * 1024
    static let maximumImportedDocumentBytes = 32 * 1024 * 1024
    static let maximumPlainTextPreviewBytes = 16 * 1024 * 1024
    static let maximumDocumentNotesBytes = 4 * 1024 * 1024

    struct FileSnapshot: Sendable {
        var canonicalJSON: String?
        var htmlContent: String
        var plainText: String
        var notes: String
        var wordCount: Int
        var characterCount: Int
        var documentID: String
        var schemaVersion: Int
        var createdAt: Date
        var modifiedAt: Date
        var personalizationOutcomes: [PersonalizationOutcomeSnapshot]

        init(
            canonicalJSON: String? = nil,
            htmlContent: String = "",
            plainText: String? = nil,
            notes: String = "",
            wordCount: Int? = nil,
            characterCount: Int? = nil,
            documentID: String = UUID().uuidString,
            schemaVersion: Int = DocumentFileStore.currentSchemaVersion,
            createdAt: Date = Date(),
            modifiedAt: Date = Date(),
            personalizationOutcomes: [PersonalizationOutcomeSnapshot] = []
        ) {
            let trimmedJSON = canonicalJSON?.trimmingCharacters(in: .whitespacesAndNewlines)
            self.canonicalJSON = trimmedJSON?.isEmpty == false ? trimmedJSON : nil
            self.htmlContent = htmlContent
            self.notes = notes

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
            self.personalizationOutcomes = personalizationOutcomes
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
        let notesFileName: String?
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
        case invalidDataURL
        case invalidPackagePath(String)
        case invalidPackageManifest
        case invalidDocumentContent(String)
        case missingReferencedAsset(String)
        case assetTooLarge(maximumMegabytes: Int)
        case imageDimensionsTooLarge(maximumPixels: Int, maximumDimension: Int)
        case packageAssetsTooLarge(maximumMegabytes: Int)
        case incompletePackageWrite(String)
        case unsupportedDocumentFormat(String)

        var errorDescription: String? {
            switch self {
            case .missingPackageManifest:
                return "The document package is missing its manifest."
            case .invalidDataURL:
                return "The document contains an invalid embedded asset."
            case .invalidPackagePath(let filename):
                return "The document package contains an unsafe file path (\(filename))."
            case .invalidPackageManifest:
                return "The document package manifest contains invalid values."
            case .invalidDocumentContent(let detail):
                return "The document package contains invalid content (\(detail))."
            case .missingReferencedAsset(let filename):
                return "The document is missing a referenced image (\(filename))."
            case .assetTooLarge(let maximumMegabytes):
                return "Images must be \(maximumMegabytes) MB or smaller."
            case .imageDimensionsTooLarge(let maximumPixels, let maximumDimension):
                return "Images must be at most \(maximumDimension) pixels on either side and \(maximumPixels / 1_000_000) megapixels."
            case .packageAssetsTooLarge(let maximumMegabytes):
                return "Document assets must total \(maximumMegabytes) MB or less."
            case .incompletePackageWrite(let detail):
                return "The document was not saved completely (\(detail))."
            case .unsupportedDocumentFormat(let fileExtension):
                let suffix = fileExtension.isEmpty ? "this file type" : ".\(fileExtension)"
                return "Shakespeare cannot open or save \(suffix)."
            }
        }
    }

    func load(from url: URL) throws -> FileSnapshot {
        try withSecurityScopedAccess(to: [url]) {
            if Self.isNativeDocumentURL(url) {
                return try loadPackage(from: url)
            }
            return try loadPortableDocument(from: url)
        }
    }

    func rename(from sourceURL: URL, to destinationURL: URL) throws {
        try withSecurityScopedAccess(to: [sourceURL, sourceURL.deletingLastPathComponent()]) {
            let fileManager = FileManager.default
            guard sourceURL != destinationURL else { return }
            if fileManager.fileExists(atPath: destinationURL.path) {
                guard sourceURL.path.caseInsensitiveCompare(destinationURL.path) == .orderedSame else {
                    throw CocoaError(.fileWriteFileExists)
                }

                let temporaryURL = sourceURL.deletingLastPathComponent()
                    .appendingPathComponent(".shakespeare-rename-\(UUID().uuidString)")
                try fileManager.moveItem(at: sourceURL, to: temporaryURL)
                do {
                    try fileManager.moveItem(at: temporaryURL, to: destinationURL)
                } catch {
                    try? fileManager.moveItem(at: temporaryURL, to: sourceURL)
                    throw error
                }
                return
            }
            try fileManager.moveItem(at: sourceURL, to: destinationURL)
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

            guard PortableDocumentFormat.format(for: url) == .html else {
                throw FileStoreError.unsupportedDocumentFormat(url.pathExtension.lowercased())
            }
            let exportableHTML = try htmlForExport(from: updated, sourceDocumentURL: sourceDocumentURL)
            updated.htmlContent = exportableHTML
            try exportableHTML.write(to: url, atomically: true, encoding: .utf8)
            return updated
        }
    }

    func export(
        _ snapshot: FileSnapshot,
        as format: PortableDocumentFormat,
        to url: URL,
        sourceDocumentURL: URL?
    ) throws {
        let accessURLs = [url, sourceDocumentURL].compactMap { $0 }
        try withSecurityScopedAccess(to: accessURLs) {
            switch format {
            case .html:
                let html = try htmlForExport(
                    from: snapshot,
                    sourceDocumentURL: sourceDocumentURL
                )
                try html.write(to: url, atomically: true, encoding: .utf8)

            case .plainText:
                try snapshot.plainText.write(to: url, atomically: true, encoding: .utf8)

            case .markdown:
                guard let canonicalJSON = snapshot.canonicalJSON else {
                    throw StandardDocumentCodecError.invalidDocument("structured")
                }
                try CanonicalDocumentValidator.validate(canonicalJSON)
                let markdown = try StandardDocumentCodec.markdown(
                    fromCanonicalJSON: canonicalJSON
                ) { source in
                    try portableImageSource(
                        source,
                        sourceDocumentURL: sourceDocumentURL
                    )
                }
                try markdown.write(to: url, atomically: true, encoding: .utf8)

            case .word, .legacyWord, .openDocument, .richText, .richTextDirectory:
                let html = try htmlForExport(
                    from: snapshot,
                    sourceDocumentURL: sourceDocumentURL
                )
                let attributedString = try StandardDocumentCodec.attributedString(fromHTML: html)
                if format != .richTextDirectory,
                   StandardDocumentCodec.containsAttachments(attributedString) {
                    throw StandardDocumentCodecError.embeddedImagesUnsupported(format.displayName)
                }

                if format == .richTextDirectory {
                    let wrapper = try StandardDocumentCodec.rtfdWrapper(from: attributedString)
                    let originalContentsURL = FileManager.default.fileExists(atPath: url.path)
                        ? url
                        : nil
                    try wrapper.write(
                        to: url,
                        options: [.atomic, .withNameUpdating],
                        originalContentsURL: originalContentsURL
                    )
                } else {
                    let data = try StandardDocumentCodec.encodedData(
                        from: attributedString,
                        format: format
                    )
                    try data.write(to: url, options: .atomic)
                }
            }
        }
    }

    func assetBaseURL(for snapshot: FileSnapshot, sourceURL: URL) throws -> URL? {
        if Self.isNativeDocumentURL(sourceURL) {
            return sourceURL
        }

        var filenames = DocumentAssetReference.filenames(in: snapshot.htmlContent)
        if let canonicalJSON = snapshot.canonicalJSON {
            filenames.formUnion(
                DocumentAssetReference.filenames(inCanonicalJSON: canonicalJSON)
            )
        }
        guard !filenames.isEmpty else { return nil }

        let workingURL = try workingDocumentURL(for: snapshot.documentID)
        try validateReferencedAssets(in: snapshot, packageURL: workingURL)
        return workingURL
    }

    private func loadPortableDocument(from url: URL) throws -> FileSnapshot {
        guard let format = PortableDocumentFormat.format(for: url) else {
            throw FileStoreError.unsupportedDocumentFormat(url.pathExtension.lowercased())
        }

        let documentID = UUID().uuidString
        var importedAssets: [String: Data] = [:]
        let importedContent: StandardDocumentCodec.ImportedContent

        switch format {
        case .html:
            let html = try PackageFileSafety.readUTF8String(
                from: url,
                maximumBytes: Self.maximumImportedDocumentBytes
            )
            importedContent = try importExternalHTML(
                html,
                sourceURL: url,
                documentID: documentID,
                assets: &importedAssets
            )

        case .markdown:
            let markdown = try PackageFileSafety.readUTF8String(
                from: url,
                maximumBytes: Self.maximumImportedDocumentBytes
            )
            importedContent = try StandardDocumentCodec.importedMarkdown(
                markdown,
                baseURL: url.deletingLastPathComponent()
            ) { imageURL, _ in
                guard let image = try externalImage(
                    from: imageURL.absoluteString,
                    relativeTo: url.deletingLastPathComponent()
                ) else {
                    return nil
                }
                return try stageImportedImage(
                    image.data,
                    suggestedFilename: image.filename,
                    documentID: documentID,
                    assets: &importedAssets
                )
            }

        case .plainText:
            let text = try PackageFileSafety.readUTF8String(
                from: url,
                maximumBytes: Self.maximumImportedDocumentBytes
            )
            importedContent = StandardDocumentCodec.ImportedContent(
                html: StandardDocumentCodec.htmlFromPlainText(text),
                plainText: text
            )

        case .richTextDirectory:
            try validateExternalDocumentPackage(at: url)
            let attributedString = try StandardDocumentCodec.attributedString(
                from: url,
                format: format
            )
            importedContent = try StandardDocumentCodec.importedContent(
                from: attributedString
            ) { data, filename in
                guard isImageAttachment(data, filename: filename) else { return nil }
                return try stageImportedImage(
                    data,
                    suggestedFilename: filename,
                    documentID: documentID,
                    assets: &importedAssets
                )
            }

        case .word, .legacyWord, .openDocument, .richText:
            let data = try PackageFileSafety.readData(
                from: url,
                maximumBytes: Self.maximumImportedDocumentBytes
            )
            var containsEmbeddedImages = false
            if format == .word || format == .openDocument {
                try StandardDocumentCodec.validateArchive(
                    data,
                    format: format,
                    maximumEntryCount: Self.maximumPackageAssetCount,
                    maximumEntryBytes: Self.maximumDocumentContentBytes,
                    maximumExpandedBytes: Self.maximumPackageAssetBytes
                ) { entryPath in
                    if StandardDocumentCodec.archiveEntryContainsEmbeddedImage(
                        entryPath,
                        format: format
                    ) {
                        containsEmbeddedImages = true
                    }
                }
            } else {
                containsEmbeddedImages = StandardDocumentCodec.containsEmbeddedImagePayload(
                    data,
                    format: format
                )
            }
            guard !containsEmbeddedImages else {
                throw StandardDocumentCodecError.embeddedImagesUnsupportedForImport(
                    format.displayName
                )
            }
            let attributedString = try StandardDocumentCodec.attributedString(
                from: data,
                format: format
            )
            importedContent = try StandardDocumentCodec.importedContent(
                from: attributedString
            ) { data, filename in
                guard isImageAttachment(data, filename: filename) else { return nil }
                return try stageImportedImage(
                    data,
                    suggestedFilename: filename,
                    documentID: documentID,
                    assets: &importedAssets
                )
            }
        }

        guard importedContent.html.utf8.count <= Self.maximumDocumentContentBytes else {
            throw PackageFileSafetyError.fileTooLarge(
                filename: url.lastPathComponent,
                maximumBytes: Self.maximumDocumentContentBytes
            )
        }
        guard importedContent.plainText.utf8.count <= Self.maximumPlainTextPreviewBytes else {
            throw PackageFileSafetyError.fileTooLarge(
                filename: url.lastPathComponent,
                maximumBytes: Self.maximumPlainTextPreviewBytes
            )
        }
        try validatePackageAssetTotal(importedAssets)
        if !importedAssets.isEmpty {
            try stageImportedAssets(importedAssets, documentID: documentID)
        }

        let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
        let createdAt = attributes?[.creationDate] as? Date ?? Date()
        let modifiedAt = attributes?[.modificationDate] as? Date ?? createdAt
        return FileSnapshot(
            canonicalJSON: nil,
            htmlContent: importedContent.html,
            plainText: importedContent.plainText,
            documentID: documentID,
            createdAt: createdAt,
            modifiedAt: modifiedAt
        )
    }

    private func importExternalHTML(
        _ html: String,
        sourceURL: URL,
        documentID: String,
        assets: inout [String: Data]
    ) throws -> StandardDocumentCodec.ImportedContent {
        let expression = try NSRegularExpression(
            pattern: #"<img\b[^>]*>"#,
            options: [.caseInsensitive, .dotMatchesLineSeparators]
        )
        var rewritten = html
        let sourceDirectory = sourceURL.deletingLastPathComponent()
        let matches = expression.matches(
            in: html,
            range: NSRange(html.startIndex..., in: html)
        )

        for match in matches.reversed() {
            guard let range = Range(match.range, in: html) else { continue }
            let tag = String(html[range])
            let source = htmlAttribute(named: "src", in: tag)
            let altText = htmlAttribute(named: "alt", in: tag)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let replacement: String

            if let source,
               let image = try externalImage(from: source, relativeTo: sourceDirectory) {
                let stagedSource = try stageImportedImage(
                    image.data,
                    suggestedFilename: image.filename,
                    documentID: documentID,
                    assets: &assets
                )
                replacement = #"<img src="\#(escapeHTMLAttribute(stagedSource))" alt="\#(escapeHTMLAttribute(altText))">"#
            } else {
                replacement = altText.isEmpty ? "" : escapeHTMLText("[Image: \(altText)]")
            }
            rewritten.replaceSubrange(range, with: replacement)
        }

        let plainText = FileSnapshot(
            canonicalJSON: nil,
            htmlContent: rewritten
        ).plainText
        return StandardDocumentCodec.ImportedContent(
            html: rewritten,
            plainText: plainText
        )
    }

    private func htmlAttribute(named name: String, in tag: String) -> String? {
        let escapedName = NSRegularExpression.escapedPattern(for: name)
        let expression = try? NSRegularExpression(
            pattern: #"\b\#(escapedName)\s*=\s*(?:"([^"]*)"|'([^']*)'|([^\s>]+))"#,
            options: [.caseInsensitive]
        )
        guard let expression,
              let match = expression.firstMatch(
                in: tag,
                range: NSRange(tag.startIndex..., in: tag)
              )
        else {
            return nil
        }

        for index in 1..<match.numberOfRanges where match.range(at: index).location != NSNotFound {
            if let range = Range(match.range(at: index), in: tag) {
                return String(tag[range])
                    .replacingOccurrences(of: "&amp;", with: "&")
                    .replacingOccurrences(of: "&quot;", with: "\"")
                    .replacingOccurrences(of: "&#39;", with: "'")
            }
        }
        return nil
    }

    private func externalImage(
        from source: String,
        relativeTo baseURL: URL
    ) throws -> (data: Data, filename: String)? {
        let trimmed = source.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if trimmed.lowercased().hasPrefix("data:") {
            let payload = try dataFromDataURL(
                trimmed,
                maximumBytes: Self.maximumImportedImageBytes
            )
            return (payload.data, "image.\(payload.fileExtension)")
        }

        let candidateURL: URL
        if let parsed = URL(string: trimmed), parsed.scheme != nil {
            guard parsed.isFileURL else { return nil }
            candidateURL = parsed
        } else {
            let decoded = trimmed.removingPercentEncoding ?? trimmed
            candidateURL = baseURL.appendingPathComponent(decoded)
        }

        let resolvedBase = baseURL.resolvingSymlinksInPath().standardizedFileURL
        let resolvedCandidate = candidateURL.resolvingSymlinksInPath().standardizedFileURL
        let basePath = resolvedBase.path.hasSuffix("/")
            ? resolvedBase.path
            : resolvedBase.path + "/"
        guard resolvedCandidate.path.hasPrefix(basePath) else { return nil }

        let data = try imageAssetData(contentsOf: resolvedCandidate)
        return (data, resolvedCandidate.lastPathComponent)
    }

    private func isImageAttachment(_ data: Data, filename: String) -> Bool {
        if let type = UTType(filenameExtension: URL(fileURLWithPath: filename).pathExtension),
           type.conforms(to: .image) {
            return true
        }
        return CGImageSourceCreateWithData(data as CFData, nil) != nil
    }

    private func stageImportedImage(
        _ data: Data,
        suggestedFilename: String,
        documentID: String,
        assets: inout [String: Data]
    ) throws -> String {
        guard data.count <= Self.maximumImportedImageBytes else {
            throw FileStoreError.assetTooLarge(
                maximumMegabytes: Self.maximumImportedImageBytes / 1_024 / 1_024
            )
        }
        try validateDecodedImage(data)
        let fileExtension = decodedImageFileExtension(
            data,
            fallbackFilename: suggestedFilename
        )
        let filename = assetFilename(for: data, fileExtension: fileExtension)
        assets[filename] = data
        guard assets.count <= Self.maximumPackageAssetCount else {
            throw FileStoreError.invalidDocumentContent("too many imported images")
        }
        try validatePackageAssetTotal(assets)
        return DocumentAssetReference.urlString(for: filename)
    }

    private func decodedImageFileExtension(
        _ data: Data,
        fallbackFilename: String
    ) -> String {
        if let source = CGImageSourceCreateWithData(data as CFData, nil),
           let identifier = CGImageSourceGetType(source) as String?,
           let fileExtension = UTType(identifier)?.preferredFilenameExtension {
            return fileExtension.lowercased()
        }

        let fallback = URL(fileURLWithPath: fallbackFilename).pathExtension.lowercased()
        return fallback.isEmpty ? "png" : fallback
    }

    private func stageImportedAssets(
        _ assets: [String: Data],
        documentID: String
    ) throws {
        try validateAssetDictionary(assets)
        let workingURL = try workingDocumentURL(for: documentID)
        let assetsURL = workingURL.appendingPathComponent(
            DocumentAssetReference.assetsDirectoryName,
            isDirectory: true
        )
        do {
            try FileManager.default.createDirectory(
                at: assetsURL,
                withIntermediateDirectories: true
            )
            for (filename, data) in assets {
                guard let destination = DocumentAssetReference.containedFileURL(
                    named: filename,
                    in: assetsURL
                ) else {
                    throw FileStoreError.invalidPackagePath(filename)
                }
                try data.write(to: destination, options: .atomic)
            }
        } catch {
            try? FileManager.default.removeItem(at: workingURL)
            throw error
        }
    }

    private func validateExternalDocumentPackage(at url: URL) throws {
        let rootValues = try url.resourceValues(
            forKeys: [.isDirectoryKey, .isSymbolicLinkKey]
        )
        guard rootValues.isDirectory == true, rootValues.isSymbolicLink != true else {
            throw PackageFileSafetyError.notRegularFile(url.lastPathComponent)
        }

        let keys: [URLResourceKey] = [
            .isDirectoryKey,
            .isRegularFileKey,
            .isSymbolicLinkKey,
            .fileSizeKey,
        ]
        guard let enumerator = FileManager.default.enumerator(
            at: url,
            includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles]
        ) else {
            throw PackageFileSafetyError.notRegularFile(url.lastPathComponent)
        }

        var fileCount = 0
        var totalBytes = 0
        for case let entry as URL in enumerator {
            let values = try entry.resourceValues(forKeys: Set(keys))
            guard values.isSymbolicLink != true else {
                throw PackageFileSafetyError.notRegularFile(entry.lastPathComponent)
            }
            if values.isDirectory == true { continue }
            guard values.isRegularFile == true else {
                throw PackageFileSafetyError.notRegularFile(entry.lastPathComponent)
            }
            fileCount += 1
            guard fileCount <= Self.maximumPackageAssetCount else {
                throw FileStoreError.invalidDocumentContent("too many RTFD files")
            }
            let fileSize = values.fileSize ?? 0
            guard fileSize <= Self.maximumPackageAssetFileBytes else {
                throw PackageFileSafetyError.fileTooLarge(
                    filename: entry.lastPathComponent,
                    maximumBytes: Self.maximumPackageAssetFileBytes
                )
            }
            totalBytes += fileSize
            guard totalBytes <= Self.maximumPackageAssetBytes else {
                throw FileStoreError.packageAssetsTooLarge(
                    maximumMegabytes: Self.maximumPackageAssetBytes / 1_024 / 1_024
                )
            }
        }
    }

    private func portableImageSource(
        _ source: String,
        sourceDocumentURL: URL?
    ) throws -> String? {
        if source.hasPrefix("data:") {
            _ = try dataFromDataURL(
                source,
                maximumBytes: Self.maximumImportedImageBytes
            )
            return source
        }
        guard let filename = DocumentAssetReference.filename(from: source),
              let data = try existingAssetData(
                named: filename,
                from: sourceDocumentURL
              )
        else {
            return nil
        }
        return dataURL(for: data, filename: filename)
    }

    private func escapeHTMLText(_ value: String) -> String {
        value.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }

    private func escapeHTMLAttribute(_ value: String) -> String {
        escapeHTMLText(value)
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&#39;")
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
        sourceDocumentURL: URL?,
        referencedAssetFilenames: Set<String>
    ) throws -> StagedImageAsset {
        let payload = try dataFromDataURL(
            dataURL,
            maximumBytes: Self.maximumImportedImageBytes
        )
        return try stageImageAsset(
            data: payload.data,
            fileExtension: payload.fileExtension,
            documentID: documentID,
            sourceDocumentURL: sourceDocumentURL,
            referencedAssetFilenames: referencedAssetFilenames
        )
    }

    func stageImageAsset(
        from fileURL: URL,
        documentID: String,
        sourceDocumentURL: URL?,
        referencedAssetFilenames: Set<String>
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
            sourceDocumentURL: sourceDocumentURL,
            referencedAssetFilenames: referencedAssetFilenames
        )
    }

    private func stageImageAsset(
        data: Data,
        fileExtension: String,
        documentID: String,
        sourceDocumentURL: URL?,
        referencedAssetFilenames: Set<String>
    ) throws -> StagedImageAsset {
        let filename = assetFilename(for: data, fileExtension: fileExtension)
        let baseURL = try workingDocumentURL(for: documentID)
        let assetsURL = baseURL.appendingPathComponent(
            DocumentAssetReference.assetsDirectoryName,
            isDirectory: true
        )

        try FileManager.default.createDirectory(at: assetsURL, withIntermediateDirectories: true)
        try copyExistingAssetsIfNeeded(
            from: sourceDocumentURL,
            to: assetsURL,
            referencedAssetFilenames: referencedAssetFilenames
        )

        let destinationURL = assetsURL.appendingPathComponent(filename)
        try validateStagedAssets(
            at: assetsURL,
            referencedAssetFilenames: referencedAssetFilenames.union([filename]),
            newFilename: filename,
            newData: data
        )
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

    /// Returns the exact content-addressed assets needed to reconstruct a snapshot.
    /// Missing references are errors so version history can never silently save a
    /// snapshot that cannot later be restored.
    func versionAssets(
        for snapshot: FileSnapshot,
        sourceDocumentURL: URL?
    ) throws -> [String: Data] {
        let accessURLs = [sourceDocumentURL].compactMap { $0 }
        return try withSecurityScopedAccess(to: accessURLs) {
            try preparePackage(from: snapshot, sourceDocumentURL: sourceDocumentURL).assets
        }
    }

    /// Materializes a version's assets into the per-document working package.
    /// The candidate directory is completely validated before it atomically
    /// replaces the previous working copy.
    func stageVersionAssets(
        _ assets: [String: Data],
        documentID: String
    ) throws -> URL {
        try validateAssetDictionary(assets)

        let destination = try workingDocumentURL(for: documentID)
        let parent = destination.deletingLastPathComponent()
        let candidate = parent.appendingPathComponent(
            ".version-restore-\(UUID().uuidString).\(Self.documentPackageExtension)",
            isDirectory: true
        )
        let candidateAssets = candidate.appendingPathComponent(
            DocumentAssetReference.assetsDirectoryName,
            isDirectory: true
        )
        try FileManager.default.createDirectory(at: candidateAssets, withIntermediateDirectories: true)

        do {
            for (filename, data) in assets {
                guard let fileURL = DocumentAssetReference.containedFileURL(
                    named: filename,
                    in: candidateAssets
                ) else {
                    throw FileStoreError.invalidPackagePath(filename)
                }
                try data.write(to: fileURL, options: [.atomic])
            }

            if FileManager.default.fileExists(atPath: destination.path) {
                _ = try FileManager.default.replaceItemAt(destination, withItemAt: candidate)
            } else {
                try FileManager.default.moveItem(at: candidate, to: destination)
            }
            return destination
        } catch {
            try? FileManager.default.removeItem(at: candidate)
            throw error
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

        let manifestData = try PackageFileSafety.readData(
            from: manifestURL,
            maximumBytes: Self.maximumManifestBytes
        )
        let manifest = try decoder.decode(PackageManifest.self, from: manifestData)
        try PackageFileSafety.validateSchemaVersion(
            manifest.schemaVersion,
            supported: Self.currentSchemaVersion
        )
        guard !manifest.documentID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              manifest.documentID.count <= 128,
              manifest.wordCount >= 0,
              manifest.characterCount >= 0
        else {
            throw FileStoreError.invalidPackageManifest
        }

        let plainText: String
        if let plainTextFileName = manifest.plainTextFileName {
            guard let plainTextURL = DocumentAssetReference.containedFileURL(
                named: plainTextFileName,
                in: url
            ) else {
                throw FileStoreError.invalidPackagePath(plainTextFileName)
            }
            plainText = try PackageFileSafety.readUTF8String(
                from: plainTextURL,
                maximumBytes: Self.maximumPlainTextPreviewBytes,
                displayName: plainTextFileName
            )
        } else {
            plainText = ""
        }

        let notes: String
        if let notesFileName = manifest.notesFileName {
            guard let notesURL = DocumentAssetReference.containedFileURL(
                named: notesFileName,
                in: url
            ) else {
                throw FileStoreError.invalidPackagePath(notesFileName)
            }
            notes = try PackageFileSafety.readUTF8String(
                from: notesURL,
                maximumBytes: Self.maximumDocumentNotesBytes,
                displayName: notesFileName
            )
        } else {
            notes = ""
        }

        guard let contentURL = DocumentAssetReference.containedFileURL(
            named: manifest.contentFileName,
            in: url
        ) else {
            throw FileStoreError.invalidPackagePath(manifest.contentFileName)
        }
        let snapshot: FileSnapshot
        switch manifest.contentFormat {
        case .prosemirrorJSON:
            let canonicalJSON = try PackageFileSafety.readUTF8String(
                from: contentURL,
                maximumBytes: Self.maximumDocumentContentBytes,
                displayName: manifest.contentFileName
            )
            do {
                try CanonicalDocumentValidator.validate(canonicalJSON)
            } catch {
                throw FileStoreError.invalidDocumentContent(error.localizedDescription)
            }
            snapshot = FileSnapshot(
                canonicalJSON: canonicalJSON,
                htmlContent: "",
                plainText: plainText,
                notes: notes,
                wordCount: manifest.wordCount,
                characterCount: manifest.characterCount,
                documentID: manifest.documentID,
                schemaVersion: manifest.schemaVersion,
                createdAt: manifest.createdAt,
                modifiedAt: manifest.modifiedAt
            )

        case .html:
            let html = try PackageFileSafety.readUTF8String(
                from: contentURL,
                maximumBytes: Self.maximumDocumentContentBytes,
                displayName: manifest.contentFileName
            )
            snapshot = FileSnapshot(
                canonicalJSON: nil,
                htmlContent: html,
                plainText: plainText.isEmpty ? nil : plainText,
                notes: notes,
                wordCount: manifest.wordCount,
                characterCount: manifest.characterCount,
                documentID: manifest.documentID,
                schemaVersion: manifest.schemaVersion,
                createdAt: manifest.createdAt,
                modifiedAt: manifest.modifiedAt
            )
        }
        try validateReferencedAssets(in: snapshot, packageURL: url)
        return snapshot
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
        let notesFileName = snapshot.notes.isEmpty ? nil : "notes.txt"
        let contentData = Data(
            (hasCanonicalJSON ? snapshot.canonicalJSON! : snapshot.htmlContent).utf8
        )
        let plainTextData = Data(snapshot.plainText.utf8)
        let notesData = Data(snapshot.notes.utf8)
        guard contentData.count <= Self.maximumDocumentContentBytes else {
            throw PackageFileSafetyError.fileTooLarge(
                filename: contentFileName,
                maximumBytes: Self.maximumDocumentContentBytes
            )
        }
        guard plainTextData.count <= Self.maximumPlainTextPreviewBytes else {
            throw PackageFileSafetyError.fileTooLarge(
                filename: plainTextFileName,
                maximumBytes: Self.maximumPlainTextPreviewBytes
            )
        }
        guard notesData.count <= Self.maximumDocumentNotesBytes else {
            throw PackageFileSafetyError.fileTooLarge(
                filename: notesFileName ?? "notes.txt",
                maximumBytes: Self.maximumDocumentNotesBytes
            )
        }

        let manifest = PackageManifest(
            schemaVersion: snapshot.schemaVersion,
            documentID: snapshot.documentID,
            createdAt: snapshot.createdAt,
            modifiedAt: snapshot.modifiedAt,
            contentFormat: contentFormat,
            contentFileName: contentFileName,
            plainTextFileName: plainTextFileName,
            notesFileName: notesFileName,
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
            contents: contentData
        )
        fileWrappers[plainTextFileName] = regularFileWrapper(
            named: plainTextFileName,
            contents: plainTextData
        )
        if let notesFileName {
            fileWrappers[notesFileName] = regularFileWrapper(
                named: notesFileName,
                contents: notesData
            )
        }

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
        try validateWrittenPackage(
            at: url,
            contentFileName: contentFileName,
            notesFileName: notesFileName
        )
    }

    /// Verifies the package on disk is complete after a write, so a partial or
    /// corrupted write surfaces as a save error instead of silent data loss.
    private func validateWrittenPackage(
        at url: URL,
        contentFileName: String,
        notesFileName: String?
    ) throws {
        let manifestURL = url.appendingPathComponent("manifest.json")
        guard let manifestData = try? PackageFileSafety.readData(
            from: manifestURL,
            maximumBytes: Self.maximumManifestBytes
        ), !manifestData.isEmpty else {
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
        if let notesFileName {
            let notesURL = url.appendingPathComponent(notesFileName)
            guard FileManager.default.fileExists(atPath: notesURL.path) else {
                throw FileStoreError.incompletePackageWrite("\(notesFileName) missing")
            }
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
            guard assets[filename] != nil else {
                throw FileStoreError.missingReferencedAsset(filename)
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
        let filenames = DocumentAssetReference.filenames(in: html)
        guard filenames.count <= Self.maximumPackageAssetCount else {
            throw FileStoreError.invalidDocumentContent("too many referenced images")
        }
        for filename in filenames {
            guard let data = try existingAssetData(named: filename, from: sourceDocumentURL) else {
                throw FileStoreError.missingReferencedAsset(filename)
            }
            result[filename] = data
        }
        try validatePackageAssetTotal(result)
        return result
    }

    private func validatePackageAssetTotal(_ assets: [String: Data]) throws {
        guard assets.count <= Self.maximumPackageAssetCount else {
            throw FileStoreError.invalidDocumentContent("too many referenced images")
        }
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
        try ShakespeareStorage.prepare()
        let safeID = documentID.replacingOccurrences(
            of: "[^A-Za-z0-9_-]",
            with: "-",
            options: .regularExpression
        )
        let directory = ShakespeareStorage.workingDocumentsDirectoryURL
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        return directory.appendingPathComponent(
            "\(safeID.isEmpty ? UUID().uuidString : safeID).\(Self.documentPackageExtension)",
            isDirectory: true
        )
    }

    private func copyExistingAssetsIfNeeded(
        from sourceDocumentURL: URL?,
        to destination: URL,
        referencedAssetFilenames: Set<String>
    ) throws {
        guard let sourceDocumentURL,
              Self.isNativeDocumentURL(sourceDocumentURL),
              sourceDocumentURL.standardizedFileURL != destination.deletingLastPathComponent().standardizedFileURL,
              referencedAssetFilenames.count <= Self.maximumPackageAssetCount
        else { return }

        try withSecurityScopedAccess(to: [sourceDocumentURL]) {
            guard let source = DocumentAssetReference.containedFileURL(
                named: DocumentAssetReference.assetsDirectoryName,
                in: sourceDocumentURL
            ) else { return }
            guard FileManager.default.fileExists(atPath: source.path) else { return }
            var copiedBytes = 0
            for filename in referencedAssetFilenames.sorted() {
                guard let file = DocumentAssetReference.containedFileURL(
                    named: filename,
                    in: source
                ), FileManager.default.fileExists(atPath: file.path) else {
                    throw FileStoreError.missingReferencedAsset(filename)
                }
                let target = destination.appendingPathComponent(filename)
                guard !FileManager.default.fileExists(atPath: target.path) else { continue }
                let data = try PackageFileSafety.readData(
                    from: file,
                    maximumBytes: Self.maximumPackageAssetFileBytes,
                    displayName: filename
                )
                copiedBytes += data.count
                guard copiedBytes <= Self.maximumPackageAssetBytes else {
                    throw FileStoreError.packageAssetsTooLarge(
                        maximumMegabytes: Self.maximumPackageAssetBytes / (1_024 * 1_024)
                    )
                }
                try data.write(to: target, options: [.atomic])
            }
        }
    }

    private func validateStagedAssets(
        at assetsURL: URL,
        referencedAssetFilenames: Set<String>,
        newFilename: String,
        newData: Data
    ) throws {
        var totalBytes = 0
        for filename in referencedAssetFilenames.sorted() {
            guard let assetURL = DocumentAssetReference.containedFileURL(
                named: filename,
                in: assetsURL
            ) else {
                throw FileStoreError.invalidPackagePath(filename)
            }
            if filename == newFilename,
               !FileManager.default.fileExists(atPath: assetURL.path) {
                totalBytes += newData.count
            } else {
                guard FileManager.default.fileExists(atPath: assetURL.path) else {
                    throw FileStoreError.missingReferencedAsset(filename)
                }
                let assetData = try PackageFileSafety.readData(
                    from: assetURL,
                    maximumBytes: Self.maximumPackageAssetFileBytes,
                    displayName: filename
                )
                if filename == newFilename, assetData != newData {
                    throw FileStoreError.invalidDocumentContent(
                        "an existing image does not match its content-addressed filename"
                    )
                }
                totalBytes += assetData.count
            }
            guard totalBytes <= Self.maximumPackageAssetBytes else {
                throw FileStoreError.packageAssetsTooLarge(
                    maximumMegabytes: Self.maximumPackageAssetBytes / (1_024 * 1_024)
                )
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
        return try imageAssetData(
            contentsOf: assetURL,
            maximumBytes: Self.maximumPackageAssetFileBytes
        )
    }

    private func imageAssetData(
        contentsOf url: URL,
        maximumBytes: Int = DocumentFileStore.maximumImportedImageBytes
    ) throws -> Data {
        do {
            let data = try PackageFileSafety.readData(
                from: url,
                maximumBytes: maximumBytes,
                displayName: url.lastPathComponent
            )
            try validateDecodedImage(data)
            return data
        } catch PackageFileSafetyError.fileTooLarge {
            throw FileStoreError.assetTooLarge(
                maximumMegabytes: maximumBytes / 1_024 / 1_024
            )
        }
    }

    private func dataFromDataURL(
        _ source: String,
        maximumBytes: Int? = nil
    ) throws -> (data: Data, mimeType: String, fileExtension: String) {
        if let maximumBytes {
            let maximumEncodedBytes = ((maximumBytes + 2) / 3) * 4 + 512
            guard source.utf8.count <= maximumEncodedBytes else {
                throw FileStoreError.assetTooLarge(maximumMegabytes: maximumBytes / 1024 / 1024)
            }
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
        try validateDecodedImage(data)

        let fileExtension = UTType(mimeType: mimeType)?.preferredFilenameExtension ?? fileExtension(forMIMEType: mimeType)
        return (data, mimeType, fileExtension)
    }

    private func validateReferencedAssets(
        in snapshot: FileSnapshot,
        packageURL: URL
    ) throws {
        var filenames = DocumentAssetReference.filenames(in: snapshot.htmlContent)
        if let canonicalJSON = snapshot.canonicalJSON {
            filenames.formUnion(DocumentAssetReference.filenames(inCanonicalJSON: canonicalJSON))
        }
        guard filenames.count <= Self.maximumPackageAssetCount else {
            throw FileStoreError.invalidDocumentContent("too many referenced images")
        }
        guard let assetsDirectory = DocumentAssetReference.containedFileURL(
            named: DocumentAssetReference.assetsDirectoryName,
            in: packageURL
        ) else {
            throw FileStoreError.invalidPackagePath(DocumentAssetReference.assetsDirectoryName)
        }

        guard FileManager.default.fileExists(atPath: assetsDirectory.path) else {
            if filenames.isEmpty { return }
            throw FileStoreError.missingReferencedAsset(filenames.sorted().first ?? "assets")
        }
        let entries = try FileManager.default.contentsOfDirectory(
            at: assetsDirectory,
            includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey],
            options: [.skipsHiddenFiles]
        )
        guard entries.count <= Self.maximumPackageAssetCount else {
            throw FileStoreError.invalidDocumentContent("too many packaged images")
        }
        let packagedFilenames = Set(entries.map(\.lastPathComponent))
        guard packagedFilenames == filenames else {
            let unexpected = packagedFilenames.subtracting(filenames).sorted().first
            let missing = filenames.subtracting(packagedFilenames).sorted().first
            throw FileStoreError.invalidDocumentContent(
                unexpected.map { "unreferenced packaged image \($0)" }
                    ?? "missing packaged image \(missing ?? "unknown")"
            )
        }

        var assets: [String: Data] = [:]
        for filename in filenames {
            guard let assetURL = DocumentAssetReference.containedFileURL(
                named: filename,
                in: assetsDirectory
            ), FileManager.default.fileExists(atPath: assetURL.path) else {
                throw FileStoreError.missingReferencedAsset(filename)
            }
            assets[filename] = try imageAssetData(
                contentsOf: assetURL,
                maximumBytes: Self.maximumPackageAssetFileBytes
            )
        }
        try validateAssetDictionary(assets)
    }

    private func validateAssetDictionary(_ assets: [String: Data]) throws {
        try validatePackageAssetTotal(assets)
        for (filename, data) in assets {
            guard filename == assetFilename(
                for: data,
                fileExtension: URL(fileURLWithPath: filename).pathExtension.lowercased()
            ) else {
                throw FileStoreError.invalidDocumentContent(
                    "an image does not match its content-addressed filename"
                )
            }
            guard data.count <= Self.maximumPackageAssetFileBytes else {
                throw FileStoreError.assetTooLarge(
                    maximumMegabytes: Self.maximumPackageAssetFileBytes / 1_024 / 1_024
                )
            }
            try validateDecodedImage(data)
        }
    }

    private func validateDecodedImage(_ data: Data) throws {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int,
              width > 0,
              height > 0
        else {
            throw FileStoreError.invalidDataURL
        }
        guard CGImageSourceGetCount(source) <= Self.maximumImageFrameCount else {
            throw FileStoreError.invalidDocumentContent("an animated image has too many frames")
        }
        guard width <= Self.maximumImageDimension,
              height <= Self.maximumImageDimension,
              width.multipliedReportingOverflow(by: height).overflow == false,
              width * height <= Self.maximumImagePixelCount
        else {
            throw FileStoreError.imageDimensionsTooLarge(
                maximumPixels: Self.maximumImagePixelCount,
                maximumDimension: Self.maximumImageDimension
            )
        }
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
