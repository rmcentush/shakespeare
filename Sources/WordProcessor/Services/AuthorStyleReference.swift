import Foundation

enum AuthorStyleReference {
    static let content: String = {
        guard let resourceURL = Bundle.module.url(forResource: "david_oks_style_guide", withExtension: "md"),
              let content = try? String(contentsOf: resourceURL, encoding: .utf8)
        else { return "" }
        return content
    }()
}
