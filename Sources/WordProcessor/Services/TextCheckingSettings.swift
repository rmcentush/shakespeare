import AppKit
import Observation
import ObjectiveC.runtime
import WebKit

@MainActor
@Observable
final class TextCheckingSettings {
    static let shared = TextCheckingSettings()

    static let dialects: [(value: String, label: String)] = [
        ("american", "American English"),
        ("british", "British English"),
        ("australian", "Australian English"),
        ("canadian", "Canadian English"),
        ("indian", "Indian English"),
    ]

    private enum Keys {
        static let continuousSpellChecking = "proofreading.spellingEnabled"
        static let grammarChecking = "proofreading.grammarEnabled"
        static let dialect = "proofreading.dialect"
        static let automaticSpellingCorrection = "textChecking.automaticSpellingCorrectionEnabled"
        static let automaticTextReplacement = "textChecking.automaticTextReplacementEnabled"
    }

    private let baselineAutomaticSpellingCorrectionEnabled: Bool
    private let baselineAutomaticTextReplacementEnabled: Bool
    private var didApplyAutomaticCorrectionToCurrentWebView = false

    weak var webView: WKWebView?

    var continuousSpellCheckingEnabled: Bool {
        didSet {
            guard continuousSpellCheckingEnabled != oldValue else { return }
            persist(continuousSpellCheckingEnabled, key: Keys.continuousSpellChecking)
            applyProofreadingOptions()
        }
    }

    var grammarCheckingEnabled: Bool {
        didSet {
            guard grammarCheckingEnabled != oldValue else { return }
            persist(grammarCheckingEnabled, key: Keys.grammarChecking)
            applyProofreadingOptions()
            NotificationCenter.default.post(name: .grammarCheckingSettingsChanged, object: self)
        }
    }

    var dialect: String {
        didSet {
            guard dialect != oldValue else { return }
            UserDefaults.standard.set(dialect, forKey: Keys.dialect)
            applyProofreadingOptions()
            NotificationCenter.default.post(name: .grammarCheckingSettingsChanged, object: self)
        }
    }

    var automaticSpellingCorrectionEnabled: Bool {
        didSet {
            guard automaticSpellingCorrectionEnabled != oldValue else { return }
            persist(automaticSpellingCorrectionEnabled, key: Keys.automaticSpellingCorrection)
            applyAutomaticSpellingCorrection(previousValue: oldValue)
        }
    }

    var automaticTextReplacementEnabled: Bool {
        didSet {
            guard automaticTextReplacementEnabled != oldValue else { return }
            persist(automaticTextReplacementEnabled, key: Keys.automaticTextReplacement)
            applyAutomaticTextReplacement()
        }
    }

    private init() {
        let textView = NSTextView()
        baselineAutomaticSpellingCorrectionEnabled = textView.isAutomaticSpellingCorrectionEnabled
        baselineAutomaticTextReplacementEnabled = textView.isAutomaticTextReplacementEnabled

        continuousSpellCheckingEnabled = Self.loadBool(key: Keys.continuousSpellChecking, fallback: true)
        grammarCheckingEnabled = Self.loadBool(key: Keys.grammarChecking, fallback: true)
        let storedDialect = UserDefaults.standard.string(forKey: Keys.dialect)
        dialect = storedDialect.flatMap { stored in
            Self.dialects.contains(where: { $0.value == stored }) ? stored : nil
        } ?? Self.defaultDialect()
        automaticSpellingCorrectionEnabled = Self.loadBool(
            key: Keys.automaticSpellingCorrection,
            fallback: textView.isAutomaticSpellingCorrectionEnabled
        )
        automaticTextReplacementEnabled = Self.loadBool(
            key: Keys.automaticTextReplacement,
            fallback: textView.isAutomaticTextReplacementEnabled
        )
    }

    func bind(webView: WKWebView) {
        self.webView = webView
        didApplyAutomaticCorrectionToCurrentWebView = false
        applyAutomaticTextReplacement()
    }

