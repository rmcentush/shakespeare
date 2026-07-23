import AppKit
@preconcurrency import Foundation

enum StandardDocumentCodecError: LocalizedError {
    case invalidDocument(String)
    case unsupportedFormat(String)
    case embeddedImagesUnsupported(String)

    var errorDescription: String? {
        switch self {
        case .invalidDocument(let format):
            return "The \(format) document could not be read."
        case .unsupportedFormat(let format):
            return "\(format) is not supported for this operation."
        case .embeddedImagesUnsupported(let format):
            return "\(format) export cannot safely preserve embedded images. Export as HTML or RTFD instead."
        }
    }
}

enum StandardDocumentCodec {
    struct ImportedContent {
        let html: String
        let plainText: String
    }

    typealias ImportedImageResolver = (_ data: Data, _ suggestedFilename: String) throws -> String?
    typealias MarkdownImageResolver = (_ url: URL, _ altText: String) throws -> String?
    typealias ExportedImageResolver = (_ source: String) throws -> String?

    static func attributedString(
        from data: Data,
        format: PortableDocumentFormat
    ) throws -> NSAttributedString {
        guard let documentType = attributedDocumentType(for: format) else {
            throw StandardDocumentCodecError.unsupportedFormat(format.displayName)
        }

        do {
            return try NSAttributedString(
                data: data,
                options: [.documentType: documentType],
                documentAttributes: nil
            )
        } catch {
            throw StandardDocumentCodecError.invalidDocument(format.displayName)
        }
    }

    static func validateArchive(
        _ data: Data,
        format: PortableDocumentFormat,
        maximumEntryCount: Int,
        maximumEntryBytes: Int,
        maximumExpandedBytes: Int
    ) throws {
        guard maximumEntryCount > 0,
              maximumEntryBytes > 0,
              maximumExpandedBytes > 0,
              data.count >= 22
        else {
            throw StandardDocumentCodecError.invalidDocument(format.displayName)
        }

        let minimumEOCDOffset = max(0, data.count - 65_557)
        var eocdOffset = data.count - 22
        while eocdOffset >= minimumEOCDOffset {
            if littleEndianUInt32(in: data, at: eocdOffset) == 0x0605_4b50 {
                break
            }
            eocdOffset -= 1
        }
        guard eocdOffset >= minimumEOCDOffset,
              littleEndianUInt32(in: data, at: eocdOffset) == 0x0605_4b50,
              littleEndianUInt16(in: data, at: eocdOffset + 4) == 0,
              littleEndianUInt16(in: data, at: eocdOffset + 6) == 0
        else {
            throw StandardDocumentCodecError.invalidDocument(format.displayName)
        }

        let entriesOnDisk = littleEndianUInt16(in: data, at: eocdOffset + 8)
        let totalEntries = littleEndianUInt16(in: data, at: eocdOffset + 10)
        let centralDirectorySize = littleEndianUInt32(in: data, at: eocdOffset + 12)
        let centralDirectoryOffset = littleEndianUInt32(in: data, at: eocdOffset + 16)
        let commentLength = littleEndianUInt16(in: data, at: eocdOffset + 20)

        guard entriesOnDisk == totalEntries,
              totalEntries != UInt16.max,
              centralDirectorySize != UInt32.max,
              centralDirectoryOffset != UInt32.max,
              Int(totalEntries) <= maximumEntryCount,
              eocdOffset + 22 + Int(commentLength) <= data.count
        else {
            throw StandardDocumentCodecError.invalidDocument(format.displayName)
        }

        let centralStart = Int(centralDirectoryOffset)
        let (centralEnd, centralOverflow) = centralStart.addingReportingOverflow(
            Int(centralDirectorySize)
        )
        guard !centralOverflow,
              centralStart >= 0,
              centralEnd <= eocdOffset,
              centralEnd <= data.count
        else {
            throw StandardDocumentCodecError.invalidDocument(format.displayName)
        }

        var cursor = centralStart
        var expandedBytes = 0
        for _ in 0..<Int(totalEntries) {
            guard cursor + 46 <= centralEnd,
                  littleEndianUInt32(in: data, at: cursor) == 0x0201_4b50
            else {
                throw StandardDocumentCodecError.invalidDocument(format.displayName)
            }

            let flags = littleEndianUInt16(in: data, at: cursor + 8)
            let compressedSize = littleEndianUInt32(in: data, at: cursor + 20)
            let expandedSize = littleEndianUInt32(in: data, at: cursor + 24)
            let filenameLength = littleEndianUInt16(in: data, at: cursor + 28)
            let extraLength = littleEndianUInt16(in: data, at: cursor + 30)
            let entryCommentLength = littleEndianUInt16(in: data, at: cursor + 32)
            let externalAttributes = littleEndianUInt32(in: data, at: cursor + 38)
            let localHeaderOffset = littleEndianUInt32(in: data, at: cursor + 42)
            let entryLength = 46
                + Int(filenameLength)
                + Int(extraLength)
                + Int(entryCommentLength)

            guard flags & 0x1 == 0,
                  compressedSize != UInt32.max,
                  expandedSize != UInt32.max,
                  Int(compressedSize) <= data.count,
                  Int(expandedSize) <= maximumEntryBytes,
                  Int(localHeaderOffset) < centralStart,
                  cursor + entryLength <= centralEnd
            else {
                throw StandardDocumentCodecError.invalidDocument(format.displayName)
            }

            let unixFileType = (externalAttributes >> 16) & 0xf000
            guard unixFileType != 0xa000 else {
                throw StandardDocumentCodecError.invalidDocument(format.displayName)
            }

            let filenameStart = cursor + 46
            let filenameEnd = filenameStart + Int(filenameLength)
            let filenameData = data[filenameStart..<filenameEnd]
            guard let filename = String(data: filenameData, encoding: .utf8),
                  isSafeArchivePath(filename)
            else {
                throw StandardDocumentCodecError.invalidDocument(format.displayName)
            }

            let (newExpandedBytes, expandedOverflow) = expandedBytes.addingReportingOverflow(
                Int(expandedSize)
            )
            guard !expandedOverflow, newExpandedBytes <= maximumExpandedBytes else {
                throw StandardDocumentCodecError.invalidDocument(format.displayName)
            }
            expandedBytes = newExpandedBytes
            cursor += entryLength
        }

        guard cursor == centralEnd else {
            throw StandardDocumentCodecError.invalidDocument(format.displayName)
        }
    }

