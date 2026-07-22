import SwiftUI

struct FindBarView: View {
    private enum Field {
        case search
        case replace
    }

    @Environment(EditorViewModel.self) private var editorViewModel
    @Binding var isVisible: Bool
    @Binding var showReplace: Bool
    let focusRequest: Int
    @State private var searchText = ""
    @State private var replaceText = ""
    @State private var matchCount = 0
    @State private var currentMatch = -1
    @FocusState private var focusedField: Field?

    var body: some View {
        VStack(spacing: 6) {
            // Find row
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                    .font(.system(size: 12))

                TextField("Find", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                    .padding(.horizontal, 8)
                    .frame(minWidth: 180, idealWidth: 240, maxWidth: 300, minHeight: 26)
                    .background(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(Color(nsColor: .textBackgroundColor))
                    )
                    .overlay {
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .stroke(Color.primary.opacity(0.1), lineWidth: 1)
                    }
                    .focused($focusedField, equals: .search)
                    .onSubmit { findNext() }
                    .onChange(of: searchText) {
                        performSearch()
                    }

                if matchCount > 0 {
                    Text("\(currentMatch + 1)/\(matchCount)")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                } else if !searchText.isEmpty {
                    Text("No results")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }

                Button(action: findPrevious) {
                    Image(systemName: "chevron.up")
                        .font(.system(size: 11, weight: .medium))
                        .frame(width: 24, height: 24)
                }
                .buttonStyle(.plain)
                .disabled(matchCount == 0)
                .help("Previous Match")
                .accessibilityLabel("Previous Match")

                Button(action: findNext) {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 11, weight: .medium))
                        .frame(width: 24, height: 24)
                }
                .buttonStyle(.plain)
                .disabled(matchCount == 0)
                .help("Next Match (Return)")
                .accessibilityLabel("Next Match")

                Button {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        showReplace.toggle()
                    }
                } label: {
                    Image(systemName: "arrow.2.squarepath")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(showReplace ? .accentColor : .secondary)
                        .frame(width: 24, height: 24)
                }
                .buttonStyle(.plain)
                .help("Toggle Replace")
                .accessibilityLabel(showReplace ? "Hide Replace" : "Show Replace")

                Button {
                    close()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                        .frame(width: 24, height: 24)
                }
                .buttonStyle(.plain)
                .help("Close Find")
                .accessibilityLabel("Close Find")
            }

            // Replace row
            if showReplace {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.turn.down.right")
                        .foregroundStyle(.secondary)
                        .font(.system(size: 12))

                    TextField("Replace", text: $replaceText)
                        .textFieldStyle(.plain)
                        .font(.system(size: 13))
                        .padding(.horizontal, 8)
                        .frame(minWidth: 180, idealWidth: 240, maxWidth: 300, minHeight: 26)
                        .background(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(Color(nsColor: .textBackgroundColor))
                        )
                        .overlay {
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .stroke(Color.primary.opacity(0.1), lineWidth: 1)
                        }
                        .focused($focusedField, equals: .replace)
                        .onSubmit { replaceOne() }

                    Button("Replace") { replaceOne() }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .font(.system(size: 12))
                        .disabled(matchCount == 0)

                    Button("Replace All") { replaceAll() }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .font(.system(size: 12))
                        .disabled(matchCount == 0)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(.bar)
        .frame(maxWidth: .infinity, alignment: .leading)
        .onAppear {
            focusSearchField()
        }
        .onChange(of: focusRequest) {
            focusSearchField()
        }
    }

    private func performSearch() {
        guard !searchText.isEmpty else {
            matchCount = 0
            currentMatch = -1
            editorViewModel.clearFind()
            return
        }
        editorViewModel.findInDocument(searchText) { count in
            matchCount = count
            currentMatch = count > 0 ? 0 : -1
        }
    }

    private func findNext() {
        editorViewModel.findNext { index, total in
            currentMatch = index
            matchCount = total
        }
    }

    private func findPrevious() {
        editorViewModel.findPrevious { index, total in
            currentMatch = index
            matchCount = total
        }
    }

    private func replaceOne() {
        editorViewModel.replaceOne(replaceText) { index, total in
            currentMatch = index
            matchCount = total
        }
    }

    private func replaceAll() {
        editorViewModel.replaceAll(replaceText) { count in
            matchCount = 0
            currentMatch = -1
        }
    }

    private func close() {
        editorViewModel.clearFind()
        searchText = ""
        replaceText = ""
        matchCount = 0
        currentMatch = -1
        withAnimation(.easeInOut(duration: 0.15)) {
            isVisible = false
            showReplace = false
        }
        editorViewModel.focusEditor()
    }

    private func focusSearchField() {
        DispatchQueue.main.async {
            focusedField = .search
        }
    }
}
