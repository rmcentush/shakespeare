import Foundation
@preconcurrency import CoreML

/// Local CoreML-based orality analysis using three separate fine-tuned BERT models,
/// matching the Havelock.AI architecture exactly.
final class HavelockService: @unchecked Sendable {
    private let regressorModel: MLModel   // doc-level orality score (sigmoid output)
    private let categoryModel: MLModel    // oral vs literate (softmax probabilities)
    private let subtypeModel: MLModel     // marker subtypes (softmax probabilities)
    private let tokenizer: BertTokenizer
    private let categoryLabels: [String: Int]
    private let subtypeLabels: [String: Int]
    private let categoryIdToLabel: [Int: String]
    private let subtypeIdToLabel: [Int: String]

    // Havelock v1.3 ensemble weights
    private static let docModelWeight = 0.35
    private static let sentenceWeight = 0.65
    private static let markerThreshold: Float = 0.05

    init?() {
        guard let tokenizer = BertTokenizer() else {
            print("HavelockService: Failed to load tokenizer")
            return nil
        }
        self.tokenizer = tokenizer

        guard let baseDir = Bundle.module.url(forResource: "Resources", withExtension: nil)?
            .appendingPathComponent("Havelock") else {
            print("HavelockService: Havelock resources not found")
            return nil
        }

        let config = MLModelConfiguration()
        config.computeUnits = .cpuAndGPU

        // Load three separate CoreML models
        guard let reg = Self.loadModel(baseDir.appendingPathComponent("HavelockRegressor.mlpackage"), config: config),
              let cat = Self.loadModel(baseDir.appendingPathComponent("HavelockCategory.mlpackage"), config: config),
              let sub = Self.loadModel(baseDir.appendingPathComponent("HavelockSubtype.mlpackage"), config: config)
        else {
            print("HavelockService: Failed to load one or more CoreML models")
            return nil
        }
        self.regressorModel = reg
        self.categoryModel = cat
        self.subtypeModel = sub

        // Load labels
        guard let catLabels = Self.loadLabels(baseDir.appendingPathComponent("bert_marker_category_labels.json")),
              let subLabels = Self.loadLabels(baseDir.appendingPathComponent("bert_marker_subtype_labels.json"))
        else {
            print("HavelockService: Failed to load labels")
            return nil
        }
        self.categoryLabels = catLabels
        self.subtypeLabels = subLabels
        self.categoryIdToLabel = Dictionary(uniqueKeysWithValues: catLabels.map { ($0.value, $0.key) })
        self.subtypeIdToLabel = Dictionary(uniqueKeysWithValues: subLabels.map { ($0.value, $0.key) })
    }

    // MARK: - Public API

    func analyzeOrality(text: String) throws -> OralityResult {
        let sentences = splitSentences(text)
        guard !sentences.isEmpty else {
            return OralityResult(score: 0, docScore: 0, oralCount: 0, literateCount: 0, sentences: [])
        }

        // Analyze each sentence with category + subtype models
        var sentenceResults: [OralityResult.SentenceAnalysis] = []
        var oralCount = 0
        var literateCount = 0
        var oralWeighted = 0.0
        var literateWeighted = 0.0

        for sentence in sentences {
            let trimmed = sentence.trimmingCharacters(in: .whitespacesAndNewlines)
            let wordCount = trimmed.split(separator: " ").count
            guard !trimmed.isEmpty, wordCount >= 3, wordCount <= 150 else { continue }

            let tokens = tokenizer.tokenize(trimmed)
            let input = try makeInput(tokens)

            // Category classification (uses its own fine-tuned BERT)
            let catOutput = try categoryModel.prediction(from: input)
            guard let catProbs = catOutput.featureValue(for: "probabilities")?.multiArrayValue else {
                throw HavelockError.inferenceFailure
            }
            let catProbArray = readFloatArray(catProbs)
            let predIdx = catProbArray.enumerated().max(by: { $0.element < $1.element })?.offset ?? 0
            let confidence = Double(catProbArray[predIdx])
            let category = categoryIdToLabel[predIdx] ?? "unknown"

            if category == "oral" {
                oralCount += 1
                oralWeighted += confidence
            } else {
                literateCount += 1
                literateWeighted += confidence
            }

            // Subtype classification (uses its own fine-tuned BERT)
            let subOutput = try subtypeModel.prediction(from: input)
            guard let subProbs = subOutput.featureValue(for: "probabilities")?.multiArrayValue else {
                throw HavelockError.inferenceFailure
            }
            let subProbArray = readFloatArray(subProbs)

            // Top markers above threshold
            let sorted = subProbArray.enumerated().sorted { $0.element > $1.element }
            var markers: [OralityResult.Marker] = []
            for (idx, conf) in sorted.prefix(3) {
                if conf >= Self.markerThreshold || markers.isEmpty {
                    if let name = subtypeIdToLabel[idx] {
                        markers.append(OralityResult.Marker(name: name, confidence: Double(conf)))
                    }
                }
            }
            // Always at least the top marker
            if markers.isEmpty, let top = sorted.first, let name = subtypeIdToLabel[top.offset] {
                markers.append(OralityResult.Marker(name: name, confidence: Double(top.element)))
            }

            sentenceResults.append(OralityResult.SentenceAnalysis(
                text: trimmed,
                category: category,
                categoryConfidence: confidence,
                primaryMarker: markers.first?.name ?? "",
                markers: markers
            ))
        }

        // Document-level score using regressor model (its own fine-tuned BERT)
        let docTokens = tokenizer.tokenize(text)
        let docInput = try makeInput(docTokens)
        let docOutput = try regressorModel.prediction(from: docInput)
        guard let scoreValue = docOutput.featureValue(for: "score") else {
            throw HavelockError.inferenceFailure
        }
        let docScore = scoreValue.doubleValue

        // Confidence-weighted ensemble scoring (Havelock v1.3)
        let totalWeighted = oralWeighted + literateWeighted
        let sentenceRatio = totalWeighted > 0 ? oralWeighted / totalWeighted : 0.5
        let ensembleScore = Self.docModelWeight * docScore + Self.sentenceWeight * sentenceRatio
        let score = Int(round(ensembleScore * 100))

        return OralityResult(
            score: score,
            docScore: docScore,
            oralCount: oralCount,
            literateCount: literateCount,
            sentences: sentenceResults
        )
    }

