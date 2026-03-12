import WebKit

final class EditorBridge: NSObject, WKScriptMessageHandler {
    weak var viewModel: EditorViewModel?

    func userContentController(
        _ userContentController: WKUserContentController,
        didReceive message: WKScriptMessage
    ) {
        guard let jsonString = message.body as? String,
              let data = jsonString.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = json["type"] as? String,
              let payload = json["payload"] as? [String: Any]
        else {
            print("EditorBridge: dropped malformed message — body type: \(Swift.type(of: message.body))")
            return
        }

        let parsed = BridgePayload.parse(type: type, payload: payload)

        Task { @MainActor in
            viewModel?.handleBridgeMessage(type: type, payload: parsed)
        }
    }
}
