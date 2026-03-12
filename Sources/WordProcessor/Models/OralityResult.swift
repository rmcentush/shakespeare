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
    }

    struct Marker {
        let name: String
        let confidence: Double
    }
}
