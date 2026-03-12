import SwiftUI

struct FindBarView: View {
    @Environment(EditorViewModel.self) private var editorViewModel
    @Binding var isVisible: Bool
    @Binding var showReplace: Bool
    @State private var searchText = ""
    @State private var replaceText = ""
    @State private var matchCount = 0
    @State private var currentMatch = -1

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
                }
                .buttonStyle(.plain)
                .disabled(matchCount == 0)

                Button(action: findNext) {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 11, weight: .medium))
                }
                .buttonStyle(.plain)
                .disabled(matchCount == 0)

                Button {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        showReplace.toggle()
                    }
                } label: {
                    Image(systemName: "arrow.2.squarepath")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(showReplace ? .accentColor : .secondary)
                }
                .buttonStyle(.plain)
                .help("Toggle Replace")

                Button {
                    close()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
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
                        .onSubmit { replaceOne() }

                    Button("Replace") { replaceOne() }
                        .buttonStyle(.plain)
                        .font(.system(size: 12))
                        .disabled(matchCount == 0)

                    Button("All") { replaceAll() }
                        .buttonStyle(.plain)
                        .font(.system(size: 12))
                        .disabled(matchCount == 0)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.bar)
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
    }
}
