import AppKit
import Observation
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
        static let proofreadingUserState = "proofreading.userState.v1"
    }

    private let baselineAutomaticSpellingCorrectionEnabled: Bool
    private let baselineAutomaticTextReplacementEnabled: Bool
    private var didApplyAutomaticCorrectionToCurrentWebView = false
    private var didApplyAutomaticTextReplacementToCurrentWebView = false

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
            applyAutomaticTextReplacement(previousValue: oldValue)
        }
    }

    private init() {
        let textView = NSTextView()
        baselineAutomaticSpellingCorrectionEnabled = textView.isAutomaticSpellingCorrectionEnabled
        baselineAutomaticTextReplacementEnabled = textView.isAutomaticTextReplacementEnabled

        continuousSpellCheckingEnabled = Self.loadBool(key: Keys.continuousSpellChecking, fallback: true)
        // Remote grammar uses the writer's paid OpenRouter account. Keep it
        // opt-in for new installs; local Harper spelling remains on by default.
        grammarCheckingEnabled = Self.loadBool(key: Keys.grammarChecking, fallback: false)
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
        didApplyAutomaticTextReplacementToCurrentWebView = false
    }

    func editorDidBecomeReady() {
        // The local and remote checkers supply the visible spelling/grammar marks. Disabling WebKit's
        // checker avoids duplicate, conflicting underlines and context menus.
        setEditorBoolOption(callback: "setSpellcheckEnabled", value: false)
        setEditorBoolOption(callback: "setAutocorrectEnabled", value: automaticSpellingCorrectionEnabled)
        restoreProofreadingUserState()
        applyProofreadingOptions()

        if !didApplyAutomaticCorrectionToCurrentWebView,
           automaticSpellingCorrectionEnabled != baselineAutomaticSpellingCorrectionEnabled {
            didApplyAutomaticCorrectionToCurrentWebView = performAction(
                #selector(NSTextView.toggleAutomaticSpellingCorrection(_:))
            )
        }
        if !didApplyAutomaticTextReplacementToCurrentWebView,
           automaticTextReplacementEnabled != baselineAutomaticTextReplacementEnabled {
            didApplyAutomaticTextReplacementToCurrentWebView = performAction(
                #selector(NSTextView.toggleAutomaticTextReplacement(_:))
            )
        }
    }

    func resetDictionary() {
        UserDefaults.standard.removeObject(forKey: Keys.proofreadingUserState)
        webView?.evaluateJavaScript("window.editorAPI?.resetProofreadingDictionary()")
        NotificationCenter.default.post(name: .grammarCheckingSettingsChanged, object: self)
    }

    func persistProofreadingUserState(_ json: String) {
        guard Self.validProofreadingUserState(json) else { return }
        UserDefaults.standard.set(json, forKey: Keys.proofreadingUserState)
    }

    private func restoreProofreadingUserState() {
        guard let json = UserDefaults.standard.string(forKey: Keys.proofreadingUserState),
              Self.validProofreadingUserState(json),
              let data = try? JSONSerialization.data(withJSONObject: json, options: .fragmentsAllowed),
              let quotedJSON = String(data: data, encoding: .utf8)
        else { return }
        webView?.evaluateJavaScript("window.editorAPI?.setProofreadingUserState(\(quotedJSON))")
    }

    private static func validProofreadingUserState(_ json: String) -> Bool {
        guard json.utf8.count <= 256 * 1_024,
              let data = json.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return false }
        let keys = ["customWords", "ignoredLints", "ignoredAIGrammar"]
        return keys.allSatisfy { key in
            guard let value = object[key] as? String, value.utf8.count <= 128 * 1_024 else { return false }
            return (try? JSONSerialization.jsonObject(with: Data(value.utf8))) != nil
        }
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

    private func applyAutomaticTextReplacement(previousValue: Bool) {
        guard previousValue != automaticTextReplacementEnabled else { return }
        if performAction(#selector(NSTextView.toggleAutomaticTextReplacement(_:))) {
            didApplyAutomaticTextReplacementToCurrentWebView = true
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
}
