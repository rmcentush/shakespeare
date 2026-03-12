import Foundation

actor DocumentFileStore {
    static let shared = DocumentFileStore()

    struct FileSnapshot: Sendable {
        let htmlContent: String
        let wordCount: Int
        let characterCount: Int

        init(htmlContent: String, wordCount: Int? = nil, characterCount: Int? = nil) {
            self.htmlContent = htmlContent

            if let wordCount, let characterCount {
                self.wordCount = wordCount
                self.characterCount = characterCount
            } else {
                let metrics = Self.metrics(forHTML: htmlContent)
                self.wordCount = metrics.wordCount
                self.characterCount = metrics.characterCount
            }
        }

        private static func metrics(forHTML html: String) -> (wordCount: Int, characterCount: Int) {
            let text = plainText(fromHTML: html)
            return (
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

    func load(from url: URL) throws -> FileSnapshot {
        try withSecurityScopedAccess(to: url) {
            let html = try String(contentsOf: url, encoding: .utf8)
            return FileSnapshot(htmlContent: html)
        }
    }

    func save(_ snapshot: FileSnapshot, to url: URL) throws {
        try withSecurityScopedAccess(to: url) {
            try snapshot.htmlContent.write(to: url, atomically: true, encoding: .utf8)
        }
    }

    private func withSecurityScopedAccess<T>(to url: URL, operation: () throws -> T) throws -> T {
        let didAccess = url.startAccessingSecurityScopedResource()
        defer {
            if didAccess {
                url.stopAccessingSecurityScopedResource()
            }
        }
        return try operation()
    }
}
