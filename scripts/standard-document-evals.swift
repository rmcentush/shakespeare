import AppKit
import Foundation

// The production definition lives with the local learning ledger. Keeping this
// evaluator stub structurally identical lets document conversion compile without
// touching the writer's real personalization storage.
struct PersonalizationOutcomeSnapshot: Codable, Equatable, Sendable {
    let actionID: String
    let outcome: String
    let finalText: String
    let confidence: Double
    let trainingEligible: Bool
}

@main
private struct StandardDocumentEvals {
    @MainActor
    static func main() async throws {
        let scratchURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "shakespeare-standard-document-\(UUID().uuidString)",
                isDirectory: true
            )
        try FileManager.default.createDirectory(
            at: scratchURL,
            withIntermediateDirectories: false
        )
        defer { try? FileManager.default.removeItem(at: scratchURL) }

        let canonicalJSON = """
        {
          "type": "doc",
          "content": [
            {
              "type": "heading",
              "attrs": {"level": 1},
              "content": [{"type": "text", "text": "Compatibility"}]
            },
            {
              "type": "paragraph",
              "content": [
                {"type": "text", "text": "This is "},
                {"type": "text", "text": "bold", "marks": [{"type": "bold"}]},
                {"type": "text", "text": " and "},
                {"type": "text", "text": "italic", "marks": [{"type": "italic"}]},
                {"type": "text", "text": "."}
              ]
            },
            {
              "type": "bulletList",
              "content": [
                {
                  "type": "listItem",
                  "content": [
                    {
                      "type": "paragraph",
                      "content": [{"type": "text", "text": "First item"}]
                    }
                  ]
                },
                {
                  "type": "listItem",
                  "content": [
                    {
                      "type": "paragraph",
                      "content": [{"type": "text", "text": "Second item"}]
                    }
                  ]
                }
              ]
            },
            {
              "type": "blockquote",
              "content": [
                {
                  "type": "paragraph",
                  "content": [{"type": "text", "text": "Quoted text"}]
                }
              ]
            },
            {
              "type": "codeBlock",
              "attrs": {"language": "swift"},
              "content": [{"type": "text", "text": "let answer = 42"}]
            },
            {
              "type": "paragraph",
              "content": [{"type": "text", "text": "Unicode: 漢字 مرحباً 😀"}]
            }
          ]
        }
        """
        let html = """
        <h1>Compatibility</h1>
        <p>This is <strong>bold</strong> and <em>italic</em>.</p>
        <ul><li><p>First item</p></li><li><p>Second item</p></li></ul>
        <blockquote><p>Quoted text</p></blockquote>
        <pre><code class="language-swift">let answer = 42</code></pre>
        <p>Unicode: 漢字 مرحباً 😀</p>
        """
        let snapshot = DocumentFileStore.FileSnapshot(
            canonicalJSON: canonicalJSON,
            htmlContent: html,
            plainText: "Compatibility\nThis is bold and italic.\nFirst item\nSecond item\nQuoted text\nlet answer = 42\nUnicode: 漢字 مرحباً 😀",
            notes: "Private planning note"
        )

        for format in PortableDocumentFormat.exportFormats {
            let exportURL = scratchURL.appendingPathComponent(
                "Compatibility.\(format.filenameExtension)",
                isDirectory: format == .richTextDirectory
            )
            try await DocumentFileStore.shared.export(
                snapshot,
                as: format,
                to: exportURL,
                sourceDocumentURL: nil
            )

            let loaded = try await DocumentFileStore.shared.load(from: exportURL)
            precondition(
                loaded.plainText.contains("Compatibility"),
                "\(format.displayName) lost the document text"
            )
            precondition(
                !loaded.plainText.contains(snapshot.notes),
                "\(format.displayName) leaked private notes"
            )
            precondition(
                loaded.plainText.contains("漢字"),
                "\(format.displayName) lost CJK text"
            )
            precondition(
                loaded.plainText.contains("مرحباً"),
                "\(format.displayName) lost Arabic text"
            )
            precondition(
                loaded.plainText.contains("😀"),
                "\(format.displayName) lost emoji text"
            )
            precondition(loaded.notes.isEmpty, "\(format.displayName) imported notes")
        }

        let markdownURL = scratchURL.appendingPathComponent("Compatibility.md")
        let markdown = try String(contentsOf: markdownURL, encoding: .utf8)
        precondition(markdown.contains("# Compatibility"))
        precondition(markdown.contains("**bold**"))
        precondition(markdown.contains("*italic*"))
        precondition(markdown.contains("- First item"))
        precondition(markdown.contains("> Quoted text"))
        precondition(markdown.contains("```swift"))
        precondition(!markdown.contains(snapshot.notes))

        let plainTextURL = scratchURL.appendingPathComponent("Compatibility.txt")
        let plainText = try String(contentsOf: plainTextURL, encoding: .utf8)
        precondition(plainText == snapshot.plainText)

        let htmlURL = scratchURL.appendingPathComponent("Compatibility.html")
        let exportedHTML = try String(contentsOf: htmlURL, encoding: .utf8)
        precondition(exportedHTML.contains("<strong>bold</strong>"))
        precondition(!exportedHTML.contains(snapshot.notes))

