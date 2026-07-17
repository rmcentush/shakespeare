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
        try validateNode(root, isRoot: true, depth: 0, nodeCount: &nodeCount)
    }

    private static func validateNode(
        _ node: [String: Any],
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

        if let attrs = node["attrs"], !(attrs is [String: Any]) {
            throw CanonicalDocumentValidationError.malformedNode
        }

        if type == "text" {
            guard node["text"] is String, node["content"] == nil else {
                throw CanonicalDocumentValidationError.malformedNode
            }
        } else if node["text"] != nil {
            throw CanonicalDocumentValidationError.malformedNode
        }

        if let marks = node["marks"] {
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
            }
        }

        if let content = node["content"] {
            guard let children = content as? [Any] else {
                throw CanonicalDocumentValidationError.malformedNode
            }
            for child in children {
                guard let child = child as? [String: Any] else {
                    throw CanonicalDocumentValidationError.malformedNode
                }
                try validateNode(
                    child,
                    depth: depth + 1,
                    nodeCount: &nodeCount
                )
            }
        }
    }
}
