import Foundation

enum DocumentAssetReference {
    static let scheme = "shakespeare-document"
    static let host = "asset"
    static let assetsDirectoryName = "assets"

    static func urlString(for filename: String) -> String {
        let encoded = filename.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? filename
        return "\(scheme)://\(host)/\(encoded)"
    }

    static func filename(from source: String) -> String? {
        guard let url = URL(string: source),
              url.scheme == scheme,
              url.host == host
        else {
            return nil
        }

        let path = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard !path.isEmpty else { return nil }
        return path.removingPercentEncoding ?? path
    }
}