        let rtfdURL = scratchURL.appendingPathComponent(
            "Compatibility.rtfd",
            isDirectory: true
        )
        let rtfdValues = try rtfdURL.resourceValues(forKeys: [.isDirectoryKey])
        precondition(rtfdValues.isDirectory == true, "RTFD export was not a package")

        let importedDocument = DocumentModel()
        let importedWordURL = scratchURL.appendingPathComponent("Compatibility.docx")
        let originalWordData = try Data(contentsOf: importedWordURL)
        let importedWord = try await DocumentFileStore.shared.load(from: importedWordURL)
        precondition(importedWord.htmlContent.contains("<b>bold</b>"))
        precondition(importedWord.htmlContent.contains("<i>italic</i>"))
        importedDocument.importDocument(
            snapshot: importedWord,
            suggestedName: "Compatibility",
            sourceURL: importedWordURL
        )
        precondition(importedDocument.fileURL == nil, "an import retained the source as its save target")
        precondition(importedDocument.isDirty, "an import was not marked for native saving")
        precondition(importedDocument.displayName == "Compatibility")
        let unchangedWordData = try Data(contentsOf: importedWordURL)
        precondition(
            unchangedWordData == originalWordData,
            "importing changed the source document"
        )

        let importedMarkdown = try await DocumentFileStore.shared.load(from: markdownURL)
        precondition(importedMarkdown.htmlContent.contains("<h1>Compatibility</h1>"))
        precondition(importedMarkdown.htmlContent.contains("<strong>bold</strong>"))
        precondition(importedMarkdown.htmlContent.contains("<ul>"))
        precondition(importedMarkdown.htmlContent.contains("<blockquote>"))
        precondition(importedMarkdown.htmlContent.contains("<pre><code"))

        var forgedArchive = originalWordData
        let centralHeader = Data([0x50, 0x4b, 0x01, 0x02])
        guard let centralRange = forgedArchive.range(of: centralHeader) else {
            preconditionFailure("Word export did not contain a ZIP central directory")
        }
        let expandedSizeOffset = centralRange.lowerBound + 24
        forgedArchive.replaceSubrange(
            expandedSizeOffset..<(expandedSizeOffset + 4),
            with: [0xff, 0xff, 0xff, 0x7f]
        )
        let forgedWordURL = scratchURL.appendingPathComponent("Forged.docx")
        try forgedArchive.write(to: forgedWordURL, options: .atomic)
        do {
            _ = try await DocumentFileStore.shared.load(from: forgedWordURL)
            preconditionFailure("a forged archive expansion size was accepted")
        } catch StandardDocumentCodecError.invalidDocument {
            // Expected: compressed standard documents are bounded before parsing.
        }

        let imageWordData = archiveByRenamingCentralEntry(
            in: originalWordData,
            toPathWithPrefix: "word/media/"
        )
        let imageWordURL = scratchURL.appendingPathComponent("Image-bearing.docx")
        try imageWordData.write(to: imageWordURL, options: .atomic)
        do {
            _ = try await DocumentFileStore.shared.load(from: imageWordURL)
            preconditionFailure("a Word import silently discarded embedded media")
        } catch StandardDocumentCodecError.embeddedImagesUnsupportedForImport {
            // Expected: AppKit drops Word attachments, so reject before conversion.
        }

        let openDocumentURL = scratchURL.appendingPathComponent("Compatibility.odt")
        let originalOpenDocumentData = try Data(contentsOf: openDocumentURL)
        let imageOpenDocumentData = archiveByRenamingCentralEntry(
            in: originalOpenDocumentData,
            toPathWithPrefix: "Pictures/"
        )
        let imageOpenDocumentURL = scratchURL.appendingPathComponent("Image-bearing.odt")
        try imageOpenDocumentData.write(to: imageOpenDocumentURL, options: .atomic)
        do {
            _ = try await DocumentFileStore.shared.load(from: imageOpenDocumentURL)
            preconditionFailure("an OpenDocument import silently discarded embedded media")
        } catch StandardDocumentCodecError.embeddedImagesUnsupportedForImport {
            // Expected: AppKit drops OpenDocument attachments.
        }
        precondition(
            StandardDocumentCodec.archiveEntryContainsEmbeddedImage(
                "CustomAssets/illustration.png",
                format: .word
            ),
            "Word image detection missed a nonstandard package location"
        )
        precondition(
            StandardDocumentCodec.archiveEntryContainsEmbeddedImage(
                "Assets/illustration.svg",
                format: .openDocument
            ),
            "OpenDocument image detection missed a nonstandard package location"
        )
        precondition(
            !StandardDocumentCodec.archiveEntryContainsEmbeddedImage(
                "word/document.xml",
                format: .word
            ),
            "Word image detection rejected ordinary document XML"
        )

