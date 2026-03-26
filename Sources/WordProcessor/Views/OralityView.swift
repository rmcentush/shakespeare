import SwiftUI

struct OralityView: View {
    @State private var oralityViewModel = OralityViewModel()
    @State private var rewriteViewModel = OralityRewriteViewModel()
    @Environment(EditorViewModel.self) private var editorViewModel

    var body: some View {
        VStack(spacing: 0) {
            if let result = oralityViewModel.result {
                ScrollView {
                    VStack(spacing: 16) {
                        // Score gauge
                        VStack(spacing: 8) {
                            ZStack {
                                Circle()
                                    .stroke(Color.gray.opacity(0.2), lineWidth: 8)
                                Circle()
                                    .trim(from: 0, to: Double(result.score) / 100.0)
                                    .stroke(scoreColor(Double(result.score)), style: StrokeStyle(lineWidth: 8, lineCap: .round))
                                    .rotationEffect(.degrees(-90))
                                VStack(spacing: 2) {
                                    Text("\(result.score)")
                                        .font(.system(size: 36, weight: .bold))
                                    Text("/ 100")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .frame(width: 120, height: 120)

                            Text(result.interpretation)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)

                            // Summary stats
                            HStack(spacing: 16) {
                                StatLabel(label: "Oral", value: "\(result.oralCount)", color: .green)
                                StatLabel(label: "Literate", value: "\(result.literateCount)", color: .red)
                            }
                        }
                        .padding()

                        Divider()

                        // Per-sentence breakdown
                        LazyVStack(alignment: .leading, spacing: 10) {
                            Text("Sentence Analysis")
                                .font(.caption.bold())
                                .foregroundStyle(.secondary)
                                .padding(.horizontal)

                            ForEach(result.sentences) { sentence in
                                VStack(alignment: .leading, spacing: 4) {
                                    HStack(alignment: .top, spacing: 8) {
                                        // Category badge
                                        Text(sentence.category.uppercased())
                                            .font(.system(size: 9, weight: .bold))
                                            .foregroundStyle(.white)
                                            .padding(.horizontal, 6)
                                            .padding(.vertical, 2)
                                            .background(sentence.category == "oral" ? Color.green : Color.red)
                                            .cornerRadius(4)

                                        Text(sentence.text)
                                            .font(.caption)
                                    }

                                    // Markers
                                    HStack(spacing: 4) {
                                        ForEach(sentence.markers.prefix(3), id: \.name) { marker in
                                            Text("\(formatMarker(marker.name)) \(Int(marker.confidence * 100))%")
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
                        .padding(.bottom)

                        // Orality improvement with Claude
                        if result.literateCount > 0 {
                            Divider()

                            VStack(spacing: 12) {
                                if rewriteViewModel.isRewriting {
                                    VStack(spacing: 8) {
                                        ProgressView()
                                        Text("Claude is rewriting...")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)

                                        if !rewriteViewModel.rewrittenText.isEmpty {
                                            ScrollView {
                                                Text(rewriteViewModel.rewrittenText)
                                                    .font(.caption)
                                                    .textSelection(.enabled)
                                                    .padding(8)
                                                    .frame(maxWidth: .infinity, alignment: .leading)
                                            }
                                            .frame(maxHeight: 200)
                                            .background(Color(.controlBackgroundColor))
                                            .cornerRadius(8)
                                            .padding(.horizontal)
                                        }
                                    }
                                } else if !rewriteViewModel.rewrittenText.isEmpty {
                                    VStack(spacing: 8) {
                                        Text("Rewritten Text")
                                            .font(.caption.bold())
                                            .foregroundStyle(.secondary)

                                        ScrollView {
                                            Text(rewriteViewModel.rewrittenText)
                                                .font(.caption)
                                                .textSelection(.enabled)
                                                .padding(8)
                                                .frame(maxWidth: .infinity, alignment: .leading)
                                        }
                                        .frame(maxHeight: 200)
                                        .background(Color(.controlBackgroundColor))
                                        .cornerRadius(8)
                                        .padding(.horizontal)

                                        HStack(spacing: 12) {
                                            Button("Apply to Editor") {
                                                applyRewrite()
                                            }
                                            .buttonStyle(.borderedProminent)

                                            Button("Discard") {
                                                rewriteViewModel.reset()
                                            }
                                            .buttonStyle(.bordered)
                                        }
                                    }
                                } else {
                                    Button {
                                        improveOrality(result: result)
                                    } label: {
                                        Label("Improve Orality with Claude", systemImage: "sparkles")
                                            .frame(maxWidth: .infinity)
                                    }
                                    .buttonStyle(.bordered)
                                    .padding(.horizontal)
                                }

                                if let error = rewriteViewModel.error {
                                    Text(error)
                                        .font(.caption)
                                        .foregroundStyle(.red)
                                        .padding(.horizontal)
                                }
                            }
                            .padding(.vertical)
                        }
                    }
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
                    Text("Select text in the editor and click Check to analyze orality.")
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

            // Check button
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
    }

    private func checkOrality() {
        rewriteViewModel.reset()
        editorViewModel.getSelectedText { text in
            if !text.isEmpty {
                Task {
                    await oralityViewModel.checkOrality(text: text)
                }
            } else {
                editorViewModel.getPlainText { plainText in
                    guard !plainText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
                    Task {
                        await oralityViewModel.checkOrality(text: plainText)
                    }
                }
            }
        }
    }

    private func scoreColor(_ score: Double) -> Color {
        if score >= 70 { return .green }
        if score >= 40 { return .orange }
        return .red
    }

    private func formatMarker(_ marker: String) -> String {
        marker.replacingOccurrences(of: "_", with: " ")
    }

    private func improveOrality(result: OralityResult) {
        editorViewModel.getPlainText { plainText in
            guard !plainText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
            Task {
                await rewriteViewModel.rewriteForOrality(
                    fullText: plainText,
                    oralityResult: result
                )
            }
        }
    }

    private func applyRewrite() {
        let html = rewriteViewModel.rewrittenText
            .components(separatedBy: "\n\n")
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .map { "<p>\($0.trimmingCharacters(in: .whitespacesAndNewlines))</p>" }
            .joined(separator: "\n")

        editorViewModel.loadContent(html)
        rewriteViewModel.reset()
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
