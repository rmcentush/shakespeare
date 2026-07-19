import SwiftUI

@Observable
@MainActor
final class FontManager {
    static let shared = FontManager()
    static let baseFont = "Georgia"
    static let baseSize = 18.0
    static let baseLineHeight = 1.7

    static let availableFonts = [
        "Georgia",
        "Palatino",
        "Baskerville",
        "Times New Roman",
        "Helvetica Neue",
        "-apple-system",
    ]

    var currentFont = baseFont
    var currentSize = baseSize
    var currentLineHeight = baseLineHeight

    private init() {
        let defaults = UserDefaults.standard
        if let font = defaults.string(forKey: "editorFont") {
            let normalizedFont = normalizeFontName(font)
            currentFont = normalizedFont
            if normalizedFont != font {
                defaults.set(normalizedFont, forKey: "editorFont")
            }
        }
        if defaults.double(forKey: "editorFontSize") > 0 {
            currentSize = defaults.double(forKey: "editorFontSize")
        }
        if defaults.double(forKey: "editorLineHeight") > 0 {
            currentLineHeight = defaults.double(forKey: "editorLineHeight")
        }
    }

    func save() {
        let defaults = UserDefaults.standard
        currentFont = normalizeFontName(currentFont)
        defaults.set(currentFont, forKey: "editorFont")
        defaults.set(currentSize, forKey: "editorFontSize")
        defaults.set(currentLineHeight, forKey: "editorLineHeight")
    }

    func themedCSS(for appearance: String) -> String {
        switch appearance {
        case "light":
            return """

            html, body { background: #ffffff !important; color: #1a1a1a !important; }
            .editor-content { color: #1a1a1a !important; }
            .editor-footnotes { border-top-color: #e0e0e0 !important; }
            .editor-footnotes-title { color: #6a6a6a !important; }
            .editor-footnotes-list li { color: #3f3f3f !important; }
            .footnote-reference {
                color: #007aff !important;
                background: rgba(0, 122, 255, 0.08) !important;
            }
            """
        case "dark":
            return """

            html, body { background: #1e1e1e !important; color: #e0e0e0 !important; }
            .editor-content { color: #e0e0e0 !important; }
            .editor-content blockquote { border-left-color: #555 !important; color: #aaa !important; }
            .editor-content code, .editor-content pre { background: #2d2d2d !important; }
            .editor-content hr { border-top-color: #444 !important; }
            .editor-footnotes { border-top-color: #444 !important; }
            .editor-footnotes-title { color: #9d9d9d !important; }
            .editor-footnotes-list li { color: #d0d0d0 !important; }
            .footnote-reference {
                color: #5ac8fa !important;
                background: rgba(90, 200, 250, 0.16) !important;
            }
            """
        default:
            return ""
        }
    }

    private func normalizeFontName(_ fontName: String) -> String {
        Self.availableFonts.contains(fontName) ? fontName : Self.baseFont
    }
}
