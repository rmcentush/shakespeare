import Foundation

@main
struct GapFillEvals {
    static func main() throws {
        try acceptsBoundedPlainProse()
        rejectsMetaOrRecursiveGapOutput()
        enforcesStyleNotesAndSchemaBounds()
        print("Gap-fill evals passed (3 cases: valid prose, unsafe output rejection, style-note contract).")
    }

    private static func acceptsBoundedPlainProse() throws {
        let response = try GapFillContract.decode("""
        {"text":"That constraint changes the result, but not the underlying argument.","style_notes":["Uses a compact declarative transition","Ends on the consequence"]}
        """)
        require(response.text.hasPrefix("That constraint"), "valid prose was rejected")
        require(response.styleNotes.count == 2, "valid style notes were lost")
    }

    private static func rejectsMetaOrRecursiveGapOutput() {
        for response in [
            #"{"text":"[[try again]]","style_notes":["Uses a direct transition"]}"#,
            #"{"text":"```Here is the fill```","style_notes":["Uses a direct transition"]}"#,
            #"{"text":"Usable prose","style_notes":[]}"#,
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

    private static func enforcesStyleNotesAndSchemaBounds() {
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
        let notes = properties?["style_notes"] as? [String: Any]
        require(notes?["minItems"] as? Int == 1, "style-note evidence became optional")
        require(notes?["maxItems"] as? Int == 3, "style-note evidence escaped its cap")
    }

    private static func require(_ condition: @autoclosure () -> Bool, _ message: String) {
        guard condition() else { fatalError("Gap-fill eval failed: \(message)") }
    }
}
