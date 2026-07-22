import Foundation

enum WritingSampleImporter {
    static let maximumFiles = 20
    static let maximumFileBytes = 400_000

    struct Result: Equatable, Sendable {
        let imported: Int
        let duplicates: Int
        let rejected: Int
        let limitReached: Int

        var isFailure: Bool { imported == 0 && (rejected > 0 || limitReached > 0) }

        var message: String {
            var parts: [String] = []
            if imported > 0 {
                parts.append("Imported \(imported) sample\(imported == 1 ? "" : "s")")
            }
            if duplicates > 0 {
                parts.append("ignored \(duplicates) duplicate\(duplicates == 1 ? "" : "s")")
            }
            if rejected > 0 {
                parts.append(
                    "skipped \(rejected) unsupported, short, or unstructured file"
                        + (rejected == 1 ? "" : "s")
                )
            }
            if limitReached > 0 {
                parts.append("skipped \(limitReached) because the 50-sample library is full")
            }
            return parts.isEmpty ? "No samples selected." : parts.joined(separator: "; ") + "."
        }
    }

    static func importFiles(_ urls: [URL]) -> Result {
        var imported = 0
        var duplicates = 0
        var rejected = max(urls.count - maximumFiles, 0)
        var limitReached = 0

        for url in urls.prefix(maximumFiles) {
            let accessed = url.startAccessingSecurityScopedResource()
            defer {
                if accessed { url.stopAccessingSecurityScopedResource() }
            }
            do {
                let text = try PackageFileSafety.readUTF8String(
                    from: url,
                    maximumBytes: maximumFileBytes
                )
                switch try TrainingEventStore.shared.appendWritingSample(text) {
                case .imported:
                    imported += 1
                case .duplicate:
                    duplicates += 1
                case .sampleLimitReached:
                    limitReached += 1
                case .learningDisabled, .tooShort, .tooLong, .insufficientStructure:
                    rejected += 1
                }
            } catch {
                rejected += 1
            }
        }

        return Result(
            imported: imported,
            duplicates: duplicates,
            rejected: rejected,
            limitReached: limitReached
        )
    }
}
