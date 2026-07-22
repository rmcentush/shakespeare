import Foundation

enum CanonicalDocumentValidationError: LocalizedError {
    case invalidJSON
    case invalidRoot
    case unsupportedNode(String)
    case unsupportedMark(String)
    case malformedNode
    case documentTooComplex

    var errorDescription: String? {
        switch self {
        case .invalidJSON:
            return "The document contains malformed JSON."
        case .invalidRoot:
            return "The document JSON must contain a ProseMirror document root."
        case .unsupportedNode(let type):
            return "The document contains an unsupported node type (\(type))."
        case .unsupportedMark(let type):
            return "The document contains an unsupported mark type (\(type))."
        case .malformedNode:
            return "The document contains malformed ProseMirror content."
        case .documentTooComplex:
            return "The document structure is too deeply nested or complex."
        }
    }
}

enum CanonicalDocumentValidator {
    private static let maximumNodeDepth = 100
    private static let maximumNodeCount = 200_000

    private static let supportedNodeTypes: Set<String> = [
        "doc", "paragraph", "text", "blockquote", "bulletList", "orderedList",
        "listItem", "heading", "horizontalRule", "hardBreak", "codeBlock",
        "image", "footnote",
    ]

    private static let supportedMarkTypes: Set<String> = [
        "bold", "code", "italic", "strike", "underline", "link", "textStyle",
        "comment",
    ]

    static func validate(_ json: String) throws {
        guard let data = json.data(using: .utf8) else {
            throw CanonicalDocumentValidationError.invalidJSON
        }

        let object: Any
        do {
            object = try JSONSerialization.jsonObject(with: data)
        } catch {
            throw CanonicalDocumentValidationError.invalidJSON
        }

        guard let root = object as? [String: Any],
              root["type"] as? String == "doc",
              root["content"] == nil || root["content"] is [Any]
        else {
            throw CanonicalDocumentValidationError.invalidRoot
        }
        var nodeCount = 0
        try validateNode(root, parentType: nil, isRoot: true, depth: 0, nodeCount: &nodeCount)
    }

    private static func validateNode(
        _ node: [String: Any],
        parentType: String?,
        isRoot: Bool = false,
        depth: Int,
        nodeCount: inout Int
    ) throws {
        nodeCount += 1
        guard depth <= maximumNodeDepth, nodeCount <= maximumNodeCount else {
            throw CanonicalDocumentValidationError.documentTooComplex
        }

        guard let type = node["type"] as? String, !type.isEmpty else {
            throw CanonicalDocumentValidationError.malformedNode
        }
        guard supportedNodeTypes.contains(type) else {
            throw CanonicalDocumentValidationError.unsupportedNode(type)
        }
        guard !isRoot || type == "doc" else {
            throw CanonicalDocumentValidationError.invalidRoot
        }
        guard isAllowed(type: type, in: parentType) else {
            throw CanonicalDocumentValidationError.malformedNode
        }

        if let attrs = node["attrs"], !(attrs is [String: Any]) {
            throw CanonicalDocumentValidationError.malformedNode
        }
        let attrs = node["attrs"] as? [String: Any] ?? [:]
        try validateAttributes(attrs, for: type)

        if type == "text" {
            guard node["text"] is String, node["content"] == nil else {
                throw CanonicalDocumentValidationError.malformedNode
            }
        } else if node["text"] != nil {
            throw CanonicalDocumentValidationError.malformedNode
        }

        if let marks = node["marks"] {
            guard ["text", "image", "footnote", "hardBreak"].contains(type) else {
                throw CanonicalDocumentValidationError.malformedNode
            }
            guard let marks = marks as? [Any] else {
                throw CanonicalDocumentValidationError.malformedNode
            }
            for value in marks {
                guard let mark = value as? [String: Any],
                      let markType = mark["type"] as? String,
                      !markType.isEmpty,
                      mark["attrs"] == nil || mark["attrs"] is [String: Any]
                else {
                    throw CanonicalDocumentValidationError.malformedNode
                }
                guard supportedMarkTypes.contains(markType) else {
                    throw CanonicalDocumentValidationError.unsupportedMark(markType)
                }
                let markAttrs = mark["attrs"] as? [String: Any] ?? [:]
                try validatePrimitiveAttributes(markAttrs)
                if markType == "link" {
                    guard let href = markAttrs["href"] as? String,
                          href.utf8.count <= 4_096,
                          href.hasPrefix("#") || href.range(
                            of: #"^(https?://|mailto:)"#,
                            options: [.regularExpression, .caseInsensitive]
                          ) != nil
                    else {
                        throw CanonicalDocumentValidationError.malformedNode
                    }
                }
            }
        }

        if let content = node["content"] {
            guard let children = content as? [Any] else {
                throw CanonicalDocumentValidationError.malformedNode
            }
            if ["doc", "blockquote", "bulletList", "orderedList", "listItem"].contains(type),
               children.isEmpty {
                throw CanonicalDocumentValidationError.malformedNode
            }
            for child in children {
                guard let child = child as? [String: Any] else {
                    throw CanonicalDocumentValidationError.malformedNode
                }
                try validateNode(
                    child,
                    parentType: type,
                    depth: depth + 1,
                    nodeCount: &nodeCount
                )
            }
        } else if ["doc", "blockquote", "bulletList", "orderedList", "listItem"].contains(type) {
            throw CanonicalDocumentValidationError.malformedNode
        }
    }

