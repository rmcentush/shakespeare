import Foundation
import UniformTypeIdentifiers
import WebKit

final class DocumentAssetSchemeHandler: NSObject, WKURLSchemeHandler {
    weak var viewModel: EditorViewModel?

    func webView(_ webView: WKWebView, start urlSchemeTask: WKURLSchemeTask) {
        guard let requestURL = urlSchemeTask.request.url,
              let filename = DocumentAssetReference.filename(from: requestURL.absoluteString),
              let documentURL = viewModel?.assetBaseURL
        else {
            urlSchemeTask.didFailWithError(CocoaError(.fileNoSuchFile))
            return
        }

        let didAccess = documentURL.startAccessingSecurityScopedResource()
        defer {
            if didAccess {
                documentURL.stopAccessingSecurityScopedResource()
            }
        }

        let assetURL = documentURL
            .appendingPathComponent(DocumentAssetReference.assetsDirectoryName, isDirectory: true)
            .appendingPathComponent(filename)

        do {
            let data = try Data(contentsOf: assetURL, options: .mappedIfSafe)
            let mimeType = UTType(filenameExtension: assetURL.pathExtension)?.preferredMIMEType ?? "application/octet-stream"
            let response = URLResponse(
                url: requestURL,
                mimeType: mimeType,
                expectedContentLength: data.count,
                textEncodingName: nil
            )
            urlSchemeTask.didReceive(response)
            urlSchemeTask.didReceive(data)
            urlSchemeTask.didFinish()
        } catch {
            urlSchemeTask.didFailWithError(error)
        }
    }

    func webView(_ webView: WKWebView, stop urlSchemeTask: WKURLSchemeTask) {}
}
