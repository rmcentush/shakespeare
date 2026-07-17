import Darwin
import Foundation

@main
struct DocumentPackageSafetyEvals {
    static func main() throws {
        let fileManager = FileManager.default
        let directory = fileManager.temporaryDirectory
            .appendingPathComponent("shakespeare-package-safety-\(UUID().uuidString)")
        defer { try? fileManager.removeItem(at: directory) }
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)

        let textURL = directory.appendingPathComponent("content.json")
        try "{\"type\":\"doc\"}".write(to: textURL, atomically: true, encoding: .utf8)
        let text = try PackageFileSafety.readUTF8String(from: textURL, maximumBytes: 64)
        require(text.contains("doc"), "valid bounded UTF-8 was rejected")

        do {
            _ = try PackageFileSafety.readData(from: textURL, maximumBytes: 4)
            fail("oversized content was accepted")
        } catch PackageFileSafetyError.fileTooLarge {
            // Expected.
        }

        let linkURL = directory.appendingPathComponent("linked.json")
        try fileManager.createSymbolicLink(at: linkURL, withDestinationURL: textURL)
        do {
            _ = try PackageFileSafety.readData(from: linkURL, maximumBytes: 64)
            fail("symbolic-link package member was accepted")
        } catch PackageFileSafetyError.notRegularFile {
            // Expected.
        }

        let invalidUTF8URL = directory.appendingPathComponent("invalid.txt")
        try Data([0xff, 0xfe]).write(to: invalidUTF8URL)
        do {
            _ = try PackageFileSafety.readUTF8String(from: invalidUTF8URL, maximumBytes: 64)
            fail("invalid UTF-8 was accepted")
        } catch PackageFileSafetyError.invalidUTF8 {
            // Expected.
        }

        try PackageFileSafety.validateSchemaVersion(1, supported: 1)
        do {
            try PackageFileSafety.validateSchemaVersion(2, supported: 1)
            fail("unsupported schema version was accepted")
        } catch PackageFileSafetyError.unsupportedSchemaVersion {
            // Expected.
        }

        print("Document package safety evals passed (bounds, file type, UTF-8, schema).")
    }

    private static func require(_ condition: @autoclosure () -> Bool, _ message: String) {
        guard condition() else { fail(message) }
    }

    private static func fail(_ message: String) -> Never {
        print("Document package safety eval failed: \(message)")
        exit(1)
    }
}
