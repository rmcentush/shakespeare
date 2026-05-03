import SwiftUI
import UniformTypeIdentifiers

struct ToolbarView: View {
    @Environment(EditorViewModel.self) private var viewModel
    @State private var fontManager = FontManager.shared
    private let lineHeightOptions: [Double] = Array(stride(from: 1.2, through: 2.4, by: 0.1)).map {
        Double(round($0 * 10) / 10)
    }

    var body: some View {
        ViewThatFits(in: .horizontal) {
            toolbarContent
            ScrollView(.horizontal, showsIndicators: false) {
                toolbarContent
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.bar)
    }

    private var toolbarContent: some View {
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
                Text("Gentium Plus").tag("Gentium Plus")
                Text("Source Serif 4").tag("Source Serif 4")
                Text("Scala").tag("Scala")
                Text("Charter").tag("Charter")
                Text("Signifier").tag("Signifier")
                Text("Edgar").tag("Edgar")
                Text("EBGaramond").tag("EBGaramond")
                Text("Times New Roman").tag("Times New Roman")
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

            Picker("", selection: Binding(
                get: { fontManager.currentLineHeight },
                set: { newHeight in
                    fontManager.currentLineHeight = newHeight
                    persistTypographySettings()
                }
            )) {
                ForEach(lineHeightOptions, id: \.self) { lineHeight in
                    Text(String(format: "%.1fx", lineHeight)).tag(lineHeight)
                }
            }
            .frame(width: 74)
            .help("Line Spacing")

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
                FootnoteButton()
                TextColorButton()
            }

            Divider()
                .frame(height: 20)
                .padding(.horizontal, 4)

            DocumentStylePicker(currentHeading: viewModel.selectionState.heading) { level in
                if level == 0 {
                    viewModel.applyFormat("paragraph")
                } else {
                    viewModel.applyFormat("heading", value: "\(level)")
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

            if viewModel.selectionState.isImage {
                Divider()
                    .frame(height: 20)
                    .padding(.horizontal, 4)

                ImageLayoutControls()
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

struct DocumentStylePicker: View {
    let currentHeading: Int
    let onSelect: (Int) -> Void

    var body: some View {
        Picker("", selection: Binding(
            get: { currentHeading },
            set: { newLevel in
                guard newLevel != currentHeading else { return }
                onSelect(newLevel)
            }
        )) {
            Text("Body").tag(0)
            Text("Title").tag(1)
            Text("Subtitle").tag(2)
            Text("Section head").tag(3)
        }
        .frame(width: 132)
        .help("Document Style")
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

struct ImageLayoutControls: View {
    @Environment(EditorViewModel.self) private var viewModel

    private var state: EditorViewModel.SelectionState {
        viewModel.selectionState
    }

    var body: some View {
        Group {
            FormatButton(icon: "textformat", isActive: state.imageLayout == "inline") {
                viewModel.applyFormat("setImageLayout", value: "inline")
            }
            .help("Inline Image")

            FormatButton(
                icon: "text.aligncenter",
                isActive: state.imageLayout == "block" && state.imageAlign == "center"
            ) {
                viewModel.applyFormat("setImageLayout", value: "block-center")
            }
            .help("Centered Image")

            FormatButton(icon: "text.alignleft", isActive: state.imageLayout == "float-left") {
                viewModel.applyFormat("setImageLayout", value: "float-left")
            }
            .help("Float Image Left")

            FormatButton(icon: "text.alignright", isActive: state.imageLayout == "float-right") {
                viewModel.applyFormat("setImageLayout", value: "float-right")
            }
            .help("Float Image Right")

            FormatButton(icon: "arrow.counterclockwise", isActive: false) {
                viewModel.applyFormat("resetImageCrop")
            }
            .help("Reset Image Crop")
        }
    }
}

struct TextColorButton: View {
    @Environment(EditorViewModel.self) private var viewModel
    @State private var showPopover = false
    @State private var isHovered = false

    private static let palette: [(name: String, hex: String, color: Color)] = [
        ("Black", "#000000", Color.black),
        ("Dark Gray", "#6b7280", Color(red: 0.42, green: 0.45, blue: 0.50)),
        ("Red", "#e53e3e", Color(red: 0.90, green: 0.24, blue: 0.24)),
        ("Orange", "#dd6b20", Color(red: 0.87, green: 0.42, blue: 0.13)),
        ("Yellow", "#d69e2e", Color(red: 0.84, green: 0.62, blue: 0.18)),
        ("Green", "#38a169", Color(red: 0.22, green: 0.63, blue: 0.41)),
        ("Teal", "#319795", Color(red: 0.19, green: 0.59, blue: 0.58)),
        ("Blue", "#3182ce", Color(red: 0.19, green: 0.51, blue: 0.81)),
        ("Purple", "#805ad5", Color(red: 0.50, green: 0.35, blue: 0.84)),
        ("Pink", "#d53f8c", Color(red: 0.84, green: 0.25, blue: 0.55)),
    ]

    private var activeColor: Color? {
        let c = viewModel.selectionState.textColor.lowercased()
        guard !c.isEmpty else { return nil }
        return Self.palette.first(where: { c == $0.hex })?.color
    }

    var body: some View {
        Button {
            showPopover.toggle()
        } label: {
            VStack(spacing: 1) {
                Text("A")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(activeColor ?? .primary)
                RoundedRectangle(cornerRadius: 1)
                    .fill(activeColor ?? Color.primary)
                    .frame(width: 14, height: 3)
            }
            .frame(width: 28, height: 28)
            .background(
                showPopover ? Color.accentColor.opacity(0.2) :
                isHovered ? Color.primary.opacity(0.08) : Color.clear
            )
            .cornerRadius(4)
        }
        .buttonStyle(.plain)
        .onHover { hovering in isHovered = hovering }
        .help("Text Color")
        .popover(isPresented: $showPopover, arrowEdge: .bottom) {
            VStack(spacing: 8) {
                let columns = Array(repeating: GridItem(.fixed(26), spacing: 4), count: 5)
                LazyVGrid(columns: columns, spacing: 4) {
                    ForEach(Self.palette, id: \.hex) { item in
                        ColorSwatch(
                            color: item.color,
                            hex: item.hex,
                            name: item.name,
                            isSelected: viewModel.selectionState.textColor.lowercased() == item.hex
                        ) {
                            viewModel.applyFormat("toggleColor", value: item.hex)
                            showPopover = false
                        }
                    }
                }

                Divider()

                Button {
                    viewModel.applyFormat("unsetColor")
                    showPopover = false
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "xmark.circle")
                            .font(.system(size: 11))
                        Text("Remove Color")
                            .font(.system(size: 11))
                    }
                    .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .disabled(viewModel.selectionState.textColor.isEmpty)
            }
            .padding(10)
        }
    }
}

struct ColorSwatch: View {
    let color: Color
    let hex: String
    let name: String
    let isSelected: Bool
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            RoundedRectangle(cornerRadius: 4)
                .fill(color)
                .frame(width: 24, height: 24)
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(isSelected ? Color.accentColor : (isHovered ? Color.primary.opacity(0.3) : Color.clear), lineWidth: 2)
                )
        }
        .buttonStyle(.plain)
        .onHover { hovering in isHovered = hovering }
        .help(name)
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

struct FootnoteButton: View {
    @Environment(EditorViewModel.self) private var viewModel
    @State private var showPopover = false
    @State private var noteText = ""
    @State private var isHovered = false

    private var trimmedNoteText: String {
        noteText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        Button {
            noteText = viewModel.selectionState.isFootnote ? viewModel.selectionState.footnoteText : ""
            showPopover = true
        } label: {
            Image(systemName: "textformat.superscript")
                .frame(width: 28, height: 28)
                .background(
                    viewModel.selectionState.isFootnote ? Color.accentColor.opacity(0.2) :
                    isHovered ? Color.primary.opacity(0.08) : Color.clear
                )
                .cornerRadius(4)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovered = hovering
        }
        .help(viewModel.selectionState.isFootnote ? "Edit Footnote" : "Insert Footnote")
        .popover(isPresented: $showPopover, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: 10) {
                Text(viewModel.selectionState.isFootnote ? "Edit Footnote" : "Insert Footnote")
                    .font(.headline)

                TextEditor(text: $noteText)
                    .font(.body)
                    .frame(width: 280, height: 120)
                    .padding(6)
                    .background(Color.primary.opacity(0.04))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.primary.opacity(0.12), lineWidth: 1)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 8))

                HStack {
                    if viewModel.selectionState.isFootnote {
                        Button("Remove", role: .destructive) {
                            viewModel.applyFormat("removeFootnote")
                            showPopover = false
                        }
                    }

                    Spacer()

                    Button("Cancel") {
                        showPopover = false
                    }

                    Button("Apply") {
                        applyFootnote()
                    }
                    .keyboardShortcut(.defaultAction)
                    .disabled(trimmedNoteText.isEmpty)
                }
            }
            .padding()
        }
    }

    private func applyFootnote() {
        guard !trimmedNoteText.isEmpty else { return }
        viewModel.applyFormat("setFootnote", value: trimmedNoteText)
        showPopover = false
    }
}

struct FocusModeButton: View {
    @Environment(EditorViewModel.self) private var viewModel
    @State private var isHovered = false

    var body: some View {
        Button {
            NotificationCenter.default.post(name: .toggleFocusMode, object: viewModel)
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