    static func attributedString(
        from url: URL,
        format: PortableDocumentFormat
    ) throws -> NSAttributedString {
        guard let documentType = attributedDocumentType(for: format) else {
            throw StandardDocumentCodecError.unsupportedFormat(format.displayName)
        }

        do {
            return try NSAttributedString(
                url: url,
                options: [.documentType: documentType],
                documentAttributes: nil
            )
        } catch {
            throw StandardDocumentCodecError.invalidDocument(format.displayName)
        }
    }

    static func importedContent(
        from attributedString: NSAttributedString,
        imageResolver: ImportedImageResolver
    ) throws -> ImportedContent {
        let mutable = NSMutableAttributedString(attributedString: attributedString)
        var replacements: [(range: NSRange, value: NSAttributedString)] = []
        var imageSources: [(filename: String, source: String)] = []
        var imageIndex = 0
        var attachmentError: Error?

        mutable.enumerateAttribute(
            .attachment,
            in: NSRange(location: 0, length: mutable.length),
            options: []
        ) { value, range, _ in
            guard attachmentError == nil else { return }
            guard let attachment = value as? NSTextAttachment else { return }
            let originalFilename = attachment.fileWrapper?.preferredFilename
                ?? attachment.fileWrapper?.filename
                ?? "attachment"
            guard let data = attachment.fileWrapper?.regularFileContents else {
                replacements.append((
                    range,
                    NSAttributedString(string: attachmentLabel(for: originalFilename))
                ))
                return
            }

            let source: String
            do {
                guard let resolvedSource = try imageResolver(data, originalFilename) else {
                    replacements.append((
                        range,
                        NSAttributedString(string: attachmentLabel(for: originalFilename))
                    ))
                    return
                }
                source = resolvedSource
            } catch {
                attachmentError = error
                return
            }

            imageIndex += 1
            let fileExtension = URL(fileURLWithPath: originalFilename).pathExtension
            let filename = fileExtension.isEmpty
                ? "imported-image-\(imageIndex)"
                : "imported-image-\(imageIndex).\(fileExtension)"
            let wrapper = FileWrapper(regularFileWithContents: data)
            wrapper.preferredFilename = filename
            let replacementAttachment = NSTextAttachment(fileWrapper: wrapper)
            replacements.append((
                range,
                NSAttributedString(attachment: replacementAttachment)
            ))
            imageSources.append((filename, source))
        }

        if let attachmentError {
            throw attachmentError
        }
        for replacement in replacements.sorted(by: { $0.range.location > $1.range.location }) {
            mutable.replaceCharacters(in: replacement.range, with: replacement.value)
        }

        let htmlData: Data
        do {
            htmlData = try mutable.data(
                from: NSRange(location: 0, length: mutable.length),
                documentAttributes: [.documentType: NSAttributedString.DocumentType.html]
            )
        } catch {
            throw StandardDocumentCodecError.invalidDocument("formatted")
        }

        var html = inlineCocoaStyles(in: String(decoding: htmlData, as: UTF8.self))
        for imageSource in imageSources {
            let encodedFilename = imageSource.filename.addingPercentEncoding(
                withAllowedCharacters: .urlPathAllowed
            ) ?? imageSource.filename
            html = html.replacingOccurrences(
                of: "file:///\(encodedFilename)",
                with: imageSource.source
            )
            html = html.replacingOccurrences(
                of: "file:///\(imageSource.filename)",
                with: imageSource.source
            )
        }

        let plainText = mutable.string.replacingOccurrences(of: "\u{fffc}", with: "")
        return ImportedContent(html: html, plainText: plainText)
    }