    func editorDidBecomeReady() {
        // Harper and Haiku supply the visible spelling/grammar marks. Disabling WebKit's
        // checker avoids duplicate, conflicting underlines and context menus.
        setEditorBoolOption(callback: "setSpellcheckEnabled", value: false)
        setEditorBoolOption(callback: "setAutocorrectEnabled", value: automaticSpellingCorrectionEnabled)
        applyProofreadingOptions()

        if !didApplyAutomaticCorrectionToCurrentWebView,
           automaticSpellingCorrectionEnabled != baselineAutomaticSpellingCorrectionEnabled {
            didApplyAutomaticCorrectionToCurrentWebView = performAction(
                #selector(NSTextView.toggleAutomaticSpellingCorrection(_:))
            )
        }
        applyAutomaticTextReplacement()
    }

    func resetDictionary() {
        webView?.evaluateJavaScript("window.editorAPI?.resetProofreadingDictionary()")
        NotificationCenter.default.post(name: .grammarCheckingSettingsChanged, object: self)
    }

    private func applyProofreadingOptions() {
        guard let webView else { return }
        let spelling = continuousSpellCheckingEnabled ? "true" : "false"
        let safeDialect = Self.dialects.contains(where: { $0.value == dialect }) ? dialect : "american"
        webView.evaluateJavaScript(
            "window.editorAPI?.setProofreadingOptions(\(spelling), false, '\(safeDialect)')"
        )
        if !grammarCheckingEnabled {
            webView.evaluateJavaScript("window.editorAPI?.setAIGrammarIssues('[]')")
        }
    }

    private func applyAutomaticSpellingCorrection(previousValue: Bool) {
        setEditorBoolOption(callback: "setAutocorrectEnabled", value: automaticSpellingCorrectionEnabled)
        guard previousValue != automaticSpellingCorrectionEnabled else { return }
        if performAction(#selector(NSTextView.toggleAutomaticSpellingCorrection(_:))) {
            didApplyAutomaticCorrectionToCurrentWebView = true
        }
    }

    private func applyAutomaticTextReplacement() {
        guard let webView else { return }
        if !setBoolSelector(
            "setAutomaticTextReplacementEnabled:",
            on: webView,
            value: automaticTextReplacementEnabled
        ), automaticTextReplacementEnabled != baselineAutomaticTextReplacementEnabled {
            performAction(#selector(NSTextView.toggleAutomaticTextReplacement(_:)))
        }
    }

    private func setEditorBoolOption(callback: String, value: Bool) {
        webView?.evaluateJavaScript("window.editorAPI?.\(callback)(\(value ? "true" : "false"))")
    }

    @discardableResult
    private func performAction(_ selector: Selector) -> Bool {
        if NSApp.sendAction(selector, to: nil, from: nil) {
            return true
        }
        guard let webView else { return false }
        return NSApp.sendAction(selector, to: webView, from: nil)
    }

    private func persist(_ value: Bool, key: String) {
        UserDefaults.standard.set(value, forKey: key)
    }

    private static func loadBool(key: String, fallback: Bool) -> Bool {
        UserDefaults.standard.object(forKey: key) as? Bool ?? fallback
    }

    private static func defaultDialect() -> String {
        switch Locale.current.region?.identifier.uppercased() {
        case "GB": return "british"
        case "AU", "NZ": return "australian"
        case "CA": return "canadian"
        case "IN": return "indian"
        default: return "american"
        }
    }

    private func setBoolSelector(_ selectorName: String, on target: AnyObject, value: Bool) -> Bool {
        let selector = Selector(selectorName)
        guard let method = class_getInstanceMethod(type(of: target), selector) else { return false }

        typealias Setter = @convention(c) (AnyObject, Selector, Bool) -> Void
        let implementation = method_getImplementation(method)
        unsafeBitCast(implementation, to: Setter.self)(target, selector, value)
        return true
    }
}
