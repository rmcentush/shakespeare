import SwiftUI

@Observable
@MainActor
final class FontManager {
    static let shared = FontManager()

    var currentFont = "Lyon Text"
    var currentSize = 18.0
    var currentLineHeight = 1.7
    private(set) var cachedFontFaceCSS: String = ""

    private init() {
        let defaults = UserDefaults.standard
        if let font = defaults.string(forKey: "editorFont") {
            currentFont = normalizeFontName(font)
        }
        if defaults.double(forKey: "editorFontSize") > 0 {
            currentSize = defaults.double(forKey: "editorFontSize")
        }
        if defaults.double(forKey: "editorLineHeight") > 0 {
            currentLineHeight = defaults.double(forKey: "editorLineHeight")
        }
        if currentFont == "EBGaramond" {
            defaults.set(currentFont, forKey: "editorFont")
        }
    }

    func save() {
        let defaults = UserDefaults.standard
        currentFont = normalizeFontName(currentFont)
        defaults.set(currentFont, forKey: "editorFont")
        defaults.set(currentSize, forKey: "editorFontSize")
        defaults.set(currentLineHeight, forKey: "editorLineHeight")
    }

    func generateCSS() -> String {
        let fontName = normalizeFontName(currentFont)
        return """
        .editor-content {
            font-family: '\(fontName)', Georgia, serif;
            font-size: \(Int(currentSize))px;
            line-height: \(currentLineHeight);
        }
        """
    }

    func fullThemeCSS() -> String {
        cachedFontFaceCSS + "\n" + generateCSS()
    }

    func themedCSS(for appearance: String) -> String {
        switch appearance {
        case "light":
            return fullThemeCSS() + """

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
            return fullThemeCSS() + """

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
            return fullThemeCSS()
        }
    }

    /// Generate @font-face CSS for all bundled font families
    /// Uses relative URLs (relative to editor.html in the same Resources directory)
    func fontFaceCSS(fontsDirectoryURL: URL?) -> String {
        guard let fontsDir = fontsDirectoryURL,
              let files = try? FileManager.default.contentsOfDirectory(at: fontsDir, includingPropertiesForKeys: nil)
        else { return "" }

        var css = ""
        for file in files {
            let ext = file.pathExtension.lowercased()
            guard ext == "otf" || ext == "ttf" || ext == "woff" || ext == "woff2" else { continue }

            let filename = file.deletingPathExtension().lastPathComponent
            let nameLower = filename.lowercased()
            let format = ext == "otf" ? "opentype" : ext == "ttf" ? "truetype" : ext

            // Determine which font family this file belongs to
            let family: String
            if nameLower.contains("lyontext") || nameLower.contains("lyon text") {
                family = "Lyon Text"
            } else if nameLower.contains("ebgaramond") {
                family = "EBGaramond"
            } else if nameLower.contains("sourceserif") {
                family = "Source Serif 4"
            } else if nameLower.contains("scala") {
                family = "Scala"
            } else if nameLower.contains("charter") {
                family = "Charter"
            } else {
                // Fallback: use filename as family name
                family = filename
            }

            // Determine weight and style from filename
            let isBlack = nameLower.contains("black")
            let isBold = nameLower.contains("bold")
            let isItalic = nameLower.contains("italic") || nameLower.hasSuffix("-it") || nameLower.hasSuffix("it")

            let weight = isBlack ? "900" : isBold ? "700" : "400"
            let style = isItalic ? "italic" : "normal"

            // Use absolute file URL for reliable loading in WKWebView inline styles
            let absoluteURL = file.absoluteString

            css += """
            @font-face {
                font-family: '\(family)';
                src: url('\(absoluteURL)') format('\(format)');
                font-weight: \(weight);
                font-style: \(style);
            }

            """
        }
        cachedFontFaceCSS = css
        return css
    }

    private func normalizeFontName(_ fontName: String) -> String {
        if fontName == "Garamond" {
            return "EBGaramond"
        }
        return fontName
    }
}
