import WebKit

final class EditorBridge: NSObject, WKScriptMessageHandler {
    weak var viewModel: EditorViewModel?

    func userContentController(
        _ userContentController: WKUserContentController,
        didReceive message: WKScriptMessage
    ) {
        let json: [String: Any]?
        if let nativeMessage = message.body as? [String: Any] {
            json = nativeMessage
        } else if let jsonString = message.body as? String,
                  let data = jsonString.data(using: .utf8) {
            json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        } else {
            json = nil
        }

        guard let json,
              let type = json["type"] as? String
        else {
            print("EditorBridge: dropped malformed message — body type: \(Swift.type(of: message.body))")
            return
        }

        let payload = json["payload"] as? [String: Any] ?? [:]

        let parsed = BridgePayload.parse(type: type, payload: payload)

        Task { @MainActor in
            viewModel?.handleBridgeMessage(type: type, payload: parsed)
        }
    }
}
