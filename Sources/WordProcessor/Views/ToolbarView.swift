import SwiftUI
import UniformTypeIdentifiers

struct ToolbarView: View {
    @Environment(EditorViewModel.self) private var viewModel
    @State private var fontManager = FontManager.shared

    var body: some View {
        HStack(spacing: 2) {
            // Font picker
            Picker("", selection: Binding(
                get: { fontManager.currentFont },
                set: { newFont in
                    fontManager.currentFont = newFont
                    persistTypographySettings()
                }
            )) {
                Text("Lyon Text").tag("Lyon Text")
                Text("Source Serif 4").tag("Source Serif 4")
                Text("Scala").tag("Scala")
                Text("Charter").tag("Charter")
                Text("Georgia").tag("Georgia")
                Text("Palatino").tag("Palatino")
                Text("Baskerville").tag("Baskerville")
                Text("Helvetica Neue").tag("Helvetica Neue")
            }
            .frame(width: 140)

            Picker("", selection: Binding(
                get: { Int(fontManager.currentSize.rounded()) },
                set: { newSize in
                    fontManager.currentSize = Double(newSize)
                    persistTypographySettings()
                }
            )) {
                ForEach(Array(12...28), id: \.self) { size in
                    Text("\(size) px").tag(size)
                }
            }
            .frame(width: 78)
            .help("Font Size")

            Divider()
                .frame(height: 20)
                .padding(.horizontal, 4)

            // Text formatting
            Group {
                FormatButton(icon: "bold", isActive: viewModel.selectionState.isBold) {
                    viewModel.applyFormat("bold")
                }
                FormatButton(icon: "italic", isActive: viewModel.selectionState.isItalic) {
                    viewModel.applyFormat("italic")
                }
                FormatButton(icon: "underline", isActive: viewModel.selectionState.isUnderline) {
                    viewModel.applyFormat("underline")
                }
                FormatButton(icon: "strikethrough", isActive: false) {
                    viewModel.applyFormat("strike")
                }
                LinkButton()
                RedTextButton()
            }

            Divider()
                .frame(height: 20)
                .padding(.horizontal, 4)

            // Headings
            Group {
                HeadingButton(level: 1, currentHeading: viewModel.selectionState.heading) {
                    viewModel.applyFormat("heading", value: "1")
                }
                HeadingButton(level: 2, currentHeading: viewModel.selectionState.heading) {
                    viewModel.applyFormat("heading", value: "2")
                }
                HeadingButton(level: 3, currentHeading: viewModel.selectionState.heading) {
                    viewModel.applyFormat("heading", value: "3")
                }
            }

            Divider()
                .frame(height: 20)
                .padding(.horizontal, 4)

            // Lists
            Group {
                FormatButton(icon: "list.bullet", isActive: false) {
                    viewModel.applyFormat("bulletList")
                }
                FormatButton(icon: "list.number", isActive: false) {
                    viewModel.applyFormat("orderedList")
                }
                FormatButton(icon: "text.quote", isActive: false) {
                    viewModel.applyFormat("blockquote")
                }
            }

            // Insert image
            FormatButton(icon: "photo", isActive: false) {
                insertImage()
            }

            Divider()
                .frame(height: 20)
                .padding(.horizontal, 4)

            // Alignment
            Group {
                AlignButton(alignment: "left", current: viewModel.selectionState.textAlign) {
                    viewModel.applyFormat("alignLeft")
                }
                AlignButton(alignment: "center", current: viewModel.selectionState.textAlign) {
                    viewModel.applyFormat("alignCenter")
                }
                AlignButton(alignment: "right", current: viewModel.selectionState.textAlign) {
                    viewModel.applyFormat("alignRight")
                }
                AlignButton(alignment: "justify", current: viewModel.selectionState.textAlign) {
                    viewModel.applyFormat("alignJustify")
                }
            }

            Spacer()

            // Focus mode
            FocusModeButton()

            Divider()
                .frame(height: 20)
                .padding(.horizontal, 4)

            // Light/Dark mode toggle
            AppearanceToggle()
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(.bar)
    }

    private func insertImage() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [UTType.image]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            guard let imageData = try? Data(contentsOf: url) else { return }

            let mimeType: String
            switch url.pathExtension.lowercased() {
            case "png": mimeType = "image/png"
            case "gif": mimeType = "image/gif"
            case "webp": mimeType = "image/webp"
            default: mimeType = "image/jpeg"
            }

            let base64 = imageData.base64EncodedString()
            let dataURL = "data:\(mimeType);base64,\(base64)"
            viewModel.applyFormat("insertImage", value: dataURL)
        }
    }

    private func persistTypographySettings() {
        fontManager.save()
        NotificationCenter.default.post(name: .fontSettingsChanged, object: nil)
    }
}

struct AppearanceToggle: View {
    @Environment(EditorViewModel.self) private var viewModel
    @AppStorage("editorAppearance") private var appearance: String = "system"

    var body: some View {
        Picker("", selection: Binding(
            get: { appearance },
            set: { newValue in
                appearance = newValue
                applyAppearance(newValue)
            }
        )) {
            Image(systemName: "circle.lefthalf.filled").tag("system")
            Image(systemName: "sun.max").tag("light")
            Image(systemName: "moon").tag("dark")
        }
        .pickerStyle(.segmented)
        .frame(width: 100)
        .onAppear {
            applyAppearance(appearance)
        }
    }

