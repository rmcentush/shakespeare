import Foundation

@main
struct GapFillEvals {
    static func main() throws {
        try acceptsBoundedPlainProse()
        rejectsMetaOrRecursiveGapOutput()
        enforcesSchemaBounds()
        print("Gap-fill evals passed (3 cases: valid prose, unsafe output rejection, compact contract).")
    }

    private static func acceptsBoundedPlainProse() throws {
        let response = try GapFillContract.decode("""
        {"text":"That constraint changes the result, but not the underlying argument."}
        """)
        require(response.text.hasPrefix("That constraint"), "valid prose was rejected")
    }

    private static func rejectsMetaOrRecursiveGapOutput() {
        for response in [
            #"{"text":"[[try again]]"}"#,
            #"{"text":"```Here is the fill```"}"#,
            #"{"text":""}"#,
        ] {
            do {
                _ = try GapFillContract.decode(response)
                fatalError("Gap-fill eval failed: unsafe output was accepted")
            } catch GapFillContract.ContractError.invalidResponse {
                // Expected.
            } catch {
                fatalError("Gap-fill eval failed with the wrong error: \(error)")
            }
        }
    }

    private static func enforcesSchemaBounds() {
        require(
            GapFillContract.systemPrompt.contains("both sides of the gap"),
            "surrounding-flow instruction disappeared"
        )
        require(
            GapFillContract.systemPrompt.contains("Do not invent"),
            "anti-fabrication instruction disappeared"
        )
        let schema = GapFillContract.outputSchema()
        let properties = schema["properties"] as? [String: Any]
        let text = properties?["text"] as? [String: Any]
        require(text?["maxLength"] as? Int == 4_000, "fill text escaped its cap")
        require(properties?["style_notes"] == nil, "model-authored style rationale remains in the contract")
        require(schema["additionalProperties"] as? Bool == false, "schema permits extra fields")
    }

    private static func require(_ condition: @autoclosure () -> Bool, _ message: String) {
        guard condition() else { fatalError("Gap-fill eval failed: \(message)") }
    }
}
