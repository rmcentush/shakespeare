import Foundation

/// Keeps web access confined to the explicit research route. The server tool
/// still decides whether a particular research turn needs a search; local
/// phrase classification must not silently downgrade a source-backed request.
enum ChatSearchPolicy {
    static func requiresWebSearch(for query: String, whenAllowed: Bool = true) -> Bool {
        whenAllowed && !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
