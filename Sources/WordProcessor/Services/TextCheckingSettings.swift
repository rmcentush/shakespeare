import AppKit
import Observation
import ObjectiveC.runtime
import WebKit

@MainActor
@Observable
final class TextCheckingSettings {
    static let shared = TextCheckingSettings()

    private enum Keys {
        static let continuousSpellChecking = "textChecking.continuousSpellCheckingEnabled"
        static let grammarChecking = "textChecking.grammarCheckingEnabled"
        static let automaticSpellingCorrection = "textChecking.automaticSpellingCorrectionEnabled"
        static let automaticTextReplacement = "textChecking.automaticTextReplacementEnabled"
    }

    private let baselineContinuousSpellCheckingEnabled: Bool
    private let baselineGrammarCheckingEnabled: Bool
    private let baselineAutomaticSpellingCorrectionEnabled: Bool
    private let baselineAutomaticTextReplacementEnabled: Bool
    private var didApplyDeferredNativeTogglesToCurrentWebView = false

    weak var webView: WKWebView?

    var continuousSpellCheckingEnabled: Bool {
        didSet {
            guard continuousSpellCheckingEnabled != oldValue else { return }
            persist(continuousSpellCheckingEnabled, key: Keys.continuousSpellChecking)
            applyContinuousSpellChecking(previousValue: oldValue)
        }
    }

    var grammarCheckingEnabled: Bool {
        didSet {
            guard grammarCheckingEnabled != oldValue else { return }
            persist(grammarCheckingEnabled, key: Keys.grammarChecking)
            applyGrammarChecking()
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
        let baseline = Self.baselineDefaults()
        baselineContinuousSpellCheckingEnabled = baseline.continuousSpellCheckingEnabled
        baselineGrammarCheckingEnabled = baseline.grammarCheckingEnabled
        baselineAutomaticSpellingCorrectionEnabled = baseline.automaticSpellingCorrectionEnabled
        baselineAutomaticTextReplacementEnabled = baseline.automaticTextReplacementEnabled

        continuousSpellCheckingEnabled = Self.loadBool(
            key: Keys.continuousSpellChecking,
            fallback: baseline.continuousSpellCheckingEnabled
        )
        grammarCheckingEnabled = Self.loadBool(
            key: Keys.grammarChecking,
            fallback: baseline.grammarCheckingEnabled
        )
        automaticSpellingCorrectionEnabled = Self.loadBool(
            key: Keys.automaticSpellingCorrection,
            fallback: baseline.automaticSpellingCorrectionEnabled
        )
        automaticTextReplacementEnabled = Self.loadBool(
            key: Keys.automaticTextReplacement,
            fallback: baseline.automaticTextReplacementEnabled
        )
    }

    func bind(webView: WKWebView) {
        self.webView = webView
        didApplyDeferredNativeTogglesToCurrentWebView = false
        applyGrammarChecking()
        applyAutomaticTextReplacement()
    }

    func editorDidBecomeReady() {
        applyEditorAttributes()

        if !didApplyDeferredNativeTogglesToCurrentWebView {
            let needsContinuousToggle = continuousSpellCheckingEnabled != baselineContinuousSpellCheckingEnabled
            let needsAutomaticCorrectionToggle = automaticSpellingCorrectionEnabled != baselineAutomaticSpellingCorrectionEnabled

            if !needsContinuousToggle && !needsAutomaticCorrectionToggle {
                didApplyDeferredNativeTogglesToCurrentWebView = true
            }

            var appliedDeferredToggles = false

            if needsContinuousToggle {
                appliedDeferredToggles = performAction(#selector(NSTextView.toggleContinuousSpellChecking(_:))) || appliedDeferredToggles
            }

            if needsAutomaticCorrectionToggle {
                appliedDeferredToggles = performAction(#selector(NSTextView.toggleAutomaticSpellingCorrection(_:))) || appliedDeferredToggles
            }

            didApplyDeferredNativeTogglesToCurrentWebView = didApplyDeferredNativeTogglesToCurrentWebView || appliedDeferredToggles
        }

        applyGrammarChecking()
        applyAutomaticTextReplacement()
    }

    func checkSpellingNow() {
        performAction(#selector(NSText.checkSpelling(_:)))
    }

    func showGuessPanel() {
        performAction(#selector(NSText.showGuessPanel(_:)))
    }

    private func applyContinuousSpellChecking(previousValue: Bool) {
        applyEditorAttributes()
        guard previousValue != continuousSpellCheckingEnabled else { return }
        if performAction(#selector(NSTextView.toggleContinuousSpellChecking(_:))) {
            didApplyDeferredNativeTogglesToCurrentWebView = true
        }
    }

    private func applyAutomaticSpellingCorrection(previousValue: Bool) {
        applyEditorAttributes()
        guard previousValue != automaticSpellingCorrectionEnabled else { return }
        if performAction(#selector(NSTextView.toggleAutomaticSpellingCorrection(_:))) {
            didApplyDeferredNativeTogglesToCurrentWebView = true
        }
    }

    private func applyGrammarChecking() {
        guard let webView else { return }
        if !setBoolSelector(
            "setGrammarCheckingEnabled:",
            on: webView,
            value: grammarCheckingEnabled
        ), grammarCheckingEnabled != baselineGrammarCheckingEnabled {
            performAction(#selector(NSTextView.toggleGrammarChecking(_:)))
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

    private func applyEditorAttributes() {
        setEditorBoolOption(
            callback: "setSpellcheckEnabled",
            value: continuousSpellCheckingEnabled
        )
        setEditorBoolOption(
            callback: "setAutocorrectEnabled",
            value: automaticSpellingCorrectionEnabled
        )
    }

    private func setEditorBoolOption(callback: String, value: Bool) {
        guard let webView else { return }
        webView.evaluateJavaScript("window.editorAPI?.\(callback)(\(value ? "true" : "false"))")
    }

    @discardableResult
    private func performAction(_ selector: Selector) -> Bool {
        if NSApp.sendAction(selector, to: nil, from: nil) {
            return true
        }

        guard let webView else {
            return false
        }

        return NSApp.sendAction(selector, to: webView, from: nil)
    }

    private func persist(_ value: Bool, key: String) {
        UserDefaults.standard.set(value, forKey: key)
    }

    private static func loadBool(key: String, fallback: Bool) -> Bool {
        if let stored = UserDefaults.standard.object(forKey: key) as? Bool {
            return stored
        }
        return fallback
    }

    private static func baselineDefaults() -> (
        continuousSpellCheckingEnabled: Bool,
        grammarCheckingEnabled: Bool,
        automaticSpellingCorrectionEnabled: Bool,
        automaticTextReplacementEnabled: Bool
    ) {
        let textView = NSTextView()
        return (
            textView.isContinuousSpellCheckingEnabled,
            textView.isGrammarCheckingEnabled,
            textView.isAutomaticSpellingCorrectionEnabled,
            textView.isAutomaticTextReplacementEnabled
        )
    }

    private func setBoolSelector(_ selectorName: String, on target: AnyObject, value: Bool) -> Bool {
        let selector = Selector((selectorName))
        guard let method = class_getInstanceMethod(type(of: target), selector) else {
            return false
        }

        typealias Setter = @convention(c) (AnyObject, Selector, Bool) -> Void
        let implementation = method_getImplementation(method)
        let function = unsafeBitCast(implementation, to: Setter.self)
        function(target, selector, value)
        return true
    }
}
