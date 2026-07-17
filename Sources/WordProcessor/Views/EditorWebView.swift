import SwiftUI
import WebKit

struct EditorWebView: NSViewRepresentable {
    @Environment(EditorViewModel.self) private var viewModel

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .nonPersistent()
        let contentController = WKUserContentController()
        let assetSchemeHandler = DocumentAssetSchemeHandler()
        assetSchemeHandler.viewModel = viewModel
        context.coordinator.assetSchemeHandler = assetSchemeHandler

        let bridge = EditorBridge()
        bridge.viewModel = viewModel
        context.coordinator.bridge = bridge

        contentController.add(bridge, name: "editorBridge")
        config.userContentController = contentController
        config.setURLSchemeHandler(assetSchemeHandler, forURLScheme: DocumentAssetReference.scheme)
        config.preferences.isTextInteractionEnabled = true

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.underPageBackgroundColor = .clear
        webView.navigationDelegate = context.coordinator
        TextCheckingSettings.shared.bind(webView: webView)

        // Load the editor HTML
        let resourceBundle = Bundle.shakespeareResources
        let bundleRootURL = resourceBundle.bundleURL
        if let htmlURL = resourceBundle.url(forResource: "editor", withExtension: "html") {
            // Grant read access only to the sealed application resource bundle.
            webView.loadFileURL(htmlURL, allowingReadAccessTo: bundleRootURL)
        }

        // Prepare the system-font theme CSS for later injection on editorReady.
        let _ = FontManager.shared.fontFaceCSS(bundle: .shakespeareResources)

        viewModel.webView = webView
        return webView
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {
        // Inject theme CSS each time the editor signals ready (handles initial load + process restart)
        if viewModel.isEditorReady && context.coordinator.lastThemeReadyCount != viewModel.editorReadyCount {
            context.coordinator.lastThemeReadyCount = viewModel.editorReadyCount
            let appearance = UserDefaults.standard.string(forKey: "editorAppearance") ?? "system"
            let themeCSS = FontManager.shared.themedCSS(for: appearance)
            viewModel.setThemeCSS(themeCSS)
            let fontManager = FontManager.shared
            viewModel.setDefaultTypography(
                fontFamily: fontManager.currentFont,
                fontSize: fontManager.currentSize,
                lineHeight: fontManager.currentLineHeight
            )
            viewModel.applyCurrentZoomToWebView()
            TextCheckingSettings.shared.editorDidBecomeReady()
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    class Coordinator: NSObject, WKNavigationDelegate {
        var bridge: EditorBridge?
        var assetSchemeHandler: DocumentAssetSchemeHandler?
        var lastThemeReadyCount = 0

        /// Called when the WKWebView web content process crashes or is terminated by the OS
        /// (e.g. due to memory pressure). Without this handler the editor goes permanently blank.
        func webView(_ webView: WKWebView, webContentProcessDidTerminate: WKWebView) {
            print("EditorWebView: web content process terminated — reloading editor")
            // Mark editor as not ready so pending content buffering kicks in
            Task { @MainActor in
                bridge?.viewModel?.isEditorReady = false
            }
            // Reload the editor HTML to recover
            let resourceBundle = Bundle.shakespeareResources
            if let htmlURL = resourceBundle.url(forResource: "editor", withExtension: "html") {
                webView.loadFileURL(htmlURL, allowingReadAccessTo: resourceBundle.bundleURL)
            }
        }
    }
}
