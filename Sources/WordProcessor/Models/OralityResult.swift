import Foundation

struct OralityResult {
    let score: Int
    let docScore: Double
    let oralCount: Int
    let literateCount: Int
    let sentences: [SentenceAnalysis]

    var interpretation: String {
        switch Double(score) / 100.0 {
        case 0.9...: return "Highly oral — epic poetry, spoken word"
        case 0.7..<0.9: return "Oral — speeches, sermons, podcasts"
        case 0.4..<0.7: return "Mixed — essays, blogs, casual writing"
        case 0.1..<0.4: return "Literate — journalism, technical writing"
        default: return "Highly literate — academic, legal"
        }
    }

    struct SentenceAnalysis: Identifiable {
        let id = UUID()
        let text: String
        let category: String          // "oral" or "literate"
        let categoryConfidence: Double
        let primaryMarker: String
        let markers: [Marker]

        var markerConfidenceSum: Double {
            markers.reduce(0) { $0 + $1.confidence }
        }
    }

    struct Marker {
        let name: String
        let confidence: Double
    }

    // MARK: - Marker Descriptions

    /// Human-readable description for each Havelock marker explaining what it detects
    /// and why it matters for oral vs. literate style.
    static let markerDescriptions: [String: String] = [
        // ── Literate markers (push toward written/academic register) ──
        "abstract_noun":
            "Uses abstract nouns instead of concrete, tangible language.",
        "additive_formal":
            "Uses a formal connective (moreover, furthermore) that sounds essay-like rather than spoken.",
        "agent_demoted":
            "Downplays who is doing the action, making the sentence less direct.",
        "agentless_passive":
            "Uses passive voice without naming the doer, hiding the speaker or actor.",
        "categorical_statement":
            "Makes absolute claims that sound more like a textbook than conversation.",
        "causal_chain":
            "Links causes and effects in a formal, analytical sequence.",
        "causal_explicit":
            "Uses explicit causal connectors (therefore, consequently) that sound academic.",
        "citation":
            "References sources or authorities in a scholarly way.",
        "concessive":
            "Uses a formal concession structure (although, despite) that reads as written.",
        "concessive_connector":
            "Uses a contrastive connector that can make the line sound more formal.",
        "conditional":
            "Uses if/then structures that read as analytical or overly hedged.",
        "contrastive":
            "Sets up formal contrasts (on the one hand / on the other) in an essayistic way.",
        "cross_reference":
            "References other parts of a text, signaling a document rather than speech.",
        "definitional_move":
            "Defines terms in a textbook-like manner.",
        "enumeration":
            "Lists items in a formal, numbered or lettered structure.",
        "epistemic_hedge":
            "Hedges certainty with qualifiers (perhaps, it seems) in a cautious, academic tone.",
        "evidential":
            "Signals findings or evidence in a detached, report-like way.",
        "footnote_reference":
            "References footnotes or endnotes, a purely written convention.",
        "institutional_subject":
            "Centers abstract systems or institutions as the subject rather than a person.",
        "list_structure":
            "Organizes ideas in a list format typical of written text.",
        "metadiscourse":
            "Comments on the text itself (\"In this section we will…\"), a written habit.",
        "methodological_framing":
            "Frames ideas in terms of method or research approach.",
        "nested_clauses":
            "Stacks subordinate clauses, making the sentence complex and hard to say aloud.",
        "nominalization":
            "Turns verbs into abstract nouns (investigate → investigation), making prose dense.",
        "objectifying_stance":
            "Takes a detached, impersonal tone that distances the speaker from the subject.",
        "probability":
            "Expresses likelihood in a statistical or formal way.",
        "qualified_assertion":
            "Qualifies claims heavily, making the sentence cautious and academic.",
        "relative_chain":
            "Chains relative clauses (which… that… who…), making the sentence dense and written.",
        "technical_abbreviation":
            "Uses abbreviations or acronyms that belong to specialized discourse.",
        "technical_term":
            "Uses specialized or academic wording instead of everyday speech.",
        "temporal_embedding":
            "Embeds time references in complex grammatical structures.",
        "third_person_reference":
            "Keeps the sentence at a distance instead of sounding directly addressed.",

        // ── Oral markers (push toward spoken/natural register) ──
        "alliteration":
            "Repeats initial sounds for rhythm and memorability, a spoken technique.",
        "anaphora":
            "Repeats a word or phrase at the start of successive clauses for emphasis.",
        "antithesis":
            "Sets up a balanced opposition for rhetorical punch.",
        "aside":
            "Inserts a parenthetical thought, like a speaker thinking aloud.",
        "assonance":
            "Repeats vowel sounds for a musical, spoken quality.",
        "asyndeton":
            "Drops conjunctions between items for a punchy, rapid feel.",
        "audience_response":
            "Anticipates or calls for the audience's reaction.",
        "conceptual_metaphor":
            "Uses a metaphor grounded in everyday physical experience.",
        "conflict_frame":
            "Frames the idea as a struggle or tension, typical of storytelling.",
        "discourse_formula":
            "Uses a familiar spoken formula or set phrase.",
        "dramatic_pause":
            "Creates a rhetorical pause or break for emphasis.",
        "embodied_action":
            "Describes physical, bodily action that grounds the sentence in lived experience.",
        "epistrophe":
            "Repeats a word or phrase at the end of successive clauses for emphasis.",
        "epithet":
            "Uses a vivid descriptive label for a person or thing.",
        "everyday_example":
            "Illustrates a point with a familiar, concrete example.",
        "imperative":
            "Uses a direct command or instruction, speaking to the reader.",
        "inclusive_we":
            "Uses \"we\" to create shared identity with the audience.",
        "intensifier_doubling":
            "Doubles up intensifiers for emphasis (very very, so so), a spoken habit.",
        "lexical_repetition":
            "Repeats key words for emphasis, a natural spoken pattern.",
        "named_individual":
            "Names a specific person, grounding the sentence in a real story.",
        "parallelism":
            "Uses parallel grammatical structures for rhythm and clarity.",
        "phatic_check":
            "Checks in with the audience (\"you know?\", \"right?\").",
        "phatic_filler":
            "Uses filler words or phrases that mimic natural speech rhythm.",
        "polysyndeton":
            "Repeats conjunctions (and… and… and…) for a flowing, spoken rhythm.",
        "proverb":
            "Uses a proverb, saying, or folk wisdom.",
        "refrain":
            "Repeats a phrase like a refrain for rhythmic emphasis.",
        "religious_formula":
            "Uses a religious or liturgical phrase or cadence.",
        "rhetorical_question":
            "Asks a question for effect rather than answer, engaging the listener.",
        "rhyme":
            "Uses rhyming words for memorability and spoken appeal.",
        "rhythm":
            "Has a strong rhythmic or cadence pattern characteristic of speech.",
        "second_person":
            "Addresses the reader directly as \"you\".",
        "self_correction":
            "Corrects or revises mid-sentence, like a speaker thinking aloud.",
        "sensory_detail":
            "Uses vivid sensory language (sight, sound, touch) that grounds the sentence.",
        "simple_conjunction":
            "Uses simple connectors (and, but, so) like natural speech.",
        "specific_place":
            "Names a specific location, grounding the sentence concretely.",
        "temporal_anchor":
            "Anchors the sentence in a specific moment (\"Last Tuesday…\").",
        "tricolon":
            "Uses a set of three parallel elements for rhetorical punch.",
        "us_them":
            "Draws a group boundary (us vs. them), creating shared identity.",
        "vocative":
            "Directly addresses someone by name or title.",
    ]

    /// Returns the description for a marker, or a generic fallback.
    static func descriptionForMarker(_ name: String) -> String {
        markerDescriptions[name]
            ?? "This marker is one of Havelock's cues for how spoken or literate the sentence sounds."
    }
}