    private static func isAllowed(type: String, in parentType: String?) -> Bool {
        switch parentType {
        case nil:
            return type == "doc"
        case "doc", "blockquote", "listItem":
            return [
                "paragraph", "blockquote", "bulletList", "orderedList", "heading",
                "horizontalRule", "codeBlock",
            ].contains(type)
        case "bulletList", "orderedList":
            return type == "listItem"
        case "paragraph", "heading":
            return ["text", "hardBreak", "image", "footnote"].contains(type)
        case "codeBlock":
            return type == "text"
        default:
            return false
        }
    }

    private static func validateAttributes(_ attrs: [String: Any], for type: String) throws {
        try validatePrimitiveAttributes(attrs)

        if type == "heading" {
            guard let level = attrs["level"] as? Int, (1...3).contains(level) else {
                throw CanonicalDocumentValidationError.malformedNode
            }
        }
        if type == "orderedList", let start = attrs["start"] {
            guard let start = start as? Int, start > 0 else {
                throw CanonicalDocumentValidationError.malformedNode
            }
        }
        if type == "image" {
            guard let source = attrs["src"] as? String, isSafeAssetSource(source) else {
                throw CanonicalDocumentValidationError.malformedNode
            }
        }
        if type == "footnote" {
            if let idValue = attrs["id"], !(idValue is String), !(idValue is NSNull) {
                throw CanonicalDocumentValidationError.malformedNode
            }
            if let id = attrs["id"] as? String,
               (id.isEmpty || id.utf8.count > 256) {
                throw CanonicalDocumentValidationError.malformedNode
            }
            if let noteValue = attrs["note"], !(noteValue is String), !(noteValue is NSNull) {
                throw CanonicalDocumentValidationError.malformedNode
            }
            if let note = attrs["note"] as? String,
               note.utf8.count > 100_000 {
                throw CanonicalDocumentValidationError.malformedNode
            }
        }
    }

    private static func validatePrimitiveAttributes(_ attrs: [String: Any]) throws {
        guard attrs.count <= 64 else {
            throw CanonicalDocumentValidationError.malformedNode
        }
        for value in attrs.values {
            guard value is String || value is NSNumber || value is NSNull else {
                throw CanonicalDocumentValidationError.malformedNode
            }
            if let string = value as? String, string.utf8.count > 1_000_000 {
                throw CanonicalDocumentValidationError.malformedNode
            }
        }
    }

    private static func isSafeAssetSource(_ source: String) -> Bool {
        guard let components = URLComponents(string: source),
              components.scheme == "shakespeare-document",
              components.host == "asset",
              components.query == nil,
              components.fragment == nil,
              components.percentEncodedPath.hasPrefix("/")
        else { return false }
        let encoded = String(components.percentEncodedPath.dropFirst())
        guard !encoded.isEmpty, !encoded.contains("/"),
              let decoded = encoded.removingPercentEncoding,
              !decoded.isEmpty,
              decoded != ".",
              decoded != "..",
              !decoded.contains("/"),
              !decoded.contains("\\"),
              !decoded.contains("\0")
        else { return false }
        return (decoded as NSString).lastPathComponent == decoded
    }
}