    // MARK: - Inference Helpers

    private func makeInput(_ tokens: BertTokenizer.TokenizedInput) throws -> MLDictionaryFeatureProvider {
        let seqLen = tokens.inputIds.count

        let idsArray = try MLMultiArray(shape: [1, NSNumber(value: seqLen)], dataType: .int32)
        let maskArray = try MLMultiArray(shape: [1, NSNumber(value: seqLen)], dataType: .int32)

        let idsPtr = idsArray.dataPointer.bindMemory(to: Int32.self, capacity: seqLen)
        let maskPtr = maskArray.dataPointer.bindMemory(to: Int32.self, capacity: seqLen)
        for i in 0..<seqLen {
            idsPtr[i] = tokens.inputIds[i]
            maskPtr[i] = tokens.attentionMask[i]
        }

        return try MLDictionaryFeatureProvider(dictionary: [
            "input_ids": MLFeatureValue(multiArray: idsArray),
            "attention_mask": MLFeatureValue(multiArray: maskArray),
        ])
    }

    private func readFloatArray(_ array: MLMultiArray) -> [Float] {
        let count = array.count
        switch array.dataType {
        case .float32:
            let ptr = array.dataPointer.bindMemory(to: Float.self, capacity: count)
            return Array(UnsafeBufferPointer(start: ptr, count: count))
        default:
            // Safe fallback
            return (0..<count).map { array[$0].floatValue }
        }
    }

    // MARK: - Helpers

    private func splitSentences(_ text: String) -> [String] {
        var sentences: [String] = []
        text.enumerateSubstrings(in: text.startIndex..., options: [.bySentences, .localized]) { substring, _, _, _ in
            if let s = substring {
                let trimmed = s.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    sentences.append(trimmed)
                }
            }
        }
        return sentences
    }

    // MARK: - Loading

    private static func loadModel(_ url: URL, config: MLModelConfiguration) -> MLModel? {
        // Try cache first
        let cacheDir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
            .appendingPathComponent("com.shakespeare.havelock")
        let cachedName = url.deletingPathExtension().lastPathComponent + ".mlmodelc"
        let cachedURL = cacheDir.appendingPathComponent(cachedName)
        let fm = FileManager.default

        if fm.fileExists(atPath: cachedURL.path),
           let model = try? MLModel(contentsOf: cachedURL, configuration: config) {
            return model
        }

        // Compile and cache
        try? fm.removeItem(at: cachedURL)
        guard let compiled = try? MLModel.compileModel(at: url) else { return nil }
        try? fm.createDirectory(at: cacheDir, withIntermediateDirectories: true)
        try? fm.copyItem(at: compiled, to: cachedURL)
        return try? MLModel(contentsOf: compiled, configuration: config)
    }

    private static func loadLabels(_ url: URL) -> [String: Int]? {
        guard let data = try? Data(contentsOf: url),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Int]
        else { return nil }
        return json
    }

    enum HavelockError: LocalizedError {
        case inferenceFailure

        var errorDescription: String? {
            switch self {
            case .inferenceFailure: return "Failed to run Havelock model inference"
            }
        }
    }
}