    private func applyAppearance(_ mode: String) {
        switch mode {
        case "light":
            NSApp.appearance = NSAppearance(named: .aqua)
            viewModel.setThemeCSS(FontManager.shared.themedCSS(for: mode))
        case "dark":
            NSApp.appearance = NSAppearance(named: .darkAqua)
            viewModel.setThemeCSS(FontManager.shared.themedCSS(for: mode))
        default:
            NSApp.appearance = nil
            viewModel.setThemeCSS(FontManager.shared.themedCSS(for: mode))
        }
    }
}

struct FormatButton: View {
    let icon: String
    let isActive: Bool
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .frame(width: 28, height: 28)
                .background(
                    isActive ? Color.accentColor.opacity(0.2) :
                    isHovered ? Color.primary.opacity(0.08) : Color.clear
                )
                .cornerRadius(4)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovered = hovering
        }
    }
}

struct HeadingButton: View {
    let level: Int
    let currentHeading: Int
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Text("H\(level)")
                .font(.system(size: 12, weight: .bold))
                .frame(width: 28, height: 28)
                .background(
                    currentHeading == level ? Color.accentColor.opacity(0.2) :
                    isHovered ? Color.primary.opacity(0.08) : Color.clear
                )
                .cornerRadius(4)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovered = hovering
        }
    }
}

struct AlignButton: View {
    let alignment: String
    let current: String
    let action: () -> Void
    @State private var isHovered = false

    private var iconName: String {
        switch alignment {
        case "center": return "text.aligncenter"
        case "right": return "text.alignright"
        case "justify": return "text.justify"
        default: return "text.alignleft"
        }
    }

    var body: some View {
        Button(action: action) {
            Image(systemName: iconName)
                .frame(width: 28, height: 28)
                .background(
                    current == alignment ? Color.accentColor.opacity(0.2) :
                    isHovered ? Color.primary.opacity(0.08) : Color.clear
                )
                .cornerRadius(4)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovered = hovering
        }
    }
}

struct RedTextButton: View {
    @Environment(EditorViewModel.self) private var viewModel
    @State private var isHovered = false

    private var isActive: Bool {
        let c = viewModel.selectionState.textColor.lowercased()
        return !c.isEmpty && (
            c.contains("red") ||
            c == "#ff0000" ||
            c == "#e53e3e" ||
            c.contains("229, 62, 62") ||
            c.contains("255, 0, 0")
        )
    }

    var body: some View {
        Button {
            viewModel.applyFormat("toggleColor", value: "#e53e3e")
        } label: {
            ZStack {
                Text("A")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(Color(red: 0.9, green: 0.24, blue: 0.24))
            }
            .frame(width: 28, height: 28)
            .background(
                isActive ? Color.red.opacity(0.15) :
                isHovered ? Color.primary.opacity(0.08) : Color.clear
            )
            .cornerRadius(4)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovered = hovering
        }
        .help("Red Text — mark for later")
    }
}

struct LinkButton: View {
    @Environment(EditorViewModel.self) private var viewModel
    @State private var showPopover = false
    @State private var linkURL = ""
    @State private var isHovered = false

    var body: some View {
        Button {
            if viewModel.selectionState.isLink {
                viewModel.applyFormat("unlink")
            } else {
                linkURL = ""
                showPopover = true
            }
        } label: {
            Image(systemName: "link")
                .frame(width: 28, height: 28)
                .background(
                    viewModel.selectionState.isLink ? Color.accentColor.opacity(0.2) :
                    isHovered ? Color.primary.opacity(0.08) : Color.clear
                )
                .cornerRadius(4)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovered = hovering
        }
        .help("Insert Link (Cmd+K)")
        .popover(isPresented: $showPopover, arrowEdge: .bottom) {
            VStack(spacing: 8) {
                Text("Insert Link")
                    .font(.headline)
                TextField("https://", text: $linkURL)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 260)
                    .onSubmit { applyLink() }
                HStack {
                    Button("Cancel") {
                        showPopover = false
                    }
                    Spacer()
                    Button("Apply") {
                        applyLink()
                    }
                    .keyboardShortcut(.defaultAction)
                    .disabled(linkURL.isEmpty)
                }
            }
            .padding()
        }
    }

    private func applyLink() {
        guard !linkURL.isEmpty else { return }
        var url = linkURL
        if !url.contains("://") {
            url = "https://" + url
        }
        viewModel.applyFormat("setLink", value: url)
        showPopover = false
    }
}

struct FocusModeButton: View {
    @State private var isHovered = false

    var body: some View {
        Button {
            NotificationCenter.default.post(name: .toggleFocusMode, object: nil)
        } label: {
            Image(systemName: "eye")
                .frame(width: 28, height: 28)
                .background(isHovered ? Color.primary.opacity(0.08) : Color.clear)
                .cornerRadius(4)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovered = hovering
        }
        .help("Focus Mode (Cmd+Shift+F)")
    }
}
