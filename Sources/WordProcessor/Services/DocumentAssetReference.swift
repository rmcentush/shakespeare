import Foundation

enum DocumentAssetReference {
    static let scheme = "shakespeare-document"
    static let host = "asset"
    static let assetsDirectoryName = "assets"

    private static let filenameURLCharacters: CharacterSet = {
        var characters = CharacterSet.alphanumerics
        characters.insert(charactersIn: "-._~")
        return characters
    }()

    private static let assetURLPattern = try! NSRegularExpression(
        pattern: #"shakespeare-document://asset/[A-Za-z0-9%._~-]+"#
    )

    static func urlString(for filename: String) -> String {
        let encoded = filename.addingPercentEncoding(withAllowedCharacters: filenameURLCharacters) ?? filename
        return "\(scheme)://\(host)/\(encoded)"
    }

    static func filename(from source: String) -> String? {
        guard let url = URL(string: source),
              url.scheme == scheme,
              url.host == host
        else {
            return nil
        }

        guard let encodedPath = URLComponents(
            url: url,
            resolvingAgainstBaseURL: false
        )?.percentEncodedPath else { return nil }
        guard encodedPath.hasPrefix("/") else { return nil }
        let encodedFilename = String(encodedPath.dropFirst())
        guard !encodedFilename.isEmpty, !encodedFilename.contains("/") else { return nil }

        let decoded = encodedFilename.removingPercentEncoding ?? encodedFilename
        guard isSafeFilename(decoded) else { return nil }
        return decoded
    }

    static func filenames(in text: String) -> Set<String> {
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return Set(assetURLPattern.matches(in: text, range: range).compactMap { match in
            guard let matchRange = Range(match.range, in: text) else { return nil }
            return filename(from: String(text[matchRange]))
        })
    }

    static func isSafeFilename(_ filename: String) -> Bool {
        guard !filename.isEmpty,
              filename != ".",
              filename != "..",
              !filename.contains("/"),
              !filename.contains("\\"),
              !filename.contains("\0")
        else {
            return false
        }

        return (filename as NSString).lastPathComponent == filename
    }

    /// Returns a direct child while rejecting traversal and symlinks that escape
    /// the supplied directory.
    static func containedFileURL(named filename: String, in directory: URL) -> URL? {
        guard isSafeFilename(filename) else { return nil }

        let resolvedDirectory = directory.resolvingSymlinksInPath().standardizedFileURL
        let candidate = directory
            .appendingPathComponent(filename, isDirectory: false)
            .resolvingSymlinksInPath()
            .standardizedFileURL

        guard candidate.deletingLastPathComponent() == resolvedDirectory else { return nil }
        return candidate
    }
}