        let richTextWithImageURL = scratchURL.appendingPathComponent("Image-bearing.rtf")
        try #"{\rtf1\ansi{\pict\pngblip 89504e470d0a1a0a}}"#.write(
            to: richTextWithImageURL,
            atomically: true,
            encoding: .utf8
        )
        do {
            _ = try await DocumentFileStore.shared.load(from: richTextWithImageURL)
            preconditionFailure("an RTF import silently discarded embedded media")
        } catch StandardDocumentCodecError.embeddedImagesUnsupportedForImport {
            // Expected: reject RTF picture groups before conversion.
        }

        let legacyWordURL = scratchURL.appendingPathComponent("Compatibility.doc")
        var legacyWordWithImage = try Data(contentsOf: legacyWordURL)
        legacyWordWithImage.append(contentsOf: [
            0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a,
        ])
        let imageLegacyWordURL = scratchURL.appendingPathComponent("Image-bearing.doc")
        try legacyWordWithImage.write(to: imageLegacyWordURL, options: .atomic)
        do {
            _ = try await DocumentFileStore.shared.load(from: imageLegacyWordURL)
            preconditionFailure("a legacy Word import silently discarded embedded media")
        } catch StandardDocumentCodecError.embeddedImagesUnsupportedForImport {
            // Expected: reject recognizable embedded raster payloads.
        }
        precondition(
            !StandardDocumentCodec.containsEmbeddedImagePayload(
                Data("A harmless BM sequence".utf8),
                format: .legacyWord
            ),
            "legacy Word image detection rejected ordinary text"
        )

        let imageDataURL = "data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVQIHWP4z8DwHwAFgAI/ScL1WQAAAABJRU5ErkJggg=="
        let imageHTMLURL = scratchURL.appendingPathComponent("Picture.html")
        try """
        <p>Picture</p>
        <img src="\(imageDataURL)" alt="One pixel">
        """.write(to: imageHTMLURL, atomically: true, encoding: .utf8)

        let importedImage = try await DocumentFileStore.shared.load(from: imageHTMLURL)
        precondition(
            importedImage.htmlContent.contains("shakespeare-document://asset/"),
            "an imported image was not localized"
        )
        let importedImageBaseURL = try await DocumentFileStore.shared.assetBaseURL(
            for: importedImage,
            sourceURL: imageHTMLURL
        )
        precondition(importedImageBaseURL != nil, "localized images have no asset base")

        let portableImageHTMLURL = scratchURL.appendingPathComponent("Picture-export.html")
        try await DocumentFileStore.shared.export(
            importedImage,
            as: .html,
            to: portableImageHTMLURL,
            sourceDocumentURL: importedImageBaseURL
        )
        let portableImageHTML = try String(
            contentsOf: portableImageHTMLURL,
            encoding: .utf8
        )
        precondition(
            portableImageHTML.contains("data:image/png;base64,"),
            "HTML export did not make its image portable"
        )

        let imageRTFDURL = scratchURL.appendingPathComponent("Picture.rtfd", isDirectory: true)
        try await DocumentFileStore.shared.export(
            importedImage,
            as: .richTextDirectory,
            to: imageRTFDURL,
            sourceDocumentURL: importedImageBaseURL
        )
        let reimportedImageRTFD = try await DocumentFileStore.shared.load(from: imageRTFDURL)
        precondition(
            reimportedImageRTFD.htmlContent.contains("shakespeare-document://asset/"),
            "RTFD did not round-trip its image"
        )

        do {
            try await DocumentFileStore.shared.export(
                importedImage,
                as: .word,
                to: scratchURL.appendingPathComponent("Picture.docx"),
                sourceDocumentURL: importedImageBaseURL
            )
            preconditionFailure("Word export silently discarded an embedded image")
        } catch StandardDocumentCodecError.embeddedImagesUnsupported {
            // Expected: AppKit's Word writer drops attachments, so fail closed.
        }

        print(
            "Standard-document evals passed "
                + "(Word, OpenDocument, RTF/RTFD, Markdown, text, HTML, notes, and images)."
        )
    }

    private static func archiveByRenamingCentralEntry(
        in data: Data,
        toPathWithPrefix prefix: String
    ) -> Data {
        var result = data
        let header = Data([0x50, 0x4b, 0x01, 0x02])
        var searchStart = result.startIndex

        while searchStart < result.endIndex,
              let range = result.range(
                of: header,
                in: searchStart..<result.endIndex
              ) {
            let filenameLengthOffset = range.lowerBound + 28
            guard filenameLengthOffset + 2 <= result.endIndex else { break }
            let filenameLength = Int(result[filenameLengthOffset])
                | (Int(result[filenameLengthOffset + 1]) << 8)
            let prefixLength = prefix.utf8.count
            if filenameLength > prefixLength {
                let replacement = prefix
                    + String(repeating: "x", count: filenameLength - prefixLength)
                let filenameStart = range.lowerBound + 46
                let filenameEnd = filenameStart + filenameLength
                guard filenameEnd <= result.endIndex else { break }
                result.replaceSubrange(
                    filenameStart..<filenameEnd,
                    with: Data(replacement.utf8)
                )
                return result
            }
            searchStart = range.upperBound
        }

        preconditionFailure("the generated archive had no replaceable central entry")
    }
}
