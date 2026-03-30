import SwiftUI

struct OralityView: View {
    let requestID: Int

    @State private var oralityViewModel = OralityViewModel()
    @State private var suggestionViewModel = OralitySuggestionViewModel()
    @Environment(EditorViewModel.self) private var editorViewModel
    @Environment(DocumentModel.self) private var document

    var body: some View {
        VStack(spacing: 0) {
            content

            Button {
                checkOrality()
            } label: {
                Label("Check Orality", systemImage: "waveform.path")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(oralityViewModel.isLoading)
            .padding()
        }
        .frame(maxHeight: .infinity)
        .task(id: requestID) {
            guard requestID > 0 else { return }
            checkOrality()
        }
    }

    @ViewBuilder
    private var content: some View {
        if let result = oralityViewModel.result {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    summaryCard(result)

                    if oralityViewModel.literateSentences.isEmpty {
                        successCard
                    } else {
                        revisionTargetsSection
                    }

                    allSentencesSection(result.sentences)
                }
                .padding(.vertical, 16)
            }
        } else if oralityViewModel.isLoading {
            Spacer()
            VStack(spacing: 8) {
                ProgressView()
                Text("Analyzing orality...")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        } else {
            Spacer()
            VStack(spacing: 12) {
                Image(systemName: "waveform.path")
                    .font(.largeTitle)
                    .foregroundStyle(.secondary)
                Text("Open the orality sidebar with the toolbar A button, then analyze the selection or the full document.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)

                if let error = oralityViewModel.error {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .padding(.horizontal)
                }
            }
            Spacer()
        }
    }

    private func summaryCard(_ result: OralityResult) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(oralityViewModel.analysisScope.title) Orality")
                        .font(.headline)
                    Text(oralityViewModel.analysisScope.detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Text(result.interpretation)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.trailing)
            }

            HStack(spacing: 16) {
                ZStack {
                    Circle()
                        .stroke(Color.gray.opacity(0.18), lineWidth: 8)
                    Circle()
                        .trim(from: 0, to: Double(result.score) / 100.0)
                        .stroke(scoreColor(Double(result.score)), style: StrokeStyle(lineWidth: 8, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    VStack(spacing: 2) {
                        Text("\(result.score)")
                            .font(.system(size: 32, weight: .bold))
                        Text("/ 100")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(width: 104, height: 104)

                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 16) {
                        StatLabel(label: "Oral", value: "\(result.oralCount)", color: .green)
                        StatLabel(label: "Literate", value: "\(result.literateCount)", color: .red)
                    }

                    if !oralityViewModel.literateSentences.isEmpty {
                        Text("Havelock exposes sentence-level diagnostics. Paragraph targets below are grouped locally from that sentence output.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
        .padding()
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .padding(.horizontal)
    }

    private var successCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("No Immediate Rewrites Needed")
                .font(.headline)
            Text("Everything Havelock flagged in this scope already reads as oral. Re-run on a different selection if you want to inspect a specific paragraph.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding()
        .background(Color.green.opacity(0.08), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .padding(.horizontal)
    }

    private var revisionTargetsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Revision Targets")
                .font(.headline)
                .padding(.horizontal)

            ForEach(oralityViewModel.literateParagraphs) { paragraph in
                paragraphCard(paragraph)
                    .padding(.horizontal)
            }
        }
    }

    private func paragraphCard(_ paragraph: OralityParagraphAnalysis) -> some View {
        let paragraphState = suggestionViewModel.paragraphState(for: paragraph.id)

        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Paragraph \(paragraph.index)")
                        .font(.subheadline.bold())
                    Text("\(paragraph.literateSentences.count) literate sentence\(paragraph.literateSentences.count == 1 ? "" : "s")")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    Task {
                        await suggestionViewModel.suggestParagraphRewrite(paragraph)
                    }
                } label: {
                    Label("Suggest Paragraph Rewrite", systemImage: "sparkles")
                }
                .buttonStyle(.bordered)
                .disabled(paragraphState.isLoading)
            }

            Text(paragraph.text)
                .font(.caption)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)

            suggestionBox(
                title: "Paragraph Suggestion",
                state: paragraphState,
                onQueue: {
                    queueParagraphSuggestion(paragraphState.suggestionText, for: paragraph)
                },
                onDiscard: {
                    suggestionViewModel.clearParagraphSuggestion(for: paragraph.id)
                }
            )

            ForEach(paragraph.literateSentences) { sentence in
                Divider()
                sentenceCard(sentence, paragraph: paragraph)
            }
        }
        .padding()
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func sentenceCard(
        _ sentence: OralityResult.SentenceAnalysis,
        paragraph: OralityParagraphAnalysis
    ) -> some View {
        let sentenceState = suggestionViewModel.sentenceState(for: sentence.id)

        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 8) {
                Text("LITERATE")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.red)
                    .cornerRadius(4)

                Text(sentence.text)
                    .font(.subheadline)
                    .textSelection(.enabled)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Why Havelock flagged this")
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)

