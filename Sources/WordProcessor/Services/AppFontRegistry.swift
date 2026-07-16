import CoreText
import Foundation

enum AppFontRegistry {
    static func registerBundledFonts(bundle: Bundle = .shakespeareResources) {
        for fontName in [
            "AnthropicSerifWebVariable-TextRegular",
            "AnthropicSerifWebVariable-TextRegularItalic",
        ] {
            guard let url = bundledFontURL(named: fontName, bundle: bundle) else { continue }
            registerFont(at: url)
        }
    }

    private static func bundledFontURL(named name: String, bundle: Bundle) -> URL? {
        let fileManager = FileManager.default
        let filename = "\(name).ttf"
        let candidates = [
            bundle.url(forResource: name, withExtension: "ttf", subdirectory: "Fonts"),
            bundle.bundleURL.appendingPathComponent("Fonts", isDirectory: true).appendingPathComponent(filename),
            bundle.resourceURL?.appendingPathComponent("Fonts", isDirectory: true).appendingPathComponent(filename),
        ].compactMap { $0 }

        return candidates.first { fileManager.fileExists(atPath: $0.path) }
    }

    private static func registerFont(at url: URL) {
        var error: Unmanaged<CFError>?
        _ = CTFontManagerRegisterFontsForURL(url as CFURL, .process, &error)
        error?.release()
    }
}
