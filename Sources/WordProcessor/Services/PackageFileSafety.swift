import Foundation

enum PackageFileSafetyError: LocalizedError, Equatable {
    case notRegularFile(String)
    case fileTooLarge(filename: String, maximumBytes: Int)
    case invalidUTF8(String)
    case unsupportedSchemaVersion(found: Int, supported: Int)

    var errorDescription: String? {
        switch self {
        case .notRegularFile(let filename):
            return "The document package contains an invalid file (\(filename))."
        case .fileTooLarge(let filename, let maximumBytes):
            let megabytes = max(1, maximumBytes / (1024 * 1024))
            return "\(filename) must be \(megabytes) MB or smaller."
        case .invalidUTF8(let filename):
            return "The document package contains unreadable text (\(filename))."
        case .unsupportedSchemaVersion(let found, let supported):
            return "This document uses format version \(found); this version of Shakespeare supports version \(supported)."
        }
    }
}

enum PackageFileSafety {
    static func readData(
        from url: URL,
        maximumBytes: Int,
        displayName: String? = nil
    ) throws -> Data {
        let filename = displayName ?? url.lastPathComponent
        guard maximumBytes >= 0 else {
            throw PackageFileSafetyError.fileTooLarge(
                filename: filename,
                maximumBytes: maximumBytes
            )
        }

        let values = try url.resourceValues(
            forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey]
        )
        guard values.isRegularFile == true, values.isSymbolicLink != true else {
            throw PackageFileSafetyError.notRegularFile(filename)
        }
        if let fileSize = values.fileSize, fileSize > maximumBytes {
            throw PackageFileSafetyError.fileTooLarge(
                filename: filename,
                maximumBytes: maximumBytes
            )
        }

        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        let data = try handle.read(upToCount: maximumBytes + 1) ?? Data()
        guard data.count <= maximumBytes else {
            throw PackageFileSafetyError.fileTooLarge(
                filename: filename,
                maximumBytes: maximumBytes
            )
        }
        return data
    }

    static func readUTF8String(
        from url: URL,
        maximumBytes: Int,
        displayName: String? = nil
    ) throws -> String {
        let filename = displayName ?? url.lastPathComponent
        let data = try readData(
            from: url,
            maximumBytes: maximumBytes,
            displayName: filename
        )
        guard let string = String(data: data, encoding: .utf8) else {
            throw PackageFileSafetyError.invalidUTF8(filename)
        }
        return string
    }

    static func validateSchemaVersion(_ found: Int, supported: Int) throws {
        guard found == supported else {
            throw PackageFileSafetyError.unsupportedSchemaVersion(
                found: found,
                supported: supported
            )
        }
    }
}
