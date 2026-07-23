import UniformTypeIdentifiers

extension UTType {
    static var shakespeareDocument: UTType {
        UTType(exportedAs: "com.shakespeare.document", conformingTo: .package)
    }
}

enum PortableDocumentFormat: String, CaseIterable, Sendable {
    case word
    case legacyWord
    case openDocument
    case richText
    case richTextDirectory
    case markdown
    case plainText
    case html

    static let importFormats: [Self] = [
        .word,
        .legacyWord,
        .openDocument,
        .richText,
        .richTextDirectory,
        .markdown,
        .plainText,
        .html,
    ]

    static let exportFormats: [Self] = [
        .word,
        .openDocument,
        .richText,
        .richTextDirectory,
        .markdown,
        .plainText,
        .html,
        .legacyWord,
    ]

    var filenameExtension: String {
        switch self {
        case .word:
            return "docx"
        case .legacyWord:
            return "doc"
        case .openDocument:
            return "odt"
        case .richText:
            return "rtf"
        case .richTextDirectory:
            return "rtfd"
        case .markdown:
            return "md"
        case .plainText:
            return "txt"
        case .html:
            return "html"
        }
    }

    var displayName: String {
        switch self {
        case .word:
            return "Microsoft Word"
        case .legacyWord:
            return "Microsoft Word 97–2004"
        case .openDocument:
            return "OpenDocument Text"
        case .richText:
            return "Rich Text"
        case .richTextDirectory:
            return "Rich Text with Attachments"
        case .markdown:
            return "Markdown"
        case .plainText:
            return "Plain Text"
        case .html:
            return "HTML"
        }
    }

    var exportMenuTitle: String {
        "\(displayName) (.\(filenameExtension))…"
    }

    var contentType: UTType {
        switch self {
        case .richText:
            return .rtf
        case .richTextDirectory:
            return .rtfd
        case .plainText:
            return .plainText
        case .html:
            return .html
        default:
            return UTType(filenameExtension: filenameExtension) ?? .data
        }
    }

    static func format(for url: URL) -> Self? {
        let fileExtension = url.pathExtension.lowercased()
        return importFormats.first { $0.matches(fileExtension: fileExtension) }
    }

    private func matches(fileExtension: String) -> Bool {
        if self == .markdown {
            return fileExtension == "md" || fileExtension == "markdown"
        }
        if self == .html {
            return fileExtension == "html" || fileExtension == "htm"
        }
        return fileExtension == filenameExtension
    }
}