    static func importedMarkdown(
        _ markdown: String,
        baseURL: URL,
        imageResolver: MarkdownImageResolver
    ) throws -> ImportedContent {
        let attributed: AttributedString
        do {
            attributed = try AttributedString(
                markdown: markdown,
                options: .init(interpretedSyntax: .full),
                baseURL: baseURL
            )
        } catch {
            throw StandardDocumentCodecError.invalidDocument("Markdown")
        }

        var html = ""
        var openComponents: [(identity: Int, closeTag: String)] = []

        for run in attributed.runs {
            let presentationIntent = run[
                AttributeScopes.FoundationAttributes.PresentationIntentAttribute.self
            ]
            let components = Array((presentationIntent?.components ?? []).reversed())
            var commonCount = 0
            while commonCount < openComponents.count,
                  commonCount < components.count,
                  openComponents[commonCount].identity == components[commonCount].identity {
                commonCount += 1
            }

            for component in openComponents.dropFirst(commonCount).reversed() {
                html += component.closeTag
            }
            openComponents.removeLast(openComponents.count - commonCount)

            for (index, component) in components.dropFirst(commonCount).enumerated() {
                let componentIndex = commonCount + index
                let tags = htmlTags(
                    for: component.kind,
                    path: components,
                    componentIndex: componentIndex
                )
                html += tags.open
                openComponents.append((component.identity, tags.close))
            }

            guard !components.contains(where: {
                if case .thematicBreak = $0.kind { return true }
                return false
            }) else {
                continue
            }

            let text = String(attributed[run.range].characters)
            if components.contains(where: {
                if case .codeBlock = $0.kind { return true }
                return false
            }) {
                html += text.standardHTMLEscaped
                continue
            }

            if let imageURL = run[
                AttributeScopes.FoundationAttributes.ImageURLAttribute.self
            ] {
                let altText = text.trimmingCharacters(in: .whitespacesAndNewlines)
                if let source = try imageResolver(imageURL.absoluteURL, altText) {
                    html += #"<img src="\#(source.standardHTMLAttributeEscaped)" alt="\#(altText.standardHTMLAttributeEscaped)">"#
                } else if !altText.isEmpty {
                    html += "[Image: \(altText)]".standardHTMLEscaped
                }
                continue
            }

            var inlineHTML: String
            let intent = run[
                AttributeScopes.FoundationAttributes.InlinePresentationIntentAttribute.self
            ] ?? []
            if intent.contains(.lineBreak) {
                inlineHTML = "<br>"
            } else if intent.contains(.softBreak) {
                inlineHTML = "\n"
            } else {
                inlineHTML = text.standardHTMLEscaped
            }

            if intent.contains(.code) {
                inlineHTML = "<code>\(inlineHTML)</code>"
            }
            if intent.contains(.stronglyEmphasized) {
                inlineHTML = "<strong>\(inlineHTML)</strong>"
            }
            if intent.contains(.emphasized) {
                inlineHTML = "<em>\(inlineHTML)</em>"
            }
            if intent.contains(.strikethrough) {
                inlineHTML = "<s>\(inlineHTML)</s>"
            }
            if let link = run[
                AttributeScopes.FoundationAttributes.LinkAttribute.self
            ], isSafeLink(link) {
                inlineHTML = #"<a href="\#(link.absoluteString.standardHTMLAttributeEscaped)">\#(inlineHTML)</a>"#
            }
            html += inlineHTML
        }

        for component in openComponents.reversed() {
            html += component.closeTag
        }

        if html.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            html = "<p></p>"
        }
        let renderedPlainText = try? attributedString(fromHTML: html).string
        let plainText = renderedPlainText?
            .replacingOccurrences(of: "\u{fffc}", with: "")
            ?? String(attributed.characters)
        return ImportedContent(html: html, plainText: plainText)
    }

    static func htmlFromPlainText(_ text: String) -> String {
        guard !text.isEmpty else { return "<p></p>" }
        return text.components(separatedBy: "\n\n").map { paragraph in
            "<p>\(paragraph.standardHTMLEscaped.replacingOccurrences(of: "\n", with: "<br>"))</p>"
        }.joined(separator: "\n")
    }

    static func attributedString(fromHTML html: String) throws -> NSAttributedString {
        guard let data = html.data(using: .utf8) else {
            throw StandardDocumentCodecError.invalidDocument("HTML")
        }
        do {
            return try NSAttributedString(
                data: data,
                options: [
                    .documentType: NSAttributedString.DocumentType.html,
                    .characterEncoding: String.Encoding.utf8.rawValue,
                ],
                documentAttributes: nil
            )
        } catch {
            throw StandardDocumentCodecError.invalidDocument("HTML")
        }
    }

    static func containsAttachments(_ attributedString: NSAttributedString) -> Bool {
        var found = false
        attributedString.enumerateAttribute(
            .attachment,
            in: NSRange(location: 0, length: attributedString.length),
            options: []
        ) { value, _, stop in
            if value is NSTextAttachment {
                found = true
                stop.pointee = true
            }
        }
        return found
    }

    static func encodedData(
        from attributedString: NSAttributedString,
        format: PortableDocumentFormat
    ) throws -> Data {
        guard let documentType = attributedDocumentType(for: format),
              format != .richTextDirectory
        else {
            throw StandardDocumentCodecError.unsupportedFormat(format.displayName)
        }
        do {
            return try attributedString.data(
                from: NSRange(location: 0, length: attributedString.length),
                documentAttributes: [.documentType: documentType]
            )
        } catch {
            throw StandardDocumentCodecError.invalidDocument(format.displayName)
        }
    }

    static func rtfdWrapper(from attributedString: NSAttributedString) throws -> FileWrapper {
        do {
            return try attributedString.fileWrapper(
                from: NSRange(location: 0, length: attributedString.length),
                documentAttributes: [.documentType: NSAttributedString.DocumentType.rtfd]
            )
        } catch {
            throw StandardDocumentCodecError.invalidDocument("RTFD")
        }
    }

    static func markdown(
        fromCanonicalJSON json: String,
        imageResolver: ExportedImageResolver
    ) throws -> String {
        guard let data = json.data(using: .utf8),
              let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              root["type"] as? String == "doc"
        else {
            throw StandardDocumentCodecError.invalidDocument("Shakespeare")
        }

        var footnotes: [(id: String, note: String)] = []
        let body = try renderBlocks(
            root["content"] as? [[String: Any]] ?? [],
            imageResolver: imageResolver,
            footnotes: &footnotes
        )
        guard !footnotes.isEmpty else {
            return body.trimmingCharacters(in: .whitespacesAndNewlines) + "\n"
        }

        let definitions = footnotes.map { footnote in
            let lines = footnote.note.components(separatedBy: .newlines)
            let first = lines.first ?? ""
            let rest = lines.dropFirst().map { "    \($0)" }
            return (["[^\(footnote.id)]: \(first)"] + rest).joined(separator: "\n")
        }.joined(separator: "\n\n")
        return body.trimmingCharacters(in: .whitespacesAndNewlines)
            + "\n\n"
            + definitions
            + "\n"
    }

    private static func attributedDocumentType(
        for format: PortableDocumentFormat
    ) -> NSAttributedString.DocumentType? {
        switch format {
        case .word:
            return .officeOpenXML
        case .legacyWord:
            return .docFormat
        case .openDocument:
            return .openDocument
        case .richText:
            return .rtf
        case .richTextDirectory:
            return .rtfd
        case .plainText:
            return .plain
        case .html:
            return .html
        case .markdown:
            return nil
        }
    }

    private static func attachmentLabel(for filename: String) -> String {
        let trimmed = filename.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "[Attachment]" : "[Attachment: \(trimmed)]"
    }

    private static func littleEndianUInt16(in data: Data, at offset: Int) -> UInt16 {
        guard offset >= 0, offset + 2 <= data.count else { return .max }
        return UInt16(data[offset])
            | (UInt16(data[offset + 1]) << 8)
    }

    private static func littleEndianUInt32(in data: Data, at offset: Int) -> UInt32 {
        guard offset >= 0, offset + 4 <= data.count else { return .max }
        return UInt32(data[offset])
            | (UInt32(data[offset + 1]) << 8)
            | (UInt32(data[offset + 2]) << 16)
            | (UInt32(data[offset + 3]) << 24)
    }

    private static func isSafeArchivePath(_ path: String) -> Bool {
        guard !path.isEmpty,
              !path.hasPrefix("/"),
              !path.contains("\\"),
              !path.contains("\0")
        else {
            return false
        }
        return path.split(separator: "/", omittingEmptySubsequences: false).allSatisfy {
            $0 != ".." && $0 != "."
        }
    }

    private static func inlineCocoaStyles(in html: String) -> String {
        let ruleExpression = try? NSRegularExpression(
            pattern: #"([A-Za-z][A-Za-z0-9_-]*)\.([A-Za-z][A-Za-z0-9_-]*)\s*\{([^}]*)\}"#,
            options: [.dotMatchesLineSeparators]
        )
        guard let ruleExpression else { return html }

        var stylesBySelector: [String: String] = [:]
        for match in ruleExpression.matches(
            in: html,
            range: NSRange(html.startIndex..., in: html)
        ) {
            guard let tagRange = Range(match.range(at: 1), in: html),
                  let classRange = Range(match.range(at: 2), in: html),
                  let styleRange = Range(match.range(at: 3), in: html)
            else {
                continue
            }
            let style = String(html[styleRange])
                .components(separatedBy: ";")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty && $0.range(of: #"url\s*\("#, options: [.regularExpression, .caseInsensitive]) == nil }
                .joined(separator: "; ")
            guard !style.isEmpty else { continue }
            let selector = "\(html[tagRange].lowercased()).\(html[classRange])"
            stylesBySelector[selector] = style
        }
        guard !stylesBySelector.isEmpty else { return html }

        let tagExpression = try? NSRegularExpression(
            pattern: #"<([A-Za-z][A-Za-z0-9_-]*)([^>]*\bclass\s*=\s*["']([^"']+)["'][^>]*)>"#,
            options: [.caseInsensitive, .dotMatchesLineSeparators]
        )
        guard let tagExpression else { return html }

        var result = html
        let matches = tagExpression.matches(
            in: html,
            range: NSRange(html.startIndex..., in: html)
        )
        for match in matches.reversed() {
            guard let matchRange = Range(match.range, in: html),
                  let tagRange = Range(match.range(at: 1), in: html),
                  let attributesRange = Range(match.range(at: 2), in: html),
                  let classesRange = Range(match.range(at: 3), in: html)
            else {
                continue
            }
            let tag = html[tagRange].lowercased()
            let classes = html[classesRange].split(whereSeparator: \.isWhitespace)
            let styles = classes.compactMap { stylesBySelector["\(tag).\($0)"] }
            guard !styles.isEmpty else { continue }

            let attributes = String(html[attributesRange])
            let inlineStyle = styles.joined(separator: "; ")
                .standardHTMLAttributeEscaped
            let replacement = "<\(html[tagRange])\(attributes) style=\"\(inlineStyle)\">"
            result.replaceSubrange(matchRange, with: replacement)
        }
        return result
    }

    private static func isSafeLink(_ url: URL) -> Bool {
        if url.absoluteString.hasPrefix("#") { return true }
        guard let scheme = url.scheme?.lowercased() else { return false }
        return scheme == "http" || scheme == "https" || scheme == "mailto"
    }

    private static func htmlTags(
        for kind: PresentationIntent.Kind,
        path: [PresentationIntent.IntentType],
        componentIndex: Int
    ) -> (open: String, close: String) {
        switch kind {
        case .paragraph:
            return ("<p>", "</p>")
        case .header(let level):
            let safeLevel = min(max(level, 1), 3)
            return ("<h\(safeLevel)>", "</h\(safeLevel)>")
        case .orderedList:
            return ("<ol>", "</ol>")
        case .unorderedList:
            return ("<ul>", "</ul>")
        case .listItem:
            return ("<li>", "</li>")
        case .codeBlock(let languageHint):
            let languageClass = languageHint.flatMap { hint -> String? in
                let safe = hint.filter { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" }
                return safe.isEmpty ? nil : #" class="language-\#(safe.standardHTMLAttributeEscaped)""#
            } ?? ""
            return ("<pre><code\(languageClass)>", "</code></pre>")
        case .blockQuote:
            return ("<blockquote>", "</blockquote>")
        case .thematicBreak:
            return ("<hr>", "")
        case .table:
            return ("<table>", "</table>")
        case .tableHeaderRow:
            return ("<thead><tr>", "</tr></thead>")
        case .tableRow:
            return ("<tr>", "</tr>")
        case .tableCell:
            let isHeader = path.prefix(componentIndex).contains {
                if case .tableHeaderRow = $0.kind { return true }
                return false
            }
            return isHeader ? ("<th>", "</th>") : ("<td>", "</td>")
        @unknown default:
            return ("", "")
        }
    }

    private static func renderBlocks(
        _ nodes: [[String: Any]],
        imageResolver: ExportedImageResolver,
        footnotes: inout [(id: String, note: String)]
    ) throws -> String {
        try nodes.compactMap { node -> String? in
            guard let type = node["type"] as? String else { return nil }
            let content = node["content"] as? [[String: Any]] ?? []
            let attrs = node["attrs"] as? [String: Any] ?? [:]

            switch type {
            case "paragraph":
                return try renderInline(content, imageResolver: imageResolver, footnotes: &footnotes)
            case "heading":
                let level = min(max(attrs["level"] as? Int ?? 1, 1), 3)
                let text = try renderInline(content, imageResolver: imageResolver, footnotes: &footnotes)
                return "\(String(repeating: "#", count: level)) \(text)"
            case "blockquote":
                let rendered = try renderBlocks(
                    content,
                    imageResolver: imageResolver,
                    footnotes: &footnotes
                )
                return rendered.components(separatedBy: .newlines)
                    .map { $0.isEmpty ? ">" : "> \($0)" }
                    .joined(separator: "\n")
            case "bulletList":
                return try renderList(
                    content,
                    start: nil,
                    imageResolver: imageResolver,
                    footnotes: &footnotes
                )
            case "orderedList":
                return try renderList(
                    content,
                    start: max(1, attrs["start"] as? Int ?? 1),
                    imageResolver: imageResolver,
                    footnotes: &footnotes
                )
            case "codeBlock":
                let text = content.compactMap { $0["text"] as? String }.joined()
                let language = (attrs["language"] as? String)?
                    .filter { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" } ?? ""
                let fence = codeFence(for: text)
                return "\(fence)\(language)\n\(text)\n\(fence)"
            case "horizontalRule":
                return "---"
            default:
                return nil
            }
        }.joined(separator: "\n\n")
    }

    private static func renderList(
        _ items: [[String: Any]],
        start: Int?,
        imageResolver: ExportedImageResolver,
        footnotes: inout [(id: String, note: String)]
    ) throws -> String {
        var ordinal = start ?? 1
        return try items.compactMap { item -> String? in
            guard item["type"] as? String == "listItem" else { return nil }
            let rendered = try renderBlocks(
                item["content"] as? [[String: Any]] ?? [],
                imageResolver: imageResolver,
                footnotes: &footnotes
            )
            let marker = start == nil ? "- " : "\(ordinal). "
            ordinal += 1
            let continuation = String(repeating: " ", count: marker.count)
            let lines = rendered.components(separatedBy: .newlines)
            guard let first = lines.first else { return marker }
            return ([marker + first] + lines.dropFirst().map { continuation + $0 })
                .joined(separator: "\n")
        }.joined(separator: "\n")
    }

    private static func renderInline(
        _ nodes: [[String: Any]],
        imageResolver: ExportedImageResolver,
        footnotes: inout [(id: String, note: String)]
    ) throws -> String {
        try nodes.compactMap { node -> String? in
            guard let type = node["type"] as? String else { return nil }
            let attrs = node["attrs"] as? [String: Any] ?? [:]

            switch type {
            case "text":
                return applyMarkdownMarks(
                    node["text"] as? String ?? "",
                    marks: node["marks"] as? [[String: Any]] ?? []
                )
            case "hardBreak":
                return "  \n"
            case "image":
                guard let source = attrs["src"] as? String,
                      let portableSource = try imageResolver(source)
                else {
                    let alt = attrs["alt"] as? String ?? ""
                    return alt.isEmpty ? nil : "[Image: \(markdownEscaped(alt))]"
                }
                let alt = (attrs["alt"] as? String ?? "")
                    .replacingOccurrences(of: "]", with: "\\]")
                let destination = portableSource
                    .replacingOccurrences(of: "(", with: "%28")
                    .replacingOccurrences(of: ")", with: "%29")
                return "![\(alt)](\(destination))"
            case "footnote":
                let baseID = (attrs["id"] as? String)?
                    .filter { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" }
                let id = baseID.flatMap { $0.isEmpty ? nil : $0 }
                    ?? "note-\(footnotes.count + 1)"
                let note = attrs["note"] as? String ?? ""
                if !footnotes.contains(where: { $0.id == id }) {
                    footnotes.append((id, note))
                }
                return "[^\(id)]"
            default:
                return nil
            }
        }.joined()
    }

    private static func applyMarkdownMarks(
        _ rawText: String,
        marks: [[String: Any]]
    ) -> String {
        let markTypes = Set(marks.compactMap { $0["type"] as? String })
        var result = markdownEscaped(rawText)
        if markTypes.contains("code") {
            let delimiter = inlineCodeDelimiter(for: rawText)
            result = "\(delimiter)\(rawText)\(delimiter)"
        }
        if markTypes.contains("bold") {
            result = "**\(result)**"
        }
        if markTypes.contains("italic") {
            result = "*\(result)*"
        }
        if markTypes.contains("strike") {
            result = "~~\(result)~~"
        }
        if markTypes.contains("underline") {
            result = "<u>\(result)</u>"
        }
        if let link = marks.first(where: { $0["type"] as? String == "link" }),
           let attrs = link["attrs"] as? [String: Any],
           let href = attrs["href"] as? String {
            result = "[\(result)](\(href.replacingOccurrences(of: ")", with: "%29")))"
        }
        return result
    }

    private static func markdownEscaped(_ value: String) -> String {
        let reserved = CharacterSet(charactersIn: #"\\`*{}[]<>#+-.!_|"#)
        return value.unicodeScalars.reduce(into: "") { result, scalar in
            if reserved.contains(scalar) {
                result.append("\\")
            }
            result.unicodeScalars.append(scalar)
        }
    }

    private static func codeFence(for value: String) -> String {
        var longest = 0
        var current = 0
        for character in value {
            if character == "`" {
                current += 1
                longest = max(longest, current)
            } else {
                current = 0
            }
        }
        return String(repeating: "`", count: max(3, longest + 1))
    }

    private static func inlineCodeDelimiter(for value: String) -> String {
        var longest = 0
        var current = 0
        for character in value {
            if character == "`" {
                current += 1
                longest = max(longest, current)
            } else {
                current = 0
            }
        }
        return String(repeating: "`", count: longest + 1)
    }
}

private extension String {
    var standardHTMLEscaped: String {
        replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }

    var standardHTMLAttributeEscaped: String {
        standardHTMLEscaped
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&#39;")
    }
}
