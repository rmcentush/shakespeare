import Darwin
import Foundation

@main
struct DocumentAssetEvals {
    static func main() throws {
        var failures: [String] = []

        expectRoundTrip(&failures)
        expectUnsafeURLsRejected(&failures)
        expectReferencesExtracted(&failures)
        try expectContainedFiles(&failures)

        if failures.isEmpty {
            print("Document asset evals passed (4 groups).")
            return
        }

        print("Document asset evals failed:")
        for failure in failures {
            print("- \(failure)")
        }
        exit(1)
    }

    private static func expectReferencesExtracted(_ failures: inout [String]) {
        let first = DocumentAssetReference.urlString(for: "cover image.png")
        let second = DocumentAssetReference.urlString(for: "café.jpg")
        let html = #"<p><img src="\#(first)"><img src="\#(second)"><img src="\#(first)"></p>"#
        let filenames = DocumentAssetReference.filenames(in: html)
        if filenames != Set(["cover image.png", "café.jpg"]) {
            failures.append("expected unique document asset references to be extracted from HTML")
        }
    }

    private static func expectRoundTrip(_ failures: inout [String]) {
        let filenames = [
            "cover image.png",
            "draft-2.webp",
            "café.jpg",
            "question?.png",
            "hash#.png",
        ]
        for filename in filenames {
            let source = DocumentAssetReference.urlString(for: filename)
            if DocumentAssetReference.filename(from: source) != filename {
                failures.append("expected \(filename) to round-trip through an asset URL")
            }
        }
    }

    private static func expectUnsafeURLsRejected(_ failures: inout [String]) {
        let unsafeSources = [
            "shakespeare-document://asset/../secret.png",
            "shakespeare-document://asset/%2E%2E%2Fsecret.png",
            "shakespeare-document://asset/%2Fsecret.png",
            "shakespeare-document://asset/folder/secret.png",
            "shakespeare-document://asset/%5Csecret.png",
        ]

        for source in unsafeSources where DocumentAssetReference.filename(from: source) != nil {
            failures.append("expected unsafe asset URL to be rejected: \(source)")
        }
    }

    private static func expectContainedFiles(_ failures: inout [String]) throws {
        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory
            .appendingPathComponent("shakespeare-asset-evals-\(UUID().uuidString)", isDirectory: true)
        let assets = root.appendingPathComponent("assets", isDirectory: true)
        let outside = root.appendingPathComponent("outside", isDirectory: true)
        defer { try? fileManager.removeItem(at: root) }

        try fileManager.createDirectory(at: assets, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: outside, withIntermediateDirectories: true)

        let image = assets.appendingPathComponent("image.png")
        try Data([0x89, 0x50, 0x4E, 0x47]).write(to: image)
        if DocumentAssetReference.containedFileURL(named: "image.png", in: assets) != image {
            failures.append("expected a direct asset child to be accepted")
        }

        let secret = outside.appendingPathComponent("secret.png")
        try Data([0x00]).write(to: secret)
        let link = assets.appendingPathComponent("linked.png")
        try fileManager.createSymbolicLink(at: link, withDestinationURL: secret)
        if DocumentAssetReference.containedFileURL(named: "linked.png", in: assets) != nil {
            failures.append("expected a symlink escaping the asset directory to be rejected")
        }
    }
}
