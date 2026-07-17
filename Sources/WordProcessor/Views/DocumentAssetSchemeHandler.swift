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

        guard let assetsDirectory = DocumentAssetReference.containedFileURL(
            named: DocumentAssetReference.assetsDirectoryName,
            in: documentURL
        ), let assetURL = DocumentAssetReference.containedFileURL(
            named: filename,
            in: assetsDirectory
        ) else {
            urlSchemeTask.didFailWithError(CocoaError(.fileReadNoPermission))
            return
        }

        do {
            let data = try PackageFileSafety.readData(
                from: assetURL,
                maximumBytes: DocumentFileStore.maximumImportedImageBytes,
                displayName: filename
            )
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