                if topMarkers(for: sentence).isEmpty {
                    Text("The API did not return marker details for this sentence.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(topMarkers(for: sentence), id: \.name) { marker in
                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(markerTitle(marker.name)) \(Int(marker.confidence * 100))%")
                                .font(.caption.bold())
                            Text(markerDescription(marker.name))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            HStack {
                Button {
                    Task {
                        await suggestionViewModel.suggestSentenceRewrite(
                            sentence: sentence,
                            paragraphText: paragraph.text
                        )
                    }
                } label: {
                    Label("Suggest Sentence Rewrite", systemImage: "sparkles")
                }
                .buttonStyle(.bordered)
                .disabled(sentenceState.isLoading)

                Spacer()

                Text("Confidence \(Int(sentence.categoryConfidence * 100))%")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            suggestionBox(
                title: "Sentence Suggestion",
                state: sentenceState,
                onQueue: {
                    queueSentenceSuggestion(sentenceState.suggestionText, for: sentence)
                },
                onDiscard: {
                    suggestionViewModel.clearSentenceSuggestion(for: sentence.id)
                }
            )
        }
    }

    private func allSentencesSection(_ sentences: [OralityResult.SentenceAnalysis]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Sentence Analysis")
                .font(.headline)
                .padding(.horizontal)

            ForEach(sentences) { sentence in
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .top, spacing: 8) {
                        Text(sentence.category.uppercased())
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(sentence.category == "oral" ? Color.green : Color.red)
                            .cornerRadius(4)

                        Text(sentence.text)
                            .font(.caption)
                            .textSelection(.enabled)
                    }

                    HStack(spacing: 4) {
                        ForEach(topMarkers(for: sentence), id: \.name) { marker in
                            Text("\(markerTitle(marker.name)) \(Int(marker.confidence * 100))%")
                                .font(.system(size: 10))
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.secondary.opacity(0.1))
                                .cornerRadius(4)
                        }
                    }
                    .padding(.leading, 52)
                }
                .padding(.horizontal)
            }
        }
        .padding(.bottom, 8)
    }

    @ViewBuilder
    private func suggestionBox(
        title: String,
        state: OralitySuggestionState,
        onQueue: @escaping () -> Void,
        onDiscard: @escaping () -> Void
    ) -> some View {
        if state.isLoading || !state.suggestionText.isEmpty || state.error != nil || state.status != nil {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(title)
                        .font(.caption.bold())
                        .foregroundStyle(.secondary)

                    Spacer()

                    if state.isLoading {
                        ProgressView()
                            .controlSize(.small)
                    }
                }

                if !state.suggestionText.isEmpty {
                    Text(state.suggestionText)
                        .font(.caption)
                        .textSelection(.enabled)
                        .padding(8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color(nsColor: .windowBackgroundColor), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                }

                if !state.isLoading && !state.suggestionText.isEmpty {
                    HStack(spacing: 10) {
                        Button("Queue Pending Edit") {
                            onQueue()
                        }
                        .buttonStyle(.borderedProminent)

                        Button("Discard") {
                            onDiscard()
                        }
                        .buttonStyle(.bordered)
                    }
                }

                if let status = state.status {
                    Text(status)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if let error = state.error {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
        }
    }

    private func checkOrality() {
        suggestionViewModel = OralitySuggestionViewModel()

        editorViewModel.getSelectedText { text in
            let normalizedSelection = normalizeText(text)
            if !normalizedSelection.isEmpty {
                Task {
                    await oralityViewModel.checkOrality(
                        text: normalizedSelection,
                        scope: .selection
                    )
                }
            } else {
                editorViewModel.getPlainText { plainText in
                    let normalizedDocument = normalizeText(plainText)
                    guard !normalizedDocument.isEmpty else { return }

                    Task {
                        await oralityViewModel.checkOrality(
                            text: normalizedDocument,
                            scope: .document
                        )
                    }
                }
            }
        }
    }

    private func queueSentenceSuggestion(
        _ suggestionText: String,
        for sentence: OralityResult.SentenceAnalysis
    ) {
        queueSuggestion(targetText: sentence.text, replacementText: suggestionText) { status, error in
            suggestionViewModel.setSentenceStatus(status, error: error, for: sentence.id)
        }
    }

    private func queueParagraphSuggestion(
        _ suggestionText: String,
        for paragraph: OralityParagraphAnalysis
    ) {
        queueSuggestion(targetText: paragraph.text, replacementText: suggestionText) { status, error in
            suggestionViewModel.setParagraphStatus(status, error: error, for: paragraph.id)
        }
    }

    private func queueSuggestion(
        targetText: String,
        replacementText: String,
        completion: @escaping (String?, String?) -> Void
    ) {
        let normalizedTarget = normalizeText(targetText)
        let normalizedReplacement = normalizeText(replacementText)

        guard !normalizedTarget.isEmpty, !normalizedReplacement.isEmpty else {
            completion(nil, "No suggestion is available to queue yet.")
            return
        }

        let editID = "orality_\(UUID().uuidString)"
        let replacementHTML = escapeHTML(normalizedReplacement)

        editorViewModel.getSelectedText { selectedText in
            let normalizedSelection = normalizeText(selectedText)

            if !normalizedSelection.isEmpty && normalizedSelection == normalizedTarget {
                editorViewModel.pendingReplaceSelection(id: editID, html: replacementHTML) { count in
                    finishQueueAction(count: count, completion: completion)
                }
                return
            }

            let resolveOccurrences: (String) -> Void = { plainText in
                let occurrenceCount = countOccurrences(of: normalizedTarget, in: plainText)
                guard occurrenceCount == 1 else {
                    let error = occurrenceCount == 0
                        ? "The original text no longer matches the document. Re-run the orality analysis."
                        : "This text appears multiple times. Select the exact sentence or paragraph, then queue the suggestion again."

                    DispatchQueue.main.async {
                        completion(nil, error)
                    }
                    return
                }

                editorViewModel.pendingFindAndReplace(
                    id: editID,
                    find: normalizedTarget,
                    replaceHTML: replacementHTML,
                    replaceAll: false
                ) { count in
                    finishQueueAction(count: count, completion: completion)
                }
            }

            if editorViewModel.isEditorReady {
                editorViewModel.getPlainText { plainText in
                    resolveOccurrences(plainText)
                }
            } else {
                resolveOccurrences(document.plainTextContent)
            }
        }
    }

    private func finishQueueAction(
        count: Int,
        completion: @escaping (String?, String?) -> Void
    ) {
        let status: String?
        let error: String?

        if count > 0 {
            status = "Queued as a pending edit. Review it in the document and accept or reject it there."
            error = nil
        } else if count == -2 {
            status = nil
            error = "Too many pending edits are already queued. Review or reject them before adding more."
        } else {
            status = nil
            error = "Unable to queue the edit. Re-run the orality analysis and try again."
        }

        DispatchQueue.main.async {
            completion(status, error)
        }
    }

    private func topMarkers(for sentence: OralityResult.SentenceAnalysis) -> [OralityResult.Marker] {
        if !sentence.markers.isEmpty {
            return Array(sentence.markers.prefix(3))
        }

        guard !sentence.primaryMarker.isEmpty else { return [] }
        return [
            OralityResult.Marker(
                name: sentence.primaryMarker,
                confidence: sentence.categoryConfidence
            )
        ]
    }

    private func scoreColor(_ score: Double) -> Color {
        if score >= 70 { return .green }
        if score >= 40 { return .orange }
        return .red
    }

    private func markerTitle(_ marker: String) -> String {
        marker
            .replacingOccurrences(of: "_", with: " ")
            .capitalized
    }

    private func markerDescription(_ marker: String) -> String {
        switch marker {
        case "technical_term":
            return "Uses specialized or academic wording instead of everyday speech."
        case "institutional_subject":
            return "Centers abstract systems or institutions rather than a person speaking directly."
        case "additive_formal":
            return "Uses a formal connective that sounds more essay-like than spoken."
        case "evidential":
            return "Signals findings or evidence in a detached, report-like way."
        case "third_person_reference":
            return "Keeps the sentence at a distance instead of sounding directly addressed."
        case "concessive_connector":
            return "Uses a contrastive connector that can make the line sound more formal."
        case "discourse_formula":
            return "Uses a familiar spoken formula, which is usually a sign of oral style."
        case "inclusive_we":
            return "Uses a direct collective voice that often reads as spoken."
        default:
            return "This marker is one of Havelock's cues for how spoken or literate the sentence sounds."
        }
    }

    private func normalizeText(_ text: String) -> String {
        text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func countOccurrences(of needle: String, in haystack: String) -> Int {
        let normalizedNeedle = needle.lowercased()
        let normalizedHaystack = normalizeText(haystack).lowercased()

        guard !normalizedNeedle.isEmpty, normalizedHaystack.count >= normalizedNeedle.count else {
            return 0
        }

        var count = 0
        var searchStart = normalizedHaystack.startIndex

        while searchStart < normalizedHaystack.endIndex,
              let range = normalizedHaystack.range(
                of: normalizedNeedle,
                options: [],
                range: searchStart..<normalizedHaystack.endIndex
              ) {
            count += 1
            searchStart = range.upperBound
        }

        return count
    }

    private func escapeHTML(_ text: String) -> String {
        text
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&#39;")
    }
}

struct StatLabel: View {
    let label: String
    let value: String
    let color: Color

    var body: some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.title3.bold())
                .foregroundStyle(color)
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }
}
